from pathlib import Path

path = Path(r"C:\digikhata\khata_app\lib\services\entry_parser_service.dart")
text = path.read_text(encoding="utf-8")

start = text.index("  static const systemPrompt = ")
end = text.index("    late http.Response response;", start)

new_block = """  static String systemPromptFor(AppLanguage language) {
    final scriptRules = switch (language) {
      AppLanguage.english =>
        'ALL string fields MUST be clear English (Latin letters only).',
      AppLanguage.urdu =>
        'ALL string fields MUST be Urdu in Arabic/Nastaliq script (not Roman, not Hindi Devanagari).',
      AppLanguage.romanUrdu =>
        'ALL string fields MUST be Roman Urdu using Latin letters only (never Devanagari, never Nastaliq).',
    };
    final examples = switch (language) {
      AppLanguage.english =>
        'Example: \"Ahmed\", \"five kg rice\", \"gave credit\".',
      AppLanguage.urdu =>
        'Example: Urdu script names and items.',
      AppLanguage.romanUrdu =>
        'Example: \"Ahmed\", \"paanch kilo chawal\", \"udhar diya\".',
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
- \$scriptRules
  \$examples
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
        {
          'role': 'user',
          'content': 'Transcript:\\n\$transcript',
        },
      ],
    });

    late http.Response response;
"""

# Unescape for Dart: we want $scriptRules and $transcript and \n in Dart source
new_block = (
    new_block.replace("\\$scriptRules", "$scriptRules")
    .replace("\\$examples", "$examples")
    .replace("\\\\n\\$transcript", "\\n$transcript")
    .replace("\\n\\$transcript", "\\n$transcript")
)

path.write_text(text[:start] + new_block + text[end:], encoding="utf-8")
print("patched ok", start, end)
