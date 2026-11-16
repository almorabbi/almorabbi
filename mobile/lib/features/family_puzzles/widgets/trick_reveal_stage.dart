/// Interactive Paper-Cut lateral-thinking stage («حرّك لتكتشف الحل»).
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../../core/haptics.dart';
import '../../../l10n/app_localizations.dart';
import '../../../theme/app_colors.dart';
import '../../../theme/design_tokens.dart';
import '../../../widgets/ui/bouncy_button.dart';
import '../data/family_puzzle_models.dart';

class TrickRevealStage extends StatefulWidget {
  const TrickRevealStage({
    super.key,
    required this.data,
    required this.solved,
    required this.onSolved,
  });

  final TrickRevealData data;
  final bool solved;
  final VoidCallback onSolved;

  @override
  State<TrickRevealStage> createState() => _TrickRevealStageState();
}

class _TrickRevealStageState extends State<TrickRevealStage> {
  late Map<String, Offset> _positions;
  final Set<String> _nudgedIds = {};
  final Set<String> _satisfiedTriggers = {};
  int _count = 0;
  bool _wrongCount = false;

  @override
  void initState() {
    super.initState();
    _resetState();
  }

  @override
  void didUpdateWidget(covariant TrickRevealStage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.data != widget.data ||
        (oldWidget.solved && !widget.solved)) {
      _resetState();
    }
  }

  void _resetState() {
    _positions = {
      for (final c in widget.data.covers) c.id: Offset(c.x, c.y),
    };
    _nudgedIds.clear();
    _satisfiedTriggers.clear();
    _count = 0;
    _wrongCount = false;
  }

  void _evaluateDragSolve(TrickCoverSpec cover, Offset pos) {
    if (widget.solved || widget.data.subMode != 'drag_solve') return;
    final zone = widget.data.targetZone;
    if (zone == null || cover.solveRole != 'trigger') return;

    final dist = (pos - Offset(zone.x, zone.y)).distance;
    final hitRadius = math.max(zone.radius, 0.22);
    if (dist <= hitRadius) {
      _satisfiedTriggers.add(cover.id);
      final requiredTriggers = widget.data.covers
          .where((c) => c.solveRole == 'trigger')
          .map((c) => c.id)
          .toSet();
      final solvedNow = widget.data.requireMode == 'all'
          ? _satisfiedTriggers.containsAll(requiredTriggers)
          : _satisfiedTriggers.isNotEmpty;
      if (solvedNow) {
        Haptics.success();
        widget.onSolved();
      } else {
        Haptics.selection();
      }
    }
  }

  void _onTapCover(TrickCoverSpec cover) {
    if (widget.solved || !cover.movable) return;
    Haptics.selection();
    setState(() {
      final wasNudged = _nudgedIds.contains(cover.id);
      if (widget.data.subMode == 'drag_solve') {
        final target = Offset(cover.nudgeX, cover.nudgeY);
        _positions[cover.id] = target;
        _nudgedIds.add(cover.id);
        _evaluateDragSolve(cover, target);
      } else {
        if (wasNudged) {
          _nudgedIds.remove(cover.id);
          _positions[cover.id] = Offset(cover.x, cover.y);
        } else {
          _nudgedIds.add(cover.id);
          _positions[cover.id] = Offset(cover.nudgeX, cover.nudgeY);
        }
      }
    });
  }

  void _onPanCover(TrickCoverSpec cover, DragUpdateDetails d, Size size) {
    if (widget.solved || !cover.movable || size.width <= 0 || size.height <= 0) {
      return;
    }
    final cur = _positions[cover.id] ?? Offset(cover.x, cover.y);
    final next = Offset(
      (cur.dx + d.delta.dx / size.width).clamp(0.06, 0.94),
      (cur.dy + d.delta.dy / size.height).clamp(0.06, 0.94),
    );
    setState(() {
      _positions[cover.id] = next;
      _nudgedIds.add(cover.id);
    });
    _evaluateDragSolve(cover, next);
  }

  void _submitCount() {
    if (widget.solved) return;
    if (_count == widget.data.targetCount) {
      setState(() => _wrongCount = false);
      Haptics.success();
      widget.onSolved();
    } else {
      setState(() => _wrongCount = true);
      Haptics.warning();
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = context.colors;
    final zone = widget.data.targetZone;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(18),
          child: DecoratedBox(
            decoration: BoxDecoration(
              border: Border.all(
                color: colors.paperShadow.withValues(alpha: 0.45),
                width: 2,
              ),
              borderRadius: BorderRadius.circular(18),
            ),
            child: AspectRatio(
              aspectRatio: 3 / 2,
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final w = constraints.maxWidth;
                  final h = constraints.maxHeight;
                  return Stack(
                    key: const ValueKey('trick_reveal_canvas'),
                    clipBehavior: Clip.hardEdge,
                    children: [
                      Positioned.fill(
                        child: SvgPicture.asset(
                          'assets/svg/stories/${widget.data.backdrop}.svg',
                          fit: BoxFit.cover,
                        ),
                      ),
                      for (final item in widget.data.underItems)
                        Positioned(
                          left: item.x * w - (w * item.scale) / 2,
                          top: item.y * h - (w * item.scale) / 2,
                          child: ExcludeSemantics(
                            child: SvgPicture.asset(
                              'assets/svg/stories/${item.prop}.svg',
                              width: w * item.scale,
                              height: w * item.scale,
                            ),
                          ),
                        ),
                      if (zone != null) ...[
                        Positioned(
                          left: zone.x * w - (w * 0.24) / 2,
                          top: zone.y * h - (w * 0.24) / 2,
                          child: ExcludeSemantics(
                            child: SvgPicture.asset(
                              'assets/svg/stories/${widget.solved ? zone.afterProp : zone.beforeProp}.svg',
                              width: w * 0.24,
                              height: w * 0.24,
                            ),
                          ),
                        ),
                        if (widget.solved && zone.afterBonusProp != null)
                          Positioned(
                            left: zone.x * w - (w * 0.14) / 2,
                            top: (zone.y - 0.14) * h - (w * 0.14) / 2,
                            child: ExcludeSemantics(
                              child: SvgPicture.asset(
                                'assets/svg/stories/${zone.afterBonusProp}.svg',
                                width: w * 0.14,
                                height: w * 0.14,
                              ),
                            ),
                          ),
                      ],
                      for (final cover in widget.data.covers)
                        if (!_isCoverConsumed(cover))
                          _buildCover(cover, w, h),
                    ],
                  );
                },
              ),
            ),
          ),
        ),
        if (widget.data.subMode == 'count_hidden') ...[
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _StepperButton(
                buttonKey: const ValueKey('trick_count_minus'),
                icon: Icons.remove_rounded,
                onTap: widget.solved || _count <= 0
                    ? null
                    : () {
                        Haptics.selection();
                        setState(() {
                          _count--;
                          _wrongCount = false;
                        });
                      },
              ),
              const SizedBox(width: 14),
              Container(
                key: const ValueKey('trick_count_value'),
                constraints: const BoxConstraints(minWidth: 68),
                padding:
                    const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                decoration: BoxDecoration(
                  color: colors.surface,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: _wrongCount
                        ? colors.dangerFg
                        : colors.primary.withValues(alpha: 0.35),
                    width: 1.5,
                  ),
                ),
                child: Text(
                  '${widget.solved ? widget.data.targetCount : _count}',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                        color: colors.ink,
                      ),
                ),
              ),
              const SizedBox(width: 14),
              _StepperButton(
                buttonKey: const ValueKey('trick_count_plus'),
                icon: Icons.add_rounded,
                onTap: widget.solved || _count >= 25
                    ? null
                    : () {
                        Haptics.selection();
                        setState(() {
                          _count++;
                          _wrongCount = false;
                        });
                      },
              ),
            ],
          ),
          if (_wrongCount) ...[
            const SizedBox(height: 8),
            Text(
              l10n.familyPuzzlesTryAgain,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: colors.dangerFg,
                    fontWeight: FontWeight.w700,
                  ),
            ),
          ],
          if (!widget.solved) ...[
            const SizedBox(height: 14),
            BouncyButton(
              key: const ValueKey('trick_count_check'),
              label: l10n.familyPuzzlesCheckAnswer,
              onTap: _submitCount,
            ),
          ],
        ],
      ],
    );
  }

  bool _isCoverConsumed(TrickCoverSpec cover) {
    if (widget.data.subMode != 'drag_solve') return false;
    if (widget.data.requireMode == 'all' &&
        _satisfiedTriggers.contains(cover.id)) {
      return true;
    }
    return widget.solved && cover.solveRole == 'trigger';
  }

  Widget _buildCover(TrickCoverSpec cover, double w, double h) {
    final pos = _positions[cover.id] ?? Offset(cover.x, cover.y);
    final sizePx = math.max(w * cover.scale, 48.0);
    final prop = (_nudgedIds.contains(cover.id) && cover.altProp != null)
        ? cover.altProp!
        : cover.prop;

    return Positioned(
      left: pos.dx * w - sizePx / 2,
      top: pos.dy * h - sizePx / 2,
      width: sizePx,
      height: sizePx,
      child: GestureDetector(
        key: ValueKey('trick_cover_${cover.id}'),
        behavior: HitTestBehavior.opaque,
        onTap: () => _onTapCover(cover),
        onPanUpdate: (d) => _onPanCover(cover, d, Size(w, h)),
        child: SvgPicture.asset(
          'assets/svg/stories/$prop.svg',
          width: sizePx,
          height: sizePx,
        ),
      ),
    );
  }
}

class _StepperButton extends StatelessWidget {
  const _StepperButton({
    required this.buttonKey,
    required this.icon,
    this.onTap,
  });

  final Key buttonKey;
  final IconData icon;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Material(
      color: colors.surfaceAlt,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        key: buttonKey,
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: SizedBox(
          width: Dt.minTouch,
          height: Dt.minTouch,
          child: Icon(
            icon,
            color: onTap == null ? colors.inkSoft : colors.primary,
          ),
        ),
      ),
    );
  }
}
