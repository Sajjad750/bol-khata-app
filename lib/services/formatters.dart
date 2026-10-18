import 'package:intl/intl.dart';

final _rsFormat = NumberFormat('#,##0', 'en_PK');

/// Formats a rupee amount as `Rs 1,500` (absolute value; sign handled by color).
String formatRs(num amount) {
  final abs = amount.abs();
  final whole = abs.round();
  return 'Rs ${_rsFormat.format(whole)}';
}

/// Relative time like "2 hours ago", "just now", "3 days ago".
String formatTimeAgo(DateTime? when, {DateTime? now}) {
  if (when == null) return 'No entries yet';
  final n = now ?? DateTime.now();
  var diff = n.difference(when);
  if (diff.isNegative) diff = Duration.zero;

  if (diff.inSeconds < 45) return 'just now';
  if (diff.inMinutes < 60) {
    final m = diff.inMinutes;
    return m == 1 ? '1 minute ago' : '$m minutes ago';
  }
  if (diff.inHours < 24) {
    final h = diff.inHours;
    return h == 1 ? '1 hour ago' : '$h hours ago';
  }
  if (diff.inDays < 30) {
    final d = diff.inDays;
    return d == 1 ? '1 day ago' : '$d days ago';
  }
  final months = (diff.inDays / 30).floor();
  if (months < 12) {
    return months == 1 ? '1 month ago' : '$months months ago';
  }
  final years = (diff.inDays / 365).floor();
  return years == 1 ? '1 year ago' : '$years years ago';
}

String formatTxnDate(DateTime when) {
  return DateFormat('d MMM yyyy, h:mm a').format(when);
}

/// Initials for avatar placeholder (1–2 letters).
String customerInitials(String name) {
  final parts = name
      .trim()
      .split(RegExp(r'\s+'))
      .where((p) => p.isNotEmpty)
      .toList();
  if (parts.isEmpty) return '?';
  if (parts.length == 1) {
    final s = parts.first;
    return s.substring(0, s.length >= 2 ? 2 : 1).toUpperCase();
  }
  return (parts[0][0] + parts[1][0]).toUpperCase();
}
