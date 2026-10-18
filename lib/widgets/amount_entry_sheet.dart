import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../database/tables.dart';
import '../theme/khata_colors.dart';

/// Bottom sheet: number pad + optional note → saves udhar / payment.
Future<void> showAmountEntrySheet({
  required BuildContext context,
  required String title,
  required String type,
  required Future<void> Function(double amount, String? note) onSave,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (ctx) {
      return _AmountEntrySheet(
        title: title,
        type: type,
        onSave: onSave,
      );
    },
  );
}

class _AmountEntrySheet extends StatefulWidget {
  const _AmountEntrySheet({
    required this.title,
    required this.type,
    required this.onSave,
  });

  final String title;
  final String type;
  final Future<void> Function(double amount, String? note) onSave;

  @override
  State<_AmountEntrySheet> createState() => _AmountEntrySheetState();
}

class _AmountEntrySheetState extends State<_AmountEntrySheet> {
  final _noteController = TextEditingController();
  String _digits = '';
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _noteController.dispose();
    super.dispose();
  }

  void _tapKey(String key) {
    HapticFeedback.selectionClick();
    setState(() {
      _error = null;
      if (key == 'back') {
        if (_digits.isNotEmpty) {
          _digits = _digits.substring(0, _digits.length - 1);
        }
        return;
      }
      if (_digits.length >= 8) return;
      if (key == '0' && _digits.isEmpty) return;
      _digits += key;
    });
  }

  Future<void> _save() async {
    final amount = double.tryParse(_digits);
    if (amount == null || amount <= 0) {
      setState(() => _error = 'Enter an amount');
      return;
    }
    setState(() => _saving = true);
    try {
      final note = _noteController.text.trim();
      await widget.onSave(amount, note.isEmpty ? null : note);
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = e.toString();
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isCredit = widget.type == TransactionType.creditGiven;
    final accent =
        isCredit ? KhataColors.primaryGreen : KhataColors.amber;
    final display = _digits.isEmpty ? '0' : _digits;

    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 16,
        bottom: MediaQuery.viewInsetsOf(context).bottom + 16,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: const Color(0xFFD0D5D2),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            widget.title,
            style: const TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'Rs $display',
            style: TextStyle(
              fontSize: 40,
              fontWeight: FontWeight.w700,
              color: accent,
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: 8),
            Text(
              _error!,
              style: const TextStyle(color: KhataColors.debtRed, fontSize: 14),
            ),
          ],
          const SizedBox(height: 12),
          TextField(
            controller: _noteController,
            textInputAction: TextInputAction.done,
            decoration: const InputDecoration(
              hintText: 'Note (optional) — e.g. rice and oil',
            ),
          ),
          const SizedBox(height: 12),
          _NumPad(onKey: _tapKey),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            height: 56,
            child: FilledButton(
              onPressed: _saving ? null : _save,
              style: FilledButton.styleFrom(backgroundColor: accent),
              child: Text(_saving ? 'Saving…' : 'Save'),
            ),
          ),
        ],
      ),
    );
  }
}

class _NumPad extends StatelessWidget {
  const _NumPad({required this.onKey});

  final void Function(String key) onKey;

  @override
  Widget build(BuildContext context) {
    const keys = [
      ['1', '2', '3'],
      ['4', '5', '6'],
      ['7', '8', '9'],
      ['', '0', 'back'],
    ];

    return Column(
      children: [
        for (final row in keys)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              children: [
                for (var i = 0; i < row.length; i++) ...[
                  if (i > 0) const SizedBox(width: 8),
                  Expanded(
                    child: row[i].isEmpty
                        ? const SizedBox(height: 56)
                        : SizedBox(
                            height: 56,
                            child: Material(
                              color: KhataColors.softGrey,
                              borderRadius: BorderRadius.circular(12),
                              child: InkWell(
                                borderRadius: BorderRadius.circular(12),
                                onTap: () => onKey(row[i]),
                                child: Center(
                                  child: row[i] == 'back'
                                      ? const Icon(Icons.backspace_outlined)
                                      : Text(
                                          row[i],
                                          style: const TextStyle(
                                            fontSize: 24,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                ),
                              ),
                            ),
                          ),
                  ),
                ],
              ],
            ),
          ),
      ],
    );
  }
}
