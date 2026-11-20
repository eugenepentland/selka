#!/usr/bin/env python3
"""Git merge driver for `SPEC.md`: merges tagged bullets by tag, not by line.

Git calls it as ``merge_spec.py %O %A %B %P --marker-size %L`` (base, ours,
theirs, pathname) and expects the result written over ``%A``; a non-zero exit
reports a conflict. ``scripts/setup-git.sh`` registers it, ``.gitattributes``
routes ``SPEC.md`` to it.

Why: parallel lanes append ``- [TAG] …`` bullets at the end of the same SPEC
sections, so a line merge sees two insertions at one point and conflicts almost
every time. Taking both sides by hand is right for pure additions but wrong
when one side amended a bullet: the union then holds the old and the new text
under one tag, which Guardian rejects as a duplicate.

The merge has two independent halves.

**Bullet text, by tag.** A bullet is a line starting ``- [TAG]`` plus every
following line up to a blank line, a heading or the next ``- `` item (SPEC has
wrapped bullets). For each tag, compare its full text in base, ours and theirs:

* both sides agree → that text (including both deleting it);
* one side equals the base → the other side's text (its edit or its deletion);
* both sides changed it differently → a conflict, shown as standard markers at
  the bullet's place. Modify/delete is one such conflict.

**Layout, by line.** Each version becomes a sequence of tokens — one per prose
line, blank line or heading, one per bullet (its tag only, so an amended bullet
does not move the layout). A three-way line merge (diff3) of these sequences
keeps every section's untagged prose, headings and order. Where both sides
changed the same stretch:

* if that stretch holds only bullets and blank lines on all three sides, it is
  resolved: ours' version of the stretch minus the bullets theirs removed from
  it, then the tokens theirs inserted, minus bullets already present. So a
  section keeps base order with each side's additions where that side put
  them, and two appends at one point come out ours-then-theirs — the order a
  ``git merge`` of theirs into ours reads, and the order the hand union used;
* otherwise lines both sides added identically are taken once (git's own
  trimming of a conflict hunk: common head and tail, and every shared run
  when the base had nothing there), and what is left over is resolved the
  same way if it holds only bullets, or is a standard conflict — an untagged
  line is never unioned, since two sides adding text at one point may be two
  versions of one paragraph.

A bullet can never be dropped silently: a tag removed from the layout is gone
only when its text decision says it was deleted; a modify/delete keeps the
bullet as a conflict. A bullet both sides placed differently is written once,
at its first place. If an input already repeats a tag, the structured merge
declines and the driver falls back to ``git merge-file`` for the whole file
(git's own result, conflict markers included); it does the same if a bullet
the decisions keep would end up nowhere in the result.

Without the driver configured (see ``scripts/setup-git.sh``), git silently uses
its normal text merge for ``SPEC.md``: nothing breaks, the old conflicts return.
"""
from __future__ import annotations

import argparse
import difflib
from dataclasses import dataclass
import re
import subprocess
import sys

TAG_RE = re.compile(r"^- \[([^\]\s]+)\]")

# Layout tokens: ("L", line) for any untagged line, ("B", tag) for a bullet.
Token = tuple[str, str]


@dataclass
class Version:
    """One side of the merge: its layout tokens and each tag's bullet text."""

    tokens: list[Token]
    bullets: dict[str, str]
    duplicates: list[str]


def parse(text: str) -> Version:
    """Split SPEC text into layout tokens and tag → full bullet text."""
    tokens: list[Token] = []
    bullets: dict[str, str] = {}
    duplicates: list[str] = []
    lines = text.splitlines(keepends=True)
    i = 0
    while i < len(lines):
        match = TAG_RE.match(lines[i])
        if match is None:
            tokens.append(("L", lines[i]))
            i += 1
            continue
        tag = match.group(1)
        end = i + 1
        while end < len(lines) and is_continuation(lines[end]):
            end += 1
        if tag in bullets:
            duplicates.append(tag)
        bullets[tag] = "".join(lines[i:end])
        tokens.append(("B", tag))
        i = end
    return Version(tokens, bullets, duplicates)


def is_continuation(line: str) -> bool:
    """Whether a line continues the bullet above it (a wrapped bullet)."""
    stripped = line.strip()
    return stripped != "" and not stripped.startswith("#") and not line.startswith("- ")


@dataclass
class Decision:
    """The merged text of one tag, or the three texts of a conflict."""

    text: str | None
    conflict: tuple[str | None, str | None, str | None] | None = None


def decide(tag: str, base: Version, ours: Version, theirs: Version) -> Decision:
    """Merge one tag's bullet text: the side that changed it wins."""
    b, o, t = base.bullets.get(tag), ours.bullets.get(tag), theirs.bullets.get(tag)
    if o == t:
        return Decision(o)
    if o == b:
        return Decision(t)
    if t == b:
        return Decision(o)
    return Decision(None, (o, b, t))


def diff3(base: list[Token], ours: list[Token], theirs: list[Token]):
    """Yield ("stable", tokens) or ("chunk", base, ours, theirs) regions."""
    to_ours = matches(base, ours)
    to_theirs = matches(base, theirs)
    i = j = k = 0
    while i < len(base) or j < len(ours) or k < len(theirs):
        n = 0
        while (
            i + n < len(base)
            and to_ours.get(i + n) == j + n
            and to_theirs.get(i + n) == k + n
        ):
            n += 1
        if n:
            yield ("stable", base[i : i + n])
            i, j, k = i + n, j + n, k + n
            continue
        nxt = i
        while nxt < len(base) and not (nxt in to_ours and nxt in to_theirs):
            nxt += 1
        if nxt == len(base):
            yield ("chunk", base[i:], ours[j:], theirs[k:])
            return
        yield ("chunk", base[i:nxt], ours[j : to_ours[nxt]], theirs[k : to_theirs[nxt]])
        i, j, k = nxt, to_ours[nxt], to_theirs[nxt]


def matches(a: list[Token], b: list[Token]) -> dict[int, int]:
    """Map each index of `a` that difflib matches to its index in `b`."""
    out: dict[int, int] = {}
    for block in difflib.SequenceMatcher(None, a, b, autojunk=False).get_matching_blocks():
        for n in range(block.size):
            out[block.a + n] = block.b + n
    return out


def only_bullets(*chunks: list[Token]) -> bool:
    """Whether every token is a bullet or a blank line."""
    return all(kind == "B" or text.strip() == "" for chunk in chunks for kind, text in chunk)


def tags_of(chunk: list[Token]) -> list[str]:
    """The bullet tags of a chunk, in order."""
    return [text for kind, text in chunk if kind == "B"]


def inserted(base: list[Token], side: list[Token]) -> list[Token]:
    """The tokens `side` inserted relative to `base`, in `side` order."""
    out: list[Token] = []
    for op, _, _, j1, j2 in difflib.SequenceMatcher(None, base, side, autojunk=False).get_opcodes():
        if op in ("insert", "replace"):
            out.extend(side[j1:j2])
    return out


class Merger:
    """Holds the three parsed versions and the per-tag decisions."""

    def __init__(self, base: Version, ours: Version, theirs: Version):
        self.base, self.ours, self.theirs = base, ours, theirs
        tags = set(base.bullets) | set(ours.bullets) | set(theirs.bullets)
        self.decisions = {tag: decide(tag, base, ours, theirs) for tag in tags}

    def kept_conflicts(self, base_chunk: list[Token], picked: list[Token]) -> list[Token]:
        """Conflicted bullets of `base_chunk` that `picked` would drop."""
        present = set(tags_of(picked))
        return [
            ("B", tag)
            for tag in tags_of(base_chunk)
            if tag not in present and self.decisions[tag].conflict is not None
        ]

    def resolve(self, b: list[Token], o: list[Token], t: list[Token]) -> list:
        """Merge one changed region into tokens and ("C", (o, b, t)) conflicts.

        Lines both sides added identically are taken once, as git's own merge
        trims a conflict hunk: first the common head and tail of ours and
        theirs, then, when the base had nothing here, every run the two
        insertions share.
        """
        merged = self.leaf(b, o, t)
        if merged is not None:
            return merged
        head = common_prefix(o, t)
        tail = common_prefix(o[head:][::-1], t[head:][::-1])
        mid_o, mid_t = o[head : len(o) - tail], t[head : len(t) - tail]
        if b:
            middle = self.leaf(b, mid_o, mid_t) or [("C", (mid_o, b, mid_t))]
        else:
            middle = []
            matcher = difflib.SequenceMatcher(None, mid_o, mid_t, autojunk=False)
            for op, i1, i2, j1, j2 in matcher.get_opcodes():
                if op == "equal":
                    middle.extend(mid_o[i1:i2])
                    continue
                sub_o, sub_t = mid_o[i1:i2], mid_t[j1:j2]
                middle.extend(self.leaf([], sub_o, sub_t) or [("C", (sub_o, [], sub_t))])
        return o[:head] + middle + o[len(o) - tail :]

    def leaf(self, b: list[Token], o: list[Token], t: list[Token]) -> list[Token] | None:
        """Resolve a region one side left alone or that holds only bullets."""
        if o == b or t == b or o == t:
            picked = t if o == b else o
            return self.kept_conflicts(b, picked) + picked
        if not only_bullets(b, o, t):
            return None
        removed_by_theirs = set(tags_of(b)) - set(tags_of(t))
        result = [
            token
            for token in o
            if not (
                token[0] == "B"
                and token[1] in removed_by_theirs
                and self.decisions[token[1]].conflict is None
            )
        ]
        result = self.kept_conflicts(b, result) + result
        present = set(tags_of(result))
        for token in inserted(b, t):
            if token[0] == "B" and token[1] in present:
                continue
            result.append(token)
        return result

    def run(self, markers: int) -> tuple[str, int] | None:
        """Return (merged text, conflict count), or None to decline."""
        out: list[str] = []
        placed: set[str] = set()
        blocks: list[str] = []
        for region in diff3(self.base.tokens, self.ours.tokens, self.theirs.tokens):
            merged = region[1] if region[0] == "stable" else self.resolve(*region[1:])
            for kind, value in merged:
                if kind == "C":
                    o, b, t = value
                    blocks.append(self.conflict_block(o, b, t, markers))
                    out.append(blocks[-1])
                    continue
                if kind == "L":
                    out.append(value)
                    continue
                if value in placed:
                    # Both sides put this bullet in different places. Its text
                    # (or its conflict) is already written at the first place.
                    continue
                placed.add(value)
                decision = self.decisions[value]
                if decision.conflict is not None:
                    blocks.append(markered(decision.conflict, markers))
                    out.append(blocks[-1])
                elif decision.text is not None:
                    out.append(decision.text)
        for tag, decision in self.decisions.items():
            survives = decision.text is not None or decision.conflict is not None
            if survives and tag not in placed and not any(f"- [{tag}]" in block for block in blocks):
                return None
        return "".join(out), len(blocks)

    def render(self, tokens: list[Token], side: Version, merged: bool) -> str:
        """One section of a prose conflict.

        Ours and theirs show each bullet's merged text where it was decided, so
        picking either side keeps the other side's amendments; the base section
        shows the base text.
        """
        parts = []
        for kind, text in tokens:
            if kind == "L":
                parts.append(text)
                continue
            decision = self.decisions[text]
            if merged and decision.conflict is None and decision.text is not None:
                parts.append(decision.text)
            else:
                parts.append(side.bullets.get(text, ""))
        return "".join(parts)

    def conflict_block(self, o: list[Token], b: list[Token], t: list[Token], markers: int) -> str:
        """A standard diff3 conflict over one unresolvable region."""
        sections = (
            self.render(o, self.ours, True),
            self.render(b, self.base, False),
            self.render(t, self.theirs, True),
        )
        return markered(sections, markers)


def common_prefix(a: list[Token], b: list[Token]) -> int:
    """How many leading tokens two sequences share."""
    n = 0
    while n < len(a) and n < len(b) and a[n] == b[n]:
        n += 1
    return n


def markered(texts: tuple[str | None, str | None, str | None], markers: int) -> str:
    """Wrap ours/base/theirs text in git's diff3-style conflict markers."""
    o, b, t = (text or "" for text in texts)
    parts = [
        "<" * markers + " ours\n", o,
        "|" * markers + " base\n", b,
        "=" * markers + "\n", t,
        ">" * markers + " theirs\n",
    ]
    return "".join(ensure_newline(part) for part in parts)


def ensure_newline(text: str) -> str:
    """Terminate a non-empty conflict section so its marker starts a line."""
    return text if text == "" or text.endswith("\n") else text + "\n"


def merge_texts(base: str, ours: str, theirs: str, markers: int = 7) -> tuple[str, int] | None:
    """Structured merge of three SPEC texts; None when it must decline."""
    versions = [parse(text) for text in (base, ours, theirs)]
    if any(version.duplicates for version in versions):
        return None
    return Merger(*versions).run(markers)


def fallback(base_path: str, ours_path: str, theirs_path: str, markers: int) -> int:
    """git's own line merge, written over ours; returns its conflict status."""
    result = subprocess.run(
        [
            "git", "merge-file", f"--marker-size={markers}",
            "-L", "ours", "-L", "base", "-L", "theirs",
            ours_path, base_path, theirs_path,
        ],
        check=False,
    )
    return 1 if result.returncode != 0 else 0


def main(argv: list[str]) -> int:
    """Merge the three files git names; exit 1 when a conflict is left."""
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("base")
    parser.add_argument("ours", help="read, then overwritten with the result")
    parser.add_argument("theirs")
    parser.add_argument("path", nargs="?", default="SPEC.md")
    parser.add_argument("--marker-size", type=int, default=7)
    args = parser.parse_args(argv)
    texts = []
    for path in (args.base, args.ours, args.theirs):
        with open(path, encoding="utf-8", newline="") as handle:
            texts.append(handle.read())
    merged = merge_texts(*texts, markers=args.marker_size)
    if merged is None:
        print(f"merge_spec: {args.path}: structured merge declined, using git merge-file", file=sys.stderr)
        return fallback(args.base, args.ours, args.theirs, args.marker_size)
    text, conflicts = merged
    with open(args.ours, "w", encoding="utf-8", newline="") as handle:
        handle.write(text)
    if conflicts:
        print(f"merge_spec: {args.path}: {conflicts} conflict(s) left for you", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
