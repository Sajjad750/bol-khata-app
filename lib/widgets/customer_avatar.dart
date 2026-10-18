import 'dart:io';

import 'package:flutter/material.dart';

import '../services/formatters.dart';

const _avatarGreen = Color(0xFF0F7A4C);

class CustomerAvatar extends StatelessWidget {
  const CustomerAvatar({
    super.key,
    required this.name,
    this.photoPath,
    this.radius = 28,
  });

  final String name;
  final String? photoPath;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final size = radius * 2;
    final path = photoPath;
    final hasFile = path != null && path.isNotEmpty && File(path).existsSync();

    if (hasFile) {
      return ClipOval(
        child: Image.file(
          File(path),
          width: size,
          height: size,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => _InitialsDisk(name: name, size: size),
        ),
      );
    }
    return _InitialsDisk(name: name, size: size);
  }
}

class _InitialsDisk extends StatelessWidget {
  const _InitialsDisk({required this.name, required this.size});

  final String name;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: const BoxDecoration(
        color: Color(0xFFE6F2EC),
        shape: BoxShape.circle,
      ),
      child: Text(
        customerInitials(name),
        style: TextStyle(
          color: _avatarGreen,
          fontWeight: FontWeight.w700,
          fontSize: size * 0.34,
        ),
      ),
    );
  }
}
