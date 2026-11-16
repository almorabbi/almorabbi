/// Modal sheet surfacing «همسة للمربّي» — a Socratic question the parent can
/// whisper to guide their child without ads, coins, or giving away the answer.
library;

import 'package:flutter/material.dart';

import '../../../l10n/app_localizations.dart';
import '../../../theme/app_colors.dart';
import '../../../theme/design_tokens.dart';
import '../../../widgets/ui/bouncy_button.dart';
import '../../../widgets/ui/brand_glyph.dart';

Future<void> showParentWhisperSheet(
  BuildContext context, {
  required String whisperText,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(Dt.rSheet)),
    ),
    builder: (ctx) => _ParentWhisperSheetBody(whisperText: whisperText),
  );
}

class _ParentWhisperSheetBody extends StatelessWidget {
  const _ParentWhisperSheetBody({required this.whisperText});

  final String whisperText;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = context.colors;
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                BrandGlyph(BrandIcon.lantern, size: 28, color: colors.accent),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    l10n.familyPuzzlesWhisperTitle,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w800,
                          color: colors.ink,
                        ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              l10n.familyPuzzlesWhisperLead,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: colors.textSecondary,
                  ),
            ),
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: colors.surfaceAlt,
                borderRadius: BorderRadius.circular(Dt.rCard),
                border: Border.all(
                  color: colors.accent.withValues(alpha: 0.45),
                ),
              ),
              child: Text(
                whisperText,
                style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                      color: colors.ink,
                      height: 1.5,
                      fontWeight: FontWeight.w600,
                    ),
              ),
            ),
            const SizedBox(height: 18),
            BouncyButton(
              label: l10n.familyPuzzlesWhisperGotIt,
              onTap: () => Navigator.of(context).pop(),
            ),
          ],
        ),
      ),
    );
  }
}
