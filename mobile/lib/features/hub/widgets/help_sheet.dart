/// «أين أجد…؟» — a list of the questions people actually get stuck on, each
/// answering itself by navigating straight to the destination.
///
/// A first-run tour only ever helps the *next* cohort; the parents complaining
/// today are already past onboarding. This is the always-available version,
/// and it doubles as the cheapest possible instrumentation: `help_intent_tapped`
/// reports what people cannot find, in their own words, without a survey.
///
/// When one intent dominates the taps, that destination is still buried and
/// belongs somewhere more obvious.
library;

import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/analytics.dart';
import '../../../core/app_routes.dart';
import '../../../l10n/app_localizations.dart';
import '../../../theme/app_theme.dart';
import '../../../theme/design_tokens.dart';
import '../../../widgets/ui/brand_glyph.dart';
import '../../../widgets/ui/directional_chevron.dart';
import '../../identity/identity_entry.dart';

class _Intent {
  const _Intent(this.id, this.glyph, this.question, this.route);

  final String id;
  final BrandIcon glyph;
  final String Function(AppLocalizations l10n) question;
  final Route<void> Function() route;
}

final _intents = <_Intent>[
  // First, because these are the questions people actually asked. The eight
  // below answer "where is X" for someone who already knows what X is; the
  // 17 Aug 2026 complaint — «من أين أبدأ ثم الترتيب» and «سمعت المسارات أظن
  // المقصود بها المربي ليس المتربي» — sits one layer under that, and this
  // sheet could not answer it at all.
  _Intent('who_for', BrandIcon.openBook, (l) => l.helpWhoAreLessonsFor, AppRoutes.paths),
  _Intent('where_start', BrandIcon.path, (l) => l.helpWhereToStart, AppRoutes.paths),
  _Intent('games', BrandIcon.star, (l) => l.helpWhereGames, AppRoutes.games),
  _Intent('stories', BrandIcon.crescent, (l) => l.helpWhereStories, AppRoutes.storyBookshelf),
  _Intent('add_child', BrandIcon.sprig, (l) => l.helpHowAddChild, AppRoutes.childrenList),
  _Intent('quran', BrandIcon.openBook, (l) => l.helpWhereQuran, AppRoutes.quran),
  _Intent('progress', BrandIcon.flame, (l) => l.helpWhereProgress, AppRoutes.dailyRoutine),
  _Intent('badges', BrandIcon.medal, (l) => l.helpWhereBadges, AppRoutes.badges),
  if (kGoogleAccountEntryEnabled)
    _Intent('backup', BrandIcon.door, (l) => l.helpHowBackup, AppRoutes.identity),
  _Intent('contact', BrandIcon.speechBubble, (l) => l.helpHowContact, AppRoutes.feedback),
];

/// Opens the help sheet. [fromScreen] is a `Screens.*` constant.
Future<void> showHelpSheet(BuildContext context, String fromScreen) {
  unawaited(Analytics.helpOpened(fromScreen));
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(Dt.rSheet)),
    ),
    builder: (_) => const _HelpSheetBody(),
  );
}

class _HelpSheetBody extends StatelessWidget {
  const _HelpSheetBody();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return SafeArea(
      child: ListView(
        shrinkWrap: true,
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        children: [
          Text(
            l10n.helpTitle,
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 4),
          Text(
            l10n.helpSubtitle,
            style: TextStyle(fontSize: 13, color: AppTheme.textSecondary),
          ),
          const SizedBox(height: 16),
          for (final intent in _intents)
            _IntentRow(
              glyph: intent.glyph,
              label: intent.question(l10n),
              onTap: () {
                unawaited(Analytics.helpIntentTapped(intent.id));
                // Close the sheet first, so back from the destination returns
                // to the screen behind it rather than re-opening the sheet.
                Navigator.of(context).pop();
                Navigator.of(context).push(intent.route());
              },
            ),
        ],
      ),
    );
  }
}

class _IntentRow extends StatelessWidget {
  const _IntentRow({
    required this.glyph,
    required this.label,
    required this.onTap,
  });

  final BrandIcon glyph;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(Dt.rCard),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 14),
          child: Row(
            children: [
              ExcludeSemantics(child: BrandGlyph(glyph, size: 20)),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  label,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const DirectionalChevron(),
            ],
          ),
        ),
      ),
    );
  }
}
