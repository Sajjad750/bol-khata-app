import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../database/app_database.dart';
import '../database/customer_list_item.dart';
import '../database/customer_search.dart';
import '../database/shop_summary.dart';
import 'auth_providers.dart';

export 'auth_providers.dart'
    show
        databaseProvider,
        syncServiceProvider,
        authControllerProvider,
        localLockServiceProvider,
        AuthRoute,
        AuthSessionState,
        AuthController;

final customersProvider = StreamProvider<List<CustomerListItem>>((ref) {
  return ref.watch(databaseProvider).watchCustomersByRecentActivity();
});

final shopSummaryProvider = StreamProvider<ShopSummary>((ref) {
  return ref.watch(databaseProvider).watchShopSummary();
});

final owingCustomersProvider = StreamProvider<List<CustomerListItem>>((ref) {
  return ref.watch(databaseProvider).watchOwingCustomers();
});

final receivedPaymentsProvider = StreamProvider<List<TransactionWithCustomer>>((
  ref,
) {
  return ref.watch(databaseProvider).watchReceivedPayments();
});

final customerProvider = StreamProvider.family<Customer?, int>((
  ref,
  customerId,
) {
  return ref.watch(databaseProvider).watchCustomer(customerId);
});

final customerTransactionsProvider =
    StreamProvider.family<List<TransactionWithItems>, int>((ref, customerId) {
      return ref
          .watch(databaseProvider)
          .watchTransactionsForCustomer(customerId);
    });

/// Count of local rows waiting to push to Supabase (customers + transactions).
final pendingSyncCountProvider = StreamProvider<int>((ref) {
  final route = ref.watch(authControllerProvider).route;
  if (route != AuthRoute.home) {
    return Stream.value(0);
  }
  return ref.watch(databaseProvider).watchPendingSyncCount();
});
