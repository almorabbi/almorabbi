/// «تسميع مع الوالد» (docs/TASMEE_WITH_PARENT.md): the child recites, the
/// parent follows the mushaf and taps the word where the child slipped.
///
/// The verdict is the parent's — nothing listens to the child and nothing
/// leaves the phone. No coins, stars or badges: worship earns nothing here.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/analytics.dart';
import '../../../l10n/app_localizations.dart';
import '../../../theme/app_theme.dart';
import '../../quran/models/surah_names.dart';
import '../../quran/providers/quran_providers.dart';
import '../data/tasmee_store.dart';
import '../providers/journey_providers.dart';

/// Longest passage offered whole; above it the parent picks a range.
const int kTasmeeWholeSurahMax = 20;
const int kTasmeeDefaultRange = 10;

const _arabicDigits = ['٠', '١', '٢', '٣', '٤', '٥', '٦', '٧', '٨', '٩'];
String _ar(int n) =>
    n.toString().split('').map((d) => _arabicDigits[int.parse(d)]).join();

/// How each kind of slip looks: a colour and an icon, so it never relies on
/// colour alone.
const Map<SlipType, (Color, IconData)> slipStyle = {
  SlipType.omit: (Color(0xFFD9534F), Icons.remove_circle_outline),
  SlipType.add: (Color(0xFFE0A100), Icons.add_circle_outline),
  SlipType.swap: (Color(0xFF6A5ACD), Icons.swap_horiz),
  SlipType.hesitate: (Color(0xFF6B7B78), Icons.more_horiz),
};

String slipLabel(AppLocalizations l10n, SlipType t) => switch (t) {
  SlipType.omit => l10n.tasmeeSlipOmit,
  SlipType.add => l10n.tasmeeSlipAdd,
  SlipType.swap => l10n.tasmeeSlipSwap,
  SlipType.hesitate => l10n.tasmeeSlipHesitate,
};

/// Opens a session for [surah]: whole when short, otherwise after the parent
/// picks the verses (first [kTasmeeDefaultRange] preselected).
Future<void> startTasmee(
  BuildContext context,
  WidgetRef ref, {
  required int childId,
  required String childName,
  required int surah,
}) async {
  final data = await ref.read(quranDataProvider.future);
  final count = (data['$surah'] ?? const []).length;
  if (count == 0 || !context.mounted) return;
  var from = 1, to = count;
  if (count > kTasmeeWholeSurahMax) {
    final picked = await showModalBottomSheet<(int, int)>(
      context: context,
      builder: (_) => _RangeSheet(count: count),
    );
    if (picked == null) return;
    (from, to) = picked;
  }
  if (!context.mounted) return;
  await Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => TasmeeScreen(
        childId: childId,
        childName: childName,
        surah: surah,
        from: from,
        to: to,
      ),
    ),
  );
}

class _RangeSheet extends StatefulWidget {
  const _RangeSheet({required this.count});
  final int count;

  @override
  State<_RangeSheet> createState() => _RangeSheetState();
}

class _RangeSheetState extends State<_RangeSheet> {
  late int _from = 1;
  late int _to = kTasmeeDefaultRange.clamp(1, widget.count);

  Widget _pick(
    String label,
    int value,
    ValueChanged<int> onChanged, {
    int min = 1,
  }) => Row(
    children: [
      Expanded(child: Text(label)),
      DropdownButton<int>(
        value: value,
        items: [
          for (var i = min; i <= widget.count; i++)
            DropdownMenuItem(value: i, child: Text('$i')),
        ],
        onChanged: (v) => v == null ? null : setState(() => onChanged(v)),
      ),
    ],
  );

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              l10n.tasmeeRangeTitle,
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 12),
            _pick(l10n.tasmeeFrom, _from, (v) {
              _from = v;
              if (_to < v) _to = v;
            }),
            _pick(l10n.tasmeeTo, _to, (v) => _to = v, min: _from),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: () => Navigator.of(context).pop((_from, _to)),
              child: Text(l10n.tasmeeStart),
            ),
          ],
        ),
      ),
    );
  }
}

class TasmeeScreen extends ConsumerStatefulWidget {
  const TasmeeScreen({
    super.key,
    required this.childId,
    required this.childName,
    required this.surah,
    required this.from,
    required this.to,
  });

  final int childId;
  final String childName;
  final int surah;
  final int from;
  final int to;

  @override
  ConsumerState<TasmeeScreen> createState() => _TasmeeScreenState();
}

class _TasmeeScreenState extends ConsumerState<TasmeeScreen> {
  /// `ayah:word` → the slip the parent marked there.
  final Map<String, SlipType> _marks = {};

  @override
  void initState() {
    super.initState();
    Analytics.tasmeeStarted(widget.surah, widget.to - widget.from + 1);
  }

  Future<void> _mark(int ayah, int word, String text) async {
    final l10n = AppLocalizations.of(context);
    final key = '$ayah:$word';
    final current = _marks[key];
    final choice = await showModalBottomSheet<Object>(
      context: context,
      // Five rows and the word itself: on a short phone (or landscape) the
      // default 9/16-height sheet cannot hold them, so it scrolls.
      isScrollControlled: true,
      builder: (ctx) => SafeArea(
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.all(14),
                child: Text(
                  text,
                  textDirection: TextDirection.rtl,
                  style: GoogleFonts.amiriQuran(fontSize: 26),
                ),
              ),
              for (final t in SlipType.values)
                ListTile(
                  key: ValueKey('slip-${t.name}'),
                  leading: Icon(slipStyle[t]!.$2, color: slipStyle[t]!.$1),
                  title: Text(slipLabel(l10n, t)),
                  selected: current == t,
                  onTap: () => Navigator.of(ctx).pop(t),
                ),
              if (current != null)
                ListTile(
                  key: const ValueKey('slip-clear'),
                  leading: const Icon(Icons.close),
                  title: Text(l10n.tasmeeSlipClear),
                  onTap: () => Navigator.of(ctx).pop(_clear),
                ),
            ],
          ),
        ),
      ),
    );
    if (!mounted || choice == null) return;
    setState(() {
      if (choice is SlipType) {
        _marks[key] = choice;
      } else if (identical(choice, _clear)) {
        _marks.remove(key);
      }
    });
  }

  /// "Remove the mark" — a value of its own, since null means "dismissed".
  static const Object _clear = _Clear();

  Future<void> _finish() async {
    final l10n = AppLocalizations.of(context);
    final counts = {
      for (final t in SlipType.values)
        t: _marks.values.where((v) => v == t).length,
    };
    final ayat =
        (_marks.keys.map((k) => int.parse(k.split(':').first)).toSet().toList()
          ..sort());
    final save = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.tasmeeSummaryTitle),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: _marks.isEmpty
              ? [Text(l10n.tasmeeSummaryClean)]
              : [
                  Text(
                    l10n.tasmeeSummaryCounts(
                      counts[SlipType.omit]!,
                      counts[SlipType.add]!,
                      counts[SlipType.swap]!,
                      counts[SlipType.hesitate]!,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(l10n.tasmeeSummaryAyat(ayat.join('، '))),
                ],
        ),
        actions: [
          FilledButton(
            key: const ValueKey('tasmee-save'),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(l10n.tasmeeSave),
          ),
        ],
      ),
    );
    if (save != true || !mounted) return;
    final session = TasmeeSession(
      at: DateTime.now(),
      from: widget.from,
      to: widget.to,
      marks: [
        for (final e in _marks.entries)
          TasmeeMark(
            ayah: int.parse(e.key.split(':').first),
            word: int.parse(e.key.split(':').last),
            type: e.value,
          ),
      ],
    );
    await ref
        .read(tasmeeProvider(widget.childId).notifier)
        .add(widget.surah, session);
    Analytics.tasmeeFinished(widget.surah, _marks.length);
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final verses = ref
        .watch(quranDataProvider)
        .maybeWhen(
          data: (d) => d['${widget.surah}'] ?? const [],
          orElse: () => const [],
        );
    final shown = [
      for (final v in verses)
        if ((v['verse'] as num) >= widget.from &&
            (v['verse'] as num) <= widget.to)
          v,
    ];
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.tasmeeTitle(surahNames[widget.surah - 1])),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Row(
              children: [
                Icon(
                  Icons.hearing_outlined,
                  color: AppTheme.textSecondary,
                  size: 18,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    l10n.tasmeeHint,
                    style: TextStyle(color: AppTheme.textSecondary),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.all(12),
              itemCount: shown.length,
              itemBuilder: (context, i) {
                final ayah = (shown[i]['verse'] as num).toInt();
                final words = ayahWords('${shown[i]['text']}');
                return Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Directionality(
                    textDirection: TextDirection.rtl,
                    child: Wrap(
                      spacing: 4,
                      runSpacing: 2,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        for (var w = 0; w < words.length; w++)
                          _Word(
                            key: ValueKey('w-$ayah-$w'),
                            text: words[w],
                            slip: _marks['$ayah:$w'],
                            onTap: () => _mark(ayah, w, words[w]),
                          ),
                        Text(
                          ' ﴿${_ar(ayah)}﴾ ',
                          style: TextStyle(
                            fontSize: 18,
                            color: AppTheme.primary,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton(
                  key: const ValueKey('tasmee-finish'),
                  onPressed: shown.isEmpty ? null : _finish,
                  child: Text(l10n.tasmeeFinish),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Clear {
  const _Clear();
}

class _Word extends StatelessWidget {
  const _Word({
    super.key,
    required this.text,
    required this.slip,
    required this.onTap,
  });

  final String text;
  final SlipType? slip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final style = slip == null ? null : slipStyle[slip]!;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 3),
        decoration: style == null
            ? null
            : BoxDecoration(
                color: style.$1.withValues(alpha: .12),
                border: Border(bottom: BorderSide(color: style.$1, width: 3)),
                borderRadius: BorderRadius.circular(6),
              ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              text,
              style: GoogleFonts.amiriQuran(
                fontSize: 26,
                height: 1.9,
                color: AppTheme.textPrimary,
              ),
            ),
            if (style != null) Icon(style.$2, size: 14, color: style.$1),
          ],
        ),
      ),
    );
  }
}
