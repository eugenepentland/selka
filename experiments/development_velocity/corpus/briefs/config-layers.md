# config-layers

Version: 1. Family: configuration. Kind: feature. Tier: small.

Request: {"layers":[OBJECT,...]}, at most 64 layers. A layer
may contain any subset of timeout, retries, enabled, label and no other fields.
Defaults are timeout=1000, retries=3, enabled=true, label="default". Non-null
values require timeout integer 0..60000, retries integer 0..10, enabled boolean,
and label ID. Null explicitly resets that field to its default. Apply layers
in source order; omitted fields preserve prior values. Return {"config":OBJECT,
"changed":[ID]} containing all four final fields and sorted field names whose
final value differs from its default.

Apply the shared PROCESS.md transport, type, schema and validation rules.
