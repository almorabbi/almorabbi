/// Child-centric Home screen variant (`child_home_v2` / 1.2 milestone).
///
/// Centres the Today tab around the active child's week:
/// 1. Sky / Noor greeting (omitted when text scale > 130% to protect the fold).
/// 2. Child weekly header (`child_weekly_home_header`) with first-week badge.
/// 3. [TodayFocusCard] immediately below the header so its primary CTA fits
///    above the fold on 360x800 even at 200% text scaling.
/// 4. Memory follow-up, Mawaqif decision, Weekly Plan (expanded in week 1),
///    Today Mission row, optional birth-month nudge, and Friday harvest banner.
/// 5. Week lantern string, Child block, Ask block, Programs card, and the
///    remaining secondary cards under [TodayMoreDivider].
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

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
import '../../coins/coins_providers.dart';
import '../../companion/providers/companion_providers.dart';
import '../../companion/widgets/noor_presence.dart';
import '../../companion/widgets/noor_today_header.dart';
import '../../family_road/providers/family_road_providers.dart';
import '../../family_road/widgets/horizon_strip.dart';
import '../../journey/widgets/child_journey_card.dart';
import '../../lanterns/providers/lantern_providers.dart';
import '../../lanterns/widgets/friday_harvest.dart';
import '../../lanterns/widgets/week_lantern_string.dart';
import '../../mawaqif/widgets/today_mawqif_card.dart';
import '../../missions/today_mission_row.dart';
import '../../onboarding/providers/onboarding_providers.dart';
import '../../program/data/progress_models.dart';
import '../../program/providers/program_providers.dart';
import '../../program/providers/progress_providers.dart';
import '../../programs/data/programs_models.dart';
import '../../programs/providers/programs_providers.dart';
import '../../programs/widgets/programs_home_card.dart';
import '../../referral/pride_invite_card.dart';
import '../../shell/root_tab.dart';
import '../../whats_new/widgets/update_available_card.dart';
import '../../whats_new/widgets/whats_new_card.dart';
import '../experiment/child_home_experiment.dart';
import 'daily_gift_moment.dart';
import 'home_community_note.dart';
import 'home_shortcuts_grid.dart';
import 'home_stats_row.dart';
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
    final gift = ref.watch(dailyGiftProvider).valueOrNull;
    final noorOn = ref.watch(noorHeaderEnabledProvider);
    final inRamadan =
        ref.watch(programsOverviewProvider).valueOrNull?.ramadan.state ==
        RamadanState.ramadan;
    final season = ref.watch(skySeasonProvider);
    final horizon = ref.watch(horizonStripGateProvider);
    final now = ref.watch(clockProvider)();
    final week = ref.watch(familyWeekProvider).valueOrNull;
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
          TodayFocusCard(
            key: focusCardKey,
            bundle: bundle,
            ageGroup: ageGroup,
            onStartFirstPath: () => onGoToTab(RootTab.learn),
          ),
          if (gift != null && gift > 0) ...[
            const SizedBox(height: 12),
            DailyGiftMoment(gift: gift),
          ],
          const SizedBox(height: 12),
          TodayFollowupCard(activeChildId: profile?.id),
          if (profile != null) ...[
            const SizedBox(height: 12),
            TodayMawqifCard(
              childId: profile.id,
              childName: childNameForCards,
              ageGroup: ageGroup,
            ),
            const SizedBox(height: 12),
            TodayWeeklyPlanCard(
              childId: profile.id,
              childName: childNameForCards,
              ageGroup: ageGroup,
              initiallyExpanded: isFirstWeek,
            ),
            const SizedBox(height: 12),
            TodayMissionRow(
              childId: profile.id,
              childName: childNameForCards,
              ageGroup: ageGroup,
            ),
          ],
          if (needsBirthMonthNudge) ...[
            const SizedBox(height: 10),
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
            const SizedBox(height: 12),
            TodayChildBlock(profile: profile),
          ],
          const SizedBox(height: 12),
          TodayAskBlock(
            childName: hasCustomName ? rawName : null,
            onAsk: () => onGoToTab(RootTab.assistant),
          ),
          const SizedBox(height: 14),
          const ProgramsHomeCard(),
          const SizedBox(height: 18),
          TodayMoreDivider(label: l10n.todayMoreTitle),
          const UpdateAvailableCard(),
          const WhatsNewCard(),
          TodayRitualsRow(ageGroup: ageGroup),
          const SizedBox(height: 16),
          HomeStatsRow(bundle: bundle),
          const SizedBox(height: 16),
          const HomeShortcutsGrid(),
          const SizedBox(height: 20),
          const ChildJourneyCard(),
          const SizedBox(height: 20),
          PrideInviteCard(streakDays: bundle?.dailyLoginStreak ?? 0),
          const HomeCommunityNote(),
        ],
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
