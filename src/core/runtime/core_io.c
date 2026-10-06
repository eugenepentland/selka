/* S3-C runtime boundary. Algorithms will be ported from qbe_io/files/grants/
   providers/resources/host_runtime into this translation unit, never linked.
   This identity probe exercises runtime-C token passage without acquiring
   authority or touching a host provider. */
int64_t myl_core_s3_token_roundtrip(int64_t token) { return token; }
