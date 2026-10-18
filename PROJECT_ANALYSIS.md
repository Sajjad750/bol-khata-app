# Bol Khata — project analysis

Reviewed 18 October 2026. Based on the checked-in source, Android/iOS configuration, SQL schema, and eight test files. This is a static code review: Flutter and Dart were not found on the current command path, so tests, builds, microphone behavior, real SMS, and live cloud operations were not executed. There is no local `.env`. The deployed Supabase schema, policies, SMS provider, and Groq credentials were not verified. No application behavior was changed.

## 1. Overall assessment

The implementation already supports the central idea: a shopkeeper records speech, the app extracts a customer reference and free-form products, the shopkeeper checks a draft, and a dated transaction updates the customer's balance. There is no product catalogue, stock table, or predefined price list. Products belong to individual transactions; quantity, unit, and line price are optional.

It is a Flutter/Dart mobile app with Riverpod state management, Drift/SQLite local storage, Supabase authentication/cloud storage, and Groq speech and language-model requests. Android and iOS project folders exist; no web or desktop runner is included.

This is a useful prototype foundation, but account separation, PIN recovery, voice amount validation, and recovery of cloud data need attention before relying on it for real customer ledgers.

## 2. Your intended flow versus the code

| Requirement | Current implementation |
|---|---|
| Add customer manually first | Supported through Add Customer, but not enforced: Home also permits speaking before selecting/creating a customer |
| Choose customer, then speak products | Supported: the microphone on a customer's khata locks the destination to that customer |
| Flexible products without predefined prices | Supported: each entry stores free-form item names and optional quantity, unit, line total |
| Speak price and optional quantity | Supported through AI extraction; no deterministic per-unit-price calculation contract |
| Save with date | Automatic database creation timestamp; spoken transaction dates are not extracted |
| Voice-only entry | Recording is voice-based, but a confirmation tap is required; unclear/missing values need correction |
| Use without internet | Existing ledger and manual writes work locally; voice processing needs internet |
| Restore ledger after changing phone | Not implemented: cloud code only pushes local rows |

## 3. Screens and navigation

There are **13 Dart files under `lib/screens`: 12 screen classes and one AuthGate routing component**. Onboarding contains five internal steps; the ledger summary screen has two modes. These are not separate screen files.

| Component | Purpose |
|---|---|
| AuthGate | Shows language selection, loading, onboarding, unlock, or Home based on state |
| LanguagePickerScreen | First-launch choice and later language changes |
| OnboardingScreen | Phone, SMS OTP, PIN, PIN confirmation, optional biometric setup; phone may be skipped |
| UnlockScreen | PIN keypad, automatic biometric prompt when enabled, Forgot PIN action |
| HomeScreen | Customer list, search, totals, sorting/filtering, global microphone, account/language menu |
| CustomersScreen | Dedicated customer management list; open khata, edit, or add |
| AddCustomerScreen | Name, phone or number-pending flag, address, reference/nickname, optional photo |
| EditCustomerScreen | Change customer details and photo |
| CustomerDetailScreen | Customer profile, balance, transaction history, voice/manual entry, payment, whole-khata deletion |
| VoiceConfirmScreen | Review/edit voice draft; also reused for full manual entry with products |
| TransactionDetailScreen | Amount, date, type, source, note and items; delete action creates a reversal |
| LedgerSummaryScreen | Money to collect or received-payment list |
| LinkPhoneScreen | Add phone and verify OTP after starting locally |

Other interfaces are dialogs/sheets: amount keypad, item editor, photo-source chooser, sorting, phone edit, confirmation/error dialogs. There is no dedicated product-management, stock, export, or general settings screen.

Home offers five sorts: recent activity, name ascending/descending, and balance high/low. Filters are all, owes you, settled, you owe, and number pending. Home search checks name and phone; voice matching separately checks names and aliases.

## 4. Voice pipeline in detail

Main sources: `lib/widgets/voice_entry_button.dart`, `lib/services/transcription_service.dart`, `lib/services/entry_parser_service.dart`, `lib/services/roman_urdu.dart`, and `lib/screens/voice_confirm_screen.dart`.

1. Hold the microphone. The app checks microphone permission and starts a temporary `.m4a` recording: mono AAC, 44.1 kHz, 128 kbps. UI states are idle, recording, transcribing, and parsing.
2. Release the microphone. Audio is sent directly from the phone to Groq's transcription endpoint with configured model `whisper-large-v3-turbo`. The selected language supplies an English or Urdu language code and prompt. Files below 256 bytes are rejected; this is a size check, not a real speech-duration check.
3. For Roman Urdu, an optional language-model request rewrites non-Latin or English-looking output into Roman Urdu. This is best effort: conversion failures return the input.
4. The transcript goes to Groq chat completions with configured model `llama-3.3-70b-versatile`, temperature zero, and JSON output requested.
5. The parser produces a draft: spoken customer reference, items, total amount, credit/payment type, note, confidence, and an in-memory transcript. Each item has name, optional quantity, unit, and price.
6. If opened from a customer page, the entry stays attached to that customer. From Home, fuzzy matching finds up to three candidates.
7. The confirmation screen permits editing items, amount, transaction type and note. The customer must be explicitly selected unless already locked. A new customer can also be created here, with a valid Pakistani mobile required.
8. Confirm saves locally. Recording cleanup is attempted in `finally`, after the confirmation route closes or processing fails. Audio and raw transcript are not stored in ledger tables.

### Price meaning

`price` means **the total rupees for the item line**, not the price per unit. Example: “Ahmed ko 2 kilo chawal 600 rupay ke udhar diye” is intended to become rice, quantity 2, kg, line price 600, transaction amount 600. This is an illustrative intended parse, not a tested live transcription.

The prompt prefers summing item prices, but the app relies on the model to supply the initial transaction amount. Editing/adding/removing items triggers a sum of positive line prices. There is no distinct unit-price field or deterministic quantity × unit-price implementation. “2 kilo at 300 per kilo” is therefore less well specified than “2 kilo for 600 total.”

### Customer matching

`lib/database/customer_search.dart` lowercases and collapses spaces, compares names and aliases with string similarity, boosts substring matches to 0.85, and includes scores of at least 0.35. A gap of 0.05 or less between the top two matches means ambiguous. These are similarity scores, not verified probabilities. Suggested customers are not automatically selected.

Confirmed spoken references may be saved as aliases for future matching. Cross-script transliteration is not part of search: Urdu-script and Latin-script names can fail to match. In a locked-customer flow the parser still expects a customer reference even though the destination is known; item-only speech needs dedicated handling.

### Failures and fallback

Transcription distinguishes missing key, connectivity, API failure, missing/short audio, and empty transcript. The parser can retry once for its domain errors and then use a local heuristic. That heuristic only recognizes a few number phrases, can guess an amount from digits, and returns no product items. It is not an offline voice implementation. Some malformed outer API responses can bypass the intended retry path because JSON decoding occurs outside the guarded content-parser block.

## 5. How records are saved

Main sources: `lib/database/tables.dart`, `lib/database/app_database.dart`, and `lib/providers/auth_providers.dart`.

All normal UI reads and writes use **SQLite on the device, through Drift**. Schema version is 4, with migrations for sync IDs, item prices, address and reference note. Foreign keys are enabled. Indexes support customer history, aliases, and pending sync.

| Local table | Stored information |
|---|---|
| Customers | Name, unique normalized phone or generated pending placeholder, address, reference, local photo path, creation date, current balance, remote ID, sync flag |
| CustomerAliases | Customer ID and nickname/reference |
| Transactions | Customer ID, positive amount, credit/payment type, note, creation date, voice/manual source, reversal link, void flag, remote ID, sync flag |
| TransactionItems | Transaction ID, product name, optional quantity, unit, line price |

Names need not be unique. Real phone numbers must be Pakistani mobile numbers and are normalized to `03XXXXXXXXX`. Manual customer creation allows a unique `pending:` placeholder when a number is not known.

Creating a transaction inserts the transaction and products and updates the balance in one database transaction: either the operation completes together or rolls back. Credit increases what the customer owes; payment decreases it. A positive balance means the customer owes the shopkeeper, zero means settled, and negative means the shopkeeper owes the customer.

Transaction date is assigned at database insertion. There is no backdate input or spoken-date field. Cloud serialization converts timestamps to UTC. The interface formats date/time for display.

The database filename is derived from a saved local ledger identity. Photos are separate files copied into the application's documents directory. PIN/session data goes into platform secure storage; language goes into SharedPreferences. No SQLite encryption is configured in the application code.

### Corrections and deletion

Deleting one entry creates an opposite transaction and marks the original voided. This preserves the trail and reverses the balance once. Correction rows cannot be reversed again through that method. Received-payment summaries exclude voided entries and reversal rows.

Deleting an entire customer is different: it permanently removes their local transactions, products, aliases and customer row, attempts to delete the photo, and attempts cloud deletion. Thus “entries are never deleted” is only true of the individual correction flow.

## 6. Cloud database and synchronization

Main sources: `lib/services/sync_service.dart`, `lib/widgets/sync_status_icon.dart`, `supabase/schema.sql`.

The cloud database is **Supabase PostgreSQL**. The SQL defines two application tables: customers and transactions. Customer aliases are embedded as JSON; transaction products are embedded as JSON. Remote UUIDs are mapped to local integer IDs. Supabase Auth owns the user identities.

With a usable cloud session and Home active, the sync provider starts an immediate pass, a 30-second timer, and another pass on app resume. It pushes customers first, then their transactions. Existing remote rows are updated; new rows are upserted using `(user_id, local_id)`. Successful rows receive their remote ID and `synced=true`; errors leave them queued. This is an app-running timer, not an operating-system background worker.

The SQL enables row-level security and scopes each table's policies to `auth.uid() = user_id`, revokes anonymous table access, and grants authenticated access. This describes the repository SQL; deployment was not inspected.

Important limits:

- No cloud download, restore, reconciliation, realtime subscription or multi-device conflict resolution exists.
- Photos are not uploaded. Only a device-local path is sent to the database.
- Offline whole-customer deletion has no persistent cloud-delete queue, so a remote copy can remain indefinitely.
- Local integer IDs can collide across devices under the same cloud user because upserts use user plus local ID.
- A row changed while its previous snapshot uploads can be incorrectly marked synced afterward; no version check protects the mark-synced update.
- Customer balance and transaction uploads are separate requests, so cloud state can be temporarily inconsistent.
- Errors are swallowed; there is no last-success time or actionable error state. Zero pending rows can display “All entries synced” even when cloud backup is not configured.

Cloud upload should not yet be presented as a complete recoverable backup.

## 7. Signup, login, PIN and biometrics

Main sources: `lib/services/supabase_service.dart`, `lib/services/local_lock_service.dart`, `lib/services/secure_supabase_storage.dart`, `lib/providers/auth_providers.dart`, onboarding and unlock screens.

There is no email/password signup page. Phone authentication uses Supabase's `signInWithOtp`, followed by `verifyOTP` for SMS. The same interface serves first and returning phone users, subject to deployed Auth configuration. Local numbers are converted to `+92…`. Real SMS requires phone authentication and an SMS provider configured in Supabase.

First launch asks for language, then phone or “Add number later,” then a four-digit PIN, PIN confirmation, and optional biometrics. Skipping phone generates a local ledger identity and permits local usage without a Supabase account. Linking a phone later preserves that ledger identity and enables upload.

On normal app startup, an onboarded user sees PIN unlock. Enabled biometrics can prompt automatically. PINs are salted and hashed with SHA-256, and the hash/salt are held in secure storage. Session tokens are also persisted with secure storage and auto-refresh enabled. Biometrics permit the operating system's device-authentication fallback because `biometricOnly` is false.

Offline unlock accepts a locally retained refresh token without requiring a live validity check. This helps offline access but cannot prove that a remote session has not been revoked. There is no authentication-state subscription in the app controller and no automatic relock-on-resume logic.

### Serious account and recovery issues

1. **Account isolation:** signing out retains the ledger identity. Completing onboarding reuses it even if the newly verified phone belongs to a different Supabase user. A different account can reopen the previous ledger; pending rows may be submitted under the new cloud user. Comments claiming account separation do not match this path.
2. **PIN recovery bypass:** Forgot PIN calls full sign-out, clears the lock, and returns to onboarding. Onboarding still allows skipping phone and creating a new PIN while preserving the ledger identity. The code does not enforce verification of the original owner before recovery.
3. **PIN hardening:** there is no app-level attempt limit or retry delay, and the PIN hash is a fast hash rather than a deliberately slow derivation. The four-digit PIN is an interface lock, not database encryption.

## 8. Language behavior

`AppLanguage` supports English, Urdu, and Roman Urdu. The preference and chosen flag persist in SharedPreferences. Riverpod updates text/layout when language changes. `AppStrings` is a handwritten three-language string catalogue.

| Selection | Layout | Material locale | Voice request |
|---|---|---|---|
| English | Left to right | en | English transcription and parsing prompt |
| Urdu | Right to left | ur | Urdu transcription and Urdu-script parsing prompt |
| Roman Urdu | Left to right | en | Urdu transcription plus optional Roman Urdu rewrite |

Urdu is script output; no custom Nastaliq font is bundled. Material locale selection does not itself guarantee a Nastaliq typeface.

Translation is incomplete. Add/edit customer, voice confirmation, link phone, many dialogs/errors, sort labels, and transaction metadata contain hard-coded English. Dates/relative time and rupee formatting are also partly fixed. Switching language does not translate existing database content, and can reduce global voice matching accuracy across scripts. Roman Urdu conversion is best effort and may add requests and latency.

## 9. Findings to prioritize

| Priority | Finding and impact | Direction |
|---|---|---|
| Critical | Different phone sign-in can reuse the previous ledger | Bind local ledgers to verified account ownership; require explicit authenticated migration from local-only mode |
| Critical | Forgot PIN can lead to skipped verification and a replacement PIN | Require owner proof for recovery; define a separate local-only recovery policy |
| High | Groq secret is intended to ship inside the `.env` app asset and is used directly on the phone | Move Groq calls behind an authenticated server endpoint with limits |
| High | Cloud upload has no restore path | Implement and test new-device/reinstall restoration before claiming recoverable backup |
| High | Multi-device local-ID collisions and sync races | Use stable client-generated global identifiers and version-aware synchronization |
| High | Item totals can be inconsistent or stale | Define line-total/unit-price semantics and validate totals deterministically |
| High | iOS privacy purpose strings missing | Add microphone, camera, photo-library and Face ID descriptions as applicable, then test on device |
| Medium | Home allows voice before selecting a customer | Enforce customer selection first if that remains the product requirement |
| Medium | Locked-customer parsing still expects a spoken customer | Pass selected customer context and parse products without requiring a name |
| Medium | Offline delete is never retried | Persist deletion markers and retry cloud cleanup |
| Medium | Translation and cross-script matching incomplete | Finish string coverage and use language-independent customer identity |
| Medium | Recording start is asynchronous but release only stops the recording state | Handle release during permission/startup so recording cannot continue unexpectedly |
| Medium | No automatic relock after app backgrounding | Define and implement a resume lock policy |
| Medium | Release Android build uses debug signing | Configure release identity and signing before distribution |

Amount details: `_syncAmountFromItemPrices` only changes the amount if at least one positive item price exists. Removing the last priced item leaves its previous total. Summing a partially priced item list can replace a valid overall amount with a subtotal. Initial parser output is not reconciled against the item sum. Quantity positivity and item-price/quantity finiteness are not comprehensively validated. Money uses floating point, and `formatRs` rounds to whole rupees despite decimal values being accepted in parts of the flow. The fallback amount regex can split longer digit runs because the grouped-number alternative comes before unrestricted digits, and choosing the largest number cannot reliably distinguish price from quantity.

Additional quality issues: the customer list's manual row mapping omits address/reference fields; edited reference notes can leave old aliases; new-customer creation and its subsequent voice transaction save are separate operations, allowing a customer to remain after entry-save failure. Friendly error handling exists but some screens still show raw errors. The transaction detail receives a snapshot rather than a live entry provider.

## 10. Tests, configuration and readiness

Eight test files cover PIN/onboarding, local persistence and balances, corrections/phone uniqueness/fuzzy ambiguity, sync flags, parser JSON and mocked API/save flow, transcription mocks, Roman Urdu conversion mocks, and a basic app widget. They do not demonstrate real microphone accuracy, SMS delivery, live RLS, cloud restoration, account switching safety or multi-device sync.

One test deserves review: the parser retry test expects exactly two HTTP calls for a phrase without Roman Urdu cues, but Roman Urdu normalization can add an HTTP call first. This is a static observation, not an executed test failure.

No CI workflow was found. Flutter/Dart were unavailable on the current command path, so no test-pass or build-pass claim is made. `.env` is absent, while `pubspec.yaml` lists it as an asset; a normal build needs that asset supplied or the declaration adjusted even though dotenv loading is optional at runtime. The supplied example lists Groq and Supabase configuration placeholders.

Android declares internet, microphone, camera and biometric permissions and uses FlutterFragmentActivity for device authentication. iOS has its runner configuration but lacks the relevant privacy descriptions in Info.plist. Android currently retains `com.digikhata.khata_app` as its application identity and debug release signing; both should be reviewed before publishing the new independent app.

Suggested implementation order: fix account ownership and PIN recovery; define customer-first flow and exact price semantics; secure voice requests; add deterministic amount validation; build restore and reliable sync/deletion; complete language support; then test real Pakistani shopkeeper speech, noisy environments, number phrases, customer ambiguity, offline transitions and device recovery. Keep confirmation before committing financial records.
