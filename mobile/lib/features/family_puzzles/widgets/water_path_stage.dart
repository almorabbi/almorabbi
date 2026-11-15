/// Interactive rotating Paper-Cut water canal stage («مسار الماء»).
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../../core/haptics.dart';
import '../../../theme/app_colors.dart';
import '../data/family_puzzle_models.dart';

class WaterPathStage extends StatefulWidget {
  const WaterPathStage({
    super.key,
    required this.data,
    required this.solved,
    required this.onSolved,
  });

  final WaterPathData data;
  final bool solved;
  final VoidCallback onSolved;

  @override
  State<WaterPathStage> createState() => _WaterPathStageState();
}

class _WaterPathStageState extends State<WaterPathStage> {
  late List<List<int>> _rotations;

  @override
  void initState() {
    super.initState();
    _reset();
  }

  @override
  void didUpdateWidget(covariant WaterPathStage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.data != widget.data ||
        (oldWidget.solved && !widget.solved)) {
      _reset();
    }
  }

  void _reset() {
    _rotations = [
      for (final row in widget.data.cells)
        [for (final c in row) c.initialRot],
    ];
  }

  void _rotateTile(int r, int c) {
    if (widget.solved) return;
    final cell = widget.data.cells[r][c];
    if (cell.fixed ||
        cell.type == WaterCellType.empty ||
        cell.type == WaterCellType.rock ||
        cell.type == WaterCellType.basin ||
        cell.type == WaterCellType.cross) {
      return;
    }

    setState(() {
      _rotations[r][c] = (_rotations[r][c] + 1) % 4;
    });
    final flow = WaterPathSolver.computeFlow(widget.data, _rotations);
    if (flow.allSolved) {
      Haptics.success();
      widget.onSolved();
    } else {
      Haptics.selection();
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final flow = WaterPathSolver.computeFlow(widget.data, _rotations);
    final targetsByCoord = {
      for (final t in widget.data.targets) math.Point<int>(t.col, t.row): t,
    };

    return Container(
      key: const ValueKey('water_path_grid'),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: colors.surfaceAlt,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: colors.paperShadow.withValues(alpha: 0.45),
          width: 2,
        ),
      ),
      child: Column(
        children: [
          for (var r = 0; r < widget.data.rows; r++)
            Padding(
              padding: EdgeInsets.only(
                bottom: r < widget.data.rows - 1 ? 6 : 0,
              ),
              child: Row(
                children: [
                  for (var c = 0; c < widget.data.cols; c++)
                    Expanded(
                      child: Padding(
                        padding: EdgeInsetsDirectional.only(
                          end: c < widget.data.cols - 1 ? 6 : 0,
                        ),
                        child: AspectRatio(
                          aspectRatio: 1.0,
                          child: _WaterTile(
                            tileKey: ValueKey('water_cell_${r}_$c'),
                            cell: widget.data.cells[r][c],
                            rot: _rotations[r][c],
                            isSource: r == widget.data.sourceRow &&
                                c == widget.data.sourceCol,
                            isWet: flow.wetCells
                                .contains(math.Point<int>(c, r)),
                            target: targetsByCoord[math.Point<int>(c, r)],
                            onTap: () => _rotateTile(r, c),
                          ),
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

class _WaterTile extends StatelessWidget {
  const _WaterTile({
    required this.tileKey,
    required this.cell,
    required this.rot,
    required this.isSource,
    required this.isWet,
    this.target,
    required this.onTap,
  });

  final Key tileKey;
  final WaterCellSpec cell;
  final int rot;
  final bool isSource;
  final bool isWet;
  final WaterTargetSpec? target;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final canRotate = !cell.fixed &&
        (cell.type == WaterCellType.straight ||
            cell.type == WaterCellType.corner ||
            cell.type == WaterCellType.tee);

    return Material(
      color: isWet
          ? colors.primary.withValues(alpha: 0.14)
          : colors.surface,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        key: tileKey,
        borderRadius: BorderRadius.circular(14),
        onTap: canRotate ? onTap : null,
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: isSource
                  ? colors.accent
                  : isWet
                      ? colors.primary.withValues(alpha: 0.55)
                      : colors.track,
              width: isSource ? 2.2 : 1.3,
            ),
          ),
          child: Stack(
            children: [
              Positioned.fill(
                child: CustomPaint(
                  painter: _CanalTilePainter(
                    type: cell.type,
                    rot: rot,
                    isWet: isWet,
                    wallColor: colors.paperShadow.withValues(alpha: 0.72),
                    dryColor: colors.track,
                    waterColor: const Color(0xFF0EA5E9),
                    rockColor: colors.inkSoft.withValues(alpha: 0.65),
                  ),
                ),
              ),
              if (target != null)
                Center(
                  child: SvgPicture.asset(
                    'assets/svg/stories/${isWet ? target!.bloomedProp : target!.thirstyProp}.svg',
                    width: 40,
                    height: 40,
                  ),
                ),
              if (isSource)
                Positioned(
                  top: 3,
                  left: 3,
                  child: SvgPicture.asset(
                    'assets/svg/stories/water_tap.svg',
                    width: 18,
                    height: 18,
                  ),
                ),
              if (canRotate)
                Positioned(
                  bottom: 2,
                  right: 3,
                  child: Icon(
                    Icons.rotate_right_rounded,
                    size: 13,
                    color: colors.inkSoft.withValues(alpha: 0.55),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CanalTilePainter extends CustomPainter {
  const _CanalTilePainter({
    required this.type,
    required this.rot,
    required this.isWet,
    required this.wallColor,
    required this.dryColor,
    required this.waterColor,
    required this.rockColor,
  });

  final WaterCellType type;
  final int rot;
  final bool isWet;
  final Color wallColor;
  final Color dryColor;
  final Color waterColor;
  final Color rockColor;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final c = Offset(w / 2, h / 2);

    if (type == WaterCellType.empty) return;
    if (type == WaterCellType.rock) {
      final p = Path()
        ..moveTo(w * 0.24, h * 0.72)
        ..lineTo(w * 0.36, h * 0.34)
        ..lineTo(w * 0.66, h * 0.28)
        ..lineTo(w * 0.78, h * 0.68)
        ..close();
      canvas.drawPath(p, Paint()..color = rockColor);
      return;
    }

    final outerPaint = Paint()
      ..color = wallColor
      ..strokeWidth = w * 0.32
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;

    final innerPaint = Paint()
      ..color = isWet ? waterColor : dryColor
      ..strokeWidth = w * 0.18
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;

    canvas.save();
    canvas.translate(c.dx, c.dy);
    canvas.rotate(rot * math.pi / 2);
    canvas.translate(-c.dx, -c.dy);

    final path = Path();
    switch (type) {
      case WaterCellType.straight:
        path
          ..moveTo(c.dx, 0)
          ..lineTo(c.dx, h);
      case WaterCellType.corner:
        path
          ..moveTo(c.dx, 0)
          ..lineTo(c.dx, c.dy)
          ..lineTo(w, c.dy);
      case WaterCellType.tee:
        path
          ..moveTo(0, c.dy)
          ..lineTo(w, c.dy)
          ..moveTo(c.dx, 0)
          ..lineTo(c.dx, c.dy);
      case WaterCellType.cross:
        path
          ..moveTo(c.dx, 0)
          ..lineTo(c.dx, h)
          ..moveTo(0, c.dy)
          ..lineTo(w, c.dy);
      case WaterCellType.basin:
        path
          ..moveTo(c.dx, 0)
          ..lineTo(c.dx, c.dy * 0.65);
      case WaterCellType.empty:
      case WaterCellType.rock:
        break;
    }

    canvas.drawPath(path, outerPaint);
    canvas.drawPath(path, innerPaint);

    if (type == WaterCellType.basin) {
      canvas.drawCircle(
        c,
        w * 0.28,
        Paint()..color = isWet ? waterColor.withValues(alpha: 0.25) : wallColor.withValues(alpha: 0.18),
      );
    }

    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _CanalTilePainter oldDelegate) =>
      oldDelegate.rot != rot ||
      oldDelegate.isWet != isWet ||
      oldDelegate.type != type;
}
