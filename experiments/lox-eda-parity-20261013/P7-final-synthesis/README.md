# Prepared final evidence synthesis

No C3 report extraction or timing has run. This helper reuses root summarize.render unchanged and follows C1 managed-summary positive-pair ratios, with zero/unmatched cases explicit. Runtime ratios, process RSS, instrumented allocations/copy traffic/peak/exit-live, allocator movement and optional compilation receipts remain separate. It preserves all60cases (13tree/13VM/34EDA), censor statuses and paired denominators; incomplete observations never produce synthetic ratios.

After coordinator authorizes final extraction:
```
python3 experiments/lox-eda-parity-20261013/P7-final-synthesis/synthesize.py \
  --root /home/epentland/ai/canopy/mylang-text-gaps-main-20261012 \
  --attempt runtime-003 \
  --output experiments/lox-eda-parity-20261013/P7-final-synthesis/extracted-001
```
Add repeatable `--manifest ABSOLUTE_JSON_PATH` for exact initial source/native/common receipts, and repeatable `--compilation-receipt ABSOLUTE_JSON_PATH` for existing compile observations. Without supplied compilation receipts the field remains empty, never guessed. Output must be a new directory inside this worker and outside root.

Pins self/summarizer/report/configuration/pins and every referenced raw counted/qualification record at first read and before publication. Embedded counted data must equal raw files. Preserves manifest bytes as snapshot strings; writes private pending output then completion receipt/marker and renames only after validation. Disables import bytecode writes when reusing root summarizer. This is synthesis of an already validated pipeline report, not a replacement full artifact validator.

Three read-only Python tests passed: positive/zero/missing managed denominators, failed-metric exclusion, synthetic60case publication/censor preservation/refusal of existing output/root writes. Synthetic integration uses only root summarize.py; it does not read pending C3 results. Syntax/interface checked. No production changes/native work/timing.
