# Pinned scalar CPU profile receipt

Authorized command from P2 worktree after sourcing dev-env.sh and exporting shared MYLANG_SLOT_DIR:

```bash
scripts/build-slot.sh timing timeout 58 taskset -c 8 python3 experiments/lox-eda-parity-20261013/P2/scalar-profile-001/profile.py
```

Initial ticket1326 (PID285094) admitted after85 s. Installed perf does not support --log-fd, so it exited129 before the C1 guest. The failed script, complete fresh calibration receipt and error text are retained as failed-log-fd-*; no profile samples came from that attempt.

Corrected ticket1338 (PID287446) admitted after5 s and completed0. A tiny exec wrapper redirects guest stderr into a separate file; perf stderr has its own log. Exact guest stdout/stderr are verified. A new process group encompasses perf and exec guest, killed and waited on timeout. DEBUGINFOD_URLS is empty. Script SHA, compiler/input/binary pins, actual perf argv, fresh Zig 2warmup+5measured calibration and 3x median per-guest cutoff are in receipt.json. Both guests completed without censoring. The profile elapsed times are diagnostic and not benchmark benefit estimates.

Perf cycles:u -F997 is available. C1 collected1419 samples; scalar collected1227. Both have zero lost samples. Decode/annotation ran outside timing admission; raw .data and decoded reports are preserved.

| Symbol | C1 share | Scalar share |
|---|---:|---:|
| vm.run |45.08%|50.57%|
| vm.read_byte |24.99%|20.29%|
| vm.read_constant |8.85%|7.35%|
| vm.call_value |6.20%|7.00%|
| vm.read_short |4.54%|4.55%|

These relative shares do not independently establish speedups. Reader cost remains material. Scalar run annotation attributes11.00% of run samples to the indirect dispatch jump,7.43% to frame-index arithmetic and7.36% to a frame-publication-path stack load. Scalar byte annotations concentrate on prologue31%/27% split across kind-check/prologue and checkedIPincrement23%; constant annotations concentrate on prologue22%, code operand load17%, kindcheck16%, constant Value loads15%/14%. Instruction-level sampling can skid; do not interpret these exact percentages as isolated instruction cost or remove checks on that basis.

Native/LLVM observations in static-observations.md explain why apparent whole Runtime mutation signatures do not support a whole-record ABI optimization. No further source changes are proposed here.
