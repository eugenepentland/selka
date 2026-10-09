import sys
variant = sys.argv[1]  # A: P1 today, B: one preserve_most call, C: preserve_most + inline immortal test
N = 12
cc = "" if variant == "A" else "preserve_mostcc "
out = ['target triple = "x86_64-unknown-linux-gnu"',
       f'declare {cc}void @myl_core_retain_slow(ptr) nounwind cold',
       'define i64 @work(ptr %blocks, i64 %v0, i64 %v1, i64 %v2, i64 %v3, i64 %v4) {',
       'entry:', '  br label %s0']
acc = ["%v0", "%v1", "%v2", "%v3", "%v4"]
for i in range(N):
    out += [f's{i}:',
            f'  %p{i} = getelementptr ptr, ptr %blocks, i64 {i}',
            f'  %blk{i} = load ptr, ptr %p{i}',
            f'  %cnt{i} = load atomic i32, ptr %blk{i} unordered, align 8',
            f'  %plain{i} = icmp ult i32 %cnt{i}, 2147483646',
            f'  br i1 %plain{i}, label %inc{i}, label %slow{i}, !prof !0',
            f'inc{i}:', f'  %n{i} = add nuw i32 %cnt{i}, 1', f'  store i32 %n{i}, ptr %blk{i}, align 8', f'  br label %done{i}']
    if variant in ("A", "C"):
        out += [f'slow{i}:', f'  %imm{i} = icmp eq i32 %cnt{i}, -1', f'  br i1 %imm{i}, label %done{i}, label %call{i}',
                f'call{i}:', f'  call {cc}void @myl_core_retain_slow(ptr %blk{i})', f'  br label %done{i}']
    else:
        out += [f'slow{i}:', f'  call {cc}void @myl_core_retain_slow(ptr %blk{i})', f'  br label %done{i}']
    new = [f'%x{i}_{k}' for k in range(5)]
    out += [f'done{i}:'] + [f'  {new[k]} = mul i64 {acc[k]}, {acc[(k+1)%5]}' for k in range(5)]
    acc = new
    out += [f'  br label %s{i+1}']
out += [f's{N}:', f'  %r1 = add i64 {acc[0]}, {acc[1]}', f'  %r2 = add i64 %r1, {acc[2]}', f'  %r3 = add i64 %r2, {acc[3]}', f'  %r4 = add i64 %r3, {acc[4]}', '  ret i64 %r4', '}',
        '!0 = !{!"branch_weights", i32 2000, i32 1}']
print("\n".join(out))
