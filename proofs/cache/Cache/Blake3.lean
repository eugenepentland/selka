/-!
# BLAKE3, so that `cacheplan` can observe files itself

The build's content digest is BLAKE3 (`src/core/fast_blake3.zig`, 32 bytes). `cacheplan replay` reads the files a
record lists and hashes them, so the digests it compares are its own, not a driver's. This is the reference
algorithm of the BLAKE3 paper (section 5), unkeyed, 32-byte output, in the order of the reference implementation.

It is **not proved**: it is trusted code, checked by `Cache.Blake3.selfTest` (the published test vectors) and by
the differential, in which it must reproduce the digests the Zig compiler recorded for the same bytes. The theorems
do not mention it; they assume only that *some* digest separates the contents seen (`CollisionFree`).
-/

namespace Cache.Blake3

def iv : Array UInt32 :=
  #[0x6A09E667, 0xBB67AE85, 0x3C6EF372, 0xA54FF53A, 0x510E527F, 0x9B05688C, 0x1F83D9AB, 0x5BE0CD19]

def perm : Array Nat := #[2, 6, 3, 10, 7, 0, 4, 13, 1, 11, 12, 5, 9, 14, 15, 8]

def chunkStart : UInt32 := 1
def chunkEnd : UInt32 := 2
def parentFlag : UInt32 := 4
def rootFlag : UInt32 := 8

@[inline] def rotr (x : UInt32) (n : UInt32) : UInt32 := (x >>> n) ||| (x <<< (32 - n))

@[inline] def g (s : Array UInt32) (a b c d : Nat) (mx my : UInt32) : Array UInt32 :=
  let s := s.set! a (s[a]! + s[b]! + mx)
  let s := s.set! d (rotr (s[d]! ^^^ s[a]!) 16)
  let s := s.set! c (s[c]! + s[d]!)
  let s := s.set! b (rotr (s[b]! ^^^ s[c]!) 12)
  let s := s.set! a (s[a]! + s[b]! + my)
  let s := s.set! d (rotr (s[d]! ^^^ s[a]!) 8)
  let s := s.set! c (s[c]! + s[d]!)
  s.set! b (rotr (s[b]! ^^^ s[c]!) 7)

def round (s : Array UInt32) (m : Array UInt32) : Array UInt32 :=
  let s := g s 0 4 8 12 m[0]! m[1]!
  let s := g s 1 5 9 13 m[2]! m[3]!
  let s := g s 2 6 10 14 m[4]! m[5]!
  let s := g s 3 7 11 15 m[6]! m[7]!
  let s := g s 0 5 10 15 m[8]! m[9]!
  let s := g s 1 6 11 12 m[10]! m[11]!
  let s := g s 2 7 8 13 m[12]! m[13]!
  g s 3 4 9 14 m[14]! m[15]!

/-- The compression function: the sixteen output words. -/
def compress (cv : Array UInt32) (block : Array UInt32) (counter : UInt64) (len flags : UInt32) : Array UInt32 := Id.run do
  let mut s : Array UInt32 :=
    #[cv[0]!, cv[1]!, cv[2]!, cv[3]!, cv[4]!, cv[5]!, cv[6]!, cv[7]!,
      iv[0]!, iv[1]!, iv[2]!, iv[3]!, counter.toUInt32, (counter >>> 32).toUInt32, len, flags]
  let mut m := block
  for r in [0:7] do
    s := round s m
    if r < 6 then
      m := perm.map fun i => m[i]!
  let mut out : Array UInt32 := Array.replicate 16 0
  for i in [0:8] do
    out := out.set! i (s[i]! ^^^ s[i + 8]!)
    out := out.set! (i + 8) (s[i + 8]! ^^^ cv[i]!)
  return out

/-- Sixteen little-endian words of a block (zero padded). -/
def words (b : ByteArray) (start len : Nat) : Array UInt32 := Id.run do
  let mut w : Array UInt32 := Array.replicate 16 0
  for i in [0:len] do
    let j := i / 4
    w := w.set! j (w[j]! ||| ((b.get! (start + i)).toUInt32 <<< (8 * (i % 4)).toUInt32))
  return w

/-- What a node would output: enough to give its chaining value or, as the root, the digest. -/
structure Output where
  cv : Array UInt32
  block : Array UInt32
  counter : UInt64
  len : UInt32
  flags : UInt32

def Output.chainingValue (o : Output) : Array UInt32 :=
  (compress o.cv o.block o.counter o.len o.flags).extract 0 8

def Output.root (o : Output) : ByteArray := Id.run do
  let out := compress o.cv o.block 0 o.len (o.flags ||| rootFlag)
  let mut bytes := ByteArray.empty
  for i in [0:8] do
    let w := out[i]!
    for k in [0:4] do
      bytes := bytes.push ((w >>> (8 * k).toUInt32) &&& 0xFF).toUInt8
  return bytes

/-- The output of one chunk (up to 1024 bytes) at chunk index `index`: the last block's output. -/
def chunkOutput (b : ByteArray) (start len : Nat) (index : UInt64) : Output := Id.run do
  let mut cv := iv
  let blocks := if len == 0 then 1 else (len + 63) / 64
  for k in [0:blocks - 1] do
    let flags := if k == 0 then chunkStart else 0
    cv := (compress cv (words b (start + 64 * k) 64) index 64 flags).extract 0 8
  let k := blocks - 1
  let blen := len - 64 * k
  let flags := (if k == 0 then chunkStart else 0) ||| chunkEnd
  return { cv, block := words b (start + 64 * k) blen, counter := index, len := blen.toUInt32, flags }

def parentOutput (left right : Array UInt32) : Output :=
  { cv := iv, block := left ++ right, counter := 0, len := 64, flags := parentFlag }

/-- The 32-byte BLAKE3 digest of `b`. -/
def hash (b : ByteArray) : ByteArray := Id.run do
  let n := b.size
  let chunks := if n == 0 then 1 else (n + 1023) / 1024
  let mut stack : Array (Array UInt32) := #[]
  for c in [0:chunks - 1] do
    let mut cv := (chunkOutput b (1024 * c) 1024 c.toUInt64).chainingValue
    -- merge completed subtrees: as many as `c + 1` has trailing zero bits
    let mut total := c + 1
    while total % 2 == 0 do
      let left := stack.back!
      stack := stack.pop
      cv := (parentOutput left cv).chainingValue
      total := total / 2
    stack := stack.push cv
  let last := chunks - 1
  let mut out := chunkOutput b (1024 * last) (n - 1024 * last) last.toUInt64
  for i in [0:stack.size] do
    let left := stack[stack.size - 1 - i]!
    out := parentOutput left out.chainingValue
  return out.root

def hexDigit (n : Nat) : Char := Char.ofNat (if n < 10 then 48 + n else 87 + n)

def hex (b : ByteArray) : String :=
  b.foldl (fun s x => s.push (hexDigit (x >>> 4).toNat) |>.push (hexDigit (x &&& 15).toNat)) ""

/-- The published test vectors: the empty input and the repeating 251-byte pattern at several lengths. -/
def selfTest : Bool :=
  let pattern (n : Nat) : ByteArray := ⟨(Array.range n).map fun i => (i % 251).toUInt8⟩
  hex (hash ByteArray.empty) == "af1349b9f5f9a1a6a0404dea36dcc9499bcb25c9adc112b7cc9a93cae41f3262" &&
  hex (hash (pattern 1)) == "2d3adedff11b61f14c886e35afa036736dcd87a74d27b5c1510225d0f592e213" &&
  hex (hash (pattern 1023)) == "10108970eeda3eb932baac1428c7a2163b0e924c9a9e25b35bba72b28f70bd11" &&
  hex (hash (pattern 1024)) == "42214739f095a406f3fc83deb889744ac00df831c10daa55189b5d121c855af7" &&
  hex (hash (pattern 1025)) == "d00278ae47eb27b34faecf67b4fe263f82d5412916c1ffd97c8cb7fb814b8444" &&
  hex (hash (pattern 31744)) == "62b6960e1a44bcc1eb1a611a8d6235b6b4b78f32e7abc4fb4c6cdcce94895c47"

end Cache.Blake3
