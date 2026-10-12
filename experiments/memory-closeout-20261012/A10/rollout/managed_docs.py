from pathlib import Path
s=Path('docs/managed-memory.md').read_text()
start=s.index('Lists, dictionaries')
end=s.index('```mylang',start)
s=s[:start]+'''Lists, dictionaries, sets, strings and byte buffers live in managed storage.
The compiler checks ownership and inserts direct destruction; source code has no
allocator parameters or explicit frees. Assignments and owned returns can move a
value, ordinary parameters borrow, and `.copy()` makes independent storage.

'''+s[end:]
s=s.replace('mut alias = values','mut alias = values.copy()')
start=s.index('A list assignment or function argument')
end=s.index('Use `Node[]`',start)
s=s[:start]+'''The explicit copy lets `alias` grow while `values` remains usable and unchanged.
Appending grows capacity automatically. Managed element reads borrow from their
container; copy a selected child when an independent owner must escape. Use a
`mut` parameter with a marked call when a helper must change its caller's value.

'''+s[end:]
s=s.replace('Owned resources, provider\ncapabilities, and must-handle results cannot be hidden inside copyable lists. There\nare no interior pointers into managed storage.', 'Owned resources and provider capabilities cannot be hidden inside copyable lists.\nA list of Results still requires explicit handling of each selected result; a list\ndoes not turn an error into success. Borrowed views cannot escape their owners.')
start=s.index('The main-derived development worktree')
end=s.index('`try` transfers',start)
s=s[:start]+'''Every dynamic allocation has one owner and compiler-inserted destruction.
Assignments of managed values move ownership; `.copy()` requests independent
storage. Read-only text and byte views borrow a named owner and may cross calls
under a single-input return contract. Mutation or moving that owner while a view
is still used is rejected. Files and dependent capabilities use scoped providers.
A returned dependent owner needs one unambiguous input provider; escaping a local
provider or an ambiguous provider choice is rejected. Sharing and `.snapshot()`
are unsupported.

'''+s[end:]
s=s.replace('this prototype only splits the immediate fresh payload.', 'whole-field transfer only splits the immediate fresh payload.')
s=s.replace('for examples, allocation counts, and runtime comparisons.', 'for historical examples, allocation counts, and runtime comparisons. These old\nmeasurements are not results for the current compiler.')
s=s.replace('increase allocation. This is an opt-in prototype with a documented supported\nsubset; ordinary builds retain the rules elsewhere on this page.', 'increase allocation. The installed compiler components have a separate\nqualification boundary recorded in the closeout report; an ordinary guest default\nchange alone does not qualify the whole package as RC-free.')
s=s.replace('A managed object is released when its last owner goes away:', 'A managed object is destroyed when its owner goes away:')
s=s.replace('when its list is released. The compiler places every count and release', 'when its list is destroyed. The compiler places destruction')
s=s.replace('be allocation-free; a fixed-slot write may allocate when copy-on-write is needed.\nManaged mutation is not a promise of purity or exclusive access.', 'be allocation-free; independent copies and operations such as text encoding or\nbuffer reversal may allocate even when their result has the same length. Managed\nmutation is not a promise of purity. Mutable borrows remain exclusive.')
start=s.index('managed, so there is no allocator argument')
end=s.index('```mylang',start)
s=s[:start]+'''managed, so there is no allocator argument to thread and no free to write.
Assignment can move the owner; ordinary arguments borrow. Elements can include
scalars, records, strings, byte strings, managed collections and Results. Resources
and provider capabilities remain outside ordinary list storage. A selected managed
element borrows the container; `.copy()` creates an independent value when needed.

'''+s[end:]
s=s.replace('`copy()` returns a fresh shallow list', '`copy()` returns an independent list and recursively copies managed children')
s=s.replace('hashed and compared structurally and copied into the table;', 'hashed and compared structurally and owned by the table;')
s=s.replace('fallback; `counts.copy()` returns a fresh shallow dictionary;', 'fallback; `counts.copy()` returns an independent dictionary and recursively copies managed children;')
s=s.replace('Those fields.', 'Those fields.')
s=s.replace('those fields. Assignment copies a dictionary value; only a `mut` parameter and marked call write back to a caller.', 'those fields. Assignment can move a dictionary owner; use `.copy()` for an\nindependent dictionary. A `mut` parameter and marked call write back to a caller.')
s=s.replace('        order.append(name)', '        order.append(name.copy())')
s=s.replace('        keys.append(name)', '        keys.append(name.copy())')
s=s.replace('## Experimental zero-RC ownership\n\n`mylang run app.my --experimental-zero-rc` enables the ownership prototype.', '## Checked ownership\n\nOrdinary commands use checked ownership.')
s=s.replace('allocation and growth still occur. Strings sliced in this stage produce owned\nresults. The Stage 2 prototype also provides explicit borrowed ranges.', 'allocation and growth still occur. String slices produce owned results. Explicit\nborrowed ranges avoid that materialization when a local view is sufficient.')
s=s.replace('This mode supports owned dictionaries', 'The checked contract supports owned dictionaries')
s=s.replace('The earlier `--experimental-single-owner` mode remains available separately.\nSee the [prototype stages and measurements](../experiments/zero-rc-20261011/README.md).', 'Historical [prototype stages and measurements](../experiments/zero-rc-20261011/README.md)\ndescribe older revisions, not a current compatibility mode.')
s=s.replace('### Borrowed text and byte ranges (experimental Stage 2)', '### Borrowed text and byte ranges')
s=s.replace('With `--experimental-zero-rc`, `.borrow(start, end)` produces a read-only', '`.borrow(start, end)` produces a read-only')
s=s.replace('Prototype limits: view bindings and parameters are immutable.', 'View bindings and parameters are immutable.')
s=s.replace('is still refused by zero-RC mode.', 'is refused by the checked ownership contract.')
s=s.replace('### Explicit values and scoped parallel work (experimental closeout)', '### Explicit values and scoped parallel work')
s=s.replace('`.copy()` also accepts records, enums, options and fixed arrays. In zero-RC mode\nit recursively duplicates owned children; scalar copies simply preserve their\nvalue. Resources and move-only values cannot be copied. Ordinary builds preserve\nvalue semantics with their existing copy-on-write behavior.', '`.copy()` also accepts records, enums, options and fixed arrays. It recursively\nduplicates owned children; scalar copies simply preserve their value. Resources\nand move-only values cannot be copied.')
s=s.replace('Zero-RC map borrows', '`parallel.map` borrows')
s=s.replace('Unit elements. Ordinary RC builds execute the standard function sequentially.\nThe prototype creates task, capture and result storage for each element; it is\nintended for testing ownership and parallel work, not for accelerating tiny\ncallbacks. Heap allocation and scheduling synchronization remain.', 'Unit elements. Heap allocation and scheduling synchronization remain. Output\nstorage and independently owned callback results can grow with input size; a\nreduction in scheduling overhead is not a claim of allocation-free parallel work.')
s=s.replace('```text\nmut text = "hello" + str(7)\nconst saved = text.copy()\ntext += "!"\n# saved remains "hello7"; text is "hello7!"\n```', '''```mylang
# doc: expect hello7
# doc: expect hello7!
func main(out: Stream) -> int:
    mut text = "hello" + str(7)
    const saved = text.copy()
    text += "!"
    out.print(saved)
    out.print(text)
    return 0
```''')
s=s.replace('```text\nfunc segment', '```mylang\n# doc: expect λz7\n# doc: expect λz7\nfunc segment')
s=s.replace('func example(out: Stream):\n    mut text', 'func main(out: Stream) -> int:\n    mut text')
s=s.replace('    # out.print(part)               # compile error: owner changed\n```', '    # out.print(part)               # compile error: owner changed\n    return 0\n```')
s=s.replace('```text\nimport parallel', '```mylang\n# doc: expect 1\n# doc: expect item-1\nimport parallel')
s=s.replace('func example(out: Stream):\n    const input', 'func main(out: Stream) -> int:\n    const input')
s=s.replace('    out.print(input[0], output[0])\n```', '    out.print(input[0])\n    out.print(output[0])\n    return 0\n```')
Path('experiments/memory-closeout-20261012/A10/rollout/managed-memory-C2.md').write_text(s)
