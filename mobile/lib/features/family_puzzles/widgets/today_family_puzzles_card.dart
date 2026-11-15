/// Calm secondary Home card inviting parents and children to play
/// «فوازير نور العائلية» together below the fold divider.
library;

import 'package:flutter/material.dart';

import '../../../core/app_routes.dart';
import '../../../l10n/app_localizations.dart';
import '../../../theme/app_colors.dart';
import '../../../theme/design_tokens.dart';
import '../../../widgets/ui/brand_glyph.dart';
import '../../../widgets/ui/directional_chevron.dart';

class TodayFamilyPuzzlesCard extends StatelessWidget {
  const TodayFamilyPuzzlesCard({super.key, this.onReturn});

  final VoidCallback? onReturn;

  Future<void> _open(BuildContext context) async {
    await Navigator.of(context).push(
      AppRoutes.familyPuzzles(source: GameSources.home),
    );
    onReturn?.call();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = context.colors;

    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Material(
        color: colors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(Dt.rCard),
          side: BorderSide(color: colors.track),
        ),
        child: InkWell(
          key: const ValueKey('today_family_puzzles_card_btn'),
          borderRadius: BorderRadius.circular(Dt.rCard),
          onTap: () => _open(context),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
            child: Row(
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: colors.accent.withValues(alpha: 0.16),
                    borderRadius: BorderRadius.circular(Dt.rButton),
                  ),
                  child: Center(
                    child: BrandGlyph(
                      BrandIcon.lantern,
                      size: 22,
                      color: colors.accentDeep,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        l10n.todayFamilyPuzzlesTitle,
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                              color: colors.ink,
                              fontWeight: FontWeight.w800,
                            ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        l10n.todayFamilyPuzzlesBody,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: colors.textSecondary,
                              height: 1.4,
                            ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  l10n.todayFamilyPuzzlesCta,
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                        color: colors.primary,
                        fontWeight: FontWeight.w800,
                      ),
                ),
                const SizedBox(width: 2),
                DirectionalChevron(color: colors.primary),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
