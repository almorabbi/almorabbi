import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../../core/analytics.dart';
import '../../../l10n/app_localizations.dart';
import '../../../theme/design_tokens.dart';
import '../../referral/referral_service.dart';
import '../../share/share_service.dart';
import '../services/infographic_stamp.dart';

/// Full-screen, zoomable viewer for a lesson infographic image.
/// Adds a rotate-screen toggle and a download button that stamps the app's
/// mark onto the saved copy only (in-app view stays clean).
class InfographicScreen extends StatefulWidget {
  final String url;
  const InfographicScreen({super.key, required this.url});

  @override
  State<InfographicScreen> createState() => _InfographicScreenState();
}

class _InfographicScreenState extends State<InfographicScreen> {
  bool _landscape = false;
  bool _saving = false;

  @override
  void dispose() {
    // Restore the app's portrait-first default on exit.
    SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
    super.dispose();
  }

  void _toggleRotation() {
    setState(() => _landscape = !_landscape);
    SystemChrome.setPreferredOrientations(
      _landscape
          ? [DeviceOrientation.landscapeLeft, DeviceOrientation.landscapeRight]
          : [DeviceOrientation.portraitUp],
    );
  }

  Future<void> _download() async {
    if (_saving) return;
    final l10n = AppLocalizations.of(context);
    final shareText = ShareService.shareText(
      l10n.shareInfographicText,
      l10n,
      referralCode: ReferralService.cachedCode,
    );
    setState(() => _saving = true);
    try {
      final bytes = await _buildWatermarked();
      final dir = await getTemporaryDirectory();
      final path =
          '${dir.path}/almorabbi_infographic_${DateTime.now().millisecondsSinceEpoch}.png';
      await File(path).writeAsBytes(bytes);
      await SharePlus.instance.share(ShareParams(
        files: [XFile(path, mimeType: 'image/png')],
        text: shareText,
      ));
      unawaited(Analytics.shareMoment('infographic'));
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(AppLocalizations.of(context).quizErrorLoading)),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  /// The infographic with the app's mark stamped on it (download only).
  Future<Uint8List> _buildWatermarked() async {
    final res = await http.get(Uri.parse(widget.url));
    if (res.statusCode != 200) throw Exception('HTTP ${res.statusCode}');
    return stampInfographic(res.bodyBytes);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(AppLocalizations.of(context).lessonInfographic),
        actions: [
          IconButton(
            tooltip: AppLocalizations.of(context).infographicRotateTooltip,
            icon: Icon(_landscape
                ? Icons.stay_current_portrait
                : Icons.screen_rotation),
            onPressed: _toggleRotation,
          ),
          IconButton(
            tooltip: AppLocalizations.of(context).infographicDownloadTooltip,
            icon: _saving
                ? SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Dt.surface),
                  )
                : const Icon(Icons.download),
            onPressed: _saving ? null : _download,
          ),
        ],
      ),
      backgroundColor: Colors.black,
      body: Center(
        child: InteractiveViewer(
          minScale: 0.8,
          maxScale: 4,
          child: Image.network(
            widget.url,
            fit: BoxFit.contain,
            loadingBuilder: (context, child, progress) => progress == null
                ? child
                : const Center(child: CircularProgressIndicator()),
            errorBuilder: (context, error, stack) => Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  AppLocalizations.of(context).infographicLoadError,
                  style: const TextStyle(color: Colors.white70, fontSize: 16),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
