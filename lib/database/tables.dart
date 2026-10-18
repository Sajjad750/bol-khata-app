import 'package:drift/drift.dart';

/// Primary customer record. [phoneNumber] is the unique identity — never name.
class Customers extends Table {
  IntColumn get id => integer().autoIncrement()();

  TextColumn get name => text().withLength(min: 1, max: 200)();

  /// Optional shop / home address for the customer.
  TextColumn get address => text().nullable()();

  /// True unique identifier for a customer (DB-level unique constraint).
  TextColumn get phoneNumber => text().unique().withLength(min: 1, max: 64)();

  /// Optional reference / nickname note (also used for voice matching).
  TextColumn get referenceNote => text().nullable()();

  /// Local filesystem path to a customer photo (visual disambiguation).
  TextColumn get photoPath => text().nullable()();

  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();

  /// Positive = customer owes shopkeeper; negative = shopkeeper owes customer.
  RealColumn get currentBalance => real().withDefault(const Constant(0.0))();

  /// Remote Supabase row id (UUID string). Null until first successful sync.
  TextColumn get supabaseId => text().nullable()();

  /// Whether this customer row has been pushed to Supabase.
  BoolColumn get synced => boolean().withDefault(const Constant(false))();
}

/// Nicknames / shop-floor references for a customer (e.g. "cycle wala Ahmed").
@DataClassName('CustomerAlias')
class CustomerAliases extends Table {
  IntColumn get id => integer().autoIncrement()();

  IntColumn get customerId => integer()();

  TextColumn get alias => text().withLength(min: 1, max: 200)();

  @override
  List<String> get customConstraints => [
        'FOREIGN KEY (customer_id) REFERENCES customers (id)',
      ];
}

/// Immutable ledger entries. Mistakes are fixed by inserting corrections —
/// never by editing [amount], [type], or [customerId] on an existing row.
class Transactions extends Table {
  IntColumn get id => integer().autoIncrement()();

  IntColumn get customerId => integer()();

  /// Always stored as a positive value.
  RealColumn get amount => real()();

  /// `"credit_given"` or `"payment_received"`.
  TextColumn get type => text()();

  TextColumn get note => text().nullable()();

  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();

  /// Whether this row has been pushed to Supabase (Phase later).
  BoolColumn get synced => boolean().withDefault(const Constant(false))();

  /// `"manual"` or `"voice"`.
  TextColumn get sourceType =>
      text().withDefault(const Constant('manual'))();

  /// Points at the original mistaken entry when this row is a correction.
  IntColumn get reversesTransactionId => integer().nullable()();

  /// Soft-void flag used only by the correction flow. Rows are never deleted.
  BoolColumn get isVoided => boolean().withDefault(const Constant(false))();

  /// Remote Supabase row id (UUID string). Null until first successful sync.
  TextColumn get supabaseId => text().nullable()();

  @override
  List<String> get customConstraints => [
        'FOREIGN KEY (customer_id) REFERENCES customers (id)',
        'FOREIGN KEY (reverses_transaction_id) REFERENCES transactions (id)',
        "CHECK (type IN ('credit_given', 'payment_received'))",
        "CHECK (source_type IN ('manual', 'voice'))",
        'CHECK (amount > 0)',
      ];
}

/// Optional line items attached to a transaction (many txns have none).
class TransactionItems extends Table {
  IntColumn get id => integer().autoIncrement()();

  IntColumn get transactionId => integer()();

  TextColumn get itemName => text().withLength(min: 1, max: 200)();

  RealColumn get quantity => real().nullable()();

  TextColumn get unit => text().nullable()();

  /// Line total in Rs (e.g. "20 rupay ke kheere" → 20). Optional.
  RealColumn get price => real().nullable()();

  @override
  List<String> get customConstraints => [
        'FOREIGN KEY (transaction_id) REFERENCES transactions (id)',
      ];
}

/// Allowed [Transactions.type] values.
abstract final class TransactionType {
  static const creditGiven = 'credit_given';
  static const paymentReceived = 'payment_received';

  static const all = {creditGiven, paymentReceived};

  static String opposite(String type) {
    switch (type) {
      case creditGiven:
        return paymentReceived;
      case paymentReceived:
        return creditGiven;
      default:
        throw ArgumentError.value(type, 'type', 'Unknown transaction type');
    }
  }
}

/// Allowed [Transactions.sourceType] values.
abstract final class TransactionSourceType {
  static const manual = 'manual';
  static const voice = 'voice';

  static const all = {manual, voice};
}
