/// «من السيرة النبوية» — the Seerah season (series `sira_sahih`, 2026-10-30).
///
/// Pins:
///   1. The bundled library carries exactly the eight Seerah stories, tagged in
///      Arabic and English, and none of them is also a prophets' story.
///   2. 🚨 Their paper-cut scenes draw no person: the Prophet ﷺ and his
///      companions are never pictured. An allowlist, not a blocklist — a new
///      human piece cannot slip in by being unlisted.
///   3. Every quoted hadith on a page keeps its citation in the text the
///      reader shows (the narrator skips it; gen_story_narration.py).
///   4. The narrator's clock skips a citation: a word after it is cued when it
///      is said, and the citation's own words cue nothing.
///   5. The shelf section's strings exist in both languages and say where the
///      stories come from and that no one is pictured.
///
/// The content itself (every «» held verbatim by its number, nothing the
/// sources do not say) is ops/tools/check_sira_stories.py's job, on pre-commit.
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:almorabbi/features/program/data/story_models.dart';
import 'package:almorabbi/features/stories/narration/story_narration.dart';
import 'package:almorabbi/features/stories/narration/word_cues.dart';
import 'package:almorabbi/features/stories/scene/story_scene_catalog.dart';
import 'package:almorabbi/l10n/app_localizations.dart';

List<Story> _bundled(String file) =>
    (jsonDecode(File('assets/data/$file').readAsStringSync()) as List)
        .map((j) => Story.fromJson(j as Map<String, dynamic>))
        .toList();

const _seerah = {
  'sira_ghar_young',
  'sira_ghar_older',
  'sira_masjid_young',
  'sira_masjid_older',
  'sira_jidh_young',
  'sira_jidh_older',
  'sira_abu_umair_young',
  'sira_abu_umair_older',
};

void main() {
  final ar = _bundled('stories.json');
  final en = _bundled('stories_en.json');

  test('the library carries the eight Seerah stories, in both languages', () {
    for (final stories in [ar, en]) {
      final seerah = stories.where((s) => s.isSeerahStory).toList();
      expect(seerah.map((s) => s.id).toSet(), _seerah);
      for (final s in seerah) {
        expect(s.isProphetStory, isFalse, reason: s.id);
        expect(s.series, kSiraSeries, reason: s.id);
      }
    }
  });

  test('a Seerah story draws no person — only sky, palms, birds, a mosque', () {
    const allowed = {
      'cloud',
      'star',
      'moon',
      'sun',
      'plant',
      'sprout',
      'seed',
      'flower',
      'rose',
      'bush',
      'tree',
      'tree_olive',
      'tree_nest',
      'bird',
      'heart',
      'lantern',
    };
    const backdrops = {
      'bg_night_sky',
      'bg_garden_day',
      'bg_garden_evening',
      'bg_street',
      'bg_mosque',
    };
    final seerah = [...ar, ...en].where((s) => s.isSeerahStory).toList();
    expect(seerah, hasLength(16));
    for (final s in seerah) {
      expect(hasScenesFor(s.id), isTrue, reason: s.id);
      expect(scenePageCount(s.id), s.pages.length, reason: s.id);
      for (final scene in [
        coverSceneFor(s.id),
        for (var i = 0; i < s.pages.length; i++) sceneFor(s.id, i),
      ]) {
        expect(
          backdrops,
          contains(scene.backdrop),
          reason: '${s.id}: ${scene.backdrop}',
        );
        for (final l in scene.layers) {
          expect(allowed, contains(l.piece), reason: '${s.id}: ${l.piece}');
        }
      }
    }
  });

  test('every quoted hadith on a Seerah page shows its citation', () {
    final cite = RegExp(r'\(صحيح (?:البخاري|مسلم) [٠-٩]+\)');
    final enCite = RegExp(r'\(Sahih (?:al-Bukhari|Muslim) \d+\)');
    for (final s in ar.where((s) => s.isSeerahStory)) {
      for (final p in s.pages) {
        final quotes = '«'.allMatches(p.text).length;
        if (quotes > 0) {
          expect(
            cite.hasMatch(p.text),
            isTrue,
            reason: '${s.id} p${p.pageNumber}',
          );
        }
      }
    }
    for (final s in en.where((s) => s.isSeerahStory)) {
      final twin = ar.firstWhere((a) => a.id == s.id);
      for (var i = 0; i < s.pages.length; i++) {
        expect(
          enCite.allMatches(s.pages[i].text).length,
          cite.allMatches(twin.pages[i].text).length,
          reason: '${s.id} p${i + 1}',
        );
      }
    }
  });

  test('the section strings say where the stories come from, in ar and en', () {
    final l10nAr = lookupAppLocalizations(const Locale('ar'));
    final l10nEn = lookupAppLocalizations(const Locale('en'));
    expect(l10nAr.storyShelfSeerah, 'من السيرة النبوية');
    expect(l10nEn.storyShelfSeerah, 'From the Seerah');
    expect(
      l10nAr.storyShelfSeerahSubtitle,
      allOf(contains('البخاري'), contains('مسلم'), contains('بلا صور')),
    );
    expect(
      l10nEn.storyShelfSeerahSubtitle,
      allOf(contains('Sahih'), contains('no pictures')),
    );
  });

  group('the citation is shown, not said', () {
    const ar =
        'قال: «يا أبا عمير ما فعل النغير» (صحيح البخاري ٦٢٠٣)، يسأله عن طائره.';
    const en =
        'He said: “O Abu Umair, what did the little bird do?” (Sahih al-Bukhari 6203)';

    test(
      'its range is found in Arabic and English, other brackets are not',
      () {
        final r = unspokenRanges(ar).single;
        expect(ar.substring(r.start, r.end), ' (صحيح البخاري ٦٢٠٣)');
        expect(unspokenRanges(en), hasLength(1));
        expect(unspokenRanges('قال أبو بكر (رضي الله عنه) لابنته'), isEmpty);
      },
    );

    test("a cue after the citation lands on the spoken text's clock", () {
      // One sentence, 10 s, timed over the spoken characters only.
      final sentence = [
        NarrationSentence(from: 0, to: ar.length, start: 0, end: 10),
      ];
      final at = wordCuesFor(
        [
          ['طائر'],
        ],
        ar,
        sentence,
      ).single.at;
      final spoken =
          ar.length -
          unspokenRanges(ar).single.end +
          unspokenRanges(ar).single.start;
      final said =
          ar.indexOf('طائره') -
          (unspokenRanges(ar).single.end - unspokenRanges(ar).single.start);
      expect(at, closeTo(said / spoken * 10, 1e-9));
      // The citation's own words are never said, so never cue.
      expect(
        wordCuesFor(
          [
            ['البخاري'],
            ['صحيح'],
          ],
          ar,
          sentence,
        ),
        isEmpty,
      );
      expect(
        wordCuesFor(
          [
            ['bukhari'],
          ],
          en,
          [NarrationSentence(from: 0, to: en.length, start: 0, end: 5)],
        ),
        isEmpty,
      );
    });
  });
}
