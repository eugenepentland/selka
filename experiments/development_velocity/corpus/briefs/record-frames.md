# record-frames

Version: 1. Family: binary-codecs. Kind: feature. Tier: small.

Request: {"records":[{"tag":INT,"data":HEX},...]}, at most
32 records. tag ranges 0..255; data is an even-length lowercase hexadecimal
string encoding at most 32 bytes (empty allowed). Each frame is one tag byte,
a two-byte unsigned LITTLE-ENDIAN payload length, then the payload. Concatenate
frames without separators. Return {"hex":HEX,"offsets":[INT]} with lowercase
wire hex and the starting byte offset of every frame. No checksum or terminator.
Empty records gives empty hex and offsets.

Apply the shared PROCESS.md transport, type, schema and validation rules.
