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
ASK = E2E / 'flows/listing/ask.yaml'
ASK_AGAIN = E2E / 'flows/listing/ask_again.yaml'
GUARDS = E2E / 'flows/listing/guards.js'
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

    def test_the_photographed_bar_is_built_after_the_wifi_icon_was_first_shown(self):
        # Shown for the first time inside the bar that gets photographed, the
        # Wi-Fi icon is there twice (the Arabic pass of two runs).
        _, _, _, log = self.run_listing()
        demo = 'shell am broadcast -a com.android.systemui.demo -e command '
        wifi = demo + 'network -e wifi show -e level 4 -e fully true'
        for lang in ('ar', 'en'):
            onboard = log.index(f'maestro {lang}_onboard {lang} 01_onboarding.yaml')
            shoot = log.index(f'maestro {lang} {lang} shoot.yaml')
            bar = [l[len(demo):] for l in log[onboard:shoot] if l.startswith(demo)]
            self.assertEqual(bar[:4], ['enter', wifi[len(demo):], 'exit', 'enter'], lang)
            # ... and that second bar is the one still up when the shoot starts.
            self.assertNotIn('exit', bar[4:], lang)
            self.assertIn(wifi[len(demo):], bar[4:], lang)
            self.assertIn('network -e mobile hide', bar[4:], lang)

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


def _flow_file(step):
    flow = step.get('runFlow') if isinstance(step, dict) else None
    return flow.get('file') if isinstance(flow, dict) else None


class ListingFlowTest(unittest.TestCase):
    """What the Play page showed for 2.0.0 and must not show again: a test
    name, a Latin name in the Arabic set, an English answer in the Arabic set."""

    @classmethod
    def setUpClass(cls):
        cls.text = FLOW.read_text(encoding='utf-8')
        cls.config, cls.steps = list(yaml.safe_load_all(cls.text))
        cls.commands = _walk(cls.steps, [])
        cls.shot_steps = list(yaml.safe_load_all(SHOT.read_text(encoding='utf-8')))[-1]
        cls.ask_steps = list(yaml.safe_load_all(ASK.read_text(encoding='utf-8')))[-1]
        cls.again_steps = list(yaml.safe_load_all(ASK_AGAIN.read_text(encoding='utf-8')))[-1]
        cls.flat = [json.dumps(s, ensure_ascii=False) for s in cls.steps]

    def shots(self):
        return [s['runFlow']['env']['SHOT'] for s in self.steps if _flow_file(s) == 'shot.yaml']

    def index(self, step):
        return self.flat.index(json.dumps(step, ensure_ascii=False))

    def test_the_slots_are_the_tools_and_each_is_taken_once(self):
        self.assertEqual(tuple(self.shots()), t.LISTING_SHOTS)

    def test_every_picture_goes_through_the_guard(self):
        for name, steps in (('shoot.yaml', self.steps), ('ask.yaml', self.ask_steps),
                            ('ask_again.yaml', self.again_steps)):
            self.assertFalse([c for c in _walk(steps, []) if 'takeScreenshot' in c],
                             f'{name} takes no screenshot of its own — shot.yaml does')
        takes = [i for i, s in enumerate(self.shot_steps) if isinstance(s, dict) and 'takeScreenshot' in s]
        self.assertEqual(len(takes), 1)
        self.assertEqual(takes[0], len(self.shot_steps) - 1, 'nothing after the capture')
        self.assertEqual(self.shot_steps[-1]['takeScreenshot'], '${SHOT}')
        refused = [c['assertNotVisible'] for c in _walk(self.shot_steps, []) if 'assertNotVisible' in c]
        for guard in ('${output.listingMarker}', '${output.listingBanner}', '${output.listingOtherLanguage}'):
            self.assertIn(guard, refused)
        # The guards are defined before anything is photographed.
        scripts = [s['runScript'] for s in self.steps if isinstance(s, dict) and 'runScript' in s]
        self.assertEqual(scripts, ['../common/l10n.js', 'guards.js'])
        self.assertLess(self.index({'runScript': 'guards.js'}), self.flat.index(
            next(f for f in self.flat if '"file": "shot.yaml"' in f)))

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
        # Two things are typed here: the child's name, then the marked
        # question. ask.yaml types the question for the picture.
        self.assertEqual(typed, ['${output.listingChild}', '${QUESTION}'])
        for steps in (self.ask_steps, self.again_steps):
            self.assertEqual([c['inputText'] for c in _walk(steps, []) if 'inputText' in c], ['${ASK}'])

    def test_the_typed_name_is_proven_on_screen_before_the_child_is_saved(self):
        typed = self.index({'inputText': '${output.listingChild}'})
        proof = self.steps[typed + 1]['extendedWaitUntil']
        self.assertEqual(proof['visible'], '${output.listingChild}')
        self.assertNotIn('optional', proof)
        self.assertEqual(self.steps[typed + 2], {'tapOn': '${output.t.add}'})

    def test_the_child_is_given_an_age_and_a_birth_month_before_the_keyboard_opens(self):
        # 7-9 for the whole calendar year: January, eight years back. Nothing
        # on Today or the road then asks the family for a birth month.
        self.assertIn("output.listingBirthYear = '' + (new Date().getFullYear() - 8)", self.text)
        order = [self.index({'tapOn': '${output.t.ageGroup7to9}'}),
                 self.index({'tapOn': '${output.t.birthMonthChoose}'}),
                 self.index({'tapOn': '${output.listingBirthYear}'}),
                 self.index({'tapOn': '${output.t.lit_monthJanuary}'}),
                 self.index({'tapOn': '${output.t.save}'}),
                 self.index({'inputText': '${output.listingChild}'})]
        self.assertEqual(order, sorted(order))
        saved = self.steps[self.index({'tapOn': '${output.t.save}'}) + 1]['extendedWaitUntil']
        self.assertEqual(saved['visible'], '${output.t.birthMonthChange}')
        self.assertNotIn('optional', saved)

    def test_the_lantern_picture_is_taken_on_the_road_not_on_today(self):
        """Today's own lantern row sits between the tip of the day (server
        text, different every day) and the count of families (known to
        overcount), and Today is too short to scroll either away."""
        lanterns = next(i for i, s in enumerate(self.steps)
                        if _flow_file(s) == 'shot.yaml' and s['runFlow']['env']['SHOT'] == 'week_lanterns')
        road = next(i for i, s in enumerate(self.steps)
                    if _flow_file(s) == 'shot.yaml' and s['runFlow']['env']['SHOT'] == 'family_road')
        between = self.steps[road + 1:lanterns]
        # Nothing leaves the road between the two pictures…
        self.assertFalse([s for s in between if s == 'back' or 'runFlow' in (s if isinstance(s, dict) else {})])
        self.assertIn({'tapOn': '${output.c.familyRoadThisWeek}'}, between)
        # …and the sheet is up, or there is no picture.
        sheet = between[-1]['extendedWaitUntil']
        self.assertEqual(sheet['visible'], '${output.c.weekActsTitle}')
        self.assertNotIn('optional', sheet)
        # Today's lantern row is not what is photographed any more.
        self.assertNotIn('weekLanternsTitle', self.text)

    def test_the_marked_question_is_asked_first_and_never_photographed(self):
        marked = self.index({'inputText': '${QUESTION}'})
        asks = [i for i, s in enumerate(self.steps) if _flow_file(s) == 'ask.yaml']
        shots = [i for i, s in enumerate(self.steps) if _flow_file(s) == 'shot.yaml']
        self.assertEqual(len(asks), 3)
        self.assertLess(marked, asks[0])
        self.assertFalse([i for i in shots if marked < i < asks[-1]],
                         'no picture while the marked conversation can be on screen')
        # Only the English pass's second question stands between the last
        # of them and the one picture taken here.
        self.assertEqual(_flow_file(self.steps[asks[-1] + 1]), 'ask_again.yaml')
        self.assertEqual([i for i in shots if i > marked], [asks[-1] + 2])
        # The assistant is the last leg: answers from production can cost no
        # other picture.
        self.assertEqual(self.shots()[-1], 'assistant')
        self.assertGreater(marked, max(i for i in shots if i < asks[0]))
        # Every question for the picture opens a NEW conversation and checks
        # the marked one has left the screen before it sends anything.
        self.assertEqual(self.ask_steps[0], {'tapOn': '${output.t.chatNewConversation}'})
        gone = self.ask_steps.index({'assertNotVisible': '(?s).*E2E test.*'})
        self.assertLess(gone, self.ask_steps.index({'inputText': '${ASK}'}))

    def questions(self):
        env = self.config['env']
        return {lang: [env[f'LISTING_ASK_{lang.upper()}_{n}'] for n in (1, 2, 3)] for lang in ('ar', 'en')}

    def test_another_question_is_asked_only_instead_of_a_bad_answer(self):
        asks = [s['runFlow'] for s in self.steps if _flow_file(s) == 'ask.yaml']
        self.assertNotIn('when', asks[0])
        for flow in asks[1:]:
            self.assertEqual(flow['when'], {'visible': '${output.listingBadAnswer}'})
        for n, flow in enumerate(asks, 1):
            self.assertEqual(flow['env'], {'ASK': "${UI_LANG == 'en' ? LISTING_ASK_EN_%d : LISTING_ASK_AR_%d}" % (n, n)})
        questions = self.questions()
        self.assertEqual(len(set(questions['ar'] + questions['en'])), 6)
        # Each in its set's script, start to end: the answer follows it.
        for q in questions['ar']:
            self.assertRegex(q, r'^[ء-يً-ْ0-9 ،؟]+$')
        for q in questions['en']:
            self.assertRegex(q, r"^[A-Za-z0-9 ,?'-]+$")
        for q in questions['ar'] + questions['en']:
            self.assertNotIn('E2E', q)
        # ask.yaml ends with the question on screen and no keyboard: it leaves
        # the tab and returns, scrolls up to the question, and insists on it.
        tail = self.ask_steps[self.ask_steps.index({'runFlow': '../common/home.yaml'}):]
        self.assertEqual(tail[1], {'tapOn': '${output.lead.navAssistant}'})
        self.assertEqual(tail[-1], {'extendedWaitUntil': {'visible': '${output.listingAsked}', 'timeout': 10000}})

    def test_the_english_conversation_holds_two_questions_and_the_arabic_one(self):
        """The header counts the questions with a string that has no singular:
        «1 سؤال» reads right, "1 questions" (the 2.0.0 page) does not."""
        arb = {lang: json.loads((ROOT / f'mobile/lib/l10n/app_{lang}.arb').read_text(encoding='utf-8'))
               for lang in ('ar', 'en')}
        self.assertEqual((arb['ar']['chatTurnsCount'], arb['en']['chatTurnsCount']),
                         ('{count} سؤال', '{count} questions'),
                         'the count has a plural form now: one question is enough in both sets — drop ask_again.yaml')
        self.assertIn('chatTurnsCount(state.turnCount)',
                      (ROOT / 'mobile/lib/screens/chat_screen.dart').read_text(encoding='utf-8'))
        again = [s['runFlow'] for s in self.steps if _flow_file(s) == 'ask_again.yaml']
        self.assertEqual(len(again), 1)
        # English only, and only under an answer fit for a picture: a bad one
        # is left for shot.yaml to refuse by name.
        self.assertEqual(again[0]['when'], {True: "${UI_LANG == 'en'}", 'notVisible': '${output.listingBadAnswer}'})
        self.assertEqual(again[0]['env'], {'ASK': '${LISTING_ASK_EN_AGAIN}'})
        question = self.config['env']['LISTING_ASK_EN_AGAIN']
        self.assertRegex(question, r"^[A-Za-z0-9 ,?'-]+$")
        self.assertNotIn(question, self.questions()['en'])
        # Same conversation, and the picture is still the first question:
        # nothing here starts a new one or re-points the pattern scrolled to.
        flat = json.dumps(self.again_steps, ensure_ascii=False)
        self.assertNotIn('chatNewConversation', flat)
        self.assertFalse([c for c in _walk(self.again_steps, []) if 'evalScript' in c])
        tail = self.again_steps[self.again_steps.index({'runFlow': '../common/home.yaml'}):]
        self.assertEqual(tail[1], {'tapOn': '${output.lead.navAssistant}'})
        self.assertEqual(tail[2]['scrollUntilVisible']['element'], {'text': '${output.listingAsked}'})
        self.assertEqual(tail[2]['scrollUntilVisible']['direction'], 'UP')
        self.assertEqual(tail[-1], {'extendedWaitUntil': {'visible': '${output.listingAsked}', 'timeout': 10000}})

    def test_the_questions_are_filed_under_the_one_domain_without_the_banner(self):
        """The app sends every question at «متوسط» (its only severity), and at
        that severity the server puts the review banner over an answer in
        every knowledge domain but «cyber» (guardrails/policies.v1.yaml). The
        server's keyword list — not a model — must file these six there, or
        the banner is a matter of luck."""
        enums = (ROOT / 'mobile/lib/models/enums.dart').read_text(encoding='utf-8')
        self.assertIn('static const Severity defaultValue = Severity.moderate;', enums)
        self.assertIn("moderate('متوسط')", enums)
        mobile = ROOT / 'mobile/lib'
        setters = [p.name for p in mobile.rglob('*.dart')
                   if 'setSeverity(' in p.read_text(encoding='utf-8') and p.name != 'chat_notifier.dart']
        self.assertEqual(setters, [], 'the parent now chooses a severity: revisit which domains draw the banner')
        policies = yaml.safe_load((ROOT / 'backend/guardrails/policies.v1.yaml').read_text(encoding='utf-8'))
        banner = {}
        for domain, policy in policies['domains'].items():
            override = (policy.get('severity_overrides') or {}).get('متوسط', {})
            banner[domain] = override.get('require_human_review',
                                          policy.get('default_policy', {}).get('require_human_review', False))
        self.assertFalse(banner['cyber'])
        for domain in ('fiqh', 'medical', 'development', 'aqeedah'):
            self.assertTrue(banner[domain], domain)
        # The classifier, as the server runs it. Its module imports two HTTP
        # clients it never uses on the keyword path: stand-ins keep this
        # runnable on the E2E job's bare runner.
        probe = (
            'import json, sys, types\n'
            'class _Any:\n'
            '    def __init__(self, *a, **k): pass\n'
            '    def __call__(self, *a, **k): return _Any()\n'
            '    def __getattr__(self, name): return _Any()\n'
            'for name in ("httpx", "requests"):\n'
            '    try:\n'
            '        __import__(name)\n'
            '    except ImportError:\n'
            '        m = types.ModuleType(name); m.__getattr__ = lambda attr: _Any; sys.modules[name] = m\n'
            'sys.path.insert(0, sys.argv[1])\n'
            'from app.services import domain_classifier as dc\n'
            'print(json.dumps([dc._keyword_fast_path(q) for q in json.loads(sys.argv[2])]))\n'
        )
        questions = self.questions()
        every = questions['ar'] + questions['en']
        proc = subprocess.run([sys.executable, '-c', probe, str(ROOT / 'backend'), json.dumps(every)],
                              capture_output=True, text=True, timeout=60)
        self.assertEqual(proc.returncode, 0, proc.stderr[-800:])
        for question, domains in zip(every, json.loads(proc.stdout)):
            self.assertEqual(domains, ['cyber'], question)

    def test_only_the_assistant_may_quote_arabic_in_the_english_set(self):
        allowed = [s['runFlow']['env']['SHOT'] for s in self.steps
                   if _flow_file(s) == 'shot.yaml' and s['runFlow']['env'].get('LISTING_QUOTES') == 'true']
        self.assertEqual(allowed, ['assistant'])
        when = next(c['runFlow']['when'][True] for c in self.shot_steps
                    if isinstance(c.get('runFlow'), dict) and 'commands' in c['runFlow']
                    and c['runFlow']['commands'][0].get('assertNotVisible') == '${output.listingOtherLanguage}')
        # Lifted for the English set only: the Arabic set is always checked.
        self.assertEqual(when, "${UI_LANG != 'en' || typeof LISTING_QUOTES === 'undefined' || LISTING_QUOTES != 'true'}")


@unittest.skipUnless(shutil.which('node'), 'guards.js is evaluated with node (present on the CI runner)')
class ListingGuardPatternsTest(unittest.TestCase):
    """guards.js itself, run as Maestro runs it (after l10n.js, with UI_LANG and
    CHILD_NAME), on the texts it exists for. Maestro matches an element's whole
    text with java.util.regex; Python's `re` reads these patterns the same way
    once the inline (?s) is given as a flag."""

    @classmethod
    def setUpClass(cls):
        ar = json.loads((ROOT / 'mobile/lib/l10n/app_ar.arb').read_text(encoding='utf-8'))
        en = json.loads((ROOT / 'mobile/lib/l10n/app_en.arb').read_text(encoding='utf-8'))
        maps, _ = t.build_l10n(ar, en)
        cls.guards = {lang: cls.evaluate(lang, maps) for lang in ('ar', 'en')}

    @staticmethod
    def evaluate(lang, maps):
        script = ('var UI_LANG = %s, CHILD_NAME = "E2E-Maestro"; var output = %s;\n%s\n'
                  'console.log(JSON.stringify(output));'
                  % (json.dumps(lang), json.dumps({'c': maps['c'], 't': maps['t']}),
                     GUARDS.read_text(encoding='utf-8')))
        out = subprocess.run(['node', '-e', script], capture_output=True, text=True, check=True).stdout
        found = json.loads(out)
        return {k: re.compile(v.replace('(?s)', ''), re.S) for k, v in found.items() if k.startswith('listing')}

    def test_the_marker_is_refused_in_both_sets(self):
        for lang in ('ar', 'en'):
            marker = self.guards[lang]['listingMarker']
            for text in ('خطة هذا الأسبوع لـE2E-Maestro جاهزة', "This week's plan for E2E-Maestro", 'E2E-Maestro',
                         'E2E test how can I teach my child to be honest'):
                self.assertTrue(marker.fullmatch(text), text)
            for text in ('خطة سلمى هذا الأسبوع', "Salma's road", 'سلمى', 'Salma'):
                self.assertIsNone(marker.fullmatch(text), text)

    def test_the_review_banner_is_refused_in_both_sets(self):
        for lang, text in (('ar', 'هذا التوجيه عام — من الأفضل مراجعة مختص بشري.'),
                           ('en', 'This guidance is general — It is best to consult a human specialist.')):
            self.assertTrue(self.guards[lang]['listingBanner'].fullmatch(text))
            self.assertTrue(self.guards[lang]['listingBadAnswer'].fullmatch(text))
        self.assertIsNone(self.guards['ar']['listingBanner'].fullmatch('تعويد طفلك على الصلاة بانتظام'))

    def test_an_english_paragraph_is_refused_in_the_arabic_set(self):
        other = self.guards['ar']['listingOtherLanguage']
        # ar/phone_08_assistant.png of listing_2.0.0, as Play showed it.
        self.assertTrue(other.fullmatch(
            "specialist's assessment, as it may signal deeper stress rather than a standalone behavior."))
        self.assertTrue(other.fullmatch(
            'To teach a 7–9-year-old honesty, the most effective lever is making truth-telling feel safer than hiding'))

    def test_a_latin_word_inside_arabic_text_is_refused_in_the_arabic_set(self):
        other, bad = self.guards['ar']['listingOtherLanguage'], self.guards['ar']['listingBadAnswer']
        # listing_2.0.0's ar/phone_02 and phone_01, and the first answer job
        # `listing` ever photographed (run 44283403696).
        for text in ('درب Salma', 'مواعيد Salma القادمة', 'خطة هذا الأسبوع لـE2E-Maestro جاهزة',
                     'فطفلك في السابعة إلى التاسعة يحتاج أن يرى الصلاة happening أمامه كل يوم'):
            self.assertTrue(other.fullmatch(text), text)
            self.assertTrue(bad.fullmatch(text), text)

    def test_arabic_and_the_system_bar_are_fine_in_the_arabic_set(self):
        other = self.guards['ar']['listingOtherLanguage']
        for text in ('خطة سلمى هذا الأسبوع', 'كيف أعوّد طفلي على الصلاة بانتظام؟', 'رمضان بعد 82 يومًا', '3G',
                     'في «تزكية الأخلاق: الصدق والرحمة والمسؤولية (7-9 سنوات)»: أتممتم 1 من 4',
                     'Android System notification: Connect to open Wi‑Fi network', 'Battery charging, 100 percent.',
                     'Wifi signal full.', '10:29'):
            self.assertIsNone(other.fullmatch(text), text)

    def test_an_arabic_sentence_is_refused_in_the_english_set(self):
        other = self.guards['en']['listingOtherLanguage']
        self.assertTrue(other.fullmatch("Today's tip\nطفلك يتململ في الصلاة؟ هذا طبيعي في عمره. صلّ أمامه واجعله يعدّ الركعات"))
        self.assertTrue(other.fullmatch('خطة هذا الأسبوع لسلمى جاهزة أدناه: تحدٍّ واحد وثلاث خطوات صغيرة.'))

    def test_english_with_an_arabic_word_or_letter_is_fine(self):
        other = self.guards['en']['listingOtherLanguage']
        for text in ("Salma's road", 'العربية', 'أ', 'Seeds of Aqeedah: The First Introduction to Allah',
                     'Say «بسم الله» before eating', 'Begin with بسم الله الرحمن الرحيم, then eat'):
            self.assertIsNone(other.fullmatch(text), text)

    def test_an_english_answer_is_retried_for_the_banner_only(self):
        bad = self.guards['en']['listingBadAnswer']
        self.assertIsNone(bad.fullmatch('Abu Hurayrah narrated: «مروا أولادكم بالصلاة وهم أبناء سبع سنين» — begin at seven.'))
        self.assertTrue(bad.fullmatch('This guidance is general — It is best to consult a human specialist.'))


if __name__ == '__main__':
    unittest.main()
