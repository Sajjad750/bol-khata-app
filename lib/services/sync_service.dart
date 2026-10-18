import 'dart:async';

import 'package:flutter/widgets.dart';

import '../database/app_database.dart';
import 'supabase_service.dart';

/// Background push of local Drift rows to Supabase.
///
/// All user-facing reads/writes stay on Drift. Failures are silent.
class SyncService with WidgetsBindingObserver {
  SyncService(this._db);

  final AppDatabase _db;

  Timer? _timer;
  bool _running = false;
  bool _tickInFlight = false;

  static const _interval = Duration(seconds: 30);

  void start() {
    if (_running) return;
    _running = true;
    WidgetsBinding.instance.addObserver(this);
    unawaited(syncNow());
    _timer = Timer.periodic(_interval, (_) => unawaited(syncNow()));
  }

  void stop() {
    _running = false;
    _timer?.cancel();
    _timer = null;
    WidgetsBinding.instance.removeObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(syncNow());
    }
  }

  /// One sync cycle. Never throws to callers.
  Future<void> syncNow() async {
    if (_tickInFlight) return;
    _tickInFlight = true;
    try {
      final ready = await SupabaseService.ensureInitialized();
      if (!ready) return;

      final userId = SupabaseService.userId;
      if (userId == null) return;

      await _pushCustomers(userId);
      await _pushTransactions(userId);
    } catch (_) {
      // Silent — offline or API errors retry next cycle.
    } finally {
      _tickInFlight = false;
    }
  }

  /// Best-effort remote delete after a local khata wipe. Never throws.
  static Future<void> deleteRemoteCustomer(String? supabaseId) async {
    if (supabaseId == null || supabaseId.isEmpty) return;
    try {
      final ready = await SupabaseService.ensureInitialized();
      if (!ready) return;
      final userId = SupabaseService.userId;
      if (userId == null) return;
      await SupabaseService.client
          .from('customers')
          .delete()
          .eq('id', supabaseId)
          .eq('user_id', userId);
    } catch (_) {
      // Local delete already succeeded; remote can lag.
    }
  }

  Future<void> _pushCustomers(String userId) async {
    final pending = await _db.getUnsyncedCustomers();
    final client = SupabaseService.client;

    for (final customer in pending) {
      try {
        final aliases = await _db.getAliasesForCustomer(customer.id);
        final payload = {
          'user_id': userId,
          'local_id': customer.id,
          'name': customer.name,
          'phone_number': customer.phoneNumber,
          'photo_path': customer.photoPath,
          'address': customer.address,
          'reference_note': customer.referenceNote,
          'created_at': customer.createdAt.toUtc().toIso8601String(),
          'current_balance': customer.currentBalance,
          'aliases': aliases,
        };

        Map<String, dynamic> row;
        if (customer.supabaseId != null && customer.supabaseId!.isNotEmpty) {
          row = Map<String, dynamic>.from(
            await client
                .from('customers')
                .update(payload)
                .eq('id', customer.supabaseId!)
                .eq('user_id', userId)
                .select()
                .single(),
          );
        } else {
          row = Map<String, dynamic>.from(
            await client
                .from('customers')
                .upsert(payload, onConflict: 'user_id,local_id')
                .select()
                .single(),
          );
        }

        final remoteId = row['id']?.toString();
        if (remoteId == null || remoteId.isEmpty) continue;

        await _db.markCustomerSynced(
          localId: customer.id,
          supabaseId: remoteId,
        );
      } catch (_) {
        // Leave unsynced; retry later.
      }
    }
  }

  Future<void> _pushTransactions(String userId) async {
    final pending = await _db.getUnsyncedTransactions();
    final client = SupabaseService.client;

    for (final txn in pending) {
      try {
        final customer = await _db.getCustomer(txn.customerId);
        if (customer == null) continue;

        // Customer must exist remotely first (id mapping).
        var remoteCustomerId = customer.supabaseId;
        if (remoteCustomerId == null || remoteCustomerId.isEmpty) {
          await _pushCustomers(userId);
          final refreshed = await _db.getCustomer(txn.customerId);
          remoteCustomerId = refreshed?.supabaseId;
          if (remoteCustomerId == null || remoteCustomerId.isEmpty) {
            continue;
          }
        }

        String? remoteReversalId;
        if (txn.reversesTransactionId != null) {
          final original =
              await (_db.select(_db.transactions)
                    ..where((t) => t.id.equals(txn.reversesTransactionId!)))
                  .getSingleOrNull();
          remoteReversalId = original?.supabaseId;
        }

        final items = await _db.getItemsForTransaction(txn.id);
        final payload = {
          'user_id': userId,
          'local_id': txn.id,
          'customer_id': remoteCustomerId,
          'local_customer_id': txn.customerId,
          'amount': txn.amount,
          'type': txn.type,
          'note': txn.note,
          'created_at': txn.createdAt.toUtc().toIso8601String(),
          'source_type': txn.sourceType,
          'reverses_local_id': txn.reversesTransactionId,
          'reverses_transaction_id': remoteReversalId,
          'is_voided': txn.isVoided,
          'items': [
            for (final item in items)
              {
                'itemName': item.itemName,
                'quantity': item.quantity,
                'unit': item.unit,
                'price': item.price,
              },
          ],
        };

        Map<String, dynamic> row;
        if (txn.supabaseId != null && txn.supabaseId!.isNotEmpty) {
          row = Map<String, dynamic>.from(
            await client
                .from('transactions')
                .update(payload)
                .eq('id', txn.supabaseId!)
                .eq('user_id', userId)
                .select()
                .single(),
          );
        } else {
          row = Map<String, dynamic>.from(
            await client
                .from('transactions')
                .upsert(payload, onConflict: 'user_id,local_id')
                .select()
                .single(),
          );
        }

        final remoteId = row['id']?.toString();
        if (remoteId == null || remoteId.isEmpty) continue;

        await _db.markTransactionSynced(localId: txn.id, supabaseId: remoteId);
      } catch (_) {
        // Silent retry next cycle.
      }
    }
  }
}
