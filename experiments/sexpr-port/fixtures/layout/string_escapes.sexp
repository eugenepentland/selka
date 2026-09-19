; layout fixture: strings carrying backslash escapes. The tokenizer captures the
; raw slice between the quotes, so the printer must write it back byte-for-byte
; and the estimated width counts the escaped spelling, not the decoded value.
(strings
  "plain"
  "escaped \"quote\""
  "back\\slash"
  "tab\there"
  "new\nline"
  "brace { and } bracket [ ]"
  "percent 10% and amp &")
