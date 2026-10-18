import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:khata_app/database/app_database.dart';
import 'package:khata_app/database/phone_numbers.dart';
import 'package:khata_app/database/tables.dart';
import 'package:khata_app/services/formatters.dart';
import 'package:path/path.dart' as p;

void main() {
  test('manual ledger flow: credit, payment, balance, persistence', () async {
    final dir = await Directory.systemTemp.createTemp('khata_flow_');
    final dbFile = File(p.join(dir.path, 'khata_test.sqlite'));

    Future<AppDatabase> open() async {
      return AppDatabase(
        executor: NativeDatabase(
          dbFile,
          setup: (raw) => raw.execute('PRAGMA foreign_keys = ON'),
        ),
      );
    }

    var db = await open();

    final customer = await db.addCustomer(
      name: 'Bilal Store',
      phoneNumber: '03001234567',
    );
    expect(PhoneNumbers.isPending(customer.phoneNumber), isFalse);

    await db.addTransaction(
      customerId: customer.id,
      amount: 1500,
      type: TransactionType.creditGiven,
      note: 'kirana',
    );

    var refreshed = (await db.getCustomer(customer.id))!;
    expect(refreshed.currentBalance, 1500);
    expect(formatRs(refreshed.currentBalance), 'Rs 1,500');

    await db.addTransaction(
      customerId: customer.id,
      amount: 500,
      type: TransactionType.paymentReceived,
    );

    refreshed = (await db.getCustomer(customer.id))!;
    expect(refreshed.currentBalance, 1000);
    expect(formatRs(refreshed.currentBalance), 'Rs 1,000');

    final history = await db.getTransactionsForCustomer(customer.id);
    expect(history.length, 2);
    expect(
      history.map((h) => h.transaction.amount),
      containsAll([1500, 500]),
    );
    // Newest / highest id first when timestamps collide.
    expect(history.first.transaction.id > history.last.transaction.id, isTrue);

    await db.close();

    // Force-close / reopen simulation
    db = await open();
    final again = (await db.getCustomer(customer.id))!;
    expect(again.name, 'Bilal Store');
    expect(again.currentBalance, 1000);
    expect((await db.getTransactionsForCustomer(customer.id)).length, 2);

    // Duplicate phone surfaces clearly
    expect(
      () => db.addCustomer(name: 'Other', phoneNumber: '03001234567'),
      throwsA(isA<DuplicatePhoneNumberException>()),
    );

    // Pending number explicit path
    final pending = await db.addCustomer(
      name: 'Pending Wala',
      phonePending: true,
    );
    expect(PhoneNumbers.isPending(pending.phoneNumber), isTrue);

    await db.close();
    await dir.delete(recursive: true);
  });
}
