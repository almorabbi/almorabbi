import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:almorabbi/features/program/data/review_prompt.dart';
import 'package:almorabbi/l10n/app_localizations.dart';

void main() {
  late DateTime fakeNow;

  Widget testHarness({
    required void Function(BuildContext) onTrigger,
    Locale locale = const Locale('ar'),
  }) {
    return MaterialApp(
      locale: locale,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Builder(
        builder: (context) => Scaffold(
          body: ElevatedButton(
            onPressed: () => onTrigger(context),
            child: const Text('trigger'),
          ),
        ),
      ),
    );
  }

  setUp(() {
    ReviewPrompt.resetTestOverrides();
    fakeNow = DateTime(2027, 2, 1, 10, 0);
    ReviewPrompt.nowProvider = () => fakeNow;
    SharedPreferences.setMockInitialValues({});
  });

  tearDown(ReviewPrompt.resetTestOverrides);

  group('ReviewPrompt v2 gating & fallback', () {
    testWidgets('shows on 2nd positive moment and not on 1st', (tester) async {
      await tester.pumpWidget(
        testHarness(
          onTrigger: (ctx) => ReviewPrompt.maybeAsk(ctx, source: 'lesson'),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('trigger'));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);

      await tester.tap(find.text('trigger'));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsOneWidget);
      expect(find.text('هل أعجبك «المربّي»؟ 🌟'), findsOneWidget);
      expect(find.text('لاحقًا'), findsOneWidget);
      expect(find.text('قيّم الآن'), findsOneWidget);
    });

    testWidgets(
      'Later snoozes across 14d cooldown AND 3 actions, then stops after 3 shows',
      (tester) async {
        await tester.pumpWidget(
          testHarness(
            onTrigger: (ctx) => ReviewPrompt.maybeAsk(ctx, source: 'story'),
          ),
        );
        await tester.pumpAndSettle();

        // Trigger show #1 on 2nd moment -> tap Later.
        await tester.tap(find.text('trigger'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('trigger'));
        await tester.pumpAndSettle();
        expect(find.byType(AlertDialog), findsOneWidget);
        await tester.tap(find.text('لاحقًا'));
        await tester.pumpAndSettle();

        // 3 new moments WITHOUT 14 days elapsed -> suppressed.
        fakeNow = fakeNow.add(const Duration(days: 5));
        for (var i = 0; i < 4; i++) {
          await tester.tap(find.text('trigger'));
          await tester.pumpAndSettle();
          expect(find.byType(AlertDialog), findsNothing);
        }

        // Advance >= 14 days total -> next moment triggers show #2.
        fakeNow = fakeNow.add(const Duration(days: 10));
        await tester.tap(find.text('trigger'));
        await tester.pumpAndSettle();
        expect(find.byType(AlertDialog), findsOneWidget);
        await tester.tap(find.text('لاحقًا'));
        await tester.pumpAndSettle();

        // Advance >= 14 days and 3 actions -> show #3 (final prompt).
        fakeNow = fakeNow.add(const Duration(days: 15));
        await tester.tap(find.text('trigger'));
        await tester.pumpAndSettle();
        expect(find.byType(AlertDialog), findsNothing);
        await tester.tap(find.text('trigger'));
        await tester.pumpAndSettle();
        expect(find.byType(AlertDialog), findsNothing);
        await tester.tap(find.text('trigger'));
        await tester.pumpAndSettle();
        expect(find.byType(AlertDialog), findsOneWidget);
        await tester.tap(find.text('لاحقًا'));
        await tester.pumpAndSettle();

        // After 3 shows, never asks again even after 60 days and 5 moments.
        fakeNow = fakeNow.add(const Duration(days: 60));
        for (var i = 0; i < 5; i++) {
          await tester.tap(find.text('trigger'));
          await tester.pumpAndSettle();
          expect(find.byType(AlertDialog), findsNothing);
        }
      },
    );

    testWidgets(
      'Rate now opens Store Listing when Play requestReview returns in <500ms (silent quota suppression)',
      (tester) async {
        var reviewCalls = 0;
        var storeCalls = 0;
        ReviewPrompt.isAvailableOverride = () async => true;
        ReviewPrompt.requestReviewOverride = () async {
          reviewCalls++;
          fakeNow = fakeNow.add(const Duration(milliseconds: 40));
        };
        ReviewPrompt.openStoreListingOverride = () async {
          storeCalls++;
        };

        await tester.pumpWidget(
          testHarness(
            onTrigger: (ctx) => ReviewPrompt.maybeAsk(ctx, source: 'lesson'),
          ),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.text('trigger'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('trigger'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('قيّم الآن'));
        await tester.pumpAndSettle();

        expect(reviewCalls, 1);
        expect(storeCalls, 1);

        // Once rated, permanently disabled.
        fakeNow = fakeNow.add(const Duration(days: 30));
        for (var i = 0; i < 5; i++) {
          await tester.tap(find.text('trigger'));
          await tester.pumpAndSettle();
          expect(find.byType(AlertDialog), findsNothing);
        }
      },
    );

    testWidgets(
      'Rate now does NOT open Store Listing when native Play sheet stayed open >=500ms',
      (tester) async {
        var reviewCalls = 0;
        var storeCalls = 0;
        ReviewPrompt.isAvailableOverride = () async => true;
        ReviewPrompt.requestReviewOverride = () async {
          reviewCalls++;
          fakeNow = fakeNow.add(const Duration(milliseconds: 900));
        };
        ReviewPrompt.openStoreListingOverride = () async {
          storeCalls++;
        };

        await tester.pumpWidget(
          testHarness(
            onTrigger: (ctx) => ReviewPrompt.maybeAsk(ctx, source: 'lesson'),
          ),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.text('trigger'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('trigger'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('قيّم الآن'));
        await tester.pumpAndSettle();

        expect(reviewCalls, 1);
        expect(storeCalls, 0);
      },
    );

    testWidgets(
      'Rate now opens Store Listing if in_app_review is unavailable or throws',
      (tester) async {
        var storeCalls = 0;
        ReviewPrompt.isAvailableOverride = () async => false;
        ReviewPrompt.openStoreListingOverride = () async {
          storeCalls++;
        };

        await tester.pumpWidget(
          testHarness(
            onTrigger: (ctx) => ReviewPrompt.maybeAsk(ctx, source: 'quran'),
          ),
        );
        await tester.pumpAndSettle();

        await ReviewPrompt.recordMoment();
        await tester.tap(find.text('trigger'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('قيّم الآن'));
        await tester.pumpAndSettle();

        expect(storeCalls, 1);
      },
    );

    testWidgets(
      'Legacy <=2.0.0 review.asked=true migrates cleanly for a 2nd chance',
      (tester) async {
        SharedPreferences.setMockInitialValues({
          'review.asked': true,
          'review.positive_actions': 2,
        });

        await tester.pumpWidget(
          testHarness(
            onTrigger: (ctx) => ReviewPrompt.maybeAsk(ctx, source: 'legacy'),
          ),
        );
        await tester.pumpAndSettle();

        // Action #3 -> suppressed (needs +2 actions after migration).
        await tester.tap(find.text('trigger'));
        await tester.pumpAndSettle();
        expect(find.byType(AlertDialog), findsNothing);

        // Action #4 -> second chance appears cleanly.
        await tester.tap(find.text('trigger'));
        await tester.pumpAndSettle();
        expect(find.byType(AlertDialog), findsOneWidget);
      },
    );
  });
}
