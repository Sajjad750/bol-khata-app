import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:drift_flutter/drift_flutter.dart';

import 'customer_list_item.dart';
import 'customer_search.dart';
import 'phone_numbers.dart';
import 'shop_summary.dart';
import 'tables.dart';

part 'app_database.g.dart';

/// Thrown when inserting a customer whose [phoneNumber] already exists.
class DuplicatePhoneNumberException implements Exception {
  DuplicatePhoneNumberException(this.phoneNumber);

  final String phoneNumber;

  @override
  String toString() =>
      'A customer with phone number "$phoneNumber" already exists.';
}

/// Thrown when a correction targets a missing or already-voided transaction.
class TransactionCorrectionException implements Exception {
  TransactionCorrectionException(this.message);

  final String message;

  @override
  String toString() => message;
}

class TransactionItemInput {
  const TransactionItemInput({
    required this.itemName,
    this.quantity,
    this.unit,
    this.price,
  });

  final String itemName;
  final double? quantity;
  final String? unit;
  final double? price;
}

@DriftDatabase(
  tables: [Customers, CustomerAliases, Transactions, TransactionItems],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase({QueryExecutor? executor, String name = 'khata'})
    : super(executor ?? _openConnection(name));

  /// In-memory DB for unit tests (offline, no Flutter path_provider needed).
  AppDatabase.memory() : super(_openMemoryConnection());

  static QueryExecutor _openConnection(String name) {
    return driftDatabase(name: name);
  }

  static QueryExecutor _openMemoryConnection() {
    return NativeDatabase.memory(
      setup: (db) => db.execute('PRAGMA foreign_keys = ON'),
    );
  }

  @override
  int get schemaVersion => 4;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (m) async {
      await m.createAll();
      await _createIndexes();
    },
    onUpgrade: (m, from, to) async {
      if (from < 2) {
        await m.addColumn(customers, customers.supabaseId);
        await m.addColumn(customers, customers.synced);
        await m.addColumn(transactions, transactions.supabaseId);
        await customStatement(
          'CREATE INDEX IF NOT EXISTS idx_customers_synced '
          'ON customers (synced) WHERE synced = 0',
        );
      }
      if (from < 3) {
        await m.addColumn(transactionItems, transactionItems.price);
      }
      if (from < 4) {
        await m.addColumn(customers, customers.address);
        await m.addColumn(customers, customers.referenceNote);
      }
    },
    beforeOpen: (details) async {
      await customStatement('PRAGMA foreign_keys = ON');
    },
  );

  Future<void> _createIndexes() async {
    await customStatement(
      'CREATE INDEX IF NOT EXISTS idx_transactions_customer_created '
      'ON transactions (customer_id, created_at DESC)',
    );
    await customStatement(
      'CREATE INDEX IF NOT EXISTS idx_transactions_synced '
      'ON transactions (synced) WHERE synced = 0',
    );
    await customStatement(
      'CREATE INDEX IF NOT EXISTS idx_customers_synced '
      'ON customers (synced) WHERE synced = 0',
    );
    await customStatement(
      'CREATE INDEX IF NOT EXISTS idx_aliases_customer '
      'ON customer_aliases (customer_id)',
    );
    await customStatement(
      'CREATE INDEX IF NOT EXISTS idx_aliases_alias '
      'ON customer_aliases (alias)',
    );
  }

  // ---------------------------------------------------------------------------
  // Customers
  // ---------------------------------------------------------------------------

  /// Adds a customer. [phoneNumber] is required and must be unique.
  /// Pass [phonePending] true to store an explicit pending placeholder instead.
  Future<Customer> addCustomer({
    required String name,
    String? phoneNumber,
    bool phonePending = false,
    String? photoPath,
    String? address,
    String? referenceNote,
    List<String> aliases = const [],
  }) async {
    final trimmedName = name.trim();
    if (trimmedName.isEmpty) {
      throw ArgumentError.value(name, 'name', 'Name is required');
    }

    final trimmedAddress = address?.trim();
    final trimmedRef = referenceNote?.trim();

    late final String trimmedPhone;
    if (phonePending) {
      trimmedPhone = PhoneNumbers.createPendingPlaceholder();
    } else {
      final raw = (phoneNumber ?? '').trim();
      if (raw.isEmpty) {
        throw ArgumentError.value(
          phoneNumber,
          'phoneNumber',
          'Phone number is required (or mark as pending)',
        );
      }
      trimmedPhone = PhoneNumbers.normalize(raw);
      if (!PhoneNumbers.isValidPakistaniMobile(trimmedPhone)) {
        throw ArgumentError.value(
          phoneNumber,
          'phoneNumber',
          'Enter a valid Pakistani mobile (03XXXXXXXXX)',
        );
      }
    }

    try {
      return await transaction(() async {
        final id = await into(customers).insert(
          CustomersCompanion.insert(
            name: trimmedName,
            phoneNumber: trimmedPhone,
            photoPath: Value(photoPath),
            address: Value(
              trimmedAddress == null || trimmedAddress.isEmpty
                  ? null
                  : trimmedAddress,
            ),
            referenceNote: Value(
              trimmedRef == null || trimmedRef.isEmpty ? null : trimmedRef,
            ),
          ),
        );

        final aliasSet = <String>{
          ...aliases.map((a) => a.trim()).where((a) => a.isNotEmpty),
          if (trimmedRef != null && trimmedRef.isNotEmpty) trimmedRef,
        };
        for (final alias in aliasSet) {
          if (alias.toLowerCase() == trimmedName.toLowerCase()) continue;
          await into(customerAliases).insert(
            CustomerAliasesCompanion.insert(customerId: id, alias: alias),
          );
        }

        return (await (select(
          customers,
        )..where((c) => c.id.equals(id))).getSingle());
      });
    } catch (e) {
      // Unique constraint on phone_number — surface a UI-friendly error.
      if (_isUniquePhoneViolation(e)) {
        throw DuplicatePhoneNumberException(trimmedPhone);
      }
      rethrow;
    }
  }

  bool _isUniquePhoneViolation(Object e) {
    final msg = e.toString().toLowerCase();
    return msg.contains('unique') &&
        (msg.contains('phone_number') || msg.contains('phonenumber'));
  }

  /// Adds a nickname / reference for an existing customer.
  Future<CustomerAlias> addAlias({
    required int customerId,
    required String alias,
  }) async {
    final trimmed = alias.trim();
    if (trimmed.isEmpty) {
      throw ArgumentError.value(alias, 'alias', 'Alias is required');
    }

    final id = await into(customerAliases).insert(
      CustomerAliasesCompanion.insert(customerId: customerId, alias: trimmed),
    );
    // Aliases ride on the customer payload — mark customer for re-push.
    await (update(customers)..where((c) => c.id.equals(customerId))).write(
      const CustomersCompanion(synced: Value(false)),
    );
    return (await (select(
      customerAliases,
    )..where((a) => a.id.equals(id))).getSingle());
  }

  /// Fuzzy match against primary name and all aliases, ranked by score.
  Future<CustomerSearchOutcome> searchCustomers(String query) async {
    final allCustomers = await select(customers).get();
    final allAliases = await select(customerAliases).get();

    final aliasesByCustomerId = <int, List<String>>{};
    for (final row in allAliases) {
      aliasesByCustomerId
          .putIfAbsent(row.customerId, () => <String>[])
          .add(row.alias);
    }

    return rankCustomerMatches(
      query: query,
      customers: allCustomers,
      aliasesByCustomerId: aliasesByCustomerId,
    );
  }

  /// Customers ordered by most recent transaction (never-transacted last).
  Future<List<Customer>> getCustomersByRecentActivity() async {
    return watchCustomersByRecentActivity().first.then(
      (items) => items.map((e) => e.customer).toList(),
    );
  }

  /// Live list for HomeScreen — updates when customers or transactions change.
  Stream<List<CustomerListItem>> watchCustomersByRecentActivity() {
    return customSelect(
      '''
      SELECT c.*, MAX(t.created_at) AS last_activity
      FROM customers AS c
      LEFT JOIN transactions AS t ON t.customer_id = c.id
      GROUP BY c.id
      ORDER BY MAX(t.created_at) DESC NULLS LAST, c.created_at DESC
      ''',
      readsFrom: {customers, transactions},
    ).watch().map((rows) {
      return rows.map((row) {
        final customer = Customer(
          id: row.read<int>('id'),
          name: row.read<String>('name'),
          phoneNumber: row.read<String>('phone_number'),
          photoPath: row.readNullable<String>('photo_path'),
          createdAt: row.read<DateTime>('created_at'),
          currentBalance: row.read<double>('current_balance'),
          supabaseId: row.readNullable<String>('supabase_id'),
          synced: row.read<bool>('synced'),
        );
        return CustomerListItem(
          customer: customer,
          lastActivityAt: row.readNullable<DateTime>('last_activity'),
        );
      }).toList();
    });
  }

  Stream<Customer?> watchCustomer(int id) {
    return (select(
      customers,
    )..where((c) => c.id.equals(id))).watchSingleOrNull();
  }

  Future<Customer?> getCustomer(int id) {
    return (select(customers)..where((c) => c.id.equals(id))).getSingleOrNull();
  }

  /// Permanently removes a customer khata and all related local rows.
  ///
  /// Returns the deleted customer (for remote cleanup / photo delete), or
  /// `null` if the id was already gone.
  Future<Customer?> deleteCustomer(int customerId) async {
    final customer = await getCustomer(customerId);
    if (customer == null) return null;

    await transaction(() async {
      final txnIds = await (select(
        transactions,
      )..where((t) => t.customerId.equals(customerId))).map((t) => t.id).get();

      if (txnIds.isNotEmpty) {
        // Clear self-FK before deleting so SQLite accepts the wipe.
        await (update(
          transactions,
        )..where((t) => t.customerId.equals(customerId))).write(
          const TransactionsCompanion(reversesTransactionId: Value(null)),
        );
        await (delete(
          transactionItems,
        )..where((i) => i.transactionId.isIn(txnIds))).go();
        await (delete(
          transactions,
        )..where((t) => t.customerId.equals(customerId))).go();
      }

      await (delete(
        customerAliases,
      )..where((a) => a.customerId.equals(customerId))).go();
      await (delete(customers)..where((c) => c.id.equals(customerId))).go();
    });

    return customer;
  }

  /// Replaces a pending or existing number. Validates uniqueness.
  Future<Customer> updateCustomerPhone({
    required int customerId,
    required String phoneNumber,
  }) async {
    final normalized = PhoneNumbers.normalize(phoneNumber);
    if (!PhoneNumbers.isValidPakistaniMobile(normalized)) {
      throw ArgumentError.value(
        phoneNumber,
        'phoneNumber',
        'Enter a valid Pakistani mobile (03XXXXXXXXX)',
      );
    }

    try {
      await (update(customers)..where((c) => c.id.equals(customerId))).write(
        CustomersCompanion(
          phoneNumber: Value(normalized),
          synced: const Value(false),
        ),
      );
    } catch (e) {
      if (_isUniquePhoneViolation(e)) {
        throw DuplicatePhoneNumberException(normalized);
      }
      rethrow;
    }

    return (await getCustomer(customerId))!;
  }

  Future<Customer> updateCustomerPhoto({
    required int customerId,
    required String photoPath,
  }) async {
    await (update(customers)..where((c) => c.id.equals(customerId))).write(
      CustomersCompanion(
        photoPath: Value(photoPath),
        synced: const Value(false),
      ),
    );
    return (await getCustomer(customerId))!;
  }

  /// Updates name / phone / photo / address / reference for an existing customer.
  Future<Customer> updateCustomerDetails({
    required int customerId,
    required String name,
    String? phoneNumber,
    bool numberPending = false,
    String? photoPath,
    bool clearPhoto = false,
    String? address,
    String? referenceNote,
  }) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) {
      throw ArgumentError.value(name, 'name', 'Name is required');
    }

    final trimmedAddress = address?.trim();
    final trimmedRef = referenceNote?.trim();

    String phone;
    if (numberPending) {
      phone = PhoneNumbers.createPendingPlaceholder();
    } else {
      final raw = phoneNumber?.trim() ?? '';
      phone = PhoneNumbers.normalize(raw);
      if (!PhoneNumbers.isValidPakistaniMobile(phone)) {
        throw ArgumentError.value(
          raw,
          'phoneNumber',
          'Enter a valid Pakistani mobile (03XXXXXXXXX)',
        );
      }
    }

    try {
      await (update(customers)..where((c) => c.id.equals(customerId))).write(
        CustomersCompanion(
          name: Value(trimmed),
          phoneNumber: Value(phone),
          address: Value(
            trimmedAddress == null || trimmedAddress.isEmpty
                ? null
                : trimmedAddress,
          ),
          referenceNote: Value(
            trimmedRef == null || trimmedRef.isEmpty ? null : trimmedRef,
          ),
          photoPath: clearPhoto
              ? const Value(null)
              : photoPath != null
              ? Value(photoPath)
              : const Value.absent(),
          synced: const Value(false),
        ),
      );
    } catch (e) {
      if (_isUniquePhoneViolation(e)) {
        throw DuplicatePhoneNumberException(phone);
      }
      rethrow;
    }

    if (trimmedRef != null &&
        trimmedRef.isNotEmpty &&
        trimmedRef.toLowerCase() != trimmed.toLowerCase()) {
      try {
        await addAlias(customerId: customerId, alias: trimmedRef);
      } catch (_) {}
    }

    return (await getCustomer(customerId))!;
  }

  // ---------------------------------------------------------------------------
  // Transactions (append-only; corrections only via [addCorrectingTransaction])
  // ---------------------------------------------------------------------------

  /// Inserts a new ledger entry and updates [Customers.currentBalance].
  ///
  /// Does **not** expose any way to mutate amount/type/customerId later.
  Future<Transaction> addTransaction({
    required int customerId,
    required double amount,
    required String type,
    String? note,
    String sourceType = TransactionSourceType.manual,
    List<TransactionItemInput> items = const [],
  }) async {
    _validateNewTransaction(amount: amount, type: type, sourceType: sourceType);

    return transaction(() async {
      final txnId = await into(transactions).insert(
        TransactionsCompanion.insert(
          customerId: customerId,
          amount: amount,
          type: type,
          note: Value(note),
          sourceType: Value(sourceType),
        ),
      );

      await _insertItems(txnId, items);
      await _applyBalanceDelta(customerId, type, amount);

      return (await (select(
        transactions,
      )..where((t) => t.id.equals(txnId))).getSingle());
    });
  }

  /// Only supported way to fix a mistake: void the original + insert offset.
  ///
  /// - Marks the original row `isVoided = true` (no other fields changed)
  /// - Inserts an opposite-type row with [reversesTransactionId] set
  /// - Adjusts balance using the new offsetting entry only
  Future<Transaction> addCorrectingTransaction({
    required int originalTransactionId,
    String? note,
    String sourceType = TransactionSourceType.manual,
  }) async {
    if (!TransactionSourceType.all.contains(sourceType)) {
      throw ArgumentError.value(sourceType, 'sourceType');
    }

    return transaction(() async {
      final original = await (select(
        transactions,
      )..where((t) => t.id.equals(originalTransactionId))).getSingleOrNull();

      if (original == null) {
        throw TransactionCorrectionException(
          'Transaction #$originalTransactionId was not found.',
        );
      }
      if (original.isVoided) {
        throw TransactionCorrectionException(
          'Transaction #$originalTransactionId is already voided.',
        );
      }
      if (original.reversesTransactionId != null) {
        throw TransactionCorrectionException(
          'Cannot void a correction row directly; void the original instead.',
        );
      }

      // Soft-void only — never mutate amount, type, or customerId.
      await (update(
        transactions,
      )..where((t) => t.id.equals(originalTransactionId))).write(
        const TransactionsCompanion(
          isVoided: Value(true),
          synced: Value(false),
        ),
      );

      final opposite = TransactionType.opposite(original.type);
      final correctionNote =
          note ?? 'Correction for transaction #$originalTransactionId';

      final correctionId = await into(transactions).insert(
        TransactionsCompanion.insert(
          customerId: original.customerId,
          amount: original.amount,
          type: opposite,
          note: Value(correctionNote),
          sourceType: Value(sourceType),
          reversesTransactionId: Value(originalTransactionId),
        ),
      );

      // Offsetting entry undoes the original balance impact.
      await _applyBalanceDelta(original.customerId, opposite, original.amount);

      return (await (select(
        transactions,
      )..where((t) => t.id.equals(correctionId))).getSingle());
    });
  }

  Future<List<TransactionWithItems>> getTransactionsForCustomer(
    int customerId,
  ) async {
    return watchTransactionsForCustomer(customerId).first;
  }

  Stream<List<TransactionWithItems>> watchTransactionsForCustomer(
    int customerId,
  ) {
    final txnQuery =
        (select(transactions)
              ..where((t) => t.customerId.equals(customerId))
              ..orderBy([
                (t) => OrderingTerm.desc(t.createdAt),
                (t) => OrderingTerm.desc(t.id),
              ]))
            .watch();

    return txnQuery.asyncMap((txns) async {
      if (txns.isEmpty) return const <TransactionWithItems>[];

      final ids = txns.map((t) => t.id).toList();
      final itemRows = await (select(
        transactionItems,
      )..where((i) => i.transactionId.isIn(ids))).get();

      final itemsByTxn = <int, List<TransactionItem>>{};
      for (final item in itemRows) {
        itemsByTxn.putIfAbsent(item.transactionId, () => []).add(item);
      }

      return [
        for (final txn in txns)
          TransactionWithItems(
            transaction: txn,
            items: itemsByTxn[txn.id] ?? const [],
          ),
      ];
    });
  }

  /// Rows not yet pushed to Supabase (local sync queue).
  Future<List<Transaction>> getUnsyncedTransactions() {
    return (select(transactions)
          ..where((t) => t.synced.equals(false))
          ..orderBy([(t) => OrderingTerm.asc(t.createdAt)]))
        .get();
  }

  Future<List<Customer>> getUnsyncedCustomers() {
    return (select(customers)
          ..where((c) => c.synced.equals(false))
          ..orderBy([(c) => OrderingTerm.asc(c.createdAt)]))
        .get();
  }

  Stream<int> watchPendingSyncCount() {
    return customSelect(
      '''
      SELECT
        (SELECT COUNT(*) FROM customers WHERE synced = 0) +
        (SELECT COUNT(*) FROM transactions WHERE synced = 0) AS pending
      ''',
      readsFrom: {customers, transactions},
    ).watch().map((rows) => rows.first.read<int>('pending'));
  }

  Future<void> markCustomerSynced({
    required int localId,
    required String supabaseId,
  }) {
    return (update(customers)..where((c) => c.id.equals(localId))).write(
      CustomersCompanion(
        supabaseId: Value(supabaseId),
        synced: const Value(true),
      ),
    );
  }

  Future<void> markTransactionSynced({
    required int localId,
    required String supabaseId,
  }) {
    return (update(transactions)..where((t) => t.id.equals(localId))).write(
      TransactionsCompanion(
        supabaseId: Value(supabaseId),
        synced: const Value(true),
      ),
    );
  }

  Future<List<String>> getAliasesForCustomer(int customerId) async {
    final rows = await (select(
      customerAliases,
    )..where((a) => a.customerId.equals(customerId))).get();
    return rows.map((r) => r.alias).toList();
  }

  Future<List<TransactionItem>> getItemsForTransaction(int transactionId) {
    return (select(
      transactionItems,
    )..where((i) => i.transactionId.equals(transactionId))).get();
  }

  /// Shop-wide: money still owed to the shopkeeper + money already received.
  Stream<ShopSummary> watchShopSummary() {
    return customSelect(
      '''
      SELECT
        (SELECT COALESCE(SUM(current_balance), 0)
           FROM customers
          WHERE current_balance > 0) AS total_owed,
        (SELECT COALESCE(SUM(amount), 0)
           FROM transactions
          WHERE type = 'payment_received'
            AND is_voided = 0
            AND reverses_transaction_id IS NULL) AS total_received
      ''',
      readsFrom: {customers, transactions},
    ).watch().map((rows) {
      final row = rows.first;
      return ShopSummary(
        totalOwed: row.read<num>('total_owed').toDouble(),
        totalReceived: row.read<num>('total_received').toDouble(),
      );
    });
  }

  /// Customers who still owe the shopkeeper (balance > 0), highest first.
  Stream<List<CustomerListItem>> watchOwingCustomers() {
    return watchCustomersByRecentActivity().map((items) {
      final owing = items.where((i) => i.currentBalance > 0).toList()
        ..sort((a, b) => b.currentBalance.compareTo(a.currentBalance));
      return owing;
    });
  }

  /// Genuine payment entries with customer + line items (newest first).
  Stream<List<TransactionWithCustomer>> watchReceivedPayments() {
    final txnQuery =
        (select(transactions)
              ..where(
                (t) =>
                    t.type.equals(TransactionType.paymentReceived) &
                    t.isVoided.equals(false) &
                    t.reversesTransactionId.isNull(),
              )
              ..orderBy([
                (t) => OrderingTerm.desc(t.createdAt),
                (t) => OrderingTerm.desc(t.id),
              ]))
            .watch();

    return txnQuery.asyncMap((txns) async {
      if (txns.isEmpty) return const <TransactionWithCustomer>[];

      final customerIds = txns.map((t) => t.customerId).toSet().toList();
      final txnIds = txns.map((t) => t.id).toList();

      final customerRows = await (select(
        customers,
      )..where((c) => c.id.isIn(customerIds))).get();
      final byCustomerId = {for (final c in customerRows) c.id: c};

      final itemRows = await (select(
        transactionItems,
      )..where((i) => i.transactionId.isIn(txnIds))).get();
      final itemsByTxn = <int, List<TransactionItem>>{};
      for (final item in itemRows) {
        itemsByTxn.putIfAbsent(item.transactionId, () => []).add(item);
      }

      return [
        for (final txn in txns)
          if (byCustomerId.containsKey(txn.customerId))
            TransactionWithCustomer(
              entry: TransactionWithItems(
                transaction: txn,
                items: itemsByTxn[txn.id] ?? const [],
              ),
              customer: byCustomerId[txn.customerId]!,
            ),
      ];
    });
  }

  // ---------------------------------------------------------------------------
  // Internals
  // ---------------------------------------------------------------------------

  void _validateNewTransaction({
    required double amount,
    required String type,
    required String sourceType,
  }) {
    if (amount <= 0) {
      throw ArgumentError.value(amount, 'amount', 'Amount must be positive');
    }
    if (!TransactionType.all.contains(type)) {
      throw ArgumentError.value(
        type,
        'type',
        'Must be credit_given or payment_received',
      );
    }
    if (!TransactionSourceType.all.contains(sourceType)) {
      throw ArgumentError.value(sourceType, 'sourceType');
    }
  }

  Future<void> _insertItems(
    int transactionId,
    List<TransactionItemInput> items,
  ) async {
    for (final item in items) {
      final name = item.itemName.trim();
      if (name.isEmpty) {
        throw ArgumentError('itemName is required for transaction items');
      }
      await into(transactionItems).insert(
        TransactionItemsCompanion.insert(
          transactionId: transactionId,
          itemName: name,
          quantity: Value(item.quantity),
          unit: Value(item.unit),
          price: Value(item.price),
        ),
      );
    }
  }

  Future<void> _applyBalanceDelta(
    int customerId,
    String type,
    double amount,
  ) async {
    final customer = await (select(
      customers,
    )..where((c) => c.id.equals(customerId))).getSingle();

    final delta = type == TransactionType.creditGiven ? amount : -amount;
    await (update(customers)..where((c) => c.id.equals(customerId))).write(
      CustomersCompanion(
        currentBalance: Value(customer.currentBalance + delta),
        synced: const Value(false),
      ),
    );
  }
}
