import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:almorabbi/features/program/data/story_models.dart';

void main() {
  group('Story model and kindergarten enrichment', () {
    test('parses enriched story with discussion questions and Islamic value', () {
      final json = {
        'id': 'badr_broken_toy',
        'title': 'بدر واللعبة المكسورة',
        'description': 'قصة تربوية',
        'coverImage': 'docs/stories/cover.png',
        'themeColor': '0xFF0F766E',
        'ageGroup': '3-6 سنوات',
        'category': 'الصدق والشجاعة',
        'discussionQuestions': [
          'ما الذي كان يمكن أن يحدث لو كذب بدر؟',
          'هل الاعتراف بالخطأ يحتاج إلى شجاعة؟'
        ],
        'islamicValue': 'قال رسول الله ﷺ: عليكم بالصدق',
        'actionChallenge': 'تحدي الصدق اليومي',
        'pages': [
          {
            'pageNumber': 1,
            'text': 'كان بدر يلعب...',
            'image': 'docs/stories/1.png',
          }
        ]
      };

      final story = Story.fromJson(json);

      expect(story.id, 'badr_broken_toy');
      expect(story.title, 'بدر واللعبة المكسورة');
      expect(story.ageGroup, '3-6 سنوات');
      expect(story.category, 'الصدق والشجاعة');
      expect(story.discussionQuestions.length, 2);
      expect(story.islamicValue, contains('عليكم بالصدق'));
      expect(story.actionChallenge, 'تحدي الصدق اليومي');
      expect(story.hasDebrief, isTrue);
      expect(story.pages.length, 1);
    });

    test('backward compatibility: legacy story without debrief fields defaults safely', () {
      final json = {
        'id': 'legacy_story',
        'title': 'قصة قديمة',
        'description': 'وصف',
        'coverImage': 'docs/stories/legacy.png',
        'themeColor': '0xFF123456',
        'pages': []
      };

      final story = Story.fromJson(json);

      expect(story.id, 'legacy_story');
      expect(story.ageGroup, isNull);
      expect(story.category, isNull);
      expect(story.discussionQuestions, isEmpty);
      expect(story.islamicValue, isNull);
      expect(story.actionChallenge, isNull);
      expect(story.hasDebrief, isFalse);
    });

    test('both docs/stories.json and mobile/assets/data/stories.json are valid and contain all 47 stories', () {
      final docsFile = File('../docs/stories.json');
      final assetsFile = File('assets/data/stories.json');

      expect(docsFile.existsSync(), isTrue);
      expect(assetsFile.existsSync(), isTrue);

      final docsStories = (jsonDecode(docsFile.readAsStringSync()) as List)
          .map((e) => Story.fromJson(e as Map<String, dynamic>))
          .toList();

      final assetsStories = (jsonDecode(assetsFile.readAsStringSync()) as List)
          .map((e) => Story.fromJson(e as Map<String, dynamic>))
          .toList();

      expect(docsStories.length, 47);
      expect(assetsStories.length, 47);

      // Verify Kindergarten stories exist
      final badr = docsStories.firstWhere((s) => s.id == 'badr_broken_toy');
      expect(badr.ageGroup, '3-6 سنوات');
      expect(badr.discussionQuestions, isNotEmpty);
      expect(badr.islamicValue, isNotEmpty);
      expect(badr.actionChallenge, isNotEmpty);
      expect(badr.hasDebrief, isTrue);

      final sarah = docsStories.firstWhere((s) => s.id == 'sarah_basil_sprout');
      expect(sarah.ageGroup, '3-6 سنوات');
      expect(sarah.hasDebrief, isTrue);

      // The Qur'anic prophets' stories and the Seerah stories carry their
      // series, in both copies — and no story is in both.
      for (final stories in [docsStories, assetsStories]) {
        expect(
          stories.where((s) => s.isProphetStory).map((s) => s.id).toSet(),
          _anbiyaIds,
        );
        expect(
          stories.where((s) => s.isSeerahStory).map((s) => s.id).toSet(),
          _siraIds,
        );
        for (final s in stories) {
          expect(s.isProphetStory && s.isSeerahStory, isFalse, reason: s.id);
          if (!_anbiyaIds.contains(s.id) && !_siraIds.contains(s.id)) {
            expect(s.series, isNull, reason: s.id);
          }
        }
      }
    });
  });

  group('series', () {
    Map<String, dynamic> storyJson([Map<String, dynamic> extra = const {}]) => {
          'id': 'anbiya_test',
          'title': 'قصة',
          'description': 'وصف',
          'coverImage': '',
          'themeColor': '0xFF0F766E',
          'pages': [],
          ...extra,
        };

    test('is read when present', () {
      final story = Story.fromJson(storyJson({'series': kAnbiyaSeries}));
      expect(story.series, 'anbiya_quran');
      expect(story.isProphetStory, isTrue);
    });

    test('a missing series is null, not a prophet story', () {
      final story = Story.fromJson(storyJson());
      expect(story.series, isNull);
      expect(story.isProphetStory, isFalse);
    });

    test('a malformed series is null and never throws', () {
      for (final bad in <Object?>[5, ['anbiya_quran'], {'id': 'x'}, true, '', '   ', null]) {
        late Story story;
        expect(() => story = Story.fromJson(storyJson({'series': bad})), returnsNormally,
            reason: '$bad');
        expect(story.series, isNull, reason: '$bad');
        expect(story.isProphetStory, isFalse, reason: '$bad');
      }
    });

    test('another series is kept but is not a prophet story', () {
      final story = Story.fromJson(storyJson({'series': ' seerah '}));
      expect(story.series, 'seerah');
      expect(story.isProphetStory, isFalse);
      expect(story.isSeerahStory, isFalse);
    });

    test('the Seerah series is read, and is not a prophet story', () {
      final story = Story.fromJson(storyJson({'series': kSiraSeries}));
      expect(story.series, 'sira_sahih');
      expect(story.isSeerahStory, isTrue);
      expect(story.isProphetStory, isFalse);
      final padded = Story.fromJson(storyJson({'series': ' sira_sahih '}));
      expect(padded.isSeerahStory, isTrue);
      for (final bad in <Object?>[5, ['sira_sahih'], '', null]) {
        expect(Story.fromJson(storyJson({'series': bad})).isSeerahStory, isFalse,
            reason: '$bad');
      }
      expect(Story.fromJson(storyJson({'series': kAnbiyaSeries})).isSeerahStory, isFalse);
    });
  });
}

const _siraIds = {
  'sira_ghar_young',
  'sira_ghar_older',
  'sira_masjid_young',
  'sira_masjid_older',
  'sira_jidh_young',
  'sira_jidh_older',
  'sira_abu_umair_young',
  'sira_abu_umair_older',
};

const _anbiyaIds = {
  'anbiya_yunus_young',
  'anbiya_yunus_older',
  'anbiya_sulayman_naml_young',
  'anbiya_sulayman_naml_older',
  'anbiya_nuh_young',
  'anbiya_nuh_older',
  'anbiya_ibrahim_nar_young',
  'anbiya_ibrahim_nar_older',
  'anbiya_bayt_young',
  'anbiya_bayt_older',
  'anbiya_musa_tabut_young',
  'anbiya_musa_tabut_older',
  'anbiya_musa_bahr_young',
  'anbiya_musa_bahr_older',
  'anbiya_yusuf_young',
  'anbiya_yusuf_older',
  'anbiya_ayyub_young',
  'anbiya_ayyub_older',
  'anbiya_zakariya_young',
  'anbiya_zakariya_older',
};
