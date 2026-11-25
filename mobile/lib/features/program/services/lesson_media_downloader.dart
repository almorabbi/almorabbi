/// Streaming downloader & native share helper for lesson audio (MP3) and
/// video (MP4) files.
///
/// Files served from `/docs/` already carry Al-Murabbi's voice/visual brand
/// signature (intro, mid-roll & outro on podcasts; Noor corner badge & QR end
/// card on videos). This service streams the file to a deterministic cache path
/// (so repeated taps are instant), reports download progress `[0..1]`, attaches
/// the parent's attributed install link via [ShareService], and opens the OS
/// share/save sheet with zero storage-permission friction.
library;

import 'dart:async';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../../core/analytics.dart';
import '../../../l10n/app_localizations.dart';
import '../../referral/referral_service.dart';
import '../../share/share_service.dart';

typedef MediaShareFn = Future<void> Function(
  String filePath,
  String mimeType,
  String shareText,
);

class LessonMediaDownloader {
  LessonMediaDownloader({
    this.client,
    Future<Directory> Function()? cacheDir,
    MediaShareFn? shareFile,
  })  : _cacheDir = cacheDir ?? getTemporaryDirectory,
        _shareFile = shareFile ?? _defaultShare;

  final http.Client? client;
  final Future<Directory> Function() _cacheDir;
  final MediaShareFn _shareFile;

  static Future<void> _defaultShare(
    String filePath,
    String mimeType,
    String shareText,
  ) async {
    await SharePlus.instance.share(
      ShareParams(
        files: [XFile(filePath, mimeType: mimeType)],
        text: shareText,
      ),
    );
  }

  /// Derive a safe, deterministic local filename for [url] and [extension].
  static String safeFileName(String url, String extension) {
    final uri = Uri.tryParse(url);
    final raw = (uri != null && uri.pathSegments.isNotEmpty)
        ? uri.pathSegments.last
        : 'almorabbi_media';
    final base = raw.replaceAll(RegExp(r'\.[^.]+$'), '');
    final cleaned = base
        .replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_')
        .replaceAll(RegExp(r'_+'), '_')
        .replaceAll(RegExp(r'^_|_$'), '');
    final stem = cleaned.isEmpty ? 'almorabbi_media' : cleaned;
    final prefix = stem.startsWith('almorabbi_') ? stem : 'almorabbi_$stem';
    return '$prefix.$extension';
  }

  /// Download [url] into the media cache (reusing a non-empty cached copy) and
  /// hand it to the system Save/Share sheet with a reverent attributed caption.
  Future<String> downloadAndShare({
    required String url,
    required String extension,
    required String mimeType,
    required String kind,
    required String baseMessage,
    required AppLocalizations l10n,
    void Function(double? progress)? onProgress,
  }) async {
    final root = await _cacheDir();
    final mediaDir = Directory('${root.path}/almorabbi_media');
    if (!await mediaDir.exists()) {
      await mediaDir.create(recursive: true);
    }
    final target = File('${mediaDir.path}/${safeFileName(url, extension)}');

    if (!await target.exists() || await target.length() == 0) {
      final ownsClient = client == null;
      final httpClient = client ?? http.Client();
      final tmp = File('${target.path}.part');
      IOSink? sink;
      try {
        final req = http.Request('GET', Uri.parse(url));
        final resp = await httpClient.send(req);
        if (resp.statusCode != 200) {
          throw HttpException('HTTP ${resp.statusCode}', uri: Uri.parse(url));
        }
        final total = resp.contentLength ?? 0;
        var received = 0;
        onProgress?.call(total > 0 ? 0.0 : null);
        sink = tmp.openWrite();
        await for (final chunk in resp.stream) {
          sink.add(chunk);
          received += chunk.length;
          if (total > 0) {
            onProgress?.call((received / total).clamp(0.0, 1.0));
          }
        }
        await sink.flush();
        await sink.close();
        sink = null;
        if (received == 0) {
          throw const HttpException('Empty response body');
        }
        if (await target.exists()) {
          await target.delete();
        }
        await tmp.rename(target.path);
      } catch (_) {
        await sink?.close();
        if (await tmp.exists()) {
          try {
            await tmp.delete();
          } catch (_) {}
        }
        rethrow;
      } finally {
        if (ownsClient) httpClient.close();
      }
    }

    onProgress?.call(1.0);
    final caption = ShareService.shareText(
      baseMessage,
      l10n,
      referralCode: ReferralService.cachedCode,
    );
    await _shareFile(target.path, mimeType, caption);
    unawaited(Analytics.shareMoment(kind));
    return target.path;
  }
}
