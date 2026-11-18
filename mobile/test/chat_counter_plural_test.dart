// The chat header and the history list count questions and messages. Both
// strings were "{count} questions" / "{count} سؤال", so a first question read
// "1 questions" (seen in the 2.0.2 store screenshot) and three read "3 سؤال".
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:almorabbi/l10n/app_localizations.dart';

void main() {
  final en = lookupAppLocalizations(const Locale('en'));
  final ar = lookupAppLocalizations(const Locale('ar'));

  test('English question and message counters agree with the count', () {
    expect(en.chatTurnsCount(1), '1 question');
    expect(en.chatTurnsCount(2), '2 questions');
    expect(en.chatTurns(1), '1 question');
    expect(en.chatSessionMessages(1), '1 message');
    expect(en.chatSessionMessages(12), '12 messages');
  });

  test('Arabic counters use the dual and the plural of a few', () {
    expect(ar.chatTurnsCount(1), 'سؤال واحد');
    expect(ar.chatTurnsCount(2), 'سؤالان');
    expect(ar.chatTurnsCount(3), '3 أسئلة');
    expect(ar.chatTurnsCount(11), '11 سؤالًا');
    expect(ar.chatSessionMessages(2), 'رسالتان');
    expect(ar.chatSessionMessages(5), '5 رسائل');
  });
}
