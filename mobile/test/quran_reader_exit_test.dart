// Leaving the Quran reader saves where the parent stopped, and throws
// nothing. Until 2026-10-15 every exit threw «Cannot use "ref" after the
// widget was disposed» from dispose() — the CI rehearsal's logcat gate caught
// it after its sound check closed the reader — and the final save never ran.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio/just_audio.dart' show PlayerState, ProcessingState;
import 'package:shared_preferences/shared_preferences.dart';

import 'package:almorabbi/features/quran/providers/quran_providers.dart';
import 'package:almorabbi/features/quran/screens/surah_reading_screen.dart';
import 'package:almorabbi/l10n/app_localizations.dart';
import 'package:almorabbi/theme/bundled_fonts.dart';

final _quran = <String, List<dynamic>>{
  '1': [
    for (var v = 1; v <= 7; v++) {'chapter': 1, 'verse': v, 'text': 'آية $v'},
  ],
  '2': [
    for (var v = 1; v <= 7; v++) {'chapter': 2, 'verse': v, 'text': 'آية $v'},
  ],
};

class _FakeRecitationPlayer implements RecitationPlayer {
  final StreamController<PlayerState> _stateController =
      StreamController<PlayerState>.broadcast();
  bool _playing = false;
  ProcessingState _processingState = ProcessingState.idle;

  final List<String> loadedUrls = <String>[];
  final List<Completer<void>> loadCompleters = <Completer<void>>[];
  int playCalls = 0;
  Object? playError;

  @override
  Stream<PlayerState> get playerStateStream => _stateController.stream;

  @override
  bool get playing => _playing;

  @override
  ProcessingState get processingState => _processingState;

  void _emit() {
    if (!_stateController.isClosed) {
      _stateController.add(PlayerState(_playing, _processingState));
    }
  }

  @override
  Future<void> setUrl(String url) async {
    loadedUrls.add(url);
    final completer = Completer<void>();
    loadCompleters.add(completer);
    _processingState = ProcessingState.loading;
    _emit();
    try {
      await completer.future;
      _processingState = ProcessingState.ready;
      _emit();
    } catch (_) {
      _playing = false;
      _processingState = ProcessingState.idle;
      _emit();
      rethrow;
    }
  }

  @override
  Future<void> play() async {
    playCalls++;
    if (playError != null) {
      final err = playError!;
      playError = null;
      throw err;
    }
    _playing = true;
    _emit();
  }

  @override
  Future<void> pause() async {
    _playing = false;
    _emit();
  }

  @override
  Future<void> stop() async {
    _playing = false;
    _processingState = ProcessingState.idle;
    _emit();
  }

  @override
  Future<void> dispose() async {
    await _stateController.close();
  }
}

void main() {
  setUpAll(configureBundledFonts);

  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('back from the reader: no error, and the place is saved',
      (tester) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final navigator = GlobalKey<NavigatorState>();
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        navigatorKey: navigator,
        locale: const Locale('ar'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const Scaffold(body: SizedBox()),
      ),
    ));
    navigator.currentState!.push(MaterialPageRoute<void>(
      builder: (_) => SurahReadingScreen(
        chapterNumber: 2,
        initialVerse: 3,
        quranData: _quran,
        debugPlayer: _FakeRecitationPlayer(),
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.byType(SurahReadingScreen), findsOneWidget);

    navigator.currentState!.pop();
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.byType(SurahReadingScreen), findsNothing);
    final saved = container.read(lastReadProvider).valueOrNull;
    expect((saved?.chapter, saved?.verse), (2, 3));
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getInt('quran_last_read_chapter'), 2);
    expect(prefs.getInt('quran_last_read_verse'), 3);
  });

  testWidgets('pausing during in-flight ayah load keeps pill on listen',
      (tester) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final player = _FakeRecitationPlayer();
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        locale: const Locale('ar'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: SurahReadingScreen(
          chapterNumber: 1,
          initialVerse: 1,
          quranData: _quran,
          debugPlayer: player,
        ),
      ),
    ));
    await tester.pumpAndSettle();

    final pill = find.byKey(const Key('quran_listen_pill'));
    expect(find.descendant(of: pill, matching: find.text('استماع')),
        findsOneWidget);

    // Tap to start loading ayah 1 -> pill switches to «إيقاف».
    await tester.tap(pill);
    await tester.pump();
    expect(
        find.descendant(of: pill, matching: find.text('إيقاف')), findsOneWidget);

    // Tap again while setUrl is still awaiting -> cancels intent immediately
    // and reverts to «استماع».
    await tester.tap(pill);
    await tester.pump();
    expect(find.descendant(of: pill, matching: find.text('استماع')),
        findsOneWidget);

    // Completing the in-flight load afterward must not re-arm playback.
    player.loadCompleters.single.complete();
    await tester.pumpAndSettle();
    expect(find.descendant(of: pill, matching: find.text('استماع')),
        findsOneWidget);
    expect(
        find.descendant(of: pill, matching: find.text('إيقاف')), findsNothing);
    expect(player.playCalls, 0);

    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: const SizedBox(),
    ));
    await tester.pumpAndSettle();
  });

  testWidgets(
      're-tapping listen after cancelling an in-flight load starts a fresh load',
      (tester) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final player = _FakeRecitationPlayer();
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        locale: const Locale('ar'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: SurahReadingScreen(
          chapterNumber: 1,
          initialVerse: 1,
          quranData: _quran,
          debugPlayer: player,
        ),
      ),
    ));
    await tester.pumpAndSettle();

    final pill = find.byKey(const Key('quran_listen_pill'));
    await tester.tap(pill);
    await tester.pump();
    await tester.tap(pill);
    await tester.pump();
    await tester.tap(pill);
    await tester.pump();

    expect(player.loadedUrls.length, 2);
    expect(player.loadedUrls[0], player.loadedUrls[1]);
    expect(
        find.descendant(of: pill, matching: find.text('إيقاف')), findsOneWidget);

    for (final c in player.loadCompleters) {
      if (!c.isCompleted) c.complete();
    }
    await tester.pumpAndSettle();
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: const SizedBox(),
    ));
    await tester.pumpAndSettle();
  });

  testWidgets(
      'failing the reloaded ayah resets pill to listen and shows quranPlayError',
      (tester) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final player = _FakeRecitationPlayer();
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        locale: const Locale('ar'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: SurahReadingScreen(
          chapterNumber: 1,
          initialVerse: 1,
          quranData: _quran,
          debugPlayer: player,
        ),
      ),
    ));
    await tester.pumpAndSettle();

    final pill = find.byKey(const Key('quran_listen_pill'));
    await tester.tap(pill); // start load #1
    await tester.pump();
    await tester.tap(pill); // pause/cancel while loading
    await tester.pump();
    await tester.tap(pill); // re-tap while load #1 may still finish
    await tester.pump();

    expect(player.loadCompleters.length, 2);
    player.loadCompleters[0].completeError(Exception('cancelled timeout'));
    player.loadCompleters[1].completeError(Exception('network failure'));
    await tester.pump();

    expect(find.descendant(of: pill, matching: find.text('استماع')),
        findsOneWidget);
    expect(find.text('تعذّر تشغيل التلاوة. تأكد من اتصالك بالإنترنت.'),
        findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: const SizedBox(),
    ));
    await tester.pumpAndSettle();
  });

  testWidgets('failing direct resume resets pill to listen and shows error',
      (tester) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final player = _FakeRecitationPlayer();
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        locale: const Locale('ar'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: SurahReadingScreen(
          chapterNumber: 1,
          initialVerse: 1,
          quranData: _quran,
          debugPlayer: player,
        ),
      ),
    ));
    await tester.pumpAndSettle();

    final pill = find.byKey(const Key('quran_listen_pill'));
    await tester.tap(pill);
    await tester.pump();
    player.loadCompleters.single.complete();
    await tester.pump();
    expect(
        find.descendant(of: pill, matching: find.text('إيقاف')), findsOneWidget);

    await tester.tap(pill); // pause
    await tester.pump();
    expect(find.descendant(of: pill, matching: find.text('استماع')),
        findsOneWidget);

    player.playError = Exception('audio backend error');
    await tester.tap(pill); // direct resume fails
    await tester.pump();

    expect(find.descendant(of: pill, matching: find.text('استماع')),
        findsOneWidget);
    expect(find.text('تعذّر تشغيل التلاوة. تأكد من اتصالك بالإنترنت.'),
        findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: const SizedBox(),
    ));
    await tester.pumpAndSettle();
  });

  testWidgets('switching reciter while paused stays silent until listen',
      (tester) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final player = _FakeRecitationPlayer();
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        locale: const Locale('ar'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: SurahReadingScreen(
          chapterNumber: 1,
          initialVerse: 1,
          quranData: _quran,
          debugPlayer: player,
        ),
      ),
    ));
    await tester.pumpAndSettle();

    final pill = find.byKey(const Key('quran_listen_pill'));
    await tester.tap(pill);
    await tester.pump();
    player.loadCompleters[0].complete();
    await tester.pump();
    expect(player.loadedUrls.single, contains('Husary_128kbps/001001.mp3'));
    expect(player.playCalls, 1);

    // Pause recitation before choosing another reciter.
    await tester.tap(pill);
    await tester.pump();
    expect(find.descendant(of: pill, matching: find.text('استماع')),
        findsOneWidget);

    await tester.tap(find.byKey(const Key('quran_reciter_button')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('محمد صديق المنشاوي'));
    await tester.pumpAndSettle();

    expect(player.loadedUrls.length, 1);
    expect(player.playCalls, 1);
    expect(find.descendant(of: pill, matching: find.text('استماع')),
        findsOneWidget);

    // Next Listen tap loads the newly selected reciter instead of resuming old audio.
    await tester.tap(pill);
    await tester.pump();
    expect(player.loadedUrls.length, 2);
    expect(player.loadedUrls.last, contains('Minshawy_Murattal_128kbps/001001.mp3'));
    expect(
        find.descendant(of: pill, matching: find.text('إيقاف')), findsOneWidget);

    for (final c in player.loadCompleters) {
      if (!c.isCompleted) c.complete();
    }
    await tester.pumpAndSettle();
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: const SizedBox(),
    ));
    await tester.pumpAndSettle();
  });
}
