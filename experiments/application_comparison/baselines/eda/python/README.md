# Python EDA inspector baseline

Independent Python standard-library implementation of
[`eda-inspector-v1.md`](../../../contracts/eda-inspector-v1.md).
Uses the workflow planner contract's transport rules. This is unscored baseline
construction; no coordinator oracle, oracle tests, other baseline implementations,
or trial artifacts were consulted.

Run with Python 3.9 or newer:

```sh
python3 -B inspector.py < request.json
python3 -B -m unittest -v
```

The CLI reads at most 1 MiB plus one detection byte from stdin and emits one JSON
response. JSON container nesting is limited to 64 levels, with the root
container counting as one and string contents ignored. Over-depth input rejects
the whole request before schema validation. Every decoded JSON string and object
key must contain only Unicode scalar values: unpaired surrogate escapes reject
the entire request; valid surrogate pairs proceed to schema validation. Defined input errors exit zero. It requires no packages, subprocess
helpers, external files, or network at runtime. Tests use subprocesses only to
exercise the CLI itself.

`inspector.py` owns strict JSON decoding, complete schema and ordered semantic
validation, micrometer conversion, clearance and boundary rules, connectivity,
half-perimeter spans, and exact SVG serialization. Geometry uses Python integers;
input integers are restricted to signed 64-bit. Component, net, reference, and
finding ordering is deterministic, independent of input array order.

Tests cover transport corruption and size boundaries, schema and phase precedence,
namespace separation, reference deduplication, clearance equality and touching,
positive-area overlap, signed coordinates, scaled geometry, center rounding,
exact SVG, nonmutation and permutation invariance, and CLI exit behavior.

Interpretation notes: exponent-form numbers that overflow to infinity are rejected
as nonfinite input. Finite JSON floats remain floats and fail integer schema fields.
Malformed JSON or container nesting above 64 produces `invalid-request`. UTF-8 BOM
is rejected as malformed JSON. These choices follow strict UTF-8 JSON handling;
no product behavior required an additional assumption.
