/// «موقف بقرار» — the step itself, five short screens (docs/MAWAQIF.md):
/// the situation → the three responses → what happens now and later → the
/// hadith, its harder words and the idea → one step to try.
///
/// No response is marked right. The hadith comes after the parent has chosen,
/// as an answer, not as a preface. The step becomes an ordinary promise
/// (`keepPromise`, source `mawqif`), so Noor asks it back like a lesson's.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/analytics.dart';
import '../../../l10n/app_localizations.dart';
import '../../../theme/app_colors.dart';
import '../../../theme/design_tokens.dart';
import '../../companion/providers/companion_providers.dart';
import '../../program/widgets/next_step_sheet.dart';
import '../../programs/widgets/program_widgets.dart';
import '../data/mawqif.dart';

class MawqifScreen extends ConsumerStatefulWidget {
  const MawqifScreen({
    super.key,
    required this.mawqif,
    required this.childId,
    required this.childName,
    this.onFinished,
  });

  final Mawqif mawqif;
  final int childId;

  /// Already resolved by the caller («طفلك» for a default name).
  final String childName;

  /// Called once, when the parent reaches the last screen.
  final VoidCallback? onFinished;

  @override
  ConsumerState<MawqifScreen> createState() => _MawqifScreenState();
}

class _MawqifScreenState extends ConsumerState<MawqifScreen> {
  static const _last = 4;
  int _stage = 0;
  MawqifChoice? _chosen;
  bool _finished = false;

  Mawqif get m => widget.mawqif;

  void _go(int stage) {
    setState(() => _stage = stage);
    if (stage == _last && !_finished) {
      _finished = true;
      unawaited(Analytics.mawqifFinished(m.id));
      widget.onFinished?.call();
    }
  }

  void _choose(MawqifChoice c) {
    setState(() => _chosen = c);
    unawaited(Analytics.mawqifChoice(m.id, c.key));
    _go(2);
  }

  Future<void> _commit() async {
    final l10n = AppLocalizations.of(context);
    final slot = await showNextStepSheet(
      context,
      tryThis: m.step,
      childName: widget.childName,
    );
    if (slot == null || !mounted) return;
    unawaited(
      ref.read(companionMemoryProvider.notifier).keepPromise(
            childId: widget.childId,
            step: m.step,
            slot: slot,
            source: 'mawqif',
            topic: m.topic,
          ),
    );
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(l10n.promiseSaved)));
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return PopScope(
      // The system back steps back through the screens before leaving them
      // (except from the last one, which is an ending).
      canPop: _stage == 0 || _stage == _last,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) setState(() => _stage = _stage == 2 ? 1 : _stage - 1);
      },
      child: Scaffold(
        appBar: AppBar(title: Text(m.title)),
        body: SafeArea(
          child: Column(
            children: [
              LinearProgressIndicator(
                value: (_stage + 1) / (_last + 1),
                minHeight: 3,
              ),
              Expanded(
                child: SingleChildScrollView(
                  key: ValueKey('mawqif-stage-$_stage'),
                  padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: switch (_stage) {
                      0 => _situation(l10n),
                      1 => _choices(l10n),
                      2 => _consequence(l10n),
                      3 => _evidence(l10n),
                      _ => _step(l10n),
                    },
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _label(String text) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(
          text,
          style: TextStyle(
            color: context.colors.accentDeep,
            fontWeight: FontWeight.w800,
            fontSize: 13,
          ),
        ),
      );

  Widget _body(String text, {double size = 16}) => ContentText(
        text,
        style: TextStyle(color: context.colors.ink, fontSize: size, height: 1.7),
      );

  Widget _primary(String label, VoidCallback onPressed, {Key? key}) => Padding(
        padding: const EdgeInsets.only(top: 24),
        child: FilledButton(key: key, onPressed: onPressed, child: Text(label)),
      );

  List<Widget> _situation(AppLocalizations l10n) => [
        _label(l10n.mawqifSituationLabel),
        _body(m.situation, size: 17),
        _primary(l10n.mawqifWhatDoYouDo, () => _go(1),
            key: const ValueKey('mawqif-to-choices')),
      ];

  List<Widget> _choices(AppLocalizations l10n) {
    final c = context.colors;
    return [
      _label(l10n.mawqifChoicesTitle),
      Text(l10n.mawqifChoicesHint,
          style: TextStyle(color: c.textSecondary, fontSize: 13.5, height: 1.5)),
      const SizedBox(height: 12),
      for (final choice in m.choices)
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Material(
            color: c.surface,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(Dt.rCard),
              side: BorderSide(color: c.track),
            ),
            child: InkWell(
              key: ValueKey('mawqif-choice-${choice.key}'),
              borderRadius: BorderRadius.circular(Dt.rCard),
              onTap: () => _choose(choice),
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: _body(choice.text, size: 15),
              ),
            ),
          ),
        ),
    ];
  }

  Widget _outcome(String label, String text, Color color) => Padding(
        padding: const EdgeInsets.only(top: 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(label,
                  style: TextStyle(
                      color: color, fontWeight: FontWeight.w800, fontSize: 12)),
            ),
            const SizedBox(width: 10),
            Expanded(child: _body(text, size: 14.5)),
          ],
        ),
      );

  List<Widget> _consequence(AppLocalizations l10n) {
    final c = context.colors;
    final chosen = _chosen ?? m.choices.first;
    return [
      _label(l10n.mawqifChoicesTitle),
      _body(chosen.text, size: 15.5),
      _outcome(l10n.mawqifNow, chosen.now, c.accentDeep),
      _outcome(l10n.mawqifLater, chosen.later, c.primary),
      const SizedBox(height: 12),
      Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          key: const ValueKey('mawqif-compare'),
          tilePadding: EdgeInsets.zero,
          title: Text(l10n.mawqifCompare,
              style: TextStyle(
                  color: c.ink, fontWeight: FontWeight.w700, fontSize: 14)),
          children: [
            for (final other in m.choices)
              Padding(
                padding: const EdgeInsets.only(bottom: 14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    ContentText(other.text,
                        style: TextStyle(
                            color: c.ink,
                            fontWeight: other.key == chosen.key
                                ? FontWeight.w800
                                : FontWeight.w600,
                            fontSize: 14,
                            height: 1.6)),
                    _outcome(l10n.mawqifNow, other.now, c.accentDeep),
                    _outcome(l10n.mawqifLater, other.later, c.primary),
                  ],
                ),
              ),
          ],
        ),
      ),
      _primary(l10n.mawqifToEvidence, () => _go(3),
          key: const ValueKey('mawqif-to-evidence')),
    ];
  }

  List<Widget> _evidence(AppLocalizations l10n) {
    final c = context.colors;
    final context_ = m.evidence.context;
    return [
      _label(l10n.mawqifToEvidence),
      EvidenceCards([m.evidence]),
      if (context_ != null) ...[
        const SizedBox(height: 8),
        ContentText(context_,
            style:
                TextStyle(color: c.textSecondary, fontSize: 13, height: 1.6)),
      ],
      if (m.words.isNotEmpty) ...[
        const SizedBox(height: 16),
        _label(l10n.mawqifWordsTitle),
        for (final w in m.words)
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Text.rich(
              TextSpan(children: [
                TextSpan(
                    text: '${w.word}: ',
                    style: const TextStyle(fontWeight: FontWeight.w800)),
                TextSpan(text: w.meaning),
              ]),
              textDirection: TextDirection.rtl,
              style: TextStyle(color: c.ink, fontSize: 14, height: 1.6),
            ),
          ),
      ],
      const SizedBox(height: 16),
      _label(l10n.mawqifIdeaTitle),
      _body(m.idea, size: 16),
      _primary(l10n.mawqifToStep, () => _go(_last),
          key: const ValueKey('mawqif-to-step')),
    ];
  }

  List<Widget> _step(AppLocalizations l10n) => [
        _label(l10n.mawqifStepTitle),
        _body(m.step, size: 17),
        _primary(l10n.mawqifCommit, _commit,
            key: const ValueKey('mawqif-commit')),
        const SizedBox(height: 8),
        TextButton(
          key: const ValueKey('mawqif-close'),
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.mawqifClose),
        ),
      ];
}
