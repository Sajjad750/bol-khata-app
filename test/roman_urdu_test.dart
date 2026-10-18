import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:khata_app/services/roman_urdu.dart';

void main() {
  test('detects Hindi Devanagari and Urdu script', () {
    expect(RomanUrdu.containsNonLatinScript('अहमद को पांच सौ'), isTrue);
    expect(RomanUrdu.containsNonLatinScript('احمد کو پانچ سو'), isTrue);
    expect(RomanUrdu.containsNonLatinScript('Ahmed ko paanch sau'), isFalse);
  });

  test('classifies Roman Urdu vs English', () {
    expect(
      RomanUrdu.looksLikeRomanUrdu('Ahmed ko paanch sau udhar diya'),
      isTrue,
    );
    expect(
      RomanUrdu.looksLikeEnglish('Gave Ahmed five hundred credit'),
      isTrue,
    );
    expect(
      RomanUrdu.looksLikeEnglish('Ahmed ko paanch sau udhar diya'),
      isFalse,
    );
  });

  test('ensure skips LLM when already Roman Urdu', () async {
    var calls = 0;
    final client = MockClient((request) async {
      calls++;
      return http.Response('{}', 500);
    });

    final out = await RomanUrdu.ensure(
      text: 'Ahmed ko paanch sau udhar diya',
      apiKey: 'test-key',
      httpClient: client,
    );
    expect(out, 'Ahmed ko paanch sau udhar diya');
    expect(calls, 0);
  });

  test('ensure converts English Whisper output to Roman Urdu', () async {
    final client = MockClient((request) async {
      expect(request.url.path, '/openai/v1/chat/completions');
      return http.Response(
        '{"choices":[{"message":{"content":"Ahmed ko paanch sau udhar diya"}}]}',
        200,
        headers: {'content-type': 'application/json'},
      );
    });

    final out = await RomanUrdu.ensure(
      text: 'Gave Ahmed five hundred on credit',
      apiKey: 'test-key',
      httpClient: client,
    );
    expect(out, 'Ahmed ko paanch sau udhar diya');
  });

  test('ensure transliterates Hindi script via LLM', () async {
    final client = MockClient((request) async {
      expect(request.url.path, '/openai/v1/chat/completions');
      return http.Response(
        '{"choices":[{"message":{"content":"Ahmed ko paanch sau udhar diya"}}]}',
        200,
        headers: {'content-type': 'application/json'},
      );
    });

    final out = await RomanUrdu.ensure(
      text: 'अहमद को पांच सौ उधार दिया',
      apiKey: 'test-key',
      httpClient: client,
    );
    expect(out, 'Ahmed ko paanch sau udhar diya');
    expect(RomanUrdu.containsNonLatinScript(out), isFalse);
  });
}
