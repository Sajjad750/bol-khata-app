import 'app_database.dart';
import 'customer_search.dart';

/// Shop-wide totals for the home screen.
class ShopSummary {
  const ShopSummary({required this.totalOwed, required this.totalReceived});

  /// Sum of positive customer balances (still to collect).
  final double totalOwed;

  /// Sum of genuine payment entries (money already received).
  final double totalReceived;
}

/// A ledger entry with its customer (for paid / received lists).
class TransactionWithCustomer {
  const TransactionWithCustomer({required this.entry, required this.customer});

  final TransactionWithItems entry;
  final Customer customer;

  Transaction get transaction => entry.transaction;
}
