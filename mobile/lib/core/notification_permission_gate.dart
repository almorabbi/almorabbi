/// One-shot notification permission ask, moved off the launch path to the
/// first real moment a parent experiences value (NOOR_WAL_QANADIL_PLAN, Phase 1
/// + 2.0.4 retention expansion): finishing a lesson, asking Noor a question,
/// logging a habit, finishing/creating a bedtime story, completing Quran
/// tasmee, or finishing a family puzzle/game round.
///
/// Asking at launch was a cold permission: nothing had been seen, nothing
/// was at stake, and one deny at the door meant the daily reminders never
/// existed. Waiting ONLY for `lessonCompleted` missed the ~75% of families
/// whose first value came from reading, stories, Noor chat, or Quran.
///
/// Wiring: [Analytics] value events call [maybeAsk], keeping UI screens free
/// of platform permission imports. The platform ask itself is injected in
/// `main()` (the composition root), which also triggers a silent push-token
/// upload to recover devices whose cold-launch registration was offline.
///
/// The flag is set BEFORE asking: one moment, one ask — a device that
/// denies is never nagged again (Android 13+ would silently drop the
/// request anyway). [prefKey] keeps its original key name so installs already
/// asked on <= 2.0.3 are never re-prompted after upgrading.
library;

import 'package:shared_preferences/shared_preferences.dart';

abstract final class NotificationPermissionGate {
  static const prefKey = 'tg.notifications.asked_after_first_lesson';

  /// The real platform ask, set once in `main()` (the composition root):
  /// Firebase's request first, the plugin's as the no-Play-Services
  /// fallback, followed by a silent push-token sync. Null (and therefore a
  /// no-op) in tests, which inject their own.
  static Future<void> Function()? ask;

  /// Called on first real parenting engagement; does its work exactly once per
  /// install. Never throws — a permission ask must never break any user flow.
  static Future<void> maybeAsk() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (prefs.getBool(prefKey) == true) return;
      await prefs.setBool(prefKey, true);
      await ask?.call();
    } catch (_) {
      // Best-effort by design.
    }
  }
}
