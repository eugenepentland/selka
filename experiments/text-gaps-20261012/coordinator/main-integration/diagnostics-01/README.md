# Native failure capture

Gate 02 failed the numeric and live-iteration native wrappers after both passed
gate 01. Their assertions did not print subprocess diagnostics. The production
compiler was unchanged for these focused reruns; only failure reporting in the
two wrappers was added. No concrete ownership or cache-path defect was found.

The compiler-filtered binary selects exactly two tests. One focused run and
12 repetitions at two concurrent processes passed (26 selected test executions,
351 guest-test subprocess invocations). Each wrapper covers debug, release,
and release with verified facts. This does not establish the cause of the two
earlier failures; the complete gate must run again with the richer diagnostics.

An initial attempt to filter the unfiltered binary at runtime selected unnamed
blocks too. That broad diagnostic attempt was stopped; it is not counted as a
passing test run. The repeat evidence below uses compiler-applied filters.
