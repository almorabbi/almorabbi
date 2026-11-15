/// Interactive dual-scene Paper-Cut «Spot the Differences» stage.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../../core/haptics.dart';
import '../../../l10n/app_localizations.dart';
import '../../../theme/app_colors.dart';
import '../../../theme/design_tokens.dart';
import '../data/family_puzzle_models.dart';

class SpotDiffStage extends StatefulWidget {
  const SpotDiffStage({
    super.key,
    required this.data,
    required this.solved,
    required this.onSolved,
  });

  final SpotDiffData data;
  final bool solved;
  final VoidCallback onSolved;

  @override
  State<SpotDiffStage> createState() => _SpotDiffStageState();
}

class _SpotDiffStageState extends State<SpotDiffStage> {
  final Set<String> _foundIds = {};
  Offset? _missTapNorm;

  @override
  void didUpdateWidget(covariant SpotDiffStage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.data != widget.data ||
        (oldWidget.solved && !widget.solved)) {
      _foundIds.clear();
      _missTapNorm = null;
    }
  }

  void _handleTap(Offset localPos, Size size) {
    if (widget.solved || size.width <= 0 || size.height <= 0) return;
    final nx = (localPos.dx / size.width).clamp(0.0, 1.0);
    final ny = (localPos.dy / size.height).clamp(0.0, 1.0);

    SpotDiffChange? match;
    var bestDist = double.infinity;
    for (final diff in widget.data.differences) {
      if (_foundIds.contains(diff.id)) continue;
      final tap = Offset(nx, ny);
      final dTop = (tap - Offset(diff.hitX, diff.hitY)).distance;
      final dBottom =
          (tap - Offset(diff.hitX + diff.dx, diff.hitY + diff.dy)).distance;
      final dist = math.min(dTop, dBottom);
      if (dist <= 0.13 && dist < bestDist) {
        bestDist = dist;
        match = diff;
      }
    }

    if (match != null) {
      setState(() {
        _foundIds.add(match!.id);
        _missTapNorm = null;
      });
      Haptics.success();
      if (_foundIds.length == widget.data.differences.length) {
        widget.onSolved();
      }
    } else {
      setState(() => _missTapNorm = Offset(nx, ny));
      Haptics.warning();
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = context.colors;
    final total = widget.data.differences.length;
    final foundCount = widget.solved ? total : _foundIds.length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Center(
          child: Container(
            key: const ValueKey('spot_diff_progress_pill'),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
            decoration: BoxDecoration(
              color: colors.surfaceAlt,
              borderRadius: BorderRadius.circular(Dt.rChip),
              border: Border.all(
                color: colors.primary.withValues(alpha: 0.25),
              ),
            ),
            child: Text(
              l10n.familyPuzzlesDiffProgress(foundCount, total),
              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    color: colors.ink,
                    fontWeight: FontWeight.w800,
                  ),
            ),
          ),
        ),
        const SizedBox(height: 10),
        _ScenePanel(
          panelKey: const ValueKey('spot_diff_top_scene'),
          data: widget.data,
          isBottomVariant: false,
          foundIds: _foundIds,
          showAllRings: widget.solved,
          missTapNorm: _missTapNorm,
          onTap: _handleTap,
        ),
        const SizedBox(height: 10),
        _ScenePanel(
          panelKey: const ValueKey('spot_diff_bottom_scene'),
          data: widget.data,
          isBottomVariant: true,
          foundIds: _foundIds,
          showAllRings: widget.solved,
          missTapNorm: _missTapNorm,
          onTap: _handleTap,
        ),
      ],
    );
  }
}

class _ScenePanel extends StatelessWidget {
  const _ScenePanel({
    required this.panelKey,
    required this.data,
    required this.isBottomVariant,
    required this.foundIds,
    required this.showAllRings,
    required this.missTapNorm,
    required this.onTap,
  });

  final Key panelKey;
  final SpotDiffData data;
  final bool isBottomVariant;
  final Set<String> foundIds;
  final bool showAllRings;
  final Offset? missTapNorm;
  final void Function(Offset localPos, Size size) onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final diffByItem = {
      for (final d in data.differences) d.itemId: d,
    };

    return ClipRRect(
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
              return GestureDetector(
                key: panelKey,
                behavior: HitTestBehavior.opaque,
                onTapUp: (d) => onTap(d.localPosition, Size(w, h)),
                child: Stack(
                  clipBehavior: Clip.hardEdge,
                  children: [
                    Positioned.fill(
                      child: SvgPicture.asset(
                        'assets/svg/stories/${data.backdrop}.svg',
                        fit: BoxFit.cover,
                      ),
                    ),
                    for (final item in data.baseItems)
                      ..._buildItem(w, h, item, diffByItem[item.id]),
                    for (final diff in data.differences)
                      if (showAllRings || foundIds.contains(diff.id))
                        _FoundRing(
                          cx: (diff.hitX + (isBottomVariant ? diff.dx : 0)) * w,
                          cy: (diff.hitY + (isBottomVariant ? diff.dy : 0)) * h,
                          ringColor: colors.paperGold,
                          shadowColor: colors.paperShadow,
                        ),
                    if (missTapNorm != null)
                      Positioned(
                        left: missTapNorm!.dx * w - 12,
                        top: missTapNorm!.dy * h - 12,
                        child: Container(
                          width: 24,
                          height: 24,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: colors.dangerFg.withValues(alpha: 0.75),
                              width: 2,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  List<Widget> _buildItem(
    double w,
    double h,
    SceneItemSpec item,
    SpotDiffChange? change,
  ) {
    var prop = item.prop;
    var x = item.x;
    var y = item.y;
    var scale = item.scale;
    var flipX = false;

    if (isBottomVariant && change != null) {
      switch (change.mode) {
        case SpotDiffMode.missing:
          return const [];
        case SpotDiffMode.swap:
          prop = change.altProp ?? prop;
        case SpotDiffMode.shift:
          x += change.dx;
          y += change.dy;
        case SpotDiffMode.flip:
          flipX = true;
        case SpotDiffMode.scale:
          scale = change.altScale ?? (scale * 1.45);
      }
    }

    final sizePx = w * scale;
    Widget child = SvgPicture.asset(
      'assets/svg/stories/$prop.svg',
      width: sizePx,
      height: sizePx,
    );
    if (flipX) {
      child = Transform.flip(flipX: true, child: child);
    }
    return [
      Positioned(
        left: x * w - sizePx / 2,
        top: y * h - sizePx / 2,
        child: ExcludeSemantics(child: child),
      ),
    ];
  }
}

class _FoundRing extends StatelessWidget {
  const _FoundRing({
    required this.cx,
    required this.cy,
    required this.ringColor,
    required this.shadowColor,
  });

  final double cx;
  final double cy;
  final Color ringColor;
  final Color shadowColor;

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: cx - 18,
      top: cy - 18,
      child: IgnorePointer(
        child: Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: ringColor, width: 3.5),
            boxShadow: [
              BoxShadow(
                color: shadowColor.withValues(alpha: 0.45),
                blurRadius: 0,
                offset: const Offset(2, 2),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
