import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:almorabbi/api/tg_client.dart';
import 'package:almorabbi/core/clock.dart';
import 'package:almorabbi/features/child_memory/widgets/today_weekly_plan_card.dart';
import 'package:almorabbi/features/home/experiment/child_home_experiment.dart';
import 'package:almorabbi/features/home/widgets/child_weekly_home.dart';
import 'package:almorabbi/features/home/widgets/sky_band.dart';
import 'package:almorabbi/features/home/widgets/today_focus_card.dart';
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

class _FakeWeeklyClient extends TgClient {
  _FakeWeeklyClient()
      : super.forTesting(
          baseUrl: 'http://fake.invalid',
          httpClient: MockClient((_) async => http.Response('{}', 404)),
        );

  Map<String, dynamic>? progress;
  Map<String, dynamic>? familyWeek;
  bool includePlan = true;

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
    bool justOnboarded = false,
    String? firstWeekRecordedIso,
    Map<String, dynamic>? appConfig,
  }) async {
    tester.view.physicalSize = phone * 3.0;
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    final fake = _FakeWeeklyClient()..familyWeek = familyWeek;
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
        if (now != null) clockProvider.overrideWithValue(() => now),
      ],
    );
    addTearDown(container.dispose);
    await container.read(sharedPreferencesProvider.future);
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
    'Week 1 after onboarding shows badge and auto-expands TodayWeeklyPlanCard',
    (tester) async {
      await pumpWeeklyHome(
        tester,
        justOnboarded: true,
        now: DateTime(2026, 11, 14, 10),
      );
      expect(find.text('أسبوع البداية'), findsOneWidget);
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
}
