# Managed collections: internals

Maintainer detail moved out of the user guide [`docs/managed-memory.md`](../managed-memory.md). The headings match the
guide's, so its "How it works" links land here. The paragraphs are the guide's earlier text, unchanged. This folder is not
part of the published site.

### Slices are views

A slice `s[start:end]` is a read-only view of its source's text or octets.
Endpoints are Unicode scalar positions for `str` and byte positions for `bytes`
and `str` slices; negative positions trap and endpoints above the length clamp.
A view holds a pointer and a length. Creating one performs no allocation or RC.
`len()` reads it directly; text length and indexing scan UTF-8. Byte indexing
returns a scalar.

## Written copies (rule C)

Every guest build also checks its final module, beside the IR verifier and the ownership validator: a copy the
source did not write is an internal error `E_CORE_HIDDEN_COPY`, whose note names `--no-validate` as the way out
([certificate validators](../tooling/native-build.md#certificate-validators)). The check counts the frame block and the
dictionary-key copy and refuses neither (decision Q8 is open). The reads that take a text or bytes view in place are
the ones that keep it quiet: a `in` probe of a view needle or container, a whitespace split of a view, and a view used
as a dictionary key. `cost --sites` labels the same sites written, a named operation or implicit. See
`docs/tooling/cost.md`.
