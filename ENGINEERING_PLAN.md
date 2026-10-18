# Bol Khata: engineering, delivery, testing and product plan

Prepared 18 October 2026. Status: proposed implementation plan, not an implemented architecture or a certification of scalability. Read alongside PROJECT_ANALYSIS.md. Existing app code is the migration starting point; preserve useful work and replace components incrementally.

## 1. Decisions and priorities

Use Flutter/Dart, Riverpod, Drift/SQLite locally, and Supabase/PostgreSQL remotely. Build an offline speech adapter whose engine can be replaced after device benchmarks. Keep a single deployable backend initially, organized by responsibility. Introduce additional infrastructure when measurements justify it.

Engineering quality means explicit financial rules, reviewed changes, repeatable builds, meaningful tests, clear ownership and recoverability. No architecture guarantees that nothing ever fails. The objective is to prevent avoidable errors, detect failures quickly, preserve locally saved work, and recover safely.

Phase 1 assumptions: Lahore; approximately 100 pilot shops; Android; one active entry device per shop; Urdu speech first; Urdu/Roman Urdu/English interface; Punjabi and mixed speech evaluated before a support commitment; flexible products; prices expressed as line totals; phone collected without OTP as unverified contact information. Confirm device/Android minimums after field inventory rather than choosing arbitrary specifications.

Priority order: account ownership and PIN recovery; financial correctness and local durability; offline speech feasibility; understandable UX; sync/restore; automated releases and operations. Set up basic CI early to protect all subsequent work.

## 2. Target application architecture

Organize code by feature: identity, customers, ledger, voice, sync and settings. Each feature contains presentation/controllers, repository interfaces, and concrete data/services where appropriate. Shared infrastructure contains database connections, configuration, secure storage, diagnostics and localization. Add a domain/use-case layer for genuinely complex ledger and synchronization rules, without wrapping every small function in another abstraction.

Example structure:

```text
lib/
  app/                  # bootstrap, navigation, environment wiring
  core/                 # shared storage, errors, localization, diagnostics
  features/
    identity/
    customers/
    ledger/
    voice/
    sync/
    settings/
```

Views render state and collect input. Riverpod controllers coordinate actions. Repositories own data access and publish local state. Ledger rules are ordinary Dart code independent of Flutter and external providers. Services adapt recording, speech models, remote APIs and device functions. Screens must not perform SQL, cloud writes, amount calculations or account migrations directly. This adapts Flutter's official separation/repository recommendations to the existing Riverpod code [1].

The phone's SQLite database is the operational source for the UI; the server is the authority for authenticated ownership, accepted sync versions and restored cloud history. Model synchronization states explicitly instead of pretending the two stores are always current [2].

Use immutable drafts and validated value types for money, quantity and IDs. Use typed failures such as permission denied, unsupported model, disk full, invalid amount, authentication expired and sync conflict. Convert them into localized customer-facing guidance. Keep dependency injection straightforward; preserve Riverpod rather than changing frameworks for style.

### Financial contract

- Store money as integer minor units: PKR 600.50 = 60050 paisa; include currency code. Define scale/rounding per currency for international growth. Convert old doubles using an explicit audited migration and reconciliation.
- Use validated decimal quantities with a documented precision; do not reuse money arithmetic for quantity. Each item stores free-form name, optional quantity/unit, and optional line total.
- Phase 1 asks for line total. Unit price is a future explicit field, with deterministic quantity multiplication and rounding when introduced.
- A posted transaction has a positive total and a known credit/payment type. If products are partially priced, show that the breakdown is incomplete and require a total; do not replace the total silently with a subtotal.
- Credit increases customer debt; payment reduces it. Correct mistakes using linked reversal/replacement entries. No silent changes to posted amounts. Record actor, device, creation time and operation ID.
- Keep a materialized balance for speed but reconcile it against the ledger. Decide how reversals count once and test that invariant.
- Save transaction, items, balance change and pending upload operation atomically. Display success only after durable local commit. Handle disk-full/write failure explicitly.
- Keep customer identity separate from phone/name. Names and unverified phone numbers do not prove ownership. Pending numbers remain supported.
- Store device capture time, UTC timestamp, timezone/offset and server receipt/sequence separately. Clock changes must not break sync ordering. Backdated entries are out of pilot scope.

### Identity and security

Remove the current account-switching reuse and Forgot PIN bypass before pilot deployment. A shop has a stable ID; a user/device is explicitly authorized for it. Never infer authorization from a typed phone number. Bind the local ledger and remote tenant deliberately; migration from local-only to cloud must be explicit and authenticated.

Pilot registration collects shop name and phone as contact data, creates a local identity/PIN and recovery mechanism, and creates a separate authenticated cloud identity when connected. Anonymous cloud authentication is a candidate for the pilot, with enrollment limits; losing its credentials must not make another phone able to claim the ledger by number. Define operator-assisted or single-use recovery codes before launch. Add verified phone identity later without changing shop/ledger IDs.

Use platform secure storage for credentials, PIN retry controls, authenticated owner recovery and a resume-lock policy. Evaluate encrypted SQLite against recovery/key-management requirements; a PIN screen alone does not encrypt records. Keep administrative/service credentials and optional cloud speech secrets on servers. RLS, tenant-scoped constraints and negative access tests must protect every data endpoint, object and restore path.

Store photos as private objects with authorized paths/URLs; do not upload device file paths as backup. Do not log raw audio, customer numbers, transcripts or ledger details. Audio collection for model evaluation requires opt-in, limited retention and restricted access. Default crash/analytics payloads must be scrubbed. Record model license and redistribution requirements before bundling it.

## 3. Offline speech design and feasibility gate

Define separate Recorder, SpeechRecognizer and EntryParser interfaces. They return typed drafts, never posted financial transactions. Execute speech processing away from the UI thread with bounded resource use; handle cancellation, interruptions and process death.

Evaluate multilingual whisper.cpp models as candidates, not an already chosen production solution [11]. Benchmark tiny/base/small or compressed alternatives on actual target phones. Record model version/checksum, language, model size, RAM, processing time, battery/thermal behavior and field-level accuracy. Native integration may require Kotlin/C++ and the Android NDK even though the app is Flutter.

Download the model resumably during supported setup, or bundle a permitted version. Verify checksums and disk space, make offline readiness visible, and retain a known-good model during updates. Local saving must remain usable if a model download fails. Never silently switch to a cloud recognizer in airplane mode or upload recordings without the intended user choice.

Pipeline: selected customer -> short recording -> speech detection/optional tested noise reduction -> offline transcript -> local number/unit/product extraction -> editable draft -> explicit confirmation -> atomic local save. Do not require a spoken customer name after customer selection. One product per recording is the initial baseline, with repeat-to-add another. Test whether that friction is acceptable before expanding to multi-item free speech.

Separate UI language, spoken language and output script. Urdu/Roman Urdu is not two spoken languages. Use per-locale parsing dictionaries for expressions such as sau, hazaar, dhai, aadha, kilo and dozen. Keep product names free-form. Add language packs and benchmarks individually; an interface translation does not create speech support.

First evaluation: 5-10 consenting shops, different speakers and phone models. Collect roughly 300-500 short labelled samples across quiet and noisy conditions, emphasizing amounts, product/brand names, fractional quantities, mixed language and ambiguous phrases. Split development/evaluation by speaker or shop to avoid tuning on the same people being measured. Keep an untouched evaluation set and publish results by language/device/noise level, including failures.

Measure exact amount and credit/payment correctness, product/quantity accuracy, rejected recordings, correction rate and end-to-end time, as well as word error rate. Model confidence alone is not a correctness guarantee. Never guess unclear amounts or save without confirmation.

Provisional voice gate: at least 95% exact amount/type recognition on the declared supported evaluation slice, no silent auto-posting, and acceptable correction burden in observed use. Target draft availability within 5 seconds at p95 for a short ~5-second recording on the agreed reference phone. These are proposed acceptance targets, not measured capability; revise the supported device/interaction scope if unmet rather than claiming universal support.

## 4. Reliable synchronization and restoration

Replace the timer-only push mechanism with a durable outbox. Use globally unique client-generated operation/entity IDs, explicit shop and device IDs, and version metadata. Retry delivery at least once and make server application idempotent: retries must not create a second financial entry. Do not claim network-level exactly-once delivery.

Server processing authenticates tenant ownership, validates payloads and applies a logical ledger operation and receipt in one database transaction. Use optimistic version checks for mutable customer fields. Posted financial entries remain append-only with corrections. Deduplicate by shop + operation ID. Reject attempted ID reuse with a different payload. Update local upload status only if the acknowledged version matches the current local version.

Download incrementally using a server-issued cursor with stable sequence/tie-breaking, pagination and a commit-safe local cursor. Never rely solely on a phone timestamp. Preserve pending local entries while applying remote state. Deletions need tombstones and retention/compaction rules so older devices do not resurrect data. Whole-khata erasure requires a separate, deliberately defined product/security policy.

Sync on successful writes when feasible, app start/resume, manual retry and scheduled network-constrained work. Use exponential backoff with jitter, bounded batches, retry caps for permanent errors, visible failure states and reconciliation. Android WorkManager is appropriate for persistent scheduled work [7], but background timing is OS-controlled; force-stop/battery restrictions can delay work. Do not promise continuous closed-app syncing.

Show: saved on this phone; waiting for backup; backup failed/retry; last backup time. Restoration must cover clean installation, authorized recovery, interrupted download, photos and balance reconciliation. Test cloud backups by restoring them to a separate environment; a backup configuration without a restore drill is incomplete.

Pilot policy: one active entry device per shop. Enforce/communicate enrollment and recovery explicitly. Later multi-device writes require tested conflict behavior and device revocation. Server compatibility must tolerate older supported mobile versions.

## 5. GitHub workflow and CI/CD

Use a protected main branch and small short-lived branches. Pull requests include problem, behavior, migration implications and evidence. Require passing checks; add one independent reviewer when another developer is available. Do not invent a blocking self-review requirement for a solo developer. Use CODEOWNERS for ledger, auth, sync and workflows as team ownership develops. Keep architecture decisions in short versioned decision records.

### On every pull request

1. Install the pinned Flutter SDK, Java and required Android/native toolchain. Commit the application lockfile. Resolve dependencies using controlled versions.
2. Check Dart formatting, static analysis and agreed strict type/lint rules. Regenerate Drift outputs and fail on unexpected generated-file changes.
3. Run domain/unit, widget, SQLite/migration and relevant backend/RLS tests. Report failures and changed-code coverage. All financial/security invariant scenarios must pass; no arbitrary 100% repository coverage promise.
4. Run dependency and secret checks, including native/model dependencies and licenses. Use Dependabot where supported and an appropriate maintained scanner such as Gitleaks after version verification. GitHub feature availability depends on repository visibility and plan.
5. Build an unsigned/unprivileged Android test artifact. On ledger/auth/sync/native changes run the relevant emulator integration suite. Upload sanitized test reports and artifacts with limited retention.

Keep fast PR jobs separate from slower nightly/release suites. Nightly includes device tests, speech regression fixtures, larger local datasets and scheduled staging load tests. Field acoustics cannot be validated by injected audio fixtures alone.

### Release path

Merge -> staging deployment and migration checks -> signed internal Android build -> device/restore smoke tests -> named pilot cohort -> staged production rollout. Start with 5-10 shops, expand to 25, then 100 after explicit gates. Signed release tags identify commit, build number, migration and speech-model version. Promote the same tested artifact where possible.

Use GitHub environment restrictions and scoped secrets where available; select the plan-appropriate equivalent when paid controls are unavailable [5]. Keep signing keys and upload credentials out of PR jobs. Restrict workflow permissions, pin third-party Actions to reviewed commit SHAs, keep untrusted PR code away from privileged jobs, and avoid unsafe shell interpolation [4]. Prefer short-lived cloud credentials when the service supports them. Never put production keys in generated test config or publish signing files in artifacts.

Separate development, staging and production Supabase projects/configuration. Apply schema changes through versioned migrations in CI, with tests from empty and prior supported schemas. Use expand/migrate/contract deployment for changes affecting old apps. A mobile-store release cannot be instantly rolled back on every phone: halt rollout, disable risky optional features, and ship a compatible fix. Database recovery generally needs forward repair, not an assumed reversible migration.

## 6. Tool setup and testing strategy

Observed today: Git, Java, VS Code and Android SDK/adb are discoverable; Android SDK includes NDK/CMake directories. Flutter/Dart are not discoverable on PATH. Docker, Supabase CLI, k6 and system CMake were not discoverable on PATH; that is not proof they are absent elsewhere. Existing dev dependencies include flutter_test, flutter_lints, drift_dev and build_runner. No GitHub workflow was found. This plan does not install software or execute application tests.

### Setup order

1. Locate/install a Flutter release compatible with the project's Dart requirement, validate flutter doctor, and pin it for developers and CI. Dart comes with Flutter. Verify compatible Java/Gradle/Android SDK/NDK versions; validate existing installations before replacing them.
2. Resolve dependencies and run the existing suite to establish a recorded baseline. Resolve missing .env asset/build configuration without introducing real test secrets. Fix or document existing failures before adding new gates.
3. Add Flutter integration_test. Configure one Android emulator plus physical entry-level and midrange reference phones. Choose actual Android versions from shop inventory.
4. Set up a local disposable Supabase test environment using supported CLI/container tooling, or a dedicated isolated staging equivalent if local virtualization is unavailable. Add SQL policy/migration tests with pgTAP where suitable. Never load-test production or use real customer fixtures.
5. Add k6 for sync/API capacity tests and profile builds with Flutter DevTools/Android profilers. Add a sanitized crash reporter such as Sentry after checking native crash visibility for the chosen speech binding.
6. Evaluate Patrol only for native/system interaction gaps such as permission dialogs; verify version compatibility before adopting it [8]. Add Firebase Test Lab for a small release device matrix when justified [9]. Cloud device testing does not require replacing Supabase with Firebase.

| Test layer | Scenarios and tools | When |
|---|---|---|
| Financial/domain | Dart/flutter_test: exact money, quantities, totals, balances, reversals, random operation sequences | Every PR |
| Local persistence | Drift SQLite: atomicity, reopen/process interruption, disk errors, migrations with realistic prior fixtures | Every relevant PR |
| Controllers/widgets | flutter_test: draft states, errors, labels, large text, RTL, navigation and selection | Every PR |
| Device integration | integration_test; optional Patrol: signup, customer, offline record/save/reopen, permission denial, interruption | Relevant PR/nightly/release |
| Backend security | Isolated Supabase/SQL tests: shop A cannot read/change shop B, forged IDs, replayed/conflicting operations | Every backend change |
| Sync/recovery | Duplicate retry, reordered requests, disconnect after server commit, token expiry, deletion offline, clean restore | Every relevant PR/release |
| Speech regression | Labelled held-out audio, exact field metrics by language/device/noise/model version | Every speech change/release |
| Performance/capacity | DevTools/profilers, k6 thresholds, slow network, large ledger, reconnection spike/soak | Baseline/nightly/pre-expansion |
| Human usability | Observe real shopkeepers completing core tasks, in local language and shop conditions | Prototype/each cohort |

Flutter's integration_test supports emulator/device end-to-end flows [3]. k6 thresholds turn load expectations into pass/fail criteria [10]. Tests must assert business outcomes, not merely repeat implementation internals. Quarantine flaky tests with an owner/deadline; never normalize rerunning until green. Use synthetic ledger data and consented/deidentified audio.

Required release scenarios: fresh local onboarding; model setup interrupted/resumed; no-network cold start; recording release during permission startup; call interrupts recording; low space; save/reopen; wrong PIN/recovery; another account; failed restore; old schema upgrade; retries after server accepted but reply lost; pending local changes during pull; photo authorization; duplicate/customer total corrections; long text and RTL.

## 7. Product and usability plan

User research: observe 5-10 Lahore shopkeepers using registers and phones. Establish language, reading comfort, typical products/units, shop noise, device/OS, connectivity and whether phones are shared. Test prototypes with users; do not assume that a modern visual style is understandable.

### Intended main journey

1. Choose interface and speaking preference with short examples. Ask for shop name/contact number and PIN; explain pilot recovery simply.
2. Complete offline model setup with visible download/readiness and a short practice entry. Explain if voice is not ready; manual entry still works.
3. Add the first customer manually: name required; phone optional/pending; photo optional. Avoid requesting microphone/camera permissions before needed.
4. Open customer: show name/photo clearly, balance with words, and large Record entry, Add manually and Receive payment actions. Remove the ambiguous Home microphone for phase 1, or make it select a customer before recording.
5. Record one short item sentence. Offer hold-to-record plus an accessible tap/start-stop option with clear state and duration limits.
6. Review customer, product, quantity and prominently displayed line total. Show credit/payment in explicit local wording. Make missing values easy to fix. Require confirmation, with an example phrase when retrying.
7. Show “Saved on this phone” after commit and a distinct backup status. Return to the customer ledger. Make a correction easy to find and explain its balance effect.

Use a small consistent design system: typography, spacing, buttons, input states, empty states and error patterns. Prefer familiar Urdu/Roman Urdu wording validated with users. Do not put sync, RLS, parser or model jargon in normal customer flows. Use customer photos/names for orientation, not color alone. Avoid translating a debit/credit term literally if users misunderstand it.

Targets: primary touch areas at least 48 logical pixels, clear contrast, readable Urdu rendering, screen-reader labels, large text without clipped controls, full RTL and correct numeric direction. Test all labels/errors and native permission paths; Flutter includes accessibility testing support [6]. Keep currency and date formatting locale-aware and amounts unambiguous. Default to current date in pilot, with no hidden spoken-date interpretation.

Prototype tasks: create customer, record credit, record payment, correct a wrong amount, use airplane mode, recognize backup pending and recover a ledger. Proposed gate: at least 8 of 10 representative participants complete a repeat entry without coaching, with zero observed wrong-customer confirmations in the session. This small study is a discovery gate, not proof of population-wide safety.

## 8. Capacity, operations and growth

Registered users do not equal concurrent load. Track daily active shops, entries per shop, payload sizes, burst upload behavior and retention. Offline speech reduces cloud computation, but does not eliminate database, auth, object storage and sync traffic.

Illustrative scenario, not a forecast: 100,000 active shops x 100 entries/day = 10 million entries/day, roughly 116 entries/second averaged over 24 hours. A 10x peak is about 1,160 entries/second. One entry may require several database operations; compressed batch requests reduce HTTP overhead, not the ledger volume. One million equally active shops multiplies those numbers by ten. Model storage/cost and reconnection bursts explicitly before purchasing capacity.

| Stage | Engineering focus | Expansion condition |
|---|---|---|
| 5-10 shops | Offline model/device proof, account fixes, local durability, understandable flow | Voice/usability/security gates satisfied |
| 25-100 shops | Working restore, sync failure tests, CI/release signing, diagnostics and support | Stable cohort metrics and restore drill |
| Around 1,000 shops | Query/index review, paginated sync, measured background workload, alerting/cost budgets | Load test at forecast peak plus headroom |
| Around 10k-100k active shops | Capacity planning, worker scaling where needed, pooled server DB connections, archive strategy, operational ownership | Demonstrated peak/reconnection/soak performance |
| Toward 1m active shops | Re-evaluate vendor capacity, partitioning/tenant placement, disaster recovery and regional requirements | Benchmarks, capacity budget and operational readiness |

The counts are review milestones, not throughput guarantees. Begin with a modular backend and managed Postgres; add workers for heavy asynchronous tasks, not a service for every screen. Only add Redis, message brokers, replicas, partitioning or multiple regions for a demonstrated bottleneck. Replicas cannot remove primary-write limits. Avoid maintaining authoritative balances in a cache.

Use indexed tenant-scoped queries, bounded history/pagination, resource limits, connection pooling for server workloads and appropriate database compute. Do not create a direct PostgreSQL connection from every phone. Supabase recommends load testing and query/index review; capacity needs measurement and suitable provisioning [12][13].

Observe crash-free sessions, local save failures, pending sync count/age, restore outcomes, wrong-field corrections, voice latency/memory, backend p95/error rates and cost per active shop. Start with one monitoring stack, sanitized logs and actionable alerts. Keep last-success backup time visible even without telemetry.

Provisional initial targets: no lost or duplicated posted entries in the defined fault-test suite; p95 local commit below 300 ms on a declared reference device; foreground small-backlog sync within 60 seconds under a defined stable test network; at least 99.5% crash-free pilot sessions, aiming for 99.9% after hardening. Targets are proposals, not existing measurements or service guarantees. For cloud availability, define an SLO after choosing a hosting plan and traffic profile.

Document recovery point/time objectives and run drills. Local-only or pending-upload entries cannot be recovered from a destroyed phone by cloud backup. Candidate server objectives before a larger launch are RPO <=15 minutes and RTO <=4 hours only if the selected backup/PITR plan and measured restores support them. For the pilot, publish the actual recovery limits rather than promising those objectives prematurely.

## 9. Ordered delivery milestones

| Milestone | Concrete deliverable | Completion evidence |
|---|---|---|
| M0: baseline | Working/pinned toolchain, existing test results, architecture decisions, issue backlog, basic PR checks | Reproducible checkout/build and recorded baseline |
| M1: feasibility and UX | Offline speech experiment, device/language benchmarks, tested customer-first prototype | Held-out metrics and observed shop tasks |
| M2: safe core | Account/recovery fix, exact money, ledger repositories/controllers, migration strategy | Financial/security/persistence tests pass |
| M3: offline journey | Local parser/recording/model lifecycle and localized draft/confirmation | End-to-end airplane-mode tests on reference phones |
| M4: recoverable cloud | Idempotent sync, cursor pull, photos, deletions and authorized restore | Disconnect/retry/restore/migration drills pass |
| M5: pilot release | Signed artifacts, staged CI/CD, diagnostics, support instructions and cohort tracking | 5-10 -> 25 -> 100 shop acceptance gates |
| M6: growth | Measured capacity plan, reliable operations, expanded device/language support | Forecast load/stress/soak evidence and budget |

M1 can run alongside safe-core design after M0, but a failed offline speech gate blocks promising the full pilot voice feature. Do not migrate the complete app to a new folder layout in one giant PR. Add characterization tests, extract one boundary, preserve behavior, migrate data safely, then remove the replaced path. Treat estimates as pending team size, hardware and speech findings; calendar promises before M1 would be unreliable.

Suggested initial PRs: (1) reproducible setup/basic CI; (2) account/recovery isolation tests and fixes; (3) exact money/domain tests and safe migration design; (4) customer-first prototype; (5) replaceable offline speech spike and benchmark results; (6) durable local save/outbox; (7) server idempotency and restore; (8) pilot release/device automation. Separate research spikes from production paths.

## 10. Research sources

These references establish the underlying practices. The architecture, targets and rollout above are project-specific recommendations, not claims of vendor certification.

1. [Flutter architecture recommendations](https://docs.flutter.dev/app-architecture/recommendations)
2. [Flutter offline-first guidance](https://docs.flutter.dev/app-architecture/design-patterns/offline-first)
3. [Flutter integration testing](https://docs.flutter.dev/testing/integration-tests)
4. [GitHub Actions secure use](https://docs.github.com/en/actions/reference/security/secure-use)
5. [GitHub deployment environments and feature availability](https://docs.github.com/en/actions/reference/workflows-and-actions/deployments-and-environments)
6. [Flutter accessibility](https://docs.flutter.dev/ui/accessibility)
7. [Android persistent background work](https://developer.android.com/develop/background-work/background-tasks/persistent)
8. [Patrol native testing API](https://pub.dev/documentation/patrol/latest/patrol/)
9. [Firebase Test Lab for Flutter](https://firebase.google.com/docs/test-lab/flutter/integration-testing-with-flutter)
10. [k6 pass/fail thresholds](https://grafana.com/docs/k6/latest/using-k6/thresholds/)
11. [whisper.cpp Android example](https://github.com/ggml-org/whisper.cpp/blob/master/examples/whisper.android/README.md?plain=1)
12. [Supabase production checklist](https://supabase.com/docs/guides/deployment/going-into-prod)
13. [Supabase connection management](https://supabase.com/docs/guides/database/connection-management)
