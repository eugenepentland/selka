# little-endian-read

Version: 1. Family: binary-codecs. Kind: bugfix. Tier: small.

Request: {"hex":HEX,"offsets":[INT,...]}. HEX is
even-length lowercase hexadecimal encoding 0..512 bytes. Offsets range 0..512.
After complete schema validation, if any offset lacks two available bytes,
return {"error":"out-of-bounds"}, without partial values. Otherwise return
{"values":[INT]} by reading unsigned LITTLE-ENDIAN 16-bit values at each
requested offset, retaining duplicate/overlapping offsets and source order.
Empty offsets succeeds even for empty hex. Fix only the supplied starter's
byte-order defect using the standard encoding facility.

Apply the shared PROCESS.md transport, type, schema and validation rules.
