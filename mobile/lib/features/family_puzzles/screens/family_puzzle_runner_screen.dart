/// Interactive puzzle runner for «فوازير نور العائلية».
///
/// Hosts either a single selected puzzle or a 3-puzzle daily co-play round,
/// providing «همسة للمربّي» (Socratic guidance without spoiling the answer),
/// an instant calm reset, and an offscreen family brain-play suggestion on
/// round completion — with zero ads, zero streaks, and zero coin bribes.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:just_audio/just_audio.dart';

import '../../../config/app_config.dart';
import '../../../core/analytics.dart';
import '../../../core/app_routes.dart';
import '../../../core/clock.dart';
import '../../../core/sound_fx.dart';
import '../../../l10n/app_localizations.dart';
import '../../../state/chat_notifier.dart' show tgClientProvider;
import '../../../theme/app_colors.dart';
import '../../../theme/app_palette.dart';
import '../../../theme/design_tokens.dart';
import '../../../widgets/ui/bouncy_button.dart';
import '../../../widgets/ui/brand_glyph.dart';
import '../../onboarding/providers/onboarding_providers.dart';
import '../../program/data/review_prompt.dart';
import '../data/family_puzzle_models.dart';
import '../data/family_puzzle_store.dart';
import '../widgets/parent_whisper_sheet.dart';
import '../widgets/piece_assembly_stage.dart';
import '../widgets/spot_diff_stage.dart';
import '../widgets/trick_reveal_stage.dart';
import '../widgets/water_path_stage.dart';

class FamilyPuzzleRunnerScreen extends ConsumerStatefulWidget {
  const FamilyPuzzleRunnerScreen({
    super.key,
    required this.puzzles,
    this.offscreenActivity,
    this.childId = 0,
    this.initialIndex = 0,
    this.isDailyRound = false,
    this.source = GameSources.unknown,
  });

  final List<FamilyPuzzle> puzzles;
  final OffscreenBrainActivity? offscreenActivity;
  final int childId;
  final int initialIndex;
  final bool isDailyRound;
  final String source;

  @override
  ConsumerState<FamilyPuzzleRunnerScreen> createState() =>
      _FamilyPuzzleRunnerScreenState();
}

class _FamilyPuzzleRunnerScreenState
    extends ConsumerState<FamilyPuzzleRunnerScreen> {
  late int _index;
  bool _solved = false;
  int _resetEpoch = 0;
  bool _roundFinished = false;
  AudioPlayer? _voicePlayer;
  StreamSubscription<PlayerState>? _voiceSub;
  bool _playingAudio = false;

  @override
  void initState() {
    super.initState();
    final maxIdx = widget.puzzles.isEmpty ? 0 : widget.puzzles.length - 1;
    _index = widget.initialIndex.clamp(0, maxIdx);
  }

  @override
  void dispose() {
    unawaited(_voiceSub?.cancel());
    unawaited(_voicePlayer?.dispose());
    super.dispose();
  }

  Future<void> _stopAudio() async {
    try {
      await _voicePlayer?.stop();
    } catch (_) {
      // Ignore platform player shutdown issues in tests/offline.
    }
    if (mounted) setState(() => _playingAudio = false);
  }

  Future<void> _toggleAudio(FamilyPuzzle puzzle, AppLocalizations l10n) async {
    final path = puzzle.audioPath;
    if (path == null || path.isEmpty) return;
    if (_playingAudio) {
      await _stopAudio();
      return;
    }
    try {
      final player = _voicePlayer ??= AudioPlayer();
      _voiceSub ??= player.playerStateStream.listen((st) {
        if (st.processingState == ProcessingState.completed && mounted) {
          setState(() => _playingAudio = false);
        }
      });
      final cleanBase = AppConfig.apiBaseUrl.endsWith('/')
          ? AppConfig.apiBaseUrl.substring(0, AppConfig.apiBaseUrl.length - 1)
          : AppConfig.apiBaseUrl;
      final cleanPath = path.startsWith('/') ? path.substring(1) : path;
      await player.setUrl('$cleanBase/$cleanPath');
      if (!mounted) return;
      setState(() => _playingAudio = true);
      await player.play();
    } catch (_) {
      if (!mounted) return;
      setState(() => _playingAudio = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.ramadanFawazirAudioOffline)),
      );
    }
  }

  int get _effectiveChildId {
    if (widget.childId != 0) return widget.childId;
    final prefsAsync = ref.read(sharedPreferencesProvider);
    if (!prefsAsync.hasValue) return 0;
    return ref.read(activeChildProfileProvider)?.id ?? 0;
  }

  void _resetCurrentPuzzle() {
    setState(() {
      _solved = false;
      _resetEpoch++;
    });
  }

  void _handlePuzzleSolved(FamilyPuzzle puzzle) {
    if (_solved || _roundFinished) return;
    setState(() => _solved = true);
    unawaited(SoundFx.lantern());
    unawaited(Analytics.familyPuzzleSolved(puzzle.id, puzzle.kind.wire));
    unawaited(ReviewPrompt.recordMoment());
    unawaited(
      FamilyPuzzleStore.markSolved(puzzle.id, childId: _effectiveChildId),
    );
    final night = puzzle.ramadanNight;
    if (night != null && night >= 1 && night <= 30) {
      try {
        final f = ref.read(tgClientProvider).markRamadanFawazir(day: night);
        unawaited(f.catchError((Object _) => <String, dynamic>{}));
      } catch (_) {
        // Offline or stubbed client without markRamadanFawazir never blocks solving.
      }
    }
  }

  Future<void> _advanceOrFinish() async {
    await _stopAudio();
    if (_index + 1 < widget.puzzles.length) {
      setState(() {
        _index++;
        _solved = false;
        _resetEpoch = 0;
      });
      return;
    }

    if (widget.isDailyRound || widget.puzzles.length > 1) {
      final now = ref.read(clockProvider)();
      final updated = await FamilyPuzzleStore.markRoundCompleted(
        now,
        childId: _effectiveChildId,
      );
      unawaited(SoundFx.lantern());
      unawaited(
        Analytics.familyRoundCompleted(
          updated.roundsCompleted,
          widget.source,
        ),
      );
      if (!mounted) return;
      setState(() => _roundFinished = true);
      unawaited(ReviewPrompt.maybeAsk(context, source: 'family_puzzles'));
      return;
    }

    if (mounted) {
      Navigator.of(context).pop(true);
    }
  }

  String _skillLabel(AppLocalizations l10n, PuzzleSkill skill) => switch (skill) {
        PuzzleSkill.observation => l10n.familyPuzzlesSkillObservation,
        PuzzleSkill.lateral => l10n.familyPuzzlesSkillLateral,
        PuzzleSkill.spatial => l10n.familyPuzzlesSkillSpatial,
        PuzzleSkill.logic => l10n.familyPuzzlesSkillLogic,
      };

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = context.colors;

    if (widget.puzzles.isEmpty) {
      return Scaffold(
        backgroundColor: colors.surface,
        appBar: AppBar(title: Text(l10n.familyPuzzlesTitle)),
        body: Center(
          child: BouncyButton(
            label: l10n.familyPuzzlesBackToLobby,
            expanded: false,
            onTap: () => Navigator.of(context).pop(),
          ),
        ),
      );
    }

    final puzzle = widget.puzzles[_index];

    return Scaffold(
      backgroundColor: colors.surface,
      appBar: AppBar(
        title: Text(
          _roundFinished ? l10n.familyPuzzlesRoundCompleteTitle : puzzle.title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        actions: [
          if (!_roundFinished)
            IconButton(
              key: const ValueKey('family_puzzle_reset'),
              tooltip: l10n.familyPuzzlesReset,
              icon: const Icon(Icons.refresh_rounded),
              onPressed: _resetCurrentPuzzle,
            ),
        ],
      ),
      body: SafeArea(
        child: _roundFinished
            ? _buildRoundCompleteView(context, l10n, colors)
            : _buildActivePuzzleView(context, l10n, colors, puzzle),
      ),
    );
  }

  Widget _buildActivePuzzleView(
    BuildContext context,
    AppLocalizations l10n,
    AppPalette colors,
    FamilyPuzzle puzzle,
  ) {
    final stageKey = ValueKey('${puzzle.id}_$_resetEpoch');
    final isLastInQueue = _index + 1 >= widget.puzzles.length;
    final nextLabel = !isLastInQueue
        ? l10n.familyPuzzlesNext
        : (widget.isDailyRound || widget.puzzles.length > 1)
            ? l10n.familyPuzzlesFinishRound
            : l10n.familyPuzzlesBackToLobby;

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            alignment: WrapAlignment.spaceBetween,
            children: [
              Wrap(
                spacing: 8,
                runSpacing: 6,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  if (widget.puzzles.length > 1)
                    Container(
                      key: const ValueKey('family_puzzle_round_indicator'),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 5,
                      ),
                      decoration: BoxDecoration(
                        color: colors.surfaceAlt,
                        borderRadius: BorderRadius.circular(Dt.rChip),
                        border: Border.all(color: colors.track),
                      ),
                      child: Text(
                        '${_index + 1} / ${widget.puzzles.length}',
                        style: Theme.of(context).textTheme.labelMedium?.copyWith(
                              color: colors.ink,
                              fontWeight: FontWeight.w800,
                            ),
                      ),
                    ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 5,
                    ),
                    decoration: BoxDecoration(
                      color: colors.primary.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(Dt.rChip),
                    ),
                    child: Text(
                      _skillLabel(l10n, puzzle.skill),
                      style: Theme.of(context).textTheme.labelMedium?.copyWith(
                            color: colors.primary,
                            fontWeight: FontWeight.w800,
                          ),
                    ),
                  ),
                ],
              ),
              Wrap(
                spacing: 8,
                runSpacing: 6,
                children: [
                  if (puzzle.audioPath != null)
                    OutlinedButton.icon(
                      key: const ValueKey('family_puzzle_audio_btn'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: colors.primary,
                        backgroundColor: _playingAudio
                            ? colors.primary.withValues(alpha: 0.14)
                            : colors.surfaceAlt,
                        side: BorderSide(
                          color: colors.primary.withValues(alpha: 0.55),
                        ),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(Dt.rChip),
                        ),
                      ),
                      onPressed: () => _toggleAudio(puzzle, l10n),
                      icon: Icon(
                        _playingAudio
                            ? Icons.pause_rounded
                            : Icons.volume_up_rounded,
                        size: 18,
                      ),
                      label: Text(
                        _playingAudio
                            ? l10n.ramadanFawazirPauseBtn
                            : l10n.ramadanFawazirListenBtn,
                        style: Theme.of(context).textTheme.labelMedium?.copyWith(
                              fontWeight: FontWeight.w800,
                              color: colors.ink,
                            ),
                      ),
                    ),
                  OutlinedButton.icon(
                    key: const ValueKey('family_puzzle_whisper_btn'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: colors.ink,
                      backgroundColor: colors.surfaceAlt,
                      side: BorderSide(
                        color: colors.accent.withValues(alpha: 0.65),
                      ),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(Dt.rChip),
                      ),
                    ),
                    onPressed: () => showParentWhisperSheet(
                      context,
                      whisperText: puzzle.parentWhisper,
                    ),
                    icon: BrandGlyph(
                      BrandIcon.lantern,
                      size: 18,
                      color: colors.accentDeep,
                    ),
                    label: Text(
                      l10n.familyPuzzlesWhisperBtn,
                      style: Theme.of(context).textTheme.labelMedium?.copyWith(
                            fontWeight: FontWeight.w800,
                            color: colors.ink,
                          ),
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: colors.surfaceAlt,
              borderRadius: BorderRadius.circular(Dt.rCard),
              border: Border.all(color: colors.track),
            ),
            child: Text(
              puzzle.subtitle,
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                    color: colors.ink,
                    fontWeight: FontWeight.w700,
                    height: 1.45,
                  ),
            ),
          ),
          const SizedBox(height: 14),
          switch (puzzle.kind) {
            PuzzleKind.spotDiff when puzzle.spotDiff != null => SpotDiffStage(
                key: stageKey,
                data: puzzle.spotDiff!,
                solved: _solved,
                onSolved: () => _handlePuzzleSolved(puzzle),
              ),
            PuzzleKind.trickReveal when puzzle.trickReveal != null =>
              TrickRevealStage(
                key: stageKey,
                data: puzzle.trickReveal!,
                solved: _solved,
                onSolved: () => _handlePuzzleSolved(puzzle),
              ),
            PuzzleKind.pieceAssembly when puzzle.pieceAssembly != null =>
              PieceAssemblyStage(
                key: stageKey,
                data: puzzle.pieceAssembly!,
                solved: _solved,
                onSolved: () => _handlePuzzleSolved(puzzle),
              ),
            PuzzleKind.waterPath when puzzle.waterPath != null => WaterPathStage(
                key: stageKey,
                data: puzzle.waterPath!,
                solved: _solved,
                onSolved: () => _handlePuzzleSolved(puzzle),
              ),
            _ => const SizedBox.shrink(),
          },
          if (_solved) ...[
            const SizedBox(height: 16),
            Container(
              key: const ValueKey('family_puzzle_praise_banner'),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: colors.primary.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(Dt.rCard),
                border: Border.all(
                  color: colors.primary.withValues(alpha: 0.45),
                ),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  BrandGlyph(
                    BrandIcon.star,
                    size: 24,
                    color: colors.accentDeep,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      puzzle.praise,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: colors.ink,
                            fontWeight: FontWeight.w700,
                            height: 1.5,
                          ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            BouncyButton(
              key: const ValueKey('family_puzzle_next_btn'),
              label: nextLabel,
              onTap: _advanceOrFinish,
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildRoundCompleteView(
    BuildContext context,
    AppLocalizations l10n,
    AppPalette colors,
  ) {
    final offscreen = widget.offscreenActivity;
    return SingleChildScrollView(
      key: const ValueKey('family_round_complete_view'),
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: colors.surfaceAlt,
              borderRadius: BorderRadius.circular(Dt.rCard),
              border: Border.all(color: colors.accent.withValues(alpha: 0.5)),
            ),
            child: Column(
              children: [
                BrandGlyph(
                  BrandIcon.lantern,
                  size: 48,
                  color: colors.accentDeep,
                ),
                const SizedBox(height: 12),
                Text(
                  l10n.familyPuzzlesRoundCompleteTitle,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        color: colors.ink,
                        fontWeight: FontWeight.w800,
                      ),
                ),
                const SizedBox(height: 8),
                Text(
                  l10n.familyPuzzlesRoundCompleteBody,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: colors.textSecondary,
                        height: 1.5,
                      ),
                ),
              ],
            ),
          ),
          if (offscreen != null) ...[
            const SizedBox(height: 16),
            Container(
              key: const ValueKey('family_round_offscreen_card'),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: colors.primary.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(Dt.rCard),
                border: Border.all(
                  color: colors.primary.withValues(alpha: 0.35),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      BrandGlyph(
                        BrandIcon.sprig,
                        size: 20,
                        color: colors.primary,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          l10n.familyPuzzlesOffscreenTitle,
                          style:
                              Theme.of(context).textTheme.labelLarge?.copyWith(
                                    color: colors.primary,
                                    fontWeight: FontWeight.w800,
                                  ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    offscreen.title,
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          color: colors.ink,
                          fontWeight: FontWeight.w800,
                        ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    offscreen.body,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: colors.ink,
                          height: 1.5,
                        ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 20),
          BouncyButton(
            key: const ValueKey('family_round_done_back'),
            label: l10n.familyPuzzlesBackToLobby,
            onTap: () => Navigator.of(context).pop(true),
          ),
        ],
      ),
    );
  }
}
