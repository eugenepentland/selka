# Complete tuple staging

Checked tuple destructuring consumes the whole right-hand side once and stages all fields before target effects. Ignored owners are destroyed, named fields become independent owners, and dependent resource fields preserve their provider origin. Ordinary RC mode uses nondestructive field projections. A shared bounded validator checks initialize-only metadata, the exact tuple type/arity, hidden unavailable staging locals, exact field types and unique destinations before checking or lowering. Typed dumps display staged slots and explicit ignored fields.

Five focused tests and Guardian 88 passed. Native managed and resource cases passed unoptimized debug and verified release; an ordinary borrowed-input control passed. Full provider and pending Result qualification remains on the integrated compiler with A01 frontend/consumer and A08 cache v8 dependencies. Raw failures, final logs and precise source hashes are recorded here.
