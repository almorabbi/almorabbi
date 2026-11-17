import 'dart:async';

import 'package:flutter/material.dart';
import 'package:in_app_review/in_app_review.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart'
    show LaunchMode, canLaunchUrl, launchUrl;

import '../../../core/analytics.dart';
import '../../../l10n/app_localizations.dart';

/// Gentle, positive-moment Play Store rating prompt.
///
/// Shown only AFTER accrued positive moments (never on first use), snoozes
/// gracefully on "Later" (waiting both a cooldown and additional positive
/// moments, capped at [maxPrompts] total shows), and falls back directly to
/// the Google Play listing if the user taps "Rate now" while Play silently
/// suppresses the native in-app review sheet.
class ReviewPrompt {
  static const _kCount = 'review.positive_actions';
  static const _kLegacyAsked = 'review.asked';
  static const _kMigratedV2 = 'review.migrated.v2';
  static const _kCompleted = 'review.completed.v2';
  static const _kShows = 'review.prompt_shows.v2';
  static const _kNextCountAt = 'review.next_count_at.v2';
  static const _kLastShownMs = 'review.last_shown_ms.v2';

  static const _storePackageId = 'com.alsaba.almorabbi';

  /// Positive moments needed before the first prompt appears.
  static const int initialThreshold = 2;

  /// Additional positive moments required before re-asking after "Later".
  static const int snoozeActionsStep = 3;

  /// Minimum elapsed wall time after "Later" / dismiss before re-asking.
  static const Duration snoozeCooldown = Duration(days: 14);

  /// Maximum times the prompt may appear without the user tapping "Rate now".
  static const int maxPrompts = 3;

  /// If Play's `requestReview()` returns faster than this without throwing,
  /// Android suppressed the native review bottom sheet (quota / prior review).
  static const Duration silentNoOpThreshold = Duration(milliseconds: 500);

  static bool _showing = false;

  @visibleForTesting
  static DateTime Function() nowProvider = DateTime.now;

  @visibleForTesting
  static Future<bool> Function()? isAvailableOverride;

  @visibleForTesting
  static Future<void> Function()? requestReviewOverride;

  @visibleForTesting
  static Future<void> Function()? openStoreListingOverride;

  @visibleForTesting
  static void resetTestOverrides() {
    nowProvider = DateTime.now;
    isAvailableOverride = null;
    requestReviewOverride = null;
    openStoreListingOverride = null;
    _showing = false;
  }

  /// Ensures legacy <= 2.0.0 devices where `review.asked = true` was set on any
  /// dismissal/later tap get a fair, gentle second chance under v2 rules.
  static Future<void> _ensureMigrated(SharedPreferences p) async {
    if (p.getBool(_kMigratedV2) ?? false) return;
    await p.setBool(_kMigratedV2, true);
    if (p.getBool(_kLegacyAsked) ?? false) {
      final currentCount = p.getInt(_kCount) ?? 0;
      if (!p.containsKey(_kShows)) {
        await p.setInt(_kShows, 1);
      }
      if (!p.containsKey(_kNextCountAt)) {
        await p.setInt(_kNextCountAt, currentCount + 2);
      }
    }
  }

  /// Records a positive moment without interrupting the current transition.
  static Future<void> recordMoment() async {
    try {
      final p = await SharedPreferences.getInstance();
      await _ensureMigrated(p);
      final count = (p.getInt(_kCount) ?? 0) + 1;
      await p.setInt(_kCount, count);
    } catch (_) {
      // Best-effort counter; never disrupt the parent's workflow.
    }
  }

  /// Marks the rating flow finished when opened explicitly from Settings.
  static Future<void> markCompletedFromSettings() async {
    try {
      final p = await SharedPreferences.getInstance();
      await _ensureMigrated(p);
      await p.setBool(_kCompleted, true);
      unawaited(
        Analytics.reviewPromptAnswered(
          action: 'settings_rate',
          source: 'settings',
          showNumber: p.getInt(_kShows) ?? 0,
        ),
      );
    } catch (_) {
      // Best-effort persistence.
    }
  }

  static Future<void> _openStoreListing() async {
    if (openStoreListingOverride != null) {
      await openStoreListingOverride!();
      return;
    }
    final market = Uri.parse('market://details?id=$_storePackageId');
    final web = Uri.parse(
      'https://play.google.com/store/apps/details?id=$_storePackageId',
    );
    try {
      if (await canLaunchUrl(market)) {
        if (await launchUrl(market, mode: LaunchMode.externalApplication)) {
          return;
        }
      }
    } catch (_) {
      // Fall through to in_app_review / web URL.
    }
    try {
      await InAppReview.instance.openStoreListing(appStoreId: _storePackageId);
      return;
    } catch (_) {
      // Fall through to HTTPS Play URL.
    }
    try {
      await launchUrl(web, mode: LaunchMode.externalApplication);
    } catch (_) {
      // Headless environment or missing browser; ignore safely.
    }
  }

  /// Launches Play's native in-app review sheet; if Play suppresses it
  /// silently in under [silentNoOpThreshold] or is unavailable, opens the store
  /// listing directly because the user explicitly tapped "Rate now".
  static Future<void> _requestReviewOrOpenStore() async {
    try {
      final available = await (isAvailableOverride != null
          ? isAvailableOverride!()
          : InAppReview.instance.isAvailable());
      if (available) {
        final started = nowProvider();
        await (requestReviewOverride != null
            ? requestReviewOverride!()
            : InAppReview.instance.requestReview());
        if (nowProvider().difference(started) >= silentNoOpThreshold) {
          return;
        }
      }
    } catch (_) {
      // Fall through to explicit Play Store listing.
    }
    await _openStoreListing();
  }

  /// Records a positive moment and politely asks once eligible gates pass.
  static Future<void> maybeAsk(
    BuildContext context, {
    String source = 'app',
  }) async {
    if (_showing) return;
    _showing = true;
    try {
      final p = await SharedPreferences.getInstance();
      await _ensureMigrated(p);

      final count = (p.getInt(_kCount) ?? 0) + 1;
      await p.setInt(_kCount, count);

      if (p.getBool(_kCompleted) ?? false) return;

      final shows = p.getInt(_kShows) ?? 0;
      if (shows >= maxPrompts) return;

      final nextAt = p.getInt(_kNextCountAt) ?? initialThreshold;
      if (count < nextAt) return;

      final now = nowProvider();
      final lastMs = p.getInt(_kLastShownMs);
      if (lastMs != null) {
        final elapsed = now.difference(
          DateTime.fromMillisecondsSinceEpoch(lastMs),
        );
        if (elapsed < snoozeCooldown) return;
      }

      if (!context.mounted) return;

      final showNumber = shows + 1;
      unawaited(p.setInt(_kShows, showNumber));
      unawaited(p.setInt(_kNextCountAt, count + snoozeActionsStep));
      unawaited(p.setInt(_kLastShownMs, now.millisecondsSinceEpoch));
      unawaited(
        Analytics.reviewPromptShown(source: source, showNumber: showNumber),
      );

      final yes = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(AppLocalizations.of(ctx).reviewPromptTitle),
          content: Text(AppLocalizations.of(ctx).reviewPromptBody),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: Text(AppLocalizations.of(ctx).reviewPromptLater),
            ),
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: Text(AppLocalizations.of(ctx).reviewPromptNow),
            ),
          ],
        ),
      );

      if (yes == true) {
        await p.setBool(_kCompleted, true);
        unawaited(
          Analytics.reviewPromptAnswered(
            action: 'rate_now',
            source: source,
            showNumber: showNumber,
          ),
        );
        await _requestReviewOrOpenStore();
      } else {
        unawaited(
          Analytics.reviewPromptAnswered(
            action: yes == false ? 'later' : 'dismissed',
            source: source,
            showNumber: showNumber,
          ),
        );
      }
    } finally {
      _showing = false;
    }
  }
}
