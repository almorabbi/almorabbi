/// Question packs — the four games' content lives in
/// `assets/content/games/*.ar.json` since 2026-08-13, not in Dart literals.
///
/// What these pin is what the move could plausibly have broken: the shape of
/// each pack, the level fallback the old `switch`'s `default:` arm provided,
/// and the rule that made the move safe — which option is right is carried by
/// its key, not by where it sits.
library;

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:almorabbi/features/games/shared/edu_game_models.dart';
import 'package:almorabbi/features/games/shared/edu_game_ui.dart';
import 'package:almorabbi/l10n/app_localizations.dart';
import 'package:almorabbi/l10n/content_direction.dart';

/// The four packs, by the id the shell loads them with ([EduGameTheme.id]).
const _games = ['data_defender', 'tree_of_deeds', 'emotion_maze', 'healthy_hero'];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    EduGameContent.resetCacheForTesting();
  });

  group('question packs', () {
    test('every game ships a pack of 10 levels × 5 questions', () async {
      for (final game in _games) {
        final pack = await EduGameContent.load(game);
        expect(pack.game, game);
        expect(pack.questionCount, 50, reason: game);
        for (var level = 1; level <= 10; level++) {
          expect(pack.forLevel(level).length, 5, reason: '$game level $level');
        }
      }
    });

    test('an unknown level falls back to level 1, as the old switch did',
        () async {
      final pack = await EduGameContent.load('tree_of_deeds');
      expect(pack.forLevel(99).first.id, pack.forLevel(1).first.id);
      expect(pack.forLevel(0).first.id, pack.forLevel(1).first.id);
    });

    test('ids are namespaced per game so a flat map cannot collide', () async {
      // All four packs used q_0..q_49. Merging them on those ids would have
      // collided four ways and silently kept one game's wording.
      final seen = <String>{};
      for (final game in _games) {
        final pack = await EduGameContent.load(game);
        for (var level = 1; level <= 10; level++) {
          for (final q in pack.forLevel(level)) {
            expect(q.id, startsWith('$game.'), reason: q.id);
            expect(seen.add(q.id), isTrue, reason: 'duplicate id ${q.id}');
          }
        }
      }
      expect(seen.length, 200);
    });

    test('correctness is carried by key, not by position', () async {
      // A translated pack will carry key + text and no verdict; correctness is
      // merged in from here by key. That only holds if the keys are present
      // and distinct, and exactly one option is right. Not ordered: the list
      // order is deliberately spread (balance_quiz_answer_positions.py) and
      // each key travels with its option.
      for (final game in _games) {
        final pack = await EduGameContent.load(game);
        for (var level = 1; level <= 10; level++) {
          for (final q in pack.forLevel(level)) {
            expect(q.options.length, 4, reason: q.id);
            expect(q.options.map((o) => o.key).toSet(), {'a', 'b', 'c', 'd'},
                reason: q.id);
            expect(q.options.where((o) => o.isCorrect).length, 1, reason: q.id);
            expect(q.options.every((o) => o.text.trim().isNotEmpty), isTrue,
                reason: q.id);
          }
        }
      }
    });

    test('the right answer has no favourite slot', () async {
      // Until 2026-10-21 it was first in 200 of 200: a child tapping the top
      // option won every game without reading. Options render in pack order.
      final slots = <int, int>{};
      for (final game in _games) {
        final pack = await EduGameContent.load(game);
        for (var level = 1; level <= 10; level++) {
          final inLevel = [
            for (final q in pack.forLevel(level))
              q.options.indexWhere((o) => o.isCorrect),
          ];
          for (final s in inLevel) {
            slots[s] = (slots[s] ?? 0) + 1;
          }
          expect(inLevel.toSet().length, greaterThan(1),
              reason: '$game level $level: one slot for every question');
        }
      }
      final total = slots.values.fold(0, (a, b) => a + b);
      expect(total, 200);
      for (final e in slots.entries) {
        expect(e.value / total, lessThanOrEqualTo(0.40),
            reason: 'slot ${e.key}: ${e.value}/$total — $slots');
      }
    });

    test('an option with no stated verdict is not treated as correct', () {
      // A translated pack omits `is_correct`. Defaulting a missing verdict to
      // true would mark every wrong answer right.
      final pack = EduQuestionPack.fromJson({
        'game': 'x',
        'levels': [
          {
            'level': 1,
            'questions': [
              {
                'id': 'x.q_0',
                'question': 'q',
                'options': [
                  {'key': 'a', 'text': 'a'},
                  {'key': 'b', 'text': 'b'},
                ],
              }
            ],
          }
        ],
      });
      expect(pack.forLevel(1).first.options.every((o) => !o.isCorrect), isTrue);
    });

    test('the level-1 content the games shipped with is still there', () async {
      // Pinned from the Dart literals this pack replaced.
      final tree = await EduGameContent.load('tree_of_deeds');
      expect(tree.forLevel(1).first.category, 'الأمانة');
      expect(tree.forLevel(1).first.id, 'tree_of_deeds.q_0');
      final healthy = await EduGameContent.load('healthy_hero');
      expect(healthy.forLevel(1).first.options.length, 4);
    });
  });

  group('English question packs (*.en.json)', () {
    test('every game ships an English pack of 10 levels × 5 questions merged with canonical verdicts',
        () async {
      final arabicScript = RegExp(r'[\u0600-\u06FF]');
      for (final game in _games) {
        expect(
          EduGameContent.assetPath(game, locale: 'en'),
          'assets/content/games/$game.en.json',
        );
        final arPack = await EduGameContent.load(game, locale: 'ar');
        final enPack = await EduGameContent.load(game, locale: 'en');
        expect(enPack.game, game);
        expect(enPack.questionCount, 50, reason: '$game en count');

        for (var level = 1; level <= 10; level++) {
          final arQs = arPack.forLevel(level);
          final enQs = enPack.forLevel(level);
          expect(enQs.length, 5, reason: '$game en level $level');

          for (var i = 0; i < 5; i++) {
            final arQ = arQs[i];
            final enQ = enQs[i];
            expect(enQ.id, arQ.id, reason: '$game level $level index $i');
            expect(enQ.question.trim(), isNotEmpty, reason: enQ.id);
            expect(arabicScript.hasMatch(enQ.question), isFalse,
                reason: '${enQ.id} question still has Arabic script');
            expect(
              ContentDirectionality.resolve(text: enQ.question),
              TextDirection.ltr,
              reason: '${enQ.id} direction',
            );
            if (enQ.category != null) {
              expect(arabicScript.hasMatch(enQ.category!), isFalse,
                  reason: '${enQ.id} category still has Arabic script');
            }

            expect(enQ.options.length, 4, reason: enQ.id);
            expect(enQ.options.map((o) => o.key).toSet(),
                {'a', 'b', 'c', 'd'},
                reason: enQ.id);
            expect(enQ.options.where((o) => o.isCorrect).length, 1,
                reason: '${enQ.id} must have exactly 1 correct option');

            for (var j = 0; j < 4; j++) {
              final arOpt = arQ.options[j];
              final enOpt = enQ.options[j];
              expect(enOpt.key, arOpt.key, reason: '${enQ.id} opt $j key');
              expect(enOpt.isCorrect, arOpt.isCorrect,
                  reason: '${enQ.id} opt ${enOpt.key} verdict mismatch');
              expect(enOpt.text.trim(), isNotEmpty,
                  reason: '${enQ.id} opt ${enOpt.key}');
              expect(arabicScript.hasMatch(enOpt.text), isFalse,
                  reason: '${enQ.id} opt ${enOpt.key} has Arabic script');
              expect(enOpt.rationale.trim(), isNotEmpty,
                  reason: '${enQ.id} opt ${enOpt.key} rationale');
              expect(arabicScript.hasMatch(enOpt.rationale), isFalse,
                  reason:
                      '${enQ.id} opt ${enOpt.key} rationale has Arabic script');
            }
          }
        }
      }
    });

    test('English options are in the Arabic pack\'s order, so the right answer is spread in both languages',
        () async {
      for (final game in _games) {
        final arPack = await EduGameContent.load(game, locale: 'ar');
        final enPack = await EduGameContent.load(game, locale: 'en');
        for (var level = 1; level <= 10; level++) {
          final arQs = arPack.forLevel(level);
          final enQs = enPack.forLevel(level);
          for (var i = 0; i < arQs.length; i++) {
            expect(
              [for (final o in enQs[i].options) o.key],
              [for (final o in arQs[i].options) o.key],
              reason: '${arQs[i].id} option order differs between ar and en',
            );
          }
        }
      }
    });

    test('raw .en.json files omit is_correct so canonical pack remains single source of truth',
        () async {
      for (final game in _games) {
        final raw = await rootBundle.loadString(
          EduGameContent.assetPath(game, locale: 'en'),
        );
        final json = jsonDecode(raw) as Map<String, dynamic>;
        for (final level in (json['levels'] as List<dynamic>)) {
          for (final q
              in ((level as Map<String, dynamic>)['questions'] as List<dynamic>)) {
            final qMap = q as Map<String, dynamic>;
            for (final o in (qMap['options'] as List<dynamic>)) {
              final oMap = o as Map<String, dynamic>;
              expect(
                oMap.containsKey('is_correct'),
                isFalse,
                reason: '${qMap['id']} option ${oMap['key']} should not carry is_correct',
              );
            }
          }
        }
      }
    });

    test('merging verdicts from canonical works even when translated options are reordered',
        () {
      final canonical = EduQuestionPack.fromJson({
        'game': 'x',
        'levels': [
          {
            'level': 1,
            'questions': [
              {
                'id': 'x.q_0',
                'question': 'سؤال',
                'options': [
                  {'key': 'a', 'text': 'أ', 'is_correct': false},
                  {'key': 'b', 'text': 'ب', 'is_correct': true},
                  {'key': 'c', 'text': 'ج', 'is_correct': false},
                  {'key': 'd', 'text': 'د', 'is_correct': false},
                ],
              }
            ],
          }
        ],
      });

      final translated = EduQuestionPack.fromJson(
        {
          'game': 'x',
          'levels': [
            {
              'level': 1,
              'questions': [
                {
                  'id': 'x.q_0',
                  'question': 'Question',
                  'options': [
                    {'key': 'd', 'text': 'Option D'},
                    {'key': 'c', 'text': 'Option C'},
                    {'key': 'b', 'text': 'Option B'},
                    {'key': 'a', 'text': 'Option A'},
                  ],
                }
              ],
            }
          ],
        },
        canonical: canonical,
      );

      final opts = translated.forLevel(1).first.options;
      expect(opts.singleWhere((o) => o.isCorrect).key, 'b');
      expect(opts.singleWhere((o) => o.isCorrect).text, 'Option B');
      expect(opts.where((o) => !o.isCorrect).map((o) => o.key).toList(),
          ['d', 'c', 'a']);
    });

    test('an unknown locale falls back to the canonical Arabic pack', () async {
      expect(
        EduGameContent.assetPath('data_defender', locale: 'fr'),
        'assets/content/games/data_defender.ar.json',
      );
      final pack = await EduGameContent.load('data_defender', locale: 'fr');
      final arPack = await EduGameContent.load('data_defender', locale: 'ar');
      expect(
        pack.forLevel(1).first.question,
        arPack.forLevel(1).first.question,
      );
    });
  });

  group('GameTier & EduGameTheme localization', () {
    test('GameTier resolves Arabic and English labels by locale', () {
      expect(GameTier.easy.labelForLocale('ar'), 'سهل');
      expect(GameTier.normal.labelForLocale('ar'), 'عادي');
      expect(GameTier.hard.labelForLocale('ar'), 'صعب');
      expect(GameTier.expert.labelForLocale('ar'), 'خبير');

      expect(GameTier.easy.labelForLocale('en'), 'Easy');
      expect(GameTier.normal.labelForLocale('en_US'), 'Normal');
      expect(GameTier.hard.labelForLocale('EN'), 'Hard');
      expect(GameTier.expert.labelForLocale('en'), 'Expert');
    });

    test('EduGameTheme resolves Arabic and English names and descriptions', () {
      const themes = [
        EduGameTheme.dataDefender,
        EduGameTheme.healthyHero,
        EduGameTheme.emotionMaze,
        EduGameTheme.treeOfDeeds,
      ];
      final arabicScript = RegExp(r'[\u0600-\u06FF]');

      for (final theme in themes) {
        expect(arabicScript.hasMatch(theme.nameForLocale('ar')), isTrue,
            reason: '${theme.id} ar name');
        expect(arabicScript.hasMatch(theme.descriptionForLocale('ar')), isTrue,
            reason: '${theme.id} ar description');

        expect(theme.nameForLocale('en'), isNotEmpty,
            reason: '${theme.id} en name');
        expect(arabicScript.hasMatch(theme.nameForLocale('en')), isFalse,
            reason: '${theme.id} en name has Arabic');
        expect(theme.descriptionForLocale('en'), isNotEmpty,
            reason: '${theme.id} en description');
        expect(arabicScript.hasMatch(theme.descriptionForLocale('en')), isFalse,
            reason: '${theme.id} en description has Arabic');
      }
    });

    testWidgets('EduLevelSelectionScreen renders localized title, description, and tier labels in English and Arabic',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: EduLevelSelectionScreen(
            theme: EduGameTheme.dataDefender,
            progress: const EduGameProgress(gameId: 'data_defender'),
            onPlay: (_) {},
            onBack: () {},
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Data Defender'), findsWidgets);
      expect(find.text('Easy'), findsWidgets);
      expect(find.text('Normal'), findsWidgets);
      expect(find.text('حارس البيانات'), findsNothing);
      expect(find.text('سهل'), findsNothing);

      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('ar'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: EduLevelSelectionScreen(
            theme: EduGameTheme.dataDefender,
            progress: const EduGameProgress(gameId: 'data_defender'),
            onPlay: (_) {},
            onBack: () {},
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('حارس البيانات'), findsWidgets);
      expect(find.text('سهل'), findsWidgets);
      expect(find.text('Data Defender'), findsNothing);
      expect(find.text('Easy'), findsNothing);
    });
  });

  group('EduGameProgress Tests', () {
    test('EduGameProgress initialization and getters', () {
      const progress = EduGameProgress(
        gameId: 'test_game',
        totalScore: 120,
        gamesPlayed: 5,
      );

      expect(progress.gameId, 'test_game');
      expect(progress.totalScore, 120);
      expect(progress.gamesPlayed, 5);
      expect(progress.highestUnlockedLevel, 1);
    });
  });
}
