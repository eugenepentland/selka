# Exited-command orphan timeout

The command exits zero immediately after spawning a new-session descendant that
holds its output pipe open. The pre-repair capture reaches its 0.3-second timeout,
loses the exited command's descendant ancestry, and hangs in its second
`communicate()`. The outer two-second watchdog proves the hang. Its traceback,
the captured partial raw bytes (`orphan-partial`, byte `ff`, newline), fixture PIDs
and cleanup result are retained here. All three fixture-owned PIDs were killed
and reaped; none remained alive. No compiler or fuzz matrix ran.

`qualification_support.pre-repair.py.txt` was **reconstructed from recorded tool
calls; byte identity verified against the pre-repair hash**,
`b708dd0023ec89a5c2e156ee71027030116ce9e4355a76c157d6eab22769eb62`.
It is not a historical saved snapshot. `reconstruct.py` inverts the recorded
supervisor patch against `../qualification-source-freeze-06/`; it publishes bytes
only on that complete SHA256 match. The first reconstruction's whitespace error,
source and failed log remain retained; no mismatching helper was published.

Run `python3 replay.py --evidence /absolute/fresh/private/directory` to copy the
exact verified old helper and fixtures into an isolated directory and reproduce
the hang without replacing the corrected helper. The watchdog's zero status
means the historical hang was reproduced, not that qualification passed.

The correction gives each command a dedicated subreaper supervisor, so an exited
parent's orphan remains attributable during concurrent commands. Local selftests
05 and 06 retain the correction results: parent-alive nested sessions, exited
parent, raw partial bytes, and two concurrent survivors. Earlier tests and the
original red evidence remain unchanged.
