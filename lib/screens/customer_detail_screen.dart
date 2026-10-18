import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import 'dart:io';

import '../database/app_database.dart';
import '../database/customer_search.dart';
import '../database/phone_numbers.dart';
import '../database/tables.dart';
import '../providers/database_providers.dart';
import '../providers/language_providers.dart';
import '../services/formatters.dart';
import '../services/photo_storage.dart';
import '../services/sync_service.dart';
import '../theme/khata_colors.dart';
import '../utils/user_facing_error.dart';
import '../widgets/amount_entry_sheet.dart';
import '../widgets/customer_avatar.dart';
import '../widgets/voice_entry_button.dart';
import 'edit_customer_screen.dart';
import 'transaction_detail_screen.dart';
import 'voice_confirm_screen.dart';

class CustomerDetailScreen extends ConsumerWidget {
  const CustomerDetailScreen({super.key, required this.customerId});

  final int customerId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final customerAsync = ref.watch(customerProvider(customerId));
    final txnsAsync = ref.watch(customerTransactionsProvider(customerId));

    return customerAsync.when(
      skipLoadingOnReload: true,
      skipLoadingOnRefresh: true,
      loading: () => const Scaffold(body: SizedBox.shrink()),
      error: (e, _) => Scaffold(
        appBar: AppBar(),
        body: Center(child: Text('Error: $e')),
      ),
      data: (customer) {
        if (customer == null) {
          return Scaffold(
            appBar: AppBar(),
            body: const Center(child: Text('Customer not found')),
          );
        }

        final balance = customer.currentBalance;
        final balanceColor = balance > 0
            ? KhataColors.primaryGreen
            : balance < 0
                ? KhataColors.debtRed
                : Colors.grey.shade700;

        return Scaffold(
          appBar: AppBar(
            title: Text(ref.watch(appStringsProvider).customer),
            actions: [
              IconButton(
                tooltip: ref.watch(appStringsProvider).editCustomer,
                onPressed: () {
                  Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) =>
                          EditCustomerScreen(customerId: customer.id),
                    ),
                  );
                },
                icon: const Icon(Icons.edit_outlined),
              ),
              IconButton(
                tooltip: ref.watch(appStringsProvider).addChangePhoto,
                onPressed: () => _pickPhoto(context, ref, customer),
                icon: const Icon(Icons.photo_camera_outlined),
              ),
              IconButton(
                tooltip: ref.watch(appStringsProvider).deleteKhata,
                onPressed: () => _confirmDeleteKhata(context, ref, customer),
                icon: const Icon(Icons.delete_outline),
              ),
            ],
          ),
          body: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
                child: Column(
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Expanded(child: SizedBox.shrink()),
                        Column(
                          children: [
                            GestureDetector(
                              onTap: () => _pickPhoto(context, ref, customer),
                              child: CustomerAvatar(
                                name: customer.name,
                                photoPath: customer.photoPath,
                                radius: 48,
                              ),
                            ),
                          ],
                        ),
                        Expanded(
                          child: Align(
                            alignment: Alignment.topCenter,
                            child: Padding(
                              padding: const EdgeInsets.only(top: 18),
                              child: _ManualAddAction(
                                label: ref.watch(appStringsProvider).add,
                                tooltip: ref
                                    .watch(appStringsProvider)
                                    .addProductsDetails,
                                onTap: () {
                                  Navigator.of(context).push(
                                    MaterialPageRoute<bool>(
                                      builder: (_) =>
                                          VoiceConfirmScreen.manualForCustomer(
                                        customerId: customer.id,
                                        customerName: customer.name,
                                      ),
                                    ),
                                  );
                                },
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    Text(
                      customer.name,
                      style: const TextStyle(
                        fontSize: 26,
                        fontWeight: FontWeight.w700,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    if (customer.address != null &&
                        customer.address!.trim().isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        customer.address!.trim(),
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 14,
                          color: Colors.grey.shade700,
                        ),
                      ),
                    ],
                    const SizedBox(height: 4),
                    if (PhoneNumbers.isPending(customer.phoneNumber))
                      TextButton(
                        onPressed: () =>
                            _promptPhone(context, ref, customer.id),
                        child: const Text('Add number'),
                      )
                    else
                      Text(
                        customer.phoneNumber,
                        style: TextStyle(
                          fontSize: 15,
                          color: Colors.grey.shade700,
                        ),
                      ),
                    if (customer.referenceNote != null &&
                        customer.referenceNote!.trim().isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        customer.referenceNote!.trim(),
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 13,
                          fontStyle: FontStyle.italic,
                          color: Colors.grey.shade600,
                        ),
                      ),
                    ],
                    const SizedBox(height: 10),
                    Text(
                      formatRs(balance),
                      style: TextStyle(
                        fontSize: 34,
                        fontWeight: FontWeight.w800,
                        color: balanceColor,
                      ),
                    ),
                    Text(
                      balance > 0
                          ? ref.watch(appStringsProvider).customerOwesYou
                          : balance < 0
                              ? ref.watch(appStringsProvider).youOweCustomer
                              : ref.watch(appStringsProvider).settled,
                      style: TextStyle(
                        fontSize: 13,
                        color: Colors.grey.shade600,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              Expanded(
                child: txnsAsync.when(
                  skipLoadingOnReload: true,
                  skipLoadingOnRefresh: true,
                  loading: () => const SizedBox.shrink(),
                  error: (e, _) => Center(child: Text('$e')),
                  data: (txns) {
                    if (txns.isEmpty) {
                      return Center(
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: Text(
                            ref.watch(appStringsProvider).noKhataEntries,
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 16,
                              color: Colors.grey.shade600,
                              height: 1.4,
                            ),
                          ),
                        ),
                      );
                    }
                    return ListView.separated(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                      itemCount: txns.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 8),
                      itemBuilder: (context, index) {
                        return _TxnTile(
                          item: txns[index],
                          customerName: customer.name,
                        );
                      },
                    );
                  },
                ),
              ),
              Material(
                elevation: 8,
                shadowColor: Colors.black26,
                color: Colors.white,
                child: SafeArea(
                  top: false,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                    // Physical LTR so mic stays thumb-friendly on the right,
                    // next to Udhar — independent of Urdu RTL chrome.
                    child: Row(
                      textDirection: TextDirection.ltr,
                      children: [
                        Expanded(
                          child: SizedBox(
                            height: 56,
                            child: FilledButton(
                              style: FilledButton.styleFrom(
                                backgroundColor: KhataColors.amber,
                              ),
                              onPressed: () => showAmountEntrySheet(
                                context: context,
                                title: ref.read(appStringsProvider).paymentLiya,
                                type: TransactionType.paymentReceived,
                                onSave: (amount, note) async {
                                  await ref.read(databaseProvider).addTransaction(
                                        customerId: customerId,
                                        amount: amount,
                                        type: TransactionType.paymentReceived,
                                        note: note,
                                      );
                                },
                              ),
                              child: Text(
                                ref.watch(appStringsProvider).paymentLiya,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: SizedBox(
                            height: 56,
                            child: FilledButton(
                              style: FilledButton.styleFrom(
                                backgroundColor: KhataColors.primaryGreen,
                              ),
                              onPressed: () => showAmountEntrySheet(
                                context: context,
                                title: ref.read(appStringsProvider).udharDiya,
                                type: TransactionType.creditGiven,
                                onSave: (amount, note) async {
                                  await ref.read(databaseProvider).addTransaction(
                                        customerId: customerId,
                                        amount: amount,
                                        type: TransactionType.creditGiven,
                                        note: note,
                                      );
                                },
                              ),
                              child: Text(
                                ref.watch(appStringsProvider).udharDiya,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        VoiceEntryButton(
                          compact: true,
                          showLabel: false,
                          lockedCustomerId: customer.id,
                          lockedCustomerName: customer.name,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _confirmDeleteKhata(
    BuildContext context,
    WidgetRef ref,
    Customer customer,
  ) async {
    final s = ref.read(appStringsProvider);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(s.deleteKhataTitle),
        content: Text(s.deleteKhataMessage(customer.name)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(s.cancel),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: KhataColors.debtRed,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(s.deleteKhataConfirm),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;

    try {
      final deleted =
          await ref.read(databaseProvider).deleteCustomer(customer.id);
      final photoPath = deleted?.photoPath ?? customer.photoPath;
      if (photoPath != null && photoPath.isNotEmpty) {
        try {
          final file = File(photoPath);
          if (await file.exists()) await file.delete();
        } catch (_) {}
      }
      await SyncService.deleteRemoteCustomer(
        deleted?.supabaseId ?? customer.supabaseId,
      );
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(s.khataDeleted)),
      );
      Navigator.of(context).pop();
    } catch (e) {
      if (!context.mounted) return;
      showAppError(context, e);
    }
  }

  Future<void> _pickPhoto(
    BuildContext context,
    WidgetRef ref,
    Customer customer,
  ) async {
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_camera),
              title: const Text('Camera'),
              onTap: () => Navigator.pop(ctx, ImageSource.camera),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library),
              title: const Text('Gallery'),
              onTap: () => Navigator.pop(ctx, ImageSource.gallery),
            ),
          ],
        ),
      ),
    );
    if (source == null) return;

    final picked = await ImagePicker().pickImage(
      source: source,
      maxWidth: 1200,
      imageQuality: 85,
    );
    if (picked == null) return;

    final path = await persistCustomerPhoto(picked.path);
    await ref.read(databaseProvider).updateCustomerPhoto(
          customerId: customer.id,
          photoPath: path,
        );
  }

  Future<void> _promptPhone(
    BuildContext context,
    WidgetRef ref,
    int customerId,
  ) async {
    final controller = TextEditingController();
    String? error;

    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setState) {
            return AlertDialog(
              title: const Text('Add phone number'),
              content: TextField(
                controller: controller,
                keyboardType: TextInputType.phone,
                decoration: InputDecoration(
                  hintText: '03XXXXXXXXX',
                  errorText: error,
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: () async {
                    final value = controller.text.trim();
                    if (!PhoneNumbers.isValidPakistaniMobile(value)) {
                      setState(() {
                        error =
                            'Enter a valid Pakistani mobile (03XXXXXXXXX)';
                      });
                      return;
                    }
                    try {
                      await ref.read(databaseProvider).updateCustomerPhone(
                            customerId: customerId,
                            phoneNumber: value,
                          );
                      if (ctx.mounted) Navigator.pop(ctx, true);
                    } on DuplicatePhoneNumberException catch (e) {
                      setState(() => error = e.toString());
                    } catch (e) {
                      setState(() => error = e.toString());
                    }
                  },
                  child: const Text('Save'),
                ),
              ],
            );
          },
        );
      },
    );

    if (saved == true && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Phone number saved')),
      );
    }
  }
}

class _ManualAddAction extends StatelessWidget {
  const _ManualAddAction({
    required this.onTap,
    required this.label,
    required this.tooltip,
  });

  final VoidCallback onTap;
  final String label;
  final String tooltip;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Tooltip(
          message: tooltip,
          child: Material(
            color: KhataColors.softGreen,
            shape: const CircleBorder(),
            elevation: 2,
            shadowColor: KhataColors.primaryGreen.withValues(alpha: 0.25),
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: onTap,
              child: Container(
                width: 56,
                height: 56,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: KhataColors.primaryGreen,
                    width: 1.5,
                  ),
                ),
                child: const Icon(
                  Icons.playlist_add_outlined,
                  color: KhataColors.primaryGreen,
                  size: 28,
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 6),
        Text(
          label,
          style: TextStyle(
            color: Colors.grey.shade700,
            fontWeight: FontWeight.w700,
            fontSize: 12,
          ),
        ),
      ],
    );
  }
}

class _TxnTile extends StatelessWidget {
  const _TxnTile({
    required this.item,
    required this.customerName,
  });

  final TransactionWithItems item;
  final String customerName;

  @override
  Widget build(BuildContext context) {
    final txn = item.transaction;
    final isCredit = txn.type == TransactionType.creditGiven;
    final voided = txn.isVoided;
    final isCorrection = txn.reversesTransactionId != null;
    final hasNote = txn.note != null && txn.note!.trim().isNotEmpty;
    final itemPreview = item.items.isEmpty
        ? null
        : item.items
            .map((i) {
              final qty = i.quantity;
              final unit = i.unit?.trim();
              final price = i.price;
              final namePart = () {
                if (qty == null) return i.itemName;
                final q = qty == qty.roundToDouble()
                    ? qty.toInt().toString()
                    : qty.toString();
                return unit != null && unit.isNotEmpty
                    ? '${i.itemName} ($q $unit)'
                    : '${i.itemName} ($q)';
              }();
              if (price == null || price <= 0) return namePart;
              final p = price == price.roundToDouble()
                  ? price.toInt().toString()
                  : price.toStringAsFixed(2);
              return '$namePart — Rs $p';
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
                item: item,
                customerName: customerName,
              ),
            ),
          );
        },
        child: Opacity(
          opacity: voided ? 0.45 : 1,
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: isCredit
                        ? KhataColors.softGreen
                        : const Color(0xFFFFF4E5),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    isCredit ? Icons.arrow_upward : Icons.arrow_downward,
                    color:
                        isCredit ? KhataColors.primaryGreen : KhataColors.amber,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        isCredit ? 'Udhar diya' : 'Payment liya',
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      if (itemPreview != null) ...[
                        const SizedBox(height: 2),
                        Text(
                          itemPreview,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(color: Colors.grey.shade800),
                        ),
                      ] else if (hasNote)
                        Text(
                          txn.note!,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(color: Colors.grey.shade700),
                        ),
                      const SizedBox(height: 4),
                      Text(
                        formatTxnDate(txn.createdAt),
                        style: TextStyle(
                          fontSize: 13,
                          color: Colors.grey.shade600,
                        ),
                      ),
                      if (voided || isCorrection) ...[
                        const SizedBox(height: 4),
                        Text(
                          voided
                              ? 'Voided'
                              : 'Correction of #${txn.reversesTransactionId}',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: voided
                                ? KhataColors.debtRed
                                : KhataColors.amber,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      formatRs(txn.amount),
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        color: isCredit
                            ? KhataColors.primaryGreen
                            : KhataColors.amber,
                        decoration:
                            voided ? TextDecoration.lineThrough : null,
                      ),
                    ),
                    Icon(
                      Icons.chevron_right,
                      color: Colors.grey.shade500,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
