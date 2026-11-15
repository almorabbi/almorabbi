/// Tests for «فوازير نور العائلية» (Family Brain Puzzles):
///  1. Bilingual content pack parity, SVG existence, Sharia/copy guardrails,
///     and compressed Gemini Ultra hero art size.
///  2. Pure BFS solver across all 4 rotating water-canal puzzles.
///  3. Deterministic 3-skill daily round picker, per-child store persistence,
///     and account-deletion cleanup via `clearPreferencesForFreshStart`.
///  4. Widget tests for AR RTL, EN LTR, Dark Mode, 360x800 @ 2.0x text scale,
///     Child Mode spent budget lock, all 4 puzzle stages, «همسة للمربّي»,
///     reset flow, daily round completion + offscreen activity card, and
///     entry points on `GamesScreen` and `TodayFamilyPuzzlesCard`.
library;

import 'dart:convert';
import 'dart:io';

import 'package:almorabbi/api/tg_client.dart';
import 'package:almorabbi/core/app_routes.dart';
import 'package:almorabbi/core/clock.dart';
import 'package:almorabbi/features/child_memory/data/local_wipe.dart';
import 'package:almorabbi/features/family_puzzles/data/family_puzzle_models.dart';
import 'package:almorabbi/features/family_puzzles/data/family_puzzle_store.dart';
import 'package:almorabbi/features/family_puzzles/screens/family_puzzle_runner_screen.dart';
import 'package:almorabbi/features/family_puzzles/screens/family_puzzles_screen.dart';
import 'package:almorabbi/features/family_puzzles/widgets/today_family_puzzles_card.dart';
import 'package:almorabbi/features/games/screens/games_screen.dart';
import 'package:almorabbi/features/routine/providers/child_mode_providers.dart';
import 'package:almorabbi/l10n/app_localizations.dart';
import 'package:almorabbi/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _NullClient implements TgClient {
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _StubChildMode extends ChildModeNotifier {
  _StubChildMode(ChildModeState initial) : super(_NullClient()) {
    state = initial;
  }
}

final RegExp _emojiRe = RegExp(r'[\u{1F300}-\u{1FAFF}\u{2600}-\u{27BF}]',
    unicode: true);

final RegExp _forbiddenCopyRe = RegExp(
  r'بابا|ماما|\bmom\b|\bdad\b|أمك|أبوك|غدًا|سلسلة|سلاسل|نقاط|عملة|عملات|فاتك|فاتت|'
  r'أجر|ثواب|\bstreak\b|\bcoin\b|\bmissed\b|\breward\b',
  caseSensitive: false,
);

const Set<String> _livingPropKeywords = {
  'bird',
  'cat',
  'dog',
  'puppy',
  'fox',
  'deer',
  'fish',
  'boy',
  'girl',
  'face',
  'person',
  'human',
  'child',
  'parent',
  'animal',
};

Iterable<String> _collectTexts(dynamic node) sync* {
  if (node is String) {
    yield node;
  } else if (node is List) {
    for (final item in node) {
      yield* _collectTexts(item);
    }
  } else if (node is Map) {
    for (final val in node.values) {
      yield* _collectTexts(val);
    }
  }
}

void _assertSvgExists(String name, String reason) {
  final file = File('assets/svg/stories/$name.svg');
  expect(file.existsSync(), isTrue, reason: 'Missing SVG $name ($reason)');
  final lower = name.toLowerCase();
  for (final kw in _livingPropKeywords) {
    expect(lower.contains(kw), isFalse,
        reason: 'Living prop keyword "$kw" in "$name" ($reason)');
  }
}

Widget _wrap({
  required Widget home,
  Locale locale = const Locale('ar'),
  ThemeMode themeMode = ThemeMode.light,
  double textScale = 1.0,
  List<Override> overrides = const [],
}) {
  return ProviderScope(
    overrides: [
      clockProvider.overrideWithValue(() => DateTime(2026, 11, 15, 10, 0)),
      ...overrides,
    ],
    child: MaterialApp(
      locale: locale,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: themeMode,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(
          textScaler: TextScaler.linear(textScale),
        ),
        child: child!,
      ),
      home: home,
    ),
  );
}

Future<void> _solveSpotDiff(
  WidgetTester tester,
  FamilyPuzzle puzzle,
) async {
  final sceneFinder = find.byKey(const ValueKey('spot_diff_top_scene'));
  await tester.ensureVisible(sceneFinder);
  await tester.pumpAndSettle();
  final box = tester.renderObject<RenderBox>(sceneFinder);
  final topLeft = box.localToGlobal(Offset.zero);
  for (final diff in puzzle.spotDiff!.differences) {
    final pt = topLeft +
        Offset(box.size.width * diff.hitX, box.size.height * diff.hitY);
    await tester.tapAt(pt);
    await tester.pump();
  }
  await tester.pumpAndSettle();
}

Future<void> _solveWaterSingleSprout(WidgetTester tester) async {
  const taps = <(int, int, int)>[
    (0, 0, 2),
    (1, 0, 1),
    (1, 1, 1),
    (1, 2, 2),
    (2, 2, 2),
    (2, 3, 1),
  ];
  for (final (r, c, count) in taps) {
    final cellFinder = find.byKey(ValueKey('water_cell_${r}_$c'));
    await tester.ensureVisible(cellFinder);
    await tester.pump();
    for (var i = 0; i < count; i++) {
      await tester.tap(cellFinder);
      await tester.pump();
    }
  }
  await tester.pumpAndSettle();
}

Future<void> _solvePieceAssembly(
  WidgetTester tester,
  FamilyPuzzle puzzle,
) async {
  for (final piece in puzzle.pieceAssembly!.pieces) {
    final pieceFinder = find.byKey(ValueKey('assembly_piece_${piece.id}'));
    final slotFinder = find.byKey(ValueKey('assembly_slot_${piece.id}'));
    await tester.ensureVisible(pieceFinder);
    await tester.tap(pieceFinder);
    await tester.pump();
    await tester.ensureVisible(slotFinder);
    await tester.tap(slotFinder);
    await tester.pump();
  }
  await tester.pumpAndSettle();
}

Future<void> _pumpReady(WidgetTester tester) async {
  await tester.pump();
  await tester.runAsync(() async {
    await GoogleFonts.pendingFonts();
    await Future<void>.delayed(const Duration(milliseconds: 120));
  });
  await tester.pump();
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FamilyPuzzlePack arPack;
  late FamilyPuzzlePack enPack;

  setUpAll(() async {
    GoogleFonts.config.allowRuntimeFetching = false;
    arPack = await loadFamilyPuzzlePack('ar');
    enPack = await loadFamilyPuzzlePack('en');
  });

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('content packs & guardrails', () {
    test('ar and en packs have parity, valid SVGs, compressed hero, zero taboo copy',
        () async {
      final ar = await loadFamilyPuzzlePack('ar');
      final en = await loadFamilyPuzzlePack('en');

      expect(ar.puzzles.length, 16);
      expect(en.puzzles.length, 16);
      expect(ar.offscreenActivities.length, 7);
      expect(en.offscreenActivities.length, 7);

      expect(
        ar.puzzles.map((p) => (p.id, p.kind, p.skill)).toList(),
        en.puzzles.map((p) => (p.id, p.kind, p.skill)).toList(),
      );
      expect(
        ar.offscreenActivities.map((a) => a.id).toList(),
        en.offscreenActivities.map((a) => a.id).toList(),
      );

      final hero = File('assets/images/puzzles/family_puzzles_hero.png');
      expect(hero.existsSync(), isTrue);
      expect(hero.lengthSync(), lessThan(100 * 1024));

      final bySkill = <PuzzleSkill, int>{};
      for (final p in ar.puzzles) {
        bySkill[p.skill] = (bySkill[p.skill] ?? 0) + 1;
        if (p.spotDiff != null) {
          final sd = p.spotDiff!;
          _assertSvgExists(sd.backdrop, p.id);
          for (final item in sd.baseItems) {
            _assertSvgExists(item.prop, '${p.id}/${item.id}');
          }
          for (final d in sd.differences) {
            if (d.altProp != null) {
              _assertSvgExists(d.altProp!, '${p.id}/${d.id}');
            }
          }
        }
        if (p.trickReveal != null) {
          final tr = p.trickReveal!;
          _assertSvgExists(tr.backdrop, p.id);
          for (final u in tr.underItems) {
            _assertSvgExists(u.prop, '${p.id}/${u.id}');
          }
          for (final c in tr.covers) {
            _assertSvgExists(c.prop, '${p.id}/${c.id}');
            if (c.altProp != null) {
              _assertSvgExists(c.altProp!, '${p.id}/${c.id}_alt');
            }
          }
          if (tr.targetZone != null) {
            final tz = tr.targetZone!;
            _assertSvgExists(tz.beforeProp, '${p.id}/tz_before');
            _assertSvgExists(tz.afterProp, '${p.id}/tz_after');
            if (tz.afterBonusProp != null) {
              _assertSvgExists(tz.afterBonusProp!, '${p.id}/tz_bonus');
            }
          }
        }
        if (p.waterPath != null) {
          for (final t in p.waterPath!.targets) {
            _assertSvgExists(t.thirstyProp, '${p.id}/thirsty');
            _assertSvgExists(t.bloomedProp, '${p.id}/bloomed');
          }
        }
      }
      expect(bySkill.keys.toSet(), PuzzleSkill.values.toSet());
      for (final count in bySkill.values) {
        expect(count, greaterThanOrEqualTo(3));
      }

      for (final lang in ['ar', 'en']) {
        final raw = jsonDecode(
          File('assets/content/games/family_puzzles.$lang.json').readAsStringSync(),
        );
        for (final text in _collectTexts(raw)) {
          expect(_emojiRe.hasMatch(text), isFalse, reason: '$lang pack emoji: $text');
          expect(_forbiddenCopyRe.hasMatch(text), isFalse,
              reason: '$lang pack forbidden text: $text');
        }
      }

      for (final file in ['lib/l10n/app_ar.arb', 'lib/l10n/app_en.arb']) {
        final arb = jsonDecode(File(file).readAsStringSync()) as Map<String, dynamic>;
        for (final entry in arb.entries) {
          if (entry.key.startsWith('familyPuzzles') ||
              entry.key.startsWith('todayFamilyPuzzles')) {
            if (entry.value is String) {
              final s = entry.value as String;
              expect(_emojiRe.hasMatch(s), isFalse, reason: '$file ${entry.key}: $s');
              expect(_forbiddenCopyRe.hasMatch(s), isFalse,
                  reason: '$file ${entry.key}: $s');
            }
          }
        }
      }
    });
  });

  group('water solver & persistence', () {
    test('all 4 water puzzles start unsolved and solve cleanly via BFS',
        () async {
      final pack = await loadFamilyPuzzlePack('ar');
      const solutions = <String, List<List<int>>>{
        'log_single_sprout': [
          [2, 0, 0, 0],
          [0, 1, 2, 0],
          [0, 0, 0, 2],
          [0, 0, 0, 0],
        ],
        'log_twin_olives': [
          [0, 1, 1, 3],
          [1, 3, 0, 0],
          [0, 0, 0, 0],
          [0, 0, 1, 3],
        ],
        'log_stone_detour': [
          [1, 2, 0, 2],
          [0, 0, 0, 0],
          [0, 0, 1, 3],
          [0, 0, 0, 0],
        ],
        'log_garden_three': [
          [0, 2, 0, 0],
          [1, 0, 1, 3],
          [0, 0, 2, 0],
          [0, 0, 0, 0],
        ],
      };

      final waterPuzzles =
          pack.puzzles.where((p) => p.kind == PuzzleKind.waterPath).toList();
      expect(waterPuzzles.length, 4);

      for (final p in waterPuzzles) {
        final wp = p.waterPath!;
        final initial = [
          for (final row in wp.cells) [for (final c in row) c.initialRot],
        ];
        expect(WaterPathSolver.computeFlow(wp, initial).allSolved, isFalse,
            reason: '${p.id} should not start solved');
        expect(
          WaterPathSolver.computeFlow(wp, solutions[p.id]!).allSolved,
          isTrue,
          reason: '${p.id} failed to solve under expected rotations',
        );
      }
    });

    test('pickDailyRound covers 3 skills, persists per child, wipes on fresh start',
        () async {
      final pack = await loadFamilyPuzzlePack('ar');
      final day = DateTime(2026, 11, 15, 9, 30);

      final roundA = pickDailyRound(pack.puzzles, day, childId: 7);
      final roundB = pickDailyRound(pack.puzzles, day, childId: 7);
      expect(roundA.length, 3);
      expect(roundA.map((p) => p.skill).toSet().length, 3);
      expect(roundA.map((p) => p.id).toList(), roundB.map((p) => p.id).toList());

      await FamilyPuzzleStore.markSolved('obs_night_room', childId: 7);
      await FamilyPuzzleStore.markRoundCompleted(day, childId: 7);

      final child7 = await FamilyPuzzleStore.load(childId: 7);
      final child9 = await FamilyPuzzleStore.load(childId: 9);
      expect(child7.solvedIds, contains('obs_night_room'));
      expect(child7.isRoundDoneOn(day), isTrue);
      expect(child7.roundsCompleted, 1);
      expect(child9.solvedIds, isEmpty);

      final prefs = await SharedPreferences.getInstance();
      await clearPreferencesForFreshStart(prefs);
      final afterWipe = await FamilyPuzzleStore.load(childId: 7);
      expect(afterWipe.solvedIds, isEmpty);
      expect(afterWipe.roundsCompleted, 0);
    });
  });

  group('lobby & accessibility', () {
    testWidgets('renders in AR RTL, EN LTR, Dark Mode, and 360x800 at 2.0x scale',
        (tester) async {
      await tester.binding.setSurfaceSize(const Size(360, 800));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(_wrap(
        home: const FamilyPuzzlesScreen(source: GameSources.index),
        locale: const Locale('ar'),
        textScale: 2.0,
      ));
      await _pumpReady(tester);

      expect(tester.takeException(), isNull);
      expect(Directionality.of(tester.element(find.byType(FamilyPuzzlesScreen))),
          TextDirection.rtl);
      expect(find.byKey(const ValueKey('family_puzzles_start_round')),
          findsOneWidget);
      expect(find.byKey(const ValueKey('family_puzzle_card_obs_night_room')),
          findsOneWidget);

      await tester.pumpWidget(_wrap(
        home: const FamilyPuzzlesScreen(source: GameSources.hub),
        locale: const Locale('en'),
        themeMode: ThemeMode.dark,
        textScale: 1.5,
      ));
      await _pumpReady(tester);

      expect(tester.takeException(), isNull);
      expect(Directionality.of(tester.element(find.byType(FamilyPuzzlesScreen))),
          TextDirection.ltr);
      expect(find.text('Noor Family Brain Puzzles'), findsWidgets);
    });

    testWidgets('respects Child Mode spent budget lock', (tester) async {
      final enL10n = lookupAppLocalizations(const Locale('en'));
      await tester.pumpWidget(_wrap(
        home: const FamilyPuzzlesScreen(),
        locale: const Locale('en'),
        overrides: [
          childModeProvider.overrideWith(
            (_) => _StubChildMode(
              const ChildModeState(active: true, remainingSeconds: 0),
            ),
          ),
        ],
      ));
      await _pumpReady(tester);

      expect(find.text(enL10n.gamesBudgetSpent), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('family_puzzles_start_round')));
      await tester.pumpAndSettle();
      // Should stay on the lobby rather than opening runner.
      expect(find.byType(FamilyPuzzleRunnerScreen), findsNothing);
    });
  });

  group('interactive mechanics & round completion', () {
    testWidgets('SpotDiffStage supports whisper sheet, reset, and full solve',
        (tester) async {
      final puzzle =
          arPack.puzzles.firstWhere((p) => p.id == 'obs_night_room');
      final arL10n = lookupAppLocalizations(const Locale('ar'));

      await tester.pumpWidget(_wrap(
        home: FamilyPuzzleRunnerScreen(puzzles: [puzzle], childId: 3),
      ));
      await _pumpReady(tester);

      await tester.tap(find.byKey(const ValueKey('family_puzzle_whisper_btn')));
      await tester.pumpAndSettle();
      expect(find.text(puzzle.parentWhisper), findsOneWidget);
      await tester.tap(find.text(arL10n.familyPuzzlesWhisperGotIt));
      await tester.pumpAndSettle();

      // Tap difference #1, confirm progress 1/total, then tap Reset -> back to 0/total.
      final totalDiffs = puzzle.spotDiff!.differences.length;
      final sceneFinder = find.byKey(const ValueKey('spot_diff_top_scene'));
      final box = tester.renderObject<RenderBox>(sceneFinder);
      final topLeft = box.localToGlobal(Offset.zero);
      final first = puzzle.spotDiff!.differences.first;
      await tester.tapAt(
        topLeft + Offset(box.size.width * first.hitX, box.size.height * first.hitY),
      );
      await tester.pump();
      expect(
        find.text(arL10n.familyPuzzlesDiffProgress(1, totalDiffs)),
        findsOneWidget,
      );

      await tester.tap(find.byKey(const ValueKey('family_puzzle_reset')));
      await _pumpReady(tester);
      expect(
        find.text(arL10n.familyPuzzlesDiffProgress(0, totalDiffs)),
        findsOneWidget,
      );

      await _solveSpotDiff(tester, puzzle);
      expect(find.byKey(const ValueKey('family_puzzle_praise_banner')),
          findsOneWidget);
      final saved =
          (await tester.runAsync(() => FamilyPuzzleStore.load(childId: 3)))!;
      expect(saved.solvedIds, contains('obs_night_room'));
    });

    testWidgets('TrickRevealStage solves both count_hidden and drag_solve',
        (tester) async {
      final countPuzzle =
          arPack.puzzles.firstWhere((p) => p.id == 'lat_hidden_lanterns');
      final dragPuzzle =
          arPack.puzzles.firstWhere((p) => p.id == 'lat_water_basil');
      final arL10n = lookupAppLocalizations(const Locale('ar'));

      await tester.pumpWidget(_wrap(
        home: FamilyPuzzleRunnerScreen(puzzles: [countPuzzle]),
      ));
      await _pumpReady(tester);

      await tester.ensureVisible(find.byKey(const ValueKey('trick_cover_c_sofa')));
      await tester.tap(find.byKey(const ValueKey('trick_cover_c_sofa')));
      await tester.pump();

      final plus = find.byKey(const ValueKey('trick_count_plus'));
      final minus = find.byKey(const ValueKey('trick_count_minus'));
      final check = find.byKey(const ValueKey('trick_count_check'));
      await tester.ensureVisible(plus);
      await tester.tap(plus);
      await tester.pump();
      await tester.tap(plus);
      await tester.pump();
      await tester.tap(minus);
      await tester.pump();
      await tester.ensureVisible(check);
      await tester.tap(check);
      await tester.pumpAndSettle();
      expect(find.text(arL10n.familyPuzzlesTryAgain), findsOneWidget);

      for (var i = 0; i < 6; i++) {
        await tester.ensureVisible(plus);
        await tester.tap(plus);
        await tester.pump();
      }
      await tester.ensureVisible(check);
      await tester.tap(check);
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('family_puzzle_praise_banner')),
          findsOneWidget);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      await tester.pumpWidget(_wrap(
        home: FamilyPuzzleRunnerScreen(puzzles: [dragPuzzle]),
      ));
      await _pumpReady(tester);
      await tester
          .ensureVisible(find.byKey(const ValueKey('trick_cover_cloud_rain')));
      await tester.tap(find.byKey(const ValueKey('trick_cover_cloud_rain')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('family_puzzle_praise_banner')),
          findsOneWidget);
    });

    testWidgets('PieceAssemblyStage and WaterPathStage finish daily round with offscreen card',
        (tester) async {
      final piecePuzzle =
          arPack.puzzles.firstWhere((p) => p.id == 'spa_warm_house');
      final waterPuzzle =
          arPack.puzzles.firstWhere((p) => p.id == 'log_single_sprout');
      final offscreen = arPack.offscreenActivities.first;

      await tester.pumpWidget(_wrap(
        home: FamilyPuzzleRunnerScreen(
          puzzles: [piecePuzzle, waterPuzzle],
          offscreenActivity: offscreen,
          childId: 5,
          isDailyRound: true,
          source: GameSources.home,
        ),
      ));
      await _pumpReady(tester);

      await _solvePieceAssembly(tester, piecePuzzle);
      expect(find.byKey(const ValueKey('family_puzzle_praise_banner')),
          findsOneWidget);

      final nextBtn = find.byKey(const ValueKey('family_puzzle_next_btn'));
      await tester.ensureVisible(nextBtn);
      await tester.tap(nextBtn);
      await _pumpReady(tester);

      await _solveWaterSingleSprout(tester);
      expect(find.byKey(const ValueKey('family_puzzle_praise_banner')),
          findsOneWidget);

      final finishBtn = find.byKey(const ValueKey('family_puzzle_next_btn'));
      await tester.ensureVisible(finishBtn);
      await tester.tap(finishBtn);
      await _pumpReady(tester);

      expect(find.byKey(const ValueKey('family_round_complete_view')),
          findsOneWidget);
      expect(find.byKey(const ValueKey('family_round_offscreen_card')),
          findsOneWidget);
      expect(find.text(offscreen.title), findsOneWidget);

      final saved =
          (await tester.runAsync(() => FamilyPuzzleStore.load(childId: 5)))!;
      expect(saved.roundsCompleted, 1);
      expect(saved.solvedIds, containsAll(['spa_warm_house', 'log_single_sprout']));
    });

    testWidgets('GamesScreen hero and TodayFamilyPuzzlesCard expose entry points',
        (tester) async {
      expect(enPack.puzzles.length, 16);
      await tester.pumpWidget(_wrap(home: const GamesScreen()));
      await _pumpReady(tester);

      final hero = find.byKey(const ValueKey('games_family_puzzles_hero'));
      expect(hero, findsOneWidget);
      await tester.tap(hero);
      await _pumpReady(tester);
      expect(find.byType(FamilyPuzzlesScreen), findsOneWidget);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      await tester.pumpWidget(_wrap(
        home: const Scaffold(
          body: TodayFamilyPuzzlesCard(key: ValueKey('today_family_puzzles_card')),
        ),
      ));
      await _pumpReady(tester);
      expect(find.byKey(const ValueKey('today_family_puzzles_card_btn')),
          findsOneWidget);
    });
  });
}
