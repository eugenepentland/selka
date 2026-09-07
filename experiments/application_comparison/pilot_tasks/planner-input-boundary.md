# Restore the exact input-size boundary

The planner has a regression: it rejects some otherwise-valid requests whose byte
length is exactly 1 MiB. Restore the v1 transport contract: exactly 1,048,576 input
bytes are allowed; larger requests return whole-request invalid-request. Input
length is measured in UTF-8 bytes, including trailing JSON whitespace.

Preserve strict JSON, Unicode scalar, nesting, integer and schema rules. Do not
increase the input budget or accept/truncate only a prefix of an oversized request.
The command must still exit zero for defined request errors.

Coordinator authoring: this task requires a narrowly seeded inclusive-boundary
regression in each baseline. Include valid requests just below/at/above the limit,
malformed requests at the boundary, multi-byte text and actual stdin execution.
The seeded variants and independent grading packs are not implemented yet.
