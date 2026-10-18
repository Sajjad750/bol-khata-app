import 'dart:convert';

import 'package:http/http.dart' as http;

/// Roman Urdu = Urdu meaning written in Latin letters
/// (e.g. "Ahmed ko paanch sau udhar diya"), never English prose,
/// Devanagari, or Nastaliq.
abstract final class RomanUrdu {
  /// Devanagari (Hindi) or Arabic/Urdu script.
  static final _indicOrArabic = RegExp(
    r'[\u0900-\u097F\u0600-\u06FF\u0750-\u077F\u08A0-\u08FF'
    r'\uFB50-\uFDFF\uFE70-\uFEFF]',
  );

  /// Common Roman Urdu / shop-khata tokens.
  static final _romanUrduCue = RegExp(
    r'\b(ko|se|ki|ka|ke|udhar|udhaar|wasool|diya|liya|de\s*diya|'
    r'rupay|rupaye|rs|hazaar|hazār|sau|sou|paanch|panch|do|teen|'
    r'jama|wasul|wasaul|bhai|sahab)\b',
    caseSensitive: false,
  );

  /// English words Whisper often emits when language is forced to `en`.
  static final _englishCue = RegExp(
    r'\b(gave|give|given|credit|received|receive|payment|rupees?|'
    r'thousand|hundred|fifty|twenty|customer|please|the|and|for)\b',
    caseSensitive: false,
  );

  static bool containsNonLatinScript(String text) =>
      _indicOrArabic.hasMatch(text);

  static bool isMostlyRoman(String text) =>
      text.trim().isNotEmpty && !containsNonLatinScript(text);

  static bool looksLikeRomanUrdu(String text) {
    if (containsNonLatinScript(text)) return false;
    return _romanUrduCue.hasMatch(text);
  }

  static bool looksLikeEnglish(String text) {
    if (containsNonLatinScript(text)) return false;
    return _englishCue.hasMatch(text) && !looksLikeRomanUrdu(text);
  }

  /// Returns Roman Urdu (Latin). Converts Urdu/Hindi script and English
  /// Whisper output into shopkeeper Roman Urdu.
  static Future<String> ensure({
    required String text,
    required String apiKey,
    http.Client? httpClient,
    String model = 'llama-3.3-70b-versatile',
  }) async {
    final cleaned = text.trim();
    if (cleaned.isEmpty) return cleaned;

    // Already good Roman Urdu — skip the extra LLM call.
    if (looksLikeRomanUrdu(cleaned) && !containsNonLatinScript(cleaned)) {
      return cleaned;
    }

    final client = httpClient ?? http.Client();
    final ownsClient = httpClient == null;
    try {
      final response = await client
          .post(
            Uri.parse('https://api.groq.com/openai/v1/chat/completions'),
            headers: {
              'Authorization': 'Bearer $apiKey',
              'Content-Type': 'application/json',
            },
            body: jsonEncode({
              'model': model,
              'temperature': 0,
              'messages': [
                {
                  'role': 'system',
                  'content':
                      'You rewrite Pakistani shopkeeper khata speech as Roman Urdu '
                      '(Latin alphabet only).\n'
                      'Hard rules:\n'
                      '- Output ONLY Roman Urdu. Never English sentences.\n'
                      '- Never Hindi Devanagari. Never Urdu/Arabic Nastaliq.\n'
                      '- Keep names, amounts, and meaning.\n'
                      '- Use words like: ko, se, udhar, wasool, diya, liya, '
                      'rupay, hazaar, sau, jama.\n'
                      '- If input is English, convert to Roman Urdu '
                      '(e.g. "gave Ahmed five hundred credit" → '
                      '"Ahmed ko paanch sau udhar diya").\n'
                      '- If input is already Roman Urdu, return it cleaned.\n'
                      '- Output one line only, no quotes or commentary.',
                },
                {'role': 'user', 'content': cleaned},
              ],
            }),
          )
          .timeout(const Duration(seconds: 30));

      if (response.statusCode < 200 || response.statusCode >= 300) {
        return cleaned;
      }
      final decoded = jsonDecode(response.body) as Map<String, dynamic>;
      final content = decoded['choices']?[0]?['message']?['content'];
      if (content is! String) return cleaned;
      final roman = content.trim().replaceAll(RegExp(r'^["“]|["”]$'), '');
      if (roman.isEmpty) return cleaned;
      if (containsNonLatinScript(roman)) return cleaned;
      return roman;
    } catch (_) {
      return cleaned;
    } finally {
      if (ownsClient) client.close();
    }
  }
}
