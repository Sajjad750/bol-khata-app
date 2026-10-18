import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../database/customer_list_item.dart';
import '../database/phone_numbers.dart';
import '../providers/database_providers.dart';
import '../services/formatters.dart';
import '../theme/khata_colors.dart';
import '../widgets/customer_avatar.dart';
import 'add_customer_screen.dart';
import 'customer_detail_screen.dart';
import 'edit_customer_screen.dart';

/// All customers — browse, search, open khata, or edit details.
class CustomersScreen extends ConsumerStatefulWidget {
  const CustomersScreen({super.key});

  @override
  ConsumerState<CustomersScreen> createState() => _CustomersScreenState();
}

class _CustomersScreenState extends ConsumerState<CustomersScreen> {
  final _searchCtrl = TextEditingController();

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  List<CustomerListItem> _filtered(List<CustomerListItem> source) {
    final q = _searchCtrl.text.trim().toLowerCase();
    final list = q.isEmpty
        ? List<CustomerListItem>.from(source)
        : source.where((item) {
            final phone = PhoneNumbers.display(item.phoneNumber).toLowerCase();
            return item.name.toLowerCase().contains(q) || phone.contains(q);
          }).toList();
    list.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return list;
  }

  Future<void> _openEdit(int customerId) async {
    await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (_) => EditCustomerScreen(customerId: customerId),
      ),
    );
  }

  void _openKhata(int customerId) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => CustomerDetailScreen(customerId: customerId),
      ),
    );
  }

  void _openAdd() {
    Navigator.of(
      context,
    ).push(MaterialPageRoute<void>(builder: (_) => const AddCustomerScreen()));
  }

  @override
  Widget build(BuildContext context) {
    final customersAsync = ref.watch(customersProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Customers'),
        actions: [
          IconButton(
            tooltip: 'Add customer',
            onPressed: _openAdd,
            icon: const Icon(Icons.person_add_alt_1),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _openAdd,
        icon: const Icon(Icons.person_add_alt_1),
        label: const Text('Add'),
      ),
      body: customersAsync.when(
        skipLoadingOnReload: true,
        skipLoadingOnRefresh: true,
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('$e')),
        data: (all) {
          final customers = _filtered(all);
          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                child: TextField(
                  controller: _searchCtrl,
                  onChanged: (_) => setState(() {}),
                  decoration: InputDecoration(
                    hintText: 'Search customers',
                    prefixIcon: const Icon(Icons.search),
                    suffixIcon: _searchCtrl.text.isEmpty
                        ? null
                        : IconButton(
                            onPressed: () {
                              _searchCtrl.clear();
                              setState(() {});
                            },
                            icon: const Icon(Icons.close),
                          ),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    '${customers.length} customer${customers.length == 1 ? '' : 's'}',
                    style: TextStyle(
                      color: Colors.grey.shade700,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
              Expanded(
                child: customers.isEmpty
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(32),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.people_outline,
                                size: 64,
                                color: KhataColors.primaryGreen.withValues(
                                  alpha: 0.5,
                                ),
                              ),
                              const SizedBox(height: 16),
                              Text(
                                all.isEmpty
                                    ? 'No customers yet'
                                    : 'No match for “${_searchCtrl.text.trim()}”',
                                style: const TextStyle(
                                  fontSize: 20,
                                  fontWeight: FontWeight.w700,
                                ),
                                textAlign: TextAlign.center,
                              ),
                              if (all.isEmpty) ...[
                                const SizedBox(height: 20),
                                FilledButton.icon(
                                  onPressed: _openAdd,
                                  icon: const Icon(Icons.person_add_alt_1),
                                  label: const Text('Add customer'),
                                ),
                              ],
                            ],
                          ),
                        ),
                      )
                    : ListView.separated(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 100),
                        itemCount: customers.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 8),
                        itemBuilder: (context, index) {
                          final item = customers[index];
                          return _CustomerManageTile(
                            item: item,
                            onOpenKhata: () => _openKhata(item.id),
                            onEdit: () => _openEdit(item.id),
                          );
                        },
                      ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _CustomerManageTile extends StatelessWidget {
  const _CustomerManageTile({
    required this.item,
    required this.onOpenKhata,
    required this.onEdit,
  });

  final CustomerListItem item;
  final VoidCallback onOpenKhata;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    final balance = item.currentBalance;
    final balanceColor = balance > 0
        ? KhataColors.primaryGreen
        : balance < 0
        ? KhataColors.debtRed
        : Colors.grey.shade700;

    return Material(
      color: const Color(0xFFF8FAF9),
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onOpenKhata,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          child: Row(
            children: [
              CustomerAvatar(
                name: item.name,
                photoPath: item.photoPath,
                radius: 26,
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
                      item.isPhonePending
                          ? 'Number pending'
                          : PhoneNumbers.display(item.phoneNumber),
                      style: TextStyle(
                        fontSize: 13,
                        color: item.isPhonePending
                            ? KhataColors.amber
                            : Colors.grey.shade600,
                        fontWeight: item.isPhonePending
                            ? FontWeight.w700
                            : FontWeight.w400,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      formatRs(balance),
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: balanceColor,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: 'Edit details',
                onPressed: onEdit,
                icon: const Icon(Icons.edit_outlined),
              ),
              IconButton(
                tooltip: 'Open khata',
                onPressed: onOpenKhata,
                icon: const Icon(Icons.chevron_right),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
