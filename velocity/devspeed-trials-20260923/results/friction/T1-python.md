# FRICTION.md

Overall this task was low-friction: Python 3, standard library only, no
external docs to consult beyond TASK.md, and no compiler to fight (an
interpreted language, so `build.sh` is really just an install step). A few
points were worth stopping to think about; logged below in the requested
format.

1. **Unicode digit trap in `str.isdigit()`.** My first instinct for
   validating the count argument was `raw.isdigit()`. Before running
   anything I recalled (this is a known Python stdlib quirk, not something
   a tool told me) that `str.isdigit()` — and even `str.isdecimal()` — accept
   non-ASCII decimal digits (Devanagari `०-९`, fullwidth `５`, etc.), and
   `isdigit()` additionally accepts non-decimal digit-like characters such
   as superscript `¹`. The task says "decimal digits only," which I read as
   ASCII `0-9`. Fix: `raw.isascii() and raw.isdigit()`, with a unit test
   (`test_non_ascii_digit_rejected`) pinning it down. Cost: zero wasted
   attempts, since I caught it before running anything, but it's a one-line
   stdlib trap that's easy to miss — nothing in the names `isdigit`/
   `isdecimal` signals the Unicode behavior. Not a documentation gap in
   TASK.md (out of its scope); the stdlib itself is just quietly permissive
   here.

2. **No stated precedence between the three error conditions.** TASK.md
   gives three independent error rules (wrong arg count / bad count /
   unreadable file) but never says which one wins when more than one holds
   at once (e.g., only one argument given, and that argument also isn't an
   openable path). I picked arg-count first, then count format, then file
   readability, and moved on — a design decision, not a bug, so it cost no
   attempts, but it's exactly the kind of ordering a hidden test could
   disagree with me on. TASK.md was silent here, not misleading.

3. **`build.sh` is a formality for a scripting language.** The trial's
   contract ("build.sh produces an executable called `prog`") clearly
   assumes a compiled language. For stdlib Python there is nothing to
   compile, so `build.sh` just copies `wordfreq.py` to `prog` and chmods it.
   Not real friction — it took one line to realize and write — but it's a
   moment of "am I missing a step" before confirming there isn't one.

Nothing else slowed things down. Scanning the file's raw bytes for
`[A-Za-z0-9]+` instead of decoding it as UTF-8 first (since a "word" can
only ever be ASCII letters/digits, so every byte of a multi-byte UTF-8
sequence is already a separator byte) sidestepped decoding-error handling
entirely. Performance was never in question: a 10 MB file with ~500k
distinct tokens ranks in well under a second.

## Three changes ranked

1. **State precedence for overlapping error conditions in task specs.**
   When a spec gives N independent error rules, say what happens when more
   than one applies simultaneously. This is the single biggest source of
   "did I guess right" uncertainty in this task, and it's a one-sentence
   fix wherever a spec like this is written.
2. **When a spec says "digits only," call out ASCII vs. Unicode
   explicitly.** `str.isdigit()`/`isdecimal()` silently accept non-ASCII
   digit characters in Python — a well-known but easy-to-forget trap a spec
   author can pre-empt in one clause ("ASCII decimal digits only").
3. **Let scripting-language tracks skip the `build.sh` ceremony, or say
   explicitly what counts as "building" a script.** For an interpreted
   stdlib-only language there's no compiler to invoke, so the step is pure
   copy-and-chmod; a one-line note in TASK.md ("build.sh may simply
   install/copy your script under the required name") would remove the
   moment of doubt before realizing that's genuinely all there is to do.
