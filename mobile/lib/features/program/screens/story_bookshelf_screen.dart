/// The story shelf — «رف الحكايات» (2026-10-30): real books on night shelves,
/// one shelf per series, a little magic. The shelf itself is
/// `features/stories/shelf/magic_shelf.dart`; this screen keeps the age
/// filters, Noor's line, and what opening a book leads to.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/app_routes.dart';
import '../../../core/haptics.dart';
import '../../../l10n/app_localizations.dart';
import '../../../widgets/ui/empty_state.dart';
import '../../../widgets/ui/error_retry_view.dart';
import '../../companion/widgets/noor_face.dart';
import '../../companion/widgets/noor_presence.dart';
import '../../screen_off/narration_store.dart';
import '../../stories/shelf/magic_shelf.dart';
import '../../stories/shelf/read_stories.dart';
import '../data/story_models.dart';
import 'package:almorabbi/widgets/ui/loading_view.dart';

/// The shelf's age filters.
enum StoryShelfFilter { all, young, older }

/// Whether [story] belongs under [filter]. Ranges overlap on purpose: a
/// 4–7 story is right for both a four-year-old and a seven-year-old.
bool storyMatchesFilter(Story story, StoryShelfFilter filter) {
  if (filter == StoryShelfFilter.all) return true;
  final range = ageRangeOf(story.ageGroup);
  if (range == null) return true; // unlabelled: never hidden
  return switch (filter) {
    StoryShelfFilter.young => range.min <= 4,
    StoryShelfFilter.older => range.max >= 7,
    StoryShelfFilter.all => true,
  };
}

class StoryBookshelfScreen extends ConsumerWidget {
  const StoryBookshelfScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final storiesAsync = ref.watch(storiesProvider);
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      backgroundColor: ShelfColors.wall,
      appBar: AppBar(
        title: Text(l10n.bedtimeStories),
        backgroundColor: ShelfColors.wall,
        foregroundColor: ShelfColors.ivory,
      ),
      body: storiesAsync.when(
        loading: () => const SingleChildScrollView(
          physics: NeverScrollableScrollPhysics(),
          child: LoadingView(count: 3, itemHeight: 220),
        ),
        error: (e, _) => EmptyState(
          emoji: '⚠️',
          title: l10n.storyLoadError,
          subtitle: userFacingError(context, e).body,
        ),
        data: (stories) => stories.isEmpty
            ? EmptyState(
                emoji: '📚',
                title: l10n.storyEmpty,
                subtitle: l10n.storyEmptyDesc,
              )
            : StoryShelf(stories: stories),
      ),
    );
  }
}

class StoryShelf extends StatefulWidget {
  const StoryShelf({super.key, required this.stories});
  final List<Story> stories;

  @override
  State<StoryShelf> createState() => _StoryShelfState();
}

class _StoryShelfState extends State<StoryShelf> {
  StoryShelfFilter _filter = StoryShelfFilter.all;

  /// Narration keys with a parent's recording still on disk — read once on
  /// open, not per card (`find` touches the filesystem).
  Set<String> _narrated = const {};

  @override
  void initState() {
    super.initState();
    _loadNarrations();
    _loadFinished();
  }

  Future<void> _loadNarrations() async {
    try {
      final keys = await NarrationStore.instance.available();
      if (mounted) setState(() => _narrated = keys);
    } catch (_) {
      // No store: no marks.
    }
  }

  Future<void> _listenInParentVoice(Story story) async {
    final found = await NarrationStore.instance.find(narrationKeyFor(story.id));
    if (found == null || !mounted) return;
    await Navigator.of(
      context,
    ).push(AppRoutes.screenOffPlayer(title: story.title, source: found.path));
  }

  Set<String> _finished = const {};

  Future<void> _loadFinished() async {
    final ids = await ReadStories.load();
    if (mounted) setState(() => _finished = ids);
  }

  Future<void> _open(Story story) async {
    final hasParent = _narrated.contains(narrationKeyFor(story.id));
    final nav = Navigator.of(context);
    await nav.push(
      BookPullout.route(
        story: story,
        onRead: () async {
          // Completes when the reader closes — then the star can light.
          await nav.pushReplacement(AppRoutes.storyReader(story));
          await _loadFinished();
        },
        onListenParent: hasParent
            ? () {
                nav.pop();
                _listenInParentVoice(story);
              }
            : null,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final visible = [
      for (final s in widget.stories)
        if (storyMatchesFilter(s, _filter)) s,
    ];
    return MagicShelf(
      stories: visible,
      finished: _finished,
      onOpenBook: _open,
      header: Padding(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const NoorPresence(size: 48, face: NoorFaceState.night),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    l10n.bedtimeStoriesDesc,
                    style: const TextStyle(
                      color: ShelfColors.ivory,
                      fontSize: 14.5,
                      height: 1.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final f in StoryShelfFilter.values)
                  ChoiceChip(
                    label: Text(switch (f) {
                      StoryShelfFilter.all => l10n.storyFilterAll(
                        widget.stories.length,
                      ),
                      StoryShelfFilter.young => l10n.storyFilterYoung,
                      StoryShelfFilter.older => l10n.storyFilterOlder,
                    }),
                    selected: _filter == f,
                    onSelected: (_) {
                      Haptics.selection();
                      setState(() => _filter = f);
                    },
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
