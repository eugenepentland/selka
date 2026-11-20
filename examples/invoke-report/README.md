# Invoking a report export

A worked example of the invocation route, with no JSON plumbing on the guest
side: a library module with three exports, two of which a caller can invoke
directly. It is the plan's "text/list transformation returning a typed report",
and it is small on purpose — the point is the *shape* of the call, not the
arithmetic.

`report.selka` declares no `main`. That is deliberate: `selka invoke` supplies a
synthetic entry point, so an export is callable without a dummy `main` being
added to a library that does not want one.

## Discovering the contract

An agent does not have to read the source to call one of these. `--describe`
answers with the checked contract, the wire representation of each parameter,
the declared effects, the capabilities the export requires, the effective
limits, and whether the export can be invoked at all:

```console
$ selka invoke examples/invoke-report/report.selka --function 'report::headline' --describe
{"version":"native-invocation-v1","status":"ok","function":"report::headline",
 "identities":{...},"limits":{...},
 "describe":{"signature":"def report::headline(n: i64) -> str effects(managed_allocation)",
   "parameters":[{"name":"n","type":"i64","mode":"value","wire":"copied"}],
   "result":"str","effects":["managed_allocation"],"required_capabilities":[],
   "invocation":{"eligible":true,"reason":null,
     "wire":{"supported":true,"unsupported_path":null,"unsupported_detail":null}}}}
```

`eligible` is the field to read first. It is `true` here because every argument
is a copied value and the result is a copied managed list, which the boundary
carries in the return direction. An export that needed a filesystem, or that
returned a record, would answer `false` with the first blocking position and the
reason, rather than being advertised and then failing.

## Calling one

`--input` takes one JSON object of named arguments. Integers are canonical
decimal **strings**, so a 64-bit value survives a client whose numbers cannot
represent it:

```console
$ echo '{"n":"90210"}' > /tmp/report-request.json
$ selka invoke examples/invoke-report/report.selka --function 'report::headline' --input=/tmp/report-request.json
{"version":"native-invocation-v1","status":"ok","function":"report::headline",
 "identities":{...},"limits":{...},
 "outcome":{"status":"returned","value":"n=90210 sum=12","diagnostics":"","output":"","steps":...},
 "reason":null}
$ echo $?
0
```

A list result arrives as a JSON array of its elements, each in the declared
element form — decimal strings for `i64` — so the two exports answer in the two
shapes a caller can tell apart:

```console
$ selka invoke examples/invoke-report/report.selka --function 'report::digit_counts' --input=/tmp/report-request.json
"outcome":{"status":"returned","value":["2","1","1","0","0","0","0","0","0","1"], ...}
```

That array is the digit histogram of 90210: two `0`s, one `1`, one `2` and one
`9`, at the indices those digits name.

## The exports

| Export | Contract | Answers |
| --- | --- | --- |
| `report::headline(n: i64) -> str` | `effects(managed_allocation)` | A text report of the digits of `n` and their sum, built with `chr` and concatenation. |
| `report::digit_counts(n: i64) -> list[i64]` | `effects(managed_allocation)` | Ten counts, index `d` being how often digit `d` appears in `n`. |
| `report::render(value: i64) -> str` | private helper | Not an export, so `--function 'report::render'` is refused as an unknown name. |

Both exports take one integer, so both are callable with the same request file.
Neither needs external authority: allocating the result is the runtime's own
business, so nothing has to be granted.

## What this example does not show

The argument direction is integers only in this version. An export taking a
`str` or a `list[T]` describes as ineligible, with the reason naming the root
that materialising a guest value mid-request would need, and `--input` refuses
it with exit 2. See [calling one export](../../docs/tooling/invoke.md) for the
whole boundary.
