# Expanded compute contract v1

Standalone single-threaded programs accept `CASE SIZE ITERATIONS SEED`. SIZE >= 2,
ITERATIONS >= 1, 1 <= SEED <= 1000000. The measured profiles use sizes 64/4096 for
micro cases except binary_search (16/256); packet_decode is an application case
(16/256). Every CLI iteration is one complete pass over SIZE fixtures. Output is
exactly `CHECKSUM ELAPSED_NS\n`, both decimal integers, with positive monotonic
elapsed nanoseconds and zero process status. All implementations use ordinary
native allocations, safe collection indexing, signed 64-bit scalar arithmetic,
and f64 for floating calculations. Bench fixtures and checksums remain within
signed 64-bit arithmetic. No compiler changes, barriers, forced noinline, custom
allocators, threads, or unsafe collection indexing are used.

Before timing, resolve CASE to a numeric discriminator and build:

- values[j] = (SEED + j*37) % 1009.
- ordered[j] = j*3 + SEED%11.
- records[j] = Triple(a=values[j], b=values[j]%17, c=values[j]*3%101).
- flags[j] = j%16 != 0 for branch_predictable; otherwise
  (values[j]*73 + j*19 + SEED)%101 < 50 for branch_mixed.
- SIZE independent immutable byte frames described below.
- indirect callable = affine_a if SEED%2 == 0, else affine_b.

All ports prepare these arrays before the start timestamp. Unused fixtures
are likewise outside timing. Initialize checksum=0 before timing. During each
batch b in [0, ITERATIONS), set phase=b%17; visit j=0..SIZE-1 and compute the
case's value from x=values[j] and add it to pass_total initialized to zero for
that batch. After the pass, fold checksum=(checksum+pass_total)%1000000007.
There is one checksum remainder per whole pass, preserving the original final
checksum while avoiding a remainder in every elementary operation. The maximum
float value is 1065024; even a 4096-element pass totals at most 4362338304,
well within signed64. Other profiles likewise remain bounded.
The finish timestamp follows the final fold; output formatting and fixture
destruction are outside timing. Dynamic dispatch and ordinary helper calls may
inline, simplify, or hoist naturally. The checker/oracle is never timed.

## Cases

| CASE | Value for each fixture |
| --- | --- |
| integer_math | (((x+phase)*17+23)//7)%1009 |
| float_math | int(((float(x)/8 + float(phase)/4)*(float(x)/16+1) + 0.5)*128) |
| branch_predictable, branch_mixed | (x+phase)*3+1 when flags[j], otherwise (x+phase)*5+7 |
| record_construct | Construct Triple(x+phase, x%17, (x*3+phase)%101); ordinary helper reads a+3*b+5*c |
| record_update | Copy records[j] by value, assign its a, b, c to the same three expressions as record_construct, then ordinary helper reads a+3*b+5*c; stored fixture remains unchanged |
| call_direct | Ordinary direct call affine_a(x+phase), where affine_a(v)=3*v+7 |
| call_indirect | Invoke runtime-selected first-class callable(x+phase); affine_b(v)=5*v+11. Selection occurs outside timing; even seed makes direct/indirect numeric work equal |
| option_handle | Ordinary helper returns None when x%4==0, otherwise Some(x+phase). Match None to 19, Some(v) to 3*v+1 |
| result_propagate | First helper returns Err(1) when x%5==0, otherwise Ok(x+phase). Second helper propagates Err unchanged and transforms Ok(v) to Ok(3*v+1). Caller matches Ok(v) to v, Err(e) to 7*e |
| binary_search | Search ordered for key=(x+phase)%(SIZE*3+3)+SEED%11; successful zero-based index + 1, otherwise 0 |
| packet_decode | Validate and decode frames[j]; successful record identifier+3*payload_sum+length, otherwise error_code*101 |

Float math is exact: all division factors and arithmetic operands are dyadic;
all intermediates are far below f64's exact 53-bit significand limit. Scaling by
128 produces an exact nonnegative integer. The integer checksum has exact equality
across ports; no tolerance comparison, decimal float formatting, or fast-math
mode is needed. Fused multiply/add would give the same result for these fixtures.

Binary search implements lower_bound with low=0, high=SIZE, repeatedly taking
middle=(low+high)//2 and updating low=middle+1 when ordered[middle]<key, otherwise
high=middle. Check the final candidate with safe indexing. Inputs include both
present and absent keys; zero encodes absence without allocation.

Options use native Option/optional values in mylang, Rust, Zig and an explicit
presence/value struct in Go. Results use fixed logical error code 1 and ordinary language propagation:
mylang/Rust native Result and `?` forwarding, Zig native error{Invalid}!i64 with
`try` forwarding, Go's conventional (value,error) return with explicit early
return. The Go sentinel error is allocated before timing. Caller maps the fixed
failure to 7. Success and failure ratios are determined by x residues,
approximately 3/4 and 4/5.

## Packet application

The binary protocol is an unsigned byte frame with a two-byte big-endian
identifier, payload length, payload and additive checksum. For fixture j:

- identifier=(SEED+j*17)%65536.
- payload[k]=(SEED+j*13+k*7)%256 for k=0..3.
- Initial frame = [165, 1, identifier//256, identifier%256, 4, payload[0],
  payload[1], payload[2], payload[3], sum(first nine bytes)%256].
- j%4==0: retain valid frame.
- j%4==1: change magic byte to 164 (error 1).
- j%4==2: increment checksum byte modulo 256 (error 4).
- j%4==3: change declared payload length to 5 (error 3).

Within timing, ordinary decode helper validates: at least six bytes (error 3),
magic=165 (error 1), version=1 (error 2), actual length=declared length+6 (error 3),
checksum=sum(all prior bytes)%256 (error 4), in that order. Only then it decodes
identifier and sums payload bytes into a returned Packet record. The caller
matches the result and folds success fields or the numeric error as specified.
The fixture contains a 1/4 valid mix plus three separately invalid conditions;
version validation is executed on fixtures passing the magic test. Frame
materialization is excluded; byte validation, payload traversal, returned records
and result handling are included.

## Oracle and qualification

`oracle.py` exports CASES metadata and checksum(case,size,iterations,seed).
Because per-pass phase has period 17 and no fixture is mutated, it independently
sums each of seventeen phases and uses quotient/remainder to fold complete
cycles. It avoids Python iteration proportional to large calibrated counts.
Qualification covers every case with sizes 2/3/17, seeds 1/42/999983 and counts
1/7/31. Compare all six arms (mylang LLVM O3/full LTO and QBE, Rust, Go,
Zig ReleaseSafe and ReleaseFast) to the oracle before publishing timing.

This suite intentionally permits optimized records/calls/results to collapse
into simpler code. Such equivalence is a useful optimizer result; do not add
barriers to defeat it or interpret results as allocation measurements.
