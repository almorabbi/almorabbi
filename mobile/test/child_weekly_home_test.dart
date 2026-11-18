import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:almorabbi/api/tg_client.dart';
import 'package:almorabbi/core/clock.dart';
import 'package:almorabbi/features/child_memory/data/memory_models.dart';
import 'package:almorabbi/features/child_memory/providers/memory_providers.dart';
import 'package:almorabbi/features/child_memory/widgets/today_followup_card.dart';
import 'package:almorabbi/features/child_memory/widgets/today_weekly_plan_card.dart';
import 'package:almorabbi/features/home/experiment/child_home_experiment.dart';
import 'package:almorabbi/features/home/widgets/child_weekly_home.dart';
import 'package:almorabbi/features/home/widgets/daily_gift_moment.dart';
import 'package:almorabbi/features/home/widgets/home_shortcuts_grid.dart';
import 'package:almorabbi/features/home/widgets/home_stats_row.dart';
import 'package:almorabbi/features/home/widgets/sky_band.dart';
import 'package:almorabbi/features/home/widgets/today_focus_card.dart';
import 'package:almorabbi/features/home/widgets/today_section.dart';
import 'package:almorabbi/features/mawaqif/widgets/today_mawqif_card.dart';
import 'package:almorabbi/features/onboarding/data/onboarding_storage.dart';
import 'package:almorabbi/features/onboarding/providers/onboarding_providers.dart';
import 'package:almorabbi/features/program/providers/progress_providers.dart';
import 'package:almorabbi/l10n/app_localizations.dart';
import 'package:almorabbi/main.dart' show appConfigProvider;
import 'package:almorabbi/screens/home_screen.dart';
import 'package:almorabbi/state/chat_notifier.dart' show tgClientProvider;
import 'package:almorabbi/theme/app_palette.dart';
import 'package:almorabbi/theme/app_theme.dart';
import 'package:almorabbi/widgets/ui/bouncy_button.dart';

import 'lantern_fakes.dart' show act, familyWeekJson;

const _dumpTodayDir = String.fromEnvironment('DUMP_TODAY_PREVIEW');

class _FakeWeeklyClient extends TgClient {
  _FakeWeeklyClient()
      : super.forTesting(
          baseUrl: 'http://fake.invalid',
          httpClient: MockClient((_) async => http.Response('{}', 404)),
        );

  Map<String, dynamic>? progress;
  Map<String, dynamic>? familyWeek;
  List<Map<String, dynamic>>? mawaqif;
  int mawaqifCalls = 0;
  bool includePlan = true;

  @override
  Future<List<Map<String, dynamic>>> getMawaqif(String ageGroup) async {
    mawaqifCalls++;
    return mawaqif ?? const <Map<String, dynamic>>[];
  }

  @override
  Future<Map<String, dynamic>> getChildProgress(
    int childId, {
    String? pathId,
  }) async =>
      progress ?? {'child_id': childId, 'lessons': []};

  @override
  Future<Map<String, dynamic>> getWeeklyPlan(
    int childId, {
    String? lang,
    int? tzOffsetMinutes,
  }) async {
    if (!includePlan) throw const TgApiError(404, 'Not Found');
    final isEn = lang == 'en';
    return {
      'child_id': childId,
      'week': '2026-W46',
      'week_start': '2026-11-09',
      'lang': lang ?? 'ar',
      'focus': {'title': isEn ? 'Calm listening' : 'الاستماع الهادئ'},
      'actions': [
        {
          'key': 'a1',
          'text': isEn ? 'Two quiet minutes' : 'دقيقتان من الإنصات',
        },
      ],
      'worship': {
        'key': 'w1',
        'text': isEn ? 'Evening dua together' : 'دعاء المساء معاً',
      },
      'marks': <String>[],
    };
  }

  @override
  Future<Map<String, dynamic>> fetchFamilyWeek(
    int tzOffsetMinutes, {
    String? lang,
  }) async =>
      familyWeek ?? (throw const TgApiError(404, 'Not Found'));

  @override
  Future<Map<String, dynamic>> fetchPrograms() async =>
      throw const TgApiError(404, 'Not Found');

  @override
  Future<Map<String, dynamic>> getPathsList({
    String? ageGroup,
    String? domain,
  }) async =>
      throw const TgApiError(503, 'offline');

  @override
  Future<Map<String, dynamic>> getNextLesson(
    String ageGroup, {
    int? childId,
  }) async =>
      throw const TgApiError(503, 'offline');

  @override
  Future<Map<String, dynamic>> getCoachTip(int childId) async =>
      throw const TgApiError(503, 'offline');

  @override
  Future<Map<String, dynamic>> getCommunityStats() async =>
      throw const TgApiError(503, 'offline');

  @override
  Future<Map<String, dynamic>> fetchChildDay(int childId) async =>
      throw const TgApiError(503, 'offline');
}

Map<String, dynamic> _sampleMawqifJson({String ageGroup = '7-9'}) => {
      'id': 'm1',
      'age_group': ageGroup,
      'topic': 'calm',
      'title': 'موقف للنقاش العائلي',
      'situation': 'موقف يومي مع الطفل',
      'choices': const [
        {'key': 'a', 'text': 'خيار ١', 'now': 'الآن ١', 'later': 'لاحقًا ١'},
        {'key': 'b', 'text': 'خيار ٢', 'now': 'الآن ٢', 'later': 'لاحقًا ٢'},
        {'key': 'c', 'text': 'خيار ٣', 'now': 'الآن ٣', 'later': 'لاحقًا ٣'},
      ],
      'evidence': const {
        'id': 'ev1',
        'kind': 'hadith',
        'text_ar': 'حديث تجريبي صحيح',
        'source': 'رواه البخاري',
      },
      'idea': 'فكرة هادئة',
      'step': 'خطوة عملية',
    };

void main() {
  tearDown(() => AppPalette.current = AppPalette.light);

  Future<ProviderContainer> pumpWeeklyHome(
    WidgetTester tester, {
    String ageGroup = '7-9',
    String childName = 'سارة',
    String? birthMonth,
    Locale locale = const Locale('ar'),
    bool dark = false,
    double textScale = 1.0,
    Size phone = const Size(360, 800),
    DateTime? now,
    Map<String, dynamic>? familyWeek,
    List<Map<String, dynamic>>? mawaqif,
    Override? dueFollowupsOverride,
    bool justOnboarded = false,
    String? firstWeekRecordedIso,
    Map<String, dynamic>? appConfig,
    _FakeWeeklyClient? client,
  }) async {
    tester.view.physicalSize = phone * 3.0;
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    final fake = (client ?? _FakeWeeklyClient())
      ..familyWeek = familyWeek
      ..mawaqif = mawaqif;
    SharedPreferences.setMockInitialValues({
      OnboardingStorage.keyActiveChildId: 1,
      OnboardingStorage.keyActiveChildName: childName,
      OnboardingStorage.keyActiveChildAgeGroup: ageGroup,
      OnboardingStorage.keyActiveChildBirthMonth: ?birthMonth,
      firstWeekOnboardedKey(1): ?firstWeekRecordedIso,
      OnboardingStorage.keyOnboardingCompleted: true,
    });
    final prefs = await SharedPreferences.getInstance();
    final container = ProviderContainer(
      overrides: [
        tgClientProvider.overrideWithValue(fake),
        sharedPreferencesProvider.overrideWith((_) async => prefs),
        appConfigProvider.overrideWith(
          (_) async => appConfig ?? const {'child_home_v2': 'v2'},
        ),
        ?dueFollowupsOverride,
        if (now != null) clockProvider.overrideWithValue(() => now),
      ],
    );
    addTearDown(container.dispose);
    await container.read(sharedPreferencesProvider.future);
    await container.read(childHomeArmProvider.future);
    container.read(activeChildIdProvider.notifier).state = 1;
    if (justOnboarded) {
      container.read(justOnboardedPlanChildProvider.notifier).state = 1;
    }

    if (dark) AppPalette.current = AppPalette.dark;
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          locale: locale,
          theme: dark ? AppTheme.dark() : AppTheme.light(),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(
              textScaler: TextScaler.linear(textScale),
            ),
            child: child!,
          ),
          home: HomeScreen(onGoToTab: (_) {}),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    return container;
  }

  testWidgets(
    '200% text on 360x800: weekly header and TodayFocusCard primary CTA stay above the fold',
    (tester) async {
      await pumpWeeklyHome(
        tester,
        phone: const Size(360, 800),
        textScale: 2.0,
      );
      expect(tester.takeException(), isNull);
      expect(find.byType(ChildWeeklyHome), findsOneWidget);
      expect(find.byType(SkyBand), findsNothing);

      final header = find.byKey(const ValueKey('child_weekly_home_header'));
      final cta = find.descendant(
        of: find.byType(TodayFocusCard),
        matching: find.byType(BouncyButton),
      );
      expect(header, findsOneWidget);
      expect(cta, findsOneWidget);
      expect(tester.getRect(header).bottom, lessThanOrEqualTo(800));
      expect(tester.getRect(cta).bottom, lessThanOrEqualTo(800));
    },
  );

  testWidgets(
    'Week 1 after onboarding shows badge and keeps TodayWeeklyPlanCard collapsed as sleek summary until tapped',
    (tester) async {
      await pumpWeeklyHome(
        tester,
        justOnboarded: true,
        now: DateTime(2026, 11, 14, 10),
      );
      expect(find.text('أسبوع البداية'), findsOneWidget);
      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('weekly_plan_summary_bar')),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pump(const Duration(milliseconds: 250));
      expect(find.text('الاستماع الهادئ'), findsOneWidget);
      expect(find.text('دعاء المساء معاً'), findsNothing);

      // Tapping the sleek summary bar expands the full weekly plan on demand.
      await tester.tap(find.byKey(const ValueKey('weekly_plan_summary_bar')));
      await tester.pump(const Duration(milliseconds: 300));
      await tester.scrollUntilVisible(
        find.text('دعاء المساء معاً'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('دعاء المساء معاً'), findsOneWidget);

      await tester.pumpWidget(const SizedBox());
      await pumpWeeklyHome(
        tester,
        justOnboarded: false,
        now: DateTime(2026, 11, 14, 10),
      );
      expect(find.text('أسبوع البداية'), findsNothing);
      await tester.scrollUntilVisible(
        find.byType(TodayWeeklyPlanCard),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('الاستماع الهادئ'), findsOneWidget);
      expect(find.text('دعاء المساء معاً'), findsNothing);
    },
  );

  test('child_home_v2 ab splits roughly 50/50, sticks in prefs, and v2 overrides',
      () async {
    var weeklyCount = 0;
    var classicCount = 0;
    for (var i = 0; i < 200; i++) {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final arm = await resolveChildHomeArm(
        prefs: prefs,
        serverMode: 'ab',
        getDeviceId: () async => 'dev-$i',
      );
      expect(prefs.getString(kChildHomeArmKey), arm.name);
      if (arm == ChildHomeArm.weekly) {
        weeklyCount++;
      } else {
        classicCount++;
      }
    }
    expect(weeklyCount, inInclusiveRange(70, 130));
    expect(classicCount, inInclusiveRange(70, 130));

    SharedPreferences.setMockInitialValues({});
    final stickyPrefs = await SharedPreferences.getInstance();
    final first = await resolveChildHomeArm(
      prefs: stickyPrefs,
      serverMode: 'ab',
      getDeviceId: () async => 'sticky-device-1',
    );
    final repeated = await resolveChildHomeArm(
      prefs: stickyPrefs,
      serverMode: 'ab',
      getDeviceId: () async => 'different-device-id',
    );
    expect(repeated, first);

    await stickyPrefs.setString(kChildHomeArmKey, ChildHomeArm.classic.name);
    final forcedV2 = await resolveChildHomeArm(
      prefs: stickyPrefs,
      serverMode: 'v2',
      getDeviceId: () async => 'sticky-device-1',
    );
    expect(forcedV2, ChildHomeArm.weekly);
  });

  testWidgets(
    'Friday shows friday_harvest_banner via clockProvider while Thursday hides it',
    (tester) async {
      final thursday = DateTime(2026, 11, 12, 18);
      await pumpWeeklyHome(
        tester,
        now: thursday,
        familyWeek: familyWeekJson(
          now: thursday,
          acts: [
            act('lesson', 0, title: 'L1'),
            act('question', 1),
          ],
        ),
      );
      await tester.scrollUntilVisible(
        find.byType(TodayFocusCard),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      expect(
        find.byKey(const ValueKey('friday_harvest_banner')),
        findsNothing,
      );

      await tester.pumpWidget(const SizedBox());
      final friday = DateTime(2026, 11, 13, 18);
      await pumpWeeklyHome(
        tester,
        now: friday,
        familyWeek: familyWeekJson(
          now: friday,
          acts: [
            act('lesson', 0, title: 'L1'),
            act('question', 1),
          ],
        ),
      );
      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('friday_harvest_banner')),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      expect(
        find.byKey(const ValueKey('friday_harvest_banner')),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'English + Dark + 200% text full scroll renders zero Arabic script',
    (tester) async {
      final friday = DateTime(2026, 11, 13, 18);
      await pumpWeeklyHome(
        tester,
        locale: const Locale('en'),
        dark: true,
        textScale: 2.0,
        childName: 'Sara',
        now: friday,
        familyWeek: familyWeekJson(
          now: friday,
          acts: [
            act('lesson', 0, title: 'Listening lesson'),
            act('question', 1),
          ],
        ),
      );

      final arabic = RegExp(r'[\u0600-\u06FF]');
      final scrollable = find.byType(Scrollable).first;
      for (var step = 0; step < 12; step++) {
        expect(tester.takeException(), isNull);
        for (final t in tester.widgetList<Text>(find.byType(Text))) {
          final s = t.data ?? t.textSpan?.toPlainText() ?? '';
          expect(
            arabic.hasMatch(s),
            isFalse,
            reason: 'Unexpected Arabic text in EN dark weekly home: "$s"',
          );
        }
        final state = tester.state<ScrollableState>(scrollable);
        if (state.position.pixels >= state.position.maxScrollExtent - 1) {
          break;
        }
        await tester.drag(find.byType(ListView).first, const Offset(0, -350));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 250));
      }
    },
  );

  testWidgets(
    'Dynamic birthMonth overrides stored ageGroup on client and toggles nudge',
    (tester) async {
      final containerWithBirthMonth = await pumpWeeklyHome(
        tester,
        ageGroup: '4-6',
        birthMonth: '2018-05',
        now: DateTime(2026, 11, 14, 10),
      );
      expect(
        containerWithBirthMonth.read(activeChildProfileProvider)?.ageGroup,
        '7-9',
      );
      expect(
        find.byKey(const ValueKey('child_birth_month_nudge')),
        findsNothing,
      );

      await tester.pumpWidget(const SizedBox());
      final containerWithoutBirthMonth = await pumpWeeklyHome(
        tester,
        ageGroup: '4-6',
        birthMonth: null,
        now: DateTime(2026, 11, 14, 10),
      );
      expect(
        containerWithoutBirthMonth.read(activeChildProfileProvider)?.ageGroup,
        '4-6',
      );
      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('child_birth_month_nudge')),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      expect(
        find.byKey(const ValueKey('child_birth_month_nudge')),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'English weekly header keeps child name bounded for Today visibility check',
    (tester) async {
      await pumpWeeklyHome(
        tester,
        locale: const Locale('en'),
        childName: 'E2E-Maestro',
        now: DateTime(2026, 11, 14, 10),
      );
      const expected = "This week's plan for E2E-Maestro";
      expect(find.text(expected), findsOneWidget);
      expect(
        RegExp(r'^(?:.*\s)?E2E-Maestro(?:\s.*)?$', dotAll: true).hasMatch(expected),
        isTrue,
      );
    },
  );

  testWidgets(
    '3-station layout drops legacy coin/shortcut clutter and unifies family time',
    (tester) async {
      for (final dark in [false, true]) {
        await tester.pumpWidget(const SizedBox());
        await pumpWeeklyHome(
          tester,
          locale: const Locale('ar'),
          dark: dark,
          childName: 'سارة',
          birthMonth: '2018-05',
          now: DateTime(2026, 11, 14, 10),
        );

        expect(find.byType(DailyGiftMoment), findsNothing);
        expect(find.byType(HomeStatsRow), findsNothing);
        expect(find.byType(HomeShortcutsGrid), findsNothing);
        expect(find.byType(TodayMoreDivider), findsNothing);
        // No duplicate "مهمة سارة اليوم" header alongside TodayMissionRow.
        expect(find.text('مهمة سارة اليوم'), findsNothing);

        Future<void> snap(String tag) async {
          if (_dumpTodayDir.isEmpty) return;
          Directory(_dumpTodayDir).createSync(recursive: true);
          final boundary = find.ancestor(
            of: find.byType(HomeScreen),
            matching: find.byType(RepaintBoundary),
          ).first;
          final ro = boundary.evaluate().single.findRenderObject()!
              as RenderRepaintBoundary;
          final img = await tester.runAsync(() => ro.toImage(pixelRatio: 2.0));
          final bd = await tester.runAsync(
            () => img!.toByteData(format: ui.ImageByteFormat.png),
          );
          img!.dispose();
          File('$_dumpTodayDir/today_${dark ? "dark" : "light"}_$tag.png')
              .writeAsBytesSync(bd!.buffer.asUint8List());
        }

        await snap('top');

        await tester.scrollUntilVisible(
          find.byKey(const ValueKey('today_family_puzzles_card')),
          220,
          scrollable: find.byType(Scrollable).first,
        );
        expect(
          find.byKey(const ValueKey('today_family_puzzles_card')),
          findsOneWidget,
        );
        await tester.scrollUntilVisible(
          find.byKey(const ValueKey('today_child_corner_handover')),
          220,
          scrollable: find.byType(Scrollable).first,
        );
        expect(
          find.byKey(const ValueKey('today_child_corner_handover')),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
        await snap('mid');
      }
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 1));
    },
  );

  testWidgets(
    'reflection slot stays empty while loading and never builds TodayMawqifCard for active child followup',
    (tester) async {
      final completer = Completer<List<Followup>>();
      final client = _FakeWeeklyClient();
      await pumpWeeklyHome(
        tester,
        phone: const Size(420, 1200),
        client: client,
        mawaqif: [_sampleMawqifJson()],
        dueFollowupsOverride:
            dueFollowupsProvider.overrideWith((_) => completer.future),
      );

      // While dueFollowupsProvider is loading: neither card builds in any frame.
      expect(find.byType(TodayFollowupCard, skipOffstage: false), findsNothing);
      expect(find.byType(TodayMawqifCard, skipOffstage: false), findsNothing);
      expect(client.mawaqifCalls, 0);

      // Resolving with a due followup for active child (id 1): only TodayFollowupCard shows.
      completer.complete(const [
        Followup(
          id: 1,
          childId: 1,
          strategy: 'التنفس الهادئ عند الغضب',
          status: 'pending',
        ),
      ]);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.byType(TodayFollowupCard), findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(TodayFollowupCard),
          matching: find.textContaining('التنفس الهادئ عند الغضب'),
        ),
        findsOneWidget,
      );
      expect(find.byType(TodayMawqifCard, skipOffstage: false), findsNothing);
      expect(client.mawaqifCalls, 0);

      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 1));
    },
  );

  testWidgets(
    'reflection slot shows TodayMawqifCard when dueFollowupsProvider settles empty or errors',
    (tester) async {
      await pumpWeeklyHome(
        tester,
        phone: const Size(420, 1200),
        mawaqif: [_sampleMawqifJson()],
        dueFollowupsOverride:
            dueFollowupsProvider.overrideWith((_) async => const <Followup>[]),
      );
      expect(find.byType(TodayFollowupCard), findsNothing);
      expect(find.byType(TodayMawqifCard), findsOneWidget);
      expect(find.byKey(const ValueKey('today-mawqif')), findsOneWidget);

      await tester.pumpWidget(const SizedBox());
      await pumpWeeklyHome(
        tester,
        phone: const Size(420, 1200),
        mawaqif: [_sampleMawqifJson()],
        dueFollowupsOverride: dueFollowupsProvider
            .overrideWith((_) => Future<List<Followup>>.error(StateError('offline'))),
      );
      expect(find.byType(TodayFollowupCard), findsNothing);
      expect(find.byType(TodayMawqifCard), findsOneWidget);
      expect(find.byKey(const ValueKey('today-mawqif')), findsOneWidget);

      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 1));
    },
  );

  testWidgets(
    'sibling due followup shows both TodayFollowupCard and active child TodayMawqifCard',
    (tester) async {
      await pumpWeeklyHome(
        tester,
        phone: const Size(420, 1400),
        mawaqif: [_sampleMawqifJson()],
        dueFollowupsOverride: dueFollowupsProvider.overrideWith(
          (_) async => const [
            Followup(
              id: 2,
              childId: 2,
              strategy: 'قصة قصيرة قبل النوم',
              status: 'pending',
            ),
          ],
        ),
      );

      expect(find.byType(TodayFollowupCard), findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(TodayFollowupCard),
          matching: find.textContaining('قصة قصيرة قبل النوم'),
        ),
        findsOneWidget,
      );
      expect(find.byType(TodayMawqifCard), findsOneWidget);
      expect(find.byKey(const ValueKey('today-mawqif')), findsOneWidget);

      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 1));
    },
  );

  testWidgets(
    'Monday week_start keeps summaryCollapsed weekly plan bar collapsed without Monday auto-reveal',
    (tester) async {
      final monday = DateTime(2026, 11, 9, 10);
      expect(monday.weekday, DateTime.monday);
      final container = await pumpWeeklyHome(
        tester,
        phone: const Size(420, 1200),
        now: monday,
      );
      final prefs = await container.read(sharedPreferencesProvider.future);
      expect(prefs.getString(TodayWeeklyPlanCard.revealKey(1)), isNull);

      expect(
        find.byKey(const ValueKey('weekly_plan_summary_bar')),
        findsOneWidget,
      );
      expect(find.text('الاستماع الهادئ'), findsOneWidget);
      expect(find.text('دقيقتان من الإنصات'), findsNothing);
      expect(find.text('دعاء المساء معاً'), findsNothing);

      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 1));
    },
  );
}
