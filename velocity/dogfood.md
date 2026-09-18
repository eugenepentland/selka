# Programs to port to mylang, one per week

Each port is a lane A "use" run performed by the improver itself: write the program in
mylang from the description, verify it against the original, and file every stumble as a
friction record under `velocity/friction/` before fixing anything. The point is the
friction, not the port.

1. `scripts/navigate.py`: callers, callees and impact over `index-project` JSON.
2. `velocity/gen_project.py`: the seeded synthetic project generator.
3. A JSON pretty-printer over the standard `json` module with a `Filesystem` capability.
4. `scripts/laws.py`: the executable-law runner.
5. The friction classifier: read `friction-v1` lines, apply `classifier.json`, print counts.
6. A Markdown table formatter that pads columns, reading stdin and writing stdout.
7. The idiom-suite runner for lane C, minus the CPython oracle call.
