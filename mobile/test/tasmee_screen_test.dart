// «تسميع مع الوالد»: tap a word, say how the child slipped, finish, save —
// and the surah list shows what is open for review.
import 'package:almorabbi/features/journey/data/tasmee_store.dart';
import 'package:almorabbi/features/journey/screens/quran_memorization_screen.dart';
import 'package:almorabbi/features/journey/screens/tasmee_screen.dart';
import 'package:almorabbi/features/onboarding/providers/onboarding_providers.dart';
import 'package:almorabbi/features/quran/providers/quran_providers.dart';
import 'package:almorabbi/l10n/app_localizations.dart';
import 'package:almorabbi/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';

// Al-Ikhlas as assets/data/quran.json has it.
const _ikhlas = [
  {'chapter': 112, 'verse': 1, 'text': 'قُلۡ هُوَ ٱللَّهُ أَحَدٌ'},
  {'chapter': 112, 'verse': 2, 'text': 'ٱللَّهُ ٱلصَّمَدُ'},
  {'chapter': 112, 'verse': 3, 'text': 'لَمۡ يَلِدۡ وَلَمۡ يُولَدۡ'},
  {'chapter': 112, 'verse': 4, 'text': 'وَلَمۡ يَكُن لَّهُۥ كُفُوًا أَحَدُۢ'},
];

Future<(ProviderContainer, SharedPreferences)> _pump(
  WidgetTester tester,
  Widget home, {
  Map<String, Object> prefs = const {},
}) async {
  await tester.runAsync(() async {
    GoogleFonts.amiriQuran();
    await GoogleFonts.pendingFonts();
  });
  SharedPreferences.setMockInitialValues(prefs);
  final p = await SharedPreferences.getInstance();
  final container = ProviderContainer(
    overrides: [
      sharedPreferencesProvider.overrideWith((_) async => p),
      quranDataProvider.overrideWith((_) async => {'112': _ikhlas}),
    ],
  );
  addTearDown(container.dispose);
  await container.read(sharedPreferencesProvider.future);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        locale: const Locale('ar'),
        theme: AppTheme.light(),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: home,
      ),
    ),
  );
  await tester.pumpAndSettle();
  return (container, p);
}

void main() {
  testWidgets(
    'mark a word, finish, save: the session is stored with its mark',
    (tester) async {
      final (_, prefs) = await _pump(
        tester,
        const TasmeeScreen(
          childId: 7,
          childName: 'سارة',
          surah: 112,
          from: 1,
          to: 4,
        ),
      );
      expect(find.text('تسميع سورة الإخلاص'), findsOneWidget);
      expect(find.text('ٱلصَّمَدُ'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('w-2-1')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('slip-omit')));
      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.remove_circle_outline), findsOneWidget);

      // Marked again: the same word can be cleared.
      await tester.tap(find.byKey(const ValueKey('w-3-0')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('slip-hesitate')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('w-3-0')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('slip-clear')));
      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.more_horiz), findsNothing);

      await tester.tap(find.byKey(const ValueKey('tasmee-finish')));
      await tester.pumpAndSettle();
      expect(
        find.text('نسيها: 1 · زاد: 0 · أبدلها: 0 · تردّد: 0'),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const ValueKey('tasmee-save')));
      await tester.pumpAndSettle();

      final saved = TasmeeStore(prefs).loadForChild(7)[112]!.single;
      expect((saved.from, saved.to), (1, 4));
      expect(saved.marks.single.ayah, 2);
      expect(saved.marks.single.word, 1);
      expect(saved.marks.single.type, SlipType.omit);
    },
  );

  testWidgets('a clean recitation says so, and saves with no marks', (
    tester,
  ) async {
    final (_, prefs) = await _pump(
      tester,
      const TasmeeScreen(
        childId: 7,
        childName: 'سارة',
        surah: 112,
        from: 1,
        to: 4,
      ),
    );
    await tester.tap(find.byKey(const ValueKey('tasmee-finish')));
    await tester.pumpAndSettle();
    expect(find.text('تسميع بلا تعثّر.'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('tasmee-save')));
    await tester.pumpAndSettle();
    expect(TasmeeStore(prefs).loadForChild(7)[112]!.single.marks, isEmpty);
  });

  testWidgets('the surah list shows what is open, and the review day', (
    tester,
  ) async {
    final yesterday = DateTime.now().subtract(const Duration(days: 1));
    SharedPreferences.setMockInitialValues({});
    final seed = TasmeeStore(await SharedPreferences.getInstance());
    await seed.add(
      7,
      112,
      TasmeeSession(
        at: yesterday,
        from: 1,
        to: 4,
        marks: const [
          TasmeeMark(ayah: 2, word: 1, type: SlipType.omit),
          TasmeeMark(ayah: 4, word: 0, type: SlipType.swap),
        ],
      ),
    );
    final stored = (await SharedPreferences.getInstance()).getString(
      TasmeeStore.key,
    )!;
    await _pump(
      tester,
      const QuranMemorizationScreen(childId: 7, childName: 'سارة'),
      prefs: {TasmeeStore.key: stored},
    );
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('tasmee-112')),
      400,
    );
    expect(find.text('موضعان للمراجعة · راجعوها اليوم'), findsOneWidget);
  });
}
