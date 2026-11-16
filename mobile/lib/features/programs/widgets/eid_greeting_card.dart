/// Zero-PII Paper-Cut Family Eid Greeting Card («عيدية العائلة الورقية»).
///
/// Built purely from pre-approved bilingual templates (`eid_greetings`) plus an
/// optional family-wide Ramadan word (no child names, ages, photos, or typed
/// free text ever leave the device or appear on the shared card).
///
/// Reuses [ShareCardFrame], [ShareCardEyebrow], [ShareCardBrandFooter], and
/// [ShareService.shareMomentCard] so it matches every viral moment card.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/analytics.dart';
import '../../../core/haptics.dart';
import '../../../l10n/app_localizations.dart';
import '../../../l10n/content_direction.dart';
import '../../../theme/app_colors.dart';
import '../../../theme/app_theme.dart';
import '../../../widgets/ui/paper_lantern.dart';
import '../../share/share_service.dart';
import '../../share/shareable_moment_card.dart';
import '../data/programs_models.dart';
import 'program_widgets.dart';

class RamadanEidGreetingCard extends StatefulWidget {
  const RamadanEidGreetingCard({
    super.key,
    required this.templates,
    required this.hijriYear,
    this.familyWord,
  });

  final List<EidGreetingTemplate> templates;
  final int hijriYear;
  final String? familyWord;

  @override
  State<RamadanEidGreetingCard> createState() => _RamadanEidGreetingCardState();
}

class _RamadanEidGreetingCardState extends State<RamadanEidGreetingCard> {
  int _selectedIdx = 0;
  bool _includeWord = false;
  bool _sharing = false;

  Future<void> _share(EidGreetingTemplate tpl) async {
    if (_sharing) return;
    final l10n = AppLocalizations.of(context);
    setState(() => _sharing = true);
    Haptics.selection();
    unawaited(Analytics.programAction('ramadan', 'eid_greeting_${tpl.key}'));
    final cardWidget = _EidGreetingShareCanvas(
      template: tpl,
      familyWord: _includeWord ? widget.familyWord : null,
      wordPrefix: _includeWord && widget.familyWord != null
          ? l10n.eidGreetingIncludeWord(widget.familyWord!)
          : null,
    );
    final msg = [
      tpl.headline,
      ...tpl.lines,
      if (_includeWord && widget.familyWord != null) widget.familyWord!,
      if (tpl.closing != null) tpl.closing!,
    ].join('\n');

    final ok = await ShareService.shareMomentCard(
      card: cardWidget,
      message: msg,
      fileTag: 'eid_${widget.hijriYear}_${tpl.key}',
    );
    if (!mounted) return;
    setState(() => _sharing = false);
    if (!ok) showProgramSnack(context, l10n.recapShareFailed);
  }

  @override
  Widget build(BuildContext context) {
    if (widget.templates.isEmpty) return const SizedBox.shrink();
    final idx = _selectedIdx.clamp(0, widget.templates.length - 1);
    final tpl = widget.templates[idx];
    final l10n = AppLocalizations.of(context);
    final c = context.colors;

    return ProgramSection(
      key: const ValueKey('ramadan_eid_greeting_section'),
      title: l10n.eidGreetingTitle,
      emoji: '💌',
      tone: SectionTone.highlight,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            l10n.eidGreetingSubtitle,
            style: TextStyle(color: c.textSecondary, height: 1.5, fontSize: 13),
          ),
          const SizedBox(height: 10),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (var i = 0; i < widget.templates.length; i++)
                  Padding(
                    padding: const EdgeInsetsDirectional.only(end: 8),
                    child: ChoiceChip(
                      key: ValueKey('eid_tpl_${widget.templates[i].key}'),
                      label: Text('${i + 1} · ${widget.templates[i].headline}'),
                      selected: i == idx,
                      onSelected: (_) {
                        Haptics.selection();
                        setState(() => _selectedIdx = i);
                      },
                    ),
                  ),
              ],
            ),
          ),
          if (widget.familyWord != null) ...[
            const SizedBox(height: 8),
            SwitchListTile.adaptive(
              key: const ValueKey('eid_greeting_word_toggle'),
              contentPadding: EdgeInsets.zero,
              value: _includeWord,
              title: Text(
                l10n.eidGreetingIncludeWord(widget.familyWord!),
                style: TextStyle(
                  color: c.ink,
                  fontWeight: FontWeight.w700,
                  fontSize: 13.5,
                ),
              ),
              onChanged: (v) => setState(() => _includeWord = v),
            ),
          ],
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: AspectRatio(
              aspectRatio: 1,
              child: FittedBox(
                child: SizedBox.fromSize(
                  size: ShareableMomentCard.size,
                  child: _EidGreetingShareCanvas(
                    key: const ValueKey('eid_greeting_preview'),
                    template: tpl,
                    familyWord: _includeWord ? widget.familyWord : null,
                    wordPrefix: _includeWord && widget.familyWord != null
                        ? l10n.eidGreetingIncludeWord(widget.familyWord!)
                        : null,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            key: const ValueKey('eid_greeting_share_btn'),
            onPressed: _sharing ? null : () => _share(tpl),
            icon: _sharing
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.share_rounded),
            label: Text(l10n.eidGreetingShareCta),
          ),
        ],
      ),
    );
  }
}

class _EidGreetingShareCanvas extends StatelessWidget {
  const _EidGreetingShareCanvas({
    super.key,
    required this.template,
    this.familyWord,
    this.wordPrefix,
  });

  final EidGreetingTemplate template;
  final String? familyWord;
  final String? wordPrefix;

  @override
  Widget build(BuildContext context) {
    final dir = ContentDirectionality.resolve(
      text: template.headline,
      fallback: TextDirection.rtl,
    );
    final mq = MediaQuery.maybeOf(context);
    final card = Directionality(
      textDirection: dir,
      child: ShareCardFrame(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const PaperLantern(lit: true, height: 112),
            const SizedBox(height: 20),
            if (template.eyebrow.isNotEmpty) ...[
              ShareCardEyebrow(template.eyebrow),
              const SizedBox(height: 20),
            ],
            Text(
              template.headline,
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.cairo(
                fontSize: 42,
                fontWeight: FontWeight.w800,
                color: AppTheme.textPrimary,
                height: 1.3,
              ),
            ),
            const SizedBox(height: 18),
            for (final line in template.lines.take(3))
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Text(
                  line,
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.cairo(
                    fontSize: 28,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.textPrimary,
                    height: 1.45,
                  ),
                ),
              ),
            if (familyWord != null && wordPrefix != null) ...[
              const SizedBox(height: 14),
              ShareCardEyebrow(wordPrefix!),
            ],
            if (template.closing != null) ...[
              const SizedBox(height: 18),
              Text(
                template.closing!,
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.cairo(
                  fontSize: 27,
                  fontWeight: FontWeight.w800,
                  color: AppTheme.primary,
                ),
              ),
            ],
            const SizedBox(height: 24),
            const ShareCardBrandFooter(qrSize: 96),
          ],
        ),
      ),
    );
    return mq == null
        ? card
        : MediaQuery(
            data: mq.copyWith(textScaler: TextScaler.noScaling),
            child: card,
          );
  }
}
