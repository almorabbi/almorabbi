/// «موقف بقرار» — a four-minute decision step for the parent
/// (docs/MAWAQIF.md).
///
/// A situation from the parent's day, three reasonable responses each with
/// what happens now and what happens later, the hadith that answers it, one
/// idea and one step. The content comes from `GET /api/program/mawaqif`; which
/// steps a parent went through stays on the device ([MawaqifStore]).
library;

import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../../programs/data/programs_models.dart';

class MawqifChoice {
  const MawqifChoice({
    required this.key,
    required this.text,
    required this.now,
    required this.later,
  });

  final String key;
  final String text;
  final String now;
  final String later;
}

class Mawqif {
  const Mawqif({
    required this.id,
    required this.ageGroup,
    required this.topic,
    required this.title,
    required this.situation,
    required this.choices,
    required this.evidence,
    required this.words,
    required this.idea,
    required this.step,
  });

  final String id;
  final String ageGroup;

  /// A follow-up topic (the server's FOLLOWUP_TOPICS) for the step's promise.
  final String topic;
  final String title;
  final String situation;
  final List<MawqifChoice> choices;
  final EvidenceCard evidence;

  /// The hadith's harder words and their meanings (Arabic only).
  final List<({String word, String meaning})> words;
  final String idea;
  final String step;

  /// Null for anything the screen could not render in full: the server drops
  /// malformed items too, but an app must not trust a field it renders.
  static Mawqif? fromJson(Object? j) {
    if (j is! Map) return null;
    String? s(Object? v) => v is String && v.trim().isNotEmpty ? v : null;
    final id = s(j['id']), age = s(j['age_group']), topic = s(j['topic']);
    final title = s(j['title']), situation = s(j['situation']);
    final idea = s(j['idea']), step = s(j['step']);
    if (id == null || age == null || topic == null || title == null ||
        situation == null || idea == null || step == null) {
      return null;
    }
    final raw = j['choices'];
    if (raw is! List || raw.length != 3) return null;
    final choices = <MawqifChoice>[];
    for (final c in raw) {
      if (c is! Map) return null;
      final key = s(c['key']), text = s(c['text']);
      final now = s(c['now']), later = s(c['later']);
      if (key == null || text == null || now == null || later == null) {
        return null;
      }
      choices.add(MawqifChoice(key: key, text: text, now: now, later: later));
    }
    final cards = EvidenceCard.listFrom([j['evidence']]);
    if (cards.isEmpty) return null;
    final ev = j['evidence'] as Map;
    final words = <({String word, String meaning})>[
      if (ev['words'] is List)
        for (final w in ev['words'] as List)
          if (w is Map && s(w['word']) != null && s(w['meaning']) != null)
            (word: w['word'] as String, meaning: w['meaning'] as String),
    ];
    return Mawqif(
      id: id,
      ageGroup: age,
      topic: topic,
      title: title,
      situation: situation,
      choices: choices,
      evidence: cards.first,
      words: words,
      idea: idea,
      step: step,
    );
  }
}

/// The steps a parent went through, per child. One JSON blob under [key];
/// account deletion's wipe removes it with every other non-exempt preference.
class MawaqifStore {
  MawaqifStore(this._prefs);

  static const String key = 'tg.mawaqif.v1';

  final SharedPreferences _prefs;

  Set<String> doneFor(int childId) {
    final list = _all()['$childId'];
    return {
      if (list is List)
        for (final id in list)
          if (id is String) id,
    };
  }

  Future<void> markDone(int childId, String id) async {
    final all = _all();
    final done = doneFor(childId)..add(id);
    all['$childId'] = done.toList()..sort();
    await _prefs.setString(key, jsonEncode(all));
  }

  Map<String, dynamic> _all() {
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

/// The first step of [items] this child has not been through, or null.
Mawqif? nextMawqif(List<Mawqif> items, Set<String> done) {
  for (final m in items) {
    if (!done.contains(m.id)) return m;
  }
  return null;
}
