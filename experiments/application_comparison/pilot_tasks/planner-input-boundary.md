# Restore the exact input-size boundary

The planner has a regression: it rejects some otherwise-valid requests whose byte
length is exactly 1 MiB. Restore the v1 transport contract: exactly 1,048,576 input
bytes are allowed; larger requests return whole-request invalid-request. Input
length is measured in UTF-8 bytes, including trailing JSON whitespace.

Preserve strict JSON, Unicode scalar, nesting, integer and schema rules. Do not
increase the input budget or accept/truncate only a prefix of an oversized request.
The command must still exit zero for defined request errors.

Add regression coverage for requests just below, at and above the limit, including
multi-byte text and actual stdin execution. Preserve rejection of malformed JSON
at the boundary.
