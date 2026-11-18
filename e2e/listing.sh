#!/usr/bin/env bash
# The store-listing shots, on the emulator that reactivecircus/android-emulator-runner
# booted for job `listing` of .github/workflows/mobile-e2e.yml.
#
#   E2E_APKS  dir with head/ (app.apk, l10n/app_{ar,en}.arb, ref.txt)
#   E2E_OUT   dir for everything uploaded as the e2e-listing artifact
#
# One pass per language, each on its own fresh install of the PR head:
#   <lang>_onboard  fresh/01_onboarding.yaml in that language — the child is
#                   created under $CHILD_NAME (built into the CI APK), so the
#                   install is test traffic to production like every other
#                   lineage (mobile-e2e.yml, "Test traffic in PRODUCTION")
#   <lang>          listing/shoot.yaml — adds the listing child, photographs
#                   the seven app screens of the Play page, asks the marked
#                   question first and the app's own suggested one for the
#                   picture (the flow's header explains each choice)
# screens/listing__<lang>__<slot>.png is what docs/brand/store/listing_*/
# manifest.json points at (docs/brand/tools/store_listing.py frames them).
#
# The job is NOT part of the delivery gate — the journeys are the gate — but
# it is not silent either: a pass that fails, or a slot left without its
# picture, turns this job red. A listing built from half a set, or from a
# picture shot.yaml refused, is how the 2.0.0 page came to show a test name.
#
# The status bar is put in SystemUI's demo mode for the pictures: full signal,
# no notification icons (the emulator's «Connect to open Wi-Fi network» and
# «Serial console enabled» otherwise sit in every capture). The clock keeps
# the device's own time, so it agrees with the greeting on Today.
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
E2E="$ROOT/e2e"
FLOWS="$E2E/flows"
APKS="${E2E_APKS:?set E2E_APKS}"
OUT="${E2E_OUT:?set E2E_OUT}"
PKG=com.alsaba.almorabbi
CHILD_NAME="${E2E_CHILD_NAME:-E2E-Maestro}"
QUESTION="${E2E_QUESTION:-E2E test how can I teach my child to be honest}"
export MAESTRO_CLI_NO_ANALYTICS=1 MAESTRO_CLI_ANALYSIS_NOTIFICATION_DISABLED=true

mkdir -p "$OUT/logcat" "$OUT/maestro" "$OUT/screens" "$OUT/device" "$OUT/listing"
: > "$OUT/results.tsv"
RUN_START_UTC=$(date -u '+%Y-%m-%d %H:%M:%S')
FAILED=0

say() { echo "[listing] $*"; }
mark() { adb shell log -t E2E "$*" >/dev/null 2>&1 || true; }   # flow boundaries in logcat

# ── device ───────────────────────────────────────────────────────────────
adb wait-for-device
adb shell svc power stayon true || true
adb shell settings put system screen_off_timeout 1800000 || true
adb shell input keyevent 82 || true
adb shell settings put global hide_error_dialogs 1 || true
adb shell setprop debug.firebase.analytics.app "$PKG" || true
adb shell getprop ro.build.version.release > "$OUT/device/android_version.txt" || true
adb shell getprop ro.product.model > "$OUT/device/model.txt" || true

adb logcat -G 16M >/dev/null 2>&1 || true
adb logcat -c || true
adb logcat -v threadtime > "$OUT/logcat/logcat.txt" 2>&1 &
LOGCAT_PID=$!

demo() { adb shell am broadcast -a com.android.systemui.demo "$@" >/dev/null 2>&1 || true; }
demo_on() {
  adb shell settings put global sysui_demo_allowed 1 >/dev/null 2>&1 || true
  demo -e command enter
  # Demo mode freezes the clock where it stood; give it the device's own time.
  demo -e command clock -e hhmm "$(adb shell date +%H%M 2>/dev/null | tr -d '\r')"
  demo -e command notifications -e visible false
  demo -e command network -e wifi show -e level 4 -e fully true
  demo -e command network -e mobile show -e datatype none -e level 4 -e fully true
  demo -e command battery -e level 100 -e plugged false
}
demo_off() { demo -e command exit; }
trap 'demo_off; kill "$LOGCAT_PID" 2>/dev/null || true' EXIT

l10n_for() {
  if ! python3 "$E2E/e2e_tool.py" l10n --arb-dir "$APKS/$1/l10n" --out "$FLOWS/common/l10n.js"; then
    echo "::error::selector generation failed for $1"
    FAILED=1
    return 1
  fi
}

run_flow() {  # name file [extra maestro args...] — every flow here counts
  local name=$1 file=$2 dir start rc
  shift 2
  dir="$OUT/maestro/listing/$name"
  mkdir -p "$dir"
  echo "::group::Listing / $name"
  mark "BEGIN listing/$name"
  start=$(date +%s)
  maestro test --format junit --output "$dir/report.xml" --test-output-dir "$dir" \
    -e CHILD_NAME="$CHILD_NAME" -e QUESTION="$QUESTION" "$@" "$FLOWS/$file"
  rc=$?
  mark "END listing/$name rc=$rc"
  printf '%s\t%s\t%s\t%s\t%s\n' listing "$name" "$rc" "$(( $(date +%s) - start ))" "" >> "$OUT/results.tsv"
  find "$dir" -path '*takeScreenshot*' -name '*.png' | while read -r png; do
    cp "$png" "$OUT/screens/listing__${name}__$(basename "$png")"
  done
  if [ -n "$(find "$dir" -path '*takeScreenshot*' -name '*retry*.png' -print -quit)" ]; then
    echo "::warning title=Listing $name::passed only after a retry — see the *retry* screenshot in e2e-listing"
  fi
  echo "::endgroup::"
  if [ "$rc" -ne 0 ]; then
    FAILED=1
    echo "::error title=Listing $name::failed (rc=$rc) — see the e2e-listing artifact"
  fi
  return "$rc"
}

skip() { printf '%s\t%s\tskip\t0\t%s\n' listing "$1" "${2:-}" >> "$OUT/results.tsv"; }

install_fresh() {  # variant
  adb uninstall "$PKG" >/dev/null 2>&1 || true
  if ! adb install "$APKS/$1/app.apk"; then
    echo "::error::adb install of the $1 APK failed"
    FAILED=1
    return 1
  fi
}

lpass() {  # lang
  if install_fresh head \
     && run_flow "${1}_onboard" fresh/01_onboarding.yaml -e UI_LANG="$1"; then
    demo_on
    run_flow "$1" listing/shoot.yaml -e UI_LANG="$1" || true
    demo_off
  else
    skip "$1" "install/onboarding failed"
  fi
}

if l10n_for head; then
  lpass ar
  lpass en
else
  for f in ar_onboard ar en_onboard en; do skip "$f" "head selector generation failed"; done
fi

# ── every slot has its picture, in both languages ────────────────────────
if ! python3 "$E2E/e2e_tool.py" listing-check "$OUT/screens" --out "$OUT/listing/listing-summary.md"; then
  FAILED=1
fi

# ── logcat gate ──────────────────────────────────────────────────────────
# Adding a second child and starting a new conversation are steps no journey
# takes; a crash on them would otherwise be seen by nobody.
sleep 3
kill "$LOGCAT_PID" 2>/dev/null || true
wait "$LOGCAT_PID" 2>/dev/null || true
if ! python3 "$E2E/e2e_tool.py" logcat-gate "$OUT/logcat/logcat.txt" \
     --package "$PKG" --allowlist "$E2E/logcat_allowlist.txt" --out "$OUT/logcat/gate.txt"; then
  echo "::error title=Listing logcat gate::crash, ANR or Flutter error in logcat — see logcat/gate.txt"
  FAILED=1
fi

{
  echo "- head: \`$(cat "$APKS/head/ref.txt" 2>/dev/null)\`"
  echo "- device: $(cat "$OUT/device/model.txt" 2>/dev/null), Android $(cat "$OUT/device/android_version.txt" 2>/dev/null)"
  echo "- test traffic: child \`$CHILD_NAME\` (one per pass, plus the listing child on the same install), question \`$QUESTION\` then the app's suggested question, UTC window $RUN_START_UTC → $(date -u '+%Y-%m-%d %H:%M:%S')"
  echo "- $(sed -n 3p "$OUT/listing/listing-summary.md" 2>/dev/null || echo 'listing check: not reached')"
} > "$OUT/meta.md"
python3 "$E2E/e2e_tool.py" summary "$OUT" --title "Store-listing shots" --artifact e2e-listing || true
exit "$FAILED"
