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

class AddCustomerScreen extends ConsumerStatefulWidget {
  const AddCustomerScreen({super.key});

  @override
  ConsumerState<AddCustomerScreen> createState() => _AddCustomerScreenState();
}

class _AddCustomerScreenState extends ConsumerState<AddCustomerScreen> {
  final _nameController = TextEditingController();
  final _addressController = TextEditingController();
  final _phoneController = TextEditingController();
  final _referenceController = TextEditingController();
  final _formKey = GlobalKey<FormState>();

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

  Future<void> _choosePhotoSource() async {
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_camera),
              title: const Text('Take photo'),
              onTap: () => Navigator.pop(ctx, ImageSource.camera),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library),
              title: const Text('Choose from gallery'),
              onTap: () => Navigator.pop(ctx, ImageSource.gallery),
            ),
          ],
        ),
      ),
    );
    if (source != null) await _pickPhoto(source);
  }

  Future<void> _save() async {
    setState(() => _phoneError = null);
    if (!_formKey.currentState!.validate()) return;

    if (!_numberPending) {
      final phone = _phoneController.text.trim();
      if (!PhoneNumbers.isValidPakistaniMobile(phone)) {
        setState(() {
          _phoneError = 'Enter a valid Pakistani mobile (03XXXXXXXXX)';
        });
        return;
      }
    }

    setState(() => _saving = true);
    try {
      await ref.read(databaseProvider).addCustomer(
            name: _nameController.text.trim(),
            address: _addressController.text.trim(),
            phoneNumber: _numberPending ? null : _phoneController.text.trim(),
            phonePending: _numberPending,
            referenceNote: _referenceController.text.trim(),
            photoPath: _photoPath,
          );
      if (mounted) Navigator.of(context).pop();
    } on DuplicatePhoneNumberException catch (e) {
      setState(() {
        _saving = false;
        _phoneError =
            'This number is already used by another customer (${e.phoneNumber}).';
      });
    } catch (e) {
      setState(() => _saving = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              userFacingMessage(
                e,
                fallback: 'Could not save customer. Please try again.',
              ),
            ),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Add customer')),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Center(
              child: GestureDetector(
                onTap: _choosePhotoSource,
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
              _photoPath == null
                  ? 'Photo optional — tap to add (helps when names match)'
                  : 'Photo added — tap to change',
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
                if (v == null || v.trim().isEmpty) return 'Name is required';
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
              subtitle: const Text(
                'Explicit choice only. Customer list will show an “Add number” tag.',
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
                onPressed: _saving ? null : _save,
                child: Text(_saving ? 'Saving…' : 'Save customer'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
