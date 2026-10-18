import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:khata_app/database/app_database.dart';
import 'package:khata_app/database/tables.dart';
import 'package:khata_app/l10n/app_language.dart';
import 'package:khata_app/services/entry_parser_service.dart';

void main() {
  group('EntryParserService.parseJsonContent', () {
    test('plain amount credit', () {
      const json = '''
      {
        "spoken_reference": "Ahmed",
        "items": [],
        "amount": 500,
        "type": "credit_given",
        "note": null,
        "confidence": "high"
      }
      ''';
      final entry = EntryParserService.parseJsonContent(json);
      expect(entry.spokenReference, 'Ahmed');
      expect(entry.amount, 500);
      expect(entry.type, TransactionType.creditGiven);
      expect(entry.items, isEmpty);
      expect(entry.confidence, ParseConfidence.high);
    });

    test('itemized entry without total', () {
      const json = '''
      {
        "spoken_reference": "Ahmed",
        "items": [
          {"itemName": "chawal", "quantity": 5, "unit": "kg"},
          {"itemName": "cheeni", "quantity": 2, "unit": "kg"}
        ],
        "amount": null,
        "type": "credit_given",
        "note": null,
        "confidence": "high"
      }
      ''';
      final entry = EntryParserService.parseJsonContent(json);
      expect(entry.amount, isNull);
      expect(entry.items.length, 2);
      expect(entry.items[0].itemName, 'chawal');
      expect(entry.items[0].quantity, 5);
      expect(entry.items[1].unit, 'kg');
    });
  });

  test(
    'parse API + alias match + save items end-to-end (mocked LLM)',
    () async {
      final client = MockClient((request) async {
        expect(request.url.host, 'api.groq.com');
        expect(request.url.path, '/openai/v1/chat/completions');
        return http.Response(
          '''
        {
          "choices": [{
            "message": {
              "content": "{\\"spoken_reference\\":\\"cycle wala Ahmed\\",\\"items\\":[{\\"itemName\\":\\"chawal\\",\\"quantity\\":5,\\"unit\\":\\"kg\\"},{\\"itemName\\":\\"cheeni\\",\\"quantity\\":2,\\"unit\\":\\"kg\\"}],\\"amount\\":null,\\"type\\":\\"credit_given\\",\\"note\\":null,\\"confidence\\":\\"high\\"}"
            }
          }]
        }
        ''',
          200,
          headers: {'content-type': 'application/json'},
        );
      });

      final parser = EntryParserService(
        httpClient: client,
        apiKeyOverride: 'test-key',
      );

      final entry = await parser.parse(
        'Ahmed ko paanch kilo chawal aur do kilo cheeni de di',
      );
      expect(entry.spokenReference, 'cycle wala Ahmed');
      expect(entry.amount, isNull);
      expect(entry.items.length, 2);

      final db = AppDatabase.memory();
      final customer = await db.addCustomer(
        name: 'Ahmed Khan',
        phoneNumber: '03001112233',
        aliases: ['cycle wala Ahmed', 'Ahmed bhai'],
      );

      final search = await db.searchCustomers(entry.spokenReference);
      expect(search.matches, isNotEmpty);
      expect(search.matches.first.id, customer.id);
      expect(search.matches.first.matchedOn.toLowerCase(), contains('cycle'));

      // Shopkeeper enters total when voice had no amount.
      const total = 1800.0;
      await db.addTransaction(
        customerId: customer.id,
        amount: total,
        type: entry.type,
        sourceType: TransactionSourceType.voice,
        items: [
          for (final item in entry.items)
            TransactionItemInput(
              itemName: item.itemName,
              quantity: item.quantity,
              unit: item.unit,
            ),
        ],
      );

      final refreshed = (await db.getCustomer(customer.id))!;
      expect(refreshed.currentBalance, total);

      final history = await db.getTransactionsForCustomer(customer.id);
      expect(history.length, 1);
      expect(history.first.transaction.sourceType, TransactionSourceType.voice);
      expect(history.first.items.length, 2);
      expect(
        history.first.items.map((i) => i.itemName),
        containsAll(['chawal', 'cheeni']),
      );

      // Plain amount phrase path (local JSON fixture for second scenario).
      final plain = EntryParserService.parseJsonContent('''
    {
      "spoken_reference": "Ahmed",
      "items": [],
      "amount": 500,
      "type": "credit_given",
      "note": null,
      "confidence": "high"
    }
    ''');
      await db.addTransaction(
        customerId: customer.id,
        amount: plain.amount!,
        type: plain.type,
        sourceType: TransactionSourceType.voice,
      );
      expect((await db.getCustomer(customer.id))!.currentBalance, total + 500);

      await db.close();
      parser.dispose();
    },
  );

  test(
    'malformed JSON retries then fails when heuristic also cannot parse',
    () async {
      var calls = 0;
      final client = MockClient((request) async {
        calls++;
        return http.Response(
          '{"choices":[{"message":{"content":"not-json"}}]}',
          200,
          headers: {'content-type': 'application/json'},
        );
      });
      final parser = EntryParserService(
        httpClient: client,
        apiKeyOverride: 'test-key',
      );

      await expectLater(
        parser.parse('mmm hmm ...', language: AppLanguage.english),
        throwsA(isA<EntryParseException>()),
      );
      expect(calls, 2); // initial + one retry
      parser.dispose();
    },
  );

  test('heuristic recovers common Roman Urdu credit phrase', () {
    final entry = EntryParserService.tryHeuristicParse(
      'Ahmed ko 500 rupay udhar diya',
    );
    expect(entry, isNotNull);
    expect(entry!.spokenReference.toLowerCase(), contains('ahmed'));
    expect(entry.amount, 500);
    expect(entry.type, TransactionType.creditGiven);
  });
}
