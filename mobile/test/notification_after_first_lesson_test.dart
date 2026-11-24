/// The notification permission ask moves from launch (main.dart) to after
/// the FIRST completed lesson (NOOR_WAL_QANADIL_PLAN, Phase 1).
///
/// Why: asking before the parent has seen anything of value is the classic
/// cold-permission — one deny at the door and the daily reminders never
/// exist. After a completed lesson the parent has a reason to say yes.
///
/// Pins:
///   1. [NotificationPermissionGate.maybeAsk] asks exactly once per install
///      (SharedPreferences flag), and never throws into the lesson flow.
///   2. The ask is armed from [Analytics.lessonCompleted] — the event the
///      lesson flow already emits — so lesson_screen.dart stays untouched.
///   3. main.dart no longer asks at launch (source pin, same shape as
///      notification_permission_test.dart).
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:almorabbi/core/notification_permission_gate.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  tearDown(() {
    NotificationPermissionGate.ask = null;
  });

  group('NotificationPermissionGate', () {
    test('asks exactly once per install', () async {
      var asks = 0;
      NotificationPermissionGate.ask = () async => asks++;

      await NotificationPermissionGate.maybeAsk();
      await NotificationPermissionGate.maybeAsk();
      await NotificationPermissionGate.maybeAsk();

      expect(asks, 1,
          reason: 'one moment, one ask — never a nag after a deny');
    });

    test('a throwing ask never breaks the lesson flow', () async {
      NotificationPermissionGate.ask = () async => throw Exception('no Activity');
      // Must simply complete.
      await NotificationPermissionGate.maybeAsk();

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool(NotificationPermissionGate.prefKey), isTrue);
    });

    test('skips installs that were already asked', () async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(NotificationPermissionGate.prefKey, true);
      var asks = 0;
      NotificationPermissionGate.ask = () async => asks++;

      await NotificationPermissionGate.maybeAsk();
      expect(asks, 0);
    });
  });

  group('wiring (source pins)', () {
    test('the gate hangs off every first real parenting value moment', () {
      final source = File('lib/core/analytics.dart').readAsStringSync();
      for (final fn in [
        'static Future<void> lessonCompleted',
        'static Future<void> chatSent',
        'static Future<void> habitCheckIn',
        'static Future<void> storyGenerated',
        'static Future<void> tasmeeFinished',
        'static Future<void> gameCompleted',
        'static Future<void> storyEvent',
        'static Future<void> familyRoundCompleted',
      ]) {
        final start = source.indexOf(fn);
        expect(start, greaterThanOrEqualTo(0), reason: 'missing $fn');
        final snippet = source.substring(start, (start + 450).clamp(0, source.length));
        expect(snippet, contains('NotificationPermissionGate.maybeAsk'),
            reason: '$fn must arm the one-shot permission gate');
      }
      // Passive screen opens must NEVER trigger a permission prompt.
      final opened = source.substring(
        source.indexOf('static Future<void> lessonOpened'),
        source.indexOf('static Future<void> lessonCompleted'),
      );
      expect(opened, isNot(contains('NotificationPermissionGate.maybeAsk')));
    });

    test('main.dart never asks for permission at cold launch and syncs token on ask', () {
      final source = File('lib/main.dart').readAsStringSync();
      expect(source, isNot(contains('The one place the app asks to notify')),
          reason: 'the launch-time ask is gone; the ask now happens once, '
              'after the first real engagement');
      expect(source, isNot(contains('askPermission: true')),
          reason: 'launch token registration must be silent — never pop a '
              'cold Android 13+ dialog before onboarding');
      expect(source, contains('NotificationPermissionGate.ask'),
          reason: 'the platform ask itself is wired in the composition root');
      final gateBlock = source.substring(
        source.indexOf('NotificationPermissionGate.ask'),
        source.indexOf('NotificationPermissionGate.ask') + 380,
      );
      expect(gateBlock, contains('registerToken()'),
          reason: 'asking permission must also recover offline/missed token uploads');
    });
  });
}
