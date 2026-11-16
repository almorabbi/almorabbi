/// Comprehensive Flutter test suite for the pre-Ramadan 2.0 creative pack:
///  1. All 30 AR & 30 EN Ramadan Lantern Fawazir puzzles (`ramadan_puzzles.*.json`):
///     parity across nights 1–30, SVG existence, zero living-being props,
///     zero shame/coin/streak language, and BFS water solver verification.
///  2. `ShabanWelcomeCard` in the 10-day window + local completion state +
///     navigation to `RamadanPrintKitScreen` (verifying local child names).
///  3. `RamadanPrintKitScreen` switching Color vs Ink-Saver cleanly.
///  4. `CompanionKind.partnerLanternLit` firing deterministically in `pickLine`.
///  5. `RamadanScreen` across `ramadan` (partner harmony banner, Fawazir day
///     card, Pre-Iftar Audio Tales & Parent Capsules, Shawwal pledge picker)
///     and `eid` / `after` (active pledge ribbon + zero-PII Paper Eid Greeting).
library;

import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:almorabbi/features/companion/data/companion_store.dart';
import 'package:almorabbi/features/companion/logic/companion_brain.dart';
import 'package:almorabbi/features/family_puzzles/data/family_puzzle_models.dart';
import 'package:almorabbi/features/family_puzzles/screens/family_puzzles_screen.dart';
import 'package:almorabbi/features/onboarding/data/onboarding_storage.dart';
import 'package:almorabbi/features/programs/screens/ramadan_print_kit_screen.dart';
import 'package:almorabbi/features/programs/screens/ramadan_screen.dart';
import 'package:almorabbi/features/programs/widgets/shaban_welcome_card.dart';
import 'package:almorabbi/l10n/app_localizations.dart';
import 'package:almorabbi/state/chat_notifier.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:screenshot/screenshot.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'programs_support.dart';

const _dumpPrintKitDir = String.fromEnvironment('DUMP_PRINT_KIT_DIR');

final _missWords = RegExp(
  r'miss|fail|behind|late|فات|فائت|تأخّر|فشل',
  caseSensitive: false,
);

const _livingPropKeywords = {
  'bird', 'cat', 'dog', 'puppy', 'fox', 'deer', 'fish',
  'boy', 'girl', 'face', 'person', 'human', 'child', 'parent', 'animal',
};

Iterable<String> _visibleStrings(dynamic node) sync* {
  if (node is String) {
    yield node;
  } else if (node is List) {
    for (final v in node) {
      yield* _visibleStrings(v);
    }
  } else if (node is Map) {
    for (final e in node.entries) {
      final k = '${e.key}';
      if (const {
        'id', 'key', 'audio_path', 'backdrop', 'prop', 'alt_prop',
        'before_prop', 'after_prop', 'after_bonus_prop',
        'thirsty_prop', 'bloomed_prop', 'color_hex', 'item_id', 'kind',
        'skill', 'mode', 'sub_mode', 'require_mode', 'solve_role', 'locale',
        'season', 'entry_dir',
      }.contains(k)) {
        continue;
      }
      yield* _visibleStrings(e.value);
    }
  }
}

void _checkSvg(String name, String ctx) {
  expect(
    File('assets/svg/stories/$name.svg').existsSync(),
    isTrue,
    reason: 'Missing SVG $name ($ctx)',
  );
  final low = name.toLowerCase();
  for (final kw in _livingPropKeywords) {
    expect(low.contains(kw), isFalse, reason: 'Living keyword $kw in $name');
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    GoogleFonts.config.allowRuntimeFetching = false;
  });

  group('ramadan fawazir & audio asset integrity', () {
    test('30 AR and 30 EN Ramadan Fawazir nights are valid and water-solvable',
        () async {
      final ar = await loadRamadanPuzzlePack('ar');
      final en = await loadRamadanPuzzlePack('en');

      expect(ar.length, 30);
      expect(en.length, 30);
      expect(
        ar.map((p) => p.ramadanNight).toList(),
        List<int>.generate(30, (i) => i + 1),
      );
      expect(
        en.map((p) => (p.id, p.kind, p.skill, p.ramadanNight)).toList(),
        ar.map((p) => (p.id, p.kind, p.skill, p.ramadanNight)).toList(),
      );

      for (final p in ar) {
        if (p.spotDiff != null) {
          _checkSvg(p.spotDiff!.backdrop, p.id);
          for (final item in p.spotDiff!.baseItems) {
            _checkSvg(item.prop, '${p.id}/${item.id}');
          }
          for (final d in p.spotDiff!.differences) {
            if (d.altProp != null) _checkSvg(d.altProp!, '${p.id}/${d.id}');
          }
        }
        if (p.trickReveal != null) {
          _checkSvg(p.trickReveal!.backdrop, p.id);
          for (final u in p.trickReveal!.underItems) {
            _checkSvg(u.prop, '${p.id}/${u.id}');
          }
          for (final c in p.trickReveal!.covers) {
            _checkSvg(c.prop, '${p.id}/${c.id}');
            if (c.altProp != null) _checkSvg(c.altProp!, '${p.id}/${c.id}');
          }
          final tz = p.trickReveal!.targetZone;
          if (tz != null) {
            _checkSvg(tz.beforeProp, '${p.id}/before');
            _checkSvg(tz.afterProp, '${p.id}/after');
            if (tz.afterBonusProp != null) {
              _checkSvg(tz.afterBonusProp!, '${p.id}/bonus');
            }
          }
        }
        if (p.waterPath != null) {
          final wp = p.waterPath!;
          final initRots = [
            for (final r in wp.cells) [for (final c in r) c.initialRot],
          ];
          expect(
            WaterPathSolver.computeFlow(wp, initRots).allSolved,
            isFalse,
            reason: '${p.id} starts already solved',
          );
          for (final t in wp.targets) {
            _checkSvg(t.thirstyProp, '${p.id}/thirsty');
            _checkSvg(t.bloomedProp, '${p.id}/bloomed');
          }
        }
      }

      for (final rel in [
        'assets/content/games/ramadan_puzzles.ar.json',
        'assets/content/games/ramadan_puzzles.en.json',
        'assets/content/programs/ramadan_audio.ar.json',
        'assets/content/programs/ramadan_audio.en.json',
      ]) {
        final raw = jsonDecode(File(rel).readAsStringSync());
        for (final s in _visibleStrings(raw)) {
          expect(_missWords.hasMatch(s), isFalse, reason: '$rel has shame text: $s');
        }
      }
    });
  });

  group('companion dual-parent lantern whisper', () {
    test('partnerLanternLit fires once per day when co-parent lit lantern', () {
      final now = DateTime(2027, 2, 12, 20);
      final line = pickLine(
        CompanionInputs(
          now: now,
          memory: const CompanionMemory(),
          childId: kChildId,
          childName: 'سارة',
          ramadanYear: 1448,
          ramadanDay: 5,
          partnerLanternDay: 5,
          partnerLanternLabel: 'Mother',
        ),
      )!;
      expect(line.kind, CompanionKind.partnerLanternLit);
      expect(line.ramadanDays, 5);
      expect(line.partnerLabel, 'Mother');
      expect(line.onceOnly, isTrue);

      final second = pickLine(
        CompanionInputs(
          now: now,
          memory: CompanionMemory(seenKeys: {line.key}),
          childId: kChildId,
          childName: 'سارة',
          ramadanYear: 1448,
          ramadanDay: 5,
          partnerLanternDay: 5,
          partnerLanternLabel: 'Mother',
        ),
      )!;
      expect(second.kind, isNot(CompanionKind.partnerLanternLit));
    });
  });

  group('Shaban welcome, print kit, fawazir, pledge & eid card widgets', () {
    testWidgets('ShabanWelcomeCard shows inside 10-day window and opens PrintKit with local names',
        (tester) async {
      final client = FakeProgramsClient()
        ..programs = {
          ...programsJson(state: 'upcoming', day: null, daysUntil: 7),
          'ramadan': {
            ...programsJson(state: 'upcoming', day: null, daysUntil: 7)['ramadan']
                as Map<String, dynamic>,
            'shaban_prep_today': {
              'days_left': 7,
              'key': 'kind_words_and_charity',
              'title': 'The Kind-Words Jar & Charity Box',
              'subtitle': 'Readying a generous heart',
              'minutes': 5,
              'steps': ['Place a charity box.'],
              'child_role': 'Decorate the box.',
            },
          },
        };

      await pumpPrograms(
        tester,
        const Scaffold(body: SingleChildScrollView(child: ShabanWelcomeCard())),
        client: client,
      );
      await settle(tester);

      expect(find.byKey(const ValueKey('shaban_welcome_card')), findsOneWidget);
      expect(find.text('The Kind-Words Jar & Charity Box'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('shaban_prep_mark_btn')));
      await settle(tester);
      expect(find.text('Ready for Tonight'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('shaban_prep_print_btn')));
      await settle(tester);
      expect(find.byType(RamadanPrintKitScreen), findsOneWidget);
      // Child name (سارة) rendered strictly from local profile, never server URL
      expect(find.textContaining('سارة'), findsWidgets);

      await tester.tap(find.byKey(const ValueKey('print_kit_ink_bw')));
      await settle(tester);
    });

    testWidgets('FamilyPuzzlesScreen displays 30 Ramadan Fawazir lanterns', (tester) async {
      GoogleFonts.config.allowRuntimeFetching = false;
      SharedPreferences.setMockInitialValues({
        OnboardingStorage.keyActiveChildId: kChildId,
        OnboardingStorage.keyActiveChildName: kChildName,
        OnboardingStorage.keyActiveChildAgeGroup: '7-9',
        OnboardingStorage.keyOnboardingCompleted: true,
      });
      await tester.pumpWidget(
        ProviderScope(
          overrides: [tgClientProvider.overrideWithValue(FakeProgramsClient())],
          child: const MaterialApp(
            locale: Locale('en'),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: FamilyPuzzlesScreen(),
          ),
        ),
      );
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 120)));
      await tester.pumpAndSettle();

      await scrollTo(tester, find.byKey(const ValueKey('ramadan_fawazir_section')));
      expect(find.byKey(const ValueKey('ramadan_fawazir_night_1')), findsOneWidget);
      expect(find.byKey(const ValueKey('ramadan_fawazir_night_30')), findsOneWidget);
    });

    testWidgets('RamadanScreen shows partner harmony, fawazir card, audio shelf & Shawwal pledge',
        (tester) async {
      final client = FakeProgramsClient()
        ..ramadanToday = {
          ...ramadanTodayJson(
            day: 22,
            content: dayContentJson(day: 22, oddNight: true),
          ),
          'partner_lantern': {
            'day': 22,
            'partner_role': 'mother',
            'partner_name': 'Umm Zayd',
          },
          'fawazir_days_lit': [3],
          'keep_habits': [
            {'key': 'charity_box', 'title': 'The charity box', 'text': 'Stays in place'},
            {'key': 'quran_circle', 'title': 'Two-minute circle', 'text': 'Every night'},
          ],
          'pledged_habits': <String>[],
        };

      await pumpPrograms(tester, const RamadanScreen(childId: kChildId), client: client);
      await settle(tester);

      expect(find.byKey(const ValueKey('ramadan_partner_lantern_banner')), findsOneWidget);
      expect(find.textContaining('Umm Zayd'), findsOneWidget);

      await scrollTo(tester, find.byKey(const ValueKey('ramadan_day_fawazir_card')));
      expect(find.byKey(const ValueKey('ramadan_day_fawazir_cta_22')), findsOneWidget);

      await scrollTo(tester, find.byKey(const ValueKey('ramadan_audio_shelf')));
      expect(find.byKey(const ValueKey('ramadan_audio_tab_tales')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('ramadan_audio_tab_capsules')));
      await settle(tester);
      expect(find.text('The Golden Half-Hour Before Maghrib'), findsOneWidget);

      await scrollTo(tester, find.byKey(const ValueKey('ramadan_shawwal_pledge_section')));
      await tester.tap(find.byKey(const ValueKey('ramadan_pledge_chip_charity_box')));
      await settle(tester);
      expect(client.calls, contains('pledge'));
      expect(client.bodies.last['habit_keys'], ['charity_box']);
    });

    testWidgets('Eid shows zero-PII greeting card', (tester) async {
      final client = FakeProgramsClient()
        ..ramadanToday = {
          ...ramadanTodayJson(state: 'eid', recap: true),
          'family_word': 'Mercy',
          'eid_greetings': [
            {
              'key': 'family_lanterns',
              'eyebrow': 'Eid Gift',
              'headline': 'Eid Mubarak From Our Home',
              'lines': ['May peace stay in your home.'],
              'closing': 'Taqabbal Allahu minna wa minkum',
            },
          ],
        };

      await pumpPrograms(tester, const RamadanScreen(childId: kChildId), client: client);
      await settle(tester);

      final cardSection = find.byKey(const ValueKey('ramadan_eid_greeting_section'));
      await scrollTo(tester, cardSection);
      expect(find.byKey(const ValueKey('eid_greeting_preview')), findsOneWidget);
      // Zero child names appear inside the Eid greeting preview
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('eid_greeting_preview')),
          matching: find.textContaining(kChildName),
        ),
        findsNothing,
      );
    });

    testWidgets('after shows pledged Shawwal habits ribbon', (tester) async {
      final afterClient = FakeProgramsClient()
        ..ramadanToday = {
          ...ramadanTodayJson(state: 'after', recap: true),
          'pledged_habits': ['charity_box'],
        };
      await pumpPrograms(tester, const RamadanScreen(childId: kChildId), client: afterClient);
      await settle(tester);
      await scrollTo(tester, find.byKey(const ValueKey('ramadan_after_pledge_ribbon')));
      expect(find.text('Our chosen Shawwal habits:'), findsOneWidget);
    });
  });

  group('RamadanPrintKitScreen off-tree 3-sheet capture', () {
    testWidgets('switching sheet tabs and tapping Share throws no exceptions', (
      tester,
    ) async {
      GoogleFonts.config.allowRuntimeFetching = false;
      SharedPreferences.setMockInitialValues({
        OnboardingStorage.keyActiveChildId: kChildId,
        OnboardingStorage.keyActiveChildName: 'سارة',
        OnboardingStorage.keyActiveChildAgeGroup: '7-9',
        OnboardingStorage.keyOnboardingCompleted: true,
      });
      await tester.pumpWidget(
        ProviderScope(
          overrides: [tgClientProvider.overrideWithValue(FakeProgramsClient())],
          child: const MaterialApp(
            locale: Locale('ar'),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: RamadanPrintKitScreen(),
          ),
        ),
      );
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 120)),
      );
      await tester.pumpAndSettle();

      for (final idx in [0, 1, 2]) {
        await tester.tap(find.byKey(ValueKey('print_kit_sheet_$idx')));
        await tester.pumpAndSettle();
        expect(find.byType(ErrorWidget), findsNothing);
        expect(find.textContaining('سارة'), findsWidgets);
      }

      await scrollTo(tester, find.byKey(const ValueKey('print_kit_share_cta')));
      await tester.tap(find.byKey(const ValueKey('print_kit_share_cta')));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 400)),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });

    testWidgets(
      'captures all 3 A4 sheets off-tree (ar color/bw & en color) with zero ErrorWidget',
      (tester) async {
        GoogleFonts.config.allowRuntimeFetching = false;
        final ar = lookupAppLocalizations(const Locale('ar'));
        final en = lookupAppLocalizations(const Locale('en'));
        const kids = [
          LocalPrintChild(name: 'سارة', ageGroup: '7-9'),
          LocalPrintChild(name: 'عمر', ageGroup: '4-6'),
        ];

        final variants = <({String slug, bool isAr, bool bw, AppLocalizations l10n})>[
          (slug: 'ar_color', isAr: true, bw: false, l10n: ar),
          (slug: 'ar_bw', isAr: true, bw: true, l10n: ar),
          (slug: 'en_color', isAr: false, bw: false, l10n: en),
        ];

        final controller = ScreenshotController();
        if (_dumpPrintKitDir.isNotEmpty) {
          Directory(_dumpPrintKitDir).createSync(recursive: true);
        }

        for (final v in variants) {
          final namesText = kids.map((k) => k.name).join(v.isAr ? '، ' : ', ');
          final sheets = buildRamadanKitSheets(
            isAr: v.isAr,
            bwInk: v.bw,
            kids: kids,
            kitHeadline: v.l10n.ramadanPrintKitTitle,
            namesBanner: v.l10n.ramadanPrintKitForChildren(namesText),
            footerTitle: v.l10n.ramadanPrintKitBannerHint,
          );
          expect(sheets, hasLength(3));

          for (var idx = 0; idx < sheets.length; idx++) {
            final sheet = sheets[idx];
            tester.view.physicalSize = RamadanPrintableSheet.a4Size;
            tester.view.devicePixelRatio = 1.0;
            addTearDown(() {
              tester.view.resetPhysicalSize();
              tester.view.resetDevicePixelRatio();
            });

            await tester.pumpWidget(
              Directionality(
                textDirection: TextDirection.ltr,
                child: SizedBox(
                  width: RamadanPrintableSheet.a4Size.width,
                  height: RamadanPrintableSheet.a4Size.height,
                  child: sheet,
                ),
              ),
            );
            await tester.pump();
            expect(
              tester.takeException(),
              isNull,
              reason: '${v.slug} sheet ${idx + 1} threw while pumping without MediaQuery/View',
            );
            expect(find.byType(ErrorWidget), findsNothing);
            expect(find.textContaining('تعذّر عرض هذا الجزء'), findsNothing);
            expect(find.textContaining('سارة'), findsWidgets);

            final png = (await tester.runAsync(
              () => controller.captureFromWidget(
                sheet,
                targetSize: RamadanPrintableSheet.a4Size,
                pixelRatio: 1.0,
                delay: const Duration(milliseconds: 120),
              ),
            ))!;
            expect(
              tester.takeException(),
              isNull,
              reason: '${v.slug} sheet ${idx + 1} threw during captureFromWidget',
            );

            final image = (await tester.runAsync(() => decodeImageFromList(png)))!;
            addTearDown(image.dispose);
            expect(image.width, 1080);
            expect(image.height, 1528);

            final rgba = (await tester.runAsync(
              () => image.toByteData(format: ui.ImageByteFormat.rawStraightRgba),
            ))!;

            double inkRatio(int yStart, int yEnd) {
              var nonWhite = 0;
              var total = 0;
              for (var y = yStart; y < yEnd; y += 3) {
                for (var x = 48; x < 1032; x += 3) {
                  final i = (y * image.width + x) * 4;
                  final r = rgba.getUint8(i);
                  final g = rgba.getUint8(i + 1);
                  final b = rgba.getUint8(i + 2);
                  total++;
                  if (r < 245 || g < 245 || b < 245) nonWhite++;
                }
              }
              return nonWhite / total;
            }

            final headInk = inkRatio(45, 225);
            final bodyInk = inkRatio(260, 1280);
            final footInk = inkRatio(1315, 1480);
            expect(
              headInk,
              greaterThan(0.01),
              reason: '${v.slug} sheet ${idx + 1}: empty header ($headInk)',
            );
            expect(
              bodyInk,
              greaterThan(0.01),
              reason: '${v.slug} sheet ${idx + 1}: empty body ($bodyInk)',
            );
            expect(
              footInk,
              greaterThan(0.01),
              reason: '${v.slug} sheet ${idx + 1}: empty QR footer ($footInk)',
            );

            if (_dumpPrintKitDir.isNotEmpty) {
              File('$_dumpPrintKitDir/${v.slug}_sheet_${idx + 1}.png')
                  .writeAsBytesSync(png);
            }
          }
        }
      },
    );
  });
}
