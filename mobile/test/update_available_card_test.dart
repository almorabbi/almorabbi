// «نسخة جديدة متاحة»: optional, once per newer build, never on the newest.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:almorabbi/features/onboarding/providers/onboarding_providers.dart';
import 'package:almorabbi/features/whats_new/widgets/update_available_card.dart';
import 'package:almorabbi/l10n/app_localizations.dart';
import 'package:almorabbi/main.dart' show appConfigProvider, packageInfoProvider;

Future<SharedPreferences> _pump(WidgetTester tester,
    {required String build, required Object? latest,
    Map<String, Object> stored = const {}}) async {
  SharedPreferences.setMockInitialValues(stored);
  final prefs = await SharedPreferences.getInstance();
  await tester.pumpWidget(ProviderScope(
    // A fresh scope per pump: the overrides differ between calls.
    key: UniqueKey(),
    overrides: [
      sharedPreferencesProvider.overrideWith((ref) async => prefs),
      packageInfoProvider.overrideWith((ref) async => PackageInfo(
          appName: 'a', packageName: 'p', version: '1.0.75', buildNumber: build)),
      appConfigProvider.overrideWith((ref) async => <String, dynamic>{
            'minimum_build_number': 119,
            'latest_build_number': latest,
          }),
    ],
    child: MaterialApp(
      locale: const Locale('ar'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: const Scaffold(body: UpdateAvailableCard()),
    ),
  ));
  await tester.pumpAndSettle();
  return prefs;
}

void main() {
  testWidgets('an older build is offered the update, and can close it',
      (tester) async {
    final prefs = await _pump(tester, build: '120', latest: 121);
    expect(find.text('نسخة جديدة من المربّي متاحة'), findsOneWidget);
    await tester.tap(find.byIcon(Icons.close_rounded));
    await tester.pumpAndSettle();
    expect(find.text('نسخة جديدة من المربّي متاحة'), findsNothing);
    expect(prefs.getInt(kUpdateDismissedBuildKey), 121);
  });

  testWidgets('the newest build, and a server that says nothing, show nothing',
      (tester) async {
    await _pump(tester, build: '121', latest: 121);
    expect(find.text('نسخة جديدة من المربّي متاحة'), findsNothing);
    await _pump(tester, build: '120', latest: 0);
    expect(find.text('نسخة جديدة من المربّي متاحة'), findsNothing);
    await _pump(tester, build: '120', latest: null);
    expect(find.text('نسخة جديدة من المربّي متاحة'), findsNothing);
  });

  testWidgets('closed for 121, asked again for 122', (tester) async {
    await _pump(tester,
        build: '120', latest: 121, stored: {kUpdateDismissedBuildKey: 121});
    expect(find.text('نسخة جديدة من المربّي متاحة'), findsNothing);
    await _pump(tester,
        build: '120', latest: 122, stored: {kUpdateDismissedBuildKey: 121});
    expect(find.text('نسخة جديدة من المربّي متاحة'), findsOneWidget);
  });
}
