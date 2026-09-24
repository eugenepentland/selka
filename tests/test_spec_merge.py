#!/usr/bin/env python3
"""Pin the `SPEC.md` merge driver (`scripts/merge_spec.py`).

Three layers:

* synthetic three-way cases for every rule the driver documents;
* git end to end: a throwaway repository configured by `scripts/setup-git.sh`
  merges two appending branches cleanly, from the main tree and from a linked
  worktree, and the same repository without the setup falls back to git's
  ordinary conflict;
* a replay of the real `SPEC.md` conflicts of 2026-09-17..23: each merge
  commit's three versions go through the driver and the result is compared
  with the committed hand resolution. Merges whose commits this clone does not
  have are skipped.

Run it directly, or print the replay table:

    python3 tests/test_spec_merge.py
    python3 tests/test_spec_merge.py --replay
"""

import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'scripts'))
import merge_spec  # noqa: E402

DRIVER = ROOT / 'scripts/merge_spec.py'
SETUP = ROOT / 'scripts/setup-git.sh'

BASE = """# Spec

Intro prose.

## Alpha

- [A-1] First alpha.
- [A-2] Second alpha.

## Beta

- [B-1] First beta,
wrapped onto a second line.
- [B-2] Second beta.

Closing prose for beta.
"""


def edit(text, old, new):
    """Replace exactly one occurrence, so a typo in a case fails loudly."""
    assert text.count(old) == 1, old
    return text.replace(old, new)


def merged(base, ours, theirs):
    """Run the structured merge and require that it did not decline."""
    result = merge_spec.merge_texts(base, ours, theirs)
    assert result is not None, 'structured merge declined'
    return result


class SyntheticMerges(unittest.TestCase):
    def test_both_sides_append_to_one_section(self):
        ours = edit(BASE, '- [A-2] Second alpha.\n', '- [A-2] Second alpha.\n- [A-3] Ours.\n')
        theirs = edit(BASE, '- [A-2] Second alpha.\n', '- [A-2] Second alpha.\n- [A-4] Theirs.\n')
        text, conflicts = merged(BASE, ours, theirs)
        self.assertEqual(conflicts, 0)
        self.assertEqual(text, edit(BASE, '- [A-2] Second alpha.\n',
                                    '- [A-2] Second alpha.\n- [A-3] Ours.\n- [A-4] Theirs.\n'))

    def test_amended_bullet_beside_an_append_keeps_only_the_new_text(self):
        # The case the hand union got wrong: ours appends at the point where
        # theirs rewrote the last bullet.
        ours = edit(BASE, '- [A-2] Second alpha.\n', '- [A-2] Second alpha.\n- [A-3] Ours.\n')
        theirs = edit(BASE, '- [A-2] Second alpha.\n', '- [A-2] Second alpha, amended.\n- [A-4] Theirs.\n')
        text, conflicts = merged(BASE, ours, theirs)
        self.assertEqual(conflicts, 0)
        self.assertEqual(text.count('[A-2]'), 1)
        self.assertIn('- [A-2] Second alpha, amended.\n- [A-3] Ours.\n- [A-4] Theirs.\n', text)

    def test_amendment_on_one_side_wins_over_the_unchanged_side(self):
        theirs = edit(BASE, '- [A-1] First alpha.', '- [A-1] First alpha, amended.')
        text, conflicts = merged(BASE, BASE, theirs)
        self.assertEqual((text, conflicts), (theirs, 0))
        text, conflicts = merged(BASE, theirs, BASE)
        self.assertEqual((text, conflicts), (theirs, 0))

    def test_both_amend_one_bullet_differently_is_a_conflict(self):
        ours = edit(BASE, '- [A-1] First alpha.', '- [A-1] Ours alpha.')
        theirs = edit(BASE, '- [A-1] First alpha.', '- [A-1] Theirs alpha.')
        text, conflicts = merged(BASE, ours, theirs)
        self.assertEqual(conflicts, 1)
        self.assertIn('<<<<<<< ours\n- [A-1] Ours alpha.\n||||||| base\n- [A-1] First alpha.\n'
                      '=======\n- [A-1] Theirs alpha.\n>>>>>>> theirs\n- [A-2]', text)

    def test_both_amend_one_bullet_identically_is_clean(self):
        ours = edit(BASE, '- [A-1] First alpha.', '- [A-1] Same.')
        text, conflicts = merged(BASE, ours, ours)
        self.assertEqual((text, conflicts), (ours, 0))

    def test_deletion_on_one_side_is_kept_beside_an_append(self):
        ours = edit(BASE, '- [A-1] First alpha.\n', '')
        theirs = edit(BASE, '- [A-2] Second alpha.\n', '- [A-2] Second alpha.\n- [A-3] Theirs.\n')
        text, conflicts = merged(BASE, ours, theirs)
        self.assertEqual(conflicts, 0)
        self.assertNotIn('[A-1]', text)
        self.assertIn('## Alpha\n\n- [A-2] Second alpha.\n- [A-3] Theirs.\n\n## Beta', text)

    def test_modify_delete_is_a_conflict_that_keeps_the_text(self):
        ours = edit(BASE, '- [A-1] First alpha.\n', '')
        theirs = edit(BASE, '- [A-1] First alpha.', '- [A-1] Amended alpha.')
        text, conflicts = merged(BASE, ours, theirs)
        self.assertEqual(conflicts, 1)
        self.assertIn('- [A-1] Amended alpha.', text)
        self.assertIn('<<<<<<< ours\n||||||| base\n- [A-1] First alpha.\n', text)

    def test_bullets_added_in_different_sections_stay_there(self):
        ours = edit(BASE, '- [A-2] Second alpha.\n', '- [A-2] Second alpha.\n- [A-3] Ours.\n')
        theirs = edit(BASE, '- [B-2] Second beta.\n', '- [B-2] Second beta.\n- [B-3] Theirs.\n')
        text, conflicts = merged(BASE, ours, theirs)
        self.assertEqual(conflicts, 0)
        self.assertIn('- [A-3] Ours.\n\n## Beta', text)
        self.assertIn('- [B-3] Theirs.\n\nClosing prose', text)

    def test_one_sided_prose_edit_merges_beside_bullet_appends(self):
        ours = edit(BASE, 'Intro prose.', 'Intro prose, edited.')
        ours = edit(ours, '- [B-2] Second beta.\n', '- [B-2] Second beta.\n- [B-3] Ours.\n')
        theirs = edit(BASE, '- [B-2] Second beta.\n', '- [B-2] Second beta.\n- [B-4] Theirs.\n')
        text, conflicts = merged(BASE, ours, theirs)
        self.assertEqual(conflicts, 0)
        self.assertIn('Intro prose, edited.', text)
        self.assertIn('- [B-3] Ours.\n- [B-4] Theirs.\n', text)

    def test_two_sided_prose_edit_is_a_conflict(self):
        ours = edit(BASE, 'Closing prose for beta.', 'Ours closing.')
        theirs = edit(BASE, 'Closing prose for beta.', 'Theirs closing.')
        text, conflicts = merged(BASE, ours, theirs)
        self.assertEqual(conflicts, 1)
        self.assertIn('<<<<<<< ours\nOurs closing.\n||||||| base\nClosing prose for beta.\n'
                      '=======\nTheirs closing.\n>>>>>>> theirs\n', text)

    def test_prose_added_beside_bullets_by_one_side_and_bullets_by_the_other_conflicts(self):
        # An untagged line is never unioned: two sides adding text at one
        # point might be two versions of one paragraph.
        ours = edit(BASE, '\n## Beta', '\nA note.\n\n## Beta')
        theirs = edit(BASE, '\n## Beta', '\n- [A-4] Theirs.\n\n## Beta')
        text, conflicts = merged(BASE, ours, theirs)
        self.assertEqual(conflicts, 1)
        self.assertIn('- [A-2] Second alpha.\n\n<<<<<<< ours\nA note.\n||||||| base\n=======\n'
                      '- [A-4] Theirs.\n>>>>>>> theirs\n\n## Beta', text)

    def test_prose_and_bullets_added_at_different_points_merge(self):
        ours = edit(BASE, '- [A-2] Second alpha.\n', '- [A-2] Second alpha.\n\nA note.\n')
        theirs = edit(BASE, '- [A-2] Second alpha.\n', '- [A-2] Second alpha.\n- [A-4] Theirs.\n')
        text, conflicts = merged(BASE, ours, theirs)
        self.assertEqual(conflicts, 0)
        self.assertIn('- [A-2] Second alpha.\n- [A-4] Theirs.\n\nA note.\n\n## Beta', text)

    def test_wrapped_bullet_amendment_replaces_every_line(self):
        ours = edit(BASE, 'wrapped onto a second line.', 'wrapped onto an amended line.')
        theirs = edit(BASE, '- [B-2] Second beta.\n', '- [B-2] Second beta.\n- [B-3] Theirs.\n')
        text, conflicts = merged(BASE, ours, theirs)
        self.assertEqual(conflicts, 0)
        self.assertIn('- [B-1] First beta,\nwrapped onto an amended line.\n- [B-2]', text)
        self.assertNotIn('a second line', text)

    def test_same_bullet_added_by_both_sides_appears_once(self):
        ours = edit(BASE, '- [A-2] Second alpha.\n', '- [A-2] Second alpha.\n- [A-3] Shared.\n- [A-4] Ours.\n')
        theirs = edit(BASE, '- [A-2] Second alpha.\n', '- [A-2] Second alpha.\n- [A-3] Shared.\n- [A-5] Theirs.\n')
        text, conflicts = merged(BASE, ours, theirs)
        self.assertEqual(conflicts, 0)
        self.assertEqual(text.count('[A-3]'), 1)
        self.assertIn('- [A-3] Shared.\n- [A-4] Ours.\n- [A-5] Theirs.\n', text)

    def test_same_tag_added_with_different_text_is_a_conflict(self):
        ours = edit(BASE, '- [A-2] Second alpha.\n', '- [A-2] Second alpha.\n- [A-3] Ours.\n')
        theirs = edit(BASE, '- [A-2] Second alpha.\n', '- [A-2] Second alpha.\n- [A-3] Theirs.\n')
        text, conflicts = merged(BASE, ours, theirs)
        self.assertEqual(conflicts, 1)
        self.assertIn('- [A-3] Ours.', text)
        self.assertIn('- [A-3] Theirs.', text)

    def test_a_moved_bullet_keeps_the_other_sides_amendment(self):
        ours = edit(BASE, '- [A-1] First alpha.\n', '')
        ours = edit(ours, '- [B-2] Second beta.\n', '- [B-2] Second beta.\n- [A-1] First alpha.\n')
        theirs = edit(BASE, '- [A-1] First alpha.', '- [A-1] Amended alpha.')
        text, conflicts = merged(BASE, ours, theirs)
        self.assertEqual(conflicts, 0)
        self.assertEqual(text.count('[A-1]'), 1)
        self.assertIn('- [B-2] Second beta.\n- [A-1] Amended alpha.\n', text)

    def test_a_repeated_tag_in_an_input_declines(self):
        ours = edit(BASE, '- [A-2] Second alpha.\n', '- [A-2] Second alpha.\n- [A-2] Again.\n')
        self.assertIsNone(merge_spec.merge_texts(BASE, ours, BASE))


def clean_env(home):
    """An environment isolated from the caller's git state and user config."""
    env = {key: value for key, value in os.environ.items() if not key.startswith('GIT_')}
    env.update({
        'HOME': str(home), 'GIT_CONFIG_NOSYSTEM': '1', 'GIT_CONFIG_GLOBAL': os.devnull,
        'GIT_AUTHOR_NAME': 'spec merge test', 'GIT_AUTHOR_EMAIL': 'test@example.invalid',
        'GIT_COMMITTER_NAME': 'spec merge test', 'GIT_COMMITTER_EMAIL': 'test@example.invalid',
    })
    return env


class DriverCommand(unittest.TestCase):
    def setUp(self):
        self.dir = Path(tempfile.mkdtemp(prefix='spec-merge-'))
        self.addCleanup(shutil.rmtree, self.dir)

    def run_driver(self, base, ours, theirs):
        paths = []
        for name, text in (('base', base), ('ours', ours), ('theirs', theirs)):
            path = self.dir / name
            path.write_text(text)
            paths.append(str(path))
        result = subprocess.run([sys.executable, str(DRIVER), *paths, 'SPEC.md', '--marker-size', '9'],
                                capture_output=True, text=True, env=clean_env(self.dir), timeout=60)
        return result.returncode, (self.dir / 'ours').read_text(), result.stderr

    def test_a_clean_merge_is_written_over_ours_and_exits_zero(self):
        ours = edit(BASE, '- [A-2] Second alpha.\n', '- [A-2] Second alpha.\n- [A-3] Ours.\n')
        theirs = edit(BASE, '- [A-2] Second alpha.\n', '- [A-2] Second alpha.\n- [A-4] Theirs.\n')
        status, text, _ = self.run_driver(BASE, ours, theirs)
        self.assertEqual(status, 0)
        self.assertIn('- [A-3] Ours.\n- [A-4] Theirs.\n', text)

    def test_a_conflict_exits_nonzero_with_the_requested_marker_size(self):
        ours = edit(BASE, '- [A-1] First alpha.', '- [A-1] Ours alpha.')
        theirs = edit(BASE, '- [A-1] First alpha.', '- [A-1] Theirs alpha.')
        status, text, stderr = self.run_driver(BASE, ours, theirs)
        self.assertEqual(status, 1)
        self.assertIn('<<<<<<<<< ours\n', text)
        self.assertIn('1 conflict', stderr)

    def test_a_declined_merge_falls_back_to_the_line_merge(self):
        ours = edit(BASE, '- [A-2] Second alpha.\n', '- [A-2] Second alpha.\n- [A-2] Again.\n- [A-3] Ours.\n')
        theirs = edit(BASE, '- [A-2] Second alpha.\n', '- [A-2] Second alpha.\n- [A-4] Theirs.\n')
        status, text, stderr = self.run_driver(BASE, ours, theirs)
        self.assertEqual(status, 1)
        self.assertIn('declined', stderr)
        self.assertIn('<<<<<<<<< ours\n- [A-2] Again.\n- [A-3] Ours.\n=========\n- [A-4] Theirs.\n', text)


class GitEndToEnd(unittest.TestCase):
    """A throwaway repository: its config is the only one these tests touch."""

    def setUp(self):
        self.dir = Path(tempfile.mkdtemp(prefix='spec-merge-git-'))
        self.addCleanup(shutil.rmtree, self.dir)
        self.env = clean_env(self.dir)
        self.repo = self.dir / 'repo'
        self.repo.mkdir()
        (self.repo / 'scripts').mkdir()
        shutil.copy(DRIVER, self.repo / 'scripts/merge_spec.py')
        shutil.copy(SETUP, self.repo / 'scripts/setup-git.sh')
        shutil.copy(ROOT / '.gitattributes', self.repo / '.gitattributes')
        (self.repo / 'SPEC.md').write_text(BASE)
        self.git('init', '-q', '-b', 'main')
        self.git('add', '.')
        self.git('commit', '-qm', 'base')
        self.git('checkout', '-qb', 'lane')
        self.write(edit(BASE, '- [A-2] Second alpha.\n', '- [A-2] Second alpha, amended.\n- [A-4] Lane.\n'))
        self.git('commit', '-qam', 'lane')
        self.git('checkout', '-q', 'main')
        self.write(edit(BASE, '- [A-2] Second alpha.\n', '- [A-2] Second alpha.\n- [A-3] Main.\n'))
        self.git('commit', '-qam', 'main')

    def git(self, *args, cwd=None, check=True):
        result = subprocess.run(['git', *args], cwd=cwd or self.repo, env=self.env,
                                capture_output=True, text=True, timeout=60)
        if check:
            self.assertEqual(result.returncode, 0, result.stderr)
        return result

    def write(self, text):
        (self.repo / 'SPEC.md').write_text(text)

    def setup_script(self, cwd):
        result = subprocess.run(['sh', 'scripts/setup-git.sh'], cwd=cwd, env=self.env,
                                capture_output=True, text=True, timeout=60)
        self.assertEqual(result.returncode, 0, result.stderr)

    def test_configured_merge_is_clean_and_keeps_only_the_amended_text(self):
        self.setup_script(self.repo)
        self.setup_script(self.repo)  # idempotent
        self.assertEqual(self.git('config', '--get-all', 'merge.spec-bullets.driver').stdout.count('\n'), 1)
        self.git('merge', '-q', '--no-edit', 'lane')
        text = (self.repo / 'SPEC.md').read_text()
        self.assertIn('- [A-2] Second alpha, amended.\n- [A-3] Main.\n- [A-4] Lane.\n', text)
        self.assertEqual(text.count('[A-2]'), 1)

    def test_a_linked_worktree_uses_the_shared_configuration(self):
        worktree = self.dir / 'wt'
        self.git('worktree', 'add', '-q', '-b', 'wt-main', str(worktree), 'main')
        self.setup_script(worktree)
        self.git('merge', '-q', '--no-edit', 'lane', cwd=worktree / 'scripts')
        text = (worktree / 'SPEC.md').read_text()
        self.assertIn('- [A-3] Main.\n- [A-4] Lane.\n', text)

    def test_without_setup_git_falls_back_to_its_line_merge(self):
        result = self.git('merge', '--no-edit', 'lane', check=False)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('CONFLICT (content): Merge conflict in SPEC.md', result.stdout)
        self.assertIn('<<<<<<< HEAD', (self.repo / 'SPEC.md').read_text())

    def test_a_tree_without_the_script_falls_back_to_merge_file(self):
        self.setup_script(self.repo)
        (self.repo / 'scripts/merge_spec.py').unlink()
        result = self.git('merge', '--no-edit', 'lane', check=False)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('<<<<<<<', (self.repo / 'SPEC.md').read_text())


# Every merge of 2026-09-17..23 whose SPEC.md conflicted under git's line
# merge, plus fix/checker-bugs (named in the request; git merged its SPEC.md
# cleanly). `identical`: the driver reproduces the committed resolution byte
# for byte. Otherwise the note says what differs and why.
REPLAY = {
    '977acf88': ('perf/lib-text-scan', 'identical'),
    '92ca76b7': ('perf/lib-sort', 'identical'),
    '21c8c63f': ('perf/root-liveness', 'identical'),
    '996a89ec': ('perf/lib-dict-hash', 'order: PY-DICT-2 stays at its base place; the hand union moved it'),
    '79835b13': ('lang/keyed-sort', 'identical'),
    '17642218': ('fix/lox-port-bugs', 'identical'),
    'b95ad5d5': ('fix/checker-bugs', 'identical'),
    '9a43eea3': ('ba857f44 into perf/loop-range-facts', 'identical'),
    '027cf1b3': ('perf/parity-integration into main', 'conflict: IO-13 amended differently on both sides'),
    'e42d48c0': ('overnight/2026-09-22 into codex', 'identical'),
    '915daf10': ('item 3 onto integration', 'identical'),
    '0560eebb': ('item 4 onto integration', 'identical'),
    'e727d8e2': ('items 5 and 6 onto integration', 'identical'),
    'e3ae1df8': ('perf/lever-search into main',
                 'conflict: INVOKE-TEXT-1 added twice with different text, and an HTML marker line '
                 'beside bullets; the hand merge also dropped 14 draft invoke bullets on purpose'),
    '0c199005': ('L2 onto L1', 'identical'),
    'd091db50': ('W10 persistent frontend cache', 'identical'),
    '5adafee3': ('eaa139c into worktree-agent-ab0f', 'identical'),
    '9456e476': ('991bdea into worktree-agent-ab0f', 'identical'),
}


def history(*args):
    """Run git against this checkout's history; None when it fails."""
    result = subprocess.run(['git', *args], cwd=ROOT, capture_output=True, text=True, timeout=60)
    return result.stdout if result.returncode == 0 else None


def replay(commit):
    """Re-merge one merge commit's SPEC.md; None when the history is absent."""
    parents = history('rev-list', '--parents', '-n1', commit)
    if parents is None:
        return None
    ours, theirs = parents.split()[1:3]
    base = history('merge-base', ours, theirs).split()[0]
    texts = [history('show', f'{rev}:SPEC.md') for rev in (base, ours, theirs, commit)]
    base_text, ours_text, theirs_text, committed = texts
    line = line_merge(base_text, ours_text, theirs_text)
    result = merge_spec.merge_texts(base_text, ours_text, theirs_text)
    text, conflicts = result if result is not None else (None, None)
    return {
        'line_conflicts': line['conflicts'],
        'line_conflict_lines': line['conflict_lines'],
        'driver_conflict_lines': conflict_lines(text or ''),
        'union_duplicates': merge_spec.parse(line['union']).duplicates,
        'driver_conflicts': conflicts,
        'identical': text == committed,
        'same_bullets': text is not None and bullets(text) == bullets(committed),
        'text': text,
        'committed': committed,
    }


def line_merge(base, ours, theirs):
    """git's own merge of three texts: its conflict count and its union."""
    with tempfile.TemporaryDirectory(prefix='spec-replay-') as directory:
        paths = []
        for name, text in (('ours', ours), ('base', base), ('theirs', theirs)):
            path = Path(directory) / name
            path.write_text(text)
            paths.append(str(path))
        plain = subprocess.run(['git', 'merge-file', '-p', '--diff3', *paths], capture_output=True, text=True)
        union = subprocess.run(['git', 'merge-file', '-p', '--union', *paths], capture_output=True, text=True)
    return {'conflicts': plain.returncode, 'conflict_lines': conflict_lines(plain.stdout), 'union': union.stdout}


def conflict_lines(text):
    """How many lines sit inside conflict markers, markers included."""
    count, inside = 0, False
    for line in text.splitlines():
        inside = inside or line.startswith('<<<<<<< ')
        count += inside
        inside = inside and not line.startswith('>>>>>>> ')
    return count


def bullets(text):
    """Tag → bullet text, ignoring order."""
    return merge_spec.parse(text).bullets


class HistoryReplay(unittest.TestCase):
    def check(self, commit):
        outcome = replay(commit)
        if outcome is None:
            self.skipTest(f'{commit} is not in this clone')
        _, note = REPLAY[commit]
        if note == 'identical':
            self.assertTrue(outcome['identical'], commit)
            self.assertEqual(outcome['driver_conflicts'], 0)
        elif note.startswith('order:'):
            self.assertFalse(outcome['identical'])
            self.assertTrue(outcome['same_bullets'], commit)
            self.assertEqual(outcome['driver_conflicts'], 0)
        else:
            self.assertGreater(outcome['driver_conflicts'], 0)
            self.assertLess(outcome['driver_conflict_lines'], outcome['line_conflict_lines'])

    def test_the_amended_bullet_merge_needs_no_hand_fix(self):
        # lang/keyed-sort amended PRELUDE-SORT-KEY-2 while the integration
        # branch appended beside it: the union repeats the tag, the driver not.
        outcome = replay('79835b13')
        if outcome is None:
            self.skipTest('79835b13 is not in this clone')
        self.assertIn('PRELUDE-SORT-KEY-2', outcome['union_duplicates'])
        self.assertTrue(outcome['identical'])

    def test_the_two_sided_amendment_is_the_only_conflict(self):
        outcome = replay('027cf1b3')
        if outcome is None:
            self.skipTest('027cf1b3 is not in this clone')
        self.assertEqual(outcome['driver_conflicts'], 1)
        resolved = resolve_conflicts_like(outcome['text'], outcome['committed'])
        self.assertEqual(resolved, outcome['committed'])


    def test_the_divergent_main_merge_differs_only_by_a_deliberate_drop(self):
        # e3ae1df8 took main's side of two parallel implementations and, with
        # their tests, removed the checkout's draft `invoke` bullets (see its
        # message). No merge rule can know that; every other bullet matches,
        # including the ten the hand resolution first lost and then restored.
        outcome = replay('e3ae1df8')
        if outcome is None:
            self.skipTest('e3ae1df8 is not in this clone')
        self.assertEqual(outcome['driver_conflicts'], 2)
        ours = bullets(resolve_conflicts_like(outcome['text'], outcome['committed']))
        committed = bullets(outcome['committed'])
        self.assertEqual({tag: text for tag, text in ours.items() if tag in committed}, committed)
        dropped = sorted(set(ours) - set(committed))
        self.assertEqual(len(dropped), 14)
        self.assertTrue(all(tag.startswith(('INVOKE-', 'WIRE-TEXT-', 'NATIVE-WIRE-')) for tag in dropped))
        for tag in ('OPTION-FLOW-1', 'GENERIC-EXPECTED-3', 'PY-DICT-2', 'SCHEMATIC-BULK-1', 'HOST-PACKED-1'):
            self.assertIn(tag, ours)


def resolve_conflicts_like(text, committed):
    """Replace each tagged conflict block with the committed bullet text."""
    reference = bullets(committed)
    out, lines, i = [], text.splitlines(keepends=True), 0
    while i < len(lines):
        if not lines[i].startswith('<<<<<<< '):
            out.append(lines[i])
            i += 1
            continue
        end = next(j for j in range(i, len(lines)) if lines[j].startswith('>>>>>>> '))
        tags = {merge_spec.TAG_RE.match(line).group(1) for line in lines[i:end] if merge_spec.TAG_RE.match(line)}
        out.extend(reference[tag] for tag in sorted(tags) if tag in reference)
        i = end + 1
    return ''.join(out)


for _commit in REPLAY:
    setattr(HistoryReplay, f'test_replay_{_commit}', lambda self, c=_commit: self.check(c))


def print_replay():
    """The replay table the audit report quotes."""
    print(f"{'merge':9} {'lane':38} {'git hunks/lines':>15} {'union dups':>18} {'driver hunks/lines':>18}  verdict")
    for commit, (lane, note) in REPLAY.items():
        outcome = replay(commit)
        if outcome is None:
            print(f'{commit:9} {lane:38} not in this clone')
            continue
        verdict = 'identical' if outcome['identical'] else note
        dups = ','.join(outcome['union_duplicates']) or '-'
        git_side = f"{outcome['line_conflicts']}/{outcome['line_conflict_lines']}"
        driver_side = f"{outcome['driver_conflicts']}/{outcome['driver_conflict_lines']}"
        print(f"{commit:9} {lane[:38]:38} {git_side:>15} {dups:>18} {driver_side:>18}  {verdict}")


if __name__ == '__main__':
    if sys.argv[1:] == ['--replay']:
        print_replay()
    else:
        unittest.main()
