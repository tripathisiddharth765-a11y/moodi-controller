import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:moodi_app/models/moodi_emotion.dart';

void main() {
  group('MOODI emotion protocol', () {
    test('contains exactly the six commands supported by the ESP32', () {
      final commands = MoodiEmotion.values.map((emotion) => emotion.command).toSet();

      expect(commands, <String>{
        'happy',
        'sad',
        'angry',
        'sleepy',
        'surprised',
        'neutral',
      });
      expect(MoodiEmotion.values, hasLength(6));
    });

    test('encodes each command as plain UTF-8 text without extra bytes', () {
      for (final emotion in MoodiEmotion.values) {
        final payload = encodeEmotionCommand(emotion);
        expect(utf8.decode(payload), emotion.command);
        expect(payload, isNot(contains(10))); // no newline
        expect(payload, isNot(contains(13))); // no carriage return
      }
    });
  });
}
