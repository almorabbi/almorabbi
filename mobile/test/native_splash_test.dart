// The Android launch screen shows the current mark, on the app's own ground.
//
// Until 2026-11 every cold start showed two logos in a row: the native launch
// screen still had the retired shield/teal mark on #01696F — PNGs that
// flutter_native_splash generated in June and nobody regenerated — and then
// Flutter's _SplashScreen drew the current logo_mark.svg on the cream ground.
// The launcher icon had moved on (ic_launcher_paper, brand_build.py); the
// splash had not, and nothing failed.
//
// Now the launch screen is one VectorDrawable, drawable/splash_mark.xml,
// generated from logo_mark.svg by `docs/brand/tools/brand_build.py splash`,
// on @color/splash_background. These tests fail if the old raster splash is
// regenerated, if logo_mark.svg changes without the drawable, or if the
// native ground drifts from the Flutter one.

import 'dart:io';
import 'dart:math' as math;

import 'package:almorabbi/theme/app_palette.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';

const _res = 'android/app/src/main/res';
const _logoMark = 'assets/svg/art/logo_mark.svg';
const _retiredTeal = '#01696F';

String _read(String path) => File(path).readAsStringSync();

String _hex(Color c) =>
    '#${(c.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase()}';

/// `<item name="…">value</item>` inside `<style name="LaunchTheme">`.
Map<String, String> _launchTheme(String stylesXml) {
  final style = RegExp(
    r'<style name="LaunchTheme"[^>]*>([\s\S]*?)</style>',
  ).firstMatch(stylesXml);
  expect(style, isNotNull, reason: 'no LaunchTheme');
  return {
    for (final m in RegExp(
      r'<item name="([^"]+)">([^<]*)</item>',
    ).allMatches(style![1]!))
      m[1]!: m[2]!.trim(),
  };
}

String _splashBackground(String colorsFile) {
  final m = RegExp(
    r'<color name="splash_background">([^<]+)</color>',
  ).firstMatch(_read(colorsFile));
  expect(m, isNotNull, reason: '$colorsFile has no splash_background');
  return m![1]!.trim().toUpperCase();
}

Iterable<File> _resFiles() =>
    Directory(_res).listSync(recursive: true).whereType<File>();

String _name(File f) => f.uri.pathSegments.last;

void main() {
  test('no raster splash is left for flutter_native_splash to have made', () {
    final leftovers = _resFiles()
        .where((f) => f.path.contains('/drawable'))
        .where(
          (f) =>
              {
                'splash.png',
                'android12splash.png',
                'background.png',
              }.contains(_name(f)) ||
              (_name(f).endsWith('.png') && _name(f).contains('splash')),
        )
        .map((f) => f.path)
        .toList();
    expect(
      leftovers,
      isEmpty,
      reason:
          'the launch screen is drawable/splash_mark.xml; these PNGs '
          'are what flutter_native_splash writes (the retired logo)',
    );
  });

  test('flutter_native_splash is not configured to regenerate it', () {
    final pubspec = _read('pubspec.yaml');
    expect(
      RegExp(r'^\s*flutter_native_splash:', multiLine: true).hasMatch(pubspec),
      isFalse,
    );
  });

  test('every launch theme draws splash_mark on splash_background', () {
    for (final dir in ['values-v31', 'values-night-v31']) {
      final t = _launchTheme(_read('$_res/$dir/styles.xml'));
      expect(
        t['android:windowSplashScreenAnimatedIcon'],
        '@drawable/splash_mark',
        reason: dir,
      );
      expect(
        t['android:windowSplashScreenBackground'],
        '@color/splash_background',
        reason: dir,
      );
      // An icon background would put a 160dp disc behind the mark that the
      // Flutter screen does not have.
      expect(
        t.containsKey('android:windowSplashScreenIconBackgroundColor'),
        isFalse,
        reason: dir,
      );
    }
    for (final dir in ['values', 'values-night']) {
      final t = _launchTheme(_read('$_res/$dir/styles.xml'));
      expect(
        t['android:windowBackground'],
        '@drawable/launch_background',
        reason: dir,
      );
    }
    final launchBackgrounds = _resFiles()
        .where((f) => _name(f) == 'launch_background.xml')
        .toList();
    expect(
      launchBackgrounds.map((f) => f.path),
      ['$_res/drawable/launch_background.xml'],
      reason: 'a qualified copy (drawable-v21/ was one) would shadow it',
    );
    final layers = _read(launchBackgrounds.single.path);
    expect(layers, contains('@color/splash_background'));
    expect(layers, contains('@drawable/splash_mark'));
    expect(layers, isNot(contains('<bitmap')));
  });

  test('the native ground is the Flutter ground, in light and dark', () {
    expect(
      _splashBackground('$_res/values/colors.xml'),
      _hex(AppPalette.light.background),
    );
    expect(
      _splashBackground('$_res/values-night/colors.xml'),
      _hex(AppPalette.dark.background),
    );
  });

  group('splash_mark.xml', () {
    // Read inside each test, so a missing file fails the test, not the load.
    late final vd = _read('$_res/drawable/splash_mark.xml');
    late final svg = _read(_logoMark);

    test('is logo_mark.svg as it is now (regenerate with brand_build.py)', () {
      final svgPaths = RegExp(
        r' d="([^"]+)"',
      ).allMatches(svg).map((m) => m[1]!).toList();
      final vdPaths = RegExp(
        r'android:pathData="([^"]+)"',
      ).allMatches(vd).map((m) => m[1]!).toList();
      expect(svgPaths, isNotEmpty);
      // logo_mark.svg is <rect> (the tile) + <path>s; the rect becomes a path.
      expect(
        vdPaths.length,
        svgPaths.length + RegExp(r'<rect\b').allMatches(svg).length,
      );
      for (final d in svgPaths) {
        expect(vdPaths, contains(d));
      }
      Set<String> colours(String s) => RegExp(
        r'#[0-9A-Fa-f]{6}\b',
      ).allMatches(s).map((m) => m[0]!.toUpperCase()).toSet();
      expect(colours(vd), colours(svg));
      expect(colours(vd), isNot(contains(_retiredTeal)));
    });

    test(
      'sits whole inside the circle Android 12+ shows, at the Flutter size',
      () {
        double attr(String name) => double.parse(
          RegExp('android:$name="([0-9.]+)').firstMatch(vd)![1]!,
        );
        final box = attr('viewportWidth');
        expect(attr('viewportHeight'), box);
        // Android 12+: an icon without an icon background is drawn into a
        // 288dp view and clipped to the centred 192dp circle.
        expect(box, 288);
        expect(RegExp(r'android:width="288dp"').hasMatch(vd), isTrue);
        final group = RegExp(
          r'<group android:translateX="([0-9.]+)" android:translateY="([0-9.]+)"'
          r' android:scaleX="([0-9.]+)" android:scaleY="([0-9.]+)"',
        ).firstMatch(vd)!;
        final tx = double.parse(group[1]!), ty = double.parse(group[2]!);
        final s = double.parse(group[3]!);
        expect(double.parse(group[4]!), s);
        final side = 240 * s; // logo_mark.svg's viewBox is 0 0 240 240
        expect(tx + side / 2, box / 2, reason: 'centred');
        expect(ty + side / 2, box / 2, reason: 'centred');
        expect(
          side / 2 * math.sqrt2,
          lessThanOrEqualTo(192 / 2),
          reason: 'even the corners of the 240-unit box are inside the circle',
        );

        final flutter = RegExp(
          r"ArtImage\(\s*'assets/svg/art/logo_mark\.svg',\s*width:\s*(\d+)",
        ).firstMatch(_read('lib/main.dart'));
        expect(
          flutter,
          isNotNull,
          reason:
              '_SplashScreen no longer draws logo_mark.svg — '
              'regenerate the native mark from what it draws now',
        );
        expect(
          side,
          double.parse(flutter![1]!),
          reason: 'native and Flutter splash draw the mark at the same size',
        );
      },
    );
  });

  test('the launcher icon is still the paper-cut one', () {
    // flutter_launcher_icons with `android: true` rewrites android:icon back
    // to @mipmap/ic_launcher without a word (docs/VISUAL_ASSETS.md).
    final manifest = _read('android/app/src/main/AndroidManifest.xml');
    expect(manifest, contains('android:icon="@mipmap/ic_launcher_paper"'));
    expect(
      manifest,
      contains('android:roundIcon="@mipmap/ic_launcher_paper_round"'),
    );
    final launcherIcons = RegExp(
      r'^flutter_launcher_icons:\n((?:[ #].*\n|\n)*)',
      multiLine: true,
    ).firstMatch(_read('pubspec.yaml'));
    expect(launcherIcons, isNotNull);
    expect(
      launcherIcons![1],
      contains(RegExp(r'^  android: false', multiLine: true)),
    );
  });
}
