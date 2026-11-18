"""The store-listing lineage: the runner with fake device/CLI boundaries, the
slot check, and what the flow may and may not put in a picture. No builds."""
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tempfile
import unittest

import yaml

E2E = Path(__file__).resolve().parent
ROOT = E2E.parent
sys.path.insert(0, str(E2E))
import e2e_tool as t  # noqa: E402

FLOW = E2E / 'flows/listing/shoot.yaml'
SHOT = E2E / 'flows/listing/shot.yaml'
PNG = b'\x89PNG\r\n\x1a\n' + b'\0' * 30_000


class ListingRunnerTest(unittest.TestCase):
    def run_listing(self, fail_flow='', fail_l10n=False, fail_check=False, fail_gate=False):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            (root / 'e2e').mkdir()
            shutil.copy(E2E / 'listing.sh', root / 'e2e/listing.sh')
            bins = root / 'bin'
            bins.mkdir()
            scripts = {
                'adb': '#!/bin/bash\necho "$*" >> "$ADB_LOG"\nexit 0\n',
                'maestro': '''#!/bin/bash
out=''; flow=''; lang=''
while [ $# -gt 0 ]; do
  [ "$1" = --test-output-dir ] && out=$2
  [[ "$1" == UI_LANG=* ]] && lang=${1#UI_LANG=}
  flow=$1; shift
done
echo "maestro $(basename "$out") $lang $(basename "$flow")" >> "$ADB_LOG"
[[ "$out" != *"/$FAIL_FLOW" || -z "$FAIL_FLOW" ]]
''',
                'python3': '''#!/bin/bash
if [[ "$2" == l10n && "$FAIL_L10N" == 1 ]]; then exit 1; fi
if [[ "$2" == listing-check && "$FAIL_CHECK" == 1 ]]; then exit 1; fi
if [[ "$2" == logcat-gate && "$FAIL_GATE" == 1 ]]; then exit 1; fi
exit 0
''',
                'sleep': '#!/bin/bash\nexit 0\n',
            }
            for name, script in scripts.items():
                p = bins / name
                p.write_text(script)
                p.chmod(0o755)
            env = dict(os.environ, PATH=f'{bins}:{os.environ["PATH"]}',
                       E2E_APKS=str(root / 'apks'), E2E_OUT=str(root / 'out'),
                       ADB_LOG=str(root / 'adb.log'), FAIL_FLOW=fail_flow,
                       FAIL_L10N=str(int(fail_l10n)), FAIL_CHECK=str(int(fail_check)),
                       FAIL_GATE=str(int(fail_gate)))
            proc = subprocess.run(['bash', str(root / 'e2e/listing.sh')], env=env,
                                  capture_output=True, text=True, timeout=15)
            rows = {}
            for line in (root / 'out/results.tsv').read_text().splitlines():
                lineage, name, rc, _seconds, reason = line.split('\t')
                self.assertEqual(lineage, 'listing')
                rows[name] = (rc, reason)
            log = (root / 'adb.log').read_text().splitlines()
            return proc.returncode, rows, proc.stdout + proc.stderr, log

    def test_two_passes_each_on_its_own_fresh_install(self):
        rc, rows, output, log = self.run_listing()
        self.assertEqual(rc, 0, output)
        self.assertEqual(rows, {name: ('0', '') for name in ('ar_onboard', 'ar', 'en_onboard', 'en')})
        flows = [l for l in log if l.startswith('maestro ')]
        # The onboarding runs in the pass's own language: no language switch
        # to get wrong before the first picture.
        self.assertEqual(flows, ['maestro ar_onboard ar 01_onboarding.yaml', 'maestro ar ar shoot.yaml',
                                 'maestro en_onboard en 01_onboarding.yaml', 'maestro en en shoot.yaml'])
        installs = [i for i, l in enumerate(log) if l.startswith('install ')]
        self.assertEqual(len(installs), 2)
        self.assertLess(installs[0], log.index(flows[0]))
        self.assertLess(log.index(flows[1]), installs[1])

    def test_a_failed_shoot_turns_the_job_red_and_the_other_language_still_runs(self):
        rc, rows, output, _ = self.run_listing(fail_flow='ar')
        self.assertEqual(rc, 1)
        self.assertEqual(rows['ar'], ('1', ''))
        self.assertEqual(rows['en'], ('0', ''))
        self.assertIn('::error title=Listing ar::failed', output)

    def test_a_failed_onboarding_skips_only_that_pass(self):
        rc, rows, _, log = self.run_listing(fail_flow='en_onboard')
        self.assertEqual(rc, 1)
        self.assertEqual(rows['en'], ('skip', 'install/onboarding failed'))
        self.assertEqual(rows['ar'], ('0', ''))
        self.assertNotIn('maestro en en shoot.yaml', log)

    def test_no_selectors_no_pictures(self):
        rc, rows, _, log = self.run_listing(fail_l10n=True)
        self.assertEqual(rc, 1)
        self.assertEqual({r[0] for r in rows.values()}, {'skip'})
        self.assertFalse([l for l in log if l.startswith('maestro ')])

    def test_a_slot_without_its_picture_is_red_even_when_every_flow_passed(self):
        rc, _, _, _ = self.run_listing(fail_check=True)
        self.assertEqual(rc, 1)

    def test_a_crash_while_photographing_is_red(self):
        rc, _, output, _ = self.run_listing(fail_gate=True)
        self.assertEqual(rc, 1)
        self.assertIn('::error title=Listing logcat gate::', output)

    def test_the_status_bar_is_in_demo_mode_for_the_shoot_only(self):
        _, _, _, log = self.run_listing()
        demo = 'shell am broadcast -a com.android.systemui.demo -e command '
        for lang in ('ar', 'en'):
            onboard = log.index(f'maestro {lang}_onboard {lang} 01_onboarding.yaml')
            shoot = log.index(f'maestro {lang} {lang} shoot.yaml')
            between = log[onboard:shoot]
            self.assertIn(demo + 'enter', between)
            self.assertIn(demo + 'notifications -e visible false', between)
            self.assertTrue(any(l.startswith(demo + 'exit') for l in log[shoot:]), lang)
        # The clock is the device's own (the greeting on Today reads it too).
        self.assertTrue(any(l.startswith(demo + 'clock -e hhmm') for l in log))
        self.assertIn('shell date +%H%M', log)

    def test_the_install_is_marked_like_every_other_lineage(self):
        marker = re.compile(r'^CHILD_NAME="\$\{E2E_CHILD_NAME:-([^}]+)\}"$', re.M)
        mine = marker.search((E2E / 'listing.sh').read_text()).group(1)
        self.assertEqual(mine, marker.search((E2E / 'run.sh').read_text()).group(1))
        question = re.compile(r'^QUESTION="\$\{E2E_QUESTION:-([^}]+)\}"$', re.M)
        self.assertEqual(question.search((E2E / 'listing.sh').read_text()).group(1),
                         question.search((E2E / 'run.sh').read_text()).group(1))


class ListingCheckTest(unittest.TestCase):
    def fill(self, screens, skip=()):
        for lang in t.LISTING_LANGS:
            for shot in t.LISTING_SHOTS:
                if (lang, shot) not in skip:
                    (screens / f'listing__{lang}__{shot}.png').write_bytes(PNG)

    def run_check(self, screens, out=None):
        argv = [sys.executable, str(E2E / 'e2e_tool.py'), 'listing-check', str(screens)]
        return subprocess.run(argv + (['--out', str(out)] if out else []), capture_output=True, text=True)

    def test_a_complete_set_passes(self):
        with tempfile.TemporaryDirectory() as tmp:
            screens = Path(tmp)
            self.fill(screens)
            # Checkpoints of the onboarding flow sit in the same folder.
            (screens / 'listing__ar_onboard__today_after_onboarding.png').write_bytes(PNG)
            proc = self.run_check(screens, screens / 'out/listing-summary.md')
            self.assertEqual(proc.returncode, 0, proc.stdout)
            self.assertIn('14 of 14 taken', (screens / 'out/listing-summary.md').read_text())
            self.assertEqual(t.listing_missing(screens), [])

    def test_one_missing_slot_fails_and_is_named(self):
        with tempfile.TemporaryDirectory() as tmp:
            screens = Path(tmp)
            self.fill(screens, skip={('en', 'assistant')})
            proc = self.run_check(screens)
            self.assertEqual(proc.returncode, 1)
            self.assertIn('13 of 14 taken', proc.stdout)
            self.assertIn('::error title=Store-listing shots::', proc.stdout)
            self.assertEqual(t.listing_missing(screens), ['en/assistant'])

    def test_a_blank_or_truncated_capture_is_not_a_picture(self):
        with tempfile.TemporaryDirectory() as tmp:
            screens = Path(tmp)
            self.fill(screens)
            (screens / 'listing__ar__today.png').write_bytes(PNG[:200])
            (screens / 'listing__ar__assistant.png').write_bytes(b'x' * 40_000)
            self.assertEqual(t.listing_missing(screens), ['ar/today', 'ar/assistant'])

    def test_no_folder_at_all_is_every_slot_missing(self):
        self.assertEqual(len(t.listing_missing(Path('/nonexistent/screens'))),
                         len(t.LISTING_LANGS) * len(t.LISTING_SHOTS))


def _walk(node, found):
    """Every command of a flow, nested runFlow/repeat commands included."""
    if isinstance(node, list):
        for item in node:
            _walk(item, found)
    elif isinstance(node, dict):
        found.append(node)
        for value in node.values():
            _walk(value, found)
    return found


class ListingFlowTest(unittest.TestCase):
    """What the Play page showed for 2.0.0 and must not show again: a test
    name, a Latin name in the Arabic set, an English answer in the Arabic set."""

    @classmethod
    def setUpClass(cls):
        cls.text = FLOW.read_text(encoding='utf-8')
        cls.config, cls.steps = list(yaml.safe_load_all(cls.text))
        cls.commands = _walk(cls.steps, [])
        cls.shot_text = SHOT.read_text(encoding='utf-8')
        cls.shot_steps = list(yaml.safe_load_all(cls.shot_text))[-1]

    def shots(self):
        return [c['runFlow']['env']['SHOT'] for c in self.commands
                if isinstance(c.get('runFlow'), dict) and c['runFlow'].get('file') == 'shot.yaml']

    def test_the_slots_are_the_tools_and_each_is_taken_once(self):
        self.assertEqual(tuple(self.shots()), t.LISTING_SHOTS)

    def test_every_picture_goes_through_the_guard(self):
        self.assertFalse([c for c in self.commands if 'takeScreenshot' in c],
                         'shoot.yaml takes no screenshot of its own — shot.yaml does')
        takes = [i for i, s in enumerate(self.shot_steps) if isinstance(s, dict) and 'takeScreenshot' in s]
        self.assertEqual(len(takes), 1)
        self.assertEqual(self.shot_steps[takes[0]]['takeScreenshot'], '${SHOT}')
        refused = [s['assertNotVisible'] for s in self.shot_steps[:takes[0]]
                   if isinstance(s, dict) and 'assertNotVisible' in s]
        self.assertIn('(?s).*(?:${CHILD_NAME}|E2E test).*', refused)

    def test_the_listing_child_has_a_real_name_in_each_script(self):
        from_backend = (ROOT / 'backend/app/core/real_traffic.py').read_text(encoding='utf-8')
        marker = re.search(r'^E2E_CHILD_NAME_LIKE = "([^"%]+)%"$', from_backend, re.M).group(1)
        env = self.config['env']
        ar, en = env['LISTING_CHILD_AR'], env['LISTING_CHILD_EN']
        self.assertRegex(ar, r'^[ء-ي]{2,12}$')
        self.assertRegex(en, r'^[A-Z][a-z]{1,11}$')
        for name in (ar, en):
            self.assertFalse(name.startswith(marker))
            self.assertNotIn('E2E', name)
        self.assertIn("UI_LANG == 'en' ? LISTING_CHILD_EN : LISTING_CHILD_AR", self.text)
        typed = [c['inputText'] for c in self.commands if 'inputText' in c]
        # Two things are typed: the child's name, then the marked question.
        self.assertEqual(typed, ['${output.listingChild}', '${QUESTION}'])

    def test_the_typed_name_is_proven_on_screen_before_the_child_is_saved(self):
        order = [next(iter(s)) + ':' + json.dumps(s, ensure_ascii=False) for s in self.steps if isinstance(s, dict)]
        typed = next(i for i, s in enumerate(order) if s.startswith('inputText:') and 'listingChild' in s)
        proof = order[typed + 1]
        self.assertTrue(proof.startswith('extendedWaitUntil:'), proof)
        self.assertIn('"visible": "${output.listingChild}"', proof)
        self.assertNotIn('optional', proof)
        save = next(i for i, s in enumerate(order) if s == 'tapOn:' + json.dumps({'tapOn': '${output.t.add}'}))
        self.assertLess(typed + 1, save)

    def test_the_marked_question_is_asked_first_and_never_photographed(self):
        flat = [json.dumps(s, ensure_ascii=False) for s in self.steps]
        marked = next(i for i, s in enumerate(flat) if '"inputText": "${QUESTION}"' in s)
        new_chat = next(i for i, s in enumerate(flat) if s == json.dumps({'tapOn': '${output.t.chatNewConversation}'}))
        suggested = next(i for i, s in enumerate(flat) if s == json.dumps({'tapOn': '${output.t.chatQ_prayRegular}'}))
        self.assertLess(marked, new_chat)
        self.assertLess(new_chat, suggested)
        shots = [i for i, s in enumerate(flat) if '"file": "shot.yaml"' in s]
        self.assertFalse([i for i in shots if marked < i < suggested],
                         'no picture while the marked conversation is on screen')
        self.assertEqual(sum(1 for i in shots if i > suggested), 1)
        # The assistant is the last leg: two answers from production can cost
        # no other picture.
        self.assertEqual(self.shots()[-1], 'assistant')
        self.assertGreater(marked, max(i for i in shots if i < suggested))

    def test_nothing_is_typed_for_the_question_in_the_picture(self):
        # The app's own suggestion, from the ARB of the interface's language.
        ar = json.loads((ROOT / 'mobile/lib/l10n/app_ar.arb').read_text(encoding='utf-8'))
        en = json.loads((ROOT / 'mobile/lib/l10n/app_en.arb').read_text(encoding='utf-8'))
        self.assertRegex(ar['chatQ_prayRegular'], r'[ء-ي]')
        self.assertNotRegex(ar['chatQ_prayRegular'], r'[A-Za-z]')
        self.assertNotRegex(en['chatQ_prayRegular'], r'[ء-ي]')
        # …and it is one of the three a 7-9 child's empty chat offers.
        chat = (ROOT / 'mobile/lib/screens/chat_screen.dart').read_text(encoding='utf-8')
        self.assertRegex(chat, r"'7-9': \[[^\]]*'chatQ_prayRegular'")
        self.assertIn("tapOn: '${output.t.ageGroup7to9}'", self.text)


class ListingGuardPatternsTest(unittest.TestCase):
    """shot.yaml's two language guards, on the texts they exist for. Maestro
    matches an element's whole text (java.util.regex); Python's `re` reads
    these patterns the same way."""

    @classmethod
    def setUpClass(cls):
        steps = list(yaml.safe_load_all(SHOT.read_text(encoding='utf-8')))[-1]
        guards = {}
        for s in steps:
            flow = s.get('runFlow') if isinstance(s, dict) else None
            if isinstance(flow, dict) and 'commands' in flow:
                for c in flow['commands']:
                    if 'assertNotVisible' in c:
                        # PyYAML reads the `true:` key of Maestro's `when` as a boolean.
                        guards[flow['when'][True]] = re.compile(c['assertNotVisible'])
        cls.arabic_set = next(v for k, v in guards.items() if "UI_LANG != 'en'" in k)
        cls.english_set = next(v for k, v in guards.items() if "UI_LANG == 'en'" in k)
        cls.english_when = next(k for k in guards if "UI_LANG == 'en'" in k)

    def test_an_english_paragraph_is_refused_in_the_arabic_set(self):
        # ar/phone_08_assistant.png of listing_2.0.0, as Play showed it.
        answer = ("specialist's assessment, as it may signal deeper stress rather than a standalone behavior.\n"
                  'العادات والمهارات الحياتية')
        self.assertTrue(self.arabic_set.fullmatch(answer))
        self.assertTrue(self.arabic_set.fullmatch(
            'To teach a 7–9-year-old honesty, the most effective lever is making truth-telling feel safer than hiding'))

    def test_arabic_with_a_latin_word_or_name_is_fine(self):
        for text in ('خطة سلمى هذا الأسبوع', 'مقال تنموي\nCDC, Positive Parenting Tips for Preschoolers (3-5 years)',
                     'كيف أعوّد طفلي على الصلاة بانتظام؟', 'Android System notification: Connect to open Wi‑Fi network',
                     'Battery charging, 100 percent.', 'درب Salma'):
            self.assertIsNone(self.arabic_set.fullmatch(text), text)

    def test_an_arabic_sentence_is_refused_in_the_english_set(self):
        self.assertTrue(self.english_set.fullmatch("Today's tip\nطفلك يتململ في الصلاة؟ هذا طبيعي في عمره. صلّ أمامه واجعله يعدّ الركعات"))
        self.assertTrue(self.english_set.fullmatch('خطة هذا الأسبوع لسلمى جاهزة أدناه: تحدٍّ واحد وثلاث خطوات صغيرة.'))

    def test_english_with_an_arabic_word_or_letter_is_fine(self):
        for text in ("Salma's road", 'العربية', 'أ', 'Seeds of Aqeedah: The First Introduction to Allah',
                     'Say «بسم الله» before eating', 'Begin with بسم الله الرحمن الرحيم, then eat'):
            self.assertIsNone(self.english_set.fullmatch(text), text)

    def test_only_the_assistant_may_quote_arabic_in_the_english_set(self):
        self.assertIn("LISTING_QUOTES != 'true'", self.english_when)
        flow = FLOW.read_text(encoding='utf-8')
        self.assertEqual(flow.count('LISTING_QUOTES'), 1)
        tail = flow.split('LISTING_QUOTES', 1)[0].rsplit('- runFlow:', 1)[1]
        self.assertIn('SHOT: assistant', tail)


if __name__ == '__main__':
    unittest.main()
