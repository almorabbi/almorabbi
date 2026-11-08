/// «مهمة اليوم» on Today for the parent — no handover (2026-11-08).
///
/// Production had 4 real confirmations in 28 days: the only road went through
/// child mode. Here the parent reads the card, marks it, and may send the
/// child a «كلمة طيبة». The row never shows a number, a coin or a "missed"
/// state, hides itself when there is nothing to show, and a dismissed sheet
/// sends nothing.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:almorabbi/features/home/widgets/today_loop_cards.dart';
import 'package:almorabbi/features/onboarding/providers/onboarding_providers.dart';

import 'memory_fakes.dart';

const _ahmad =
    ActiveChildProfile(id: 12, name: 'أحمد', ageGroup: '7-9', avatarEmoji: '🧒');

const _title = 'اسقِ نبتة البيت';

class _MissionServer extends FakeMemoryServer {
  Map<String, dynamic>? card = {
    'mission_id': null,
    'mission_key': 'mission_7-9_water_plant',
    'status': 'preview',
    'title_ar': _title,
    'instruction_ar': 'املأ الإبريق واسقِ النبتة وحدك.',
  };
  bool failGet = false;
  bool expired = false;
  final List<({int childId, String key, String? note})> done = [];

  @override
  Future<Map<String, dynamic>?> fetchParentMissionToday(int childId) async {
    if (failGet) throw Exception('offline');
    return card;
  }

  @override
  Future<bool> markParentMissionDone(int childId,
      {required String missionKey, String? note}) async {
    done.add((childId: childId, key: missionKey, note: note));
    return !expired;
  }
}

Widget _today() => const Scaffold(
      body: SingleChildScrollView(
        padding: EdgeInsets.all(16),
        child: TodayLoopCards(profile: _ahmad, hideFollowup: true),
      ),
    );

Future<_MissionServer> _pump(WidgetTester tester, [_MissionServer? s]) async {
  final server = s ?? _MissionServer();
  await pumpMemoryApp(tester, _today(), server: server);
  await settle(tester);
  return server;
}

Future<void> _tapDone(WidgetTester tester) async {
  await tester.ensureVisible(find.text('أُنجزت'));
  await tester.pump();
  await tester.tap(find.text('أُنجزت'));
  await settle(tester);
}

void main() {
  testWidgets('shows today\'s card for the active child', (tester) async {
    await _pump(tester);
    expect(find.text('مهمة اليوم لـأحمد'), findsOneWidget);
    expect(find.text(_title), findsOneWidget);
    expect(find.text('أُنجزت'), findsOneWidget);
  });

  testWidgets('done with a chip: the note is sent, the row says it plainly', (
    tester,
  ) async {
    final server = await _pump(tester);
    await _tapDone(tester);
    expect(find.text('كلمة طيبة لـأحمد؟'), findsOneWidget);
    await tester.tap(find.text('فخورون بك'));
    await settle(tester);
    await tester.tap(find.text('أرسل'));
    await settle(tester);
    expect(server.done.single.key, 'mission_7-9_water_plant');
    expect(server.done.single.note, 'فخورون بك');
    expect(find.text('أنجز أحمد مهمة اليوم'), findsOneWidget);
    expect(find.text('أُنجزت'), findsNothing);
  });

  testWidgets('done without a word sends no note', (tester) async {
    final server = await _pump(tester);
    await _tapDone(tester);
    await tester.tap(find.text('تمّ، بلا كلمة'));
    await settle(tester);
    expect(server.done.single.note, anyOf(isNull, isEmpty));
    expect(find.text('أنجز أحمد مهمة اليوم'), findsOneWidget);
  });

  testWidgets('a dismissed sheet sends nothing', (tester) async {
    final server = await _pump(tester);
    await _tapDone(tester);
    await tester.tapAt(const Offset(10, 10)); // the barrier
    await settle(tester);
    expect(server.done, isEmpty);
    expect(find.text('أُنجزت'), findsOneWidget);
  });

  testWidgets('a card the child already finished reads as done', (tester) async {
    final server = _MissionServer()
      ..card = {
        'mission_id': 7,
        'mission_key': 'mission_7-9_water_plant',
        'status': 'confirmed',
        'title_ar': _title,
      };
    await _pump(tester, server);
    expect(find.text('أنجز أحمد مهمة اليوم'), findsOneWidget);
    expect(find.text('أُنجزت'), findsNothing);
  });

  testWidgets('an expired card goes quietly', (tester) async {
    final server = await _pump(tester, _MissionServer()..expired = true);
    await _tapDone(tester);
    await tester.tap(find.text('تمّ، بلا كلمة'));
    await settle(tester);
    expect(find.text(_title), findsNothing);
    expect(find.byType(SnackBar), findsNothing);
    expect(server.done, hasLength(1));
  });

  testWidgets('no bank, or no server: nothing shown', (tester) async {
    await _pump(tester, _MissionServer()..card = null);
    expect(find.textContaining('مهمة اليوم'), findsNothing);
  });

  testWidgets('a failed load shows nothing and throws nothing', (tester) async {
    await _pump(tester, _MissionServer()..failGet = true);
    expect(find.textContaining('مهمة اليوم'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('no number, no coin, no "missed" anywhere on the row', (tester) async {
    await _pump(tester);
    final texts = tester
        .widgetList<Text>(find.descendant(
            of: find.byType(TodayLoopCards), matching: find.byType(Text)))
        .map((t) => t.data ?? '')
        .where((t) => t.contains('مهمة') || t.contains('أُنجزت'));
    for (final t in texts) {
      expect(RegExp(r'[0-9٠-٩]').hasMatch(t), isFalse, reason: t);
      for (final banned in ['عملة', 'نقاط', 'فاتك', 'أجر', 'ثواب']) {
        expect(t.contains(banned), isFalse, reason: '$banned in $t');
      }
    }
  });
}
