/// Client experiment arm resolution for `child_home_v2` (M2).
///
/// Maps `/api/app-config`'s `child_home_v2` field (`'v2' | 'ab' | 'classic'`)
/// to [ChildHomeArm]:
/// - `'v2'` -> [ChildHomeArm.weekly]
/// - `'ab'` -> sticky 50/50 split via FNV-1a32(`deviceId:child_home_v2`),
///   cached in SharedPreferences under [kChildHomeArmKey]
/// - `'classic'` or omitted (`null`) -> [ChildHomeArm.classic]
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../main.dart' show appConfigProvider;
import '../../onboarding/providers/onboarding_providers.dart'
    show sharedPreferencesProvider;
import '../../../state/chat_notifier.dart' show tgClientProvider;
import '../../stories/experiment/story_experiment.dart' show fnv1a32;

/// Home surface variant shown to the parent.
enum ChildHomeArm {
  classic,
  weekly,
}

/// SharedPreferences key caching the sticky `'ab'` assignment.
const kChildHomeArmKey = 'exp.child_home_v2.arm';

/// SharedPreferences key recording when [childId] finished onboarding so week 1
/// can stay expanded across app restarts during the first 7 days.
String firstWeekOnboardedKey(int childId) => 'child.first_week.v1.$childId';

/// Resolves [ChildHomeArm] deterministically and caches `'ab'` assignments in
/// [prefs] under [kChildHomeArmKey].
Future<ChildHomeArm> resolveChildHomeArm({
  required SharedPreferences prefs,
  required String? serverMode,
  required Future<String> Function() getDeviceId,
}) async {
  if (serverMode == 'v2') {
    return ChildHomeArm.weekly;
  }
  if (serverMode != 'ab') {
    return ChildHomeArm.classic;
  }
  final cached = prefs.getString(kChildHomeArmKey);
  if (cached == ChildHomeArm.weekly.name) {
    return ChildHomeArm.weekly;
  }
  if (cached == ChildHomeArm.classic.name) {
    return ChildHomeArm.classic;
  }
  final deviceId = await getDeviceId();
  if (deviceId.isEmpty) {
    return ChildHomeArm.classic;
  }
  final bucket = fnv1a32('$deviceId:child_home_v2') & 1;
  final arm = bucket == 0 ? ChildHomeArm.weekly : ChildHomeArm.classic;
  await prefs.setString(kChildHomeArmKey, arm.name);
  return arm;
}

/// Device identifier used for experiment bucketing on the Home tab.
final childHomeDeviceIdProvider = FutureProvider<String>((ref) async {
  try {
    return await ref.read(tgClientProvider).experimentDeviceId();
  } catch (_) {
    return '';
  }
});

/// Set to the newly created child's id right as onboarding completes so their
/// weekly plan opens expanded on their very first Home visit.
final justOnboardedPlanChildProvider = StateProvider<int?>((ref) => null);

/// Resolves the active Home variant from `/api/app-config`'s `child_home_v2`.
final childHomeArmProvider = FutureProvider<ChildHomeArm>((ref) async {
  Map<String, dynamic> cfg;
  try {
    cfg = await ref.watch(appConfigProvider.future);
  } catch (_) {
    cfg = const <String, dynamic>{};
  }
  final rawMode = cfg['child_home_v2']?.toString();
  if (rawMode == 'v2') {
    return ChildHomeArm.weekly;
  }
  if (rawMode != 'ab') {
    return ChildHomeArm.classic;
  }
  final prefs = await ref.watch(sharedPreferencesProvider.future);
  return resolveChildHomeArm(
    prefs: prefs,
    serverMode: rawMode,
    getDeviceId: () => ref.read(childHomeDeviceIdProvider.future),
  );
});
