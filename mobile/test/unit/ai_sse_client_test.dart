import 'dart:convert';

import 'package:contractorhub/features/ai/data/ai_sse_client.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('parseSseEvent', () {
    test('parses a token event with delta text', () {
      final event = parseSseEvent('token', '{"delta":"hello"}');

      expect(event, isNotNull);
      expect(event!.event, equals('token'));
      expect(event.data, equals('{"delta":"hello"}'));
      expect(event.dataJson['delta'], equals('hello'));
    });

    test('parses a tool_call event for create_trade_scope', () {
      final data = jsonEncode({
        'tool': 'create_trade_scope',
        'input': {'trade_name': 'Electrical', 'sort_order': 0},
        'id': 'tc_1',
      });
      final event = parseSseEvent('tool_call', data);

      expect(event, isNotNull);
      expect(event!.event, equals('tool_call'));
      expect(event.dataJson['tool'], equals('create_trade_scope'));
      expect(event.dataJson['id'], equals('tc_1'));

      final input = event.dataJson['input'] as Map<String, dynamic>;
      expect(input['trade_name'], equals('Electrical'));
      expect(input['sort_order'], equals(0));
    });

    test('parses a done event with stop_reason', () {
      final event = parseSseEvent('done', '{"stop_reason":"end_turn"}');

      expect(event, isNotNull);
      expect(event!.event, equals('done'));
      expect(event.dataJson['stop_reason'], equals('end_turn'));
    });

    test('parses an error event with message', () {
      final event = parseSseEvent('error', '{"message":"Something went wrong"}');

      expect(event, isNotNull);
      expect(event!.event, equals('error'));
      expect(event.dataJson['message'], equals('Something went wrong'));
    });

    test('returns null when dataLine is empty', () {
      final event = parseSseEvent('token', '');

      expect(event, isNull);
    });

    test('defaults to message event type when eventLine is empty', () {
      final event = parseSseEvent('', '{"delta":"world"}');

      expect(event, isNotNull);
      expect(event!.event, equals('message'));
      expect(event.dataJson['delta'], equals('world'));
    });

    test('dataJson returns empty map on invalid JSON', () {
      final event = parseSseEvent('token', 'not-valid-json');

      expect(event, isNotNull);
      expect(event!.event, equals('token'));
      expect(event.dataJson, equals({}));
    });

    test('parses tool_call for create_task with materials list', () {
      final data = jsonEncode({
        'tool': 'create_task',
        'input': {
          'title': 'Install conduit',
          'description': 'Run 2-inch conduit from panel to junction boxes',
          'priority': 'high',
          'estimated_hours': 4.5,
          'materials': ['2-inch conduit', 'wire nuts', 'junction boxes'],
          'sort_order': 0,
        },
        'id': 'task_1',
      });
      final event = parseSseEvent('tool_call', data);

      expect(event, isNotNull);
      expect(event!.dataJson['tool'], equals('create_task'));

      final input = event.dataJson['input'] as Map<String, dynamic>;
      expect(input['title'], equals('Install conduit'));
      expect(input['estimated_hours'], equals(4.5));

      final materials = input['materials'] as List;
      expect(materials.length, equals(3));
      expect(materials.first, equals('2-inch conduit'));
    });

    test('handles multiline delta text in token event', () {
      final event = parseSseEvent(
        'token',
        '{"delta":"Let me analyze\\nyour project requirements."}',
      );

      expect(event, isNotNull);
      expect(event!.dataJson['delta'],
          equals('Let me analyze\nyour project requirements.'));
    });
  });

  group('SseEvent', () {
    test('toString includes event and data', () {
      const event = SseEvent(event: 'token', data: '{"delta":"hi"}');
      expect(event.toString(), contains('token'));
      expect(event.toString(), contains('hi'));
    });

    test('dataJson parses complex nested object', () {
      final data = jsonEncode({
        'tool': 'create_trade_scope',
        'input': {
          'trade_name': 'Plumbing',
          'trade_type': 'plumber',
          'estimated_days': 5,
        },
      });
      final event = SseEvent(event: 'tool_call', data: data);

      expect(event.dataJson['tool'], equals('create_trade_scope'));
      final input = event.dataJson['input'] as Map<String, dynamic>;
      expect(input['trade_type'], equals('plumber'));
    });
  });
}
