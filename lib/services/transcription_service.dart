import 'dart:convert';
import 'dart:io';

import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import 'package:path/path.dart' as p;

import '../l10n/app_language.dart';
import 'roman_urdu.dart';

enum TranscriptionFailureKind {
  missingApiKey,
  noInternet,
  apiFailure,
  emptyAudio,
  emptyTranscript,
  unknown,
}

class TranscriptionException implements Exception {
  TranscriptionException(
    this.message, {
    this.kind = TranscriptionFailureKind.unknown,
  });

  final String message;
  final TranscriptionFailureKind kind;

  @override
  String toString() => message;
}

/// Sends recorded audio to Groq Whisper and returns plain transcript text.
///
/// Output script follows [AppLanguage]: English, Urdu (Nastaliq), or Roman Urdu.
class TranscriptionService {
  TranscriptionService({http.Client? httpClient, this.apiKeyOverride})
    : _client = httpClient ?? http.Client();

  static const _endpoint =
      'https://api.groq.com/openai/v1/audio/transcriptions';
  static const _model = 'whisper-large-v3-turbo';

  static const _romanUrduPrompt =
      'Roman Urdu transcript. '
      'Ahmed ko paanch sau rupay udhar diya. '
      'Bilal se do hazaar wasool liya. '
      'Qwerty ko ek sau diya. '
      'Latin letters only — not English, not Hindi script.';

  static const _englishPrompt =
      'English transcript of a Pakistani shop ledger. '
      'Gave Ahmed five hundred rupees credit. '
      'Received two thousand from Bilal. '
      'Clear English only.';

  static const _urduPrompt =
      'اردو میں دکان کے کھاتے کی آڈیو کو لکھیں۔ '
      'احمد کو پانچ سو روپے ادھار دیا۔ '
      'بلال سے دو ہزار وصول لیا۔';

  final http.Client _client;

  /// Optional override for tests; otherwise reads `GROQ_API_KEY` from dotenv.
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

  String _promptFor(AppLanguage language) => switch (language) {
    AppLanguage.english => _englishPrompt,
    AppLanguage.urdu => _urduPrompt,
    AppLanguage.romanUrdu => _romanUrduPrompt,
  };

  /// Transcribes [audioFilePath] via Groq Whisper for [language].
  Future<String> transcribe(
    String audioFilePath, {
    AppLanguage language = AppLanguage.romanUrdu,
  }) async {
    final key = _apiKey;
    if (key == null || key.isEmpty || key.contains('your-groq-api-key')) {
      throw TranscriptionException(
        'Groq API key missing. Add GROQ_API_KEY to your .env file.',
        kind: TranscriptionFailureKind.missingApiKey,
      );
    }

    final file = File(audioFilePath);
    if (!await file.exists()) {
      throw TranscriptionException(
        'Recording file not found.',
        kind: TranscriptionFailureKind.emptyAudio,
      );
    }
    final length = await file.length();
    if (length < 256) {
      throw TranscriptionException(
        'Recording was too short. Hold the button and speak, then release.',
        kind: TranscriptionFailureKind.emptyAudio,
      );
    }

    final request = http.MultipartRequest('POST', Uri.parse(_endpoint));
    request.headers['Authorization'] = 'Bearer $key';
    request.fields['model'] = _model;
    request.fields['language'] = language.whisperLanguage;
    request.fields['response_format'] = 'json';
    request.fields['prompt'] = _promptFor(language);

    final filename = p.basename(audioFilePath);
    final mime = _mimeFor(filename);
    request.files.add(
      await http.MultipartFile.fromPath(
        'file',
        audioFilePath,
        filename: filename,
        contentType: mime,
      ),
    );

    late http.StreamedResponse streamed;
    try {
      streamed = await _client
          .send(request)
          .timeout(const Duration(seconds: 45));
    } on SocketException {
      throw TranscriptionException(
        'No internet connection. Check your network and try again.',
        kind: TranscriptionFailureKind.noInternet,
      );
    } on HttpException {
      throw TranscriptionException(
        'Could not reach Groq. Check your connection and try again.',
        kind: TranscriptionFailureKind.noInternet,
      );
    } catch (e) {
      final msg = e.toString().toLowerCase();
      if (msg.contains('socket') ||
          msg.contains('network') ||
          msg.contains('failed host lookup') ||
          msg.contains('timed out') ||
          msg.contains('timeout')) {
        throw TranscriptionException(
          'No internet connection. Check your network and try again.',
          kind: TranscriptionFailureKind.noInternet,
        );
      }
      throw TranscriptionException(
        'Transcription failed: $e',
        kind: TranscriptionFailureKind.unknown,
      );
    }

    final body = await streamed.stream.bytesToString();
    if (streamed.statusCode < 200 || streamed.statusCode >= 300) {
      throw TranscriptionException(
        _friendlyApiError(streamed.statusCode, body),
        kind: TranscriptionFailureKind.apiFailure,
      );
    }

    final decoded = jsonDecode(body);
    final text = decoded is Map<String, dynamic>
        ? (decoded['text'] as String?)?.trim() ?? ''
        : '';

    if (text.isEmpty) {
      throw TranscriptionException(
        'No speech detected. Try again, speaking clearly.',
        kind: TranscriptionFailureKind.emptyTranscript,
      );
    }

    switch (language) {
      case AppLanguage.romanUrdu:
        return RomanUrdu.ensure(text: text, apiKey: key, httpClient: _client);
      case AppLanguage.english:
      case AppLanguage.urdu:
        return text;
    }
  }

  void dispose() {
    _client.close();
  }

  static MediaType _mimeFor(String filename) {
    final ext = p.extension(filename).toLowerCase();
    switch (ext) {
      case '.m4a':
      case '.mp4':
        return MediaType('audio', 'mp4');
      case '.wav':
        return MediaType('audio', 'wav');
      case '.mp3':
        return MediaType('audio', 'mpeg');
      case '.webm':
        return MediaType('audio', 'webm');
      default:
        return MediaType('application', 'octet-stream');
    }
  }

  static String _friendlyApiError(int status, String body) {
    String detail = '';
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map && decoded['error'] is Map) {
        detail = (decoded['error']['message'] as String?)?.trim() ?? '';
      }
    } catch (_) {
      detail = body.trim();
    }
    if (detail.length > 180) {
      detail = '${detail.substring(0, 180)}…';
    }

    if (status == 401) {
      return 'Invalid Groq API key. Check GROQ_API_KEY in .env.';
    }
    if (status == 429) {
      return 'Groq rate limit reached. Wait a moment and try again.';
    }
    if (detail.isNotEmpty) {
      return 'Transcription failed ($status): $detail';
    }
    return 'Transcription failed (HTTP $status). Try again.';
  }
}
