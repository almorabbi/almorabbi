/// Interactive geometric Paper-Cut assembly board («ركّب القطع»).
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../core/haptics.dart';
import '../../../theme/app_colors.dart';
import '../../../theme/design_tokens.dart';
import '../data/family_puzzle_models.dart';

class PieceAssemblyStage extends StatefulWidget {
  const PieceAssemblyStage({
    super.key,
    required this.data,
    required this.solved,
    required this.onSolved,
  });

  final PieceAssemblyData data;
  final bool solved;
  final VoidCallback onSolved;

  @override
  State<PieceAssemblyStage> createState() => _PieceAssemblyStageState();
}

class _PieceAssemblyStageState extends State<PieceAssemblyStage> {
  late Map<String, Offset> _centers;
  final Set<String> _snappedIds = {};
  String? _selectedId;

  @override
  void initState() {
    super.initState();
    _reset();
  }

  @override
  void didUpdateWidget(covariant PieceAssemblyStage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.data != widget.data ||
        (oldWidget.solved && !widget.solved)) {
      _reset();
    }
  }

  void _reset() {
    _centers = {
      for (final p in widget.data.pieces) p.id: p.startCenter,
    };
    _snappedIds.clear();
    _selectedId = null;
  }

  void _snapPiece(AssemblyPieceSpec piece) {
    setState(() {
      _centers[piece.id] = piece.targetCenter;
      _snappedIds.add(piece.id);
      if (_selectedId == piece.id) _selectedId = null;
    });
    if (_snappedIds.length == widget.data.pieces.length) {
      Haptics.success();
      widget.onSolved();
    } else {
      Haptics.selection();
    }
  }

  void _trySnapAtCurrent(AssemblyPieceSpec piece) {
    final cur = _centers[piece.id] ?? piece.startCenter;
    final dist = (cur - piece.targetCenter).distance;
    if (dist <= 0.14) {
      _snapPiece(piece);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: AspectRatio(
        aspectRatio: 1.0,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final side = constraints.maxWidth;
            return Container(
              key: const ValueKey('piece_assembly_board'),
              decoration: BoxDecoration(
                color: colors.surfaceAlt,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: colors.paperShadow.withValues(alpha: 0.45),
                  width: 2,
                ),
              ),
              child: Stack(
                children: [
                  // Target silhouettes + already-snapped pieces drawn cleanly in order.
                  Positioned.fill(
                    child: CustomPaint(
                      painter: _AssemblyBoardPainter(
                        pieces: widget.data.pieces,
                        snappedIds: widget.solved
                            ? {for (final p in widget.data.pieces) p.id}
                            : _snappedIds,
                        outlineColor: colors.inkSoft.withValues(alpha: 0.48),
                        shadowColor: colors.paperShadow,
                      ),
                    ),
                  ),
                  // Accessible tap slots for snapped placement once a piece is selected.
                  if (!widget.solved)
                    for (final p in widget.data.pieces)
                      if (!_snappedIds.contains(p.id))
                        Positioned(
                          left: p.targetCenter.dx * side - Dt.minTouch / 2,
                          top: p.targetCenter.dy * side - Dt.minTouch / 2,
                          width: Dt.minTouch,
                          height: Dt.minTouch,
                          child: GestureDetector(
                            key: ValueKey('assembly_slot_${p.id}'),
                            behavior: HitTestBehavior.opaque,
                            onTap: () {
                              if (_selectedId == p.id) {
                                _snapPiece(p);
                              }
                            },
                            child: const SizedBox.expand(),
                          ),
                        ),
                  // Movable loose Paper-Cut pieces.
                  if (!widget.solved)
                    for (final p in widget.data.pieces)
                      if (!_snappedIds.contains(p.id))
                        _buildLoosePiece(p, side, colors),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildLoosePiece(
    AssemblyPieceSpec piece,
    double side,
    dynamic colors,
  ) {
    final center = _centers[piece.id] ?? piece.startCenter;
    final boxSide = math.max(_pieceDiameter(piece, side), Dt.minTouch);
    final selected = _selectedId == piece.id;

    return Positioned(
      left: center.dx * side - boxSide / 2,
      top: center.dy * side - boxSide / 2,
      width: boxSide,
      height: boxSide,
      child: GestureDetector(
        key: ValueKey('assembly_piece_${piece.id}'),
        behavior: HitTestBehavior.opaque,
        onTap: () {
          Haptics.selection();
          setState(() => _selectedId = selected ? null : piece.id);
        },
        onPanStart: (_) {
          setState(() => _selectedId = piece.id);
        },
        onPanUpdate: (d) {
          final next = Offset(
            (center.dx + d.delta.dx / side).clamp(0.08, 0.92),
            (center.dy + d.delta.dy / side).clamp(0.08, 0.92),
          );
          setState(() => _centers[piece.id] = next);
          if ((next - piece.targetCenter).distance <= 0.11) {
            _snapPiece(piece);
          }
        },
        onPanEnd: (_) => _trySnapAtCurrent(piece),
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Positioned.fill(
              child: CustomPaint(
                painter: _LoosePiecePainter(
                  piece: piece,
                  boardSide: side,
                  shadowColor: colors.paperShadow as Color,
                  highlightColor: selected ? colors.paperGold as Color : null,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  double _pieceDiameter(AssemblyPieceSpec piece, double side) {
    var maxExtent = 0.0;
    for (final pt in piece.points) {
      maxExtent = math.max(maxExtent, math.max(pt.dx.abs(), pt.dy.abs()));
    }
    return (maxExtent * 2 * side) + 16;
  }
}

Path _buildPolygonPath(
  List<Offset> points,
  Offset centerPx,
  double scaleSide,
) {
  final path = Path();
  if (points.isEmpty) return path;
  path.moveTo(
    centerPx.dx + points.first.dx * scaleSide,
    centerPx.dy + points.first.dy * scaleSide,
  );
  for (var i = 1; i < points.length; i++) {
    path.lineTo(
      centerPx.dx + points[i].dx * scaleSide,
      centerPx.dy + points[i].dy * scaleSide,
    );
  }
  path.close();
  return path;
}

class _AssemblyBoardPainter extends CustomPainter {
  const _AssemblyBoardPainter({
    required this.pieces,
    required this.snappedIds,
    required this.outlineColor,
    required this.shadowColor,
  });

  final List<AssemblyPieceSpec> pieces;
  final Set<String> snappedIds;
  final Color outlineColor;
  final Color shadowColor;

  @override
  void paint(Canvas canvas, Size size) {
    final side = size.width;
    final outlinePaint = Paint()
      ..color = outlineColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0
      ..strokeJoin = StrokeJoin.round;

    final silhouetteFill = Paint()
      ..color = outlineColor.withValues(alpha: 0.10)
      ..style = PaintingStyle.fill;

    for (final piece in pieces) {
      final centerPx = Offset(
        piece.targetCenter.dx * side,
        piece.targetCenter.dy * side,
      );
      final targetPath = _buildPolygonPath(piece.points, centerPx, side);
      if (snappedIds.contains(piece.id)) {
        canvas.drawPath(
          targetPath.shift(const Offset(3, 4)),
          Paint()..color = shadowColor.withValues(alpha: 0.32),
        );
        canvas.drawPath(targetPath, Paint()..color = piece.color);
      } else {
        canvas.drawPath(targetPath, silhouetteFill);
        canvas.drawPath(targetPath, outlinePaint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _AssemblyBoardPainter oldDelegate) =>
      oldDelegate.snappedIds.length != snappedIds.length ||
      oldDelegate.outlineColor != outlineColor;
}

class _LoosePiecePainter extends CustomPainter {
  const _LoosePiecePainter({
    required this.piece,
    required this.boardSide,
    required this.shadowColor,
    this.highlightColor,
  });

  final AssemblyPieceSpec piece;
  final double boardSide;
  final Color shadowColor;
  final Color? highlightColor;

  @override
  void paint(Canvas canvas, Size size) {
    final centerPx = Offset(size.width / 2, size.height / 2);
    final path = _buildPolygonPath(piece.points, centerPx, boardSide);
    canvas.drawPath(
      path.shift(const Offset(3, 4)),
      Paint()..color = shadowColor.withValues(alpha: 0.38),
    );
    canvas.drawPath(path, Paint()..color = piece.color);
    if (highlightColor != null) {
      canvas.drawPath(
        path,
        Paint()
          ..color = highlightColor!
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _LoosePiecePainter oldDelegate) =>
      oldDelegate.highlightColor != highlightColor ||
      oldDelegate.boardSide != boardSide;
}
