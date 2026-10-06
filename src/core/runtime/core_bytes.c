/* S3-T2 owns mutable bytes and embedded blobs. The layout is the existing
   32-byte myl_block header plus raw octets; source admission remains refused.
   The S3-0 emitter uses the fail-closed IR placeholder until implementation. */
