// The age chips on «Things to do without a screen» were a const Arabic map,
// so an English parent saw «أقل من سنتين» above English activities.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:almorabbi/features/offscreen/offscreen_activities_screen.dart';
import 'package:almorabbi/l10n/app_localizations.dart';

Future<void> _pump(WidgetTester tester, Locale locale) async {
  await tester.pumpWidget(ProviderScope(
    overrides: [
      offscreenActivitiesProvider.overrideWith((ref) async => <String, dynamic>{
            'under-2': {'activities': <dynamic>[]},
          }),
    ],
    child: MaterialApp(
      locale: locale,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: const OffscreenActivitiesScreen(),
    ),
  ));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('English: the age chips are English', (tester) async {
    await _pump(tester, const Locale('en'));
    expect(find.text('Under 2'), findsOneWidget);
    expect(find.text('أقل من سنتين'), findsNothing);
  });

  testWidgets('Arabic: the age chips are Arabic', (tester) async {
    await _pump(tester, const Locale('ar'));
    expect(find.text('أقل من سنتين'), findsOneWidget);
  });
}
