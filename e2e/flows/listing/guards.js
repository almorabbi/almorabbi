// What a picture on the Play page must never carry — one definition for
// shot.yaml, which refuses the capture, and for shoot.yaml, which asks the
// assistant another question rather than photograph such an answer.
// docs/brand/store/listing_2.0.0 carried the first two on the store itself.
// Runs after common/l10n.js (runScript). Reads UI_LANG and CHILD_NAME.
//
// Maestro matches an element's WHOLE text (java.util.regex), hence the
// leading (?s).* … .* on every pattern.
var arabicSet = UI_LANG != 'en'

// The run's test marker: the onboarding child's name (built into the CI APK
// so production can leave the install out of its reports) or the marked
// question. The pictures show the listing child, so a marker on screen means
// the wrong child is active or the wrong conversation is open.
output.listingMarker = '(?s).*(?:' + CHILD_NAME + '|E2E test).*'

// «هذا التوجيه عام — من الأفضل مراجعة مختص» over an answer (safety_banner.dart,
// set by the server for a domain and severity — guardrails/policies.v1.yaml).
// Honest in the app; on the store it reads as a health notice, and the listing
// was rejected once for looking like a health app (2026-06-28).
output.listingBanner = output.c.safetyGeneralGuidance

// The other language as running text. A name or the basmala is fine; a
// sentence is not.
//   Arabic set: 80 Latin characters in a row (letters, spaces, punctuation) —
//     the English answer of ar/phone_08 — or a Latin word inside an Arabic
//     text: «درب Salma», «لـE2E-Maestro», «أن يرى الصلاة happening أمامه».
//   English set: 30 Arabic characters in a row. shot.yaml lifts this one rule
//     for the assistant (LISTING_QUOTES), whose answer may quote an ayah.
var latin = "[A-Za-z][A-Za-z ,.;:!?\\x27\\x22()—–-]{79,}"
var arabicLetter = '[ء-ي]'
output.listingOtherLanguage = arabicSet
  ? '(?s)(?:.*' + latin + '.*|.*' + arabicLetter + '.*[A-Za-z]{3,}.*|.*[A-Za-z]{3,}.*' + arabicLetter + '.*)'
  : '(?s).*' + arabicLetter + '[ء-يً-ْ ،؛؟.:!«»()\\x27\\x22—–-]{29,}.*'

// An answer shoot.yaml will not photograph: it asks the next suggestion.
output.listingBadAnswer = arabicSet
  ? '(?:' + output.listingBanner + '|' + output.listingOtherLanguage + ')'
  : output.listingBanner
