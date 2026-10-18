import 'dart:convert';

import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;

import '../database/tables.dart';
import '../l10n/app_language.dart';
import 'roman_urdu.dart';

/// Confidence from the LLM parse step.
enum ParseConfidence { high, low }

/// One line item extracted from speech (editable on confirm screen).
class ParsedItem {
  ParsedItem({required this.itemName, this.quantity, this.unit, this.price});

  String itemName;
  double? quantity;
  String? unit;

  /// Line total in Rs (optional).
  double? price;

  Map<String, dynamic> toJson() => {
    'itemName': itemName,
    'quantity': quantity,
    'unit': unit,
    'price': price,
  };

  factory ParsedItem.fromJson(Map<String, dynamic> json) {
    final name =
        _asString(json['itemName'] ?? json['item_name'] ?? json['name']) ?? '';
    return ParsedItem(
      itemName: name,
      quantity: _asDouble(json['quantity'] ?? json['qty']),
      unit: _asString(json['unit']),
      price: _asDouble(
        json['price'] ?? json['amount'] ?? json['line_total'] ?? json['rs'],
      ),
    );
  }
}

/// Structured ledger draft from transcribed speech (before customer match).
class ParsedEntry {
  ParsedEntry({
    required this.spokenReference,
    required this.items,
    required this.amount,
    required this.type,
    required this.note,
    required this.confidence,
    this.rawTranscript = '',
  });

  /// Verbatim customer reference as spoken — not resolved to a DB customer yet.
  String spokenReference;
  List<ParsedItem> items;
  double? amount;
  String type; // credit_given | payment_received
  String? note;
  ParseConfidence confidence;
  String rawTranscript;

  bool get isCredit => type == TransactionType.creditGiven;
}

class EntryParseException implements Exception {
  EntryParseException(this.message);

  final String message;

  @override
  String toString() => message;
}

double? _asDouble(Object? value) {
  if (value == null) return null;
  if (value is num) return value.toDouble();
  if (value is String) {
    final cleaned = value.trim().replaceAll(',', '');
    return double.tryParse(cleaned);
  }
  return null;
}

String? _asString(Object? value) {
  if (value == null) return null;
  if (value is String) {
    final t = value.trim();
    return t.isEmpty ? null : t;
  }
  if (value is num || value is bool) return value.toString();
  return null;
}

String _normalizeType(Object? raw) {
  final s = _asString(raw)?.toLowerCase() ?? '';
  if (s == TransactionType.creditGiven ||
      s == 'credit' ||
      s == 'udhar' ||
      s == 'debit' ||
      s.contains('credit') ||
      s.contains('udhar') ||
      s.contains('diya') ||
      s.contains('given')) {
    return TransactionType.creditGiven;
  }
  if (s == TransactionType.paymentReceived ||
      s == 'payment' ||
      s == 'wasool' ||
      s == 'jama' ||
      s.contains('payment') ||
      s.contains('received') ||
      s.contains('wasool') ||
      s.contains('liya') ||
      s.contains('collected')) {
    return TransactionType.paymentReceived;
  }
  return '';
}

/// Turns transcribed speech into a structured [ParsedEntry] via an LLM.
///
/// Uses Groq (`llama-3.3-70b-versatile`) with the same `GROQ_API_KEY` as
/// Whisper transcription — one provider for the full voice pipeline.
class EntryParserService {
  EntryParserService({http.Client? httpClient, this.apiKeyOverride})
    : _client = httpClient ?? http.Client();

  static const _endpoint = 'https://api.groq.com/openai/v1/chat/completions';
  static const _model = 'llama-3.3-70b-versatile';

  final http.Client _client;
  final String? apiKeyOverride;

  String? get _apiKey {
    if (apiKeyOverride != null) {
      final trimmed = apiKeyOverride!.trim();
      return trimmed.isEmpty ? null : trimmed;
    }
    try {
      return dotenv.env['GROQ_API_KEY']?.trim();
    } catch (_) {
      return null;
    }
  }

  static String systemPromptFor(AppLanguage language) {
    final scriptRules = switch (language) {
      AppLanguage.english =>
        'ALL string fields MUST be clear English (Latin letters only).',
      AppLanguage.urdu =>
        'ALL string fields MUST be Urdu in Arabic/Nastaliq script (not Roman, not Hindi Devanagari).',
      AppLanguage.romanUrdu =>
        'ALL string fields MUST be Roman Urdu using Latin letters only (never Devanagari, never Nastaliq).',
    };
    final examples = switch (language) {
      AppLanguage.english => 'Example: "Ahmed", "five kg rice", "gave credit".',
      AppLanguage.urdu => 'Example: Urdu script names and items.',
      AppLanguage.romanUrdu =>
        'Example: "Ahmed", "paanch kilo chawal", "udhar diya".',
    };

    return '''
You extract structured khata (shop ledger) entries from Pakistani shopkeeper speech.

Return ONLY valid JSON matching this exact schema (no markdown, no commentary):
{
  "spoken_reference": string,
  "items": [ { "itemName": string, "quantity": number or null, "unit": string or null, "price": number or null } ],
  "amount": number or null,
  "type": "credit_given" or "payment_received",
  "note": string or null,
  "confidence": "high" or "low"
}

Rules:
- $scriptRules
  $examples
- spoken_reference: what the shopkeeper called the customer. Never empty.
- items: ALWAYS an array. Use [] if none. Never null.
- price: line total in rupees when spoken; null if unknown.
- amount: total rupees; prefer sum of item prices when clear.
- type: "credit_given" for udhar/credit/diya; "payment_received" for payment/wasool/liya.
- note: leftover context, else null.
- confidence: "low" if unclear; otherwise "high".

Numbers: paanch sou / five hundred = 500; paanch kilo -> qty 5 unit kg.
''';
  }

  /// Parses [transcript] into a [ParsedEntry]. Retries once on malformed JSON.
  Future<ParsedEntry> parse(
    String transcript, {
    AppLanguage language = AppLanguage.romanUrdu,
  }) async {
    final key = _apiKey;
    if (key == null || key.isEmpty || key.contains('your-groq-api-key')) {
      throw EntryParseException(
        'Groq API key missing. Add GROQ_API_KEY to your .env file.',
      );
    }

    final cleaned = transcript.trim();
    if (cleaned.isEmpty) {
      throw EntryParseException('Nothing to parse — empty transcript.');
    }

    final normalized = switch (language) {
      AppLanguage.romanUrdu => await RomanUrdu.ensure(
        text: cleaned,
        apiKey: key,
        httpClient: _client,
      ),
      AppLanguage.english || AppLanguage.urdu => cleaned,
    };

    try {
      return await _parseOnce(normalized, key, language);
    } on EntryParseException {
      try {
        return await _parseOnce(normalized, key, language);
      } on EntryParseException {
        final fallback = tryHeuristicParse(normalized);
        if (fallback != null) return fallback;
        rethrow;
      }
    }
  }

  Future<ParsedEntry> _parseOnce(
    String transcript,
    String key,
    AppLanguage language,
  ) async {
    final body = jsonEncode({
      'model': _model,
      'temperature': 0,
      'response_format': {'type': 'json_object'},
      'messages': [
        {'role': 'system', 'content': systemPromptFor(language)},
        {'role': 'user', 'content': 'Transcript:\n$transcript'},
      ],
    });

    late http.Response response;
    try {
      response = await _client
          .post(
            Uri.parse(_endpoint),
            headers: {
              'Authorization': 'Bearer $key',
              'Content-Type': 'application/json',
            },
            body: body,
          )
          .timeout(const Duration(seconds: 45));
    } catch (e) {
      throw EntryParseException(
        'Could not reach the parser. Check your internet and try again.',
      );
    }

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw EntryParseException(
        _friendlyApiError(response.statusCode, response.body),
      );
    }

    final decoded = jsonDecode(response.body) as Map<String, dynamic>;
    final content = decoded['choices']?[0]?['message']?['content'];
    if (content is! String || content.trim().isEmpty) {
      throw EntryParseException('Parser returned an empty response.');
    }

    try {
      final entry = parseJsonContent(content, fallbackTranscript: transcript);
      entry.rawTranscript = transcript;
      return entry;
    } catch (_) {
      final fallback = tryHeuristicParse(transcript);
      if (fallback != null) return fallback;
      throw EntryParseException(
        'Could not understand the voice entry. Please enter it manually.',
      );
    }
  }

  /// Visible for unit tests — maps model JSON → [ParsedEntry].
  static ParsedEntry parseJsonContent(
    String content, {
    String? fallbackTranscript,
  }) {
    final map = _extractJsonMap(content);

    var type = _normalizeType(map['type']);
    if (type.isEmpty && fallbackTranscript != null) {
      type = _guessTypeFromText(fallbackTranscript);
    }
    if (type.isEmpty) {
      type = TransactionType.creditGiven;
    }

    final confRaw = _asString(map['confidence'])?.toLowerCase();
    final confidence = confRaw == 'low'
        ? ParseConfidence.low
        : ParseConfidence.high;

    final itemsRaw = map['items'];
    final items = <ParsedItem>[];
    if (itemsRaw is List) {
      for (final row in itemsRaw) {
        if (row is Map<String, dynamic>) {
          final item = ParsedItem.fromJson(row);
          if (item.itemName.isNotEmpty) items.add(item);
        } else if (row is Map) {
          final item = ParsedItem.fromJson(Map<String, dynamic>.from(row));
          if (item.itemName.isNotEmpty) items.add(item);
        }
      }
    }

    var spoken =
        _asString(
          map['spoken_reference'] ??
              map['spokenReference'] ??
              map['customer'] ??
              map['name'],
        ) ??
        '';
    if (spoken.isEmpty && fallbackTranscript != null) {
      spoken = _guessSpokenReference(fallbackTranscript);
    }
    if (spoken.isEmpty) {
      throw const FormatException('Missing spoken_reference');
    }

    final note = _asString(map['note']);

    return ParsedEntry(
      spokenReference: spoken,
      items: items,
      amount: _asDouble(map['amount'] ?? map['total'] ?? map['rupees']),
      type: type,
      note: note,
      confidence: spoken == 'Customer' ? ParseConfidence.low : confidence,
    );
  }

  /// Best-effort local parse for common shop phrases when the LLM JSON is bad.
  static ParsedEntry? tryHeuristicParse(String transcript) {
    final text = transcript.trim();
    if (text.isEmpty) return null;

    final amount = _extractAmount(text);
    final type = _guessTypeFromText(text);
    final spoken = _guessSpokenReference(text);
    if (spoken.isEmpty) return null;
    // Need either amount or a clear payment/credit verb.
    if (amount == null && type.isEmpty) return null;

    return ParsedEntry(
      spokenReference: spoken,
      items: const [],
      amount: amount,
      type: type.isEmpty ? TransactionType.creditGiven : type,
      note: null,
      confidence: ParseConfidence.low,
      rawTranscript: text,
    );
  }

  static Map<String, dynamic> _extractJsonMap(String content) {
    var text = content.trim();
    if (text.startsWith('```')) {
      text = text
          .replaceFirst(RegExp(r'^```(?:json)?\s*', caseSensitive: false), '')
          .replaceFirst(RegExp(r'\s*```$'), '');
    }

    try {
      final decoded = jsonDecode(text);
      if (decoded is Map<String, dynamic>) return decoded;
      if (decoded is Map) return Map<String, dynamic>.from(decoded);
    } catch (_) {
      // Fall through to brace extraction.
    }

    final start = text.indexOf('{');
    final end = text.lastIndexOf('}');
    if (start >= 0 && end > start) {
      final slice = text.substring(start, end + 1);
      final decoded = jsonDecode(slice);
      if (decoded is Map<String, dynamic>) return decoded;
      if (decoded is Map) return Map<String, dynamic>.from(decoded);
    }
    throw const FormatException('No JSON object');
  }

  static String _guessTypeFromText(String text) {
    final lower = text.toLowerCase();
    if (RegExp(
      r'wasool|payment|jama|liya|جمع|وصول|received|collect',
      caseSensitive: false,
    ).hasMatch(lower)) {
      return TransactionType.paymentReceived;
    }
    if (RegExp(
      r'udhar|credit|diya|دی|ادھار|de diya|udhaar',
      caseSensitive: false,
    ).hasMatch(lower)) {
      return TransactionType.creditGiven;
    }
    return '';
  }

  static String _guessSpokenReference(String text) {
    final cleaned = text
        .replaceAll(RegExp(r'[\"“”]'), '')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    if (cleaned.isEmpty) return '';

    // "X ko …" / "X کو …"
    final ko = RegExp(
      r'^(.+?)\s+(?:ko|کو)\b',
      caseSensitive: false,
    ).firstMatch(cleaned);
    if (ko != null) {
      final name = ko.group(1)!.trim();
      if (name.isNotEmpty && name.length <= 40) return name;
    }

    final first = cleaned
        .split(' ')
        .firstWhere(
          (w) => RegExp(r'^[A-Za-z\u0600-\u06FF]{2,}').hasMatch(w),
          orElse: () => '',
        );
    if (first.length >= 2) return first;
    return 'Customer';
  }

  static double? _extractAmount(String text) {
    final lower = text.toLowerCase();

    // Digits: 500, 1,000, 100.50
    final digit = RegExp(r'(\d{1,3}(?:,\d{3})*|\d+)(?:\.\d+)?')
        .allMatches(text)
        .map((m) => double.tryParse(m.group(0)!.replaceAll(',', '')))
        .whereType<double>()
        .where((n) => n > 0)
        .toList();
    if (digit.isNotEmpty) {
      // Prefer the largest plausible rupee amount.
      digit.sort();
      return digit.last;
    }

    if (lower.contains('paanch sou') ||
        lower.contains('paanch so') ||
        lower.contains('پانچ سو')) {
      return 500;
    }
    if (lower.contains('ek hazaar') || lower.contains('ایک ہزار')) {
      return 1000;
    }
    if (lower.contains('dhai hazar') || lower.contains('dhai hazaar')) {
      return 2500;
    }
    return null;
  }

  void dispose() {
    _client.close();
  }

  static String _friendlyApiError(int status, String body) {
    String detail = '';
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map && decoded['error'] is Map) {
        detail = (decoded['error']['message'] as String?)?.trim() ?? '';
      }
    } catch (_) {}
    if (status == 401) {
      return 'Invalid Groq API key. Check GROQ_API_KEY in .env.';
    }
    if (detail.isNotEmpty) return 'Parser failed ($status): $detail';
    return 'Parser failed (HTTP $status). Try again.';
  }
}
