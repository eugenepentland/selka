# Classifying interface changes (internals)

Implementation detail moved out of the user guide, verbatim, under the same headings.

## `selka api-diff`

A v2 baseline has seven tab-separated
columns: identity, display name, kind, interface fingerprint, body fingerprint,
non-`from` interface fingerprint, and sorted source positions (`fresh` for none).
Positions are not limited to 64 parameters.
Component provider matching still requires the exact selected declaration;
API-diff's directional compatibility does not relax provider validation.
