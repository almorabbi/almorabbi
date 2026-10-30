/// Which stories are told with their painted pictures, alive
/// (living_picture.dart) — and, page by page, the things in each picture the
/// narrator's words point the camera at.
///
/// A story is here only when every one of its pages has a real painting in
/// docs/stories/ (served by the backend, the same files the reader showed
/// before the paper-cut scenes) — all 19 bundled stories since 2026-10-24,
/// and the prophets' stories (series anbiya_quran) since 2026-10-25: their
/// story pages show only what the Qur'an mentions — no prophet, no person —
/// so no region there is ever cued by a prophet's name onto a human figure.
/// The Seerah season (series sira_sahih, 2026-10-30) likewise: the Prophet ﷺ
/// and his companions are never pictured, so no region is cued by a person.
/// The paper-cut scenes stay for a story the server adds before the app
/// knows it, and as the fallback when a painting cannot be loaded (offline).
///
/// Regions are normalised to the 1024² painting. Cue words are Arabic and
/// English in one list (narration/word_cues.dart); every word here is one the
/// page's recording actually says in at least one language — pinned against
/// the real manifests in test/living_picture_test.dart.
library;

import 'package:flutter/painting.dart';

import 'living_picture.dart';

String _page(String storyId, int page) => 'docs/stories/${storyId}_$page.png';

/// The living picture for page [index] (0-based) of [storyId], or null —
/// that story keeps its paper-cut scenes.
LivingPicture? livingPictureFor(String storyId, int index) {
  final pages = _catalog[storyId];
  if (pages == null || index < 0 || index >= pages.length) return null;
  return pages[index];
}

/// The painted cover of a living story, or null.
String? livingCoverFor(String storyId) =>
    _catalog.containsKey(storyId) ? 'docs/stories/${storyId}_cover.png' : null;

/// The stories told with their paintings.
Iterable<String> get livingStories => _catalog.keys;

final Map<String, List<LivingPicture>> _catalog = {
  // يوسف وغرسة الأمل — Yusuf and the Seed of Hope
  'hope_sprout': [
    LivingPicture(
      image: _page('hope_sprout', 1),
      regions: [
        PictureRegion(
          'father',
          Rect.fromLTRB(0.5, 0.15, 0.9, 0.9),
          cue: ['والده', 'والدي', 'father'],
        ),
        PictureRegion(
          'yusuf',
          Rect.fromLTRB(0.22, 0.28, 0.48, 0.85),
          cue: ['يوسف', 'yusuf'],
        ),
        PictureRegion(
          'the golden seed',
          Rect.fromLTRB(0.38, 0.48, 0.6, 0.65),
          cue: ['بذر', 'seed'],
          burst: PictureBurst.sparkles,
        ),
        PictureRegion(
          'the garden',
          Rect.fromLTRB(0, 0.55, 1, 1),
          cue: ['طبيع', 'nature'],
        ),
      ],
    ),
    LivingPicture(
      image: _page('hope_sprout', 2),
      regions: [
        PictureRegion(
          'yusuf',
          Rect.fromLTRB(0.25, 0.15, 0.7, 0.8),
          cue: ['يوسف', 'yusuf'],
        ),
        PictureRegion(
          'the pot of earth',
          Rect.fromLTRB(0.48, 0.62, 0.72, 0.9),
          cue: ['تراب', 'بذر', 'soil', 'seed'],
        ),
        PictureRegion(
          'the watering can',
          Rect.fromLTRB(0.62, 0.48, 0.86, 0.7),
          cue: ['سقا', 'watered'],
          burst: PictureBurst.sparkles,
        ),
        PictureRegion(
          'the trowel',
          Rect.fromLTRB(0.3, 0.78, 0.5, 0.95),
          cue: ['حفر', 'dug'],
        ),
      ],
    ),
    LivingPicture(
      image: _page('hope_sprout', 3),
      regions: [
        PictureRegion(
          'yusuf, sad',
          Rect.fromLTRB(0.25, 0.35, 0.62, 0.95),
          cue: ['يوسف', 'yusuf', 'حزين', 'sad'],
        ),
        PictureRegion(
          'his father',
          Rect.fromLTRB(0.5, 0.05, 0.98, 0.95),
          cue: ['والده', 'father', 'ضاحك', 'laughed'],
        ),
      ],
    ),
    LivingPicture(
      image: _page('hope_sprout', 4),
      ambient: PictureAmbient.sparkles,
      regions: [
        PictureRegion(
          'yusuf',
          Rect.fromLTRB(0.05, 0.3, 0.6, 0.95),
          cue: ['يوسف', 'yusuf'],
        ),
        PictureRegion(
          'the green shoot',
          Rect.fromLTRB(0.5, 0.4, 0.82, 0.98),
          cue: ['برعم', 'shoot'],
          burst: PictureBurst.sparkles,
        ),
        PictureRegion(
          'the morning sun',
          Rect.fromLTRB(0.4, 0, 0.9, 0.32),
          cue: ['شمس', 'sun'],
        ),
        PictureRegion(
          'yusuf happy',
          Rect.fromLTRB(0.2, 0.3, 0.55, 0.65),
          cue: ['فرح', 'happy'],
          burst: PictureBurst.hearts,
        ),
      ],
    ),
  ],
  // أنس والهر الصغير — Anas and the Little Cat
  'kitten_kindness': [
    LivingPicture(
      image: _page('kitten_kindness', 1),
      regions: [
        PictureRegion(
          'anas',
          Rect.fromLTRB(0.58, 0.33, 0.84, 0.85),
          cue: ['انس', 'anas', 'مدرس', 'school'],
        ),
        PictureRegion(
          'the old tree',
          Rect.fromLTRB(0, 0, 0.55, 0.85),
          cue: ['شجر', 'tree'],
        ),
        PictureRegion(
          'the kitten',
          Rect.fromLTRB(0.28, 0.48, 0.5, 0.72),
          cue: ['صوت', 'هر', 'sound', 'cat'],
        ),
      ],
    ),
    LivingPicture(
      image: _page('kitten_kindness', 2),
      regions: [
        PictureRegion(
          'the kitten',
          Rect.fromLTRB(0.33, 0.52, 0.62, 0.87),
          cue: ['مخلوق', 'creature', 'animals'],
        ),
        PictureRegion(
          'anas',
          Rect.fromLTRB(0.5, 0.15, 0.95, 0.85),
          cue: ['انس', 'anas'],
        ),
        PictureRegion(
          'anas feels for it',
          Rect.fromLTRB(0.55, 0.15, 0.9, 0.5),
          cue: ['شفق', 'رحم', 'pity', 'mercy'],
          burst: PictureBurst.hearts,
        ),
      ],
    ),
    LivingPicture(
      image: _page('kitten_kindness', 3),
      regions: [
        PictureRegion(
          'anas',
          Rect.fromLTRB(0.4, 0.05, 0.95, 0.85),
          cue: ['انس', 'anas'],
        ),
        PictureRegion(
          'the bowl of water',
          Rect.fromLTRB(0.16, 0.7, 0.38, 0.9),
          cue: ['وعاء', 'bowl'],
          burst: PictureBurst.sparkles,
        ),
        PictureRegion(
          'the cloth',
          Rect.fromLTRB(0.4, 0.55, 0.66, 0.85),
          cue: ['منديل', 'مسح', 'cloth', 'wiped'],
        ),
        PictureRegion(
          'the kitten',
          Rect.fromLTRB(0.2, 0.55, 0.56, 0.85),
          cue: ['هر', 'cat'],
        ),
      ],
    ),
    LivingPicture(
      image: _page('kitten_kindness', 4),
      ambient: PictureAmbient.sparkles,
      regions: [
        PictureRegion(
          'the kitten',
          Rect.fromLTRB(0.08, 0.45, 0.52, 0.95),
          cue: ['هر', 'cat', 'صوت', 'purr'],
          burst: PictureBurst.hearts,
        ),
        PictureRegion(
          'anas',
          Rect.fromLTRB(0.42, 0.1, 0.85, 0.95),
          cue: ['انس', 'anas'],
        ),
        PictureRegion(
          'his happy heart',
          Rect.fromLTRB(0.42, 0.1, 0.8, 0.5),
          cue: ['قلب', 'سرور', 'heart', 'joy'],
          burst: PictureBurst.hearts,
        ),
      ],
    ),
  ],
  // ليلى ونجمتها الصغيرة — Layla and Her Little Star
  'layla_star': [
    LivingPicture(
      image: _page('layla_star', 1),
      ambient: PictureAmbient.sparkles,
      regions: [
        PictureRegion(
          'layla',
          Rect.fromLTRB(0.2, 0.2, 0.65, 0.9),
          cue: ['ليلي', 'layla'],
        ),
        PictureRegion(
          'the starry sky',
          Rect.fromLTRB(0.4, 0.05, 0.95, 0.75),
          cue: ['سماء', 'نجوم', 'sky', 'stars'],
          burst: PictureBurst.sparkles,
        ),
      ],
    ),
    LivingPicture(
      image: _page('layla_star', 2),
      ambient: PictureAmbient.sparkles,
      regions: [
        PictureRegion(
          'the little star',
          Rect.fromLTRB(0.62, 0, 0.98, 0.42),
          cue: ['نجم', 'star'],
          burst: PictureBurst.sparkles,
        ),
        PictureRegion(
          'layla',
          Rect.fromLTRB(0.3, 0.25, 0.56, 0.72),
          cue: ['ليلي', 'layla'],
        ),
        PictureRegion(
          'her bed',
          Rect.fromLTRB(0.22, 0.5, 0.82, 0.92),
          cue: ['سرير', 'bed'],
        ),
        PictureRegion(
          'her mother',
          Rect.fromLTRB(0.5, 0.15, 0.86, 0.95),
          cue: ['والدت', 'mother'],
        ),
      ],
    ),
    LivingPicture(
      image: _page('layla_star', 3),
      ambient: PictureAmbient.sparkles,
      regions: [
        PictureRegion(
          'the dream cloud',
          Rect.fromLTRB(0.12, 0.05, 0.95, 0.55),
          cue: ['سحاب', 'نجم', 'clouds', 'star'],
          burst: PictureBurst.sparkles,
        ),
        PictureRegion(
          'layla',
          Rect.fromLTRB(0.35, 0.45, 0.82, 0.92),
          cue: ['ليلي', 'layla'],
        ),
      ],
    ),
    LivingPicture(
      image: _page('layla_star', 4),
      ambient: PictureAmbient.sparkles,
      regions: [
        PictureRegion(
          'the stars in the window',
          Rect.fromLTRB(0, 0.05, 0.45, 0.62),
          cue: ['نجوم', 'كون', 'stars', 'universe'],
          burst: PictureBurst.sparkles,
        ),
        PictureRegion(
          'layla',
          Rect.fromLTRB(0.45, 0.38, 0.9, 0.75),
          cue: ['ليلي', 'layla'],
        ),
      ],
    ),
    LivingPicture(
      image: _page('layla_star', 5),
      ambient: PictureAmbient.sparkles,
      regions: [
        PictureRegion(
          'her kitten',
          Rect.fromLTRB(0.08, 0.22, 0.42, 0.5),
          cue: ['قط', 'kitten'],
          burst: PictureBurst.hearts,
        ),
        PictureRegion(
          'mother\'s food',
          Rect.fromLTRB(0.32, 0.18, 0.66, 0.52),
          cue: ['طعام', 'امي', 'food', 'mother'],
        ),
        PictureRegion(
          'grandfather\'s garden',
          Rect.fromLTRB(0.6, 0.18, 0.92, 0.56),
          cue: ['جدي', 'حديق', 'grandfather', 'garden'],
        ),
        PictureRegion(
          'layla',
          Rect.fromLTRB(0.3, 0.58, 0.82, 0.96),
          cue: ['ليلي', 'layla'],
        ),
      ],
    ),
    LivingPicture(
      image: _page('layla_star', 6),
      ambient: PictureAmbient.sparkles,
      regions: [
        PictureRegion(
          'her little star',
          Rect.fromLTRB(0.08, 0.12, 0.5, 0.46),
          cue: ['نجم', 'star'],
          burst: PictureBurst.sparkles,
        ),
        PictureRegion(
          'layla',
          Rect.fromLTRB(0.45, 0.4, 0.9, 0.72),
          cue: ['ليلي', 'layla'],
        ),
        PictureRegion(
          'the warm blanket',
          Rect.fromLTRB(0.08, 0.55, 0.82, 0.95),
          cue: ['لحاف', 'blanket'],
        ),
      ],
    ),
  ],
  // صالح وعصفور الأمانة — Saleh and the Little Bird of Amanah
  'saleh_bird': [
    LivingPicture(
      image: _page('saleh_bird', 1),
      regions: [
        PictureRegion(
          'saleh',
          Rect.fromLTRB(0.2, 0.45, 0.5, 0.92),
          cue: ['صالح', 'saleh'],
        ),
        PictureRegion(
          'his ball',
          Rect.fromLTRB(0.4, 0.82, 0.56, 0.97),
          cue: ['كرت', 'ball'],
        ),
        PictureRegion(
          'the bird and its nest',
          Rect.fromLTRB(0.6, 0.15, 0.9, 0.38),
          cue: ['عصفور', 'عش', 'bird', 'nest'],
          burst: PictureBurst.sparkles,
        ),
        PictureRegion(
          'the olive tree',
          Rect.fromLTRB(0.5, 0, 1, 0.9),
          cue: ['زيتون', 'شجر', 'tree'],
        ),
      ],
    ),
    LivingPicture(
      image: _page('saleh_bird', 2),
      regions: [
        PictureRegion(
          'saleh',
          Rect.fromLTRB(0.25, 0.4, 0.7, 0.9),
          cue: ['صالح', 'saleh'],
        ),
        PictureRegion(
          'the wallet',
          Rect.fromLTRB(0.46, 0.66, 0.72, 0.86),
          cue: ['محفظ', 'نقود', 'wallet', 'money'],
          burst: PictureBurst.sparkles,
        ),
        PictureRegion(
          'the tree',
          Rect.fromLTRB(0.4, 0, 1, 0.75),
          cue: ['شجر', 'tree'],
        ),
      ],
    ),
    LivingPicture(
      image: _page('saleh_bird', 3),
      regions: [
        PictureRegion(
          'saleh',
          Rect.fromLTRB(0.2, 0.3, 0.46, 0.92),
          cue: ['صالح', 'saleh'],
        ),
        PictureRegion(
          'the kind man',
          Rect.fromLTRB(0.55, 0.28, 0.95, 0.92),
          cue: ['حارس', 'جار', 'احمد', 'guard', 'neighbor', 'ahmad'],
        ),
        PictureRegion(
          'the wallet',
          Rect.fromLTRB(0.38, 0.4, 0.56, 0.56),
          cue: ['محفظ', 'wallet'],
        ),
      ],
    ),
    LivingPicture(
      image: _page('saleh_bird', 4),
      regions: [
        PictureRegion(
          'the man',
          Rect.fromLTRB(0.5, 0.32, 0.92, 0.97),
          cue: ['رجل', 'man'],
        ),
        PictureRegion(
          'saleh',
          Rect.fromLTRB(0.2, 0.4, 0.46, 0.92),
          cue: ['صالح', 'saleh'],
        ),
        PictureRegion(
          'the grass',
          Rect.fromLTRB(0, 0.65, 1, 1),
          cue: ['اعشاب', 'grass'],
        ),
      ],
    ),
    LivingPicture(
      image: _page('saleh_bird', 5),
      regions: [
        PictureRegion(
          'saleh',
          Rect.fromLTRB(0.28, 0.32, 0.52, 0.95),
          cue: ['صالح', 'saleh'],
        ),
        PictureRegion(
          'the man',
          Rect.fromLTRB(0.48, 0.25, 0.9, 0.97),
          cue: ['رجل', 'man'],
        ),
        PictureRegion(
          'the wallet',
          Rect.fromLTRB(0.4, 0.52, 0.6, 0.7),
          cue: ['محفظ', 'wallet'],
          burst: PictureBurst.sparkles,
        ),
        PictureRegion(
          'saleh\'s smile',
          Rect.fromLTRB(0.3, 0.32, 0.5, 0.55),
          cue: ['ابتسام', 'smile'],
          burst: PictureBurst.hearts,
        ),
      ],
    ),
    LivingPicture(
      image: _page('saleh_bird', 6),
      ambient: PictureAmbient.sparkles,
      regions: [
        PictureRegion(
          'the man, joyful',
          Rect.fromLTRB(0.55, 0.25, 0.95, 0.95),
          cue: ['رجل', 'فرح', 'man', 'joy'],
          burst: PictureBurst.hearts,
        ),
        PictureRegion(
          'saleh',
          Rect.fromLTRB(0.25, 0.35, 0.56, 0.95),
          cue: ['صالح', 'saleh'],
        ),
        PictureRegion(
          'the singing bird',
          Rect.fromLTRB(0.3, 0.12, 0.58, 0.34),
          cue: ['سعيد', 'happy'],
          burst: PictureBurst.sparkles,
        ),
      ],
    ),
  ],
  // نور والحديقة النظيفة — Noor and the Clean Garden
  'noor_clean': [
    LivingPicture(
      image: _page('noor_clean', 1),
      regions: [
        PictureRegion(
          'noor',
          Rect.fromLTRB(0.2, 0.15, 0.6, 0.75),
          cue: ['نور', 'noor'],
        ),
        PictureRegion(
          'the litter',
          Rect.fromLTRB(0.45, 0.55, 0.95, 0.95),
          cue: ['مخلفات', 'اوراق', 'trash', 'leaves'],
        ),
        PictureRegion(
          'the garden',
          Rect.fromLTRB(0, 0, 1, 0.5),
          cue: ['حديق', 'garden'],
        ),
      ],
    ),
    LivingPicture(
      image: _page('noor_clean', 2),
      regions: [
        PictureRegion(
          'noor',
          Rect.fromLTRB(0.3, 0.12, 0.66, 0.86),
          cue: ['نور', 'noor'],
        ),
        PictureRegion(
          'the big bag',
          Rect.fromLTRB(0.58, 0.45, 0.96, 0.9),
          cue: ['اكياس', 'bags'],
          burst: PictureBurst.sparkles,
        ),
        PictureRegion(
          'the bottles and papers',
          Rect.fromLTRB(0.05, 0.65, 0.62, 0.98),
          cue: ['علب', 'اوراق', 'bottles', 'leaves'],
        ),
      ],
    ),
    LivingPicture(
      image: _page('noor_clean', 3),
      ambient: PictureAmbient.sparkles,
      regions: [
        PictureRegion(
          'the sign',
          Rect.fromLTRB(0.8, 0.16, 1, 0.36),
          cue: ['لافت', 'sign'],
          burst: PictureBurst.sparkles,
        ),
        PictureRegion(
          'noor',
          Rect.fromLTRB(0.3, 0.18, 0.56, 0.75),
          cue: ['نور', 'noor'],
        ),
        PictureRegion(
          'the garden',
          Rect.fromLTRB(0, 0.3, 1, 1),
          cue: ['حديق', 'garden'],
        ),
      ],
    ),
    LivingPicture(
      image: _page('noor_clean', 4),
      ambient: PictureAmbient.sparkles,
      regions: [
        PictureRegion(
          'the friends',
          Rect.fromLTRB(0.08, 0.4, 0.92, 0.86),
          cue: ['اصدقاء', 'friends', 'فريق', 'team'],
          burst: PictureBurst.hearts,
        ),
        PictureRegion(
          'the garden',
          Rect.fromLTRB(0, 0, 1, 0.45),
          cue: ['garden'],
        ),
      ],
    ),
    LivingPicture(
      image: _page('noor_clean', 5),
      ambient: PictureAmbient.sparkles,
      regions: [
        PictureRegion(
          'the little flower',
          Rect.fromLTRB(0.42, 0.66, 0.72, 0.9),
          cue: ['ورد', 'flower'],
          burst: PictureBurst.sparkles,
        ),
        PictureRegion(
          'the watering can',
          Rect.fromLTRB(0.36, 0.5, 0.62, 0.7),
          cue: ['سقو', 'watered'],
        ),
        PictureRegion(
          'the children',
          Rect.fromLTRB(0.14, 0.35, 0.92, 0.9),
          cue: ['اطفال', 'children'],
        ),
      ],
    ),
    LivingPicture(
      image: _page('noor_clean', 6),
      ambient: PictureAmbient.sparkles,
      regions: [
        PictureRegion(
          'the wooden bench',
          Rect.fromLTRB(0.2, 0.5, 0.86, 0.86),
          cue: ['مقعد', 'bench'],
        ),
        PictureRegion(
          'the happy children',
          Rect.fromLTRB(0.2, 0.35, 0.86, 0.8),
          cue: ['نور', 'noor', 'سعاد', 'happy'],
          burst: PictureBurst.hearts,
        ),
        PictureRegion(
          'the trees in the breeze',
          Rect.fromLTRB(0, 0, 1, 0.42),
          cue: ['نسيم', 'breeze'],
        ),
      ],
    ),
  ],
  // مريم وصندوق الألعاب — Maryam and the Toy Box
  'maryam_toys': [
    LivingPicture(
      image: _page('maryam_toys', 1),
      ambient: PictureAmbient.sparkles,
      regions: [
        PictureRegion(
          'maryam',
          Rect.fromLTRB(0.46, 0.18, 0.84, 0.76),
          cue: ['مريم', 'maryam', 'سعيد', 'happy'],
          burst: PictureBurst.hearts,
        ),
        PictureRegion(
          'the new toy box',
          Rect.fromLTRB(0.2, 0.6, 0.64, 0.94),
          cue: ['صندوق', 'box'],
          burst: PictureBurst.sparkles,
        ),
        PictureRegion(
          'the dolls',
          Rect.fromLTRB(0.38, 0.48, 0.62, 0.72),
          cue: ['دمي', 'dolls'],
        ),
        PictureRegion(
          'the little cars',
          Rect.fromLTRB(0.52, 0.76, 0.84, 0.96),
          cue: ['سيار', 'cars'],
        ),
      ],
    ),
    LivingPicture(
      image: _page('maryam_toys', 2),
      regions: [
        PictureRegion(
          'fatimah',
          Rect.fromLTRB(0.6, 0.2, 0.94, 0.95),
          cue: ['فاطم', 'fatimah'],
        ),
        PictureRegion(
          'the toys she longs for',
          Rect.fromLTRB(0.48, 0.4, 0.7, 0.66),
          cue: ['العاب', 'toys'],
        ),
        PictureRegion(
          'maryam',
          Rect.fromLTRB(0.14, 0.14, 0.5, 0.9),
          cue: ['مريم', 'maryam'],
        ),
        PictureRegion(
          'the toys she hides',
          Rect.fromLTRB(0.12, 0.34, 0.5, 0.68),
          cue: ['اخفت', 'مفضل', 'hid', 'favourite'],
        ),
      ],
    ),
    LivingPicture(
      image: _page('maryam_toys', 3),
      regions: [
        PictureRegion(
          'maryam',
          Rect.fromLTRB(0.2, 0.36, 0.56, 0.96),
          cue: ['مريم', 'maryam'],
        ),
        PictureRegion(
          'the room',
          Rect.fromLTRB(0, 0, 1, 0.5),
          cue: ['تصرف', 'right'],
        ),
      ],
    ),
    LivingPicture(
      image: _page('maryam_toys', 4),
      ambient: PictureAmbient.sparkles,
      regions: [
        PictureRegion(
          'maryam',
          Rect.fromLTRB(0.04, 0.24, 0.56, 0.9),
          cue: ['مريم', 'maryam'],
        ),
        PictureRegion(
          'maryam\'s toys',
          Rect.fromLTRB(0.24, 0.62, 0.64, 0.96),
          cue: ['العاب', 'toys'],
          burst: PictureBurst.sparkles,
        ),
        PictureRegion(
          'her friend',
          Rect.fromLTRB(0.54, 0.3, 0.96, 0.96),
          cue: ['معا', 'together'],
        ),
        PictureRegion(
          'happy hearts',
          Rect.fromLTRB(0.1, 0.2, 0.9, 0.7),
          cue: ['قلوب', 'hearts'],
          burst: PictureBurst.hearts,
        ),
      ],
    ),
    LivingPicture(
      image: _page('maryam_toys', 5),
      ambient: PictureAmbient.sparkles,
      regions: [
        PictureRegion(
          'maryam at ease',
          Rect.fromLTRB(0.14, 0.26, 0.5, 0.82),
          cue: ['قلب', 'heart'],
          burst: PictureBurst.hearts,
        ),
        PictureRegion(
          'maryam',
          Rect.fromLTRB(0.14, 0.26, 0.5, 0.82),
          cue: ['مريم', 'maryam'],
        ),
        PictureRegion(
          'the box',
          Rect.fromLTRB(0, 0.72, 0.26, 1),
          cue: ['صندوق', 'box'],
        ),
        PictureRegion(
          'fatimah',
          Rect.fromLTRB(0.56, 0.34, 0.9, 0.82),
          cue: ['فاطم', 'fatimah'],
        ),
        PictureRegion(
          'the tower of blocks',
          Rect.fromLTRB(0.42, 0.06, 0.62, 0.84),
          cue: ['مكعب', 'برج', 'blocks', 'tower'],
          burst: PictureBurst.sparkles,
        ),
        PictureRegion(
          'laughing',
          Rect.fromLTRB(0.16, 0.24, 0.86, 0.6),
          cue: ['=تضحكان', 'laughing'],
          burst: PictureBurst.hearts,
        ),
      ],
    ),
    LivingPicture(
      image: _page('maryam_toys', 6),
      ambient: PictureAmbient.sparkles,
      regions: [
        PictureRegion(
          'the two friends hugging',
          Rect.fromLTRB(0.18, 0.18, 0.76, 0.92),
          cue: ['فاطم', 'ابتسام', 'fatimah', 'smile'],
          burst: PictureBurst.hearts,
        ),
        PictureRegion(
          'the shared toy box',
          Rect.fromLTRB(0.6, 0.54, 0.96, 0.94),
          cue: ['مشارك', 'sharing'],
          burst: PictureBurst.sparkles,
        ),
      ],
    ),
  ],
  // عمر ونور الصلاة — Umar and the Light of Salah
  'omar_prayer': [
    LivingPicture(
      image: _page('omar_prayer', 1),
      regions: [
        PictureRegion(
          'umar',
          Rect.fromLTRB(0.38, 0.44, 0.64, 0.86),
          cue: ['عمر', 'umar'],
        ),
        PictureRegion(
          'his friends',
          Rect.fromLTRB(0.1, 0.48, 0.9, 0.86),
          cue: ['friends'],
        ),
        PictureRegion(
          'the minaret',
          Rect.fromLTRB(0.56, 0.06, 0.74, 0.44),
          cue: ['اذان', 'adhan'],
          burst: PictureBurst.sparkles,
        ),
      ],
    ),
    LivingPicture(
      image: _page('omar_prayer', 2),
      regions: [
        PictureRegion(
          'umar',
          Rect.fromLTRB(0.44, 0.36, 0.72, 0.86),
          cue: ['عمر', 'umar'],
        ),
        PictureRegion(
          'his friends',
          Rect.fromLTRB(0.16, 0.42, 0.92, 0.88),
          cue: ['friends'],
        ),
        PictureRegion(
          'the masjid',
          Rect.fromLTRB(0.52, 0.14, 0.96, 0.44),
          cue: ['مسجد', 'masjid'],
          burst: PictureBurst.sparkles,
        ),
      ],
    ),
    LivingPicture(
      image: _page('omar_prayer', 3),
      regions: [
        PictureRegion(
          'umar',
          Rect.fromLTRB(0.2, 0.22, 0.6, 0.92),
          cue: ['عمر', 'umar'],
        ),
        PictureRegion(
          'the water of wudu',
          Rect.fromLTRB(0.55, 0.38, 0.96, 0.76),
          cue: ['وضوء', 'متوضا', 'wudu'],
          burst: PictureBurst.sparkles,
        ),
        PictureRegion(
          'his face',
          Rect.fromLTRB(0.24, 0.2, 0.52, 0.46),
          cue: ['وجه', 'face'],
        ),
      ],
    ),
    LivingPicture(
      image: _page('omar_prayer', 4),
      regions: [
        PictureRegion(
          'umar',
          Rect.fromLTRB(0.32, 0.48, 0.54, 0.96),
          cue: ['عمر', 'umar'],
        ),
        PictureRegion(
          'his father',
          Rect.fromLTRB(0.5, 0.28, 0.76, 0.96),
          cue: ['والده', 'father'],
        ),
        PictureRegion(
          'the masjid',
          Rect.fromLTRB(0, 0, 1, 0.6),
          cue: ['مسجد', 'masjid'],
        ),
      ],
    ),
    LivingPicture(
      image: _page('omar_prayer', 5),
      ambient: PictureAmbient.sparkles,
      regions: [
        PictureRegion(
          'umar',
          Rect.fromLTRB(0.36, 0.42, 0.7, 0.97),
          cue: ['عمر', 'umar', 'صدر', 'chest'],
          burst: PictureBurst.hearts,
        ),
        PictureRegion(
          'the light',
          Rect.fromLTRB(0.28, 0.04, 0.96, 0.62),
          cue: ['نور', 'light'],
          burst: PictureBurst.sparkles,
        ),
      ],
    ),
    LivingPicture(
      image: _page('omar_prayer', 6),
      ambient: PictureAmbient.sparkles,
      regions: [
        PictureRegion(
          'umar',
          Rect.fromLTRB(0.2, 0.3, 0.56, 0.9),
          cue: ['عمر', 'umar'],
        ),
        PictureRegion(
          'his friends',
          Rect.fromLTRB(0.5, 0.36, 0.96, 0.9),
          cue: ['اصدقاء', 'friends'],
          burst: PictureBurst.hearts,
        ),
        PictureRegion(
          'the masjid',
          Rect.fromLTRB(0.6, 0.18, 0.96, 0.44),
          cue: ['اذان', 'adhan'],
        ),
      ],
    ),
  ],
  // خديجة وحق الجار — Khadijah and the Right of the Neighbor
  'khadija_neighbor': [
    LivingPicture(
      image: _page('khadija_neighbor', 1),
      regions: [
        PictureRegion(
          'khadijah',
          Rect.fromLTRB(0.24, 0.2, 0.58, 0.86),
          cue: ['خديج', 'khadijah'],
        ),
        PictureRegion(
          'her mother',
          Rect.fromLTRB(0.5, 0.14, 0.9, 0.76),
          cue: ['والدت', 'ام', 'mother'],
        ),
        PictureRegion(
          'the warm soup',
          Rect.fromLTRB(0.42, 0.54, 0.8, 0.86),
          cue: ['حساء', 'soup'],
          burst: PictureBurst.sparkles,
        ),
      ],
    ),
    LivingPicture(
      image: _page('khadija_neighbor', 2),
      regions: [
        PictureRegion(
          'her mother',
          Rect.fromLTRB(0.14, 0.14, 0.62, 0.96),
          cue: ['ام', 'mother', 'smiled'],
        ),
        PictureRegion(
          'khadijah',
          Rect.fromLTRB(0.54, 0.24, 0.86, 0.98),
          cue: ['خديج', 'khadijah'],
        ),
        PictureRegion(
          'the dish',
          Rect.fromLTRB(0.44, 0.46, 0.72, 0.7),
          cue: ['طعام', 'food'],
        ),
      ],
    ),
    LivingPicture(
      image: _page('khadija_neighbor', 3),
      regions: [
        PictureRegion(
          'khadijah',
          Rect.fromLTRB(0.54, 0.38, 0.82, 0.9),
          cue: ['خديج', 'khadijah'],
        ),
        PictureRegion(
          'the warm plate',
          Rect.fromLTRB(0.54, 0.48, 0.72, 0.64),
          cue: ['طبق', 'plate'],
          burst: PictureBurst.sparkles,
        ),
        PictureRegion(
          'the door',
          Rect.fromLTRB(0.14, 0.28, 0.46, 0.82),
          cue: ['باب', 'door'],
        ),
      ],
    ),
    LivingPicture(
      image: _page('khadija_neighbor', 4),
      ambient: PictureAmbient.sparkles,
      regions: [
        PictureRegion(
          'grandma aisha',
          Rect.fromLTRB(0.44, 0.24, 0.9, 0.96),
          cue: ['جدة', 'grandma'],
          burst: PictureBurst.hearts,
        ),
        PictureRegion(
          'khadijah',
          Rect.fromLTRB(0.2, 0.54, 0.48, 0.96),
          cue: ['خديج', 'khadijah'],
        ),
      ],
    ),
    LivingPicture(
      image: _page('khadija_neighbor', 5),
      ambient: PictureAmbient.sparkles,
      regions: [
        PictureRegion(
          'khadijah, happy',
          Rect.fromLTRB(0.36, 0.34, 0.7, 0.96),
          cue: ['خديج', 'khadijah', 'قلب', 'heart'],
          burst: PictureBurst.hearts,
        ),
        PictureRegion(
          'the night sky',
          Rect.fromLTRB(0.45, 0, 0.9, 0.32),
          cue: ['سعاد', 'happiness'],
          burst: PictureBurst.sparkles,
        ),
      ],
    ),
    LivingPicture(
      image: _page('khadija_neighbor', 6),
      ambient: PictureAmbient.sparkles,
      regions: [
        PictureRegion(
          'the basket of fruit',
          Rect.fromLTRB(0.36, 0.4, 0.68, 0.66),
          cue: ['فواك', 'fruits'],
          burst: PictureBurst.sparkles,
        ),
        PictureRegion(
          'grandma aisha',
          Rect.fromLTRB(0.58, 0.24, 0.96, 0.96),
          cue: ['جدة', 'grandma'],
        ),
        PictureRegion(
          'khadijah',
          Rect.fromLTRB(0.24, 0.28, 0.6, 0.96),
          cue: ['خديج', 'khadijah'],
          burst: PictureBurst.hearts,
        ),
      ],
    ),
  ],
  // عبد الله وباسم الله — Abdullah and 'Bismillah'
  'abdullah_bismillah': [
    LivingPicture(
      image: _page('abdullah_bismillah', 1),
      regions: [
        PictureRegion(
          'abdullah',
          Rect.fromLTRB(0.1, 0.18, 0.52, 0.96),
          cue: ['عبد', 'abdullah'],
        ),
        PictureRegion(
          'the table',
          Rect.fromLTRB(0.34, 0.48, 0.98, 0.92),
          cue: ['مائد', 'table'],
        ),
        PictureRegion(
          'the fruit',
          Rect.fromLTRB(0.66, 0.48, 0.96, 0.72),
          cue: ['فاكه', 'fruit'],
          burst: PictureBurst.sparkles,
        ),
        PictureRegion(
          'his school bag',
          Rect.fromLTRB(0, 0.68, 0.22, 0.96),
          cue: ['مدرس', 'school'],
        ),
      ],
    ),
    LivingPicture(
      image: _page('abdullah_bismillah', 2),
      regions: [
        PictureRegion(
          'his father',
          Rect.fromLTRB(0.04, 0.14, 0.62, 0.86),
          cue: ['والده', 'father'],
        ),
        PictureRegion(
          'abdullah',
          Rect.fromLTRB(0.54, 0.28, 0.86, 0.82),
          cue: ['عبد', 'abdullah'],
        ),
      ],
    ),
    LivingPicture(
      image: _page('abdullah_bismillah', 3),
      ambient: PictureAmbient.sparkles,
      regions: [
        PictureRegion(
          'abdullah smiling',
          Rect.fromLTRB(0.28, 0.04, 0.76, 0.76),
          cue: ['عبد', 'abdullah', 'ابتسم', 'smiled'],
          burst: PictureBurst.hearts,
        ),
        PictureRegion(
          'the food in front of him',
          Rect.fromLTRB(0.18, 0.68, 0.86, 1),
          cue: ['امام', 'front'],
          burst: PictureBurst.sparkles,
        ),
      ],
    ),
    LivingPicture(
      image: _page('abdullah_bismillah', 4),
      regions: [
        PictureRegion(
          'abdullah',
          Rect.fromLTRB(0.18, 0.18, 0.62, 0.96),
          cue: ['عبد'],
        ),
        PictureRegion(
          'his food',
          Rect.fromLTRB(0.34, 0.58, 0.64, 0.74),
          cue: ['طعام', 'food'],
          burst: PictureBurst.sparkles,
        ),
      ],
    ),
    LivingPicture(
      image: _page('abdullah_bismillah', 5),
      ambient: PictureAmbient.sparkles,
      regions: [
        PictureRegion(
          'abdullah',
          Rect.fromLTRB(0.28, 0.22, 0.74, 0.76),
          cue: ['عبد', 'abdullah', 'حمد', 'alhamdulillah'],
          burst: PictureBurst.hearts,
        ),
        PictureRegion(
          'his hands',
          Rect.fromLTRB(0.4, 0.52, 0.64, 0.76),
          cue: ['مسح', 'wiped'],
        ),
      ],
    ),
    LivingPicture(
      image: _page('abdullah_bismillah', 6),
      ambient: PictureAmbient.sparkles,
      regions: [
        PictureRegion(
          'the family',
          Rect.fromLTRB(0.08, 0.28, 0.96, 0.96),
          cue: ['عائل', 'family'],
          burst: PictureBurst.hearts,
        ),
        PictureRegion(
          'abdullah',
          Rect.fromLTRB(0.4, 0.3, 0.62, 0.62),
          cue: ['عبد', 'abdullah'],
        ),
        PictureRegion(
          'the table',
          Rect.fromLTRB(0.18, 0.58, 0.96, 0.96),
          cue: ['مائد', 'table'],
          burst: PictureBurst.sparkles,
        ),
      ],
    ),
  ],
  // عائشة وأدب الاستئذان — Aisha and the Adab of Isti'dhan
  'aisha_permission': [
    LivingPicture(
      image: _page('aisha_permission', 1),
      regions: [
        PictureRegion(
          'aisha',
          Rect.fromLTRB(0.22, 0.15, 0.6, 0.95),
          cue: ['عائش', 'aisha'],
        ),
        PictureRegion(
          'the door',
          Rect.fromLTRB(0.52, 0, 0.8, 0.95),
          cue: ['باب', 'door'],
        ),
        PictureRegion(
          'the books',
          Rect.fromLTRB(0.82, 0.55, 1, 0.95),
          cue: ['كتاب', 'book'],
          burst: PictureBurst.sparkles,
        ),
      ],
    ),
    LivingPicture(
      image: _page('aisha_permission', 2),
      ambient: PictureAmbient.sparkles,
      regions: [
        PictureRegion(
          'remembering her father',
          Rect.fromLTRB(0.3, 0, 0.72, 0.38),
          cue: ['ابي', 'father'],
          burst: PictureBurst.sparkles,
        ),
        PictureRegion(
          'aisha',
          Rect.fromLTRB(0.3, 0.38, 0.6, 0.9),
          cue: ['عائش', 'aisha'],
        ),
      ],
    ),
    LivingPicture(
      image: _page('aisha_permission', 3),
      regions: [
        PictureRegion(
          'aisha',
          Rect.fromLTRB(0.2, 0.12, 0.6, 0.95),
          cue: ['عائش', 'aisha'],
        ),
        PictureRegion(
          'the door, knocked gently',
          Rect.fromLTRB(0.5, 0, 0.92, 0.95),
          cue: ['باب', '=طرقات', 'door', 'knocked'],
          burst: PictureBurst.sparkles,
        ),
      ],
    ),
    LivingPicture(
      image: _page('aisha_permission', 4),
      ambient: PictureAmbient.sparkles,
      regions: [
        PictureRegion(
          'her mother',
          Rect.fromLTRB(0.5, 0.24, 0.9, 0.86),
          cue: ['ام', 'mother'],
          burst: PictureBurst.hearts,
        ),
        PictureRegion(
          'aisha',
          Rect.fromLTRB(0.12, 0.3, 0.42, 0.95),
          cue: ['عائش', 'aisha'],
        ),
        PictureRegion(
          'the open door',
          Rect.fromLTRB(0, 0, 0.22, 0.95),
          cue: ['=دخلت', 'entered'],
        ),
      ],
    ),
    LivingPicture(
      image: _page('aisha_permission', 5),
      ambient: PictureAmbient.sparkles,
      regions: [
        PictureRegion(
          'her mother',
          Rect.fromLTRB(0.44, 0.14, 0.86, 0.95),
          cue: ['ام', 'mother'],
        ),
        PictureRegion(
          'aisha',
          Rect.fromLTRB(0.28, 0.3, 0.56, 0.9),
          cue: ['عائش', 'aisha'],
        ),
        PictureRegion(
          'the midday sun',
          Rect.fromLTRB(0, 0, 0.46, 0.4),
          cue: ['ظهير', 'midday'],
          burst: PictureBurst.sparkles,
        ),
        PictureRegion(
          'the two of them',
          Rect.fromLTRB(0.26, 0.14, 0.86, 0.7),
          cue: ['محب', 'love'],
          burst: PictureBurst.hearts,
        ),
      ],
    ),
    LivingPicture(
      image: _page('aisha_permission', 6),
      ambient: PictureAmbient.sparkles,
      regions: [
        PictureRegion(
          'aisha',
          Rect.fromLTRB(0.48, 0.14, 0.74, 0.92),
          cue: ['عائش', 'aisha'],
        ),
        PictureRegion(
          'her sisters',
          Rect.fromLTRB(0.16, 0.34, 0.52, 0.95),
          cue: ['اخوات', 'sisters'],
          burst: PictureBurst.hearts,
        ),
        PictureRegion(
          'the door',
          Rect.fromLTRB(0.55, 0, 0.9, 0.95),
          cue: ['غرف', 'room'],
        ),
      ],
    ),
  ],
  // ياسين وعجائب الخالق — Yaseen and the Wonders of the Creator
  'yaseen_creation': [
    LivingPicture(
      image: _page('yaseen_creation', 1),
      regions: [
        PictureRegion(
          'his father',
          Rect.fromLTRB(0.54, 0.04, 0.96, 0.9),
          cue: ['والده', 'father'],
        ),
        PictureRegion(
          'yaseen',
          Rect.fromLTRB(0.24, 0.36, 0.56, 0.86),
          cue: ['ياسين', 'yaseen'],
        ),
        PictureRegion(
          'the ant and its grain',
          Rect.fromLTRB(0.44, 0.58, 0.64, 0.76),
          cue: ['نمل', 'قمح', 'ant', 'wheat'],
          burst: PictureBurst.sparkles,
        ),
        PictureRegion(
          'the garden',
          Rect.fromLTRB(0, 0, 1, 0.4),
          cue: ['حديق', 'garden'],
        ),
      ],
    ),
    LivingPicture(
      image: _page('yaseen_creation', 2),
      regions: [
        PictureRegion(
          'yaseen',
          Rect.fromLTRB(0.14, 0.34, 0.56, 0.86),
          cue: ['ياسين', 'yaseen'],
        ),
        PictureRegion(
          'the ant',
          Rect.fromLTRB(0.4, 0.58, 0.64, 0.76),
          cue: ['نمل', 'ant'],
          burst: PictureBurst.sparkles,
        ),
        PictureRegion(
          'his father',
          Rect.fromLTRB(0.44, 0.08, 0.96, 0.86),
          cue: ['ابي', 'father'],
        ),
      ],
    ),
    LivingPicture(
      image: _page('yaseen_creation', 3),
      ambient: PictureAmbient.sparkles,
      regions: [
        PictureRegion(
          'his father, smiling',
          Rect.fromLTRB(0.5, 0.08, 0.96, 0.86),
          cue: ['=والد', 'father'],
          burst: PictureBurst.hearts,
        ),
        PictureRegion(
          'yaseen',
          Rect.fromLTRB(0.14, 0.24, 0.52, 0.86),
          cue: ['ياسين', 'yaseen'],
        ),
      ],
    ),
    LivingPicture(
      image: _page('yaseen_creation', 4),
      ambient: PictureAmbient.sparkles,
      regions: [
        PictureRegion(
          'the stars',
          Rect.fromLTRB(0.24, 0, 1, 0.46),
          cue: ['نجوم', 'stars'],
          burst: PictureBurst.sparkles,
        ),
        PictureRegion(
          'the trees',
          Rect.fromLTRB(0, 0, 0.32, 0.62),
          cue: ['اشجار', 'trees'],
        ),
        PictureRegion(
          'the flowers',
          Rect.fromLTRB(0.68, 0.54, 1, 1),
          cue: ['ازهار', 'flowers'],
        ),
        PictureRegion(
          'yaseen',
          Rect.fromLTRB(0.24, 0.48, 0.56, 0.96),
          cue: ['ياسين', 'yaseen'],
        ),
      ],
    ),
    LivingPicture(
      image: _page('yaseen_creation', 5),
      ambient: PictureAmbient.sparkles,
      regions: [
        PictureRegion(
          'yaseen',
          Rect.fromLTRB(0.18, 0.38, 0.62, 0.96),
          cue: ['ياسين', 'yaseen'],
          burst: PictureBurst.hearts,
        ),
        PictureRegion(
          'the birds',
          Rect.fromLTRB(0.3, 0, 1, 0.42),
          cue: ['مخلوق', 'creature'],
          burst: PictureBurst.sparkles,
        ),
      ],
    ),
    LivingPicture(
      image: _page('yaseen_creation', 6),
      ambient: PictureAmbient.sparkles,
      regions: [
        PictureRegion(
          'yaseen',
          Rect.fromLTRB(0.38, 0.54, 0.96, 0.96),
          cue: ['ياسين', 'yaseen'],
        ),
        PictureRegion(
          'allah\'s creations',
          Rect.fromLTRB(0, 0.2, 1, 0.62),
          cue: ['مخلوقات', 'creations'],
          burst: PictureBurst.sparkles,
        ),
      ],
    ),
  ],
  // فاطمة وزهرة البر — Fatima and the Flower of Birr
  'fatima_parents': [
    LivingPicture(
      image: _page('fatima_parents', 1),
      regions: [
        PictureRegion(
          'her mother, tired',
          Rect.fromLTRB(0.14, 0.14, 0.6, 0.86),
          cue: ['والدة', 'mother'],
        ),
        PictureRegion(
          'the sofa',
          Rect.fromLTRB(0, 0.24, 0.76, 0.9),
          cue: ['اريك', 'sofa'],
        ),
        PictureRegion(
          'fatima',
          Rect.fromLTRB(0.6, 0.54, 0.9, 0.94),
          cue: ['فاطم', 'fatima'],
        ),
      ],
    ),
    LivingPicture(
      image: _page('fatima_parents', 2),
      regions: [
        PictureRegion(
          'fatima',
          Rect.fromLTRB(0.54, 0.14, 0.86, 0.86),
          cue: ['فاطم', 'fatima', 'سرور', 'happiness'],
          burst: PictureBurst.hearts,
        ),
        PictureRegion(
          'her mother',
          Rect.fromLTRB(0.06, 0.1, 0.56, 0.88),
          cue: ['امها', 'mother'],
        ),
      ],
    ),
    LivingPicture(
      image: _page('fatima_parents', 3),
      ambient: PictureAmbient.sparkles,
      regions: [
        PictureRegion(
          'fatima',
          Rect.fromLTRB(0.18, 0.4, 0.56, 0.92),
          cue: ['فاطم', 'fatima'],
        ),
        PictureRegion(
          'the toy basket',
          Rect.fromLTRB(0.18, 0.66, 0.52, 0.96),
          cue: ['العاب', 'toys'],
          burst: PictureBurst.sparkles,
        ),
        PictureRegion(
          'the warm cup',
          Rect.fromLTRB(0.86, 0.48, 0.99, 0.64),
          cue: ['كوب', 'cup'],
          burst: PictureBurst.sparkles,
        ),
      ],
    ),
    LivingPicture(
      image: _page('fatima_parents', 4),
      ambient: PictureAmbient.sparkles,
      regions: [
        PictureRegion(
          'the hug',
          Rect.fromLTRB(0.18, 0.14, 0.72, 0.9),
          cue: ['ضمت', 'ام', 'hugged', 'mother'],
          burst: PictureBurst.hearts,
        ),
      ],
    ),
    LivingPicture(
      image: _page('fatima_parents', 5),
      ambient: PictureAmbient.sparkles,
      regions: [
        PictureRegion(
          'her father',
          Rect.fromLTRB(0.18, 0.14, 0.66, 0.95),
          cue: ['=والد', 'father', 'فخر', 'proud'],
        ),
        PictureRegion(
          'the rose',
          Rect.fromLTRB(0.45, 0.4, 0.6, 0.6),
          cue: ['زهر', 'rose'],
          burst: PictureBurst.sparkles,
        ),
        PictureRegion(
          'fatima',
          Rect.fromLTRB(0.48, 0.4, 0.74, 0.94),
          cue: ['فاطم', 'fatima'],
          burst: PictureBurst.hearts,
        ),
      ],
    ),
    LivingPicture(
      image: _page('fatima_parents', 6),
      ambient: PictureAmbient.sparkles,
      regions: [
        PictureRegion(
          'fatima',
          Rect.fromLTRB(0.14, 0.3, 0.46, 0.95),
          cue: ['فاطم', 'fatima'],
          burst: PictureBurst.hearts,
        ),
        PictureRegion(
          'her parents',
          Rect.fromLTRB(0.44, 0.14, 0.96, 0.9),
          cue: ['ابيها', 'امها', 'father', 'mother'],
        ),
        PictureRegion(
          'the rose',
          Rect.fromLTRB(0.84, 0.44, 0.99, 0.66),
          cue: ['محب', 'love'],
          burst: PictureBurst.sparkles,
        ),
      ],
    ),
  ],
  // بلال وقلب التسامح — Bilal and the Heart of Forgiveness
  'bilal_forgiveness': [
    LivingPicture(
      image: _page('bilal_forgiveness', 1),
      regions: [
        PictureRegion(
          'bilal',
          Rect.fromLTRB(0.06, 0.24, 0.46, 0.92),
          cue: ['بلال', 'bilal'],
        ),
        PictureRegion(
          'his painting',
          Rect.fromLTRB(0.2, 0.54, 0.56, 0.7),
          cue: ['لوح', 'painting'],
          burst: PictureBurst.sparkles,
        ),
        PictureRegion(
          'tariq',
          Rect.fromLTRB(0.46, 0.2, 0.9, 0.9),
          cue: ['طارق', 'tariq'],
        ),
        PictureRegion(
          'the juice',
          Rect.fromLTRB(0.44, 0.48, 0.64, 0.66),
          cue: ['عصير', 'juice'],
        ),
      ],
    ),
    LivingPicture(
      image: _page('bilal_forgiveness', 2),
      regions: [
        PictureRegion(
          'bilal',
          Rect.fromLTRB(0.1, 0.2, 0.46, 0.86),
          cue: ['بلال', 'bilal'],
        ),
        PictureRegion(
          'tariq, sorry',
          Rect.fromLTRB(0.52, 0.14, 0.86, 0.9),
          cue: ['طارق', 'اسف', 'tariq', 'sorry'],
        ),
      ],
    ),
    LivingPicture(
      image: _page('bilal_forgiveness', 3),
      regions: [
        PictureRegion(
          'bilal, calm',
          Rect.fromLTRB(0.08, 0.2, 0.56, 0.95),
          cue: ['بلال', 'bilal'],
        ),
      ],
    ),
    LivingPicture(
      image: _page('bilal_forgiveness', 4),
      ambient: PictureAmbient.sparkles,
      regions: [
        PictureRegion(
          'bilal smiling',
          Rect.fromLTRB(0.14, 0.14, 0.52, 0.9),
          cue: ['بلال', 'ابتسم', 'bilal', 'smiled'],
          burst: PictureBurst.hearts,
        ),
        PictureRegion(
          'tariq',
          Rect.fromLTRB(0.54, 0.2, 0.88, 0.9),
          cue: ['طارق', 'tariq'],
        ),
        PictureRegion(
          'a new sheet',
          Rect.fromLTRB(0.28, 0.66, 0.76, 0.96),
          cue: ['لوح', 'picture'],
          burst: PictureBurst.sparkles,
        ),
      ],
    ),
    LivingPicture(
      image: _page('bilal_forgiveness', 5),
      ambient: PictureAmbient.sparkles,
      regions: [
        PictureRegion(
          'tariq, surprised',
          Rect.fromLTRB(0.56, 0.14, 0.96, 0.9),
          cue: ['طارق', 'tariq'],
        ),
        PictureRegion(
          'bilal',
          Rect.fromLTRB(0.08, 0.2, 0.5, 0.9),
          cue: ['بلال', 'bilal'],
        ),
        PictureRegion(
          'the table',
          Rect.fromLTRB(0.22, 0.66, 0.86, 0.96),
          cue: ['طاول', 'table'],
        ),
        PictureRegion(
          'the shared colours',
          Rect.fromLTRB(0.44, 0.48, 0.72, 0.66),
          cue: ['الوان', 'colors'],
          burst: PictureBurst.sparkles,
        ),
      ],
    ),
    LivingPicture(
      image: _page('bilal_forgiveness', 6),
      ambient: PictureAmbient.sparkles,
      regions: [
        PictureRegion(
          'bilal',
          Rect.fromLTRB(0.14, 0.14, 0.56, 0.95),
          cue: ['بلال', 'bilal', 'قلب', 'heart'],
          burst: PictureBurst.hearts,
        ),
        PictureRegion(
          'their new painting',
          Rect.fromLTRB(0.38, 0.54, 0.88, 0.86),
          cue: ['محب', 'love'],
          burst: PictureBurst.sparkles,
        ),
      ],
    ),
  ],
  // حمزة وأمانة الكلمة — Hamza and the Amanah of the Word
  'hamza_truth': [
    LivingPicture(
      image: _page('hamza_truth', 1),
      regions: [
        PictureRegion(
          'hamza',
          Rect.fromLTRB(0.66, 0.26, 0.92, 0.82),
          cue: ['حمز', 'hamza'],
        ),
        PictureRegion(
          'the boy who fell',
          Rect.fromLTRB(0.24, 0.6, 0.64, 0.86),
          cue: ['طفل', 'child'],
        ),
        PictureRegion(
          'the children laughing',
          Rect.fromLTRB(0, 0.24, 0.5, 0.66),
          cue: ['اطفال', 'children'],
        ),
        PictureRegion(
          'the playground',
          Rect.fromLTRB(0.3, 0.08, 0.82, 0.5),
          cue: ['ملعب', 'playground'],
          burst: PictureBurst.sparkles,
        ),
      ],
    ),
    LivingPicture(
      image: _page('hamza_truth', 2),
      regions: [
        PictureRegion(
          'hamza',
          Rect.fromLTRB(0.28, 0.24, 0.66, 1),
          cue: ['حمز', 'hamza'],
        ),
        PictureRegion(
          'his quran circle',
          Rect.fromLTRB(0.58, 0, 1, 0.4),
          cue: ['حلقت', 'circle'],
          burst: PictureBurst.sparkles,
        ),
      ],
    ),
    LivingPicture(
      image: _page('hamza_truth', 3),
      ambient: PictureAmbient.sparkles,
      regions: [
        PictureRegion(
          'hamza',
          Rect.fromLTRB(0.38, 0.14, 0.8, 0.86),
          cue: ['حمز', 'hamza'],
        ),
        PictureRegion(
          'the boy he helps up',
          Rect.fromLTRB(0.16, 0.44, 0.56, 0.9),
          cue: ['طفل', 'child'],
          burst: PictureBurst.hearts,
        ),
        PictureRegion(
          'his friends',
          Rect.fromLTRB(0, 0.2, 1, 0.82),
          cue: ['اصدقائ', 'friends'],
        ),
        PictureRegion(
          'his hand',
          Rect.fromLTRB(0.4, 0.48, 0.62, 0.66),
          cue: ['=يده', 'hand'],
          burst: PictureBurst.sparkles,
        ),
      ],
    ),
    LivingPicture(
      image: _page('hamza_truth', 4),
      ambient: PictureAmbient.sparkles,
      regions: [
        PictureRegion(
          'the children',
          Rect.fromLTRB(0, 0.3, 0.66, 0.95),
          cue: ['اطفال', 'children'],
        ),
        PictureRegion(
          'their friend',
          Rect.fromLTRB(0.46, 0.3, 0.72, 0.9),
          cue: ['صديق', 'friend'],
          burst: PictureBurst.hearts,
        ),
        PictureRegion(
          'the ball',
          Rect.fromLTRB(0.44, 0.74, 0.62, 0.92),
          cue: ['لعب', 'play'],
        ),
      ],
    ),
    LivingPicture(
      image: _page('hamza_truth', 5),
      ambient: PictureAmbient.sparkles,
      regions: [
        PictureRegion(
          'hamza, proud',
          Rect.fromLTRB(0.28, 0.1, 0.72, 0.95),
          cue: ['حمز', 'hamza'],
          burst: PictureBurst.hearts,
        ),
        PictureRegion(
          'home',
          Rect.fromLTRB(0, 0, 1, 0.6),
          cue: ['منزل', 'home'],
        ),
      ],
    ),
    LivingPicture(
      image: _page('hamza_truth', 6),
      ambient: PictureAmbient.sparkles,
      regions: [
        PictureRegion(
          'hamza and his friends',
          Rect.fromLTRB(0.04, 0.4, 0.96, 0.95),
          cue: ['اصدقاؤ', 'friends'],
          burst: PictureBurst.hearts,
        ),
        PictureRegion(
          'the school',
          Rect.fromLTRB(0.3, 0.08, 1, 0.46),
          cue: ['مدرس', 'school'],
          burst: PictureBurst.sparkles,
        ),
        PictureRegion(
          'hamza',
          Rect.fromLTRB(0.26, 0.4, 0.46, 0.9),
          cue: ['حمز', 'hamza'],
        ),
      ],
    ),
  ],
  // بدر واللعبة المكسورة — Badr and the Broken Toy
  'badr_broken_toy': [
    LivingPicture(
      image: _page('badr_broken_toy', 1),
      regions: [
        PictureRegion(
          'badr',
          Rect.fromLTRB(0.38, 0.24, 0.76, 0.86),
          cue: ['بدر', 'badr'],
        ),
        PictureRegion(
          'the blue racing car',
          Rect.fromLTRB(0.2, 0.7, 0.56, 0.93),
          cue: ['سيار', 'car'],
          burst: PictureBurst.sparkles,
        ),
        PictureRegion(
          'the carpet',
          Rect.fromLTRB(0, 0.66, 1, 1),
          cue: ['سجاد', 'carpet'],
        ),
      ],
    ),
    LivingPicture(
      image: _page('badr_broken_toy', 2),
      regions: [
        PictureRegion(
          'the broken wheel',
          Rect.fromLTRB(0.2, 0.7, 0.6, 0.93),
          cue: ['عجلات', 'wheels'],
          burst: PictureBurst.sparkles,
        ),
        PictureRegion(
          'the table',
          Rect.fromLTRB(0, 0.46, 0.34, 0.72),
          cue: ['طاول', 'table'],
        ),
        PictureRegion(
          'badr, scared',
          Rect.fromLTRB(0.44, 0.26, 0.8, 0.84),
          cue: ['بدر', 'badr', 'خوف', 'scared'],
        ),
        PictureRegion(
          'the sofa',
          Rect.fromLTRB(0, 0.18, 0.46, 0.52),
          cue: ['اريك', 'sofa'],
        ),
      ],
    ),
    LivingPicture(
      image: _page('badr_broken_toy', 3),
      regions: [
        PictureRegion(
          'badr',
          Rect.fromLTRB(0.36, 0.24, 0.72, 0.92),
          cue: ['بدر', 'badr'],
        ),
        PictureRegion(
          'his father\'s photo',
          Rect.fromLTRB(0.66, 0.18, 0.82, 0.34),
          cue: ['والده', 'father'],
          burst: PictureBurst.sparkles,
        ),
        PictureRegion(
          'the broken car',
          Rect.fromLTRB(0.34, 0.52, 0.62, 0.74),
          cue: ['حقيق', 'truth'],
        ),
      ],
    ),
    LivingPicture(
      image: _page('badr_broken_toy', 4),
      ambient: PictureAmbient.sparkles,
      regions: [
        PictureRegion(
          'badr',
          Rect.fromLTRB(0.28, 0.3, 0.64, 0.92),
          cue: ['بدر', 'badr'],
        ),
        PictureRegion(
          'his brother omar',
          Rect.fromLTRB(0.54, 0.28, 0.86, 0.92),
          cue: ['عمر', 'omar', 'احتضن', 'hugged'],
          burst: PictureBurst.hearts,
        ),
        PictureRegion(
          'dad with the toolbox',
          Rect.fromLTRB(0.16, 0.1, 0.4, 0.64),
          cue: ['ابي', 'dad'],
          burst: PictureBurst.sparkles,
        ),
        PictureRegion(
          'the car',
          Rect.fromLTRB(0.4, 0.58, 0.66, 0.74),
          cue: ['سيار', 'car'],
        ),
      ],
    ),
  ],
  // سارة ونبتة الريحان — Sarah and the Basil Plant
  'sarah_basil_sprout': [
    LivingPicture(
      image: _page('sarah_basil_sprout', 1),
      regions: [
        PictureRegion(
          'sarah',
          Rect.fromLTRB(0.44, 0.16, 0.86, 0.84),
          cue: ['سار', 'sarah'],
        ),
        PictureRegion(
          'the plant pot',
          Rect.fromLTRB(0.14, 0.38, 0.44, 0.86),
          cue: ['حوض', 'pot'],
        ),
        PictureRegion(
          'the dry leaves and tissues',
          Rect.fromLTRB(0, 0.72, 0.52, 0.96),
          cue: ['مناديل', 'اوراق', 'tissues', 'leaves'],
        ),
        PictureRegion(
          'the yard',
          Rect.fromLTRB(0.18, 0.12, 0.62, 0.42),
          cue: ['فسح', 'break'],
        ),
      ],
    ),
    LivingPicture(
      image: _page('sarah_basil_sprout', 2),
      regions: [
        PictureRegion(
          'sarah',
          Rect.fromLTRB(0.4, 0.16, 0.76, 0.82),
          cue: ['سار', 'sarah'],
        ),
        PictureRegion(
          'hind',
          Rect.fromLTRB(0.64, 0.36, 0.96, 0.86),
          cue: ['هند', 'hind'],
        ),
        PictureRegion(
          'the drooping plant',
          Rect.fromLTRB(0.14, 0.38, 0.44, 0.86),
          cue: ['نبت', 'نبات', 'plant'],
        ),
      ],
    ),
    LivingPicture(
      image: _page('sarah_basil_sprout', 3),
      ambient: PictureAmbient.sparkles,
      regions: [
        PictureRegion(
          'sarah',
          Rect.fromLTRB(0.46, 0.16, 0.84, 0.86),
          cue: ['سار', 'sarah'],
        ),
        PictureRegion(
          'the watering can',
          Rect.fromLTRB(0.44, 0.46, 0.72, 0.66),
          cue: ['رشاش', 'watering'],
          burst: PictureBurst.sparkles,
        ),
        PictureRegion(
          'the bin',
          Rect.fromLTRB(0.64, 0.58, 0.92, 0.76),
          cue: ['=سلة', 'bin'],
        ),
        PictureRegion(
          'the dry soil',
          Rect.fromLTRB(0.18, 0.58, 0.44, 0.74),
          cue: ['ترب', 'soil'],
        ),
      ],
    ),
    LivingPicture(
      image: _page('sarah_basil_sprout', 4),
      ambient: PictureAmbient.sparkles,
      regions: [
        PictureRegion(
          'the basil',
          Rect.fromLTRB(0.14, 0.58, 0.44, 0.96),
          cue: ['ريحان', 'basil'],
          burst: PictureBurst.sparkles,
        ),
        PictureRegion(
          'sarah',
          Rect.fromLTRB(0.28, 0.28, 0.56, 0.84),
          cue: ['سار', 'sarah', 'happy'],
          burst: PictureBurst.hearts,
        ),
        PictureRegion(
          'the teacher',
          Rect.fromLTRB(0.5, 0.18, 0.84, 0.92),
          cue: ['معلم', 'teacher'],
        ),
        PictureRegion(
          'the yard',
          Rect.fromLTRB(0, 0, 1, 0.28),
          cue: ['رائح', 'smell'],
          burst: PictureBurst.sparkles,
        ),
      ],
    ),
  ],
  // تميم وبركان الغضب — Tamim and the Volcano of Anger
  'tamim_anger_volcano': [
    LivingPicture(
      image: _page('tamim_anger_volcano', 1),
      regions: [
        PictureRegion(
          'the falling tower',
          Rect.fromLTRB(0.28, 0.26, 0.64, 0.72),
          cue: ['برج', 'مكعب', 'tower', 'blocks'],
          burst: PictureBurst.sparkles,
        ),
        PictureRegion(
          'tamim',
          Rect.fromLTRB(0.58, 0.18, 0.9, 0.86),
          cue: ['تميم', 'tamim'],
        ),
        PictureRegion(
          'the table',
          Rect.fromLTRB(0.24, 0.58, 0.76, 0.92),
          cue: ['طاول', 'table'],
        ),
      ],
    ),
    LivingPicture(
      image: _page('tamim_anger_volcano', 2),
      regions: [
        PictureRegion(
          'tamim',
          Rect.fromLTRB(0.54, 0.16, 0.86, 0.84),
          cue: ['تميم', 'tamim'],
        ),
        PictureRegion(
          'the red heat',
          Rect.fromLTRB(0.24, 0.08, 0.56, 0.56),
          cue: ['بركان', 'volcano'],
        ),
        PictureRegion(
          'the blocks',
          Rect.fromLTRB(0.24, 0.58, 0.82, 0.96),
          cue: ['مكعب', 'blocks'],
        ),
      ],
    ),
    LivingPicture(
      image: _page('tamim_anger_volcano', 3),
      regions: [
        PictureRegion(
          'his mother',
          Rect.fromLTRB(0.54, 0.24, 0.98, 0.9),
          cue: ['والدت', 'mother'],
        ),
        PictureRegion(
          'tamim',
          Rect.fromLTRB(0.3, 0.36, 0.64, 0.9),
          cue: ['تميم', 'tamim'],
        ),
      ],
    ),
    LivingPicture(
      image: _page('tamim_anger_volcano', 4),
      ambient: PictureAmbient.sparkles,
      regions: [
        PictureRegion(
          'washing his face',
          Rect.fromLTRB(0.04, 0.24, 0.46, 0.96),
          cue: ['غسل', 'washed'],
          burst: PictureBurst.sparkles,
        ),
        PictureRegion(
          'tamim and his tower',
          Rect.fromLTRB(0.48, 0.24, 0.86, 0.92),
          cue: ['تميم', 'برج', 'tamim', 'tower'],
          burst: PictureBurst.hearts,
        ),
        PictureRegion(
          'his mother',
          Rect.fromLTRB(0.78, 0.28, 1, 0.96),
          cue: ['ام', 'mother'],
        ),
      ],
    ),
  ],
  // نورة وصندوق المشاركة — Noura and the Sharing Box
  'noura_sharing_box': [
    LivingPicture(
      image: _page('noura_sharing_box', 1),
      ambient: PictureAmbient.sparkles,
      regions: [
        PictureRegion(
          'noura',
          Rect.fromLTRB(0.28, 0.34, 0.66, 0.86),
          cue: ['نور', 'noura'],
        ),
        PictureRegion(
          'the box of colours',
          Rect.fromLTRB(0.54, 0.46, 0.76, 0.66),
          cue: ['الوان', 'pencils'],
          burst: PictureBurst.sparkles,
        ),
        PictureRegion(
          'the drawing paper',
          Rect.fromLTRB(0.24, 0.64, 0.82, 0.9),
          cue: ['رسم', 'draw'],
        ),
      ],
    ),
    LivingPicture(
      image: _page('noura_sharing_box', 2),
      regions: [
        PictureRegion(
          'layla',
          Rect.fromLTRB(0.24, 0.34, 0.52, 0.86),
          cue: ['ليلي', 'layla'],
        ),
        PictureRegion(
          'noura',
          Rect.fromLTRB(0.54, 0.34, 0.86, 0.86),
          cue: ['نور', 'noura'],
        ),
        PictureRegion(
          'the pencil box',
          Rect.fromLTRB(0.46, 0.58, 0.72, 0.74),
          cue: ['الوان'],
        ),
      ],
    ),
    LivingPicture(
      image: _page('noura_sharing_box', 3),
      regions: [
        PictureRegion(
          'noura, thinking',
          Rect.fromLTRB(0.6, 0.18, 0.92, 0.86),
          cue: ['نور', 'noura'],
        ),
        PictureRegion(
          'the pencils',
          Rect.fromLTRB(0.48, 0.52, 0.76, 0.74),
          cue: ['الوان', 'pencils'],
          burst: PictureBurst.sparkles,
        ),
        PictureRegion(
          'her classmate',
          Rect.fromLTRB(0.18, 0.34, 0.52, 0.86),
          cue: ['قلوب', 'heart'],
        ),
      ],
    ),
    LivingPicture(
      image: _page('noura_sharing_box', 4),
      ambient: PictureAmbient.sparkles,
      regions: [
        PictureRegion(
          'the rainbow picture',
          Rect.fromLTRB(0.28, 0.62, 0.66, 0.86),
          cue: ['لوح', 'picture'],
          burst: PictureBurst.sparkles,
        ),
        PictureRegion(
          'layla laughing',
          Rect.fromLTRB(0.24, 0.34, 0.52, 0.76),
          cue: ['ليلي', 'layla'],
          burst: PictureBurst.hearts,
        ),
        PictureRegion(
          'noura',
          Rect.fromLTRB(0.54, 0.3, 0.86, 0.86),
          cue: ['نور', 'noura'],
        ),
        PictureRegion(
          'the shared pencils',
          Rect.fromLTRB(0.48, 0.58, 0.8, 0.76),
          cue: ['الوان', 'pencils'],
        ),
      ],
    ),
  ],
  // سلمان وسر الأمانة — Salman and the Secret of Trust
  'salman_secret_trust': [
    LivingPicture(
      image: _page('salman_secret_trust', 1),
      regions: [
        PictureRegion(
          'salman',
          Rect.fromLTRB(0.14, 0.34, 0.52, 0.96),
          cue: ['سلمان', 'salman'],
        ),
        PictureRegion(
          'the shiny wallet',
          Rect.fromLTRB(0.4, 0.74, 0.62, 0.9),
          cue: ['محفظ', 'wallet'],
          burst: PictureBurst.sparkles,
        ),
        PictureRegion(
          'the corridor',
          Rect.fromLTRB(0, 0, 1, 0.6),
          cue: ['ممر', 'corridor'],
        ),
      ],
    ),
    LivingPicture(
      image: _page('salman_secret_trust', 2),
      regions: [
        PictureRegion(
          'salman',
          Rect.fromLTRB(0.14, 0.34, 0.56, 0.96),
          cue: ['سلمان', 'salman'],
        ),
        PictureRegion(
          'the wallet',
          Rect.fromLTRB(0.46, 0.54, 0.68, 0.74),
          cue: ['محفظ', 'wallet'],
          burst: PictureBurst.sparkles,
        ),
        PictureRegion(
          'his heart',
          Rect.fromLTRB(0.24, 0.48, 0.46, 0.7),
          cue: ['قلب', 'heart'],
          burst: PictureBurst.hearts,
        ),
      ],
    ),
    LivingPicture(
      image: _page('salman_secret_trust', 3),
      regions: [
        PictureRegion(
          'the teacher',
          Rect.fromLTRB(0.54, 0.16, 0.86, 0.6),
          cue: ['معلم', 'teacher'],
        ),
        PictureRegion(
          'salman',
          Rect.fromLTRB(0.18, 0.34, 0.52, 0.96),
          cue: ['سلمان', 'salman'],
        ),
        PictureRegion(
          'the wallet',
          Rect.fromLTRB(0.46, 0.54, 0.66, 0.7),
          cue: ['محفظ', 'wallet'],
          burst: PictureBurst.sparkles,
        ),
      ],
    ),
    LivingPicture(
      image: _page('salman_secret_trust', 4),
      ambient: PictureAmbient.sparkles,
      regions: [
        PictureRegion(
          'the head teacher',
          Rect.fromLTRB(0.24, 0.22, 0.5, 0.86),
          cue: ['مدير', 'head'],
        ),
        PictureRegion(
          'salman',
          Rect.fromLTRB(0.46, 0.3, 0.72, 0.86),
          cue: ['سلمان', 'salman'],
        ),
        PictureRegion(
          'ziyad with his wallet',
          Rect.fromLTRB(0.64, 0.58, 0.96, 1),
          cue: ['زياد', 'ziyad'],
          burst: PictureBurst.hearts,
        ),
        PictureRegion(
          'the award',
          Rect.fromLTRB(0.34, 0.44, 0.56, 0.62),
          cue: ['درع', 'award'],
          burst: PictureBurst.sparkles,
        ),
      ],
    ),
  ],
  // يونس عليه السلام والحوت — Prophet Yunus and the Whale (no person on a story page; page 1 is today's family)
  'anbiya_yunus_young': [
    LivingPicture(
      image: _page('anbiya_yunus_young', 1),
      regions: [
        PictureRegion(
          'the toy ship on the shelf',
          Rect.fromLTRB(0.36, 0.02, 0.54, 0.18),
          cue: ['سفينة', 'ship'],
        ),
        PictureRegion(
          'the night sea through the window',
          Rect.fromLTRB(0.66, 0.0, 1.0, 0.42),
          cue: ['=ركب', 'boarded'],
        ),
      ],
    ),
    LivingPicture(
      image: _page('anbiya_yunus_young', 2),
      regions: [
        PictureRegion(
          'the laden ship',
          Rect.fromLTRB(0.05, 0.05, 0.75, 0.95),
          cue: ['سفينة', 'ship'],
        ),
        PictureRegion(
          'the sea',
          Rect.fromLTRB(0.55, 0.15, 0.95, 0.9),
          cue: ['البحر', 'أمواج', 'sea', 'waves'],
        ),
      ],
    ),
    LivingPicture(
      image: _page('anbiya_yunus_young', 3),
      regions: [
        PictureRegion(
          'the whale',
          Rect.fromLTRB(0.05, 0.25, 0.85, 0.65),
          cue: ['الحوت', 'whale'],
        ),
        PictureRegion(
          'the night sky',
          Rect.fromLTRB(0.0, 0.0, 1.0, 0.2),
          cue: ['الليل', 'night'],
          burst: PictureBurst.sparkles,
        ),
        PictureRegion(
          'the deep sea',
          Rect.fromLTRB(0.0, 0.55, 1.0, 1.0),
          cue: ['البحر', 'sea'],
        ),
      ],
    ),
    LivingPicture(
      image: _page('anbiya_yunus_young', 4),
      ambient: PictureAmbient.sparkles,
      regions: [
        PictureRegion(
          'the gourd plant',
          Rect.fromLTRB(0.15, 0.12, 0.95, 0.75),
          cue: ['يقطين', 'gourd'],
          burst: PictureBurst.sparkles,
        ),
        PictureRegion(
          'the empty shore',
          Rect.fromLTRB(0.0, 0.6, 1.0, 1.0),
          cue: ['أرض', 'land'],
        ),
      ],
    ),
  ],
  // دعاء يونس عليه السلام في الظلمات — The Du'a of Yunus in the Darkness
  'anbiya_yunus_older': [
    LivingPicture(
      image: _page('anbiya_yunus_older', 1),
      regions: [
        PictureRegion(
          'the ship on the sea through the window',
          Rect.fromLTRB(0.3, 0.05, 0.7, 0.6),
          cue: ['أرسله', 'sent'],
        ),
        PictureRegion(
          'the book',
          Rect.fromLTRB(0.3, 0.6, 0.62, 0.85),
          cue: ['قال', 'says'],
        ),
      ],
    ),
    LivingPicture(
      image: _page('anbiya_yunus_older', 2),
      regions: [
        PictureRegion(
          'the laden ship',
          Rect.fromLTRB(0.05, 0.05, 0.95, 0.9),
          cue: ['سفينة', 'ship'],
        ),
        PictureRegion(
          'the cargo',
          Rect.fromLTRB(0.2, 0.45, 0.75, 0.75),
          cue: ['الأمتعة', 'goods'],
        ),
      ],
    ),
    LivingPicture(
      image: _page('anbiya_yunus_older', 3),
      regions: [
        PictureRegion(
          'the ship at the surface',
          Rect.fromLTRB(0.55, 0.0, 0.9, 0.16),
          cue: ['سفينة', 'ship'],
        ),
        PictureRegion(
          'the waves above',
          Rect.fromLTRB(0.0, 0.0, 1.0, 0.22),
          cue: ['أمواج', 'waves'],
        ),
        PictureRegion(
          'the whale',
          Rect.fromLTRB(0.2, 0.22, 0.8, 0.62),
          cue: ['الحوت', 'whale'],
        ),
        PictureRegion(
          'the sea',
          Rect.fromLTRB(0.0, 0.1, 1.0, 0.75),
          cue: ['البحر', 'sea'],
        ),
      ],
    ),
    LivingPicture(
      image: _page('anbiya_yunus_older', 4),
      regions: [
        PictureRegion(
          'the starry night',
          Rect.fromLTRB(0.0, 0.05, 1.0, 0.38),
          cue: ['الليل', 'night'],
          burst: PictureBurst.sparkles,
        ),
        PictureRegion(
          'the dark sea',
          Rect.fromLTRB(0.05, 0.35, 0.95, 0.62),
          cue: ['البحر', 'sea'],
        ),
        PictureRegion(
          'the whale in the deep',
          Rect.fromLTRB(0.1, 0.55, 0.9, 0.88),
          cue: ['الحوت', 'whale'],
        ),
      ],
    ),
    LivingPicture(
      image: _page('anbiya_yunus_older', 5),
      regions: [
        PictureRegion(
          'the gourd plant',
          Rect.fromLTRB(0.25, 0.3, 1.0, 0.78),
          cue: ['يقطين', 'gourd'],
          burst: PictureBurst.sparkles,
        ),
        PictureRegion(
          'the bare land',
          Rect.fromLTRB(0.0, 0.55, 0.75, 1.0),
          cue: ['أرض', 'land'],
        ),
      ],
    ),
    LivingPicture(
      image: _page('anbiya_yunus_older', 6),
      ambient: PictureAmbient.sparkles,
      regions: [
        PictureRegion(
          'the town',
          Rect.fromLTRB(0.0, 0.25, 1.0, 0.9),
          cue: ['المؤمنين', 'believers'],
          burst: PictureBurst.sparkles,
        ),
        PictureRegion(
          'the birds in the morning sky',
          Rect.fromLTRB(0.0, 0.0, 1.0, 0.32),
          cue: ['العبرة', 'lesson'],
        ),
      ],
    ),
  ],
  // سليمان عليه السلام والنملة — Prophet Sulayman and the Ant (no person on a story page; page 1 is today's family)
  'anbiya_sulayman_naml_young': [
    LivingPicture(
      image: _page('anbiya_sulayman_naml_young', 1),
      regions: [
        PictureRegion(
          'the magnifying glass',
          Rect.fromLTRB(0.4, 0.68, 0.66, 0.88),
          cue: ['علمًا', 'knowledge'],
          burst: PictureBurst.sparkles,
        ),
        PictureRegion(
          'the butterflies over the garden',
          Rect.fromLTRB(0.25, 0.0, 0.8, 0.3),
          cue: ['الطير', 'birds'],
        ),
      ],
    ),
    LivingPicture(
      image: _page('anbiya_sulayman_naml_young', 2),
      regions: [
        PictureRegion(
          'the birds flying in rows',
          Rect.fromLTRB(0.0, 0.0, 1.0, 0.5),
          cue: ['منتظمين', 'order'],
        ),
        PictureRegion(
          'the valley',
          Rect.fromLTRB(0.0, 0.5, 1.0, 1.0),
          cue: ['وادي', 'valley'],
        ),
      ],
    ),
    LivingPicture(
      image: _page('anbiya_sulayman_naml_young', 3),
      regions: [
        PictureRegion(
          'the ant on the stone',
          Rect.fromLTRB(0.15, 0.4, 0.5, 0.78),
          cue: ['نملة', 'ant'],
        ),
        PictureRegion(
          'the ants\' homes',
          Rect.fromLTRB(0.5, 0.2, 0.95, 0.58),
          cue: ['homes'],
        ),
      ],
    ),
    LivingPicture(
      image: _page('anbiya_sulayman_naml_young', 4),
      ambient: PictureAmbient.sparkles,
      regions: [
        PictureRegion(
          'the ants\' homes',
          Rect.fromLTRB(0.0, 0.62, 1.0, 0.97),
          cue: ['النمل', 'ants'],
        ),
        PictureRegion(
          'the sunny valley',
          Rect.fromLTRB(0.0, 0.05, 1.0, 0.55),
          cue: ['نعمة', 'blessing'],
          burst: PictureBurst.sparkles,
        ),
      ],
    ),
  ],
  // سليمان عليه السلام ووادي النمل — Prophet Sulayman and the Valley of the Ants
  'anbiya_sulayman_naml_older': [
    LivingPicture(
      image: _page('anbiya_sulayman_naml_older', 1),
      regions: [
        PictureRegion(
          'the garden where the story is told',
          Rect.fromLTRB(0.3, 0.1, 1.0, 0.9),
          cue: ['العلم', 'knowledge'],
        ),
        PictureRegion(
          'the birds on the branch',
          Rect.fromLTRB(0.35, 0.0, 0.85, 0.2),
          cue: ['عمل', 'acted'],
        ),
      ],
    ),
    LivingPicture(
      image: _page('anbiya_sulayman_naml_older', 2),
      regions: [
        PictureRegion(
          'the birds',
          Rect.fromLTRB(0.0, 0.0, 0.45, 1.0),
          cue: ['الطير', 'birds'],
        ),
        PictureRegion(
          'the hoopoe',
          Rect.fromLTRB(0.55, 0.45, 0.98, 0.98),
          cue: ['منطق', 'speech'],
          burst: PictureBurst.sparkles,
        ),
      ],
    ),
    LivingPicture(
      image: _page('anbiya_sulayman_naml_older', 3),
      regions: [
        PictureRegion(
          'the birds in rows',
          Rect.fromLTRB(0.35, 0.0, 1.0, 0.32),
          cue: ['الطير', 'birds'],
        ),
        PictureRegion(
          'the long road',
          Rect.fromLTRB(0.25, 0.45, 1.0, 1.0),
          cue: ['مسير', 'march'],
        ),
      ],
    ),
    LivingPicture(
      image: _page('anbiya_sulayman_naml_older', 4),
      regions: [
        PictureRegion(
          'the ant on the stone',
          Rect.fromLTRB(0.3, 0.2, 0.7, 0.58),
          cue: ['نملة', 'ant'],
        ),
        PictureRegion(
          'the ants\' homes',
          Rect.fromLTRB(0.6, 0.2, 1.0, 0.55),
          cue: ['homes'],
        ),
        PictureRegion(
          'the ants',
          Rect.fromLTRB(0.1, 0.5, 0.95, 0.95),
          cue: ['النمل', 'ants'],
        ),
      ],
    ),
    LivingPicture(
      image: _page('anbiya_sulayman_naml_older', 5),
      regions: [
        PictureRegion(
          'the ants going home',
          Rect.fromLTRB(0.0, 0.48, 1.0, 1.0),
          cue: ['النمل', 'ants'],
        ),
        PictureRegion(
          'the sky over the valley',
          Rect.fromLTRB(0.0, 0.0, 1.0, 0.45),
          cue: ['نعمة', 'blessing'],
          burst: PictureBurst.sparkles,
        ),
      ],
    ),
    LivingPicture(
      image: _page('anbiya_sulayman_naml_older', 6),
      ambient: PictureAmbient.sparkles,
      regions: [
        PictureRegion(
          'the ant hills',
          Rect.fromLTRB(0.0, 0.45, 1.0, 0.95),
          cue: ['النملة', 'ant'],
        ),
        PictureRegion(
          'the sunset sky with birds',
          Rect.fromLTRB(0.0, 0.0, 1.0, 0.45),
          cue: ['النعمة', 'blessing'],
          burst: PictureBurst.sparkles,
        ),
      ],
    ),
  ],
  // إبراهيم عليه السلام والنار — Prophet Ibrahim (peace be upon him) and the Fire
  'anbiya_ibrahim_nar_young': [
    LivingPicture(
      image: _page('anbiya_ibrahim_nar_young', 1),
      regions: [
        PictureRegion(
          'the fireplace',
          Rect.fromLTRB(0.22, 0.2, 0.6, 0.55),
          cue: ['عالم', 'knew'],
        ),
        PictureRegion(
          'the night window',
          Rect.fromLTRB(0.85, 0.0, 1.0, 0.35),
          cue: ['هداه', 'guidance'],
        ),
      ],
    ),
    LivingPicture(
      image: _page('anbiya_ibrahim_nar_young', 2),
      regions: [
        PictureRegion(
          'the stone statues',
          Rect.fromLTRB(0.0, 0.55, 1.0, 0.95),
          cue: ['أصنام', 'idols'],
        ),
        PictureRegion(
          'the light through the window',
          Rect.fromLTRB(0.4, 0.05, 0.65, 0.35),
          cue: ['التماثيل', 'statues'],
        ),
      ],
    ),
    LivingPicture(
      image: _page('anbiya_ibrahim_nar_young', 3),
      regions: [
        PictureRegion(
          'the broken pieces',
          Rect.fromLTRB(0.2, 0.62, 0.85, 0.95),
          cue: ['قطع', 'pieces'],
        ),
        PictureRegion(
          'the big statue left standing',
          Rect.fromLTRB(0.38, 0.45, 0.6, 0.8),
          cue: ['كبير', 'biggest'],
        ),
      ],
    ),
    LivingPicture(
      image: _page('anbiya_ibrahim_nar_young', 4),
      ambient: PictureAmbient.sparkles,
      regions: [
        PictureRegion(
          'the cool fire',
          Rect.fromLTRB(0.25, 0.45, 0.75, 0.75),
          cue: ['نار', 'fire'],
          burst: PictureBurst.sparkles,
        ),
        PictureRegion(
          'the starry sky',
          Rect.fromLTRB(0.0, 0.0, 1.0, 0.35),
          cue: ['أذى', 'harm'],
        ),
      ],
    ),
  ],
  // إبراهيم عليه السلام والأصنام والنار — Prophet Ibrahim (peace be upon him), the Idols and the Fire
  'anbiya_ibrahim_nar_older': [
    LivingPicture(
      image: _page('anbiya_ibrahim_nar_older', 1),
      regions: [
        PictureRegion(
          'the starry sky',
          Rect.fromLTRB(0.0, 0.0, 1.0, 0.4),
          cue: ['هداه', 'guidance'],
        ),
        PictureRegion(
          'the lantern',
          Rect.fromLTRB(0.2, 0.42, 0.38, 0.6),
          cue: ['يدعو', 'calling'],
        ),
      ],
    ),
    LivingPicture(
      image: _page('anbiya_ibrahim_nar_older', 2),
      regions: [
        PictureRegion(
          'the row of stone idols',
          Rect.fromLTRB(0.0, 0.42, 1.0, 0.85),
          cue: ['أصنام', 'idols'],
        ),
        PictureRegion(
          'the beam of light',
          Rect.fromLTRB(0.4, 0.0, 0.7, 0.5),
          cue: ['التماثيل', 'statues'],
        ),
        PictureRegion(
          'the bowls of fruit',
          Rect.fromLTRB(0.1, 0.78, 0.6, 1.0),
          cue: ['=ابائهم', 'forefathers'],
        ),
      ],
    ),
    LivingPicture(
      image: _page('anbiya_ibrahim_nar_older', 3),
      regions: [
        PictureRegion(
          'the broken pieces',
          Rect.fromLTRB(0.0, 0.55, 1.0, 1.0),
          cue: ['قطع', 'pieces'],
        ),
        PictureRegion(
          'the biggest statue',
          Rect.fromLTRB(0.55, 0.18, 0.82, 0.48),
          cue: ['كبير', 'biggest'],
        ),
      ],
    ),
    LivingPicture(
      image: _page('anbiya_ibrahim_nar_older', 4),
      regions: [
        PictureRegion(
          'the great fire',
          Rect.fromLTRB(0.45, 0.3, 0.75, 0.65),
          cue: ['نار', 'fire'],
          burst: PictureBurst.sparkles,
        ),
        PictureRegion(
          'the smoke',
          Rect.fromLTRB(0.4, 0.0, 0.95, 0.4),
          cue: ['=اشعلوا', 'lit'],
        ),
      ],
    ),
    LivingPicture(
      image: _page('anbiya_ibrahim_nar_older', 5),
      ambient: PictureAmbient.sparkles,
      regions: [
        PictureRegion(
          'the fire turned cool',
          Rect.fromLTRB(0.4, 0.3, 0.7, 0.68),
          cue: ['fire'],
          burst: PictureBurst.sparkles,
        ),
        PictureRegion(
          'the quiet town',
          Rect.fromLTRB(0.0, 0.5, 1.0, 0.9),
          cue: ['أذى', 'harm'],
        ),
      ],
    ),
    LivingPicture(
      image: _page('anbiya_ibrahim_nar_older', 6),
      ambient: PictureAmbient.sparkles,
      regions: [
        PictureRegion(
          'the morning sky with birds',
          Rect.fromLTRB(0.0, 0.0, 1.0, 0.35),
          cue: ['عبر', 'lessons'],
        ),
        PictureRegion(
          'the embers',
          Rect.fromLTRB(0.4, 0.5, 0.7, 0.65),
          cue: ['النار', 'fire'],
        ),
        PictureRegion(
          'the town',
          Rect.fromLTRB(0.0, 0.45, 1.0, 0.9),
          cue: ['كيد', 'plot'],
        ),
      ],
    ),
  ],
  // إبراهيم وإسماعيل عليهما السلام يبنيان البيت — Ibrahim and Isma'il (peace be upon them) Build the House
  'anbiya_bayt_young': [
    LivingPicture(
      image: _page('anbiya_bayt_young', 1),
      regions: [
        PictureRegion(
          'the picture of the Kaaba on the wall',
          Rect.fromLTRB(0.5, 0.07, 0.78, 0.42),
          cue: ['الكعبة', 'kaaba'],
        ),
        PictureRegion(
          'the open picture book',
          Rect.fromLTRB(0.3, 0.76, 0.66, 0.98),
          cue: ['=رفع', 'raised'],
        ),
      ],
    ),
    LivingPicture(
      image: _page('anbiya_bayt_young', 2),
      regions: [
        PictureRegion(
          'the quiet valley',
          Rect.fromLTRB(0.0, 0.45, 1.0, 1.0),
          cue: ['البلد', 'land'],
        ),
        PictureRegion(
          'the mountains and the sky',
          Rect.fromLTRB(0.0, 0.0, 1.0, 0.55),
          cue: ['آمنًا', 'safe'],
        ),
      ],
    ),
    LivingPicture(
      image: _page('anbiya_bayt_young', 3),
      regions: [
        PictureRegion(
          'the rising foundations',
          Rect.fromLTRB(0.15, 0.5, 0.9, 0.85),
          cue: ['قواعد', 'foundations'],
        ),
        PictureRegion(
          'the pile of stones',
          Rect.fromLTRB(0.05, 0.6, 0.38, 0.88),
          cue: ['البيت', 'house'],
        ),
      ],
    ),
    LivingPicture(
      image: _page('anbiya_bayt_young', 4),
      ambient: PictureAmbient.sparkles,
      regions: [
        PictureRegion(
          'the finished House',
          Rect.fromLTRB(0.25, 0.45, 0.72, 0.9),
          cue: ['بيت', 'house'],
          burst: PictureBurst.sparkles,
        ),
        PictureRegion(
          'the birds circling in the sky',
          Rect.fromLTRB(0.0, 0.0, 1.0, 0.42),
          cue: ['يطوف', 'circle'],
        ),
      ],
    ),
  ],
  // إبراهيم وإسماعيل عليهما السلام يرفعان قواعد البيت — Ibrahim and Isma'il (peace be upon them) Raise the House
  'anbiya_bayt_older': [
    LivingPicture(
      image: _page('anbiya_bayt_older', 1),
      regions: [
        PictureRegion(
          'the model of the Kaaba',
          Rect.fromLTRB(0.36, 0.26, 0.58, 0.5),
          cue: ['الكعبة', 'kaaba'],
        ),
        PictureRegion(
          'the globe',
          Rect.fromLTRB(0.0, 0.35, 0.26, 0.72),
          cue: ['ناس', 'people'],
        ),
      ],
    ),
    LivingPicture(
      image: _page('anbiya_bayt_older', 2),
      regions: [
        PictureRegion(
          'the valley floor',
          Rect.fromLTRB(0.0, 0.5, 1.0, 1.0),
          cue: ['البلد', 'land'],
        ),
        PictureRegion(
          'the mountains at dawn',
          Rect.fromLTRB(0.0, 0.0, 1.0, 0.55),
          cue: ['آمنًا', 'safe'],
        ),
      ],
    ),
    LivingPicture(
      image: _page('anbiya_bayt_older', 3),
      regions: [
        PictureRegion(
          'the rising foundations',
          Rect.fromLTRB(0.2, 0.45, 0.95, 0.8),
          cue: ['أسس', 'foundations'],
        ),
        PictureRegion(
          'the standing stone',
          Rect.fromLTRB(0.0, 0.42, 0.2, 0.72),
          cue: ['مقام', 'station'],
          burst: PictureBurst.sparkles,
        ),
      ],
    ),
    LivingPicture(
      image: _page('anbiya_bayt_older', 4),
      regions: [
        PictureRegion(
          'the finished House',
          Rect.fromLTRB(0.3, 0.25, 0.72, 0.85),
          cue: ['بيت', 'house'],
        ),
        PictureRegion(
          'the midday sky',
          Rect.fromLTRB(0.0, 0.0, 1.0, 0.3),
          cue: ['طواف', 'circling'],
        ),
      ],
    ),
    LivingPicture(
      image: _page('anbiya_bayt_older', 5),
      regions: [
        PictureRegion(
          'the starry night sky',
          Rect.fromLTRB(0.0, 0.0, 1.0, 0.4),
          cue: ['=ربهما', 'lord'],
          burst: PictureBurst.sparkles,
        ),
        PictureRegion(
          'the House at night',
          Rect.fromLTRB(0.28, 0.3, 0.68, 0.82),
          cue: ['=دعوا', 'prayed'],
        ),
      ],
    ),
    LivingPicture(
      image: _page('anbiya_bayt_older', 6),
      ambient: PictureAmbient.sparkles,
      regions: [
        PictureRegion(
          'the House in the green valley',
          Rect.fromLTRB(0.0, 0.45, 1.0, 1.0),
          cue: ['البيت', 'house'],
        ),
        PictureRegion(
          'the birds in the morning sky',
          Rect.fromLTRB(0.0, 0.0, 1.0, 0.4),
          cue: ['رسول', 'messenger'],
          burst: PictureBurst.sparkles,
        ),
      ],
    ),
  ],
  // موسى عليه السلام والتابوت — Prophet Musa (peace be upon him) and the Box
  'anbiya_musa_tabut_young': [
    LivingPicture(
      image: _page('anbiya_musa_tabut_young', 1),
      regions: [
        PictureRegion(
          'the toy boat',
          Rect.fromLTRB(0.6, 0.76, 0.84, 0.98),
          cue: ['صندوق', 'box'],
        ),
        PictureRegion(
          'the open picture book',
          Rect.fromLTRB(0.3, 0.6, 0.6, 0.78),
          cue: ['=ترضعه', 'nurse'],
        ),
      ],
    ),
    LivingPicture(
      image: _page('anbiya_musa_tabut_young', 2),
      regions: [
        PictureRegion(
          'the box among the reeds',
          Rect.fromLTRB(0.25, 0.55, 0.62, 0.86),
          cue: ['صندوق', 'box'],
        ),
        PictureRegion(
          'the river',
          Rect.fromLTRB(0.0, 0.3, 1.0, 0.6),
          cue: ['اليم', 'river'],
        ),
      ],
    ),
    LivingPicture(
      image: _page('anbiya_musa_tabut_young', 3),
      regions: [
        PictureRegion(
          'the box on the water',
          Rect.fromLTRB(0.58, 0.55, 0.9, 0.86),
          cue: ['الصندوق', 'box'],
        ),
        PictureRegion(
          'the heron on the shore',
          Rect.fromLTRB(0.8, 0.42, 1.0, 0.76),
          cue: ['الساحل', 'shore'],
        ),
      ],
    ),
    LivingPicture(
      image: _page('anbiya_musa_tabut_young', 4),
      ambient: PictureAmbient.sparkles,
      regions: [
        PictureRegion(
          'the cradle',
          Rect.fromLTRB(0.1, 0.45, 0.75, 0.95),
          cue: ['أمه', 'mother'],
          burst: PictureBurst.hearts,
        ),
        PictureRegion(
          'the little lamp',
          Rect.fromLTRB(0.62, 0.6, 0.86, 0.86),
          cue: ['وعده', 'promise'],
          burst: PictureBurst.sparkles,
        ),
      ],
    ),
  ],
  // موسى عليه السلام في اليمّ — Prophet Musa (peace be upon him) on the River
  'anbiya_musa_tabut_older': [
    LivingPicture(
      image: _page('anbiya_musa_tabut_older', 1),
      regions: [
        PictureRegion(
          'the paper boat on the water',
          Rect.fromLTRB(0.6, 0.62, 0.82, 0.84),
          cue: ['river'],
        ),
        PictureRegion(
          'the open picture book',
          Rect.fromLTRB(0.1, 0.55, 0.46, 0.82),
          cue: ['=الهم', 'inspired'],
        ),
      ],
    ),
    LivingPicture(
      image: _page('anbiya_musa_tabut_older', 2),
      regions: [
        PictureRegion(
          'the house with the glowing window',
          Rect.fromLTRB(0.07, 0.45, 0.5, 0.8),
          cue: ['قلبها', 'heart'],
        ),
        PictureRegion(
          'the river at night',
          Rect.fromLTRB(0.45, 0.4, 1.0, 0.72),
          cue: ['النيل', 'nile'],
        ),
        PictureRegion(
          'the stars',
          Rect.fromLTRB(0.0, 0.0, 1.0, 0.35),
          cue: ['صبرت', 'patient'],
          burst: PictureBurst.sparkles,
        ),
      ],
    ),
    LivingPicture(
      image: _page('anbiya_musa_tabut_older', 3),
      regions: [
        PictureRegion(
          'the box on the river',
          Rect.fromLTRB(0.58, 0.48, 0.84, 0.68),
          cue: ['الصندوق', 'box'],
        ),
        PictureRegion(
          'the wide river',
          Rect.fromLTRB(0.25, 0.4, 1.0, 0.78),
          cue: ['اليم', 'river'],
        ),
      ],
    ),
    LivingPicture(
      image: _page('anbiya_musa_tabut_older', 4),
      regions: [
        PictureRegion(
          'the box at the foot of the steps',
          Rect.fromLTRB(0.4, 0.74, 0.66, 0.95),
          cue: ['=رأته', 'saw'],
        ),
        PictureRegion(
          'the palace garden',
          Rect.fromLTRB(0.45, 0.0, 1.0, 0.55),
          cue: ['فرعون', 'pharaoh'],
        ),
      ],
    ),
    LivingPicture(
      image: _page('anbiya_musa_tabut_older', 5),
      regions: [
        PictureRegion(
          'the footprints along the path',
          Rect.fromLTRB(0.3, 0.55, 0.78, 1.0),
          cue: ['أثر', 'trail'],
        ),
        PictureRegion(
          'the river far ahead',
          Rect.fromLTRB(0.15, 0.2, 1.0, 0.52),
          cue: ['بعيد', 'distance'],
        ),
      ],
    ),
    LivingPicture(
      image: _page('anbiya_musa_tabut_older', 6),
      ambient: PictureAmbient.sparkles,
      regions: [
        PictureRegion(
          'the cradle',
          Rect.fromLTRB(0.4, 0.55, 0.76, 0.92),
          cue: ['أم', 'mother'],
          burst: PictureBurst.hearts,
        ),
        PictureRegion(
          'the jug of milk and the fruit',
          Rect.fromLTRB(0.05, 0.48, 0.36, 0.76),
          cue: ['وعده', 'promise'],
        ),
        PictureRegion(
          'the sunlit window',
          Rect.fromLTRB(0.25, 0.0, 0.66, 0.42),
          cue: ['سليم', 'safe'],
          burst: PictureBurst.sparkles,
        ),
      ],
    ),
  ],
  // موسى عليه السلام والبحر — Prophet Musa (peace be upon him) and the Sea
  'anbiya_musa_bahr_young': [
    LivingPicture(
      image: _page('anbiya_musa_bahr_young', 1),
      regions: [
        PictureRegion(
          'the evening sky over the sea',
          Rect.fromLTRB(0.0, 0.0, 1.0, 0.3),
          cue: ['ليلًا', 'night'],
        ),
        PictureRegion(
          'the sea and the far sail',
          Rect.fromLTRB(0.0, 0.2, 0.6, 0.45),
          cue: ['يسير', 'travel'],
        ),
      ],
    ),
    LivingPicture(
      image: _page('anbiya_musa_bahr_young', 2),
      regions: [
        PictureRegion(
          'the footprints on the road',
          Rect.fromLTRB(0.3, 0.45, 1.0, 1.0),
          cue: ['فسار', 'travelled'],
        ),
        PictureRegion(
          'the night sky',
          Rect.fromLTRB(0.0, 0.0, 1.0, 0.3),
          cue: ['الليل', 'night'],
          burst: PictureBurst.sparkles,
        ),
      ],
    ),
    LivingPicture(
      image: _page('anbiya_musa_bahr_young', 3),
      regions: [
        PictureRegion(
          'the walls of water',
          Rect.fromLTRB(0.0, 0.05, 1.0, 0.6),
          cue: ['الجبل', 'mountain'],
        ),
        PictureRegion(
          'the dry path',
          Rect.fromLTRB(0.25, 0.45, 0.8, 1.0),
          cue: ['فانفلق', 'split'],
          burst: PictureBurst.sparkles,
        ),
      ],
    ),
    LivingPicture(
      image: _page('anbiya_musa_bahr_young', 4),
      ambient: PictureAmbient.sparkles,
      regions: [
        PictureRegion(
          'the calm sea',
          Rect.fromLTRB(0.0, 0.25, 1.0, 0.65),
          cue: ['البحر', 'sea'],
        ),
        PictureRegion(
          'the shore',
          Rect.fromLTRB(0.0, 0.6, 1.0, 1.0),
          cue: ['البر', 'shore'],
        ),
      ],
    ),
  ],
  // موسى عليه السلام وانفلاق البحر — Prophet Musa (peace be upon him) and the Parting of the Sea
  'anbiya_musa_bahr_older': [
    LivingPicture(
      image: _page('anbiya_musa_bahr_older', 1),
      regions: [
        PictureRegion(
          'the sea at dawn',
          Rect.fromLTRB(0.3, 0.2, 1.0, 0.6),
          cue: ['يسير', 'travel'],
        ),
        PictureRegion(
          'the seagulls in the sky',
          Rect.fromLTRB(0.1, 0.0, 0.9, 0.25),
          cue: ['ليلًا', 'night'],
        ),
      ],
    ),
    LivingPicture(
      image: _page('anbiya_musa_bahr_older', 2),
      regions: [
        PictureRegion(
          'the footprints on the road',
          Rect.fromLTRB(0.3, 0.45, 0.9, 1.0),
          cue: ['فسار', 'travelled'],
        ),
        PictureRegion(
          'the starry sky',
          Rect.fromLTRB(0.0, 0.0, 1.0, 0.3),
          cue: ['الليل', 'night'],
          burst: PictureBurst.sparkles,
        ),
      ],
    ),
    LivingPicture(
      image: _page('anbiya_musa_bahr_older', 3),
      regions: [
        PictureRegion(
          'the cloud of dust far away',
          Rect.fromLTRB(0.35, 0.0, 1.0, 0.35),
          cue: ['=لحقوا', 'caught'],
        ),
        PictureRegion(
          'the road to the sea',
          Rect.fromLTRB(0.2, 0.35, 0.8, 1.0),
          cue: ['فريق', 'side'],
        ),
      ],
    ),
    LivingPicture(
      image: _page('anbiya_musa_bahr_older', 4),
      regions: [
        PictureRegion(
          'the walls of water',
          Rect.fromLTRB(0.0, 0.0, 1.0, 0.75),
          cue: ['الجبل', 'mountain'],
        ),
        PictureRegion(
          'the dry path',
          Rect.fromLTRB(0.3, 0.45, 0.75, 1.0),
          cue: ['فانفلق', 'split'],
          burst: PictureBurst.sparkles,
        ),
      ],
    ),
    LivingPicture(
      image: _page('anbiya_musa_bahr_older', 5),
      regions: [
        PictureRegion(
          'the footprints across the sea bed',
          Rect.fromLTRB(0.3, 0.4, 0.75, 1.0),
          cue: ['عبر', 'crossed'],
        ),
        PictureRegion(
          'the far shore',
          Rect.fromLTRB(0.35, 0.2, 0.65, 0.45),
          cue: ['البر', 'shore'],
          burst: PictureBurst.sparkles,
        ),
      ],
    ),
    LivingPicture(
      image: _page('anbiya_musa_bahr_older', 6),
      ambient: PictureAmbient.sparkles,
      regions: [
        PictureRegion(
          'the calm sea',
          Rect.fromLTRB(0.0, 0.25, 1.0, 0.65),
          cue: ['البحر', 'sea'],
        ),
        PictureRegion(
          'the sky with birds',
          Rect.fromLTRB(0.0, 0.0, 1.0, 0.25),
          cue: ['عبرة', 'lesson'],
          burst: PictureBurst.sparkles,
        ),
      ],
    ),
  ],
  // رؤيا يوسف عليه السلام — The Dream of Prophet Yusuf (peace be upon him)
  'anbiya_yusuf_young': [
    LivingPicture(
      image: _page('anbiya_yusuf_young', 1),
      regions: [
        PictureRegion(
          'the starry sky',
          Rect.fromLTRB(0.0, 0.0, 1.0, 0.4),
          cue: ['رؤيا', 'dream'],
          burst: PictureBurst.sparkles,
        ),
        PictureRegion(
          'the crescent moon',
          Rect.fromLTRB(0.1, 0.05, 0.35, 0.25),
          cue: ['منامه', 'sleep'],
        ),
      ],
    ),
    LivingPicture(
      image: _page('anbiya_yusuf_young', 2),
      ambient: PictureAmbient.sparkles,
      regions: [
        PictureRegion(
          'the eleven stars',
          Rect.fromLTRB(0.05, 0.05, 0.95, 0.45),
          cue: ['بشرى', 'stars'],
          burst: PictureBurst.sparkles,
        ),
        PictureRegion(
          'the sun',
          Rect.fromLTRB(0.35, 0.35, 0.7, 0.6),
          cue: ['sun'],
        ),
        PictureRegion(
          'the moon',
          Rect.fromLTRB(0.6, 0.3, 0.8, 0.5),
          cue: ['moon'],
        ),
      ],
    ),
    LivingPicture(
      image: _page('anbiya_yusuf_young', 3),
      regions: [
        PictureRegion(
          'the tent with its lamp',
          Rect.fromLTRB(0.25, 0.45, 0.85, 0.8),
          cue: ['نصحه', 'advised'],
        ),
        PictureRegion(
          'the night sky',
          Rect.fromLTRB(0.0, 0.0, 1.0, 0.4),
          cue: ['رؤياه', 'dream'],
        ),
      ],
    ),
    LivingPicture(
      image: _page('anbiya_yusuf_young', 4),
      ambient: PictureAmbient.sparkles,
      regions: [
        PictureRegion(
          'the raised seat',
          Rect.fromLTRB(0.15, 0.1, 0.45, 0.6),
          cue: ['العرش', 'throne'],
          burst: PictureBurst.sparkles,
        ),
        PictureRegion(
          'the carpets and the gifts',
          Rect.fromLTRB(0.05, 0.55, 0.95, 1.0),
          cue: ['تحية', 'greeting'],
        ),
      ],
    ),
  ],
  // يوسف عليه السلام: رؤيا صارت حقًّا — Prophet Yusuf (peace be upon him): A Dream Made True
  'anbiya_yusuf_older': [
    LivingPicture(
      image: _page('anbiya_yusuf_older', 1),
      regions: [
        PictureRegion(
          'the night window',
          Rect.fromLTRB(0.03, 0.05, 0.42, 0.55),
          cue: ['منامه', 'sleep'],
          burst: PictureBurst.sparkles,
        ),
        PictureRegion(
          'the open book',
          Rect.fromLTRB(0.3, 0.6, 0.75, 0.85),
          cue: ['رؤيا', 'dream'],
        ),
      ],
    ),
    LivingPicture(
      image: _page('anbiya_yusuf_older', 2),
      ambient: PictureAmbient.sparkles,
      regions: [
        PictureRegion(
          'the eleven stars',
          Rect.fromLTRB(0.05, 0.1, 0.95, 0.42),
          cue: ['بشرى', 'stars'],
          burst: PictureBurst.sparkles,
        ),
        PictureRegion(
          'the sun and the moon',
          Rect.fromLTRB(0.4, 0.25, 0.95, 0.45),
          cue: ['sun', 'moon'],
        ),
      ],
    ),
    LivingPicture(
      image: _page('anbiya_yusuf_older', 3),
      regions: [
        PictureRegion(
          'the tent and its lamp',
          Rect.fromLTRB(0.45, 0.45, 0.95, 0.75),
          cue: ['نصحه', 'advised'],
        ),
        PictureRegion(
          'the night sky',
          Rect.fromLTRB(0.0, 0.0, 1.0, 0.4),
          cue: ['رؤياه', 'dream'],
          burst: PictureBurst.sparkles,
        ),
      ],
    ),
    LivingPicture(
      image: _page('anbiya_yusuf_older', 4),
      regions: [
        PictureRegion(
          'the folded shirt',
          Rect.fromLTRB(0.25, 0.35, 0.6, 0.55),
          cue: ['قميصه', 'shirt'],
          burst: PictureBurst.sparkles,
        ),
        PictureRegion(
          'the travel bags',
          Rect.fromLTRB(0.55, 0.4, 0.95, 0.85),
          cue: ['القافلة', 'caravan'],
        ),
      ],
    ),
    LivingPicture(
      image: _page('anbiya_yusuf_older', 5),
      regions: [
        PictureRegion(
          'the city of Egypt',
          Rect.fromLTRB(0.3, 0.0, 1.0, 0.5),
          cue: ['مصر', 'egypt'],
        ),
        PictureRegion(
          'the resting camels',
          Rect.fromLTRB(0.0, 0.4, 1.0, 1.0),
          cue: ['أهله', 'family'],
        ),
      ],
    ),
    LivingPicture(
      image: _page('anbiya_yusuf_older', 6),
      ambient: PictureAmbient.sparkles,
      regions: [
        PictureRegion(
          'the raised seat',
          Rect.fromLTRB(0.3, 0.42, 0.7, 0.75),
          cue: ['العرش', 'throne'],
          burst: PictureBurst.sparkles,
        ),
        PictureRegion(
          'the stars, the sun and the moon in the window',
          Rect.fromLTRB(0.25, 0.0, 0.75, 0.35),
          cue: ['لطيف', 'dream'],
        ),
      ],
    ),
  ],
  // أيوب عليه السلام والصبر — Prophet Ayyub (peace be upon him) and Patience
  'anbiya_ayyub_young': [
    LivingPicture(
      image: _page('anbiya_ayyub_young', 1),
      regions: [
        PictureRegion(
          'the window at sunset',
          Rect.fromLTRB(0.68, 0.1, 0.95, 0.45),
          cue: ['=صبر', 'patient'],
        ),
        PictureRegion(
          'the books on the shelf',
          Rect.fromLTRB(0.25, 0.08, 0.47, 0.27),
          cue: ['عبده', 'servant'],
        ),
      ],
    ),
    LivingPicture(
      image: _page('anbiya_ayyub_young', 2),
      regions: [
        PictureRegion(
          'the tent',
          Rect.fromLTRB(0.2, 0.42, 0.85, 0.75),
          cue: ['نادى', 'called'],
        ),
        PictureRegion(
          'the starry sky',
          Rect.fromLTRB(0.0, 0.0, 1.0, 0.42),
          cue: ['merciful'],
          burst: PictureBurst.sparkles,
        ),
      ],
    ),
    LivingPicture(
      image: _page('anbiya_ayyub_young', 3),
      regions: [
        PictureRegion(
          'the spring and its pool',
          Rect.fromLTRB(0.15, 0.38, 0.85, 0.75),
          cue: ['ماء', 'water'],
          burst: PictureBurst.sparkles,
        ),
        PictureRegion(
          'the ground',
          Rect.fromLTRB(0.0, 0.7, 1.0, 1.0),
          cue: ['الأرض', 'ground'],
        ),
      ],
    ),
    LivingPicture(
      image: _page('anbiya_ayyub_young', 4),
      ambient: PictureAmbient.sparkles,
      regions: [
        PictureRegion(
          'the tents',
          Rect.fromLTRB(0.05, 0.25, 0.45, 0.55),
          cue: ['أهله', 'family'],
        ),
        PictureRegion(
          'the flocks',
          Rect.fromLTRB(0.4, 0.25, 1.0, 0.5),
          cue: ['رحمة', 'mercy'],
        ),
        PictureRegion(
          'the pool',
          Rect.fromLTRB(0.15, 0.5, 0.85, 0.85),
          cue: ['البلاء', 'trial'],
        ),
      ],
    ),
  ],
  // صبر أيوب عليه السلام ورحمة ربه — Prophet Ayyub (peace be upon him): Patience and Mercy
  'anbiya_ayyub_older': [
    LivingPicture(
      image: _page('anbiya_ayyub_older', 1),
      regions: [
        PictureRegion(
          'the fountain',
          Rect.fromLTRB(0.2, 0.25, 0.45, 0.48),
          cue: ['ابتلاه', 'tested'],
        ),
        PictureRegion(
          'the flowers',
          Rect.fromLTRB(0.0, 0.55, 0.25, 1.0),
          cue: ['عبده', 'servant'],
        ),
      ],
    ),
    LivingPicture(
      image: _page('anbiya_ayyub_older', 2),
      regions: [
        PictureRegion(
          'the tent',
          Rect.fromLTRB(0.45, 0.35, 1.0, 0.65),
          cue: ['أهله', 'family'],
        ),
        PictureRegion(
          'the cracked ground',
          Rect.fromLTRB(0.0, 0.6, 1.0, 1.0),
          cue: ['مشقة', 'hardship'],
        ),
        PictureRegion(
          'the heavy sky',
          Rect.fromLTRB(0.0, 0.0, 1.0, 0.35),
          cue: ['تعب', 'tiredness'],
        ),
      ],
    ),
    LivingPicture(
      image: _page('anbiya_ayyub_older', 3),
      regions: [
        PictureRegion(
          'the tent and its lamp',
          Rect.fromLTRB(0.45, 0.35, 1.0, 0.7),
          cue: ['نادى', 'called'],
        ),
        PictureRegion(
          'the stars',
          Rect.fromLTRB(0.0, 0.0, 1.0, 0.4),
          cue: ['رحمة', 'mercy'],
          burst: PictureBurst.sparkles,
        ),
      ],
    ),
    LivingPicture(
      image: _page('anbiya_ayyub_older', 4),
      regions: [
        PictureRegion(
          'the spring',
          Rect.fromLTRB(0.25, 0.3, 0.7, 0.75),
          cue: ['ماء', 'water'],
          burst: PictureBurst.sparkles,
        ),
        PictureRegion(
          'the water jars',
          Rect.fromLTRB(0.65, 0.45, 0.95, 0.75),
          cue: ['=يشرب', 'drink'],
        ),
        PictureRegion(
          'the ground',
          Rect.fromLTRB(0.0, 0.7, 1.0, 1.0),
          cue: ['الأرض', 'ground'],
        ),
      ],
    ),
    LivingPicture(
      image: _page('anbiya_ayyub_older', 5),
      regions: [
        PictureRegion(
          'the palm tree',
          Rect.fromLTRB(0.15, 0.0, 0.6, 0.5),
          cue: ['أكرمه', 'honoured'],
        ),
        PictureRegion(
          'the stream',
          Rect.fromLTRB(0.1, 0.6, 0.9, 1.0),
          cue: ['ضره', 'harm'],
        ),
      ],
    ),
    LivingPicture(
      image: _page('anbiya_ayyub_older', 6),
      ambient: PictureAmbient.sparkles,
      regions: [
        PictureRegion(
          'the flocks',
          Rect.fromLTRB(0.05, 0.55, 1.0, 1.0),
          cue: ['رحمة', 'mercy'],
        ),
        PictureRegion(
          'the sunset sky',
          Rect.fromLTRB(0.0, 0.0, 1.0, 0.35),
          cue: ['العبرة', 'lesson'],
          burst: PictureBurst.sparkles,
        ),
        PictureRegion(
          'the tents',
          Rect.fromLTRB(0.05, 0.3, 0.75, 0.55),
          cue: ['=صابرا', 'patient'],
        ),
      ],
    ),
  ],
  // زكريا عليه السلام والبشرى — Prophet Zakariya (peace be upon him) and the Glad Tidings
  'anbiya_zakariya_young': [
    LivingPicture(
      image: _page('anbiya_zakariya_young', 1),
      regions: [
        PictureRegion(
          'the painting on the wall',
          Rect.fromLTRB(0.4, 0.05, 0.75, 0.3),
          cue: ['رحمة', 'mercy'],
        ),
        PictureRegion(
          'the plant',
          Rect.fromLTRB(0.0, 0.25, 0.2, 0.7),
          cue: ['=كبر', 'old'],
        ),
      ],
    ),
    LivingPicture(
      image: _page('anbiya_zakariya_young', 2),
      regions: [
        PictureRegion(
          'the prayer niche',
          Rect.fromLTRB(0.25, 0.2, 0.6, 0.8),
          cue: ['=سرا', 'secret'],
        ),
        PictureRegion(
          'the prayer mat',
          Rect.fromLTRB(0.3, 0.78, 0.75, 1.0),
          cue: ['دعا', 'called'],
        ),
        PictureRegion(
          'the lamp',
          Rect.fromLTRB(0.43, 0.08, 0.58, 0.35),
          cue: ['ربه', 'lord'],
          burst: PictureBurst.sparkles,
        ),
      ],
    ),
    LivingPicture(
      image: _page('anbiya_zakariya_young', 3),
      regions: [
        PictureRegion(
          'the starry sky',
          Rect.fromLTRB(0.0, 0.0, 1.0, 0.4),
          cue: ['بشره', 'glad'],
          burst: PictureBurst.sparkles,
        ),
        PictureRegion(
          'the moon',
          Rect.fromLTRB(0.55, 0.05, 0.85, 0.3),
          cue: ['دعاءه', 'answered'],
        ),
      ],
    ),
    LivingPicture(
      image: _page('anbiya_zakariya_young', 4),
      ambient: PictureAmbient.sparkles,
      regions: [
        PictureRegion(
          'the cradle',
          Rect.fromLTRB(0.3, 0.6, 0.65, 0.95),
          cue: ['اسم', 'name'],
          burst: PictureBurst.hearts,
        ),
        PictureRegion(
          'the fig tree',
          Rect.fromLTRB(0.0, 0.15, 0.5, 0.7),
          cue: ['رحم', 'mercy'],
        ),
      ],
    ),
  ],
  // زكريا عليه السلام ودعاءٌ في السرّ — Prophet Zakariya (peace be upon him): A Du'a in Secret
  'anbiya_zakariya_older': [
    LivingPicture(
      image: _page('anbiya_zakariya_older', 1),
      regions: [
        PictureRegion(
          'the bookshelves',
          Rect.fromLTRB(0.0, 0.0, 0.25, 0.5),
          cue: ['عبرة', 'lesson'],
        ),
        PictureRegion(
          'the window',
          Rect.fromLTRB(0.5, 0.05, 0.75, 0.38),
          cue: ['=سرا', 'secret'],
        ),
      ],
    ),
    LivingPicture(
      image: _page('anbiya_zakariya_older', 2),
      regions: [
        PictureRegion(
          'the lamp in the niche',
          Rect.fromLTRB(0.35, 0.15, 0.65, 0.45),
          cue: ['قال', 'said'],
          burst: PictureBurst.sparkles,
        ),
        PictureRegion(
          'the prayer mat',
          Rect.fromLTRB(0.35, 0.65, 1.0, 0.95),
          cue: ['ربه', 'lord'],
        ),
        PictureRegion(
          'the prayer beads',
          Rect.fromLTRB(0.75, 0.62, 0.95, 0.78),
          cue: ['ولدا', 'child'],
        ),
      ],
    ),
    LivingPicture(
      image: _page('anbiya_zakariya_older', 3),
      regions: [
        PictureRegion(
          'the first night',
          Rect.fromLTRB(0.02, 0.05, 0.34, 0.95),
          cue: ['ثلاث', 'three'],
        ),
        PictureRegion(
          'the second night',
          Rect.fromLTRB(0.34, 0.05, 0.66, 0.95),
          cue: ['ليال', 'nights'],
          burst: PictureBurst.sparkles,
        ),
        PictureRegion(
          'the third night',
          Rect.fromLTRB(0.66, 0.05, 0.98, 0.95),
          cue: ['علامة', 'sign'],
        ),
      ],
    ),
    LivingPicture(
      image: _page('anbiya_zakariya_older', 4),
      regions: [
        PictureRegion(
          'the door at dawn',
          Rect.fromLTRB(0.04, 0.08, 0.5, 0.95),
          cue: ['صباحا', 'morning'],
        ),
        PictureRegion(
          'the door at dusk',
          Rect.fromLTRB(0.5, 0.08, 0.96, 0.95),
          cue: ['مساء', 'evening'],
        ),
        PictureRegion(
          'the courtyard',
          Rect.fromLTRB(0.1, 0.5, 0.9, 0.95),
          cue: ['قومه', 'people'],
        ),
      ],
    ),
    LivingPicture(
      image: _page('anbiya_zakariya_older', 5),
      regions: [
        PictureRegion(
          'the open book',
          Rect.fromLTRB(0.1, 0.2, 0.9, 0.75),
          cue: ['التوراة', 'torah'],
          burst: PictureBurst.sparkles,
        ),
        PictureRegion(
          'the olive branch',
          Rect.fromLTRB(0.05, 0.6, 0.35, 0.85),
          cue: ['الحكمة', 'wisdom'],
        ),
      ],
    ),
    LivingPicture(
      image: _page('anbiya_zakariya_older', 6),
      ambient: PictureAmbient.sparkles,
      regions: [
        PictureRegion(
          'the little sandals',
          Rect.fromLTRB(0.2, 0.75, 0.4, 0.92),
          cue: ['بوالديه', 'parents'],
          burst: PictureBurst.hearts,
        ),
        PictureRegion(
          'the lamp',
          Rect.fromLTRB(0.2, 0.6, 0.35, 0.75),
          cue: ['سلام', 'peace'],
        ),
        PictureRegion(
          'the fig tree',
          Rect.fromLTRB(0.2, 0.0, 0.8, 0.55),
          cue: ['رحم', 'mercy'],
        ),
      ],
    ),
  ],
  // نوح عليه السلام والسفينة — Prophet Nuh (peace be upon him) and the Ship
  'anbiya_nuh_young': [
    LivingPicture(
      image: _page('anbiya_nuh_young', 1),
      regions: [
        PictureRegion(
          'the rainy window',
          Rect.fromLTRB(0.48, 0.0, 0.75, 0.22),
          cue: ['الطوفان', 'flood'],
        ),
        PictureRegion(
          'the shelves of toys and books',
          Rect.fromLTRB(0.0, 0.0, 0.3, 0.45),
          cue: ['أمر', 'commanded'],
        ),
      ],
    ),
    LivingPicture(
      image: _page('anbiya_nuh_young', 2),
      regions: [
        PictureRegion(
          'the ship being built',
          Rect.fromLTRB(0.12, 0.12, 0.92, 0.68),
          cue: ['السفينة', 'ship'],
        ),
        PictureRegion(
          'the timber and tools',
          Rect.fromLTRB(0.0, 0.62, 1.0, 1.0),
          cue: ['صنع', 'built'],
        ),
      ],
    ),
    LivingPicture(
      image: _page('anbiya_nuh_young', 3),
      regions: [
        PictureRegion(
          'the animals on the ramp',
          Rect.fromLTRB(0.38, 0.42, 0.95, 0.98),
          cue: ['الحيوانات', 'animal'],
        ),
        PictureRegion(
          'the ship',
          Rect.fromLTRB(0.2, 0.2, 0.98, 0.7),
          cue: ['السفينة', 'ship'],
        ),
        PictureRegion(
          'the clouds',
          Rect.fromLTRB(0.3, 0.0, 1.0, 0.3),
          cue: ['الماء', 'water'],
        ),
      ],
    ),
    LivingPicture(
      image: _page('anbiya_nuh_young', 4),
      ambient: PictureAmbient.sparkles,
      regions: [
        PictureRegion(
          'the waves',
          Rect.fromLTRB(0.0, 0.62, 1.0, 1.0),
          cue: ['موج', 'waves'],
        ),
        PictureRegion(
          'the ship',
          Rect.fromLTRB(0.1, 0.22, 0.9, 0.72),
          cue: ['السفينة', 'ship'],
        ),
        PictureRegion(
          'the rain',
          Rect.fromLTRB(0.0, 0.0, 1.0, 0.3),
          cue: ['الماء', 'water'],
        ),
      ],
    ),
  ],
  // نوح عليه السلام وسفينة النجاة — Prophet Nuh (peace be upon him) and the Ship
  'anbiya_nuh_older': [
    LivingPicture(
      image: _page('anbiya_nuh_older', 1),
      regions: [
        PictureRegion(
          'the model ship on the table',
          Rect.fromLTRB(0.38, 0.6, 0.65, 0.8),
          cue: ['sent'],
        ),
        PictureRegion(
          'the rainy window',
          Rect.fromLTRB(0.3, 0.0, 0.62, 0.3),
          cue: ['عذاب', 'punishment'],
        ),
      ],
    ),
    LivingPicture(
      image: _page('anbiya_nuh_older', 2),
      regions: [
        PictureRegion(
          'the village far away',
          Rect.fromLTRB(0.62, 0.42, 1.0, 0.66),
          cue: ['قومه', 'people'],
        ),
        PictureRegion(
          'the frame of the ship',
          Rect.fromLTRB(0.05, 0.12, 0.7, 0.65),
          cue: ['السفينة', 'ship'],
        ),
      ],
    ),
    LivingPicture(
      image: _page('anbiya_nuh_older', 3),
      regions: [
        PictureRegion(
          'the animals coming',
          Rect.fromLTRB(0.0, 0.6, 1.0, 0.95),
          cue: ['الحيوانات', 'animal'],
        ),
        PictureRegion(
          'the ship on dry land',
          Rect.fromLTRB(0.4, 0.12, 1.0, 0.6),
          cue: ['السفينة', 'ship'],
        ),
        PictureRegion(
          'the dark clouds',
          Rect.fromLTRB(0.0, 0.0, 1.0, 0.3),
          cue: ['العذاب', 'punishment'],
        ),
      ],
    ),
    LivingPicture(
      image: _page('anbiya_nuh_older', 4),
      regions: [
        PictureRegion(
          'the rushing water',
          Rect.fromLTRB(0.0, 0.55, 1.0, 1.0),
          cue: ['موج', 'waves'],
        ),
        PictureRegion(
          'the ship',
          Rect.fromLTRB(0.15, 0.12, 0.75, 0.65),
          cue: ['السفينة', 'ship'],
        ),
      ],
    ),
    LivingPicture(
      image: _page('anbiya_nuh_older', 5),
      regions: [
        PictureRegion(
          'the great wave',
          Rect.fromLTRB(0.2, 0.45, 0.85, 0.85),
          cue: ['الموج', 'waves'],
        ),
        PictureRegion(
          'the ship',
          Rect.fromLTRB(0.3, 0.25, 0.75, 0.55),
          cue: ['نادى', 'called'],
        ),
      ],
    ),
    LivingPicture(
      image: _page('anbiya_nuh_older', 6),
      ambient: PictureAmbient.sparkles,
      regions: [
        PictureRegion(
          'the mountain',
          Rect.fromLTRB(0.25, 0.45, 0.85, 0.78),
          cue: ['الجودي', 'judi'],
          burst: PictureBurst.sparkles,
        ),
        PictureRegion(
          'the ship at rest',
          Rect.fromLTRB(0.3, 0.25, 0.75, 0.5),
          cue: ['السفينة', 'ship'],
        ),
        PictureRegion(
          'the green land',
          Rect.fromLTRB(0.0, 0.7, 1.0, 1.0),
          cue: ['عبر', 'lessons'],
        ),
      ],
    ),
  ],

  // ───── من السيرة النبوية (series: sira_sahih) ─────
  // 🚨 The Prophet ﷺ is never pictured, and no companion either: a story page
  // shows only the places and things the hadith names (the cave, the palms,
  // the stones, the minbar, the trunk, the little bird); page 1 is a family of
  // today. So no region is ever cued by a person's name.

  // صاحبا الغار — The Two in the Cave
  'sira_ghar_young': [
    LivingPicture(
      image: _page('sira_ghar_young', 1),
      regions: [
        PictureRegion(
          'the mountain at night through the window',
          Rect.fromLTRB(0.7, 0.0, 0.98, 0.43),
          cue: ['مكة', 'makkah'],
        ),
      ],
    ),
    LivingPicture(
      image: _page('sira_ghar_young', 2),
      ambient: PictureAmbient.sparkles,
      regions: [
        PictureRegion(
          'the cave mouth',
          Rect.fromLTRB(0.44, 0.35, 0.58, 0.48),
          cue: ['غار', 'cave'],
        ),
        PictureRegion(
          'the mountain',
          Rect.fromLTRB(0.12, 0.14, 0.88, 0.66),
          cue: ['جبل', 'mountain'],
        ),
        PictureRegion(
          'the crescent moon',
          Rect.fromLTRB(0.66, 0.06, 0.84, 0.22),
          cue: ['ليال', 'night'],
          burst: PictureBurst.sparkles,
        ),
      ],
    ),
    LivingPicture(
      image: _page('sira_ghar_young', 3),
      regions: [
        PictureRegion(
          'the night outside the cave',
          Rect.fromLTRB(0.24, 0.12, 0.72, 0.62),
          cue: ['نظر', 'look'],
        ),
        PictureRegion(
          'the cave floor',
          Rect.fromLTRB(0.08, 0.76, 0.92, 0.98),
          cue: ['قدميه', 'feet'],
        ),
      ],
    ),
    LivingPicture(
      image: _page('sira_ghar_young', 4),
      ambient: PictureAmbient.sparkles,
      regions: [
        PictureRegion(
          'the dawn light on the mountain',
          Rect.fromLTRB(0.5, 0.2, 0.95, 0.5),
          cue: ['الطمأنينة', 'tranquillity'],
          burst: PictureBurst.sparkles,
        ),
        PictureRegion(
          'the mountain',
          Rect.fromLTRB(0.12, 0.16, 0.88, 0.7),
          cue: ['أنجاه', 'saved'],
        ),
      ],
    ),
  ],
  'sira_ghar_older': [
    LivingPicture(
      image: _page('sira_ghar_older', 1),
      regions: [
        PictureRegion(
          'the mountains through the window',
          Rect.fromLTRB(0.5, 0.05, 0.88, 0.55),
          cue: ['مكة', 'makkah'],
        ),
      ],
    ),
    LivingPicture(
      image: _page('sira_ghar_older', 2),
      ambient: PictureAmbient.sparkles,
      regions: [
        PictureRegion(
          'the town between the mountains',
          Rect.fromLTRB(0.38, 0.36, 0.68, 0.54),
          cue: ['مكة', 'makkah'],
        ),
        PictureRegion(
          'the mountains',
          Rect.fromLTRB(0.0, 0.24, 1.0, 0.52),
          cue: ['جبل', 'mountain'],
        ),
        PictureRegion(
          'the crescent moon',
          Rect.fromLTRB(0.38, 0.06, 0.56, 0.22),
          cue: ['ليال', 'night'],
          burst: PictureBurst.sparkles,
        ),
      ],
    ),
    LivingPicture(
      image: _page('sira_ghar_older', 3),
      regions: [
        PictureRegion(
          'the cave mouth high on the mountain',
          Rect.fromLTRB(0.26, 0.06, 0.44, 0.28),
          cue: ['الغار', 'cave'],
        ),
        PictureRegion(
          'the tracks in the sand below',
          Rect.fromLTRB(0.2, 0.62, 0.8, 0.96),
          cue: ['قدميه', 'feet'],
        ),
      ],
    ),
    LivingPicture(
      image: _page('sira_ghar_older', 4),
      ambient: PictureAmbient.sparkles,
      regions: [
        PictureRegion(
          'the starry sky through the cave mouth',
          Rect.fromLTRB(0.38, 0.1, 0.88, 0.66),
          cue: ['اثنين', 'two'],
        ),
      ],
    ),
    LivingPicture(
      image: _page('sira_ghar_older', 5),
      ambient: PictureAmbient.sparkles,
      regions: [
        PictureRegion(
          'the glow of the sky over the cave',
          Rect.fromLTRB(0.1, 0.05, 0.9, 0.45),
          cue: ['الطمأنينة', 'tranquillity'],
          burst: PictureBurst.sparkles,
        ),
        PictureRegion(
          'the cave',
          Rect.fromLTRB(0.12, 0.38, 0.88, 0.78),
          cue: ['أنجاه', 'saved'],
        ),
      ],
    ),
    LivingPicture(
      image: _page('sira_ghar_older', 6),
      regions: [
        PictureRegion(
          'the cave at sunrise',
          Rect.fromLTRB(0.08, 0.38, 0.72, 0.8),
          cue: ['الغار', 'cave'],
        ),
        PictureRegion(
          'the rising sun',
          Rect.fromLTRB(0.6, 0.3, 0.98, 0.62),
          cue: ['نصر', 'help'],
          burst: PictureBurst.sparkles,
        ),
      ],
    ),
  ],

  // بناء المسجد النبوي — Building the Prophet's Mosque
  'sira_masjid_young': [
    LivingPicture(
      image: _page('sira_masjid_young', 1),
      regions: [
        PictureRegion(
          'the houses behind the courtyard',
          Rect.fromLTRB(0.48, 0.0, 0.96, 0.44),
          cue: ['المدينة', 'madinah'],
        ),
      ],
    ),
    LivingPicture(
      image: _page('sira_masjid_young', 2),
      regions: [
        PictureRegion(
          'the house with its door',
          Rect.fromLTRB(0.68, 0.46, 0.96, 0.68),
          cue: ['دار', 'house'],
        ),
        PictureRegion(
          'the palm garden',
          Rect.fromLTRB(0.7, 0.0, 1.0, 0.86),
          cue: ['=بستانكم', 'garden'],
        ),
      ],
    ),
    LivingPicture(
      image: _page('sira_masjid_young', 3),
      regions: [
        PictureRegion(
          'the old ruins in the garden',
          Rect.fromLTRB(0.08, 0.56, 0.82, 0.86),
          cue: ['ثمن', 'price'],
        ),
      ],
    ),
    LivingPicture(
      image: _page('sira_masjid_young', 4),
      regions: [
        PictureRegion(
          'the palm trunks set in a row',
          Rect.fromLTRB(0.18, 0.36, 0.82, 0.72),
          cue: ['النخل', 'palm'],
        ),
        PictureRegion(
          'the piles of stones',
          Rect.fromLTRB(0.02, 0.68, 0.44, 0.9),
          cue: ['الصخر', 'rock'],
        ),
      ],
    ),
  ],
  'sira_masjid_older': [
    LivingPicture(
      image: _page('sira_masjid_older', 1),
      regions: [
        PictureRegion(
          'the clay houses on the table',
          Rect.fromLTRB(0.44, 0.44, 0.7, 0.64),
          cue: ['المدينة', 'madinah'],
        ),
      ],
    ),
    LivingPicture(
      image: _page('sira_masjid_older', 2),
      regions: [
        PictureRegion(
          'the house',
          Rect.fromLTRB(0.76, 0.46, 0.98, 0.68),
          cue: ['دار', 'house'],
        ),
        PictureRegion(
          'the yard in front of the house',
          Rect.fromLTRB(0.62, 0.62, 0.98, 0.92),
          cue: ['فناء', 'courtyard'],
        ),
      ],
    ),
    LivingPicture(
      image: _page('sira_masjid_older', 3),
      regions: [
        PictureRegion(
          'the palm tree',
          Rect.fromLTRB(0.52, 0.04, 0.76, 0.56),
          cue: ['=بستانكم', 'garden'],
        ),
        PictureRegion(
          'the mat on the ground',
          Rect.fromLTRB(0.66, 0.74, 0.96, 0.92),
          cue: ['الصلاة', 'prayer'],
        ),
      ],
    ),
    LivingPicture(
      image: _page('sira_masjid_older', 4),
      regions: [
        PictureRegion(
          'the ruins',
          Rect.fromLTRB(0.12, 0.14, 0.52, 0.5),
          cue: ['خرب', 'ruins'],
        ),
        PictureRegion(
          'the palms',
          Rect.fromLTRB(0.0, 0.0, 1.0, 0.36),
          cue: ['نخل', 'palm'],
        ),
      ],
    ),
    LivingPicture(
      image: _page('sira_masjid_older', 5),
      regions: [
        PictureRegion(
          'the palm trunks set in rows',
          Rect.fromLTRB(0.04, 0.44, 0.76, 0.82),
          cue: ['النخل', 'palm'],
        ),
        PictureRegion(
          'the stone posts of the door',
          Rect.fromLTRB(0.14, 0.28, 0.36, 0.5),
          cue: ['الحجارة', 'stone'],
        ),
        PictureRegion(
          'the pile of stones',
          Rect.fromLTRB(0.44, 0.34, 0.72, 0.48),
          cue: ['الصخر', 'rock'],
        ),
      ],
    ),
    LivingPicture(
      image: _page('sira_masjid_older', 6),
      regions: [
        PictureRegion(
          'the palms of the garden',
          Rect.fromLTRB(0.0, 0.0, 1.0, 0.36),
          cue: ['=بستانهم', 'garden'],
        ),
        PictureRegion(
          'the stones by the wall',
          Rect.fromLTRB(0.0, 0.72, 0.18, 0.92),
          cue: ['الصخر', 'rock'],
        ),
      ],
    ),
  ],

  // الجذع الذي حنّ — The Palm Trunk That Cried
  'sira_jidh_young': [
    LivingPicture(
      image: _page('sira_jidh_young', 1),
      regions: [
        PictureRegion(
          'the palm trunk',
          Rect.fromLTRB(0.6, 0.12, 0.76, 0.76),
          cue: ['جذع', 'trunk'],
        ),
        PictureRegion(
          'the palm fronds',
          Rect.fromLTRB(0.08, 0.0, 0.96, 0.26),
          cue: ['النخل', 'palm'],
        ),
      ],
    ),
    LivingPicture(
      image: _page('sira_jidh_young', 2),
      regions: [
        PictureRegion(
          'the empty floor by the trunk',
          Rect.fromLTRB(0.2, 0.54, 0.56, 0.78),
          cue: ['منبر', 'minbar'],
        ),
      ],
    ),
    LivingPicture(
      image: _page('sira_jidh_young', 3),
      regions: [
        PictureRegion(
          'the minbar',
          Rect.fromLTRB(0.32, 0.48, 0.56, 0.7),
          cue: ['منبر', 'المنبر', 'minbar'],
        ),
        PictureRegion(
          'the palm trunk',
          Rect.fromLTRB(0.52, 0.0, 0.68, 0.82),
          cue: ['الجذع', 'trunk'],
        ),
      ],
    ),
    LivingPicture(
      image: _page('sira_jidh_young', 4),
      ambient: PictureAmbient.sparkles,
      regions: [
        PictureRegion(
          'the palm trunk',
          Rect.fromLTRB(0.56, 0.0, 0.7, 0.84),
          cue: ['ضم', 'held'],
          burst: PictureBurst.hearts,
        ),
        PictureRegion(
          'the light falling into the mosque',
          Rect.fromLTRB(0.28, 0.08, 0.62, 0.5),
          cue: ['الذكر', 'remembrance'],
          burst: PictureBurst.sparkles,
        ),
        PictureRegion(
          'the minbar',
          Rect.fromLTRB(0.38, 0.48, 0.56, 0.7),
          cue: ['نزل', 'down'],
        ),
      ],
    ),
  ],
  'sira_jidh_older': [
    LivingPicture(
      image: _page('sira_jidh_older', 1),
      regions: [
        PictureRegion(
          'the palm trunk',
          Rect.fromLTRB(0.68, 0.06, 0.86, 0.86),
          cue: ['جذع', 'trunk'],
        ),
        PictureRegion(
          'the palm fronds',
          Rect.fromLTRB(0.24, 0.0, 0.98, 0.26),
          cue: ['النخل', 'palm'],
        ),
      ],
    ),
    LivingPicture(
      image: _page('sira_jidh_older', 2),
      regions: [
        PictureRegion(
          'the open floor of the mosque',
          Rect.fromLTRB(0.2, 0.5, 0.76, 0.86),
          cue: ['منبر', 'minbar'],
        ),
      ],
    ),
    LivingPicture(
      image: _page('sira_jidh_older', 3),
      regions: [
        PictureRegion(
          'the minbar',
          Rect.fromLTRB(0.1, 0.5, 0.44, 0.82),
          cue: ['منبر', 'المنبر', 'minbar'],
        ),
        PictureRegion(
          'the carpenter\'s tools',
          Rect.fromLTRB(0.52, 0.74, 0.84, 0.92),
          cue: ['صنعوا', 'made'],
        ),
      ],
    ),
    LivingPicture(
      image: _page('sira_jidh_older', 4),
      regions: [
        PictureRegion(
          'the palm trunk',
          Rect.fromLTRB(0.66, 0.0, 0.84, 0.84),
          cue: ['الجذع', 'trunk'],
        ),
        PictureRegion(
          'the rings of sound around the trunk',
          Rect.fromLTRB(0.46, 0.18, 0.98, 0.8),
          cue: ['صوت', 'sound'],
        ),
      ],
    ),
    LivingPicture(
      image: _page('sira_jidh_older', 5),
      ambient: PictureAmbient.sparkles,
      regions: [
        PictureRegion(
          'the palm trunk',
          Rect.fromLTRB(0.66, 0.0, 0.84, 0.86),
          cue: ['ضم', 'held'],
          burst: PictureBurst.hearts,
        ),
        PictureRegion(
          'the minbar',
          Rect.fromLTRB(0.1, 0.5, 0.44, 0.82),
          cue: ['نزل', 'down'],
        ),
        PictureRegion(
          'the light falling into the mosque',
          Rect.fromLTRB(0.3, 0.08, 0.66, 0.5),
          cue: ['الذكر', 'remembrance'],
          burst: PictureBurst.sparkles,
        ),
      ],
    ),
    LivingPicture(
      image: _page('sira_jidh_older', 6),
      ambient: PictureAmbient.sparkles,
      regions: [
        PictureRegion(
          'the palm trunk',
          Rect.fromLTRB(0.64, 0.0, 0.82, 0.86),
          cue: ['الجذع', 'trunk'],
        ),
        PictureRegion(
          'the minbar',
          Rect.fromLTRB(0.1, 0.5, 0.44, 0.82),
          cue: ['نزل', 'down'],
        ),
        PictureRegion(
          'the evening light',
          Rect.fromLTRB(0.3, 0.06, 0.66, 0.5),
          cue: ['الذكر', 'remembrance'],
          burst: PictureBurst.sparkles,
        ),
      ],
    ),
  ],

  // أبو عمير وطائره الصغير — Abu Umair and His Little Bird
  'sira_abu_umair_young': [
    LivingPicture(
      image: _page('sira_abu_umair_young', 1),
      regions: [
        PictureRegion(
          'the sparrow on the railing',
          Rect.fromLTRB(0.72, 0.26, 0.9, 0.4),
          cue: ['نغر', 'طائر', 'nughar', 'bird'],
        ),
      ],
    ),
    LivingPicture(
      image: _page('sira_abu_umair_young', 2),
      regions: [
        PictureRegion(
          'the little bird',
          Rect.fromLTRB(0.5, 0.64, 0.74, 0.84),
          cue: ['النغير', 'طائر', 'nughayr', 'bird'],
        ),
        PictureRegion(
          'the doorway',
          Rect.fromLTRB(0.1, 0.2, 0.34, 0.66),
          cue: ['=جاء', 'came'],
        ),
      ],
    ),
    LivingPicture(
      image: _page('sira_abu_umair_young', 3),
      ambient: PictureAmbient.sparkles,
      regions: [
        PictureRegion(
          'the doorway of the house',
          Rect.fromLTRB(0.08, 0.2, 0.42, 0.7),
          cue: ['خلق', 'character'],
          burst: PictureBurst.sparkles,
        ),
      ],
    ),
    LivingPicture(
      image: _page('sira_abu_umair_young', 4),
      ambient: PictureAmbient.sparkles,
      regions: [
        PictureRegion(
          'the evening sky',
          Rect.fromLTRB(0.44, 0.0, 0.96, 0.32),
          cue: ['سنين', 'years'],
          burst: PictureBurst.sparkles,
        ),
        PictureRegion(
          'the water jug',
          Rect.fromLTRB(0.76, 0.44, 0.9, 0.62),
          cue: ['خدمت', 'served'],
        ),
      ],
    ),
  ],
  'sira_abu_umair_older': [
    LivingPicture(
      image: _page('sira_abu_umair_older', 1),
      ambient: PictureAmbient.sparkles,
      regions: [
        PictureRegion(
          'the sunny window',
          Rect.fromLTRB(0.64, 0.08, 0.98, 0.44),
          cue: ['خلق', 'character'],
          burst: PictureBurst.sparkles,
        ),
      ],
    ),
    LivingPicture(
      image: _page('sira_abu_umair_older', 2),
      regions: [
        PictureRegion(
          'the little bird at the bowl',
          Rect.fromLTRB(0.42, 0.52, 0.62, 0.7),
          cue: ['نغر', 'طائر', 'nughar', 'bird'],
        ),
        PictureRegion(
          'the toy duck',
          Rect.fromLTRB(0.48, 0.72, 0.6, 0.84),
          cue: ['يلعب', 'played'],
        ),
      ],
    ),
    LivingPicture(
      image: _page('sira_abu_umair_older', 3),
      regions: [
        PictureRegion(
          'the little bird on the step',
          Rect.fromLTRB(0.18, 0.6, 0.38, 0.78),
          cue: ['النغير', 'nughayr'],
        ),
        PictureRegion(
          'the open door',
          Rect.fromLTRB(0.1, 0.14, 0.5, 0.7),
          cue: ['=جاء', 'came'],
        ),
      ],
    ),
    LivingPicture(
      image: _page('sira_abu_umair_older', 4),
      regions: [
        PictureRegion(
          'the mat',
          Rect.fromLTRB(0.26, 0.68, 0.92, 0.92),
          cue: ['بساط', 'mat'],
        ),
        PictureRegion(
          'the broom',
          Rect.fromLTRB(0.14, 0.18, 0.34, 0.76),
          cue: ['يكنس', 'swept'],
        ),
        PictureRegion(
          'the water jar',
          Rect.fromLTRB(0.04, 0.62, 0.22, 0.86),
          cue: ['ماء', 'water'],
        ),
      ],
    ),
    LivingPicture(
      image: _page('sira_abu_umair_older', 5),
      ambient: PictureAmbient.sparkles,
      regions: [
        PictureRegion(
          'the palm with its dates',
          Rect.fromLTRB(0.38, 0.0, 0.72, 0.6),
          cue: ['سنين', 'years'],
          burst: PictureBurst.sparkles,
        ),
        PictureRegion(
          'the door of the house',
          Rect.fromLTRB(0.12, 0.3, 0.3, 0.74),
          cue: ['خدمت', 'served'],
        ),
      ],
    ),
    LivingPicture(
      image: _page('sira_abu_umair_older', 6),
      ambient: PictureAmbient.sparkles,
      regions: [
        PictureRegion(
          'the little bird on the wall',
          Rect.fromLTRB(0.28, 0.36, 0.48, 0.52),
          cue: ['طائر', 'bird'],
        ),
        PictureRegion(
          'the walls of the house',
          Rect.fromLTRB(0.0, 0.3, 1.0, 0.76),
          cue: ['بيت', 'family'],
        ),
        PictureRegion(
          'the sunset sky',
          Rect.fromLTRB(0.0, 0.0, 1.0, 0.34),
          cue: ['سنين', 'years'],
          burst: PictureBurst.sparkles,
        ),
      ],
    ),
  ],
};
