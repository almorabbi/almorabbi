// Phase 4 widget tests — program layer (paths/lessons/daily tip).
//
// Strategy: we don't hit the real network. We override
// [tgClientProvider] with a `_FakeTgClient` whose HTTP methods return
// canned JSON shaped exactly like the backend responses, then assert
// the UI renders the expected widgets (titles, counts, error state).

import 'dart:ui' show Tristate;

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:almorabbi/api/tg_client.dart';
import 'package:almorabbi/features/child_corner/corner_picks.dart';
import 'package:almorabbi/features/onboarding/data/onboarding_storage.dart';
import 'package:almorabbi/features/onboarding/providers/onboarding_providers.dart';
import 'package:almorabbi/features/program/data/program_repository.dart';
import 'package:almorabbi/features/program/data/story_models.dart';
import 'package:almorabbi/features/program/providers/program_providers.dart';
import 'package:almorabbi/features/program/providers/progress_providers.dart';
import 'package:almorabbi/features/program/screens/lesson_screen.dart';
import 'package:almorabbi/features/program/screens/path_detail_screen.dart';
import 'package:almorabbi/features/program/screens/paths_screen.dart';
import 'package:almorabbi/features/onboarding/screens/update_splash_screen.dart';
import 'package:almorabbi/features/shell/root_tab.dart';
import 'package:almorabbi/main.dart';
import 'package:almorabbi/l10n/app_localizations.dart';
import 'package:almorabbi/state/chat_notifier.dart';

void main() {
  group('ProgramRepository', () {
    test('listPaths() parses backend envelope', () async {
      final fake = _FakeTgClient();
      fake.pathsListJson = {
        'count': 1,
        'paths': [_pathJson(id: 'path_4-6_islamic_parenting_adab')],
      };
      final repo = ProgramRepository(fake);
      final result = await repo.listPaths(ageGroup: '4-6');
      expect(result.count, 1);
      expect(result.paths.first.id, 'path_4-6_islamic_parenting_adab');
      expect(result.paths.first.ageGroup, '4-6');
      expect(result.paths.first.lessonIds.length, 3);
    });

    test('getPathDetail() with includeLessons returns PathDetail', () async {
      final fake = _FakeTgClient();
      // API returns path fields at the ROOT level (flat) with a
      // `lessons` array — no "path" wrapper key (see commit 7d056fc).
      fake.pathDetailJson = {
        ..._pathJson(id: 'path_4-6_islamic_parenting_adab'),
        'lessons': [
          _lessonJson(id: 'lesson_4-6_islamic_parenting_adab_01', order: 1),
        ],
      };
      final repo = ProgramRepository(fake);
      final detail = await repo.getPathDetail(
        'path_4-6_islamic_parenting_adab',
      );
      expect(detail.path.id, 'path_4-6_islamic_parenting_adab');
      expect(detail.lessons.length, 1);
      expect(detail.lessons.first.order, 1);
    });

    test('getLesson() parses single lesson', () async {
      final fake = _FakeTgClient();
      fake.lessonJson = _lessonJson(
        id: 'lesson_4-6_islamic_parenting_adab_01',
        order: 1,
        withWarning: true,
      );
      final repo = ProgramRepository(fake);
      final lesson = await repo.getLesson(
        'lesson_4-6_islamic_parenting_adab_01',
      );
      expect(lesson.title, 'الرفق: قيمة تربوية قبل أسلوب');
      expect(lesson.needsProfessionalFollowup, isTrue);
    });
    });

    group('Program widgets', () {
    testWidgets('PathsScreen shows cards from fake list', (WidgetTester tester) async {
      final fake = _FakeTgClient();
      fake.pathsListJson = {
        'count': 2,
        'paths': [
          _pathJson(
            id: 'path_4-6_islamic_parenting_adab',
            title: 'تأسيس الآداب الإسلامية',
          ),
          _pathJson(
            id: 'path_4-6_development_positive_parenting',
            title: 'التربية الإيجابية',
          ),
        ],
      };

      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final storage = OnboardingStorage(prefs);
      await storage.setActiveChild(id: 1, name: 'سارة', ageGroup: '4-6');
      await storage.markOnboardingCompleted();

      final container = ProviderContainer(
        overrides: [
          tgClientProvider.overrideWithValue(fake),
          sharedPreferencesProvider.overrideWith((_) async => prefs),
        ],
      );
      await container.read(sharedPreferencesProvider.future);
      container.read(activeChildIdProvider.notifier).state = 1;
      addTearDown(container.dispose);

      // Set a larger viewport to avoid AppBar overflow
      tester.view.physicalSize = const Size(400, 800);
      tester.view.devicePixelRatio = 1.0;

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(
            locale: Locale('ar'),
            home: PathsScreen(),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
          ),
        ),
      );
      await tester.pumpAndSettle();

      // AppBar title is the word the user tapped in the nav bar («التعلّم»);
      // it used to read «مساراتي», so the word you press and the word you land
      // on were different. It also has to FIT: «مسارات التعلّم 🛤️» rendered as
      // «مسارات الت...» next to the child chip and three action icons on a
      // 1080px screen. Caught on an emulator; no test can see an ellipsis.
      expect(find.textContaining('التعلّم'), findsWidgets);
      // The reader is named before any card is read: the age band on a card is
      // the child's, the prose behind it is addressed to the parent.
      expect(find.textContaining('هذه الدروس تقرؤها أنت'), findsOneWidget);
      expect(find.textContaining('عن طفلك في'), findsWidgets);
      expect(find.text('تأسيس الآداب الإسلامية'), findsOneWidget);
      expect(find.text('التربية الإيجابية'), findsOneWidget);
      // Days pill on the path cards (emoji-prefixed in the redesign)
      expect(find.textContaining('14 يوم'), findsWidgets);
      // Accessibility (P1 #5): each path card exposes one coherent button
      // semantics node labelled with its title for screen readers.
      expect(
        find.bySemanticsLabel(RegExp('مسار: تأسيس الآداب الإسلامية')),
        findsOneWidget,
      );
    });

    testWidgets('PathsScreen shows error state on failure', (WidgetTester tester) async {
      final fake = _FakeTgClient();
      fake.throwOnPathsList = true;

      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final storage = OnboardingStorage(prefs);
      await storage.setActiveChild(id: 1, name: 'سارة', ageGroup: '4-6');
      await storage.markOnboardingCompleted();

      final container = ProviderContainer(
        overrides: [
          tgClientProvider.overrideWithValue(fake),
          sharedPreferencesProvider.overrideWith((_) async => prefs),
        ],
      );
      await container.read(sharedPreferencesProvider.future);
      container.read(activeChildIdProvider.notifier).state = 1;
      addTearDown(container.dispose);

      // Set a larger viewport
      tester.view.physicalSize = const Size(400, 800);
      tester.view.devicePixelRatio = 1.0;

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(
            locale: Locale('ar'),
            home: PathsScreen(),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('إعادة المحاولة'), findsOneWidget);
    });

    for (final locale in const [Locale('ar'), Locale('en')]) {
      testWidgets('lesson favorite has localized semantics and a 48dp target (${locale.languageCode})', (t) async {
        final semantics = t.ensureSemantics();
        try {
          SharedPreferences.setMockInitialValues({});
          final prefs = await SharedPreferences.getInstance();
          final container = ProviderContainer(overrides: [
            tgClientProvider.overrideWithValue(_FakeTgClient()),
            sharedPreferencesProvider.overrideWith((_) async => prefs),
          ]);
          addTearDown(container.dispose);
          await container.read(sharedPreferencesProvider.future);
          await t.pumpWidget(UncontrolledProviderScope(
            container: container,
            child: MaterialApp(
              locale: locale,
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              home: const LessonScreen(lessonId: 'a11y-lesson', ageGroup: '4-6'),
            ),
          ));
          await t.pumpAndSettle();
          final l10n = AppLocalizations.of(t.element(find.byType(LessonScreen)));
          final favorite = find.bySemanticsLabel(l10n.lessonFavAdd);
          expect(favorite, findsOneWidget);
          final offData = t.getSemantics(favorite).getSemanticsData();
          expect(offData.hasAction(SemanticsAction.tap), isTrue);
          // A favourite is an on/off state, not just a button: TalkBack must
          // announce "off" here and "on" after the tap.
          expect(offData.flagsCollection.isToggled, Tristate.isFalse);
          final button = find.byTooltip(l10n.lessonFavAdd);
          expect(t.getSize(button).height, greaterThanOrEqualTo(48));
          expect(t.getSize(button).width, greaterThanOrEqualTo(48));
          await t.tap(button);
          await t.pumpAndSettle();
          final removed = find.bySemanticsLabel(l10n.lessonFavRemove);
          expect(removed, findsOneWidget);
          expect(t.getSemantics(removed).getSemanticsData().flagsCollection.isToggled,
              Tristate.isTrue);
        } finally {
          semantics.dispose();
        }
      });
    }

    testWidgets('LessonScreen renders try_this, summary, reflection prompts',
        (WidgetTester tester) async {
      final fake = _FakeTgClient();
      fake.lessonJson = _lessonJson(
        id: 'lesson_4-6_islamic_parenting_adab_01',
        order: 1,
        summary: 'ملخص تجريبي للدرس.',
        tryThis: 'جرّب هذا النص في أسبوعك.',
        reflectionPrompts: ['سؤال 1؟', 'سؤال 2؟'],
        withWarning: false,
      );

      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final storage = OnboardingStorage(prefs);
      await storage.setActiveChild(id: 1, name: 'سارة', ageGroup: '4-6');
      await storage.markOnboardingCompleted();

      final container = ProviderContainer(
        overrides: [
          tgClientProvider.overrideWithValue(fake),
          sharedPreferencesProvider.overrideWith((_) async => prefs),
        ],
      );
      await container.read(sharedPreferencesProvider.future);
      container.read(activeChildIdProvider.notifier).state = 1;
      addTearDown(container.dispose);
      tester.view.physicalSize = const Size(800, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(
            locale: Locale('ar'),
            home: LessonScreen(
              lessonId: 'lesson_4-6_islamic_parenting_adab_01',
              ageGroup: '4-6',
              childId: 1,
            ),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('ملخص الدرس'), findsOneWidget);
      expect(find.text('جرّب هذا'), findsOneWidget);
      expect(find.text('ملخص تجريبي للدرس.'), findsOneWidget);
      expect(find.text('جرّب هذا النص في أسبوعك.'), findsOneWidget);
      // 2.0.4: actionable try_this is surfaced above the longer summary.
      expect(
        tester.getTopLeft(find.text('جرّب هذا')).dy,
        lessThan(tester.getTopLeft(find.text('ملخص الدرس')).dy),
        reason: 'practical step must appear above the fold before summary',
      );
      // Scroll down to the reflection prompts; they live below the fold in
      // the lesson ListView, so find.text cannot see them while offstage.
      await tester.scrollUntilVisible(
        find.text('سؤال 1؟'),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('سؤال 1؟'), findsOneWidget);
      expect(find.text('سؤال 2؟'), findsOneWidget);
      // needs_professional_followup is NOT set on this lesson
      expect(find.textContaining('متابعة متخصصة'), findsNothing);
    });

    // Regression: a lesson reached by deep link or from favourites is built
    // with childId: null and no age band. That used to hide the completion
    // button with no explanation, so every notification landing on a lesson
    // produced a page the parent could read but never finish — and
    // lesson_opened never fired for it either.
    testWidgets('LessonScreen falls back to the active child when none is passed',
        (WidgetTester tester) async {
      final fake = _FakeTgClient();
      fake.lessonJson = _lessonJson(
        id: 'lesson_4-6_islamic_parenting_adab_01',
        order: 1,
        summary: 'ملخص تجريبي للدرس.',
        tryThis: 'جرّب هذا النص في أسبوعك.',
        reflectionPrompts: const [],
        withWarning: false,
      );

      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final storage = OnboardingStorage(prefs);
      await storage.setActiveChild(id: 7, name: 'سارة', ageGroup: '4-6');
      await storage.markOnboardingCompleted();

      final container = ProviderContainer(
        overrides: [
          tgClientProvider.overrideWithValue(fake),
          sharedPreferencesProvider.overrideWith((_) async => prefs),
        ],
      );
      await container.read(sharedPreferencesProvider.future);
      container.read(activeChildIdProvider.notifier).state = 7;
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(
            locale: Locale('ar'),
            // Exactly what deep_link_handler.dart builds: no child, no age.
            home: LessonScreen(
              lessonId: 'lesson_4-6_islamic_parenting_adab_01',
              ageGroup: '',
              childId: null,
            ),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('أتممت هذا الدرس'), findsOneWidget,
          reason: 'the completion CTA must resolve the active child itself');
      expect(find.text('أضف طفلك'), findsNothing);
    });

    testWidgets('LessonScreen offers add-child when there is genuinely no child',
        (WidgetTester tester) async {
      final fake = _FakeTgClient();
      fake.lessonJson = _lessonJson(
        id: 'lesson_4-6_islamic_parenting_adab_01',
        order: 1,
        summary: 'ملخص تجريبي للدرس.',
        tryThis: 'جرّب هذا النص في أسبوعك.',
        reflectionPrompts: const [],
        withWarning: false,
      );

      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();

      final container = ProviderContainer(
        overrides: [
          tgClientProvider.overrideWithValue(fake),
          sharedPreferencesProvider.overrideWith((_) async => prefs),
        ],
      );
      await container.read(sharedPreferencesProvider.future);
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(
            locale: Locale('ar'),
            home: LessonScreen(
              lessonId: 'lesson_4-6_islamic_parenting_adab_01',
              ageGroup: '',
              childId: null,
            ),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
          ),
        ),
      );
      await tester.pumpAndSettle();

      // A way forward, rather than a silently missing button.
      expect(find.text('أضف طفلك'), findsOneWidget);
      expect(find.text('أتممت هذا الدرس'), findsNothing);
    });

    testWidgets('LessonScreen shows interactive content section when assets are present',
        (WidgetTester tester) async {
      final fake = _FakeTgClient();
      fake.lessonJson = _lessonJson(
        id: 'lesson_4-6_islamic_parenting_adab_01',
        order: 1,
      );
      fake.lessonAssetsJson = {
        'podcast_mp3': 'docs/lesson_01_podcast.mp3',
        'video_mp4': 'docs/lesson_videos/video.mp4',
        'flashcards': [
          {'id': 'fc-1', 'item_count': 10}
        ],
        'quizzes': [
          {'id': 'qz-1', 'item_count': 5}
        ]
      };

      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final storage = OnboardingStorage(prefs);
      await storage.setActiveChild(id: 1, name: 'سارة', ageGroup: '4-6');
      await storage.markOnboardingCompleted();

      final container = ProviderContainer(
        overrides: [
          tgClientProvider.overrideWithValue(fake),
          sharedPreferencesProvider.overrideWith((_) async => prefs),
        ],
      );
      await container.read(sharedPreferencesProvider.future);
      container.read(activeChildIdProvider.notifier).state = 1;
      addTearDown(container.dispose);
      tester.view.physicalSize = const Size(800, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(
            locale: Locale('ar'),
            home: LessonScreen(
              lessonId: 'lesson_4-6_islamic_parenting_adab_01',
              ageGroup: '4-6',
              childId: 1,
            ),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Quick media bar surfaces Video & Podcast directly below the summary
      // (GA4 shows >54% open video & 35% podcast), while study tools stay
      // collapsed in lesson_deepen_tile below.
      final quickVideo = find.byKey(const Key('lesson_quick_video'));
      final quickPodcast = find.byKey(const Key('lesson_quick_podcast'));
      await tester.scrollUntilVisible(
        quickVideo,
        200,
        scrollable: find.byType(Scrollable).first,
      );
      expect(quickVideo, findsOneWidget);
      expect(quickPodcast, findsOneWidget);

      final deepenTile = find.byKey(const Key('lesson_deepen_tile'));
      await tester.scrollUntilVisible(
        deepenTile,
        250,
        scrollable: find.byType(Scrollable).first,
      );
      expect(deepenTile, findsOneWidget);
      expect(find.textContaining('أدوات المراجعة'), findsOneWidget);
      // Study tools are collapsed by default:
      expect(find.textContaining('فلاش كاردز (10 بطاقة)'), findsNothing);

      // Expand the collapsible extras card:
      await tester.tap(find.textContaining('أدوات المراجعة'));
      await tester.pumpAndSettle();

      expect(find.textContaining('فلاش كاردز (10 بطاقة)'), findsOneWidget);
      expect(find.textContaining('اختبر نفسك (5 سؤال)'), findsOneWidget);

      // Scroll back to quick media bar and tap podcast to verify the real
      // player screen opens with its download button.
      await tester.scrollUntilVisible(
        quickPodcast,
        -200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(quickPodcast);
      // Pump a few frames so the navigator can finish pushing the
      // new route. We don't pumpAndSettle because just_audio's
      // MethodChannel never resolves in the host VM.
      for (var i = 0; i < 5; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
      expect(find.byKey(const Key('podcast_download_button')), findsOneWidget);
    });

    testWidgets('LessonScreen renders parent_script and sends assistant_prompts to assistant tab',
        (WidgetTester tester) async {
      final fake = _FakeTgClient();
      fake.lessonJson = {
        ..._lessonJson(
          id: 'lesson_4-6_islamic_parenting_bond_01',
          order: 1,
          summary: 'ملخص تربوي عملي.',
          tryThis: 'جرّب هذا الليلة لمدة خمس دقائق.',
        ),
        'parent_script': '«يا حبيبي أنا معك الآن، هيا نلعب معًا خمس دقائق.»',
        'assistant_prompts': ['طفلي يرفض اللعب المشترك، ماذا أفعل؟'],
      };

      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final storage = OnboardingStorage(prefs);
      await storage.setActiveChild(id: 1, name: 'سارة', ageGroup: '4-6');
      await storage.markOnboardingCompleted();

      final container = ProviderContainer(
        overrides: [
          tgClientProvider.overrideWithValue(fake),
          sharedPreferencesProvider.overrideWith((_) async => prefs),
        ],
      );
      await container.read(sharedPreferencesProvider.future);
      container.read(activeChildIdProvider.notifier).state = 1;
      addTearDown(container.dispose);
      tester.view.physicalSize = const Size(800, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(
            locale: Locale('ar'),
            home: LessonScreen(
              lessonId: 'lesson_4-6_islamic_parenting_bond_01',
              ageGroup: '4-6',
              childId: 1,
            ),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('جملتك الجاهزة لطفلك الليلة'), findsOneWidget);
      expect(
        find.text('«يا حبيبي أنا معك الآن، هيا نلعب معًا خمس دقائق.»'),
        findsOneWidget,
      );

      final promptFinder = find.text('طفلي يرفض اللعب المشترك، ماذا أفعل؟');
      await tester.scrollUntilVisible(
        promptFinder,
        250,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(promptFinder);
      await tester.pumpAndSettle();

      expect(
        container.read(pendingChatQuestionProvider),
        'طفلي يرفض اللعب المشترك، ماذا أفعل؟',
      );
      expect(container.read(rootTabRequestProvider), RootTab.assistant);
    });

    test('rememberLessonStoryForToday bridges lesson story into Child Corner for today only',
        () async {
      SharedPreferences.setMockInitialValues({});
      final today = DateTime(2026, 11, 24, 20, 0);
      final tomorrow = DateTime(2026, 11, 25, 9, 0);
      await rememberLessonStoryForToday('story_b', today);

      expect(await preferredLessonStoryForToday(today), 'story_b');
      expect(await preferredLessonStoryForToday(tomorrow), isNull);

      final stories = [
        Story(
          id: 'story_a',
          title: 'أ',
          description: '',
          coverImage: '',
          themeColor: '#0F6B5C',
          pages: [StoryPage(pageNumber: 1, text: 'p1', image: '')],
        ),
        Story(
          id: 'story_b',
          title: 'ب',
          description: '',
          coverImage: '',
          themeColor: '#0F6B5C',
          pages: [StoryPage(pageNumber: 1, text: 'p1', image: '')],
        ),
      ];
      final picked = cornerStoryFor(
        stories,
        today,
        preferredStoryId: await preferredLessonStoryForToday(today),
      );
      expect(picked?.id, 'story_b');
    });

    testWidgets('LessonScreen does not show interactive content when no assets are present',
        (WidgetTester tester) async {
      final fake = _FakeTgClient();
      fake.lessonJson = _lessonJson(
        id: 'lesson_4-6_islamic_parenting_adab_01',
        order: 1,
      );
      fake.lessonAssetsJson = null; // will throw 404/error

      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final storage = OnboardingStorage(prefs);
      await storage.setActiveChild(id: 1, name: 'سارة', ageGroup: '4-6');
      await storage.markOnboardingCompleted();

      final container = ProviderContainer(
        overrides: [
          tgClientProvider.overrideWithValue(fake),
          sharedPreferencesProvider.overrideWith((_) async => prefs),
        ],
      );
      await container.read(sharedPreferencesProvider.future);
      container.read(activeChildIdProvider.notifier).state = 1;
      addTearDown(container.dispose);
      tester.view.physicalSize = const Size(800, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(
            locale: Locale('ar'),
            home: LessonScreen(
              lessonId: 'lesson_4-6_islamic_parenting_adab_01',
              ageGroup: '4-6',
              childId: 1,
            ),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('محتوى تفاعلي'), findsNothing);
    });

    testWidgets('PathDetailScreen lists lessons, navigate to lesson screen',
        (WidgetTester tester) async {
      final fake = _FakeTgClient();
      fake.pathDetailJson = {
        ..._pathJson(id: 'path_4-6_islamic_parenting_adab'),
        'lessons': [
          _lessonJson(
            id: 'lesson_4-6_islamic_parenting_adab_01',
            order: 1,
            title: 'الرفق',
          ),
          _lessonJson(
            id: 'lesson_4-6_islamic_parenting_adab_02',
            order: 2,
            title: 'اللعب النبوي',
          ),
        ],
      };

      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final storage = OnboardingStorage(prefs);
      await storage.setActiveChild(id: 1, name: 'سارة', ageGroup: '4-6');
      await storage.markOnboardingCompleted();

      final container = ProviderContainer(
        overrides: [
          tgClientProvider.overrideWithValue(fake),
          sharedPreferencesProvider.overrideWith((_) async => prefs),
        ],
      );
      await container.read(sharedPreferencesProvider.future);
      container.read(activeChildIdProvider.notifier).state = 1;
      addTearDown(container.dispose);
      tester.view.physicalSize = const Size(800, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(
            locale: Locale('ar'),
            home: PathDetailScreen(
              pathId: 'path_4-6_islamic_parenting_adab',
              ageGroup: '4-6',
            ),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 100));

      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 100));

      // The domain art holds its height above the lessons from the first
      // frame (an SVG reserves its box while it parses), so on the test's
      // 800×600 screen the list starts below the fold — as it always did on
      // a phone, under the 1024² art this replaced. Scroll to it.
      await tester.scrollUntilVisible(
        find.text('اللعب النبوي'),
        200,
        scrollable: find
            .descendant(
              of: find.byType(ListView),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      expect(find.text('الرفق'), findsOneWidget);
      expect(find.text('اللعب النبوي'), findsOneWidget);
      expect(find.text('الدروس (2)'), findsOneWidget);
      // Tap the first lesson - set lessonJson BEFORE tapping so the navigation gets the data
      fake.lessonJson = _lessonJson(
        id: 'lesson_4-6_islamic_parenting_adab_01',
        order: 1,
        title: 'الرفق',
      );
      await tester.tap(find.text('الرفق'));
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 100));
      // The lesson screen should appear with the lesson loaded
      expect(find.text('ملخص الدرس'), findsOneWidget);
    });

    testWidgets('RootScaffold NavigationBar switches tabs', (WidgetTester tester) async {
      // Use a fake that works for paths list but throws elsewhere
      final fake = _FakeTgClient();
      fake.pathsListJson = {
        'count': 2,
        'paths': [
          _pathJson(
            id: 'path_4-6_islamic_parenting_adab',
            title: 'تأسيس الآداب الإسلامية',
          ),
          _pathJson(
            id: 'path_4-6_development_positive_parenting',
            title: 'التربية الإيجابية',
          ),
        ],
      };

      SharedPreferences.setMockInitialValues({});
      // The boot reads the child-mode flag before it builds the parent's app
      // (ChildModeGate). An unmocked plugin call never answers inside a
      // widget test, so without this the app would wait on its splash.
      FlutterSecureStorage.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final storage = OnboardingStorage(prefs);
      await storage.setActiveChild(id: 1, name: 'سارة', ageGroup: '4-6');
      await storage.markOnboardingCompleted();
      await storage.markUpdateSeen(updateSplashVersion); // skip the update splash

      final container = ProviderContainer(
        overrides: [
          tgClientProvider.overrideWithValue(fake),
          sharedPreferencesProvider.overrideWith((_) async => prefs),
        ],
      );
      await container.read(sharedPreferencesProvider.future);
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const TutorGuardianApp(),
        ),
      );
      // Pump multiple times to let the boot sequence complete
      for (int i = 0; i < 80; i++) {
        await tester.pump(const Duration(milliseconds: 500));
        if (find.byType(NavigationBar).evaluate().isNotEmpty) break;
      }
      await tester.pump(const Duration(milliseconds: 1000));
      await tester.pump(const Duration(milliseconds: 1000));

      // Tab 0 (المساعد) is the default
      await tester.pump(const Duration(milliseconds: 1000));
      await tester.pump(const Duration(milliseconds: 1000));
      await tester.pump(const Duration(milliseconds: 1000));
      await tester.pump(const Duration(milliseconds: 1000));

      expect(find.byType(NavigationBar), findsOneWidget);
      final navBar = tester.widget<NavigationBar>(find.byType(NavigationBar));
      expect(navBar.destinations.length, RootTab.count);

      // The IndexedStack must have exactly one child per destination. When the
      // shell went from five tabs to four, HomeScreen was still asking for
      // index 4 — which is not a wrong screen, it is a range crash.
      final stack = tester.widget<IndexedStack>(find.byType(IndexedStack).first);
      expect(stack.children.length, RootTab.count);
      for (final index in [RootTab.today, RootTab.learn, RootTab.assistant, RootTab.more]) {
        expect(index, lessThan(RootTab.count));
      }

      // Every label is static. The old 4th tab renamed itself by child age
      // («حساب اليوم» / «ميزان العادات»), which is why it no longer lives here.
      expect(
        find.descendant(
          of: find.byType(NavigationBar),
          matching: find.text('اليوم'),
        ),
        findsOneWidget,
      );
      expect(find.text('التعلّم'), findsOneWidget);
      expect(find.text('المساعد'), findsOneWidget);
      expect(find.text('المزيد'), findsOneWidget);

      // Actually switch to the التعلّم (paths) tab. IndexedStack keeps the
      // non-active tab offstage, so its content isn't findable until selected.
      await tester.tap(find.text('التعلّم'));
      for (int i = 0; i < 12; i++) {
        await tester.pump(const Duration(milliseconds: 300));
        if (find.text('تأسيس الآداب الإسلامية').evaluate().isNotEmpty) break;
      }

      // Should now show the PathsScreen content
      expect(find.text('تأسيس الآداب الإسلامية'), findsOneWidget);
    });
  });
}

// ── Fake TgClient ─────────────────────────────────────────────────────────

class _FakeTgClient extends TgClient {
  Map<String, dynamic>? pathsListJson;
  Map<String, dynamic>? pathDetailJson;
  Map<String, dynamic>? lessonJson;
  Map<String, dynamic>? lessonAssetsJson;
  bool throwOnPathsList = false;

  @override
  Future<Map<String, dynamic>> getPathsList({
    String? ageGroup,
    String? domain,
  }) async {
    if (throwOnPathsList) {
      throw const TgApiError(500, 'fake-error');
    }
    return pathsListJson ?? {'count': 0, 'paths': []};
  }

  @override
  Future<Map<String, dynamic>> getPathDetail(
    String pathId, {
    bool includeLessons = false,
  }) async {
    // Flat shape — path fields at root + lessons array (commit 7d056fc).
    return pathDetailJson ?? {..._pathJson(id: pathId), 'lessons': []};
  }

  @override
  Future<Map<String, dynamic>> getLesson(String lessonId) async {
    return lessonJson ?? _lessonJson(id: lessonId, order: 1);
  }

  @override
  Future<Map<String, dynamic>> getLessonAssets(String lessonId, {String? lang}) async {
    if (lessonAssetsJson != null) return lessonAssetsJson!;
    throw const TgApiError(404, 'not-found');
  }
}

// ── JSON fixtures (mirror backend response shapes exactly) ────────────────

Map<String, dynamic> _pathJson({
  required String id,
  String title = 'تأسيس الآداب الإسلامية والضمير الأخلاقي (4-6 سنوات)',
}) {
  return {
    'id': id,
    'title': title,
    'age_group': '4-6',
    'domain': 'islamic_parenting',
    'description': 'رحلة تربوية لمدة 14 يوماً لتأسيس القيم الأخلاقية.',
    'lesson_ids': [
      'lesson_4-6_islamic_parenting_adab_01',
      'lesson_4-6_islamic_parenting_adab_02',
      'lesson_4-6_islamic_parenting_adab_03',
    ],
    'estimated_days': 14,
    'pedagogical_framework': 'prophetic_7_7_7',
    'primary_reference': {
      'type': 'كتاب_تربوي',
      'info': 'ابن القيم الجوزية، تحفة المودود',
    },
    'prerequisites': [],
    'is_published': true,
    'version': '1.0.0',
  };
}

Map<String, dynamic> _lessonJson({
  required String id,
  required int order,
  String title = 'الرفق: قيمة تربوية قبل أسلوب',
  String summary = 'في مرحلة ما قبل العمليات يبدأ الطفل بتمييز الصوت الحنون.',
  String tryThis = 'هذا الأسبوع: اختر وقتاً يومياً واحداً تتحدث فيه مع طفلك بصوت هادئ.',
  List<String>? reflectionPrompts,
  bool withWarning = false,
}) {
  return {
    'id': id,
    'path_id': 'path_4-6_islamic_parenting_adab',
    'title': title,
    'age_group': '4-6',
    'domain': 'islamic_parenting',
    'unit_ids': ['0bd76d3c-548a-46ed-b17b-78874741662a'],
    'summary': summary,
    'try_this': tryThis,
    'order': order,
    'estimated_minutes': 5,
    'reflection_prompts': reflectionPrompts ?? [],
    'warning_flags': withWarning ? ['needs_professional_followup'] : [],
    'is_published': true,
    'version': '1.0.0',
  };
}

// ── Fake TgClient ─────────────────────────────────────────────────────────
