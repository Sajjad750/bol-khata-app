import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../database/customer_list_item.dart';
import '../database/phone_numbers.dart';
import '../providers/database_providers.dart';
import '../providers/language_providers.dart';
import '../l10n/app_strings.dart';
import '../services/formatters.dart';
import '../theme/bol_khata_brand.dart';
import '../theme/khata_colors.dart';
import '../widgets/customer_avatar.dart';
import '../widgets/sync_status_icon.dart';
import '../widgets/voice_entry_button.dart';
import 'add_customer_screen.dart';
import 'customer_detail_screen.dart';
import 'customers_screen.dart';
import 'language_picker_screen.dart';
import 'ledger_summary_screen.dart';
import 'link_phone_screen.dart';

enum CustomerSort {
  recent,
  nameAsc,
  nameDesc,
  balanceHigh,
  balanceLow,
}

enum CustomerFilter {
  all,
  owesYou,
  settled,
  youOwe,
  numberPending,
}

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  final _searchCtrl = TextEditingController();
  CustomerSort _sort = CustomerSort.recent;
  CustomerFilter _filter = CustomerFilter.all;

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  void _openAddCustomer() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => const AddCustomerScreen()),
    );
  }

  List<CustomerListItem> _apply(
    List<CustomerListItem> source,
  ) {
    final q = _searchCtrl.text.trim().toLowerCase();
    var list = source.where((item) {
      switch (_filter) {
        case CustomerFilter.all:
          break;
        case CustomerFilter.owesYou:
          if (item.currentBalance <= 0) return false;
          break;
        case CustomerFilter.settled:
          if (item.currentBalance != 0) return false;
          break;
        case CustomerFilter.youOwe:
          if (item.currentBalance >= 0) return false;
          break;
        case CustomerFilter.numberPending:
          if (!item.isPhonePending) return false;
          break;
      }
      if (q.isEmpty) return true;
      final phone = PhoneNumbers.display(item.phoneNumber).toLowerCase();
      return item.name.toLowerCase().contains(q) || phone.contains(q);
    }).toList();

    switch (_sort) {
      case CustomerSort.recent:
        // Already ordered by recent activity from DB.
        break;
      case CustomerSort.nameAsc:
        list.sort(
          (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
        );
        break;
      case CustomerSort.nameDesc:
        list.sort(
          (a, b) => b.name.toLowerCase().compareTo(a.name.toLowerCase()),
        );
        break;
      case CustomerSort.balanceHigh:
        list.sort((a, b) => b.currentBalance.compareTo(a.currentBalance));
        break;
      case CustomerSort.balanceLow:
        list.sort((a, b) => a.currentBalance.compareTo(b.currentBalance));
        break;
    }
    return list;
  }

  String get _sortLabel {
    switch (_sort) {
      case CustomerSort.recent:
        return 'Recent activity';
      case CustomerSort.nameAsc:
        return 'Name A–Z';
      case CustomerSort.nameDesc:
        return 'Name Z–A';
      case CustomerSort.balanceHigh:
        return 'Highest udhar';
      case CustomerSort.balanceLow:
        return 'Lowest udhar';
    }
  }

  Future<void> _pickSort() async {
    final chosen = await showModalBottomSheet<CustomerSort>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const ListTile(
              title: Text(
                'Sort customers',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
            for (final s in CustomerSort.values)
              ListTile(
                leading: Icon(
                  _sort == s
                      ? Icons.radio_button_checked
                      : Icons.radio_button_off,
                  color: KhataColors.primaryGreen,
                ),
                title: Text(_labelForSort(s)),
                onTap: () => Navigator.pop(ctx, s),
              ),
          ],
        ),
      ),
    );
    if (chosen != null) setState(() => _sort = chosen);
  }

  String _labelForSort(CustomerSort s) {
    switch (s) {
      case CustomerSort.recent:
        return 'Recent activity (last entry)';
      case CustomerSort.nameAsc:
        return 'Name (A–Z)';
      case CustomerSort.nameDesc:
        return 'Name (Z–A)';
      case CustomerSort.balanceHigh:
        return 'Udhar amount (high → low)';
      case CustomerSort.balanceLow:
        return 'Udhar amount (low → high)';
    }
  }

  @override
  Widget build(BuildContext context) {
    final customersAsync = ref.watch(customersProvider);

    return Scaffold(
      appBar: AppBar(
        title: const BolKhataLogo(
          height: 28,
          showName: true,
          variant: BolKhataLogoVariant.black,
        ),
        actions: [
          IconButton(
            tooltip: 'All customers',
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const CustomersScreen(),
                ),
              );
            },
            icon: const Icon(Icons.people_outline),
          ),
          const SyncStatusIcon(),
          PopupMenuButton<String>(
            onSelected: (value) async {
              if (value == 'language') {
                await Navigator.of(context).push<void>(
                  MaterialPageRoute<void>(
                    builder: (_) => const LanguagePickerScreen(
                      allowSkipIfChosen: true,
                    ),
                  ),
                );
                return;
              }
              if (value == 'add_phone') {
                await Navigator.of(context).push<bool>(
                  MaterialPageRoute<bool>(
                    builder: (_) => const LinkPhoneScreen(),
                  ),
                );
                return;
              }
              if (value == 'signout') {
                final s = ref.read(appStringsProvider);
                final ok = await showDialog<bool>(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    title: Text('${s.signOut}?'),
                    content: const Text(
                      'You will set up PIN / phone again. '
                      'Your khata data on this phone is kept and will show after you sign in.',
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(ctx, false),
                        child: Text(s.cancel),
                      ),
                      FilledButton(
                        onPressed: () => Navigator.pop(ctx, true),
                        child: Text(s.signOut),
                      ),
                    ],
                  ),
                );
                if (ok == true && context.mounted) {
                  await ref.read(authControllerProvider.notifier).signOutFully();
                }
              }
            },
            itemBuilder: (context) {
              final s = ref.read(appStringsProvider);
              return [
                PopupMenuItem(
                  value: 'language',
                  child: Text(s.changeLanguage),
                ),
                PopupMenuItem(
                  value: 'add_phone',
                  child: Text(s.addPhoneNumber),
                ),
                PopupMenuItem(value: 'signout', child: Text(s.signOut)),
              ];
            },
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _openAddCustomer,
        icon: const Icon(Icons.person_add_alt_1),
        label: const Text('Add'),
      ),
      body: customersAsync.when(
        skipLoadingOnReload: true,
        skipLoadingOnRefresh: true,
        loading: () => _HomeBody(
          customers: const [],
          searchCtrl: _searchCtrl,
          sortLabel: _sortLabel,
          filter: _filter,
          onSearchChanged: () => setState(() {}),
          onSortTap: _pickSort,
          onFilterChanged: (f) => setState(() => _filter = f),
          onAdd: _openAddCustomer,
        ),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (customers) => _HomeBody(
          customers: _apply(customers),
          searchCtrl: _searchCtrl,
          sortLabel: _sortLabel,
          filter: _filter,
          onSearchChanged: () => setState(() {}),
          onSortTap: _pickSort,
          onFilterChanged: (f) => setState(() => _filter = f),
          onAdd: _openAddCustomer,
          totalCount: customers.length,
        ),
      ),
    );
  }
}

class _HomeBody extends ConsumerWidget {
  const _HomeBody({
    required this.customers,
    required this.searchCtrl,
    required this.sortLabel,
    required this.filter,
    required this.onSearchChanged,
    required this.onSortTap,
    required this.onFilterChanged,
    required this.onAdd,
    this.totalCount,
  });

  final List<CustomerListItem> customers;
  final TextEditingController searchCtrl;
  final String sortLabel;
  final CustomerFilter filter;
  final VoidCallback onSearchChanged;
  final VoidCallback onSortTap;
  final ValueChanged<CustomerFilter> onFilterChanged;
  final VoidCallback onAdd;
  final int? totalCount;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final emptyBecauseFilter =
        customers.isEmpty && (totalCount ?? 0) > 0;
    final s = ref.watch(appStringsProvider);
    final summaryAsync = ref.watch(shopSummaryProvider);

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          child: TextField(
            controller: searchCtrl,
            onChanged: (_) => onSearchChanged(),
            textInputAction: TextInputAction.search,
            decoration: InputDecoration(
              hintText: s.searchHint,
              prefixIcon: const Icon(Icons.search),
              suffixIcon: searchCtrl.text.isEmpty
                  ? null
                  : IconButton(
                      tooltip: 'Clear',
                      onPressed: () {
                        searchCtrl.clear();
                        onSearchChanged();
                      },
                      icon: const Icon(Icons.close),
                    ),
            ),
          ),
        ),
        const SizedBox(height: 10),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: summaryAsync.when(
            skipLoadingOnReload: true,
            skipLoadingOnRefresh: true,
            loading: () => const SizedBox(height: 84),
            error: (_, _) => const SizedBox.shrink(),
            data: (summary) => Row(
              children: [
                Expanded(
                  child: _SummaryCard(
                    label: s.toCollect,
                    amount: summary.totalOwed,
                    color: KhataColors.primaryGreen,
                    softColor: KhataColors.softGreen,
                    onTap: () {
                      Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => const LedgerSummaryScreen(
                            kind: LedgerSummaryKind.owed,
                          ),
                        ),
                      );
                    },
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _SummaryCard(
                    label: s.receivedBack,
                    amount: summary.totalReceived,
                    color: KhataColors.amber,
                    softColor: const Color(0xFFFFF4E5),
                    onTap: () {
                      Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => const LedgerSummaryScreen(
                            kind: LedgerSummaryKind.received,
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 8),
        SizedBox(
          height: 40,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            children: [
              for (final f in CustomerFilter.values) ...[
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: FilterChip(
                    label: Text(_filterLabel(f, s)),
                    selected: filter == f,
                    onSelected: (_) => onFilterChanged(f),
                    selectedColor: KhataColors.softGreen,
                    checkmarkColor: KhataColors.primaryGreen,
                    labelStyle: TextStyle(
                      fontWeight:
                          filter == f ? FontWeight.w700 : FontWeight.w500,
                      color: filter == f
                          ? KhataColors.primaryGreen
                          : Colors.grey.shade800,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 4, 8, 0),
          child: Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: onSortTap,
              icon: const Icon(Icons.sort),
              label: Text(sortLabel),
            ),
          ),
        ),
        Expanded(
          child: customers.isEmpty
              ? (emptyBecauseFilter
                  ? Center(
                      child: Text(
                        'No customers match this search / filter.',
                        style: TextStyle(
                          fontSize: 16,
                          color: Colors.grey.shade600,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    )
                  : _EmptyCustomers(onAdd: onAdd))
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  itemCount: customers.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 8),
                  itemBuilder: (context, index) {
                    return _CustomerTile(item: customers[index]);
                  },
                ),
        ),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 88),
            child: const Column(
              children: [
                VoiceEntryButton(),
              ],
            ),
          ),
        ),
      ],
    );
  }

  String _filterLabel(CustomerFilter f, AppStrings s) {
    switch (f) {
      case CustomerFilter.all:
        return 'All';
      case CustomerFilter.owesYou:
        return s.owesYou;
      case CustomerFilter.settled:
        return s.settled;
      case CustomerFilter.youOwe:
        return s.youOwe;
      case CustomerFilter.numberPending:
        return s.noPhone;
    }
  }
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({
    required this.label,
    required this.amount,
    required this.color,
    required this.softColor,
    required this.onTap,
  });

  final String label;
  final double amount;
  final Color color;
  final Color softColor;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: softColor,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: color,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                formatRs(amount),
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  color: color,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EmptyCustomers extends StatelessWidget {
  const _EmptyCustomers({required this.onAdd});

  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const BolKhataLogo(height: 64, variant: BolKhataLogoVariant.green),
            const SizedBox(height: 20),
            const Text(
              'No customers yet',
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.w700),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              'Add your first customer to start tracking udhar and payments.',
              style: TextStyle(fontSize: 16, color: Colors.grey.shade700),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: onAdd,
              icon: const Icon(Icons.person_add_alt_1),
              label: const Text('Add first customer'),
            ),
          ],
        ),
      ),
    );
  }
}

class _CustomerTile extends StatelessWidget {
  const _CustomerTile({required this.item});

  final CustomerListItem item;

  @override
  Widget build(BuildContext context) {
    final balance = item.currentBalance;
    final owesYou = balance > 0;
    final youOwe = balance < 0;
    final balanceColor = owesYou
        ? KhataColors.primaryGreen
        : youOwe
            ? KhataColors.debtRed
            : Colors.grey.shade700;

    return Material(
      color: const Color(0xFFF8FAF9),
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () {
          Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => CustomerDetailScreen(customerId: item.id),
            ),
          );
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          child: Row(
            children: [
              CustomerAvatar(
                name: item.name,
                photoPath: item.photoPath,
                radius: 28,
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.name,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      formatTimeAgo(item.lastActivityAt),
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.grey.shade600,
                      ),
                    ),
                    if (item.isPhonePending) ...[
                      const SizedBox(height: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFFF4E5),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Text(
                          'Add number',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: KhataColors.amber,
                          ),
                        ),
                      ),
                    ] else ...[
                      const SizedBox(height: 2),
                      Text(
                        PhoneNumbers.display(item.phoneNumber),
                        style: TextStyle(
                          fontSize: 13,
                          color: Colors.grey.shade600,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              Text(
                formatRs(balance),
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: balanceColor,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
