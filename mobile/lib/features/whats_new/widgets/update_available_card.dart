/// «نسخة جديدة متاحة» — an optional update, never a wall.
///
/// The maintainer's call for 1.0.75 (2026-10-28): no forced update, «اللي عاوز يحدث
/// يحدث». The server names the newest live build (`/api/app-config` →
/// `latest_build_number`, env LATEST_BUILD_NUMBER, 0 = say nothing); a build
/// older than that shows one dismissible card on Today. Dismissal is per
/// latest build, so the next release can ask once more, and no more often.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart' show launchUrl, LaunchMode;

import '../../../l10n/app_localizations.dart';
import '../../../main.dart' show appConfigProvider, packageInfoProvider;
import '../../../theme/app_theme.dart';
import '../../../theme/design_tokens.dart';
import '../../onboarding/providers/onboarding_providers.dart';

const kStoreUrlFallback =
    'https://play.google.com/store/apps/details?id=com.alsaba.almorabbi';

/// Where the dismissed latest build is remembered.
const kUpdateDismissedBuildKey = 'tg.update.dismissed_build';

/// Whether to offer the update: the server knows a newer live build, and the
/// parent hasn't closed the card for that build.
bool shouldOfferUpdate({
  required int currentBuild,
  required Object? latestBuild,
  required SharedPreferences prefs,
}) {
  if (latestBuild is! int || latestBuild <= currentBuild) return false;
  final dismissed = prefs.getInt(kUpdateDismissedBuildKey);
  return dismissed == null || dismissed < latestBuild;
}

class UpdateAvailableCard extends ConsumerStatefulWidget {
  const UpdateAvailableCard({super.key});

  @override
  ConsumerState<UpdateAvailableCard> createState() =>
      _UpdateAvailableCardState();
}

class _UpdateAvailableCardState extends ConsumerState<UpdateAvailableCard> {
  bool _dismissed = false;

  @override
  Widget build(BuildContext context) {
    if (_dismissed) return const SizedBox.shrink();
    final prefs = ref.watch(sharedPreferencesProvider).valueOrNull;
    final info = ref.watch(packageInfoProvider).valueOrNull;
    final config = ref.watch(appConfigProvider).valueOrNull;
    if (prefs == null || info == null || config == null) {
      return const SizedBox.shrink();
    }
    final current = int.tryParse(info.buildNumber);
    final latest = config['latest_build_number'];
    if (current == null ||
        !shouldOfferUpdate(
            currentBuild: current, latestBuild: latest, prefs: prefs)) {
      return const SizedBox.shrink();
    }
    final storeUrl = config['store_url'] as String? ?? kStoreUrlFallback;
    final l10n = AppLocalizations.of(context);

    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 14, 12, 14),
        decoration: BoxDecoration(
          color: AppTheme.primary.withValues(alpha: .07),
          borderRadius: BorderRadius.circular(Dt.rCard),
          border: Border.all(color: AppTheme.primary.withValues(alpha: .18)),
        ),
        child: Row(
          children: [
            const Text('🌙', style: TextStyle(fontSize: 18)),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    l10n.updateAvailableTitle,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                      color: AppTheme.primary,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    l10n.updateAvailableBody,
                    style: TextStyle(
                      fontSize: 13.5,
                      height: 1.5,
                      color: AppTheme.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 8),
                  FilledButton(
                    onPressed: () => launchUrl(Uri.parse(storeUrl),
                        mode: LaunchMode.externalApplication),
                    child: Text(l10n.updateAvailableAction),
                  ),
                ],
              ),
            ),
            IconButton(
              tooltip: l10n.close,
              visualDensity: VisualDensity.compact,
              icon: Icon(Icons.close_rounded,
                  size: 18, color: AppTheme.textSecondary),
              onPressed: () {
                setState(() => _dismissed = true);
                prefs.setInt(kUpdateDismissedBuildKey, latest as int);
              },
            ),
          ],
        ),
      ),
    );
  }
}
