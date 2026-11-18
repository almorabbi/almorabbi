/// The stamp on a downloaded infographic is the app's current mark.
///
/// The stamp is the one piece of the brand that leaves the app: it is burnt
/// into the copy a parent downloads and shares, so a stale one keeps
/// travelling long after every screen has moved on. Until 2026-11 it was
/// `assets/images/logo.png` — the previous logo, a child's profile inside a
/// crescent — while the launcher icon, the in-app splash and the store had
/// all moved to the paper-cut mark (`assets/svg/art/logo_mark.svg`). Nothing
/// failed: the old file decoded, the share sheet opened, and the wrong mark
/// went out.
///
/// So this checks the picture, not the call:
///
///   1. The stamped PNG is decoded and read back pixel by pixel. The tile,
///      the crescent and the sprout are where the mark's own geometry puts
///      them, in the brand's colours; the tile's rounded corners and
///      everything outside the stamp are still the infographic. An SVG that
///      flutter_svg cannot draw does not throw — the picture stays empty —
///      and only the pixels would say so.
///   2. The one asset read for it is the mark, never the old PNG.
///   3. The old PNG is not in the bundle at all. `assets/images/` is declared
///      as a folder, so the file merely existing would ship it.
library;

import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:almorabbi/features/program/services/infographic_stamp.dart';

const _oldLogo = 'assets/images/logo.png';

/// A colour the mark does not use, so "still the infographic" is readable.
const _ground = Color(0xFF336699);

// «نور والقناديل» — the fills of assets/svg/art/logo_mark.svg.
const _tile = Color(0xFF0F6B5C);
const _cream = Color(0xFFFBF1DE);
const _leaf = Color(0xFF7ED3A6);

/// rootBundle, remembering what was asked of it.
class _RecordingBundle extends CachingAssetBundle {
  final keys = <String>[];

  @override
  Future<ByteData> load(String key) {
    keys.add(key);
    return rootBundle.load(key);
  }
}

Future<Uint8List> _flatPng(int width, int height, Color color) async {
  final recorder = ui.PictureRecorder();
  Canvas(recorder).drawRect(
    Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
    Paint()..color = color,
  );
  final picture = recorder.endRecording();
  final image = await picture.toImage(width, height);
  final png = await image.toByteData(format: ui.ImageByteFormat.png);
  picture.dispose();
  image.dispose();
  return png!.buffer.asUint8List();
}

class _Pixels {
  _Pixels(this.width, this.height, this._rgba);

  final int width;
  final int height;
  final ByteData _rgba;

  static Future<_Pixels> decode(Uint8List png) async {
    final image = await decodeImageFromList(png);
    final rgba = await image.toByteData(
      format: ui.ImageByteFormat.rawStraightRgba,
    );
    final pixels = _Pixels(image.width, image.height, rgba!);
    image.dispose();
    return pixels;
  }

  Color at(num x, num y) {
    final i = (y.round() * width + x.round()) * 4;
    return Color.fromARGB(
      _rgba.getUint8(i + 3),
      _rgba.getUint8(i),
      _rgba.getUint8(i + 1),
      _rgba.getUint8(i + 2),
    );
  }
}

int _channel(double v) => (v * 255).round();

/// Flat colour, give or take the rounding of one blend.
Matcher _is(Color expected) => predicate<Color>(
      (c) =>
          (_channel(c.r) - _channel(expected.r)).abs() <= 2 &&
          (_channel(c.g) - _channel(expected.g)).abs() <= 2 &&
          (_channel(c.b) - _channel(expected.b)).abs() <= 2 &&
          _channel(c.a) == 255,
      'is ${expected.toARGB32().toRadixString(16)}',
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // 2000 wide: the stamp is 6% of the width — 120 px, the mark's 240-unit
  // viewBox at half scale — 2% in from the right and bottom edges.
  const width = 2000, height = 1200;
  const side = 120.0, left = 1840.0, top = 1040.0;

  /// A point of the mark's viewBox, as a pixel of the stamped image.
  Offset onMark(double vx, double vy) =>
      Offset(left + vx * side / 240, top + vy * side / 240);

  group('the stamp on a downloaded infographic', () {
    late _RecordingBundle bundle;
    late _Pixels out;

    setUpAll(() async {
      bundle = _RecordingBundle();
      final base = await _flatPng(width, height, _ground);
      out = await _Pixels.decode(await stampInfographic(base, bundle: bundle));
    });

    Color at(Offset p) => out.at(p.dx, p.dy);

    test('keeps the infographic at its own size', () {
      expect((out.width, out.height), (width, height));
    });

    test('is the current mark, drawn in the bottom-right corner', () {
      // Top of the tile, clear of the crescent and the sprout.
      expect(at(onMark(120, 20)), _is(_tile));
      // The belly of the crescent.
      expect(at(onMark(77, 126)), _is(_cream));
      // The left leaf of the sprout.
      expect(at(onMark(135.5, 93)), _is(_leaf));
    });

    test('is a rounded tile: its corners are still the infographic', () {
      // The old logo was a full-bleed square; the mark's tile is rounded
      // (rx 52 of 240), so each corner of the stamp's box shows through.
      for (final corner in [
        onMark(4, 4),
        onMark(236, 4),
        onMark(4, 236),
        onMark(236, 236),
      ]) {
        expect(at(corner), _is(_ground), reason: '$corner');
      }
    });

    test('touches nothing outside its box', () {
      for (final p in [
        const Offset(0, 0),
        const Offset(width / 2, height / 2),
        Offset(left - 3, top + side / 2),
        Offset(left + side / 2, top - 3),
        Offset(left + side + 3, top + side / 2),
        Offset(left + side / 2, top + side + 3),
        const Offset(width - 1, height - 1),
      ]) {
        expect(at(p), _is(_ground), reason: '$p');
      }
    });

    test('reads the mark and nothing else — never the old PNG', () {
      expect(infographicStampAsset, 'assets/svg/art/logo_mark.svg');
      expect(bundle.keys, [infographicStampAsset]);
    });
  });

  group('the old logo', () {
    test('is not on disk under assets/', () {
      expect(File(_oldLogo).existsSync(), isFalse);
    });

    test('is not in the bundle', () async {
      final manifest = await AssetManifest.loadFromAssetBundle(rootBundle);
      expect(manifest.listAssets(), isNot(contains(_oldLogo)));
      expect(manifest.listAssets(), contains(infographicStampAsset));
    });
  });
}
