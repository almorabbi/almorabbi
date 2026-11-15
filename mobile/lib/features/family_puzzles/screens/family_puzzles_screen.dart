/// Lobby screen for «فوازير نور العائلية».
///
/// Displays today's 3-puzzle co-play round hero banner alongside all 16
/// Paper-Cut puzzles grouped across four cognitive skills: observation,
/// lateral thinking, spatial assembly, and logic flow.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/analytics.dart';
import '../../../core/app_routes.dart';
import '../../../core/clock.dart';
import '../../../l10n/app_localizations.dart';
import '../../../theme/app_colors.dart';
import '../../../theme/app_palette.dart';
import '../../../theme/design_tokens.dart';
import '../../../widgets/ui/bouncy_button.dart';
import '../../../widgets/ui/brand_glyph.dart';
import '../../../widgets/ui/directional_chevron.dart';
import '../../onboarding/providers/onboarding_providers.dart';
import '../../routine/providers/child_mode_providers.dart';
import '../data/family_puzzle_models.dart';
import '../data/family_puzzle_store.dart';

class FamilyPuzzlesScreen extends ConsumerStatefulWidget {
  const FamilyPuzzlesScreen({
    super.key,
    this.source = GameSources.unknown,
  });

  final String source;

  @override
  ConsumerState<FamilyPuzzlesScreen> createState() =>
      _FamilyPuzzlesScreenState();
}

class _FamilyPuzzlesScreenState extends ConsumerState<FamilyPuzzlesScreen> {
  FamilyPuzzlePack? _pack;
  FamilyPuzzleProgress _progress = const FamilyPuzzleProgress();
  String? _loadedLang;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    unawaited(Analytics.familyPuzzlesOpened(widget.source));
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final lang = Localizations.localeOf(context).languageCode;
    if (_loadedLang != lang) {
      _loadedLang = lang;
      unawaited(_loadData(lang));
    }
  }

  int get _effectiveChildId {
    final prefsAsync = ref.read(sharedPreferencesProvider);
    if (!prefsAsync.hasValue) return 0;
    return ref.read(activeChildProfileProvider)?.id ?? 0;
  }

  Future<void> _loadData(String lang) async {
    try {
      final pack = await loadFamilyPuzzlePack(lang);
      final progress = await FamilyPuzzleStore.load(childId: _effectiveChildId);
      if (!mounted) return;
      setState(() {
        _pack = pack;
        _progress = progress;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  Future<void> _refreshProgress() async {
    final progress = await FamilyPuzzleStore.load(childId: _effectiveChildId);
    if (!mounted) return;
    setState(() => _progress = progress);
  }

  Future<void> _launchDailyRound(DateTime now) async {
    final pack = _pack;
    if (pack == null || pack.puzzles.isEmpty) return;
    final childId = _effectiveChildId;
    final daily = pickDailyRound(pack.puzzles, now, childId: childId);
    final offscreen = pickOffscreenActivity(
      pack.offscreenActivities,
      now,
      childId: childId,
    );
    await Navigator.of(context).push(
      AppRoutes.familyPuzzleRunner(
        puzzles: daily,
        offscreenActivity: offscreen,
        childId: childId,
        isDailyRound: true,
        source: widget.source,
      ),
    );
    await _refreshProgress();
  }

  Future<void> _launchSinglePuzzle(FamilyPuzzle puzzle, DateTime now) async {
    final pack = _pack;
    final childId = _effectiveChildId;
    final offscreen = pack == null
        ? null
        : pickOffscreenActivity(pack.offscreenActivities, now, childId: childId);
    await Navigator.of(context).push(
      AppRoutes.familyPuzzleRunner(
        puzzles: [puzzle],
        offscreenActivity: offscreen,
        childId: childId,
        isDailyRound: false,
        source: widget.source,
      ),
    );
    await _refreshProgress();
  }

  String _skillTitle(AppLocalizations l10n, PuzzleSkill skill) => switch (skill) {
        PuzzleSkill.observation => l10n.familyPuzzlesSkillObservation,
        PuzzleSkill.lateral => l10n.familyPuzzlesSkillLateral,
        PuzzleSkill.spatial => l10n.familyPuzzlesSkillSpatial,
        PuzzleSkill.logic => l10n.familyPuzzlesSkillLogic,
      };

  BrandIcon _skillGlyph(PuzzleSkill skill) => switch (skill) {
        PuzzleSkill.observation => BrandIcon.sun,
        PuzzleSkill.lateral => BrandIcon.lantern,
        PuzzleSkill.spatial => BrandIcon.path,
        PuzzleSkill.logic => BrandIcon.sprig,
      };

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = context.colors;
    final now = ref.watch(clockProvider)();
    final childMode = ref.watch(childModeProvider);
    final remaining = childMode.remainingSeconds;
    final spent = childMode.active && remaining != null && remaining <= 0;

    return Scaffold(
      backgroundColor: colors.surface,
      appBar: AppBar(title: Text(l10n.familyPuzzlesTitle)),
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _buildContent(context, l10n, colors, now, spent),
      ),
    );
  }

  Widget _buildContent(
    BuildContext context,
    AppLocalizations l10n,
    AppPalette colors,
    DateTime now,
    bool spent,
  ) {
    final pack = _pack;
    final roundDone = _progress.isRoundDoneOn(now);
    final puzzles = pack?.puzzles ?? const <FamilyPuzzle>[];

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 28),
      children: [
        if (spent)
          Padding(
            padding: const EdgeInsets.only(bottom: 14),
            child: Text(
              l10n.gamesBudgetSpent,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: colors.textSecondary,
                  ),
            ),
          ),
        Material(
          color: colors.surfaceAlt,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(Dt.rCard),
            side: BorderSide(color: colors.track),
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(
                height: 164,
                child: Image.asset(
                  'assets/images/puzzles/family_puzzles_hero.png',
                  fit: BoxFit.cover,
                  errorBuilder: (context, error, stackTrace) => ColoredBox(
                    color: colors.paperEmerald.withValues(alpha: 0.2),
                    child: Center(
                      child: BrandGlyph(
                        BrandIcon.lantern,
                        size: 56,
                        color: colors.paperEmerald,
                      ),
                    ),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Wrap(
                      spacing: 8,
                      runSpacing: 6,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: colors.accent.withValues(alpha: 0.18),
                            borderRadius: BorderRadius.circular(Dt.rChip),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              BrandGlyph(
                                BrandIcon.lantern,
                                size: 15,
                                color: colors.accentDeep,
                              ),
                              const SizedBox(width: 6),
                              Flexible(
                                child: Text(
                                  l10n.familyPuzzlesCoPlayBadge,
                                  style: Theme.of(context)
                                      .textTheme
                                      .labelMedium
                                      ?.copyWith(
                                        color: colors.accentDeep,
                                        fontWeight: FontWeight.w800,
                                      ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        if (roundDone)
                          Container(
                            key: const ValueKey('family_puzzles_round_done'),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: colors.primary.withValues(alpha: 0.14),
                              borderRadius: BorderRadius.circular(Dt.rChip),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                BrandGlyph(
                                  BrandIcon.star,
                                  size: 14,
                                  color: colors.primary,
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  l10n.familyPuzzlesRoundDoneBadge,
                                  style: Theme.of(context)
                                      .textTheme
                                      .labelMedium
                                      ?.copyWith(
                                        color: colors.primary,
                                        fontWeight: FontWeight.w800,
                                      ),
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Text(
                      l10n.familyPuzzlesTitle,
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                            color: colors.ink,
                            fontWeight: FontWeight.w800,
                          ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      l10n.familyPuzzlesSubtitle,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: colors.textSecondary,
                            height: 1.45,
                          ),
                    ),
                    const SizedBox(height: 14),
                    BouncyButton(
                      key: const ValueKey('family_puzzles_start_round'),
                      label: roundDone
                          ? l10n.familyPuzzlesReplayRound
                          : l10n.familyPuzzlesStartRound,
                      onTap: (spent || puzzles.isEmpty)
                          ? null
                          : () => _launchDailyRound(now),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        for (final skill in PuzzleSkill.values) ...[
          _buildSkillSection(
            context,
            l10n,
            colors,
            skill,
            [
              for (final p in puzzles)
                if (p.skill == skill) p,
            ],
            now,
            spent,
          ),
        ],
      ],
    );
  }

  Widget _buildSkillSection(
    BuildContext context,
    AppLocalizations l10n,
    AppPalette colors,
    PuzzleSkill skill,
    List<FamilyPuzzle> items,
    DateTime now,
    bool spent,
  ) {
    if (items.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              children: [
                BrandGlyph(_skillGlyph(skill), size: 20, color: colors.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _skillTitle(l10n, skill),
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          color: colors.ink,
                          fontWeight: FontWeight.w800,
                        ),
                  ),
                ),
              ],
            ),
          ),
          for (final p in items)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Material(
                color: colors.surface,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(Dt.rCard),
                  side: BorderSide(color: colors.track),
                ),
                child: InkWell(
                  key: ValueKey('family_puzzle_card_${p.id}'),
                  borderRadius: BorderRadius.circular(Dt.rCard),
                  onTap: spent ? null : () => _launchSinglePuzzle(p, now),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 12,
                    ),
                    child: Row(
                      children: [
                        BrandGlyph(
                          _skillGlyph(skill),
                          size: 22,
                          color: _progress.solvedIds.contains(p.id)
                              ? colors.primary
                              : colors.textSecondary,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                p.title,
                                style: Theme.of(context)
                                    .textTheme
                                    .titleSmall
                                    ?.copyWith(
                                      color: colors.ink,
                                      fontWeight: FontWeight.w800,
                                    ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                p.subtitle,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: Theme.of(context)
                                    .textTheme
                                    .bodySmall
                                    ?.copyWith(
                                      color: colors.textSecondary,
                                    ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        if (_progress.solvedIds.contains(p.id))
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 4),
                            child: BrandGlyph(
                              BrandIcon.star,
                              size: 18,
                              color: colors.accentDeep,
                            ),
                          ),
                        if (spent)
                          Icon(
                            Icons.lock_outline_rounded,
                            size: 18,
                            color: colors.textSecondary,
                          )
                        else
                          DirectionalChevron(color: colors.textSecondary),
                      ],
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
