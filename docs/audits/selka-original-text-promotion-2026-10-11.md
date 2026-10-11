# Original text fixture promotion

The original `profile_text_method.input`, `bytes_encode_profile.input` and `bytes_decode_profile.input` match ROOT `cce6c1e83c1ceea88f650276f8ceaa96365c67b9` byte-for-byte; the receipt records equal local/ROOT SHA256 values. All three returned 7 under native, shadow and component execution, both ordinary and `--release --verify-facts` builds, with leak checking enabled. Checks and complete typed dumps also matched exactly: 36 operations passed, zero failures or skips.

The manifest promotes only these three entries from profile refusal to managed text success. The exact refusal-set test removes only these names and asserts their complete promoted contracts. Source bytes and all other selected cases remain unchanged. Proof uses the already qualified text deployment (native host `6841548b…`, body artifact `c9f70cac…`); no broader inventory rerun or complete bootstrap claim is made.

The focused Python suite passed 20 tests and full Guardian passed 88 checks. An initial test-update attempt ran 20 tests with two failures: the final decode name remained in the refusal set and current B6 status counts still expected 10 successes. Both were corrected; historical B6 counts and its complete case inventory remain unchanged. That failed log is archived, and Guardian did not execute in the failed chained command.
