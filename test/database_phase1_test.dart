import 'package:flutter_test/flutter_test.dart';
import 'package:khata_app/database/app_database.dart';
import 'package:khata_app/database/tables.dart';

void main() {
  late AppDatabase db;

  setUp(() {
    db = AppDatabase.memory();
  });

  tearDown(() async {
    await db.close();
  });

  test('phone uniqueness, correction flow, and ambiguous fuzzy search', () async {
    // Two "Ahmed"s — different phones, overlapping aliases.
    final ahmed1 = await db.addCustomer(
      name: 'Ahmed Khan',
      phoneNumber: '03001234567',
      photoPath: '/photos/ahmed_khan.jpg',
      aliases: ['cycle wala Ahmed', 'Ahmed bhai'],
    );

    final ahmed2 = await db.addCustomer(
      name: 'Ahmed Ali',
      phoneNumber: '03009876543',
      photoPath: '/photos/ahmed_ali.jpg',
      aliases: ['corner wala Ahmed', 'Ahmed bhai'],
    );

    // Duplicate phone must fail clearly for the UI.
    expect(
      () => db.addCustomer(name: 'Someone Else', phoneNumber: '03001234567'),
      throwsA(isA<DuplicatePhoneNumberException>()),
    );

    // Credit given → balance increases.
    final original = await db.addTransaction(
      customerId: ahmed1.id,
      amount: 500,
      type: TransactionType.creditGiven,
      note: 'for rice and oil',
      items: const [
        TransactionItemInput(itemName: 'chawal', quantity: 5, unit: 'kg'),
        TransactionItemInput(itemName: 'cheeni', quantity: 2, unit: 'kg'),
      ],
    );

    var customer = await (db.select(
      db.customers,
    )..where((c) => c.id.equals(ahmed1.id))).getSingle();
    expect(customer.currentBalance, 500);

    // Correction voids original and inserts offsetting payment.
    final correction = await db.addCorrectingTransaction(
      originalTransactionId: original.id,
      note: 'Entered wrong amount by mistake',
    );

    customer = await (db.select(
      db.customers,
    )..where((c) => c.id.equals(ahmed1.id))).getSingle();
    expect(customer.currentBalance, 0);
    expect(correction.reversesTransactionId, original.id);
    expect(correction.type, TransactionType.paymentReceived);

    final history = await db.getTransactionsForCustomer(ahmed1.id);
    expect(history.length, 2);
    expect(history.any((h) => h.isVoided), isTrue);
    expect(history.any((h) => h.isCorrection), isTrue);
    expect(
      history.firstWhere((h) => h.transaction.id == original.id).items.length,
      2,
    );

    // Shared alias "Ahmed bhai" should be ambiguous across both customers.
    final search = await db.searchCustomers('Ahmed bhai');

    expect(search.matches.length, greaterThanOrEqualTo(2));
    expect(search.ambiguous, isTrue);
    expect(
      search.matches.map((m) => m.phoneNumber),
      containsAll([ahmed1.phoneNumber, ahmed2.phoneNumber]),
    );

    final unsynced = await db.getUnsyncedTransactions();
    expect(unsynced.length, greaterThanOrEqualTo(2));
    expect(unsynced.every((t) => !t.synced), isTrue);

    final recent = await db.getCustomersByRecentActivity();
    expect(recent.first.id, ahmed1.id);

    // Foreign keys enforced offline (invalid customer_id must fail).
    expect(
      () => db
          .into(db.customerAliases)
          .insert(
            CustomerAliasesCompanion.insert(customerId: 999999, alias: 'ghost'),
          ),
      throwsA(anything),
    );

    final schema = await db
        .customSelect(
          "SELECT sql FROM sqlite_master WHERE type = 'table' AND name != 'sqlite_sequence'",
        )
        .get();
    final ddl = schema.map((r) => r.read<String>('sql')).join('\n');
    expect(ddl.toUpperCase(), contains('FOREIGN KEY'));
    expect(ddl.toUpperCase(), contains('UNIQUE'));
  });
}
