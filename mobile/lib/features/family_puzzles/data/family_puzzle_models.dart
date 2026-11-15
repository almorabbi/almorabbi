/// Models, asset loader, and pure BFS flow solver for «فوازير نور العائلية».
library;

import 'dart:collection';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;

enum PuzzleKind {
  spotDiff('spot_diff'),
  trickReveal('trick_reveal'),
  pieceAssembly('piece_assembly'),
  waterPath('water_path');

  final String wire;
  const PuzzleKind(this.wire);

  static PuzzleKind fromWire(String raw) => values.firstWhere(
        (v) => v.wire == raw,
        orElse: () => PuzzleKind.spotDiff,
      );
}

enum PuzzleSkill {
  observation('observation'),
  lateral('lateral'),
  spatial('spatial'),
  logic('logic');

  final String wire;
  const PuzzleSkill(this.wire);

  static PuzzleSkill fromWire(String raw) => values.firstWhere(
        (v) => v.wire == raw,
        orElse: () => PuzzleSkill.observation,
      );
}

class SceneItemSpec {
  final String id;
  final String prop;
  final double x;
  final double y;
  final double scale;

  const SceneItemSpec({
    required this.id,
    required this.prop,
    required this.x,
    required this.y,
    required this.scale,
  });

  factory SceneItemSpec.fromJson(Map<String, dynamic> j) => SceneItemSpec(
        id: j['id'] as String,
        prop: j['prop'] as String,
        x: (j['x'] as num).toDouble(),
        y: (j['y'] as num).toDouble(),
        scale: (j['scale'] as num).toDouble(),
      );
}

enum SpotDiffMode {
  missing('missing'),
  swap('swap'),
  shift('shift'),
  flip('flip'),
  scale('scale');

  final String wire;
  const SpotDiffMode(this.wire);

  static SpotDiffMode fromWire(String raw) => values.firstWhere(
        (v) => v.wire == raw,
        orElse: () => SpotDiffMode.missing,
      );
}

class SpotDiffChange {
  final String id;
  final String itemId;
  final SpotDiffMode mode;
  final String? altProp;
  final double dx;
  final double dy;
  final double? altScale;
  final double hitX;
  final double hitY;

  const SpotDiffChange({
    required this.id,
    required this.itemId,
    required this.mode,
    this.altProp,
    this.dx = 0,
    this.dy = 0,
    this.altScale,
    required this.hitX,
    required this.hitY,
  });

  factory SpotDiffChange.fromJson(Map<String, dynamic> j) => SpotDiffChange(
        id: j['id'] as String,
        itemId: j['item_id'] as String,
        mode: SpotDiffMode.fromWire(j['mode'] as String),
        altProp: j['alt_prop'] as String?,
        dx: (j['dx'] as num?)?.toDouble() ?? 0,
        dy: (j['dy'] as num?)?.toDouble() ?? 0,
        altScale: (j['alt_scale'] as num?)?.toDouble(),
        hitX: (j['hit_x'] as num).toDouble(),
        hitY: (j['hit_y'] as num).toDouble(),
      );
}

class SpotDiffData {
  final String backdrop;
  final List<SceneItemSpec> baseItems;
  final List<SpotDiffChange> differences;

  const SpotDiffData({
    required this.backdrop,
    required this.baseItems,
    required this.differences,
  });

  factory SpotDiffData.fromJson(Map<String, dynamic> j) => SpotDiffData(
        backdrop: j['backdrop'] as String,
        baseItems: (j['base_items'] as List)
            .map((e) => SceneItemSpec.fromJson(e as Map<String, dynamic>))
            .toList(),
        differences: (j['differences'] as List)
            .map((e) => SpotDiffChange.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
}

class TrickCoverSpec {
  final String id;
  final String prop;
  final String? altProp;
  final double x;
  final double y;
  final double scale;
  final bool movable;
  final String? solveRole;
  final double nudgeX;
  final double nudgeY;

  const TrickCoverSpec({
    required this.id,
    required this.prop,
    this.altProp,
    required this.x,
    required this.y,
    required this.scale,
    this.movable = true,
    this.solveRole,
    required this.nudgeX,
    required this.nudgeY,
  });

  factory TrickCoverSpec.fromJson(Map<String, dynamic> j) {
    final x = (j['x'] as num).toDouble();
    final y = (j['y'] as num).toDouble();
    return TrickCoverSpec(
      id: j['id'] as String,
      prop: j['prop'] as String,
      altProp: j['alt_prop'] as String?,
      x: x,
      y: y,
      scale: (j['scale'] as num).toDouble(),
      movable: (j['movable'] as bool?) ?? true,
      solveRole: j['solve_role'] as String?,
      nudgeX: (j['nudge_x'] as num?)?.toDouble() ?? x,
      nudgeY: (j['nudge_y'] as num?)?.toDouble() ?? y,
    );
  }
}

class TrickTargetZone {
  final double x;
  final double y;
  final double radius;
  final String beforeProp;
  final String afterProp;
  final String? afterBonusProp;

  const TrickTargetZone({
    required this.x,
    required this.y,
    required this.radius,
    required this.beforeProp,
    required this.afterProp,
    this.afterBonusProp,
  });

  factory TrickTargetZone.fromJson(Map<String, dynamic> j) => TrickTargetZone(
        x: (j['x'] as num).toDouble(),
        y: (j['y'] as num).toDouble(),
        radius: (j['radius'] as num).toDouble(),
        beforeProp: j['before_prop'] as String,
        afterProp: j['after_prop'] as String,
        afterBonusProp: j['after_bonus_prop'] as String?,
      );
}

class TrickRevealData {
  final String subMode; // 'count_hidden' | 'drag_solve'
  final String backdrop;
  final int targetCount;
  final String requireMode; // 'any' | 'all'
  final TrickTargetZone? targetZone;
  final List<SceneItemSpec> underItems;
  final List<TrickCoverSpec> covers;

  const TrickRevealData({
    required this.subMode,
    required this.backdrop,
    this.targetCount = 0,
    this.requireMode = 'any',
    this.targetZone,
    required this.underItems,
    required this.covers,
  });

  factory TrickRevealData.fromJson(Map<String, dynamic> j) => TrickRevealData(
        subMode: j['sub_mode'] as String,
        backdrop: j['backdrop'] as String,
        targetCount: (j['target_count'] as int?) ?? 0,
        requireMode: (j['require_mode'] as String?) ?? 'any',
        targetZone: j['target_zone'] == null
            ? null
            : TrickTargetZone.fromJson(
                j['target_zone'] as Map<String, dynamic>,
              ),
        underItems: (j['under_items'] as List? ?? const [])
            .map((e) => SceneItemSpec.fromJson(e as Map<String, dynamic>))
            .toList(),
        covers: (j['covers'] as List? ?? const [])
            .map((e) => TrickCoverSpec.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
}

Color parsePaperHexColor(String hex) {
  final cleaned = hex.replaceFirst('#', '').trim();
  final val = int.tryParse(cleaned, radix: 16) ?? 0x0F6B5C;
  return Color(cleaned.length <= 6 ? (0xFF000000 | val) : val);
}

class AssemblyPieceSpec {
  final String id;
  final Color color;
  final List<Offset> points;
  final Offset targetCenter;
  final Offset startCenter;

  const AssemblyPieceSpec({
    required this.id,
    required this.color,
    required this.points,
    required this.targetCenter,
    required this.startCenter,
  });

  factory AssemblyPieceSpec.fromJson(Map<String, dynamic> j) {
    final pts = (j['points'] as List)
        .map(
          (p) => Offset(
            ((p as List)[0] as num).toDouble(),
            (p[1] as num).toDouble(),
          ),
        )
        .toList();
    final tc = j['target_center'] as List;
    final sc = j['start_center'] as List;
    return AssemblyPieceSpec(
      id: j['id'] as String,
      color: parsePaperHexColor(j['color_hex'] as String),
      points: pts,
      targetCenter: Offset((tc[0] as num).toDouble(), (tc[1] as num).toDouble()),
      startCenter: Offset((sc[0] as num).toDouble(), (sc[1] as num).toDouble()),
    );
  }
}

class PieceAssemblyData {
  final List<AssemblyPieceSpec> pieces;

  const PieceAssemblyData({required this.pieces});

  factory PieceAssemblyData.fromJson(Map<String, dynamic> j) => PieceAssemblyData(
        pieces: (j['pieces'] as List)
            .map((e) => AssemblyPieceSpec.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
}

enum WaterDir {
  n('N', -1, 0),
  e('E', 0, 1),
  s('S', 1, 0),
  w('W', 0, -1);

  final String code;
  final int dr;
  final int dc;
  const WaterDir(this.code, this.dr, this.dc);

  WaterDir get opposite => WaterDir.values[(index + 2) % 4];

  WaterDir rotateClockwise(int steps) =>
      WaterDir.values[(index + steps) % WaterDir.values.length];

  static WaterDir fromCode(String raw) => values.firstWhere(
        (d) => d.code == raw.toUpperCase(),
        orElse: () => WaterDir.w,
      );
}

enum WaterCellType {
  empty('empty'),
  rock('rock'),
  straight('straight'),
  corner('corner'),
  tee('tee'),
  cross('cross'),
  basin('basin');

  final String wire;
  const WaterCellType(this.wire);

  static WaterCellType fromWire(String raw) => values.firstWhere(
        (t) => t.wire == raw,
        orElse: () => WaterCellType.empty,
      );
}

class WaterCellSpec {
  final WaterCellType type;
  final int initialRot;
  final bool fixed;

  const WaterCellSpec({
    required this.type,
    required this.initialRot,
    this.fixed = false,
  });

  factory WaterCellSpec.fromJson(Map<String, dynamic> j) => WaterCellSpec(
        type: WaterCellType.fromWire(j['type'] as String),
        initialRot: (j['initial_rot'] as int?) ?? 0,
        fixed: (j['fixed'] as bool?) ?? false,
      );
}

class WaterTargetSpec {
  final int row;
  final int col;
  final String thirstyProp;
  final String bloomedProp;

  const WaterTargetSpec({
    required this.row,
    required this.col,
    required this.thirstyProp,
    required this.bloomedProp,
  });

  factory WaterTargetSpec.fromJson(Map<String, dynamic> j) => WaterTargetSpec(
        row: j['row'] as int,
        col: j['col'] as int,
        thirstyProp: j['thirsty_prop'] as String,
        bloomedProp: j['bloomed_prop'] as String,
      );
}

class WaterPathData {
  final int rows;
  final int cols;
  final int sourceRow;
  final int sourceCol;
  final WaterDir entryDir;
  final List<WaterTargetSpec> targets;
  final List<List<WaterCellSpec>> cells;

  const WaterPathData({
    required this.rows,
    required this.cols,
    required this.sourceRow,
    required this.sourceCol,
    required this.entryDir,
    required this.targets,
    required this.cells,
  });

  factory WaterPathData.fromJson(Map<String, dynamic> j) {
    final src = j['source'] as Map<String, dynamic>;
    return WaterPathData(
      rows: j['rows'] as int,
      cols: j['cols'] as int,
      sourceRow: src['row'] as int,
      sourceCol: src['col'] as int,
      entryDir: WaterDir.fromCode(src['entry_dir'] as String),
      targets: (j['targets'] as List)
          .map((e) => WaterTargetSpec.fromJson(e as Map<String, dynamic>))
          .toList(),
      cells: (j['cells'] as List)
          .map(
            (row) => (row as List)
                .map((c) => WaterCellSpec.fromJson(c as Map<String, dynamic>))
                .toList(),
          )
          .toList(),
    );
  }
}

class WaterFlowResult {
  final Set<Point<int>> wetCells;
  final Set<Point<int>> wateredTargets;
  final bool allSolved;

  const WaterFlowResult({
    required this.wetCells,
    required this.wateredTargets,
    required this.allSolved,
  });
}

/// Pure deterministic BFS flow solver for rotating canal tiles.
abstract final class WaterPathSolver {
  static Set<WaterDir> basePorts(WaterCellType type) => switch (type) {
        WaterCellType.empty => const {},
        WaterCellType.rock => const {},
        WaterCellType.straight => const {WaterDir.n, WaterDir.s},
        WaterCellType.corner => const {WaterDir.n, WaterDir.e},
        WaterCellType.tee => const {WaterDir.n, WaterDir.e, WaterDir.w},
        WaterCellType.cross => const {
            WaterDir.n,
            WaterDir.e,
            WaterDir.s,
            WaterDir.w,
          },
        WaterCellType.basin => const {WaterDir.n},
      };

  static Set<WaterDir> portsFor(WaterCellType type, int rot) {
    final steps = ((rot % 4) + 4) % 4;
    return {
      for (final d in basePorts(type)) d.rotateClockwise(steps),
    };
  }

  static WaterFlowResult computeFlow(
    WaterPathData data,
    List<List<int>> rotations,
  ) {
    final wet = <Point<int>>{};
    final queue = Queue<Point<int>>();
    final sr = data.sourceRow;
    final sc = data.sourceCol;
    if (sr >= 0 &&
        sr < data.rows &&
        sc >= 0 &&
        sc < data.cols &&
        portsFor(data.cells[sr][sc].type, rotations[sr][sc])
            .contains(data.entryDir)) {
      final start = Point<int>(sc, sr); // Point(x: col, y: row)
      wet.add(start);
      queue.add(start);
    }

    while (queue.isNotEmpty) {
      final cur = queue.removeFirst();
      final r = cur.y;
      final c = cur.x;
      final outDirs = portsFor(data.cells[r][c].type, rotations[r][c]);
      for (final d in outDirs) {
        final nr = r + d.dr;
        final nc = c + d.dc;
        if (nr < 0 || nr >= data.rows || nc < 0 || nc >= data.cols) continue;
        final next = Point<int>(nc, nr);
        if (wet.contains(next)) continue;
        final inDirs = portsFor(data.cells[nr][nc].type, rotations[nr][nc]);
        if (inDirs.contains(d.opposite)) {
          wet.add(next);
          queue.add(next);
        }
      }
    }

    final targetPts = <Point<int>>{
      for (final t in data.targets) Point<int>(t.col, t.row),
    };
    final watered = targetPts.intersection(wet);
    return WaterFlowResult(
      wetCells: wet,
      wateredTargets: watered,
      allSolved: targetPts.isNotEmpty && watered.length == targetPts.length,
    );
  }
}

class FamilyPuzzle {
  final String id;
  final PuzzleKind kind;
  final PuzzleSkill skill;
  final String title;
  final String subtitle;
  final String parentWhisper;
  final String praise;
  final SpotDiffData? spotDiff;
  final TrickRevealData? trickReveal;
  final PieceAssemblyData? pieceAssembly;
  final WaterPathData? waterPath;

  const FamilyPuzzle({
    required this.id,
    required this.kind,
    required this.skill,
    required this.title,
    required this.subtitle,
    required this.parentWhisper,
    required this.praise,
    this.spotDiff,
    this.trickReveal,
    this.pieceAssembly,
    this.waterPath,
  });

  factory FamilyPuzzle.fromJson(Map<String, dynamic> j) => FamilyPuzzle(
        id: j['id'] as String,
        kind: PuzzleKind.fromWire(j['kind'] as String),
        skill: PuzzleSkill.fromWire(j['skill'] as String),
        title: j['title'] as String,
        subtitle: j['subtitle'] as String,
        parentWhisper: j['parent_whisper'] as String,
        praise: j['praise'] as String,
        spotDiff: j['spot_diff'] == null
            ? null
            : SpotDiffData.fromJson(j['spot_diff'] as Map<String, dynamic>),
        trickReveal: j['trick_reveal'] == null
            ? null
            : TrickRevealData.fromJson(
                j['trick_reveal'] as Map<String, dynamic>,
              ),
        pieceAssembly: j['piece_assembly'] == null
            ? null
            : PieceAssemblyData.fromJson(
                j['piece_assembly'] as Map<String, dynamic>,
              ),
        waterPath: j['water_path'] == null
            ? null
            : WaterPathData.fromJson(j['water_path'] as Map<String, dynamic>),
      );
}

class OffscreenBrainActivity {
  final String id;
  final String title;
  final String body;

  const OffscreenBrainActivity({
    required this.id,
    required this.title,
    required this.body,
  });

  factory OffscreenBrainActivity.fromJson(Map<String, dynamic> j) =>
      OffscreenBrainActivity(
        id: j['id'] as String,
        title: j['title'] as String,
        body: j['body'] as String,
      );
}

class FamilyPuzzlePack {
  final int version;
  final String locale;
  final List<FamilyPuzzle> puzzles;
  final List<OffscreenBrainActivity> offscreenActivities;

  const FamilyPuzzlePack({
    required this.version,
    required this.locale,
    required this.puzzles,
    required this.offscreenActivities,
  });

  factory FamilyPuzzlePack.fromJson(Map<String, dynamic> j) => FamilyPuzzlePack(
        version: (j['version'] as int?) ?? 1,
        locale: (j['locale'] as String?) ?? 'ar',
        puzzles: (j['puzzles'] as List)
            .map((e) => FamilyPuzzle.fromJson(e as Map<String, dynamic>))
            .toList(),
        offscreenActivities: (j['offscreen_activities'] as List)
            .map(
              (e) => OffscreenBrainActivity.fromJson(e as Map<String, dynamic>),
            )
            .toList(),
      );
}

final Map<String, FamilyPuzzlePack> _packCache = {};

Future<FamilyPuzzlePack> loadFamilyPuzzlePack(String languageCode) async {
  final base = languageCode.trim().toLowerCase().split(RegExp(r'[_-]')).first;
  final lang = base == 'en' ? 'en' : 'ar';
  final cached = _packCache[lang];
  if (cached != null) return cached;
  final raw = await rootBundle.loadString(
    'assets/content/games/family_puzzles.$lang.json',
  );
  final pack = FamilyPuzzlePack.fromJson(jsonDecode(raw) as Map<String, dynamic>);
  _packCache[lang] = pack;
  return pack;
}
