/// Active 10-day Sha'ban home-preparation card («عشر الاستقبال في شعبان»).
///
/// Appears on Today (`ChildWeeklyHome`) when `ramadan.state == upcoming`,
/// `1 <= ramadan.daysUntilStart <= 10`, and the server serves today's station
/// (`ramadan.shabanPrepToday`). Completion state stays strictly local in
/// `SharedPreferences` — calm checkboxes, zero streaks, zero shame metrics.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/analytics.dart';
import '../../../core/app_routes.dart';
import '../../../core/haptics.dart';
import '../../../l10n/app_localizations.dart';
import '../../../theme/app_colors.dart';
import '../../../theme/design_tokens.dart';
import '../../../widgets/ui/paper_lantern.dart';
import '../../onboarding/providers/onboarding_providers.dart';
import '../data/programs_models.dart';
import '../providers/programs_providers.dart';
import 'program_widgets.dart';

String shabanPrepStorageKey(int hijriYear) => 'tg.shaban_prep.done.$hijriYear';

class ShabanWelcomeCard extends ConsumerStatefulWidget {
  const ShabanWelcomeCard({super.key});

  @override
  ConsumerState<ShabanWelcomeCard> createState() => _ShabanWelcomeCardState();
}

class _ShabanWelcomeCardState extends ConsumerState<ShabanWelcomeCard> {
  Future<void> _toggleStationDone(int hijriYear, String stationKey) async {
    Haptics.selection();
    final prefs = await ref.read(sharedPreferencesProvider.future);
    final key = shabanPrepStorageKey(hijriYear);
    final cur = Set<String>.from(prefs.getStringList(key) ?? const []);
    if (cur.contains(stationKey)) {
      cur.remove(stationKey);
    } else {
      cur.add(stationKey);
    }
    await prefs.setStringList(key, cur.toList()..sort());
    unawaited(Analytics.programAction('shaban_prep', stationKey));
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final overview = ref.watch(programsOverviewProvider).valueOrNull;
    if (overview == null) return const SizedBox.shrink();
    final r = overview.ramadan;
    final station = r.shabanPrepToday;
    final days = r.daysUntilStart;
    final year = r.season?.hijriYear;
    if (r.state != RamadanState.upcoming ||
        station == null ||
        days == null ||
        days < 1 ||
        days > 10 ||
        year == null) {
      return const SizedBox.shrink();
    }

    final prefs = ref.watch(sharedPreferencesProvider).valueOrNull;
    final doneKeys = prefs?.getStringList(shabanPrepStorageKey(year)) ?? const [];
    final isDone = doneKeys.contains(station.key);
    final profile = ref.watch(activeChildProfileProvider);
    final childId =
        profile?.id ??
        (overview.children.isNotEmpty ? overview.children.first.childId : null);

    final l10n = AppLocalizations.of(context);
    final c = context.colors;

    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Material(
        key: const ValueKey('shaban_welcome_card'),
        color: c.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(Dt.rCard),
          side: BorderSide(
            color: (isDone ? c.paperGold : c.primary).withValues(alpha: 0.42),
            width: 1.4,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  PaperLantern(lit: isDone, height: 34),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: c.accent.withValues(alpha: 0.16),
                            borderRadius: BorderRadius.circular(Dt.rChip),
                          ),
                          child: Text(
                            l10n.shabanPrepEyebrow(days),
                            style: Theme.of(context).textTheme.labelSmall
                                ?.copyWith(
                                  color: c.accentDeep,
                                  fontWeight: FontWeight.w800,
                                ),
                          ),
                        ),
                        const SizedBox(height: 4),
                        ContentText(
                          station.title,
                          style: Theme.of(context).textTheme.titleSmall
                              ?.copyWith(
                                color: c.ink,
                                fontWeight: FontWeight.w800,
                              ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              if (station.subtitle != null) ...[
                const SizedBox(height: 8),
                ContentText(
                  station.subtitle!,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: c.textSecondary,
                    height: 1.45,
                  ),
                ),
              ],
              if (station.steps.isNotEmpty) ...[
                const SizedBox(height: 10),
                ProgramBullets(station.steps, numbered: true),
              ],
              if (station.childRole != null) ...[
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: c.surfaceAlt,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: ContentText(
                    station.childRole!,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: c.ink,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const SizedBox(height: 10),
              ],
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  FilledButton.tonalIcon(
                    key: const ValueKey('shaban_prep_mark_btn'),
                    onPressed: () => _toggleStationDone(year, station.key),
                    icon: Icon(
                      isDone
                          ? Icons.check_circle_rounded
                          : Icons.check_circle_outline_rounded,
                      size: 18,
                    ),
                    label: Text(
                      isDone ? l10n.shabanPrepDoneBtn : l10n.shabanPrepMarkBtn,
                    ),
                  ),
                  OutlinedButton.icon(
                    key: const ValueKey('shaban_prep_print_btn'),
                    onPressed: () =>
                        Navigator.of(context).push(AppRoutes.ramadanPrintKit()),
                    icon: const Icon(Icons.print_outlined, size: 18),
                    label: Text(l10n.shabanPrepOpenPrintCta),
                  ),
                  if (childId != null)
                    TextButton(
                      key: const ValueKey('shaban_prep_open_ramadan_btn'),
                      onPressed: () =>
                          Navigator.of(context).push(AppRoutes.ramadan(childId)),
                      child: Text(l10n.noorChipRamadan),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
