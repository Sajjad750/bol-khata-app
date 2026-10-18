import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../database/app_database.dart';
import '../database/customer_search.dart';
import '../database/phone_numbers.dart';
import '../database/tables.dart';
import '../providers/database_providers.dart';
import '../services/entry_parser_service.dart';
import '../services/formatters.dart';
import '../theme/khata_colors.dart';
import '../utils/user_facing_error.dart';
import '../widgets/amount_entry_sheet.dart';
import '../widgets/customer_avatar.dart';

/// Confirm / edit a ledger draft before saving (voice or manual).
class VoiceConfirmScreen extends ConsumerStatefulWidget {
  const VoiceConfirmScreen({
    super.key,
    required this.entry,
    required this.candidates,
    required this.ambiguousMatch,
    this.lockedCustomerId,
    this.lockedCustomerName,
    this.sourceType = TransactionSourceType.voice,
  });

  /// Opens a blank manual entry for one customer (products + amount + note).
  factory VoiceConfirmScreen.manualForCustomer({
    Key? key,
    required int customerId,
    required String customerName,
  }) {
    return VoiceConfirmScreen(
      key: key,
      entry: ParsedEntry(
        spokenReference: customerName,
        items: [],
        amount: null,
        type: TransactionType.creditGiven,
        note: null,
        confidence: ParseConfidence.high,
      ),
      candidates: const [],
      ambiguousMatch: false,
      lockedCustomerId: customerId,
      lockedCustomerName: customerName,
      sourceType: TransactionSourceType.manual,
    );
  }

  final ParsedEntry entry;
  final List<CustomerSearchHit> candidates;
  final bool ambiguousMatch;

  /// When set, entry is for this customer — picker is hidden.
  final int? lockedCustomerId;
  final String? lockedCustomerName;

  /// [TransactionSourceType.voice] or [TransactionSourceType.manual].
  final String sourceType;

  bool get isManual => sourceType == TransactionSourceType.manual;

  @override
  ConsumerState<VoiceConfirmScreen> createState() => _VoiceConfirmScreenState();
}

class _VoiceConfirmScreenState extends ConsumerState<VoiceConfirmScreen> {
  late ParsedEntry _entry;
  late List<ParsedItem> _items;
  late TextEditingController _noteController;

  /// null until shopkeeper taps a chip (or finishes + New Customer).
  int? _selectedCustomerId;
  bool _creatingNew = false;
  bool _saving = false;

  final _newNameController = TextEditingController();
  final _newPhoneController = TextEditingController();
  String? _newPhoneError;

  /// Visual suggestion only — not an actual selection until tapped.
  int? get _suggestedCustomerId {
    if (widget.ambiguousMatch) return null;
    if (widget.candidates.length == 1) return widget.candidates.first.id;
    if (widget.candidates.isNotEmpty && !widget.ambiguousMatch) {
      return widget.candidates.first.id;
    }
    return null;
  }

  bool get _customerLocked => widget.lockedCustomerId != null;

  bool get _customerSectionNeedsAttention =>
      !_customerLocked &&
      (widget.ambiguousMatch ||
          _entry.confidence == ParseConfidence.low ||
          widget.candidates.isEmpty);

  @override
  void initState() {
    super.initState();
    _entry = widget.entry;
    _items = List<ParsedItem>.from(
      _entry.items.map(
        (i) => ParsedItem(
          itemName: i.itemName,
          quantity: i.quantity,
          unit: i.unit,
          price: i.price,
        ),
      ),
    );
    _noteController = TextEditingController(text: _entry.note ?? '');
    _newNameController.text = _entry.spokenReference;
    if (widget.lockedCustomerId != null) {
      _selectedCustomerId = widget.lockedCustomerId;
      _creatingNew = false;
    }
  }

  @override
  void dispose() {
    _noteController.dispose();
    _newNameController.dispose();
    _newPhoneController.dispose();
    super.dispose();
  }

  Future<void> _editAmount() async {
    await showAmountEntrySheet(
      context: context,
      title: _entry.isCredit ? 'Udhar amount' : 'Payment amount',
      type: _entry.type,
      onSave: (amount, _) async {
        setState(() => _entry.amount = amount);
      },
    );
  }

  /// Sum of line prices when present; updates total amount.
  void _syncAmountFromItemPrices() {
    var sum = 0.0;
    var any = false;
    for (final item in _items) {
      final p = item.price;
      if (p != null && p > 0) {
        sum += p;
        any = true;
      }
    }
    if (any) {
      _entry.amount = sum;
    }
  }

  String? _formatPrice(double? price) {
    if (price == null || price <= 0) return null;
    if (price == price.roundToDouble()) return 'Rs ${price.toInt()}';
    return 'Rs ${price.toStringAsFixed(2)}';
  }

  Future<void> _editItem(int index) async {
    final item = _items[index];
    final result = await showDialog<ParsedItem>(
      context: context,
      builder: (ctx) => _ItemEditorDialog(
        title: 'Edit item',
        confirmLabel: 'Save',
        initial: item,
      ),
    );
    if (result != null && mounted) {
      setState(() {
        _items[index] = result;
        _syncAmountFromItemPrices();
      });
    }
  }

  Future<void> _addItem() async {
    final result = await showDialog<ParsedItem>(
      context: context,
      builder: (ctx) => const _ItemEditorDialog(
        title: 'Add item',
        confirmLabel: 'Add',
      ),
    );
    if (result != null && mounted) {
      setState(() {
        _items.add(result);
        _syncAmountFromItemPrices();
      });
    }
  }

  Future<void> _confirm() async {
    if (_creatingNew) {
      setState(() => _newPhoneError = null);
      final name = _newNameController.text.trim();
      final phone = _newPhoneController.text.trim();
      if (name.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Enter a customer name')),
        );
        return;
      }
      if (!PhoneNumbers.isValidPakistaniMobile(phone)) {
        setState(() {
          _newPhoneError = 'Enter a valid Pakistani mobile (03XXXXXXXXX)';
        });
        return;
      }
    } else if (_selectedCustomerId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Select a customer (or add a new one)')),
      );
      return;
    }

    final amount = _entry.amount;
    if (amount == null || amount <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter the total amount')),
      );
      await _editAmount();
      return;
    }

    setState(() => _saving = true);
    final db = ref.read(databaseProvider);

    try {
      late final int customerId;
      if (_creatingNew) {
        final customer = await db.addCustomer(
          name: _newNameController.text.trim(),
          phoneNumber: _newPhoneController.text.trim(),
          aliases: _newNameController.text.trim() == _entry.spokenReference
              ? const []
              : [_entry.spokenReference],
        );
        customerId = customer.id;
      } else {
        customerId = _selectedCustomerId!;
        // Persist spoken nickname as alias when it differs from primary name.
        final spoken = _entry.spokenReference.trim();
        CustomerSearchHit? hit;
        for (final c in widget.candidates) {
          if (c.id == customerId) {
            hit = c;
            break;
          }
        }
        if (spoken.isNotEmpty &&
            hit != null &&
            spoken.toLowerCase() != hit.name.toLowerCase() &&
            !hit.aliases.any((a) => a.toLowerCase() == spoken.toLowerCase())) {
          try {
            await db.addAlias(customerId: customerId, alias: spoken);
          } catch (_) {}
        }
      }

      final note = _noteController.text.trim();
      await db.addTransaction(
        customerId: customerId,
        amount: amount,
        type: _entry.type,
        note: note.isEmpty ? null : note,
        sourceType: widget.sourceType,
        items: [
          for (final item in _items)
            TransactionItemInput(
              itemName: item.itemName,
              quantity: item.quantity,
              unit: item.unit,
              price: item.price,
            ),
        ],
      );

      if (!mounted) return;
      Navigator.of(context).pop(true);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Entry saved'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } on DuplicatePhoneNumberException catch (e) {
      setState(() {
        _saving = false;
        _newPhoneError = userFacingMessage(
          e,
          fallback: 'This phone number is already used by another customer.',
        );
      });
    } catch (e) {
      setState(() => _saving = false);
      if (mounted) {
        showAppError(
          context,
          e,
          fallback: 'Could not save this entry. Please try again.',
        );
      }
    }
  }

  String _phoneDigits(String phone) {
    if (PhoneNumbers.isPending(phone)) return 'pending';
    final digits = PhoneNumbers.digitsOnly(phone);
    if (digits.length < 4) return digits;
    return '•••${digits.substring(digits.length - 4)}';
  }

  @override
  Widget build(BuildContext context) {
    final amount = _entry.amount;
    final attentionBorder = _customerSectionNeedsAttention
        ? Border.all(color: const Color(0xFFEAB308), width: 2)
        : Border.all(color: const Color(0xFFE5E7EB));

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.isManual ? 'Add entry' : 'Confirm entry'),
        actions: [
          TextButton(
            onPressed: _saving ? null : () => Navigator.pop(context, false),
            child: Text(widget.isManual ? 'Cancel' : 'Discard'),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          if (_entry.rawTranscript.isNotEmpty) ...[
            Text(
              '“${_entry.rawTranscript}”',
              style: TextStyle(
                fontSize: 14,
                fontStyle: FontStyle.italic,
                color: Colors.grey.shade700,
              ),
            ),
            const SizedBox(height: 12),
          ],

          // ---- Customer match ----
          if (_customerLocked) ...[
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: KhataColors.softGreen,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Row(
                children: [
                  const Icon(Icons.person, color: KhataColors.primaryGreen),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.lockedCustomerName ??
                              (widget.candidates.isEmpty
                                  ? 'Selected customer'
                                  : widget.candidates.first.name),
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        Text(
                          'Saving to this customer’s khata',
                          style: TextStyle(
                            fontSize: 13,
                            color: Colors.grey.shade700,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ] else ...[
            Text(
              'Heard: ${_entry.spokenReference}',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: Colors.grey.shade700,
              ),
            ),
            const SizedBox(height: 8),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFFFFBEB),
                borderRadius: BorderRadius.circular(14),
                border: attentionBorder,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (_customerSectionNeedsAttention)
                    const Padding(
                      padding: EdgeInsets.only(bottom: 8),
                      child: Text(
                        'Double-check the customer',
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          color: Color(0xFFA16207),
                        ),
                      ),
                    ),
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        for (final hit in widget.candidates) ...[
                          _CustomerChip(
                            name: hit.name,
                            phoneHint: _phoneDigits(hit.phoneNumber),
                            photoPath: hit.photoPath,
                            selected: !_creatingNew &&
                                _selectedCustomerId == hit.id,
                            suggested: _suggestedCustomerId == hit.id &&
                                _selectedCustomerId == null &&
                                !_creatingNew,
                            onTap: () {
                              setState(() {
                                _creatingNew = false;
                                _selectedCustomerId = hit.id;
                              });
                            },
                          ),
                          const SizedBox(width: 8),
                        ],
                        _NewCustomerChip(
                          selected: _creatingNew,
                          onTap: () {
                            setState(() {
                              _creatingNew = true;
                              _selectedCustomerId = null;
                            });
                          },
                        ),
                      ],
                    ),
                  ),
                  if (_creatingNew) ...[
                    const SizedBox(height: 12),
                    TextField(
                      controller: _newNameController,
                      textCapitalization: TextCapitalization.words,
                      decoration: const InputDecoration(
                        labelText: 'New customer name',
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _newPhoneController,
                      keyboardType: TextInputType.phone,
                      decoration: InputDecoration(
                        labelText: 'Phone number (required)',
                        hintText: '03XXXXXXXXX',
                        errorText: _newPhoneError,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],

          const SizedBox(height: 20),

          // ---- Items ----
          Row(
            children: [
              const Text(
                'Items',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
              ),
              const Spacer(),
              TextButton.icon(
                onPressed: _addItem,
                icon: const Icon(Icons.add),
                label: const Text('Add item'),
              ),
            ],
          ),
          if (_items.isEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                widget.isManual
                    ? 'Add products for this khata (optional), then set the total.'
                    : 'No items parsed — plain amount entry.',
                style: TextStyle(color: Colors.grey.shade600),
              ),
            )
          else
            ...List.generate(_items.length, (index) {
              final item = _items[index];
              final qty = item.quantity;
              final unit = item.unit;
              final detail = [
                if (qty != null)
                  (qty == qty.roundToDouble()
                      ? qty.toInt().toString()
                      : qty.toString()),
                if (unit != null && unit.isNotEmpty) unit,
              ].join(' ');
              final priceLabel = _formatPrice(item.price);
              return Dismissible(
                key: ValueKey('item-$index-${item.itemName}'),
                direction: DismissDirection.endToStart,
                background: Container(
                  alignment: Alignment.centerRight,
                  padding: const EdgeInsets.only(right: 16),
                  color: KhataColors.debtRed,
                  child: const Icon(Icons.delete, color: Colors.white),
                ),
                onDismissed: (_) {
                  setState(() {
                    _items.removeAt(index);
                    _syncAmountFromItemPrices();
                  });
                },
                child: ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(
                    item.itemName,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  subtitle: detail.isEmpty ? null : Text(detail),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (priceLabel != null)
                        Padding(
                          padding: const EdgeInsets.only(right: 4),
                          child: Text(
                            priceLabel,
                            style: const TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 15,
                            ),
                          ),
                        ),
                      IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () => setState(() {
                          _items.removeAt(index);
                          _syncAmountFromItemPrices();
                        }),
                      ),
                    ],
                  ),
                  onTap: () => _editItem(index),
                ),
              );
            }),

          const Divider(height: 32),

          // ---- Amount + type ----
          const Text(
            'Amount & type',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 12),
          SegmentedButton<String>(
            segments: const [
              ButtonSegment(
                value: TransactionType.creditGiven,
                label: Text('Udhar Diya'),
                icon: Icon(Icons.arrow_upward),
              ),
              ButtonSegment(
                value: TransactionType.paymentReceived,
                label: Text('Payment Liya'),
                icon: Icon(Icons.arrow_downward),
              ),
            ],
            selected: {_entry.type},
            onSelectionChanged: (s) {
              setState(() => _entry.type = s.first);
            },
          ),
          const SizedBox(height: 16),
          InkWell(
            onTap: _editAmount,
            borderRadius: BorderRadius.circular(12),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
              decoration: BoxDecoration(
                color: KhataColors.softGrey,
                borderRadius: BorderRadius.circular(12),
                border: _entry.confidence == ParseConfidence.low &&
                        (amount == null || amount <= 0)
                    ? Border.all(color: const Color(0xFFEAB308), width: 2)
                    : null,
              ),
              child: Column(
                children: [
                  Text(
                    amount == null || amount <= 0
                        ? 'Tap to enter amount'
                        : formatRs(amount),
                    style: TextStyle(
                      fontSize: 32,
                      fontWeight: FontWeight.w800,
                      color: _entry.isCredit
                          ? KhataColors.primaryGreen
                          : KhataColors.amber,
                    ),
                  ),
                  Text(
                    'Tap to edit',
                    style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _noteController,
            decoration: InputDecoration(
              labelText: 'Note (optional)',
              hintText: widget.isManual
                  ? 'e.g. 2 bags rice, 1 oil'
                  : null,
            ),
          ),
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            height: 56,
            child: FilledButton(
              onPressed: _saving ? null : _confirm,
              child: Text(_saving ? 'Saving…' : 'Confirm'),
            ),
          ),
        ],
      ),
    );
  }
}

class _CustomerChip extends StatelessWidget {
  const _CustomerChip({
    required this.name,
    required this.phoneHint,
    required this.photoPath,
    required this.selected,
    required this.suggested,
    required this.onTap,
  });

  final String name;
  final String phoneHint;
  final String? photoPath;
  final bool selected;
  final bool suggested;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final borderColor = selected
        ? KhataColors.primaryGreen
        : suggested
            ? const Color(0xFF86EFAC)
            : const Color(0xFFD1D5DB);

    return Material(
      color: selected ? KhataColors.softGreen : Colors.white,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          width: 132,
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: borderColor, width: selected ? 2.5 : 1.5),
          ),
          child: Column(
            children: [
              CustomerAvatar(name: name, photoPath: photoPath, radius: 26),
              const SizedBox(height: 8),
              Text(
                name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
              ),
              Text(
                phoneHint,
                style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
              ),
              if (suggested && !selected)
                const Padding(
                  padding: EdgeInsets.only(top: 4),
                  child: Text(
                    'Suggested — tap',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      color: KhataColors.primaryGreen,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NewCustomerChip extends StatelessWidget {
  const _NewCustomerChip({required this.selected, required this.onTap});

  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? KhataColors.softGreen : Colors.white,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          width: 120,
          height: 132,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: selected ? KhataColors.primaryGreen : const Color(0xFFD1D5DB),
              width: selected ? 2.5 : 1.5,
            ),
          ),
          child: const Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.person_add_alt_1, color: KhataColors.primaryGreen),
              SizedBox(height: 8),
              Text(
                '+ New Customer',
                textAlign: TextAlign.center,
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Owns its own controllers so Cancel/Save never dispose mid-unmount.
class _ItemEditorDialog extends StatefulWidget {
  const _ItemEditorDialog({
    required this.title,
    required this.confirmLabel,
    this.initial,
  });

  final String title;
  final String confirmLabel;
  final ParsedItem? initial;

  @override
  State<_ItemEditorDialog> createState() => _ItemEditorDialogState();
}

class _ItemEditorDialogState extends State<_ItemEditorDialog> {
  late final TextEditingController _nameCtrl;
  late final TextEditingController _qtyCtrl;
  late final TextEditingController _unitCtrl;
  late final TextEditingController _priceCtrl;
  String? _error;

  @override
  void initState() {
    super.initState();
    final item = widget.initial;
    _nameCtrl = TextEditingController(text: item?.itemName ?? '');
    _qtyCtrl = TextEditingController(
      text: item?.quantity?.toString() ?? '',
    );
    _unitCtrl = TextEditingController(text: item?.unit ?? '');
    final price = item?.price;
    _priceCtrl = TextEditingController(
      text: price == null
          ? ''
          : (price == price.roundToDouble()
              ? price.toInt().toString()
              : price.toString()),
    );
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _qtyCtrl.dispose();
    _unitCtrl.dispose();
    _priceCtrl.dispose();
    super.dispose();
  }

  void _submit() {
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) {
      setState(() => _error = 'Enter an item name');
      return;
    }
    final priceText = _priceCtrl.text.trim();
    double? price;
    if (priceText.isNotEmpty) {
      price = double.tryParse(priceText);
      if (price == null || price < 0) {
        setState(() => _error = 'Enter a valid price in rupees');
        return;
      }
    }
    Navigator.of(context).pop(
      ParsedItem(
        itemName: name,
        quantity: double.tryParse(_qtyCtrl.text.trim()),
        unit: _unitCtrl.text.trim().isEmpty ? null : _unitCtrl.text.trim(),
        price: price,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _nameCtrl,
              decoration: const InputDecoration(labelText: 'Item name'),
              autofocus: widget.initial == null,
              textInputAction: TextInputAction.next,
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _qtyCtrl,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(labelText: 'Quantity'),
              textInputAction: TextInputAction.next,
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _unitCtrl,
              decoration:
                  const InputDecoration(labelText: 'Unit (kg, dozen…)'),
              textInputAction: TextInputAction.next,
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _priceCtrl,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(
                labelText: 'Price (Rs)',
                hintText: 'Line total — e.g. 20',
              ),
              onSubmitted: (_) => _submit(),
            ),
            if (_error != null) ...[
              const SizedBox(height: 10),
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  _error!,
                  style: const TextStyle(
                    color: KhataColors.debtRed,
                    fontSize: 14,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _submit,
          child: Text(widget.confirmLabel),
        ),
      ],
    );
  }
}
