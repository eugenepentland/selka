# Deferred quote append experiment

User stopped optimization before adoption. This experiment is NOT integrated, NOT timed, and has no production/evidence commit. Root should gate common002 unchanged.

Worker src differences against common002 8b7d59eba are exactly two quote append_byte(34) → append_range(b"\"",0,1) replacements. Explicitly permitted compiler/span and CSV leaf commits were cherry-picked before build, so all other src files match common002. Existing guard/items production commits remain unchanged.

Fresh immutable runtime/count guests and installation are in .tmp/text-gaps/json-quotes; build-receipt.json lists all hashes. Both guests passed 50 unchanged oracle cases. Native assembly confirms opening and closing quotes use inline byte stores/capacity checks, retaining append fallback on growth. Five JSON counter cases have identical allocation/growth/copy/RC/live totals; push/appends operation differences retained in counter-comparison.json. New growth/escape/Unicode/output-independence fixture passed common002 baseline. Native candidate qualification status is recorded below; no further test/build/timing action is authorized.

Already-running native qualification: 56 invocations, 184 passed, 0 failed, 0 unsupported.
