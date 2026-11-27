# Next Mobile Release Backlog

Tracked items deferred to the next planned Play release (no standalone Play release triggered solely for these).

## 1. Age Band `2-3` Display Labels & Under-2 Gate by Months (`#fb_b796ab75`, 2026-11-27)

Context: Parents of children aged 12–23 months (`birth_month` → `2-3` curriculum band per `band_for_age_months`) saw labels reading «2–3 سنوات» / «2-3 years» and had `screen_off` offered in the mobile handover gate. Backend under-2 enforcement by `age_months < 24` and the 7 `path_2-3_*` path titles ship in the backend PR; the following mobile changes ship in the next mobile release:

- **ARB labels (all locales under `mobile/lib/l10n/`):**
  - Update `ageGroup2to3` and `age2to3` (AR: `1–3 سنوات` / `١–٣ سنوات`, EN: `1–3 years`, and any additional locales) so the 12–23 month year is explicitly covered by the label while keeping wire value `'2-3'` unchanged.
- **Mobile child-surface gate (`mobile/lib/features/handover/child_surface_policy.dart` & callers):**
  - Extend `childSurfaceBand(String? profileAgeGroup, {int? ageMonths})` (and `childSurfaceAllowed`, `handoverSurfacesFor`, `childCornerActivitiesFor`, `childCornerOffered`, `childCornerOpeningSurface`, plus callers reading `activeChildProfileProvider.birthMonth`) so that whenever `birthMonth` is known and `ageMonths < 24`, the surface band is **always `'under-2'`** regardless of `profileAgeGroup`.
  - Add unit tests in `mobile/test/child_surface_policy_test.dart` covering `('2-3', ageMonths: 16) == 'under-2'`, `('4-6', ageMonths: 23) == 'under-2'`, `('2-3', ageMonths: 24) == '2-3'`, and `('2-3', ageMonths: null) == '2-3'`.
- **Editorial note (separate decision, no edits yet):** 19 of the 35 `lesson_2-3_*` lessons mention age 2–3 explicitly or assume post-age-2 screen time / 24-month milestones; tracked for review before any lesson-copy edits.
