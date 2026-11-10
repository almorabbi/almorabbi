/// «مهمة اليوم» on Today, for the parent — no handover needed.
///
/// Production, 28 days to 2026-11-08 (real devices): 4 bank missions were
/// confirmed. The only road ran through child mode — PIN, handover, the
/// child's claim, the evening list. Here the parent reads today's card, tells
/// the child about it, and marks it once it happened, with an optional
/// «كلمة طيبة» the child reads the next time they hold the phone.
///
/// Reading mints nothing on the server (the card is a preview until a tap);
/// the child's own card, when they already have one today, is the one shown
/// and settled. Hides itself while loading, on any failure, on an older server
/// and for a band without a mission bank. No number, no coin, no "missed".
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/analytics.dart';
import '../../core/haptics.dart';
import '../../l10n/app_localizations.dart';
import '../../state/chat_notifier.dart';
import '../../theme/app_colors.dart';
import '../../theme/design_tokens.dart';
import '../child_memory/widgets/memory_errors.dart';
import '../lanterns/providers/lantern_providers.dart';

class TodayMissionRow extends ConsumerStatefulWidget {
  const TodayMissionRow({
    super.key,
    required this.childId,
    required this.childName,
    required this.ageGroup,
  });

  final int childId;
  final String childName;
  final String ageGroup;

  @override
  ConsumerState<TodayMissionRow> createState() => _TodayMissionRowState();
}

class _TodayMissionRowState extends ConsumerState<TodayMissionRow> {
  Map<String, dynamic>? _card;
  bool _sending = false;
  bool _shownLogged = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(TodayMissionRow old) {
    super.didUpdateWidget(old);
    if (old.childId != widget.childId) {
      _card = null;
      _shownLogged = false;
      _load();
    }
  }

  Future<void> _load() async {
    final childId = widget.childId;
    try {
      final card =
          await ref.read(tgClientProvider).fetchParentMissionToday(childId);
      if (!mounted || childId != widget.childId) return;
      setState(() => _card = card);
      if (card != null && card['status'] != 'confirmed' && !_shownLogged) {
        _shownLogged = true;
        unawaited(Analytics.missionShownParent(widget.ageGroup));
      }
    } catch (_) {
      // Quiet: a row that cannot load is simply not shown.
    }
  }

  bool get _done => _card?['status'] == 'confirmed';

  Future<void> _markDone() async {
    final card = _card;
    final key = card?['mission_key'] as String?;
    if (card == null || key == null || _sending) return;
    final note = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _PraiseSheet(childName: widget.childName),
    );
    if (note == null || !mounted) return; // dismissed: nothing sent
    setState(() => _sending = true);
    try {
      final ok = await ref.read(tgClientProvider).markParentMissionDone(
            widget.childId,
            missionKey: key,
            note: note,
          );
      if (!mounted) return;
      if (!ok) {
        // The card can no longer be settled (it expired): let it go quietly.
        setState(() => _card = null);
        return;
      }
      Haptics.success();
      unawaited(Analytics.missionDoneParent(widget.ageGroup,
          withNote: note.trim().isNotEmpty));
      if (note.trim().isNotEmpty) {
        unawaited(Analytics.praiseSent(widget.ageGroup));
      }
      setState(() => _card = {...card, 'status': 'confirmed'});
      // The same row lights today's lantern on the server.
      ref.invalidate(familyWeekProvider);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.maybeOf(context)
        ?..removeCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(describeActionFailure(context, e))));
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final card = _card;
    final title = (card?['title_ar'] as String?)?.trim() ?? '';
    if (card == null || title.isEmpty) return const SizedBox.shrink();
    final l10n = AppLocalizations.of(context);
    final colors = context.colors;
    final instruction = (card['instruction_ar'] as String?)?.trim() ?? '';

    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Container(
        decoration: BoxDecoration(
          color: colors.surface,
          borderRadius: BorderRadius.circular(Dt.rCard),
          border: Border.all(color: colors.track),
        ),
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(Icons.wb_sunny_outlined, color: colors.accentDeep, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    l10n.missionTodayFor(widget.childName),
                    style: TextStyle(
                      color: colors.accentDeep,
                      fontWeight: FontWeight.w800,
                      fontSize: 13,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              title,
              style: TextStyle(
                color: colors.ink,
                fontWeight: FontWeight.w800,
                fontSize: 15,
                height: 1.4,
              ),
            ),
            if (instruction.isNotEmpty && !_done) ...[
              const SizedBox(height: 4),
              Text(
                instruction,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    color: colors.textSecondary, fontSize: 12.5, height: 1.5),
              ),
            ],
            const SizedBox(height: 10),
            if (_done)
              Row(
                children: [
                  Icon(Icons.check_circle_rounded,
                      color: colors.success, size: 18),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      l10n.missionTodayDone(widget.childName),
                      style: TextStyle(
                        color: colors.successText,
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                      ),
                    ),
                  ),
                ],
              )
            else
              Row(
                children: [
                  Expanded(
                    child: Text(
                      l10n.missionTodayHint(widget.childName),
                      style: TextStyle(
                          color: colors.inkSoft, fontSize: 12, height: 1.5),
                    ),
                  ),
                  const SizedBox(width: 8),
                  FilledButton.tonal(
                    onPressed: _sending ? null : _markDone,
                    child: Text(l10n.missionTodayDoneButton),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

/// After «أُنجزت»: an optional kind word for the child — the evening screen's
/// fixed chips, or a short line of the parent's own. Pops the note ('' for
/// none); a dismissed sheet pops null and nothing is sent.
class _PraiseSheet extends StatefulWidget {
  const _PraiseSheet({required this.childName});

  final String childName;

  @override
  State<_PraiseSheet> createState() => _PraiseSheetState();
}

class _PraiseSheetState extends State<_PraiseSheet> {
  String? _chip;
  final _own = TextEditingController();

  @override
  void dispose() {
    _own.dispose();
    super.dispose();
  }

  String get _note {
    final own = _own.text.trim();
    if (_chip != null && own.isNotEmpty) return '${_chip!} — $own';
    return _chip ?? own;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = context.colors;
    final chips = [
      l10n.praiseChipAhsant,
      l10n.praiseChipBarakAllahuFik,
      l10n.praiseChipProud,
    ];
    return Padding(
      padding: EdgeInsets.fromLTRB(
          20, 0, 20, 20 + MediaQuery.viewInsetsOf(context).bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            l10n.missionPraiseSheetTitle(widget.childName),
            style: TextStyle(
                color: colors.ink, fontWeight: FontWeight.w800, fontSize: 16),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final c in chips)
                ChoiceChip(
                  label: Text(c),
                  selected: _chip == c,
                  onSelected: (on) => setState(() => _chip = on ? c : null),
                ),
            ],
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _own,
            maxLength: 120,
            textInputAction: TextInputAction.done,
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(hintText: l10n.praiseOwnWordsHint),
          ),
          const SizedBox(height: 8),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(_note),
            child: Text(_note.isEmpty
                ? l10n.missionPraiseSkip
                : l10n.missionPraiseSend),
          ),
        ],
      ),
    );
  }
}
