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

  test('offline writes stay local; sync flags and id mapping work', () async {
    final customer = await db.addCustomer(
      name: 'Offline Ali',
      phoneNumber: '03005554433',
    );
    expect(customer.synced, isFalse);
    expect(customer.supabaseId, isNull);

    await db.addTransaction(
      customerId: customer.id,
      amount: 750,
      type: TransactionType.creditGiven,
      note: 'airplane mode',
      items: const [
        TransactionItemInput(itemName: 'atta', quantity: 10, unit: 'kg'),
      ],
    );

    final pendingCustomers = await db.getUnsyncedCustomers();
    final pendingTxns = await db.getUnsyncedTransactions();
    expect(pendingCustomers.length, 1);
    expect(pendingTxns.length, 1);
    expect(pendingTxns.first.synced, isFalse);

    // Simulate successful cloud push: store remote UUID mapping.
    await db.markCustomerSynced(
      localId: customer.id,
      supabaseId: '11111111-1111-1111-1111-111111111111',
    );
    await db.markTransactionSynced(
      localId: pendingTxns.first.id,
      supabaseId: '22222222-2222-2222-2222-222222222222',
    );

    expect(await db.getUnsyncedCustomers(), isEmpty);
    expect(await db.getUnsyncedTransactions(), isEmpty);

    final syncedCustomer = (await db.getCustomer(customer.id))!;
    expect(syncedCustomer.supabaseId, '11111111-1111-1111-1111-111111111111');
    expect(syncedCustomer.synced, isTrue);
    expect(syncedCustomer.currentBalance, 750);

    // New local write marks customer unsynced again (balance changed).
    await db.addTransaction(
      customerId: customer.id,
      amount: 100,
      type: TransactionType.paymentReceived,
    );
    expect((await db.getCustomer(customer.id))!.synced, isFalse);
    expect((await db.getUnsyncedTransactions()).length, 1);

    final pendingCount = await db.watchPendingSyncCount().first;
    expect(pendingCount, greaterThanOrEqualTo(2)); // customer + txn
  });
}
