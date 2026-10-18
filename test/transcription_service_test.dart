import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:khata_app/services/transcription_service.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory tempDir;
  late File audioFile;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('khata_tx_');
    audioFile = File(p.join(tempDir.path, 'sample.m4a'));
    // >256 bytes so empty-audio guard passes
    await audioFile.writeAsBytes(List<int>.filled(512, 1));
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  test('transcribe returns text from Groq Whisper JSON response', () async {
    final client = MockClient((request) async {
      expect(request.url.host, 'api.groq.com');
      expect(request.url.path, '/openai/v1/audio/transcriptions');
      expect(request.method, 'POST');
      expect(request.headers['Authorization'], 'Bearer test-key');
      // MockClient sees the finalized body Request, not MultipartRequest.
      return http.Response(
        '{"text":"Ahmed ko paanch sou rupay udhar diya"}',
        200,
      );
    });

    final service = TranscriptionService(
      httpClient: client,
      apiKeyOverride: 'test-key',
    );

    final text = await service.transcribe(audioFile.path);
    expect(text, 'Ahmed ko paanch sou rupay udhar diya');
    service.dispose();
  });

  test('missing API key throws clear error', () async {
    final service = TranscriptionService(
      httpClient: MockClient((_) async => http.Response('', 500)),
      apiKeyOverride: '',
    );

    expect(
      () => service.transcribe(audioFile.path),
      throwsA(
        isA<TranscriptionException>().having(
          (e) => e.kind,
          'kind',
          TranscriptionFailureKind.missingApiKey,
        ),
      ),
    );
    service.dispose();
  });

  test('API failure surfaces friendly message', () async {
    final client = MockClient((request) async {
      return http.Response('{"error":{"message":"Invalid file format"}}', 400);
    });
    final service = TranscriptionService(
      httpClient: client,
      apiKeyOverride: 'test-key',
    );

    try {
      await service.transcribe(audioFile.path);
      fail('expected TranscriptionException');
    } on TranscriptionException catch (e) {
      expect(e.kind, TranscriptionFailureKind.apiFailure);
      expect(e.message, contains('Invalid file format'));
    }
    service.dispose();
  });
}
