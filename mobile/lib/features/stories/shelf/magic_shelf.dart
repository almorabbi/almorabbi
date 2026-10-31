/// «رف الحكايات» — the stories as real books on wooden shelves, at night, a
/// little magic (the maintainer, 2026-10-30: «رف كتب حقيقي… حاجة سحرية مش تقليدية»).
///
/// One shelf per series (the prophets, the Seerah, the tales), each a plank on
/// a night wall that scrolls sideways. A book stands with its spine out, the
/// spine cut from the story's own key picture — the whale, the ants, the cave
/// — so the shelf shows what each story *is*, not a row of families reading.
/// The next unread book of a shelf faces out and glows. Golden motes drift
/// over the wall. A tap lifts the book off the shelf ([BookPullout]) into an
/// open cover with «نقرؤها معًا» and «اسمعها من نور».
///
/// With reduced motion the motes and the glow hold still; nothing else needs
/// the motion to make sense.
library;

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../core/haptics.dart';
import '../../../core/sound_fx.dart';
import '../../../l10n/app_localizations.dart';
import '../../../l10n/content_direction.dart';
import '../../program/data/story_models.dart';
import '../living/living_picture.dart' show livingImage;
import '../living/living_picture_catalog.dart'
    show livingCoverFor, livingPictureFor;

enum ShelfKind { prophets, seerah, tales }

ShelfKind shelfOf(Story s) => switch (s.series) {
  kAnbiyaSeries => ShelfKind.prophets,
  kSiraSeries => ShelfKind.seerah,
  _ => ShelfKind.tales,
};

/// The picture a book wears on its spine and its cover: for a series story
/// its first story page (a place or a thing — never a person), for a tale its
/// painted cover; null when the app has no painting for it.
String? spinePictureOf(Story s) {
  if (s.series != null) {
    final scene = livingPictureFor(s.id, 1);
    if (scene != null) return scene.image;
  }
  return livingCoverFor(s.id);
}

/// The wall's palette — the shelf is its own night room in light and dark.
class ShelfColors {
  static const wall = Color(0xFF16233F);
  static const wallLow = Color(0xFF1E2F52);
  static const wood = Color(0xFF8A5A33);
  static const woodDark = Color(0xFF5E3A1F);
  static const woodEdge = Color(0xFFB07A48);
  static const gold = Color(0xFFF2C56B);
  static const ivory = Color(0xFFFBF3E2);
  static const ink = Color(0xFF2A1A0E);
}

class MagicShelf extends StatelessWidget {
  const MagicShelf({
    super.key,
    required this.stories,
    required this.finished,
    required this.onOpenBook,
    this.header,
  });

  final List<Story> stories;
  final Set<String> finished;
  final void Function(Story story) onOpenBook;

  /// Shown on the wall above the first shelf (the filters, Noor's line).
  final Widget? header;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final groups = <ShelfKind, List<Story>>{};
    for (final s in stories) {
      (groups[shelfOf(s)] ??= []).add(s);
    }
    String title(ShelfKind k) => switch (k) {
      ShelfKind.prophets => l10n.storyProphetsTitle,
      ShelfKind.seerah => l10n.storyShelfSeerah,
      ShelfKind.tales => l10n.storyShelfTales,
    };
    String? subtitle(ShelfKind k) => switch (k) {
      ShelfKind.prophets => l10n.storyProphetsSubtitle,
      ShelfKind.seerah => l10n.storyShelfSeerahSubtitle,
      ShelfKind.tales => null,
    };
    final still = MediaQuery.of(context).disableAnimations;
    return ColoredBox(
      color: ShelfColors.wall,
      child: Stack(
        children: [
          if (!still)
            const Positioned.fill(child: IgnorePointer(child: ShelfMotes())),
          ListView(
            padding: const EdgeInsets.only(top: 4, bottom: 32),
            children: [
              ?header,
              for (final kind in ShelfKind.values)
                if (groups[kind]?.isNotEmpty ?? false)
                  BookShelf(
                    key: ValueKey('shelf-${kind.name}'),
                    title: title(kind),
                    subtitle: subtitle(kind),
                    stories: groups[kind]!,
                    finished: finished,
                    onOpenBook: onOpenBook,
                  ),
            ],
          ),
        ],
      ),
    );
  }
}

/// One plank: its name, its books standing on it, scrolling sideways.
class BookShelf extends StatelessWidget {
  const BookShelf({
    super.key,
    required this.title,
    this.subtitle,
    required this.stories,
    required this.finished,
    required this.onOpenBook,
  });

  final String title;
  final String? subtitle;
  final List<Story> stories;
  final Set<String> finished;
  final void Function(Story story) onOpenBook;

  @override
  Widget build(BuildContext context) {
    final scale = MediaQuery.textScalerOf(context).scale(1).clamp(1.0, 2.0);
    final waiting = stories.firstWhere(
      (s) => !finished.contains(s.id),
      orElse: () => stories.first,
    );
    final bookHeight = 168.0 + 24 * (scale - 1);
    return Padding(
      padding: const EdgeInsets.only(top: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 18),
            child: Row(
              children: [
                const _Lantern(),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Semantics(
                        header: true,
                        child: Text(
                          title,
                          style: const TextStyle(
                            color: ShelfColors.gold,
                            fontSize: 17,
                            height: 1.35,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                      if (subtitle != null)
                        Text(
                          subtitle!,
                          style: TextStyle(
                            color: ShelfColors.ivory.withValues(alpha: .75),
                            fontSize: 12.5,
                            height: 1.45,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          SizedBox(
            height: bookHeight + 26,
            child: Stack(
              children: [
                const Positioned(left: 0, right: 0, bottom: 0, child: _Plank()),
                Positioned.fill(
                  bottom: 18,
                  // Every book mounted (a Row, not a lazy list): a shelf holds
                  // tens, not thousands, and tests and screen readers see all.
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 18),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        for (final (i, s) in stories.indexed) ...[
                          if (i > 0) const SizedBox(width: 4),
                          ShelfBook(
                            key: ValueKey('book-${s.id}'),
                            story: s,
                            facingOut: identical(s, waiting),
                            finished: finished.contains(s.id),
                            height: bookHeight - 14 * (s.id.hashCode % 3),
                            scale: scale.toDouble(),
                            onTap: () => onOpenBook(s),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// A book on the shelf: a spine, or — the one waiting to be read — a cover
/// facing out with a soft glow behind it.
class ShelfBook extends StatefulWidget {
  const ShelfBook({
    super.key,
    required this.story,
    required this.facingOut,
    required this.finished,
    required this.height,
    required this.scale,
    required this.onTap,
  });

  final Story story;
  final bool facingOut;
  final bool finished;
  final double height;
  final double scale;
  final VoidCallback onTap;

  @override
  State<ShelfBook> createState() => _ShelfBookState();
}

class _ShelfBookState extends State<ShelfBook>
    with SingleTickerProviderStateMixin {
  late final AnimationController _glow = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2400),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final still = MediaQuery.of(context).disableAnimations;
    if (widget.facingOut && !still) {
      if (!_glow.isAnimating) _glow.repeat(reverse: true);
    } else {
      _glow.stop();
    }
  }

  @override
  void dispose() {
    _glow.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.story;
    final l10n = AppLocalizations.of(context);
    final color = _themeColor(s.themeColor);
    final width = widget.facingOut
        ? widget.height * .74
        : 44 * widget.scale.clamp(1.0, 1.6);
    // Every fourth spine leans a little on its neighbour, like a real shelf.
    final lean = !widget.facingOut && widget.story.id.hashCode % 4 == 0;
    final book = Hero(
      tag: 'story-cover-${s.id}',
      child: Material(
        type: MaterialType.transparency,
        child: SizedBox(
          width: width,
          height: widget.height,
          child: widget.facingOut
              ? _Cover(story: s, color: color)
              : _Spine(story: s, color: color),
        ),
      ),
    );
    return Semantics(
      button: true,
      label: [s.title, if (s.ageGroup != null) s.ageGroup!].join('، '),
      hint: l10n.storyTapToOpen,
      excludeSemantics: true,
      child: GestureDetector(
        onTap: () {
          Haptics.selection();
          unawaited(SoundFx.page());
          widget.onTap();
        },
        child: Stack(
          clipBehavior: Clip.none,
          alignment: Alignment.bottomCenter,
          children: [
            if (widget.facingOut)
              Positioned(
                bottom: -6,
                child: AnimatedBuilder(
                  animation: _glow,
                  builder: (_, _) => Container(
                    width: width * 1.25,
                    height: widget.height * .9,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: ShelfColors.gold.withValues(
                            alpha: .18 + .17 * _glow.value,
                          ),
                          blurRadius: 36,
                          spreadRadius: 4,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            if (lean)
              Transform.rotate(
                angle: -.07,
                alignment: Alignment.bottomLeft,
                child: book,
              )
            else
              book,
            if (widget.finished)
              const Positioned(
                top: -8,
                child: Icon(
                  Icons.star_rounded,
                  size: 18,
                  color: ShelfColors.gold,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

Color _themeColor(String hex) {
  final v = int.tryParse(hex.replaceFirst('0x', ''), radix: 16);
  return v == null ? ShelfColors.wood : Color(v);
}

ImageProvider _thumb(String path, int width) =>
    ResizeImage(livingImage(path), width: width, policy: ResizeImagePolicy.fit);

class _Spine extends StatelessWidget {
  const _Spine({required this.story, required this.color});
  final Story story;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final picture = spinePictureOf(story);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: color,
        borderRadius: const BorderRadius.vertical(
          top: Radius.circular(5),
          bottom: Radius.circular(2),
        ),
        boxShadow: const [
          BoxShadow(
            color: Color(0x66000000),
            offset: Offset(2, 2),
            blurRadius: 3,
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: const BorderRadius.vertical(
          top: Radius.circular(5),
          bottom: Radius.circular(2),
        ),
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (picture != null)
              Image(
                image: _thumb(picture, 256),
                fit: BoxFit.cover,
                excludeFromSemantics: true,
                errorBuilder: (_, _, _) => const SizedBox.shrink(),
              ),
            // The book's head and tail bands, and a darkening along the
            // joint so it reads as a spine, not a strip of photo.
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    Colors.black.withValues(alpha: .35),
                    Colors.transparent,
                    Colors.black.withValues(alpha: .25),
                  ],
                  stops: const [0, .45, 1],
                ),
              ),
            ),
            Align(
              alignment: Alignment.topCenter,
              child: _Band(color: color),
            ),
            Align(
              alignment: Alignment.bottomCenter,
              child: _Band(color: color),
            ),
            Center(
              child: RotatedBox(
                quarterTurns: 1,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: ShelfColors.ivory.withValues(alpha: .9),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: ContentDirectionality(
                    languageCode: story.language,
                    text: story.title,
                    child: Text(
                      story.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: ShelfColors.ink,
                        fontSize: 11.5,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Band extends StatelessWidget {
  const _Band({required this.color});
  final Color color;
  @override
  Widget build(BuildContext context) => Container(
    height: 9,
    color: Color.lerp(color, Colors.black, .25),
    alignment: Alignment.center,
    child: Container(
      height: 1.5,
      color: ShelfColors.gold.withValues(alpha: .8),
    ),
  );
}

class _Cover extends StatelessWidget {
  const _Cover({required this.story, required this.color});
  final Story story;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final picture = spinePictureOf(story);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: color,
        borderRadius: const BorderRadius.horizontal(
          left: Radius.circular(3),
          right: Radius.circular(8),
        ),
        boxShadow: const [
          BoxShadow(
            color: Color(0x80000000),
            offset: Offset(3, 4),
            blurRadius: 6,
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: const BorderRadius.horizontal(
          left: Radius.circular(3),
          right: Radius.circular(8),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: picture == null
                  ? const SizedBox.shrink()
                  : Image(
                      image: _thumb(picture, 512),
                      fit: BoxFit.cover,
                      excludeFromSemantics: true,
                      errorBuilder: (_, _, _) => const SizedBox.shrink(),
                    ),
            ),
            Container(
              color: ShelfColors.ivory,
              padding: const EdgeInsets.fromLTRB(6, 5, 6, 6),
              child: ContentDirectionality(
                languageCode: story.language,
                text: story.title,
                child: Text(
                  story.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: ShelfColors.ink,
                    fontSize: 12.5,
                    height: 1.3,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Plank extends StatelessWidget {
  const _Plank();
  @override
  Widget build(BuildContext context) => Column(
    children: [
      Container(height: 4, color: ShelfColors.woodEdge),
      Container(
        height: 14,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [ShelfColors.wood, ShelfColors.woodDark],
          ),
        ),
      ),
      Container(height: 8, color: Colors.black.withValues(alpha: .25)),
    ],
  );
}

/// A small lantern at the head of each shelf — Noor's lanterns.
class _Lantern extends StatelessWidget {
  const _Lantern();
  @override
  Widget build(BuildContext context) => Container(
    width: 26,
    height: 26,
    decoration: BoxDecoration(
      shape: BoxShape.circle,
      color: ShelfColors.gold.withValues(alpha: .18),
      boxShadow: [
        BoxShadow(
          color: ShelfColors.gold.withValues(alpha: .45),
          blurRadius: 14,
        ),
      ],
    ),
    child: const Icon(Icons.light_rounded, size: 17, color: ShelfColors.gold),
  );
}

/// Golden motes drifting up the wall, twinkling. Painted, not widgets.
class ShelfMotes extends StatefulWidget {
  const ShelfMotes({super.key});
  @override
  State<ShelfMotes> createState() => _ShelfMotesState();
}

class _ShelfMotesState extends State<ShelfMotes>
    with SingleTickerProviderStateMixin {
  late final AnimationController _t = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 40),
  )..repeat();

  @override
  void dispose() {
    _t.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      RepaintBoundary(child: CustomPaint(painter: _MotesPainter(_t)));
}

class _MotesPainter extends CustomPainter {
  _MotesPainter(this.t) : super(repaint: t);
  final Animation<double> t;
  static final _seeds = List.generate(28, (i) {
    final r = math.Random(i * 7919);
    return (
      r.nextDouble(),
      r.nextDouble(),
      1 + r.nextDouble() * 2.2,
      r.nextDouble(),
    );
  });

  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint();
    for (final (x, y, radius, phase) in _seeds) {
      final v = (t.value + phase) % 1.0;
      final dy = (y - v) % 1.0;
      final sway = math.sin((v + phase) * math.pi * 4) * 10;
      final twinkle =
          .35 + .65 * (0.5 + 0.5 * math.sin((v * 9 + phase) * math.pi * 2));
      p.color = ShelfColors.gold.withValues(alpha: .55 * twinkle);
      p.maskFilter = const MaskFilter.blur(BlurStyle.normal, 2.2);
      canvas.drawCircle(
        Offset(x * size.width + sway, dy * size.height),
        radius,
        p,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _MotesPainter old) => false;
}

/// The book lifted off the shelf: the cover large, a breath of sparkle, the
/// title, the ages, and the ways in. A transparent page route so the cover
/// flies from its place on the shelf (the shared `story-cover-<id>` hero).
class BookPullout extends StatelessWidget {
  const BookPullout({
    super.key,
    required this.story,
    required this.onRead,
    this.onListenParent,
  });

  final Story story;
  final VoidCallback onRead;
  final VoidCallback? onListenParent;

  static Route<void> route({
    required Story story,
    required VoidCallback onRead,
    VoidCallback? onListenParent,
  }) => PageRouteBuilder<void>(
    opaque: false,
    barrierDismissible: true,
    barrierColor: Colors.black.withValues(alpha: .72),
    transitionDuration: const Duration(milliseconds: 520),
    reverseTransitionDuration: const Duration(milliseconds: 360),
    pageBuilder: (_, _, _) => BookPullout(
      story: story,
      onRead: onRead,
      onListenParent: onListenParent,
    ),
    transitionsBuilder: (context, anim, _, child) {
      final curved = CurvedAnimation(parent: anim, curve: Curves.easeOutBack);
      return AnimatedBuilder(
        animation: curved,
        builder: (context, _) => Transform(
          alignment: Alignment.center,
          transform: Matrix4.identity()
            ..setEntry(3, 2, .0012)
            ..rotateY((1 - curved.value) * .5),
          child: Opacity(opacity: anim.value.clamp(0, 1), child: child),
        ),
      );
    },
  );

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final size = MediaQuery.sizeOf(context);
    final coverW = math.min(size.width * .62, 320.0);
    final color = _themeColor(story.themeColor);
    final still = MediaQuery.of(context).disableAnimations;
    // A transparent route has no Material behind it: without one, every
    // Text here would draw with the debug yellow double underline.
    return Material(
      type: MaterialType.transparency,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => Navigator.of(context).maybePop(),
        child: SafeArea(
          child: Center(
            child: GestureDetector(
              onTap: () {},
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Stack(
                      alignment: Alignment.center,
                      clipBehavior: Clip.none,
                      children: [
                        if (!still) const _Sparkle(),
                        Hero(
                          tag: 'story-cover-${story.id}',
                          child: Material(
                            type: MaterialType.transparency,
                            child: SizedBox(
                              width: coverW,
                              height: coverW * 1.32,
                              child: _Cover(story: story, color: color),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 18),
                    if (story.ageGroup != null)
                      Text(
                        story.ageGroup!,
                        style: TextStyle(
                          color: ShelfColors.ivory.withValues(alpha: .85),
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    if (story.description.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 360),
                        child: ContentDirectionality(
                          languageCode: story.language,
                          text: story.description,
                          child: Text(
                            story.description,
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              color: ShelfColors.ivory,
                              fontSize: 14,
                              height: 1.55,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
                    ],
                    const SizedBox(height: 18),
                    FilledButton.icon(
                      key: const ValueKey('pullout-read'),
                      style: FilledButton.styleFrom(
                        backgroundColor: ShelfColors.gold,
                        foregroundColor: ShelfColors.ink,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 26,
                          vertical: 14,
                        ),
                      ),
                      onPressed: onRead,
                      icon: const Icon(Icons.auto_stories_rounded),
                      label: Text(
                        l10n.storyReadTogether,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    if (onListenParent != null) ...[
                      const SizedBox(height: 10),
                      TextButton.icon(
                        style: TextButton.styleFrom(
                          foregroundColor: ShelfColors.ivory,
                        ),
                        onPressed: onListenParent,
                        icon: const Icon(Icons.record_voice_over_rounded),
                        label: Text(l10n.storyListenInParentVoice),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A burst of gold around the lifted book, once.
class _Sparkle extends StatefulWidget {
  const _Sparkle();
  @override
  State<_Sparkle> createState() => _SparkleState();
}

class _SparkleState extends State<_Sparkle>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  )..forward();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => IgnorePointer(
    child: CustomPaint(
      size: const Size(360, 420),
      painter: _SparklePainter(_c),
    ),
  );
}

class _SparklePainter extends CustomPainter {
  _SparklePainter(this.t) : super(repaint: t);
  final Animation<double> t;

  @override
  void paint(Canvas canvas, Size size) {
    final v = Curves.easeOut.transform(t.value);
    final c = size.center(Offset.zero);
    final p = Paint()
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 1.5);
    for (var i = 0; i < 22; i++) {
      final a = i / 22 * math.pi * 2 + i * .37;
      final d = 60 + 150 * v * (0.6 + (i % 5) / 10);
      p.color = ShelfColors.gold.withValues(alpha: (1 - v) * .9);
      canvas.drawCircle(
        c + Offset(math.cos(a) * d, math.sin(a) * d * 1.15),
        2.4 * (1 - v * .5),
        p,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _SparklePainter old) => false;
}
