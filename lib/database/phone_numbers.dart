/// Pakistani mobile helpers + pending-number placeholders for uniqueness.
abstract final class PhoneNumbers {
  static const pendingPrefix = 'pending:';

  static bool isPending(String phoneNumber) =>
      phoneNumber.startsWith(pendingPrefix);

  /// Unique placeholder stored when shopkeeper explicitly marks number pending.
  static String createPendingPlaceholder() =>
      '$pendingPrefix${DateTime.now().microsecondsSinceEpoch}';

  /// Digits-only form for comparison / validation.
  static String digitsOnly(String input) =>
      input.replaceAll(RegExp(r'[^\d]'), '');

  /// Accepts 03XXXXXXXXX, +923XXXXXXXXX, 923XXXXXXXXX (and spaced variants).
  static bool isValidPakistaniMobile(String input) {
    final raw = input.trim();
    if (raw.isEmpty || isPending(raw)) return false;

    var digits = digitsOnly(raw);
    if (digits.startsWith('92') && digits.length == 12) {
      digits = '0${digits.substring(2)}';
    }
    // 03XX XXX XXXX → 11 digits starting with 03
    return RegExp(r'^03\d{9}$').hasMatch(digits);
  }

  /// Normalize to local `03XXXXXXXXX` when valid; otherwise return trimmed input.
  static String normalize(String input) {
    final trimmed = input.trim();
    if (isPending(trimmed)) return trimmed;

    var digits = digitsOnly(trimmed);
    if (digits.startsWith('92') && digits.length == 12) {
      digits = '0${digits.substring(2)}';
    }
    if (RegExp(r'^03\d{9}$').hasMatch(digits)) return digits;
    return trimmed;
  }

  static String display(String phoneNumber) {
    if (isPending(phoneNumber)) return 'Number pending';
    return phoneNumber;
  }
}
