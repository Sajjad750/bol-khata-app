import 'package:string_similarity/string_similarity.dart';

import 'app_database.dart';

/// One ranked fuzzy-search candidate for UI confirmation.
class CustomerSearchHit {
  const CustomerSearchHit({
    required this.customer,
    required this.score,
    required this.matchedOn,
    required this.aliases,
  });

  final Customer customer;
  final double score;

  /// Which string produced the best score (primary name or an alias).
  final String matchedOn;
  final List<String> aliases;

  String get phoneNumber => customer.phoneNumber;
  String? get photoPath => customer.photoPath;
  String get name => customer.name;
  int get id => customer.id;
  double get currentBalance => customer.currentBalance;
}

/// Fuzzy search outcome. When [ambiguous] is true, the UI must not pre-select.
class CustomerSearchOutcome {
  const CustomerSearchOutcome({required this.matches, required this.ambiguous});

  final List<CustomerSearchHit> matches;

  /// True when the top two (or more) candidates score within [ambiguityMargin].
  final bool ambiguous;
}

/// Narrow score gap that triggers the ambiguous flag (0–1 similarity scale).
const double ambiguityMargin = 0.05;

/// Minimum score to include a candidate in results.
const double minMatchScore = 0.35;

String normalizeSearchText(String input) {
  return input.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
}

double similarityScore(String a, String b) {
  final na = normalizeSearchText(a);
  final nb = normalizeSearchText(b);
  if (na.isEmpty || nb.isEmpty) return 0;
  if (na == nb) return 1;
  // Dice coefficient via string_similarity (0–1). Also boost substring hits
  // common for nicknames like "ahmed" inside "cycle wala ahmed".
  final dice = na.similarityTo(nb);
  final containsBoost = na.contains(nb) || nb.contains(na) ? 0.85 : 0.0;
  return dice > containsBoost ? dice : containsBoost;
}

CustomerSearchOutcome rankCustomerMatches({
  required String query,
  required List<Customer> customers,
  required Map<int, List<String>> aliasesByCustomerId,
}) {
  final hits = <CustomerSearchHit>[];

  for (final customer in customers) {
    final aliases = aliasesByCustomerId[customer.id] ?? const <String>[];
    var bestScore = similarityScore(query, customer.name);
    var matchedOn = customer.name;

    for (final alias in aliases) {
      final score = similarityScore(query, alias);
      if (score > bestScore) {
        bestScore = score;
        matchedOn = alias;
      }
    }

    if (bestScore >= minMatchScore) {
      hits.add(
        CustomerSearchHit(
          customer: customer,
          score: bestScore,
          matchedOn: matchedOn,
          aliases: aliases,
        ),
      );
    }
  }

  hits.sort((a, b) => b.score.compareTo(a.score));

  final ambiguous =
      hits.length >= 2 && (hits[0].score - hits[1].score) <= ambiguityMargin;

  return CustomerSearchOutcome(matches: hits, ambiguous: ambiguous);
}

/// A transaction with its optional line items, for customer history views.
class TransactionWithItems {
  const TransactionWithItems({required this.transaction, required this.items});

  final Transaction transaction;
  final List<TransactionItem> items;

  bool get isVoided => transaction.isVoided;
  bool get isCorrection => transaction.reversesTransactionId != null;
}
