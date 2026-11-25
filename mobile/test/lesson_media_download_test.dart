import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:almorabbi/core/analytics.dart';
import 'package:almorabbi/features/program/screens/podcast_player_screen.dart';
import 'package:almorabbi/features/program/screens/video_player_screen.dart';
import 'package:almorabbi/features/program/services/lesson_media_downloader.dart';
import 'package:almorabbi/l10n/app_localizations.dart';
import 'package:almorabbi/l10n/app_localizations_ar.dart';
import 'package:almorabbi/l10n/app_localizations_en.dart';

class _FakeDownloader extends LessonMediaDownloader {
  final calls = <Map<String, String>>[];

  @override
  Future<String> downloadAndShare({
    required String url,
    required String extension,
    required String mimeType,
    required String kind,
    required String baseMessage,
    required AppLocalizations l10n,
    void Function(double? progress)? onProgress,
  }) async {
    onProgress?.call(0.5);
    calls.add({
      'url': url,
      'extension': extension,
      'mimeType': mimeType,
      'kind': kind,
      'baseMessage': baseMessage,
    });
    onProgress?.call(1.0);
    return '/tmp/fake.$extension';
  }
}

void main() {
  group('LessonMediaDownloader', () {
    test('safeFileName sanitizes paths and prefixes almorabbi_', () {
      expect(
        LessonMediaDownloader.safeFileName(
          'https://tg-api.alsaba.cloud/docs/lesson_4-6_bond_01_podcast.mp3',
          'mp3',
        ),
        'almorabbi_lesson_4-6_bond_01_podcast.mp3',
      );
      expect(
        LessonMediaDownloader.safeFileName(
          'https://tg-api.alsaba.cloud/docs/path_videos/path_7-9_ar_eg.mp4?v=2',
          'mp4',
        ),
        'almorabbi_path_7-9_ar_eg.mp4',
      );
    });

    test('streams file, reports progress, caches on 2nd call, and appends install link', () async {
      final tmpDir = await Directory.systemTemp.createTemp('tg-dl-test-');
      addTearDown(() => tmpDir.delete(recursive: true));

      var httpCalls = 0;
      final client = MockClient.streaming((request, _) async {
        httpCalls += 1;
        final chunks = [
          List<int>.filled(64, 1),
          List<int>.filled(64, 2),
        ];
        return http.StreamedResponse(
          Stream<List<int>>.fromIterable(chunks),
          200,
          contentLength: 128,
        );
      });

      final shared = <Map<String, String>>[];
      final events = <String>[];
      Analytics.debugSink = (name, params) {
        events.add('$name:${params?['kind']}');
      };
      addTearDown(() => Analytics.debugSink = null);

      final dl = LessonMediaDownloader(
        client: client,
        cacheDir: () async => tmpDir,
        shareFile: (path, mime, text) async {
          shared.add({'path': path, 'mime': mime, 'text': text});
        },
      );

      final progress = <double?>[];
      final l10n = AppLocalizationsAr();
      final out1 = await dl.downloadAndShare(
        url: 'https://tg-api.alsaba.cloud/docs/lesson_test_podcast.mp3',
        extension: 'mp3',
        mimeType: 'audio/mpeg',
        kind: 'podcast',
        baseMessage: l10n.sharePodcastText,
        l10n: l10n,
        onProgress: progress.add,
      );

      expect(httpCalls, 1);
      expect(File(out1).lengthSync(), 128);
      expect(progress.last, 1.0);
      expect(shared, hasLength(1));
      expect(shared.single['mime'], 'audio/mpeg');
      expect(shared.single['text'], contains('https://tg-api.alsaba.cloud/go'));
      expect(events, contains('share_moment:podcast'));

      // Second call reuses the cached file without re-downloading.
      final out2 = await dl.downloadAndShare(
        url: 'https://tg-api.alsaba.cloud/docs/lesson_test_podcast.mp3',
        extension: 'mp3',
        mimeType: 'audio/mpeg',
        kind: 'podcast',
        baseMessage: l10n.sharePodcastText,
        l10n: l10n,
      );
      expect(out2, out1);
      expect(httpCalls, 1);
    });

    test('non-200 response throws and cleans up partial file', () async {
      final tmpDir = await Directory.systemTemp.createTemp('tg-dl-err-');
      addTearDown(() => tmpDir.delete(recursive: true));

      final client = MockClient.streaming((request, _) async {
        return http.StreamedResponse(const Stream.empty(), 404);
      });
      final dl = LessonMediaDownloader(
        client: client,
        cacheDir: () async => tmpDir,
        shareFile: (_, _, _) async {},
      );

      await expectLater(
        dl.downloadAndShare(
          url: 'https://tg-api.alsaba.cloud/docs/missing.mp4',
          extension: 'mp4',
          mimeType: 'video/mp4',
          kind: 'video',
          baseMessage: 'Video',
          l10n: AppLocalizationsEn(),
        ),
        throwsA(isA<HttpException>()),
      );

      final dir = Directory('${tmpDir.path}/almorabbi_media');
      expect(dir.listSync(), isEmpty);
    });
  });

  group('Player screen download buttons', () {
    testWidgets('PodcastPlayerScreen shows download button when URL is present and invokes downloader',
        (tester) async {
      final dl = _FakeDownloader();

      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('ar'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: PodcastPlayerScreen(
            url: 'https://tg-api.alsaba.cloud/docs/sample.mp3',
            title: 'درس تجريبي',
            downloader: dl,
          ),
        ),
      );
      await tester.pump();

      final btn = find.byKey(const Key('podcast_download_button'));
      expect(btn, findsOneWidget);
      await tester.tap(btn);
      await tester.pump();

      expect(dl.calls, hasLength(1));
      expect(dl.calls.single['mimeType'], 'audio/mpeg');
      expect(dl.calls.single['kind'], 'podcast');
      expect(dl.calls.single['url'], 'https://tg-api.alsaba.cloud/docs/sample.mp3');
    });

    testWidgets('VideoPlayerScreen shows download button when URL is present and invokes downloader',
        (tester) async {
      final dl = _FakeDownloader();

      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: VideoPlayerScreen(
            url: 'https://tg-api.alsaba.cloud/docs/sample.mp4',
            title: 'Sample Lesson',
            downloader: dl,
          ),
        ),
      );
      await tester.pump();

      final btn = find.byKey(const Key('video_download_button'));
      expect(btn, findsOneWidget);
      await tester.tap(btn);
      await tester.pump();

      expect(dl.calls, hasLength(1));
      expect(dl.calls.single['mimeType'], 'video/mp4');
      expect(dl.calls.single['kind'], 'video');
      expect(dl.calls.single['url'], 'https://tg-api.alsaba.cloud/docs/sample.mp4');
    });

    testWidgets('Download button is hidden when URL is null or empty', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          locale: Locale('ar'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: VideoPlayerScreen(url: null, title: 'بلا رابط'),
        ),
      );
      await tester.pump();
      expect(find.byKey(const Key('video_download_button')), findsNothing);
    });
  });
}
