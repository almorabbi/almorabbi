/// «تسميع مع الوالد» — what a parent marked while their child recited
/// (docs/TASMEE_WITH_PARENT.md).
///
/// The child recites from memory; the parent follows the mushaf on the screen
/// and taps the word where the child slipped, saying how: left it out, added,
/// swapped it, hesitated. Nothing judges the recitation automatically and no
/// audio is kept. Local only, one JSON blob under [TasmeeStore.key]; account
/// deletion's wipe removes it with every other non-exempt preference.
library;

import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

enum SlipType { omit, add, swap, hesitate }

class TasmeeMark {
  const TasmeeMark({
    required this.ayah,
    required this.word,
    required this.type,
  });

  /// Verse number in the surah, and the word's index in it (0-based, the
  /// verse's text split on spaces — see [ayahWords]).
  final int ayah;
  final int word;
  final SlipType type;

  Map<String, Object> toJson() => {
    'ayah': ayah,
    'word': word,
    'type': type.name,
  };

  static TasmeeMark? fromJson(Object? j) {
    if (j is! Map) return null;
    final ayah = j['ayah'], word = j['word'], type = j['type'];
    if (ayah is! num || word is! num || type is! String) return null;
    final t = SlipType.values.where((v) => v.name == type);
    if (t.isEmpty) return null;
    return TasmeeMark(ayah: ayah.toInt(), word: word.toInt(), type: t.first);
  }
}

class TasmeeSession {
  const TasmeeSession({
    required this.at,
    required this.from,
    required this.to,
    required this.marks,
  });

  final DateTime at;
  final int from;
  final int to;
  final List<TasmeeMark> marks;

  bool covers(int ayah) => ayah >= from && ayah <= to;

  Map<String, Object> toJson() => {
    'at': at.toIso8601String(),
    'from': from,
    'to': to,
    'marks': [for (final m in marks) m.toJson()],
  };

  static TasmeeSession? fromJson(Object? j) {
    if (j is! Map) return null;
    final at = DateTime.tryParse('${j['at']}');
    final from = j['from'], to = j['to'], marks = j['marks'];
    if (at == null || from is! num || to is! num || marks is! List) return null;
    return TasmeeSession(
      at: at,
      from: from.toInt(),
      to: to.toInt(),
      marks: [for (final m in marks) ?TasmeeMark.fromJson(m)],
    );
  }
}

/// The words of one verse as the screen shows them. The mushaf text in
/// assets/data/quran.json carries no stand-alone pause marks, so splitting on
/// spaces gives words only (test/tasmee_store_test.dart checks every verse).
List<String> ayahWords(String text) =>
    text.split(' ').where((w) => w.isNotEmpty).toList();

/// Words still to review: marked in some session and not recited cleanly in a
/// later session that covered their verse. Keyed `ayah:word`.
Map<String, SlipType> openSlips(List<TasmeeSession> sessions) {
  final open = <String, SlipType>{};
  final ordered = [...sessions]..sort((a, b) => a.at.compareTo(b.at));
  for (final s in ordered) {
    final marked = {for (final m in s.marks) '${m.ayah}:${m.word}': m.type};
    open.removeWhere((key, _) {
      final ayah = int.parse(key.split(':').first);
      return s.covers(ayah) && !marked.containsKey(key);
    });
    open.addAll(marked);
  }
  return open;
}

/// The day the surah is due for review, or null when nothing is open. One day
/// after a session with slips, then 3, then 7 while sessions keep finding
/// slips; a clean session starts the count again (spec: «مواضع المراجعة»).
DateTime? reviewDue(List<TasmeeSession> sessions) {
  if (sessions.isEmpty || openSlips(sessions).isEmpty) return null;
  final ordered = [...sessions]..sort((a, b) => a.at.compareTo(b.at));
  var run = 0;
  for (final s in ordered.reversed) {
    if (s.marks.isEmpty) break;
    run++;
  }
  const steps = [1, 3, 7];
  final days = steps[(run - 1).clamp(0, steps.length - 1)];
  final last = ordered.last.at;
  return DateTime(last.year, last.month, last.day + days);
}

bool isDue(List<TasmeeSession> sessions, DateTime now) {
  final due = reviewDue(sessions);
  return due != null && !DateTime(now.year, now.month, now.day).isBefore(due);
}

class TasmeeStore {
  TasmeeStore(this._prefs);

  static const String key = 'tg.tasmee.v1';
  static const int maxSessions = 20;

  final SharedPreferences _prefs;

  /// Every surah's sessions for one child, oldest first.
  Map<int, List<TasmeeSession>> loadForChild(int childId) {
    final child = _loadAll()[childId.toString()];
    if (child is! Map) return {};
    final out = <int, List<TasmeeSession>>{};
    for (final e in child.entries) {
      final surah = int.tryParse('${e.key}');
      final list = e.value;
      if (surah == null || list is! List) continue;
      out[surah] = [for (final s in list) ?TasmeeSession.fromJson(s)]
        ..sort((a, b) => a.at.compareTo(b.at));
    }
    return out;
  }

  Future<Map<int, List<TasmeeSession>>> add(
    int childId,
    int surah,
    TasmeeSession session,
  ) async {
    final all = _loadAll();
    final cid = childId.toString();
    final child = all[cid] is Map
        ? Map<String, dynamic>.from(all[cid] as Map)
        : <String, dynamic>{};
    final list = child['$surah'] is List
        ? List<dynamic>.from(child['$surah'] as List)
        : <dynamic>[];
    list.add(session.toJson());
    while (list.length > maxSessions) {
      list.removeAt(0);
    }
    child['$surah'] = list;
    all[cid] = child;
    await _prefs.setString(key, jsonEncode(all));
    return loadForChild(childId);
  }

  Map<String, dynamic> _loadAll() {
    final raw = _prefs.getString(key);
    if (raw == null || raw.isEmpty) return {};
    try {
      final decoded = jsonDecode(raw);
      return decoded is Map ? Map<String, dynamic>.from(decoded) : {};
    } catch (_) {
      return {};
    }
  }
}
