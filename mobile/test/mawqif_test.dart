/// «موقف بقرار» (docs/MAWAQIF.md): the model, the device store, the Today
/// card and the five screens.
///
/// The card hides itself when there is nothing to show (no steps, a failure,
/// every step gone through) and never shows a number. The hadith comes after
/// the choice; reaching the last screen marks the step gone through; the step
/// becomes a promise with source `mawqif`.
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:almorabbi/features/home/widgets/today_loop_cards.dart';
import 'package:almorabbi/features/mawaqif/data/mawqif.dart';
import 'package:almorabbi/features/onboarding/providers/onboarding_providers.dart';

import 'memory_fakes.dart';

const _ahmad =
    ActiveChildProfile(id: 12, name: 'أحمد', ageGroup: '7-9', avatarEmoji: '🧒');

List<Map<String, dynamic>> _bank([String lang = 'ar']) {
  final path = lang == 'ar'
      ? '../knowledge_base/curriculum/mawaqif/mawaqif.json'
      : '../knowledge_base/curriculum/i18n/en/mawaqif/mawaqif.json';
  final data = jsonDecode(File(path).readAsStringSync()) as Map<String, dynamic>;
  return [
    for (final i in data['items'] as List) Map<String, dynamic>.from(i as Map),
  ];
}

Map<String, dynamic> _band(String age) =>
    _bank().firstWhere((i) => i['age_group'] == age);

Widget _today() => const Scaffold(
      body: SingleChildScrollView(
        padding: EdgeInsets.all(16),
        child: TodayLoopCards(profile: _ahmad, hideFollowup: true),
      ),
    );

Future<FakeMemoryServer> _pump(WidgetTester tester,
    {List<Map<String, dynamic>>? items, bool fail = false}) async {
  final server = FakeMemoryServer()
    ..mawaqif = items ?? [_band('7-9')]
    ..failMawaqif = fail;
  await pumpMemoryApp(tester, _today(), server: server);
  await settle(tester);
  return server;
}

Future<void> _tap(WidgetTester tester, Finder f) async {
  await tester.ensureVisible(f);
  await tester.pump();
  await tester.tap(f);
  await settle(tester);
}

void main() {
  group('model', () {
    test('every item of both banks parses in full', () {
      for (final lang in ['ar', 'en']) {
        final raw = _bank(lang);
        final parsed = [for (final j in raw) ?Mawqif.fromJson(j)];
        expect(parsed, hasLength(raw.length), reason: lang);
        for (final m in parsed) {
          expect(m.choices, hasLength(3));
          expect(m.evidence.source, isNotEmpty);
        }
      }
    });

    test('the English twin carries the meaning, the Arabic its words', () {
      final ar = Mawqif.fromJson(_band('7-9'))!;
      final en = Mawqif.fromJson(
          _bank('en').firstWhere((i) => i['age_group'] == '7-9'))!;
      expect(ar.words, isNotEmpty);
      expect(en.evidence.meaning, isNotEmpty);
      expect(en.evidence.textAr, ar.evidence.textAr);
    });

    test('anything the screen cannot render in full is refused', () {
      final good = _band('7-9');
      expect(Mawqif.fromJson(null), isNull);
      expect(Mawqif.fromJson({...good, 'step': ' '}), isNull);
      expect(
          Mawqif.fromJson({
            ...good,
            'choices': (good['choices'] as List).take(2).toList(),
          }),
          isNull);
      expect(Mawqif.fromJson({...good, 'evidence': {'text_ar': 'x'}}), isNull);
    });

    test('store: per child, idempotent, survives corrupt data', () async {
      SharedPreferences.setMockInitialValues({MawaqifStore.key: '{oops'});
      final store = MawaqifStore(await SharedPreferences.getInstance());
      expect(store.doneFor(12), isEmpty);
      await store.markDone(12, 'a');
      await store.markDone(12, 'a');
      await store.markDone(7, 'b');
      expect(store.doneFor(12), {'a'});
      expect(store.doneFor(7), {'b'});
    });

    test('next is the first step not gone through', () {
      final items = [
        for (final j in _bank()) ?Mawqif.fromJson(j),
      ];
      expect(nextMawqif(items, {})!.id, items.first.id);
      expect(nextMawqif(items, {items.first.id})!.id, items[1].id);
      expect(nextMawqif(items, {for (final m in items) m.id}), isNull);
    });
  });

  group('Today card', () {
    testWidgets('shows the band\'s step, with no number', (tester) async {
      final server = await _pump(tester);
      expect(server.calls, contains('GET /api/program/mawaqif age_group=7-9'));
      expect(find.byKey(const ValueKey('today-mawqif')), findsOneWidget);
      expect(find.text('ضرب أخاه'), findsOneWidget);
    });

    testWidgets('hidden with no steps', (tester) async {
      await _pump(tester, items: []);
      expect(find.byKey(const ValueKey('today-mawqif')), findsNothing);
    });

    testWidgets('hidden on a failure', (tester) async {
      await _pump(tester, fail: true);
      expect(find.byKey(const ValueKey('today-mawqif')), findsNothing);
    });

    testWidgets('the whole step: choice → now/later → hadith → step',
        (tester) async {
      await _pump(tester);
      await _tap(tester, find.byKey(const ValueKey('today-mawqif')));

      // The situation first, no hadith yet.
      expect(find.textContaining('مزّق رسمته'), findsOneWidget);
      expect(find.textContaining('الصرعة'), findsNothing);
      await _tap(tester, find.byKey(const ValueKey('mawqif-to-choices')));

      // Three responses, none marked right.
      for (final k in ['shout', 'calm_first', 'apology']) {
        expect(find.byKey(ValueKey('mawqif-choice-$k')), findsOneWidget);
      }
      await _tap(tester, find.byKey(const ValueKey('mawqif-choice-shout')));

      // What happens now and later for the one chosen.
      expect(find.text('يتوقف الشجار في ثانية.'), findsOneWidget);
      expect(find.textContaining('الأعلى صوتًا'), findsOneWidget);
      await _tap(tester, find.byKey(const ValueKey('mawqif-compare')));
      expect(find.textContaining('ينتهي الموقف باعتذار'), findsOneWidget);
      await _tap(tester, find.byKey(const ValueKey('mawqif-to-evidence')));

      // The hadith as an answer, with its source and words.
      expect(find.textContaining('ليس الشديد بالصرعة'), findsOneWidget);
      expect(find.textContaining('حديث ٦١١٤'), findsOneWidget);
      expect(find.text('معاني الكلمات'), findsOneWidget);
      await _tap(tester, find.byKey(const ValueKey('mawqif-to-step')));

      // The step; leaving here marks it gone through.
      expect(find.textContaining('أهدأ دقيقة كاملة'), findsOneWidget);
      await _tap(tester, find.byKey(const ValueKey('mawqif-close')));
      final prefs = await SharedPreferences.getInstance();
      final done = MawaqifStore(prefs).doneFor(12);
      expect(done, {'mawqif_7-9_sibling_hit'});
      // Gone through → the card goes away (the band has only this one).
      expect(find.byKey(const ValueKey('today-mawqif')), findsNothing);
    });

    testWidgets('«سأجرّبها» asks when, then opens a mawqif promise',
        (tester) async {
      final server = await _pump(tester);
      await _tap(tester, find.byKey(const ValueKey('today-mawqif')));
      await _tap(tester, find.byKey(const ValueKey('mawqif-to-choices')));
      await _tap(tester, find.byKey(const ValueKey('mawqif-choice-calm_first')));
      await _tap(tester, find.byKey(const ValueKey('mawqif-to-evidence')));
      await _tap(tester, find.byKey(const ValueKey('mawqif-to-step')));
      await _tap(tester, find.byKey(const ValueKey('mawqif-commit')));
      expect(find.text('متى ستجرّبها مع أحمد؟'), findsOneWidget);
      await _tap(tester, find.text('الليلة'));
      await settle(tester, 12);
      // The first try meets the device-proof challenge and is retried once
      // proven; one follow-up is opened, recorded as a mawqif promise.
      final opened = server.followups.values
          .where((f) => f['source'] == 'mawqif')
          .toList();
      expect(opened, hasLength(1));
      expect(opened.single['topic'], 'siblings');
    });
  });
}
