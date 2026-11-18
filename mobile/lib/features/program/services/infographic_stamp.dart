/// The mark burnt into the copy of an infographic a parent downloads.
///
/// It is the only piece of the brand that leaves the app with the user's own
/// share, so it is drawn from the same file the splash paints
/// (`assets/svg/art/logo_mark.svg`) rather than from a raster copy of it: a
/// copy is a second logo to keep in step, and the first one — a PNG of the
/// previous logo — went on being stamped after the app had a new mark. Drawn
/// as a vector it is also sharp at any infographic size.
///
/// test/infographic_stamp_test.dart reads the stamped pixels back.
library;

import 'dart:ui' as ui;

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_svg/flutter_svg.dart';

/// The app's mark — the one the splash shows (main.dart).
const infographicStampAsset = 'assets/svg/art/logo_mark.svg';

/// The stamp's width, and its distance from the right and bottom edges, as
/// fractions of the infographic's width.
const _widthFraction = 0.06;
const _marginFraction = 0.02;

/// Returns [imageBytes] (any format the engine decodes) as a PNG of the same
/// size, with the app's mark in its bottom-right corner.
///
/// [bundle] is where the mark is read from; the root bundle when null.
Future<Uint8List> stampInfographic(
  Uint8List imageBytes, {
  AssetBundle? bundle,
}) async {
  ui.Image? base;
  PictureInfo? mark;
  ui.Picture? picture;
  ui.Image? stamped;
  try {
    base = await decodeImageFromList(imageBytes);
    mark = await vg.loadPicture(
      SvgAssetLoader(infographicStampAsset, assetBundle: bundle),
      null,
    );

    final w = base.width.toDouble();
    final h = base.height.toDouble();
    final markW = w * _widthFraction;
    final markH = markW * mark.size.height / mark.size.width;
    final margin = w * _marginFraction;

    final recorder = ui.PictureRecorder();
    Canvas(recorder)
      ..drawImage(base, Offset.zero, Paint())
      ..translate(w - markW - margin, h - markH - margin)
      ..scale(markW / mark.size.width, markH / mark.size.height)
      ..drawPicture(mark.picture);
    picture = recorder.endRecording();

    stamped = await picture.toImage(base.width, base.height);
    final png = await stamped.toByteData(format: ui.ImageByteFormat.png);
    return png!.buffer.asUint8List();
  } finally {
    stamped?.dispose();
    picture?.dispose();
    mark?.picture.dispose();
    base?.dispose();
  }
}
