# Short-input join copy loop

This separate candidate starts from dfcb900be5c56ac3634620e9e672057e50c4ba41,
whose production inputs are equivalent to accepted combined text f994742d/d9.
The d9 compiler, source, guests, native helpers and measurements remain immutable.

The actual d9 LLVM join body repeats the separator's nonempty/16/8/4/2-byte
decisions for each gap, reloads its octets and carries a byte offset plus the
output base. The proposed general short-input path chooses the separator's
bounded word band and endpoints once, and advances one output pointer through
a leaf containing only fixed-size copies. The existing checked sizing pass
also proves every part and the separator have at most sixteen octets. This is
the original short-copy threshold, applied to arbitrary inputs rather than
particular benchmark literals. The mixed/long path retains the original loop.

Checked separator multiplication, checked byte accumulation, scalar counts,
ASCII/index publication, allocation shape/count, roots and refusal order stay
the same. Empty separators are never read. Word loads and overlapping stores
remain inside the exact view/owned payload bounds. The output is fresh and
distinct from the read-only inputs; the helper cannot allocate or collect.

Focused correctness extends exact-allocation separator widths to every value
from zero through eighteen, and retains unaligned Unicode/ASCII view coverage,
empty/singleton inputs, collection pressure and overflow refusals. Another684
oracle outcomes use2/17/64 mixed-width pieces, including empties, either wholly
short or with one seventeen-octet piece that must use the general path. Existing
five text/RC sanitizer suites remain the intended native checks. Actual RF
guests and a matched d9 screen must establish code shape and profitability.

All five native suites pass at -O3 under ASan+UBSan, including684 mixed-width
oracle outcomes,31104 retained search outcomes and53 native RC collection cases.
The native log and receipt retain commands, flags and source/log identities.
Fresh compiler/guest build and actual-code inspection still precede timing;
there is no profitability or RF acceptance claim. This is the last text
candidate before the next integrated RF milestone.

The six-arm5r1w screen passes360 samples and720 fresh qualifications: LLVM join
is the current fastest at168.049ns small and5827.498ns large. The matched d9
comparison passes288 outcomes: LLVM join0.66659/0.46578 after/before, with all
ten controls0.98973..1.00795. An independent15r3w repeat passes216 outcomes:
small join237.874 to157.853ns (0.66360), large join12240.259 to5679.631ns
(0.46401), large search84.229 to83.720ns (0.99395). All artifact hashes stay
unchanged. The coordinator adopts the production/test delta at6cf7bdce for a
fresh integrated RF milestone; no normal RF confirmation follows from these
Debug-host screens. Small equality, parsing and formatting remain open.

Actual join_short contains no calls in either backend and no LLVM stack memory
references; its1605-byte body saves rbp/rbx. Native join grows1229 to1352bytes.
The three bulk memcpy sites remain with the general path. Scanner/index/shared
kernel normalized instructions and entry mod64 values remain identical to d9;
entries shift64bytes, scanner stays aligned, kernel stays14135bytes. This is
emitted-work evidence, with remaining layout interactions explicitly retained.

evidence.json binds45 compressed raw artifacts and6 scripts, plus the committed
native log/receipt. It retains source/compiler/guest identities, exact commands,
fresh400 text records, all24 source/assets/artifact validations, emitted code,
screen/pair/repeat and Guardian logs. The archive gate passes all88 whole-tree
checks with existing report-only findings and no policy change.
