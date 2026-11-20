# Interface files (internals)

Implementation detail moved out of the user guide, verbatim, under the same headings.

## What the file contains

The same sources always render the same bytes, whether the cache is cold, warm
or disabled.

## Enforcing current files with `selka.json`

The bytes of every checked-in
interface file are part of the configuration identity that the verdict caches
use, so editing or deleting one never replays an earlier successful check.

and such a project's test
runs never replay a whole recorded report.
