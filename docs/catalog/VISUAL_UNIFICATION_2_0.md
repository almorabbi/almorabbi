# Visual Unification 2.0 (`visual_unification_v2`)

Specifying the three visual decisions resolved before lifting «المربّي الذكي» toward `2.0.0`:

## 1. System Dark Mode & Surface Discipline
- `ThemeModeNotifier` defaults to `ThemeMode.system` (`mobile/lib/features/onboarding/providers/onboarding_providers.dart`).
- All widget surfaces use semantic `context.colors` (`AppPalette.light` / `AppPalette.dark`) rather than literal `Colors.white` or light hex fills.
- **Automated Regression Guard**: `mobile/test/design_system_contrast_test.dart` runs `scanLightSurfaces()` from `mobile/tool/audit_light_surfaces.dart` inside every `flutter test` invocation and fails immediately if any unannotated light ground enters `mobile/lib/`. All WCAG AA text contrast pairs (>= 4.5:1) and non-text icon pairs (>= 3:1) are verified in both palettes.

## 2. Unified Paper-Cut `BrandGlyph` Iconography
- `DomainStyle` in `mobile/lib/theme/design_tokens.dart` (`kVisualUnificationVersion = 'visual_unification_v2'`) replaces vendor-dependent emoji strings with canonical `BrandIcon` SVG assets:
  - `islamic_parenting` -> `BrandIcon.lantern`
  - `aqeedah` -> `BrandIcon.crescent`
  - `development` -> `BrandIcon.sprig`
  - `medical` -> `BrandIcon.star`
  - `cyber` -> `BrandIcon.globe`
  - `infant_pregnancy` -> `BrandIcon.sun`
  - fallback -> `BrandIcon.openBook`
- All domain hero tiles, path filters, lesson hero watermarks, `ProgramsHomeCard`, `HelpSheet`, and `ChildWeeklyHome` render `BrandGlyph` / `GlyphHero`.
- **Automated Regression Guard**: `mobile/test/brand_glyph_test.dart` strips comments and forbids raw emoji in `guardedFiles`, while `mobile/test/svg_assets_test.dart` enforces the 1-to-1 bijection between `BrandIcon` and bundled SVGs.

## 3. Story Motion Experiment Resolution (`STORY_MOTION_MODE=motion`)
- Production 30-day cohort comparison (`story_events`):
  - `motion` arm: **55.7%** story completion (`59 / 106`), **4.65 / 5** mean rating.
  - `static` arm: **46.8%** story completion (`22 / 47`), **4.55 / 5** mean rating.
- Production `/api/app-config` sets `STORY_MOTION_MODE=motion` in server `.env` (preserving `"ab"` default in code tests), while client-side `MediaQuery.disableAnimations` (`reduceMotion`) continues to automatically honour user accessibility settings with static framing.
