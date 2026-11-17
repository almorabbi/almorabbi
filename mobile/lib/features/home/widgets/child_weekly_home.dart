/// Child-centric Home screen variant (`child_home_v2`), streamlined into
/// three calm daily stations:
///   1. Your parenting step today ([TodayFocusCard], a single reflection card
///      per active child — follow-up OR Mawaqif, plus sibling follow-up when due
///      for another child — and a sleek collapsible [TodayWeeklyPlanCard]).
///   2. Shared family time ([TodayMissionRow], [TodayFamilyPuzzlesCard], and
///      clear Child Corner handover tile inside [ChildDayCard]).
///   3. Companion & seasonal corner ([TodayAskBlock], optional Friday harvest,
///      [WeekLanternString], [ShabanWelcomeCard], [ProgramsHomeCard]), followed
///      by a quiet rituals/journey footer.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/analytics.dart';
import '../../../core/app_routes.dart';
import '../../../core/clock.dart';
import '../../../l10n/app_localizations.dart';
import '../../../theme/app_colors.dart';
import '../../../theme/design_tokens.dart';
import '../../../widgets/ui/brand_glyph.dart';
import '../../child_memory/data/placeholder_names.dart';
import '../../child_memory/providers/memory_providers.dart';
import '../../child_memory/widgets/today_followup_card.dart';
import '../../child_memory/widgets/today_weekly_plan_card.dart';
import '../../companion/providers/companion_providers.dart';
import '../../companion/widgets/noor_presence.dart';
import '../../companion/widgets/noor_today_header.dart';
import '../../family_puzzles/widgets/today_family_puzzles_card.dart';
import '../../family_road/providers/family_road_providers.dart';
import '../../family_road/widgets/horizon_strip.dart';
import '../../journey/widgets/child_journey_card.dart';
import '../../lanterns/providers/lantern_providers.dart';
import '../../lanterns/widgets/friday_harvest.dart';
import '../../lanterns/widgets/week_lantern_string.dart';
import '../../mawaqif/widgets/today_mawqif_card.dart';
import '../../missions/today_mission_row.dart';
import '../../onboarding/providers/onboarding_providers.dart';
import '../../parent_day/child_day_card.dart';
import '../../program/data/progress_models.dart';
import '../../program/providers/program_providers.dart';
import '../../program/providers/progress_providers.dart';
import '../../programs/data/programs_models.dart';
import '../../programs/providers/programs_providers.dart';
import '../../programs/widgets/programs_home_card.dart';
import '../../programs/widgets/shaban_welcome_card.dart';
import '../../referral/pride_invite_card.dart';
import '../../shell/root_tab.dart';
import '../../whats_new/widgets/update_available_card.dart';
import '../../whats_new/widgets/whats_new_card.dart';
import '../experiment/child_home_experiment.dart';
import 'home_community_note.dart';
import 'sky_band.dart';
import 'today_ask_block.dart';
import 'today_child_block.dart';
import 'today_focus_card.dart';
import 'today_rituals_row.dart';
import 'today_section.dart';

/// Child-centric Home body shown when `child_home_v2` resolves to
/// [ChildHomeArm.weekly].
class ChildWeeklyHome extends ConsumerWidget {
  const ChildWeeklyHome({
    super.key,
    required this.onGoToTab,
    this.focusCardKey,
  });

  final void Function(int tabIndex) onGoToTab;
  final Key? focusCardKey;

  bool _isFirstWeek(
    WidgetRef ref,
    ActiveChildProfile profile,
    DateTime now,
  ) {
    if (ref.watch(justOnboardedPlanChildProvider) == profile.id) {
      return true;
    }
    final prefs = ref.watch(sharedPreferencesProvider).valueOrNull;
    final raw = prefs?.getString(firstWeekOnboardedKey(profile.id));
    if (raw == null || raw.isEmpty) return false;
    final recorded = DateTime.tryParse(raw);
    if (recorded == null) return false;
    final diff = now.toUtc().difference(recorded.toUtc());
    return !diff.isNegative && diff.inDays < 7;
  }

  Future<void> _refresh(
    WidgetRef ref,
    ActiveChildProfile? profile,
    String lang,
  ) async {
    ref.invalidate(activeChildProgressProvider);
    ref.invalidate(familyWeekProvider);
    ref.invalidate(dueFollowupsProvider);
    if (profile != null) {
      ref.invalidate(weeklyPlanProvider((childId: profile.id, lang: lang)));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final colors = context.colors;
    final profile = ref.watch(activeChildProfileProvider);
    final ageGroup = ref.watch(selectedAgeGroupProvider);
    final bundle = ref
        .watch(activeChildProgressProvider)
        ?.maybeWhen(data: (b) => b, orElse: () => null);
    final noorOn = ref.watch(noorHeaderEnabledProvider);
    final inRamadan =
        ref.watch(programsOverviewProvider).valueOrNull?.ramadan.state ==
        RamadanState.ramadan;
    final season = ref.watch(skySeasonProvider);
    final horizon = ref.watch(horizonStripGateProvider);
    final now = ref.watch(clockProvider)();
    final week = ref.watch(familyWeekProvider).valueOrNull;
    final dueFollowupsAsync = ref.watch(dueFollowupsProvider);
    final dueFollowups = dueFollowupsAsync.valueOrNull;
    final followupsSettled =
        dueFollowupsAsync.hasValue || dueFollowupsAsync.hasError;
    final showFollowupCard = dueFollowups != null && dueFollowups.isNotEmpty;
    final hasActiveChildFollowup = profile != null &&
        dueFollowups != null &&
        dueFollowups.any((f) => f.childId == profile.id);
    final showMawqifCard = followupsSettled && !hasActiveChildFollowup;
    final largeText = MediaQuery.textScalerOf(context).scale(10) > 13;
    final stripOnHills = horizon != null && !largeText;

    final rawName = profile?.name.trim() ?? '';
    final hasCustomName = rawName.isNotEmpty && !isDefaultChildName(rawName);
    final headerTitle = hasCustomName
        ? l10n.childWeeklyHomeTitle(rawName)
        : l10n.childWeeklyHomeTitleNoName;
    final childNameForCards = profile?.name ?? l10n.childFallbackName;
    final isFirstWeek = profile != null && _isFirstWeek(ref, profile, now);
    final needsBirthMonthNudge =
        profile != null &&
        (profile.birthMonth == null || profile.birthMonth!.trim().isEmpty);
    final showFridayBanner =
        now.weekday == DateTime.friday &&
        week != null &&
        (week.lanterns > 0 || week.acts.isNotEmpty);
    final lang = Localizations.localeOf(context).languageCode;

    final sectionGap = largeText ? 8.0 : 14.0;
    final fallbackGreeting = Row(
      children: [
        const NoorPresence(size: 48),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            l10n.greetingPeace,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: colors.textSecondary,
            ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );

    final handoverTile = profile == null
        ? null
        : _ChildCornerHandoverTile(
            key: const ValueKey('today_child_corner_handover'),
            title: l10n.todayChildCornerHandoverTitle(childNameForCards),
            subtitle: l10n.todayChildCornerHandoverSubtitle,
            ctaLabel: l10n.todayMissionOpen,
            onTap: () {
              unawaited(Analytics.todayBlockTapped('mission', 'child_mode'));
              Navigator.of(context).push(
                AppRoutes.handoverGate(
                  childId: profile.id,
                  childName: profile.name,
                  ageGroup: profile.ageGroup,
                  surface: 'mission',
                ),
              );
            },
          );

    return RefreshIndicator(
      onRefresh: () => _refresh(ref, profile, lang),
      child: ListView(
        padding: EdgeInsets.fromLTRB(
          16,
          largeText ? 8 : 12,
          16,
          28,
        ),
        children: [
          if (!largeText && noorOn) ...[
            SkyBand(
              now: now,
              ramadan: inRamadan,
              season: season,
              footer: stripOnHills ? HorizonStrip(gate: horizon) : null,
              child: NoorTodayHeader(fallback: fallbackGreeting),
            ),
            SizedBox(height: sectionGap),
          ] else if (!largeText && horizon != null) ...[
            HorizonStrip(gate: horizon),
            SizedBox(height: sectionGap),
          ],
          _WeeklyChildHeader(
            key: const ValueKey('child_weekly_home_header'),
            title: headerTitle,
            isFirstWeek: isFirstWeek,
            firstWeekLabel: l10n.childWeeklyFirstWeekBadge,
            compact: largeText,
          ),
          SizedBox(height: sectionGap),

          // Station 1: Today's focus + single reflection slot + collapsible weekly plan.
          TodayFocusCard(
            key: focusCardKey,
            bundle: bundle,
            ageGroup: ageGroup,
            onStartFirstPath: () => onGoToTab(RootTab.learn),
          ),
          if (showFollowupCard) ...[
            const SizedBox(height: 12),
            TodayFollowupCard(activeChildId: profile?.id),
          ],
          if (profile != null && showMawqifCard) ...[
            const SizedBox(height: 12),
            TodayMawqifCard(
              childId: profile.id,
              childName: childNameForCards,
              ageGroup: ageGroup,
            ),
          ],
          if (profile != null)
            TodayWeeklyPlanCard(
              childId: profile.id,
              childName: childNameForCards,
              ageGroup: ageGroup,
              initiallyExpanded: false,
              summaryCollapsed: true,
            ),

          // Station 2: Shared family time (mission, puzzles, Safe Child Corner).
          const SizedBox(height: 22),
          if (profile != null && kMissionBands.contains(ageGroup)) ...[
            TodaySectionHeader(
              icon: BrandIcon.lantern,
              title: hasCustomName
                  ? l10n.todayFamilyTimeTitle(rawName)
                  : l10n.todayFamilyTimeTitleNoName,
            ),
            TodayMissionRow(
              childId: profile.id,
              childName: childNameForCards,
              ageGroup: ageGroup,
            ),
            const TodayFamilyPuzzlesCard(
              key: ValueKey('today_family_puzzles_card'),
            ),
            const SizedBox(height: 12),
            ChildDayCard(
              whenEmpty: handoverTile,
              whenNoMission: handoverTile,
              onOpened: () =>
                  unawaited(Analytics.todayBlockTapped('mission', 'open_day')),
            ),
          ] else
            TodayChildBlock(profile: profile),

          // Station 3: Noor assistant, week lanterns, and seasonal programs.
          const SizedBox(height: 22),
          TodayAskBlock(
            childName: hasCustomName ? rawName : null,
            onAsk: () => onGoToTab(RootTab.assistant),
          ),
          if (showFridayBanner) ...[
            const SizedBox(height: 12),
            _FridayHarvestBanner(
              key: const ValueKey('friday_harvest_banner'),
              title: l10n.fridayHarvestBannerTitle,
              subtitle: l10n.fridayHarvestBannerSubtitle(week.lanterns),
              onTap: () => showFridayHarvest(context, week),
            ),
          ],
          if (profile != null) ...[
            const SizedBox(height: 12),
            const WeekLanternString(),
          ],
          const SizedBox(height: 12),
          const ShabanWelcomeCard(),
          const ProgramsHomeCard(),

          // Quiet footer: optional system cards, daily rituals, child journey.
          const UpdateAvailableCard(),
          const WhatsNewCard(),
          if (needsBirthMonthNudge) ...[
            const SizedBox(height: 12),
            _BirthMonthNudge(
              label: l10n.childWeeklyBirthMonthNudge,
              onTap: () => Navigator.of(context).push(
                AppRoutes.editChild(
                  ChildProfile(
                    id: profile.id,
                    name: profile.name,
                    ageGroup: profile.ageGroup,
                    avatarEmoji: profile.avatarEmoji,
                    birthMonth: profile.birthMonth,
                    serverKnowsBirthMonth: true,
                  ),
                ),
              ),
            ),
          ],
          const SizedBox(height: 18),
          TodayRitualsRow(ageGroup: ageGroup),
          const SizedBox(height: 14),
          const ChildJourneyCard(),
          const SizedBox(height: 16),
          PrideInviteCard(streakDays: bundle?.dailyLoginStreak ?? 0),
          const HomeCommunityNote(),
        ],
      ),
    );
  }
}

class _ChildCornerHandoverTile extends StatelessWidget {
  const _ChildCornerHandoverTile({
    super.key,
    required this.title,
    required this.subtitle,
    required this.ctaLabel,
    required this.onTap,
  });

  final String title;
  final String subtitle;
  final String ctaLabel;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Material(
      color: colors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(Dt.rCard),
        side: BorderSide(color: colors.track),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: colors.primary.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(Dt.rButton),
                  ),
                  child: Icon(
                    Icons.phonelink_lock_outlined,
                    size: 20,
                    color: colors.primary,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          color: colors.ink,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: colors.textSecondary,
                          height: 1.4,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Align(
              alignment: AlignmentDirectional.centerEnd,
              child: FilledButton.tonalIcon(
                onPressed: onTap,
                icon: const Icon(Icons.explore_outlined, size: 18),
                label: Text(ctaLabel),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _WeeklyChildHeader extends StatelessWidget {
  const _WeeklyChildHeader({
    super.key,
    required this.title,
    required this.isFirstWeek,
    required this.firstWeekLabel,
    required this.compact,
  });

  final String title;
  final bool isFirstWeek;
  final String firstWeekLabel;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Container(
      width: double.infinity,
      padding: EdgeInsets.symmetric(
        horizontal: 14,
        vertical: compact ? 8 : 12,
      ),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(Dt.rCard),
        border: Border.all(
          color: colors.primary.withValues(alpha: 0.16),
        ),
        boxShadow: Dt.cardShadow,
      ),
      child: Wrap(
        spacing: 8,
        runSpacing: 6,
        crossAxisAlignment: WrapCrossAlignment.center,
        alignment: WrapAlignment.spaceBetween,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              BrandGlyph(
                BrandIcon.lantern,
                size: compact ? 18 : 22,
                color: colors.primary,
              ),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: colors.ink,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
          if (isFirstWeek)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: colors.primary.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(999),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  BrandGlyph(
                    BrandIcon.sprig,
                    size: 14,
                    color: colors.primaryDeep,
                  ),
                  const SizedBox(width: 5),
                  Text(
                    firstWeekLabel,
                    style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      color: colors.primaryDeep,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _BirthMonthNudge extends StatelessWidget {
  const _BirthMonthNudge({
    required this.label,
    required this.onTap,
  });

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Material(
      color: colors.surfaceAlt,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        key: const ValueKey('child_birth_month_nudge'),
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          child: Row(
            children: [
              BrandGlyph(BrandIcon.sun, size: 18, color: colors.primary),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  label,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: colors.inkSoft,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              Icon(
                Icons.chevron_right_rounded,
                size: 18,
                color: colors.textSecondary,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _FridayHarvestBanner extends StatelessWidget {
  const _FridayHarvestBanner({
    super.key,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Material(
      color: colors.surface,
      borderRadius: BorderRadius.circular(Dt.rCard),
      child: InkWell(
        borderRadius: BorderRadius.circular(Dt.rCard),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: colors.accent.withValues(alpha: 0.14),
            borderRadius: BorderRadius.circular(Dt.rCard),
            border: Border.all(color: colors.accent.withValues(alpha: 0.45)),
          ),
          child: Row(
            children: [
              BrandGlyph(
                BrandIcon.lantern,
                size: 26,
                color: colors.accentDeep,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        color: colors.ink,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: colors.inkSoft,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.chevron_right_rounded,
                size: 20,
                color: colors.accentDeep,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
