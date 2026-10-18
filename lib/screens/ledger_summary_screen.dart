import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../database/customer_list_item.dart';
import '../database/phone_numbers.dart';
import '../database/shop_summary.dart';
import '../providers/database_providers.dart';
import '../providers/language_providers.dart';
import '../services/formatters.dart';
import '../theme/khata_colors.dart';
import '../widgets/customer_avatar.dart';
import 'customer_detail_screen.dart';
import 'transaction_detail_screen.dart';

enum LedgerSummaryKind { owed, received }

/// Lists who still owes the shopkeeper, or who already paid — with amounts/dates.
class LedgerSummaryScreen extends ConsumerWidget {
  const LedgerSummaryScreen({super.key, required this.kind});

  final LedgerSummaryKind kind;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(appStringsProvider);
    final isOwed = kind == LedgerSummaryKind.owed;

    return Scaffold(
      appBar: AppBar(
        title: Text(isOwed ? s.toCollectTitle : s.receivedTitle),
      ),
      body: isOwed
          ? _OwingBody(emptyLabel: s.noOneOwesYou)
          : _ReceivedBody(emptyLabel: s.noPaymentsYet),
    );
  }
}

class _OwingBody extends ConsumerWidget {
  const _OwingBody({required this.emptyLabel});

  final String emptyLabel;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(owingCustomersProvider);
    return async.when(
      skipLoadingOnReload: true,
      skipLoadingOnRefresh: true,
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('$e')),
      data: (items) {
        if (items.isEmpty) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Text(
                emptyLabel,
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 16, color: Colors.grey.shade600),
              ),
            ),
          );
        }
        return ListView.separated(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
          itemCount: items.length,
          separatorBuilder: (_, _) => const SizedBox(height: 8),
          itemBuilder: (context, index) {
            return _OwingTile(item: items[index]);
          },
        );
      },
    );
  }
}

class _OwingTile extends StatelessWidget {
  const _OwingTile({required this.item});

  final CustomerListItem item;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: KhataColors.softGrey,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () {
          Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => CustomerDetailScreen(customerId: item.id),
            ),
          );
        },
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              CustomerAvatar(
                name: item.name,
                photoPath: item.photoPath,
                radius: 24,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.name,
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      formatTimeAgo(item.lastActivityAt),
                      style: TextStyle(
                        fontSize: 13,
                        color: Colors.grey.shade600,
                      ),
                    ),
                    if (!item.isPhonePending)
                      Text(
                        PhoneNumbers.display(item.phoneNumber),
                        style: TextStyle(
                          fontSize: 13,
                          color: Colors.grey.shade600,
                        ),
                      ),
                  ],
                ),
              ),
              Text(
                formatRs(item.currentBalance),
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: KhataColors.primaryGreen,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ReceivedBody extends ConsumerWidget {
  const _ReceivedBody({required this.emptyLabel});

  final String emptyLabel;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(receivedPaymentsProvider);
    return async.when(
      skipLoadingOnReload: true,
      skipLoadingOnRefresh: true,
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('$e')),
      data: (items) {
        if (items.isEmpty) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Text(
                emptyLabel,
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 16, color: Colors.grey.shade600),
              ),
            ),
          );
        }
        return ListView.separated(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
          itemCount: items.length,
          separatorBuilder: (_, _) => const SizedBox(height: 8),
          itemBuilder: (context, index) {
            return _PaymentTile(row: items[index]);
          },
        );
      },
    );
  }
}

class _PaymentTile extends StatelessWidget {
  const _PaymentTile({required this.row});

  final TransactionWithCustomer row;

  @override
  Widget build(BuildContext context) {
    final txn = row.transaction;
    final items = row.entry.items;
    final preview = items.isEmpty
        ? null
        : items
            .map((i) {
              final price = i.price;
              if (price == null || price <= 0) return i.itemName;
              final p = price == price.roundToDouble()
                  ? price.toInt().toString()
                  : price.toStringAsFixed(2);
              return '${i.itemName} — Rs $p';
            })
            .join(', ');

    return Material(
      color: KhataColors.softGrey,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () {
          Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => TransactionDetailScreen(
                item: row.entry,
                customerName: row.customer.name,
              ),
            ),
          );
        },
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: const Color(0xFFFFF4E5),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.arrow_downward,
                  color: KhataColors.amber,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      row.customer.name,
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    if (preview != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        preview,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: Colors.grey.shade800),
                      ),
                    ],
                    const SizedBox(height: 4),
                    Text(
                      formatTxnDate(txn.createdAt),
                      style: TextStyle(
                        fontSize: 13,
                        color: Colors.grey.shade600,
                      ),
                    ),
                  ],
                ),
              ),
              Text(
                formatRs(txn.amount),
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: KhataColors.amber,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
