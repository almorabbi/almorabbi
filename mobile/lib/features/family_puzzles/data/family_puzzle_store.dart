/// Per-child local persistence & daily round scheduling for «فوازير نور العائلية».
library;

import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'family_puzzle_models.dart';

const String kFamilyPuzzlesStoragePrefix = 'tg.family_puzzles.v1.';

class FamilyPuzzleProgress {
  final Set<String> solvedIds;
  final String? lastRoundDate;
  final int roundsCompleted;

  const FamilyPuzzleProgress({
    this.solvedIds = const {},
    this.lastRoundDate,
    this.roundsCompleted = 0,
  });

  bool isRoundDoneOn(DateTime now) => lastRoundDate == familyPuzzleDayKey(now);

  Map<String, dynamic> toJson() => {
        'solved_ids': solvedIds.toList(),
        'last_round_date': lastRoundDate,
        'rounds_completed': roundsCompleted,
      };

  factory FamilyPuzzleProgress.fromJson(Map<String, dynamic> j) =>
      FamilyPuzzleProgress(
        solvedIds: (j['solved_ids'] as List? ?? const [])
            .whereType<String>()
            .toSet(),
        lastRoundDate: j['last_round_date'] as String?,
        roundsCompleted: (j['rounds_completed'] as int?) ?? 0,
      );
}

String familyPuzzleDayKey(DateTime now) {
  final m = now.month.toString().padLeft(2, '0');
  final d = now.day.toString().padLeft(2, '0');
  return '${now.year}-$m-$d';
}

int familyPuzzleDayIndex(DateTime now) => DateTime.utc(
      now.year,
      now.month,
      now.day,
    ).difference(DateTime.utc(2026)).inDays;

/// Deterministically selects a calm 3-puzzle daily round across 3 distinct
/// cognitive skills so the same day holds steady without casino randomness.
List<FamilyPuzzle> pickDailyRound(
  List<FamilyPuzzle> puzzles,
  DateTime now, {
  int childId = 0,
}) {
  if (puzzles.isEmpty) return const [];

  final bySkill = <PuzzleSkill, List<FamilyPuzzle>>{
    for (final s in PuzzleSkill.values) s: [],
  };
  for (final p in puzzles) {
    bySkill[p.skill]!.add(p);
  }

  final nonEmptySkills = [
    for (final s in PuzzleSkill.values)
      if (bySkill[s]!.isNotEmpty) s,
  ];
  if (nonEmptySkills.isEmpty) return const [];

  final dayIdx = familyPuzzleDayIndex(now);
  final salt = childId.abs();
  final picks = <FamilyPuzzle>[];
  final chosenIds = <String>{};

  for (var i = 0; i < 3 && i < nonEmptySkills.length; i++) {
    final skillOffset = (dayIdx + salt + i) % nonEmptySkills.length;
    final skill = nonEmptySkills[skillOffset < 0
        ? skillOffset + nonEmptySkills.length
        : skillOffset];
    final bucket = bySkill[skill]!;
    final rawIdx = (dayIdx ~/ 3 + salt + i) % bucket.length;
    final idx = rawIdx < 0 ? rawIdx + bucket.length : rawIdx;
    final puzzle = bucket[idx];
    if (chosenIds.add(puzzle.id)) {
      picks.add(puzzle);
    }
  }

  // Fallback if fewer than 3 distinct skill buckets exist.
  for (final p in puzzles) {
    if (picks.length >= 3) break;
    if (chosenIds.add(p.id)) picks.add(p);
  }

  return picks;
}

OffscreenBrainActivity? pickOffscreenActivity(
  List<OffscreenBrainActivity> list,
  DateTime now, {
  int childId = 0,
}) {
  if (list.isEmpty) return null;
  final raw = (familyPuzzleDayIndex(now) + childId.abs()) % list.length;
  final idx = raw < 0 ? raw + list.length : raw;
  return list[idx];
}

abstract final class FamilyPuzzleStore {
  static String _key(int childId) => '$kFamilyPuzzlesStoragePrefix$childId';

  static Future<FamilyPuzzleProgress> load({int childId = 0}) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_key(childId));
      if (raw == null || raw.isEmpty) return const FamilyPuzzleProgress();
      return FamilyPuzzleProgress.fromJson(
        jsonDecode(raw) as Map<String, dynamic>,
      );
    } catch (_) {
      return const FamilyPuzzleProgress();
    }
  }

  static Future<FamilyPuzzleProgress> markSolved(
    String puzzleId, {
    int childId = 0,
  }) async {
    final current = await load(childId: childId);
    final updated = FamilyPuzzleProgress(
      solvedIds: {...current.solvedIds, puzzleId},
      lastRoundDate: current.lastRoundDate,
      roundsCompleted: current.roundsCompleted,
    );
    await _save(childId, updated);
    return updated;
  }

  static Future<FamilyPuzzleProgress> markRoundCompleted(
    DateTime now, {
    int childId = 0,
  }) async {
    final current = await load(childId: childId);
    final updated = FamilyPuzzleProgress(
      solvedIds: current.solvedIds,
      lastRoundDate: familyPuzzleDayKey(now),
      roundsCompleted: current.roundsCompleted + 1,
    );
    await _save(childId, updated);
    return updated;
  }

  static Future<void> _save(int childId, FamilyPuzzleProgress progress) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_key(childId), jsonEncode(progress.toJson()));
    } catch (_) {
      // Persistence failure never breaks gameplay.
    }
  }
}
