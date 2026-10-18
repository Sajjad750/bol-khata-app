import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../theme/khata_colors.dart';

/// Turns raw exceptions into short shopkeeper-friendly copy.
/// Backend / framework internals are never shown.
String userFacingMessage(
  Object error, {
  String fallback = 'Something went wrong. Please try again.',
}) {
  if (error is UserFacingException) return error.message;

  final raw = error.toString().trim();
  final lower = raw.toLowerCase();

  if (_looksInternal(lower, raw)) return fallback;

  var message = raw
      .replaceFirst(RegExp(r'^(Exception|Error):\s*', caseSensitive: false), '')
      .trim();
  if (message.isEmpty || message.length > 140) return fallback;
  return message;
}

bool _looksInternal(String lower, String raw) {
  const needles = [
    'socketexception',
    'clientexception',
    'handshakeexception',
    'failed host lookup',
    'connection refused',
    'connection reset',
    'network is unreachable',
    'timeout',
    'supabase',
    'postgres',
    'postgrest',
    'status code',
    'http/',
    'xmlhttprequest',
    'failed assertion',
    'package:flutter',
    'package:drift',
    'package:http',
    'stack overflow',
    'null check operator',
    'nosuchmethod',
    'typeerror',
    'rangeerror',
    'formatexception',
    'jwt',
    'api key',
    'authorization',
    'bearer ',
  ];
  for (final n in needles) {
    if (lower.contains(n)) return true;
  }
  if (raw.contains('\n') && raw.contains('#')) return true; // stack-ish
  return false;
}

/// Domain error that is already safe to show.
class UserFacingException implements Exception {
  UserFacingException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Floating snackbar — never a full-screen dump.
void showAppError(BuildContext context, Object error, {String? fallback}) {
  if (!context.mounted) return;
  final message = userFacingMessage(
    error,
    fallback: fallback ?? 'Something went wrong. Please try again.',
  );
  ScaffoldMessenger.of(context).clearSnackBars();
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(message),
      behavior: SnackBarBehavior.floating,
      backgroundColor: KhataColors.debtRed,
      duration: const Duration(seconds: 4),
    ),
  );
}

/// Install once at app start — replaces the full red/grey error screen.
void installFriendlyErrorUi() {
  ErrorWidget.builder = (details) {
    if (kDebugMode) {
      // Keep some signal for developers, but not the full red dump.
      debugPrint('UI error: ${details.exceptionAsString()}');
    }
    return const _FriendlyErrorSurface();
  };

  final previous = FlutterError.onError;
  FlutterError.onError = (details) {
    previous?.call(details);
    if (kDebugMode) {
      FlutterError.dumpErrorToConsole(details, forceReport: true);
    }
  };
}

class _FriendlyErrorSurface extends StatelessWidget {
  const _FriendlyErrorSurface();

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      child: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.error_outline,
                  size: 48,
                  color: Colors.grey.shade600,
                ),
                const SizedBox(height: 12),
                const Text(
                  'Something went wrong on this screen.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Go back and try again.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 15,
                    color: Colors.grey.shade700,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
