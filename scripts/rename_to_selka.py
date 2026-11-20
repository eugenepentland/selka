#!/usr/bin/env python3
"""The rename program: `mylang` becomes `selka` everywhere, in one deterministic and re-runnable cut.

    python3 scripts/rename_to_selka.py                 # --report: change nothing, print the counts and what no rule covers
    python3 scripts/rename_to_selka.py --apply         # do it in the current git worktree (git mv, in-place rewrite)
    python3 scripts/rename_to_selka.py --project DIR   # cross a Selka project outside this repository
    python3 scripts/rename_to_selka.py --rules         # print the table (names, groups, what each matches and writes)

Standard library only. The table is `RULES` below: an ordered list, longer names before shorter ones, each rule
a regular expression and its replacement. A file's text goes through the rules in order; a name that must keep the
old spelling is hidden from them first (`SPANS`), a whole path that keeps it is `KEPT`, and the lines of a file that
keep it are `split_kept`. Nothing here recomputes a digest or regenerates a golden file: the text is renamed, and
`--report` lists the places where renamed text is hashed (`WATCH`) so that the cut's hand fixes are known beforehand.

Deterministic: files in sorted order, no clock, no random. Idempotent: the output of a rule is matched by no rule, so a
second `--apply` finds nothing to do and says so (the tree is then dirty with the first run's changes, which is why the
clean-tree check comes after the plan: an empty plan is accepted on any tree).

The suffix rule (`suffix-source`) is the delicate one: `.my` is two letters. It matches `.my` only when the next
character cannot continue a name (`[A-Za-z0-9_]`: that leaves `.mylang`, `.myi`, `.mypy_cache`, `.mysql` alone), is not
the start of the two real MySQL file names `.my.cnf` and `.my.ini`, and is not a call or an index (`x.my(`, `x.my[`).
`--report` prints what the unbounded patterns `\\.my` and `\\.my\\b` would have matched wrongly, with counts.

The symbol group is OFF (decision GH-D16: renaming `myl_` would make `selka_` the reserved extern prefix and refuse a
project's own `selka_*` C functions; `--with-symbols` exists only to show what the group would have done): the runtime
keeps `myl_` and `MYL_`, guest symbols keep `my.NAME`, and the debug-info producer string `mylang-core` (the one LLVM
emits and the runtime compares) is protected from the catch-all rule where it stands as the producer. Every other
`mylang-core`, the prefix of the compiler's own output lines and the old executable's name in prose, is renamed with the rest.

A file that names the old spelling on purpose after the cut (the hints, their tests) keeps it: a line that holds the words
`rename: keep` is hidden from every rule, and a file whose first eight lines hold `rename: keep-file` is not rewritten at all.
Neither mark exists on a tree that predates the cut, so they change nothing there, and a second `--apply` on the finished
branch finds nothing to do.

`.gitignore` keeps every line that a rule would change and adds the new spelling beside it (a worktree that crosses the
cut still holds its old work directory, and it must stay ignored); comment lines are rewritten in place.
"""
from __future__ import annotations

import argparse
import fnmatch
import os
import re
import subprocess
import sys
import zlib
from collections import Counter, defaultdict
from dataclasses import dataclass, field, replace
from pathlib import Path
from typing import Callable, Iterable, Optional

# The first lines of the newest entries of CHANGES.md that keep the old names: nothing at or below the first of them found
# (from the top of the file) is rewritten, because those entries describe the compiler that existed. The first is the entry
# that announces the rename, which names the old spellings on purpose and is on the cut branch only; the second is the newest
# entry on the commit the cut starts from (main 027de883ec, 19 November 2026), which a branch that predates the cut has.
# Change them with --changes-kept-from (once or more: it replaces both).
CHANGES_KEPT_FROM = (
    "### The language is called `selka` now: the command, the suffixes, the project file, the variables and the directories "
    "(lane GH-5.3, 19 November 2026)",
    "### The product's names live in `src/product.zig`, and the code that computes with them reads them there "
    "(lane GH-5.1, 19 November 2026)",
)

NAME = r"(?![A-Za-z0-9_])"  # the next character cannot continue a name


def _case(match: re.Match) -> str:
    word = match.group(0)
    if word.isupper():
        return "SELKA"
    return "Selka" if word[0].isupper() else "selka"


@dataclass(frozen=True)
class Rule:
    name: str
    group: str  # "core", or "symbols" (off unless --with-symbols)
    pattern: re.Pattern
    repl: object  # a string with backreferences, or a function of the match
    what: str
    project: bool = False  # also part of `--project`
    only: tuple = ()  # when not empty: only for paths that start with one of these
    exclude: tuple = ()  # never for paths that start with one of these

    def applies(self, path: str) -> bool:
        return (not self.only or path.startswith(self.only)) and not path.startswith(self.exclude)


def _rule(name: str, group: str, pattern: str, repl: object, what: str, flags: int = 0, project: bool = False,
          only: tuple = (), exclude: tuple = ()) -> Rule:
    return Rule(name, group, re.compile(pattern, flags), repl, what, project, only, exclude)


_FLAG_NAMES = {
    "shard-plan": "--test-shard-plan",
    "shard": "--test-shard",
    "test-filter": "--test-filter",
    "test-list": "--test-list",
    # `--guardian-filter=` only names the filter a build forwarded; `--test-filter=` is the runtime filter. The runner
    # tells them apart by prefix, so they must not become one spelling.
    "filter": "--test-announce-filter",
    "*": "--test-*",
}

# The table. Order is the rule: a longer or more specific name goes before the shorter one it contains.
RULES: tuple[Rule, ...] = (
    _rule("zon-fingerprint", "core", r"(?<=\.fingerprint = 0x)%08x([0-9a-f]{8})" % zlib.crc32(b"mylang"),
          lambda m: "%08x%s" % (zlib.crc32(b"selka"), m.group(1)),
          "build.zig.zon's package fingerprint: the high half is the CRC-32 of the name `mylang`; it becomes the CRC-32 of "
          "`selka` and the random low half stays", only=("build.zig.zon",)),
    _rule("runner-flags", "core", r"--guardian-(shard-plan|shard|test-filter|test-list|filter|\*)(?![A-Za-z0-9_-])",
          lambda m: _FLAG_NAMES[m.group(1)],
          "--guardian-shard[-plan], --guardian-test-filter, --guardian-test-list, --guardian-filter -> --test-shard[-plan], "
          "--test-filter, --test-list, --test-announce-filter"),
    _rule("runner-lines", "core", r"guardian/test:", "test:", "the runner's output prefix `guardian/test:` -> `test:`"),
    _rule("runner-env", "core", r"GUARDIAN_TEST_", "SELKA_TEST_", "GUARDIAN_TEST_* -> SELKA_TEST_*"),
    _rule("suffix-interface", "core", r"\.myi" + NAME, ".selkai", "`.myi` (a module interface) -> `.selkai`", project=True),
    _rule("suffix-source", "core", r"\.my" + NAME + r"(?!\.(?:cnf|ini)\b)(?![(\[])", ".selka",
          "`.my` as a source suffix: not before [A-Za-z0-9_], not `.my.cnf`/`.my.ini`, not `.my(` or `.my[` -> `.selka`",
          project=True),
    _rule("project-file", "core", r"mylang\.json" + NAME, "selka.json", "`mylang.json` -> `selka.json`", project=True),
    _rule("env-mylang", "core", r"MYLANG_", "SELKA_", "MYLANG_* variables -> SELKA_*", project=True),
    _rule("env-myl-core", "core", r"MYL_CORE_", "SELKA_CORE_", "MYL_CORE_* -> SELKA_CORE_*", project=True),
    _rule("cache-project", "core", r"\.mylang-cache", ".selka-cache", "`.mylang-cache` -> `.selka-cache`", project=True),
    _rule("user-dirs", "core", r"(\.cache|\.config|\.local/state|\.local/share|XDG_[A-Z_]+\}?)/mylang", r"\1/selka",
          "per-user directories `~/.cache/mylang`, `~/.config/mylang`, `~/.local/state/mylang`, `$XDG_*/mylang` -> selka"),
    _rule("install-bin", "core", r"(?<=bin/)mylang", "selka", "`bin/mylang` (the installed command) -> `bin/selka`", project=True),
    _rule("install-libexec", "core", r"(?<=libexec/)mylang", "selka", "`libexec/mylang` -> `libexec/selka`"),
    _rule("commit-file", "core", r"mylang(?=\.commit)", "selka", "`mylang.commit` (and `.index`) -> `selka.commit`"),
    _rule("fence", "core", r"(`{3}|~{3})(?:mylang|my)" + NAME, r"\1selka",
          "documentation fence ```mylang or its short alias ```my (also ~~~) -> selka", project=True),
    _rule("doc-marker", "core", r"not-mylang", "not-selka",
          "the prose marker `# doc: not-mylang` -> `not-selka` (the compiler keeps recognising the old one: code, by hand)"),
    # The symbol group: off unless --with-symbols (decision GH-D16), one switch for all of it.
    _rule("producer", "symbols", r"mylang-core(?![A-Za-z0-9_-])", "selka-core",
          "the debug-info producer and the `mylang-core:` output prefix -> `selka-core`"),
    _rule("guest-symbol", "symbols", r"(@\\?\")my\.(?=[A-Za-z_{])", r"\1selka.",
          "LLVM guest symbols @\"my.NAME\" (and the format @\"my.{s}\") -> @\"selka.NAME\""),
    _rule("guest-symbol-quoted", "symbols", r"(?<![A-Za-z0-9_.])\"my\.(?=[A-Za-z_])", '"selka.',
          "a quoted symbol \"my.NAME\" in the core's code and tests -> \"selka.NAME\"", only=("src/core/",)),
    _rule("guest-symbol-literal", "symbols", r"(?<![A-Za-z0-9_.])\"my\.\"", '"selka."',
          "the literal prefix \"my.\" the code strips or adds -> \"selka.\""),
    _rule("guest-symbol-prose", "symbols", r"\bmy\.(?=[A-Za-z_<][A-Za-z0-9_<>]*::)", "selka.",
          "`my.module::name` as profilers print it -> `selka.module::name`"),
    _rule("runtime-symbol", "symbols", r"myl_", "selka_", "runtime symbols and files `myl_...` -> `selka_...`"),
    _rule("runtime-macro", "symbols", r"MYL_", "SELKA_", "C macros `MYL_...` (MYL_CORE_ was done above) -> `SELKA_...`"),
    # `"my"` standing alone is a language or extension label (benchmark arms, the short fence tag), not the name.
    _rule("label-my", "core", r"(?<![A-Za-z0-9_.])([\"'])my\1", r"\1selka\1",
          "a quoted `\"my\"` language or extension label -> `\"selka\"`"),
    # The catch-all: every other spelling of the name, case preserved (mylang, MYLANG, MyLang, Mylang).
    _rule("name-word", "core", r"mylang", _case, "any other `mylang` (any case; also inside names) -> `selka`/`SELKA`/`Selka`",
          flags=re.IGNORECASE),
    # Project mode takes the command name only where it stands alone as a word.
    _rule("project-command", "core", r"(?<![A-Za-z0-9_./])(?<![A-Za-z0-9_]-)mylang(?![A-Za-z0-9_.-])", _case,
          "(project mode only) the command or shell variable `mylang`/`MYLANG` as a whole word -> `selka`/`SELKA`",
          flags=re.IGNORECASE, project=True),
)
SUFFIX_RULE = next(r for r in RULES if r.name == "suffix-source")
# `name-word` is not part of --project (it would rename identifiers of the project's own); `project-command` replaces it.
PROJECT_ONLY = {"project-command"}
NOT_PROJECT = {"name-word"}


@dataclass(frozen=True)
class Span:
    name: str
    pattern: re.Pattern
    reason: str
    when_group_off: Optional[str] = None  # the span is protected only when this group is switched off
    only: tuple = ()  # when not empty: only for paths that start with one of these


SPANS: tuple[Span, ...] = (
    Span("checkout-folders", re.compile(r"canopy/mylang[A-Za-z0-9_.-]*"),
         "the checkout folder and the worktree and archive folders keep their names (the agents' memory is keyed on the path)"),
    Span("home-cache-folders", re.compile(r"\.home-cache/mylang[A-Za-z0-9_.-]*"),
         "machine folders of this host, outside the repository"),
    Span("git-tag", re.compile(r"refs/tags/mylang-[A-Za-z0-9._-]*"), "a tag that exists in the repository keeps its name"),
    Span("machine-folders", re.compile(
        r"(?<![A-Za-z0-9_.-])mylang-(?:evidence-archive|map-refresh|worktrees|checkbuild|review-gate-probe|lane-[A-Za-z0-9_]+|"
        r"gate(?![A-Za-z0-9_-]))(?![A-Za-z0-9_])"),
         "a sibling checkout or worktree folder named without its parent (`mylang-lane-s4`, `mylang-map-refresh`, `mylang-evidence-archive`) "
         "keeps its name: the folders are not renamed"),
    Span("marked-lines", re.compile(r"[^\n]*rename: keep[^\n]*"),
         "a line that holds the words `rename: keep` names the old spelling on purpose (the hints and their tests)"),
    Span("recorded-compilers", re.compile(r'(?<=/)bin/mylang(?=")'),
         "the old pinned compilers that measured bench/parity/thresholds.json are called mylang", only=("bench/parity/thresholds.json",)),
    Span("producer-name", re.compile(r'(?:producer:? ?\\?"|\.producer, ")mylang-core(?=\\?")'),
         "without the symbol group the debug-info producer string stays what the runtime compares it with: only where it is written "
         "as the producer (`producer: \"mylang-core\"`, `strcmp(cu.producer, \"mylang-core\")`)", "symbols"),
)


@dataclass(frozen=True)
class Keep:
    name: str
    pattern: str  # a prefix when it ends with "/", else an fnmatch glob over the repository-relative path
    reason: str

    def matches(self, path: str) -> bool:
        if self.pattern.endswith("/"):
            return path.startswith(self.pattern)
        return fnmatch.fnmatchcase(path, self.pattern)


KEPT: tuple[Keep, ...] = (
    Keep("history-audits", "docs/audits/", "dated audit reports describe the compiler that produced them"),
    Keep("history-legacy", "docs/legacy/", "retired documents, kept as they were"),
    Keep("history-experiments", "experiments/", "experiment archives: their recorded names, commands and hashes"),
    Keep("history-doc-experiments", "docs/experiments/", "write-ups of past runs, like docs/audits: they name what ran"),
    Keep("history-velocity", "velocity/", "dated velocity trials and their results"),
    Keep("bench-candidates", "benchmarks/runtime/candidates/", "recorded benchmark candidates and their readmes"),
    Keep("bench-results", "benchmarks/runtime/results/", "recorded benchmark results"),
    Keep("bench-assessment", "benchmarks/runtime/assessment/results/", "recorded benchmark assessment"),
    Keep("bench-audit", "benchmarks/runtime/audit/", "recorded benchmark audit evidence"),
    Keep("bench-parity-records", "bench/parity/*_2026????.json", "dated parity measurements, as recorded"),
    Keep("rename-program", "scripts/rename_to_selka*.py", "the program and its tests spell the old names as data: it must not rewrite itself"),
)

# Lines kept inside a file that is otherwise rewritten: (path glob, how many lines at the top).
KEEP_FILE = re.compile(r"rename: keep-file")
KEPT_HEAD_LINES = (
    ("tools/test_runner/*.zig", 1, "the origin header (a copy of guardian-zig, MIT): the copied URL and commit stay exact"),
)

# Places where a renamed string is hashed into something a test or a file pins: the hand fixes of the cut.
# (name, regex over the text before the rename, what breaks)
WATCH: tuple[tuple[str, Optional[re.Pattern], str], ...] = (
    ("cache-identity", re.compile(r"\bmylang-[a-z0-9-]+-v[0-9]+\b"),
     "a cache key or digest domain: every store entry under the old key is orphaned, and a pinned digest changes"),
    ("not-mylang-in-code", re.compile(r"\"not-mylang\"|not_mylang\b"),
     "the compiler must keep recognising the old marker: re-add it by hand after the rename"),
    ("suffix-length", None,
     "a length assumption about the three-character suffix `.my`: `len - 3`, `+ 3` or `[0..3]` within eight lines after a `.my` literal"),
    ("suffix-literal-zig", re.compile(r"\"\.myi?\""),
     "a `\".my\"` literal in code (GH-5.1 moves these into one place)"),
    ("fixed-width-array", re.compile(r"\[[0-9]+\]u8\s*=\s*\"[^\"]*(?:\.my|mylang|myl_)[^\"]*\"\.\*"),
     "a fixed-size byte array initialised from a string that carries a renamed name"),
    ("selka-underscore-names", re.compile(r"\bselka_[A-Za-z0-9_]+"),
     "a name that already starts with `selka_`: the symbol group makes `selka_` the reserved runtime prefix "
     "(src/c_abi.zig refuses extern names in it), so a project's own extern `selka_sqlite_open` would be refused"),
    ("symbol-hash", re.compile(r"myl_[tf]_[0-9a-f]{16,64}"),
     "a symbol that carries a digest: the digest may be computed over text that names renamed symbols"),
)

RESIDUAL: tuple[tuple[str, str, re.Pattern], ...] = (
    ("mylang", "core", re.compile(r"mylang", re.IGNORECASE)),
    ("suffix-left", "core", re.compile(r"\.myi?(?![A-Za-z0-9_])")),
    ("fence-alias-my", "core", re.compile(r"(?:`{3}|~{3})my(?![A-Za-z0-9_])")),
    ("guardian-runner", "core", re.compile(r"--guardian-|guardian/test|GUARDIAN_TEST_")),
    ("language-label-my", "core", re.compile(r"(?<![A-Za-z0-9_.])[\"']my[\"']")),
    ("myl-names", "symbols", re.compile(r"myl_|MYL_|(?<![A-Za-z0-9_.])\"my\.|@\\?\"my\.|\bmy\.[A-Za-z_]\w*::")),
)

NAIVE_SUFFIX = (re.compile(r"\.my"), re.compile(r"\.my\b"))
TOKEN = re.compile(r"[A-Za-z0-9_-]*(?:selka|SELKA|Selka)[A-Za-z0-9_-]*")
SKIP_DIRS = {".git", ".mylang-cache", ".selka-cache", ".zig-cache", "zig-out", "node_modules"}


@dataclass
class Config:
    with_symbols: bool = False
    changes_kept_from: tuple = CHANGES_KEPT_FROM
    rewrite_kept: frozenset = frozenset()
    project: bool = False
    keep_paths: bool = True  # False: a path inside a kept folder is renamed like any other (the lines `.gitignore` adds)

    def rules(self) -> list[Rule]:
        chosen = []
        for rule in RULES:
            if not self.with_symbols and rule.group == "symbols":
                continue
            if self.project and (not rule.project or rule.name in NOT_PROJECT):
                continue
            if not self.project and rule.name in PROJECT_ONLY:
                continue
            chosen.append(rule)
        return chosen

    def spans(self) -> list[Span]:
        chosen = [s for s in SPANS if s.when_group_off is None or (s.when_group_off == "symbols" and not self.with_symbols)]
        prefixes = [k.pattern for k in KEPT if k.pattern.endswith("/") and k.name not in self.rewrite_kept]
        if prefixes and not self.project and self.keep_paths:
            # A live file that names a path inside a kept folder (`experiments/x/main.my`, a glob, a link) must keep naming
            # what is there: the folder is not renamed, so neither is the mention.
            pattern = r"(?<![A-Za-z0-9_-])(?:%s)[^\s\"'`<>()\[\]{},;|]*" % "|".join(re.escape(p) for p in prefixes)
            chosen.append(Span("kept-path-mentions", re.compile(pattern),
                               "a path inside a kept folder, wherever a live file names it, keeps its spelling"))
        return chosen


@dataclass
class FilePlan:
    path: str
    new_path: str
    status: str  # "rewrite", "kept", "binary", "symlink"
    reason: str = ""
    new_text: Optional[str] = None
    counts: Counter = field(default_factory=Counter)
    spans: Counter = field(default_factory=Counter)
    residual: list = field(default_factory=list)  # (line, kind, group, text)
    move_kind: str = ""
    kept_hits: int = 0
    watch: Counter = field(default_factory=Counter)
    created_tokens: set = field(default_factory=set)
    naive: Counter = field(default_factory=Counter)
    new_target: Optional[str] = None  # a link whose target text names renamed things
    identities: Counter = field(default_factory=Counter)


def apply_rules(text: str, cfg: Config, path: str = "") -> tuple[str, Counter, Counter, str, list]:
    """Return (new text, rule counts, span counts, masked new text for scanning, saved spans)."""
    saved: list[str] = []
    span_counts: Counter = Counter()

    def hold(name: str) -> Callable[[re.Match], str]:
        def inner(match: re.Match) -> str:
            saved.append(match.group(0))
            span_counts[name] += 1
            return "\x00%d\x00" % (len(saved) - 1)
        return inner

    masked = text
    for span in cfg.spans():
        if span.only and not path.startswith(span.only):
            continue
        masked = span.pattern.sub(hold(span.name), masked)
    counts: Counter = Counter()
    for rule in cfg.rules():
        if not rule.applies(path):
            continue
        masked, n = rule.pattern.subn(rule.repl, masked)
        if n:
            counts[rule.name] += n
    restored = restore(masked, saved)
    return restored, counts, span_counts, masked, saved


_HOLD = re.compile(r"\x00(\d+)\x00")


def restore(masked: str, saved: list[str]) -> str:
    return _HOLD.sub(lambda m: saved[int(m.group(1))], masked) if saved else masked


def split_kept(path: str, text: str, cfg: Config) -> Optional[tuple[str, str, str]]:
    """The (kept head, rewritable middle, kept tail) of a file, or None when the marker of CHANGES.md is missing."""
    if path == "CHANGES.md":
        offset = 0
        for line in text.splitlines(keepends=True):
            if line.rstrip("\r\n") in cfg.changes_kept_from:
                return "", text[:offset], text[offset:]
            offset += len(line)
        return None
    for glob, count, _ in KEPT_HEAD_LINES:
        if fnmatch.fnmatchcase(path, glob):
            lines = text.splitlines(keepends=True)
            return "".join(lines[:count]), "".join(lines[count:]), ""
    return "", text, ""


def keep_for(path: str, cfg: Config) -> Optional[Keep]:
    if cfg.project:
        return None
    for keep in KEPT:
        if keep.name not in cfg.rewrite_kept and keep.matches(path):
            return keep
    return None


def renamed_path(path: str, cfg: Config) -> tuple[str, Counter]:
    """The path after the rules (every component goes through the table; `mylang.json`, suffixes, names with `myl_`)."""
    if keep_for(path, cfg):
        return path, Counter()
    new, counts, _, _, _ = apply_rules(path, cfg, path)
    return new, counts


MOVE_KINDS = (("suffix-source", ".my -> .selka"), ("suffix-interface", ".myi -> .selkai"),
              ("project-file", "mylang.json -> selka.json"), ("runtime-symbol", "myl_ names"), ("name-word", "other names with mylang"))


def move_kind(counts: Counter) -> str:
    for rule, label in MOVE_KINDS:
        if counts[rule]:
            return label
    return "other names" if counts else ""


def scan_residual(masked: str, line_base: int, saved: list[str], cfg: Config) -> list:
    hits = []
    for kind, group, pattern in RESIDUAL:
        for match in pattern.finditer(masked):
            line_no = line_base + masked.count("\n", 0, match.start()) + 1
            start = masked.rfind("\n", 0, match.start()) + 1
            end = masked.find("\n", match.end())
            line = restore(masked[start:end if end >= 0 else len(masked)], saved)
            hits.append((line_no, kind, group, line))
    unique = {}
    for hit in hits:
        unique.setdefault((hit[0], hit[1]), hit)
    return [unique[key] for key in sorted(unique)]


_SUFFIX_MENTION = re.compile(r"\.myi?\"|\.myi?\b")
_LENGTH_THREE = re.compile(r"(?:len|length)\s*[-+]\s*3\b|\[0\s*\.\.\s*3\]")


def suffix_length_sites(body: str) -> int:
    """Lines that do arithmetic with the number three within eight lines after a line that names the suffix."""
    lines = body.split("\n")
    last_mention = -100
    sites = 0
    for index, line in enumerate(lines):
        if _SUFFIX_MENTION.search(line):
            last_mention = index
        if index - last_mention <= 8 and _LENGTH_THREE.search(line):
            sites += 1
    return sites


def pair_ignore_lines(body: str, cfg: Config, path: str) -> tuple[str, Counter]:
    """A `.gitignore`: each pattern line that a rule would change stays, and its new spelling follows it (unless the file
    already holds that line); a comment line is rewritten in place. A path inside a kept folder is renamed here too:
    a future experiment written with the new names must be tracked like the old ones."""
    plain = replace(cfg, keep_paths=False)
    lines = body.splitlines(keepends=True)
    present = {line.rstrip("\r\n") for line in lines}
    out: list[str] = []
    counts: Counter = Counter()
    for line in lines:
        text = line.rstrip("\r\n")
        ending = line[len(text):] or "\n"
        if text.lstrip().startswith("#"):
            new, found, _, _, _ = apply_rules(text, cfg, path)
            out.append(new + line[len(text):])
            counts.update(found)
            continue
        out.append(line)
        new, found, _, _, _ = apply_rules(text, plain, path)
        if new == text or new in present:
            continue
        present.add(new)
        if not line.endswith("\n"):
            out[-1] = line + "\n"
        out.append(new + ending)
        counts.update(found)
    return "".join(out), counts


def plan_file(root: Path, path: str, cfg: Config) -> FilePlan:
    new_path, path_counts = renamed_path(path, cfg)
    full = root / path
    plan = FilePlan(path, new_path, "rewrite", counts=Counter())
    plan.move_kind = move_kind(path_counts) if new_path != path else ""
    if full.is_symlink():
        plan.status, plan.reason = "symlink", "a link: its target text is renamed, not the file behind it"
        if not keep_for(path, cfg):
            target = os.readlink(full)
            renamed = apply_rules(target, cfg, path)[0]
            plan.new_target = renamed if renamed != target else None
        return plan
    try:
        data = full.read_bytes()
    except OSError as error:
        plan.status, plan.reason = "binary", "unreadable: %s" % error
        return plan
    if b"\x00" in data[:8192]:
        plan.status, plan.reason = "binary", "binary file"
        return plan
    try:
        text = data.decode("utf-8")
    except UnicodeDecodeError:
        plan.status, plan.reason = "binary", "not UTF-8"
        return plan
    keep = keep_for(path, cfg)
    if keep:
        plan.status, plan.reason = "kept", keep.name
        plan.kept_hits = sum(1 for line in text.splitlines() if any(p.search(line) for _, _, p in RESIDUAL))
        return plan
    if not cfg.project and KEEP_FILE.search("\n".join(text.splitlines()[:8])):
        plan.status, plan.reason = "kept", "marked-file"
        plan.kept_hits = sum(1 for line in text.splitlines() if any(p.search(line) for _, _, p in RESIDUAL))
        return plan
    parts = split_kept(path, text, cfg)
    if parts is None:
        plan.status, plan.reason = "kept", "CHANGES.md marker line not found"
        return plan
    head, body, tail = parts
    if os.path.basename(path) == ".gitignore":
        new_body, counts = pair_ignore_lines(body, cfg, path)
        spans, residual = Counter(), []
    else:
        new_body, counts, spans, masked, saved = apply_rules(body, cfg, path)
        residual = scan_residual(masked, head.count("\n"), saved, cfg)
    plan.counts, plan.spans, plan.residual = counts, spans, residual
    if tail:
        plan.kept_hits = sum(1 for line in tail.splitlines() if any(p.search(line) for _, _, p in RESIDUAL))
    plan.new_text = head + new_body + tail
    if plan.new_text == text:
        plan.new_text = None
    for name, pattern, _ in WATCH:
        found = suffix_length_sites(body) if pattern is None else len(pattern.findall(body))
        if found:
            plan.watch[name] = found
            if name == "cache-identity":
                plan.identities.update(m for m in pattern.findall(body))
    if plan.new_text is not None:
        plan.created_tokens = set(TOKEN.findall(plan.new_text)) - set(TOKEN.findall(text))
    bounded = {m.start() for m in SUFFIX_RULE.pattern.finditer(body)}
    for index, pattern in enumerate(NAIVE_SUFFIX):
        for match in pattern.finditer(body):
            if match.start() not in bounded:
                token = re.match(r"\.my[A-Za-z0-9_]*(?:\.[a-z]+)?", body[match.start():])
                plan.naive[(index, token.group(0) if token else ".my")] += 1
    return plan


def run(root: Path, *args: str, check: bool = True) -> str:
    done = subprocess.run(["git", "-C", str(root), *args], capture_output=True, text=True)
    if check and done.returncode != 0:
        raise SystemExit("git %s failed: %s" % (" ".join(args), done.stderr.strip()))
    return done.stdout


def is_repository(root: Path) -> bool:
    done = subprocess.run(["git", "-C", str(root), "rev-parse", "--show-toplevel"], capture_output=True, text=True)
    return done.returncode == 0 and Path(done.stdout.strip()).resolve() == root.resolve()


def list_files(root: Path) -> tuple[list[str], set[str]]:
    """Sorted relative paths, and the subset that git tracks."""
    tracked: set[str] = set()
    if is_repository(root):
        tracked = {p for p in run(root, "ls-files", "-z").split("\0") if p}
    found = set(tracked)
    if not tracked:
        for folder, dirs, names in os.walk(root):
            dirs[:] = sorted(d for d in dirs if d not in SKIP_DIRS)
            for name in names:
                found.add(os.path.relpath(os.path.join(folder, name), root).replace(os.sep, "/"))
    return sorted(p for p in found if (root / p).exists() or (root / p).is_symlink()), tracked


@dataclass
class Plan:
    files: list[FilePlan]
    problems: list[str]

    def moves(self) -> list[FilePlan]:
        return [f for f in self.files if f.new_path != f.path]

    def edits(self) -> list[FilePlan]:
        return [f for f in self.files if f.new_text is not None]

    def retargets(self) -> list[FilePlan]:
        return [f for f in self.files if f.new_target is not None]


def build_plan(root: Path, cfg: Config) -> tuple[Plan, set[str]]:
    paths, tracked = list_files(root)
    files = [plan_file(root, p, cfg) for p in paths]
    problems = []
    targets = defaultdict(list)
    for f in files:
        targets[f.new_path].append(f.path)
    existing = set(paths)
    for target, sources in sorted(targets.items()):
        if len(sources) > 1:
            problems.append("two files become %s: %s" % (target, ", ".join(sources)))
        elif target != sources[0] and target in existing:
            problems.append("%s would replace the existing %s" % (sources[0], target))
    return Plan(files, problems), tracked


def table(plan: Plan, cfg: Config) -> list[str]:
    per_rule_files: Counter = Counter()
    per_rule_hits: Counter = Counter()
    for f in plan.files:
        for rule, n in f.counts.items():
            per_rule_files[rule] += 1
            per_rule_hits[rule] += n
    # Path renames also count in the rules, but only text counts belong in this table.
    lines = ["%-22s %-8s %7s %13s" % ("rule", "group", "files", "replacements")]
    for rule in cfg.rules():
        lines.append("%-22s %-8s %7d %13d" % (rule.name, rule.group, per_rule_files[rule.name], per_rule_hits[rule.name]))
    lines.append("%-22s %-8s %7d %13d" % ("TOTAL", "", len(plan.edits()), sum(per_rule_hits.values())))
    return lines


def report(plan: Plan, cfg: Config, out, moves: bool = False) -> int:
    emit = lambda text="": print(text, file=out)
    emit("== rules (files and replacements in file contents) ==")
    for line in table(plan, cfg):
        emit(line)
    emit()
    emit("== files to move (git mv) ==")
    kinds = Counter(f.move_kind for f in plan.moves())
    for _, label in MOVE_KINDS + (("other", "other names"),):
        if kinds[label]:
            emit("%-28s %6d" % (label, kinds[label]))
    emit("%-28s %6d" % ("TOTAL", len(plan.moves())))
    if moves:
        for f in plan.moves():
            emit("  %s -> %s" % (f.path, f.new_path))
    span_totals: Counter = Counter()
    for f in plan.files:
        span_totals.update(f.spans)
    emit()
    emit("== names kept inside rewritten files (SPANS) ==")
    for span in cfg.spans():
        emit("%-20s %6d  %s" % (span.name, span_totals[span.name], span.reason))
    emit()
    emit("== paths that keep the old name (KEPT) ==")
    for keep in KEPT:
        members = [f for f in plan.files if f.status == "kept" and f.reason == keep.name]
        state = "REWRITTEN (--rewrite-kept)" if keep.name in cfg.rewrite_kept else "%5d files, %6d lines with the old name" % (
            len(members), sum(f.kept_hits for f in members))
        emit("%-22s %-40s %s" % (keep.name, keep.pattern, state))
        emit("    why: " + keep.reason)
    for glob, count, why in KEPT_HEAD_LINES:
        emit("%-22s %-40s first %d line(s)" % ("kept-head", glob, count))
        emit("    why: " + why)
    changes = [f for f in plan.files if f.path == "CHANGES.md"]
    if changes:
        emit("CHANGES.md: kept from the first of the lines %s down (%d lines with the old name below it)" % (
            " / ".join(repr(line[:50]) for line in cfg.changes_kept_from), changes[0].kept_hits)
            if changes[0].status == "rewrite" else "CHANGES.md: MARKER LINE NOT FOUND, the whole file is kept")
    other = Counter(f.status for f in plan.files if f.status in ("binary", "symlink"))
    emit("binary files: %d (not UTF-8 or with NUL bytes); links: %d, of which %d get a renamed target" % (
        other["binary"], other["symlink"], len(plan.retargets())))
    emit()
    emit("== places where a renamed string reaches a stored format or a pinned value (WATCH; before the rename) ==")
    for name, _, why in WATCH:
        members = [(f.path, f.watch[name]) for f in plan.files if f.watch[name]]
        emit("%-20s %5d lines in %4d files: %s" % (name, sum(n for _, n in members), len(members), why))
        for path, n in members[:6]:
            emit("    %s (%d)" % (path, n))
        if len(members) > 6:
            emit("    ... %d more files" % (len(members) - 6))
        if name == "cache-identity":
            names: dict = defaultdict(set)
            for f in plan.files:
                for text in f.identities:
                    names[text].add(f.path)
            emit("    %d distinct identity strings (files in parentheses; in src/ they are hashed or compared):" % len(names))
            for text in sorted(names):
                emit("      %s (%s)" % (text, ", ".join(sorted(names[text])[:3]) + (" ..." if len(names[text]) > 3 else "")))
    emit()
    emit("== what the suffix rule's bounds keep out (matches of the unbounded patterns the rule does not take) ==")
    naive: Counter = Counter()
    for f in plan.files:
        naive.update(f.naive)
    for index, label in enumerate(("`\\.my` anywhere", "`\\.my\\b`")):
        rows = [(n, tok) for (i, tok), n in naive.items() if i == index]
        emit("%s would also have matched %d places in %d distinct spellings: %s" % (
            label, sum(n for n, _ in rows), len(rows), ", ".join("%s x%d" % (t, n) for n, t in sorted(rows, reverse=True)[:8])))
    emit()
    emit("== uncovered hits: the old name where no rule reaches (path:line: text) ==")
    unlisted = Counter()
    by_folder: dict = defaultdict(list)
    for f in plan.files:
        for line_no, kind, group, text in f.residual:
            if group == "symbols" and not cfg.with_symbols:
                unlisted[kind] += 1
                continue
            folder = f.path.split("/", 1)[0] if "/" in f.path else "(top level)"
            by_folder[folder].append("%s:%d: [%s] %s" % (f.path, line_no, kind, text.strip()[:120]))
    total = 0
    for folder in sorted(by_folder):
        emit("-- %s (%d)" % (folder, len(by_folder[folder])))
        for line in by_folder[folder]:
            emit(line)
        total += len(by_folder[folder])
    if unlisted:
        emit("left alone with the symbol group off (not listed): " + ", ".join("%s %d" % kv for kv in sorted(unlisted.items())))
    for problem in plan.problems:
        emit("PROBLEM: " + problem)
    emit()
    emit("TOTAL: %d files rewritten (%d replacements), %d files moved, %d uncovered hits, %d problems" % (
        len(plan.edits()), sum(sum(f.counts.values()) for f in plan.files), len(plan.moves()), total, len(plan.problems)))
    return total


def collisions(plan: Plan, root: Path) -> list[str]:
    """Names the rename creates that already exist elsewhere in the tree (a cache domain used twice, a variable)."""
    bare = {"selka", "SELKA", "Selka", "selka_", "SELKA_", "selka-", "SELKA-"}
    created: set = set()
    for f in plan.files:
        created |= f.created_tokens
    created -= bare
    found: dict = {}
    for f in plan.files:
        if f.status != "rewrite" or not created:
            continue
        try:
            text = (root / f.path).read_text(encoding="utf-8")
        except (OSError, UnicodeDecodeError):
            continue
        for token in created & set(TOKEN.findall(text)):
            found.setdefault(token, f.path)
    return ["%s (already in %s)" % (token, found[token]) for token in sorted(found)]


def apply_plan(root: Path, plan: Plan, tracked: set[str], cfg: Config) -> None:
    for f in plan.edits():
        full = root / f.path
        mode = full.stat().st_mode
        full.write_bytes(f.new_text.encode("utf-8"))
        os.chmod(full, mode)
    use_git = bool(tracked)
    for f in plan.moves():
        source, target = root / f.path, root / f.new_path
        target.parent.mkdir(parents=True, exist_ok=True)
        if use_git and f.path in tracked:
            run(root, "mv", "--", f.path, f.new_path)
        else:
            os.rename(source, target)
    for f in plan.retargets():
        link = root / f.new_path
        link.unlink()
        os.symlink(f.new_target, link)


def dirty_tracked(root: Path) -> bool:
    return bool(run(root, "status", "--porcelain", "--untracked-files=no").strip())


def main(argv: Optional[list[str]] = None) -> int:
    parser = argparse.ArgumentParser(description="Rename mylang to selka (see the module docstring).")
    mode = parser.add_mutually_exclusive_group()
    mode.add_argument("--report", action="store_true",
                      help="change nothing, print the counts (the default; with --project, the preview of that project's crossing)")
    mode.add_argument("--apply", action="store_true", help="apply in the current git worktree; refuses a dirty tree")
    mode.add_argument("--rules", action="store_true", help="print the rule table and exit")
    parser.add_argument("--project", metavar="DIR",
                        help="cross a Selka project outside this repository: applies at once, or only reports with --report")
    parser.add_argument("--root", default=".", help="the worktree (default: the current directory)")
    parser.add_argument("--with-symbols", action="store_true",
                        help="also rename the runtime and guest symbol group (off in the cut: decision GH-D16)")
    parser.add_argument("--changes-kept-from", action="append", metavar="LINE",
                        help="the first line of the newest CHANGES.md entry that keeps the old name (repeatable; replaces the defaults)")
    parser.add_argument("--rewrite-kept", action="append", default=[], metavar="NAME", help="rewrite one KEPT entry after all")
    parser.add_argument("--moves", action="store_true", help="list every move in the report")
    args = parser.parse_args(argv)

    cfg = Config(with_symbols=args.with_symbols, changes_kept_from=tuple(args.changes_kept_from or CHANGES_KEPT_FROM),
                 rewrite_kept=frozenset(args.rewrite_kept), project=bool(args.project))
    if args.rules:
        for rule in RULES:
            where = "project" if rule.project else ""
            print("%-22s %-8s %-8s %s\n    pattern: %s" % (rule.name, rule.group, where, rule.what, rule.pattern.pattern))
        for span in SPANS:
            print("keeps %-18s %s\n    pattern: %s" % (span.name, span.reason, span.pattern.pattern))
        return 0
    root = Path(args.project if args.project else args.root).resolve()
    if not root.is_dir():
        print("not a folder: %s" % root, file=sys.stderr)
        return 2
    plan, tracked = build_plan(root, cfg)
    if plan.problems:
        for problem in plan.problems:
            print("PROBLEM: " + problem, file=sys.stderr)
    # A project crosses when `--project DIR` is given alone (the command the compiler's hint names) or with --apply; with
    # --report it is only previewed. The repository itself is only reported unless --apply is given.
    apply = args.apply or (bool(args.project) and not args.report)
    if not apply:
        report(plan, cfg, sys.stdout, moves=args.moves)
        clashes = collisions(plan, root)
        print("names the rename creates that already exist in the tree (%d): %s" % (len(clashes), "; ".join(clashes[:30])))
        return 0
    if plan.problems:
        print("refusing: the problems above would lose a file", file=sys.stderr)
        return 2
    if not plan.edits() and not plan.moves() and not plan.retargets():
        print("nothing to change: no file text and no file name matches a rule")
        return 0
    if tracked and dirty_tracked(root):
        print("refusing: the worktree has uncommitted changes to tracked files; commit or discard them first", file=sys.stderr)
        return 2
    if args.apply and not args.project and not tracked:
        print("refusing: %s is not a git worktree (use --project for a project folder)" % root, file=sys.stderr)
        return 2
    if args.apply and any(f.path == "CHANGES.md" and f.reason == "CHANGES.md marker line not found" for f in plan.files):
        print("refusing: the marker line of CHANGES.md was not found (--changes-kept-from)", file=sys.stderr)
        return 2
    apply_plan(root, plan, tracked, cfg)
    report(plan, cfg, sys.stdout, moves=args.moves)
    print("applied: %d files rewritten, %d files moved, %d links retargeted" % (len(plan.edits()), len(plan.moves()), len(plan.retargets())))
    return 0


if __name__ == "__main__":
    sys.exit(main())
