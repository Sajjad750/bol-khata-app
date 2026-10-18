import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../database/customer_search.dart';
import '../database/tables.dart';
import '../providers/database_providers.dart';
import '../providers/language_providers.dart';
import '../services/formatters.dart';
import '../theme/khata_colors.dart';
import '../utils/user_facing_error.dart';

/// Full detail for one ledger entry (amount, note, line items, meta).
class TransactionDetailScreen extends ConsumerWidget {
  const TransactionDetailScreen({
    super.key,
    required this.item,
    required this.customerName,
  });

  final TransactionWithItems item;
  final String customerName;

  Future<void> _confirmDelete(BuildContext context, WidgetRef ref) async {
    final s = ref.read(appStringsProvider);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(s.deleteEntryTitle),
        content: Text(s.deleteEntryMessage),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(s.cancel),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: KhataColors.debtRed),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(s.deleteKhataConfirm),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;

    try {
      await ref
          .read(databaseProvider)
          .addCorrectingTransaction(originalTransactionId: item.transaction.id);
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(s.entryDeleted)));
      Navigator.of(context).pop();
    } catch (e) {
      if (!context.mounted) return;
      showAppError(context, e);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(appStringsProvider);
    final txn = item.transaction;
    final isCredit = txn.type == TransactionType.creditGiven;
    final voided = txn.isVoided;
    final isCorrection = txn.reversesTransactionId != null;
    final canDelete = !voided && !isCorrection;
    final accent = isCredit ? KhataColors.primaryGreen : KhataColors.amber;
    final title = isCredit ? s.udharDiyaShort : s.paymentLiyaShort;

    return Scaffold(
      appBar: AppBar(
        title: Text(s.entryDetail),
        actions: [
          if (canDelete)
            IconButton(
              tooltip: s.deleteEntry,
              onPressed: () => _confirmDelete(context, ref),
              icon: const Icon(Icons.delete_outline),
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
        children: [
          Row(
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: isCredit
                      ? KhataColors.softGreen
                      : const Color(0xFFFFF4E5),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(
                  isCredit ? Icons.arrow_upward : Icons.arrow_downward,
                  color: accent,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Text(
                      customerName,
                      style: TextStyle(
                        fontSize: 15,
                        color: Colors.grey.shade700,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Text(
            formatRs(txn.amount),
            style: TextStyle(
              fontSize: 40,
              fontWeight: FontWeight.w800,
              color: accent,
              decoration: voided ? TextDecoration.lineThrough : null,
            ),
          ),
          if (voided || isCorrection) ...[
            const SizedBox(height: 8),
            Text(
              voided
                  ? 'This entry was voided'
                  : 'Correction of entry #${txn.reversesTransactionId}',
              style: TextStyle(
                fontWeight: FontWeight.w700,
                color: voided ? KhataColors.debtRed : KhataColors.amber,
              ),
            ),
          ],
          const SizedBox(height: 24),
          _SectionCard(
            children: [
              _DetailRow(label: 'Date', value: formatTxnDate(txn.createdAt)),
              _DetailRow(
                label: 'Type',
                value: isCredit ? 'Udhar (credit given)' : 'Payment received',
              ),
              _DetailRow(
                label: 'Source',
                value: txn.sourceType == TransactionSourceType.voice
                    ? 'Voice entry'
                    : 'Manual entry',
              ),
              if (txn.note != null && txn.note!.trim().isNotEmpty)
                _DetailRow(label: 'Note', value: txn.note!.trim()),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            s.items,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: Colors.grey.shade800,
            ),
          ),
          const SizedBox(height: 8),
          if (item.items.isEmpty)
            _SectionCard(
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Text(
                    isCredit
                        ? 'No item breakdown — plain udhar amount.'
                        : 'No item breakdown — plain payment amount.',
                    style: TextStyle(fontSize: 15, color: Colors.grey.shade700),
                  ),
                ),
              ],
            )
          else
            _SectionCard(
              children: [
                for (var i = 0; i < item.items.length; i++) ...[
                  if (i > 0) const Divider(height: 20),
                  _ItemRow(item: item.items[i]),
                ],
              ],
            ),
        ],
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: KhataColors.softGrey,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: children,
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 88,
            child: Text(
              label,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: Colors.grey.shade600,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}

class _ItemRow extends StatelessWidget {
  const _ItemRow({required this.item});

  final dynamic item;

  @override
  Widget build(BuildContext context) {
    final qty = item.quantity as double?;
    final unit = (item.unit as String?)?.trim();
    final price = item.price as double?;
    final name = item.itemName as String;

    final qtyPart = () {
      if (qty == null) return null;
      final q = qty == qty.roundToDouble()
          ? qty.toInt().toString()
          : qty.toString();
      return unit != null && unit.isNotEmpty ? '$q $unit' : q;
    }();

    return Row(
      children: [
        Icon(Icons.shopping_bag_outlined, color: Colors.grey.shade600),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                name,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
              if (qtyPart != null)
                Text(qtyPart, style: TextStyle(color: Colors.grey.shade700)),
            ],
          ),
        ),
        if (price != null && price > 0)
          Text(
            formatRs(price),
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: KhataColors.primaryGreen,
            ),
          ),
      ],
    );
  }
}
