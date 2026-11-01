import 'dart:convert';

enum MoodiEmotion {
  happy('Happy', 'happy', '😄', 'A little burst of joy'),
  sad('Sad', 'sad', '😢', 'A quiet, gentle mood'),
  angry('Angry', 'angry', '😠', 'A grumpy little face'),
  sleepy('Sleepy', 'sleepy', '😴', 'Time to slow down'),
  surprised('Surprised', 'surprised', '😮', 'Something unexpected!'),
  neutral('Neutral', 'neutral', '😐', 'Calm and steady');

  const MoodiEmotion(this.label, this.command, this.emoji, this.description);

  final String label;
  final String command;
  final String emoji;
  final String description;
}

/// The ESP32 firmware expects a UTF-8 text command, for example "happy".
List<int> encodeEmotionCommand(MoodiEmotion emotion) {
  return utf8.encode(emotion.command);
}
