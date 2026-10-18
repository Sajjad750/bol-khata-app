import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../database/app_database.dart';
import '../database/phone_numbers.dart';
import '../providers/database_providers.dart';
import '../services/photo_storage.dart';
import '../theme/khata_colors.dart';
import '../utils/user_facing_error.dart';

/// Edit an existing customer's name, phone, and photo.
class EditCustomerScreen extends ConsumerStatefulWidget {
  const EditCustomerScreen({super.key, required this.customerId});

  final int customerId;

  @override
  ConsumerState<EditCustomerScreen> createState() => _EditCustomerScreenState();
}

class _EditCustomerScreenState extends ConsumerState<EditCustomerScreen> {
  final _nameController = TextEditingController();
  final _addressController = TextEditingController();
  final _phoneController = TextEditingController();
  final _referenceController = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  bool _loaded = false;
  bool _numberPending = false;
  bool _saving = false;
  String? _photoPath;
  String? _phoneError;

  @override
  void dispose() {
    _nameController.dispose();
    _addressController.dispose();
    _phoneController.dispose();
    _referenceController.dispose();
    super.dispose();
  }

  void _hydrate(Customer customer) {
    if (_loaded) return;
    _loaded = true;
    _nameController.text = customer.name;
    _addressController.text = customer.address ?? '';
    _referenceController.text = customer.referenceNote ?? '';
    _numberPending = PhoneNumbers.isPending(customer.phoneNumber);
    if (!_numberPending) {
      _phoneController.text = customer.phoneNumber;
    }
    _photoPath = customer.photoPath;
  }

  Future<void> _pickPhoto(ImageSource source) async {
    final picked = await ImagePicker().pickImage(
      source: source,
      maxWidth: 1200,
      imageQuality: 85,
    );
    if (picked == null) return;
    final path = await persistCustomerPhoto(picked.path);
    setState(() => _photoPath = path);
  }

  Future<void> _photoActions() async {
    final action = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_camera),
              title: const Text('Take photo'),
              onTap: () => Navigator.pop(ctx, 'camera'),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library),
              title: const Text('Choose from gallery'),
              onTap: () => Navigator.pop(ctx, 'gallery'),
            ),
            if (_photoPath != null)
              ListTile(
                leading: const Icon(Icons.delete_outline, color: KhataColors.debtRed),
                title: const Text('Remove photo'),
                onTap: () => Navigator.pop(ctx, 'remove'),
              ),
          ],
        ),
      ),
    );
    if (action == 'camera') await _pickPhoto(ImageSource.camera);
    if (action == 'gallery') await _pickPhoto(ImageSource.gallery);
    if (action == 'remove') setState(() => _photoPath = null);
  }

  Future<void> _save(Customer original) async {
    setState(() {
      _phoneError = null;
      _saving = true;
    });
    if (!_formKey.currentState!.validate()) {
      setState(() => _saving = false);
      return;
    }

    if (!_numberPending) {
      final phone = _phoneController.text.trim();
      if (!PhoneNumbers.isValidPakistaniMobile(phone)) {
        setState(() {
          _phoneError = 'Enter a valid Pakistani mobile (03XXXXXXXXX)';
          _saving = false;
        });
        return;
      }
    }

    try {
      final clearPhoto = original.photoPath != null && _photoPath == null;
      await ref.read(databaseProvider).updateCustomerDetails(
            customerId: widget.customerId,
            name: _nameController.text,
            address: _addressController.text,
            phoneNumber: _numberPending ? null : _phoneController.text,
            numberPending: _numberPending,
            referenceNote: _referenceController.text,
            photoPath: _photoPath,
            clearPhoto: clearPhoto,
          );
      if (!mounted) return;
      Navigator.pop(context, true);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Customer updated')),
      );
    } on DuplicatePhoneNumberException catch (_) {
      setState(() {
        _saving = false;
        _phoneError =
            'This phone number is already used by another customer.';
      });
    } catch (e) {
      setState(() => _saving = false);
      if (mounted) {
        showAppError(
          context,
          e,
          fallback: 'Could not update customer. Please try again.',
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final customerAsync = ref.watch(customerProvider(widget.customerId));

    return customerAsync.when(
      loading: () => const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      ),
      error: (e, _) => Scaffold(
        appBar: AppBar(),
        body: Center(child: Text('$e')),
      ),
      data: (customer) {
        if (customer == null) {
          return Scaffold(
            appBar: AppBar(),
            body: const Center(child: Text('Customer not found')),
          );
        }
        _hydrate(customer);

        return Scaffold(
          appBar: AppBar(title: const Text('Edit customer')),
          body: Form(
            key: _formKey,
            child: ListView(
              padding: const EdgeInsets.all(20),
              children: [
                Center(
                  child: GestureDetector(
                    onTap: _photoActions,
                    child: Stack(
                      alignment: Alignment.bottomRight,
                      children: [
                        CircleAvatar(
                          radius: 52,
                          backgroundColor: KhataColors.softGreen,
                          backgroundImage: _photoPath != null
                              ? FileImage(File(_photoPath!))
                              : null,
                          child: _photoPath == null
                              ? const Icon(
                                  Icons.person,
                                  size: 48,
                                  color: KhataColors.primaryGreen,
                                )
                              : null,
                        ),
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: const BoxDecoration(
                            color: KhataColors.primaryGreen,
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.camera_alt,
                            color: Colors.white,
                            size: 18,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Tap photo to change',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
                ),
                const SizedBox(height: 24),
                TextFormField(
                  controller: _nameController,
                  textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(
                    labelText: 'Name',
                    hintText: 'Customer name',
                  ),
                  validator: (v) {
                    if (v == null || v.trim().isEmpty) {
                      return 'Name is required';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _addressController,
                  textCapitalization: TextCapitalization.sentences,
                  maxLines: 2,
                  decoration: const InputDecoration(
                    labelText: 'Address',
                    hintText: 'Shop / home address (optional)',
                  ),
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _phoneController,
                  enabled: !_numberPending,
                  keyboardType: TextInputType.phone,
                  decoration: InputDecoration(
                    labelText: 'Phone number',
                    hintText: '03XXXXXXXXX',
                    errorText: _phoneError,
                  ),
                ),
                const SizedBox(height: 8),
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  value: _numberPending,
                  onChanged: (v) {
                    setState(() {
                      _numberPending = v ?? false;
                      _phoneError = null;
                      if (_numberPending) _phoneController.clear();
                    });
                  },
                  title: const Text(
                    'Number pending — I will add it later',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                  controlAffinity: ListTileControlAffinity.leading,
                ),
                const SizedBox(height: 8),
                TextFormField(
                  controller: _referenceController,
                  textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(
                    labelText: 'Reference',
                    hintText: 'e.g. cycle wala, cousin of Ahmed',
                  ),
                ),
                const SizedBox(height: 28),
                SizedBox(
                  width: double.infinity,
                  height: 56,
                  child: FilledButton(
                    onPressed: _saving ? null : () => _save(customer),
                    child: Text(_saving ? 'Saving…' : 'Save changes'),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
