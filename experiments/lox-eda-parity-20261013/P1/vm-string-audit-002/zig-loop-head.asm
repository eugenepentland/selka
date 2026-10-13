
/home/epentland/ai/canopy/mylang-memory-20261012/.tmp/lox-eda-20261012/reference-binaries/lox-zig-fast:     file format elf64-x86-64


Disassembly of section .text:

0000000001028db3 <main.main+0x28d3>:
vm.Vm.run():
/home/epentland/ai/canopy/mylang-worktrees/claude-parity-measure/.mylang-cache/lox/ports/zig/src/vm.zig:221
 1028db3:	49 8b 4d 00          	mov    0x0(%r13),%rcx
vm.readByte():
/home/epentland/ai/canopy/mylang-worktrees/claude-parity-measure/.mylang-cache/lox/ports/zig/src/vm.zig:426
 1028db7:	49 8b 04 24          	mov    (%r12),%rax
 1028dbb:	0f b6 0c 01          	movzbl (%rcx,%rax,1),%ecx
/home/epentland/ai/canopy/mylang-worktrees/claude-parity-measure/.mylang-cache/lox/ports/zig/src/vm.zig:427
 1028dbf:	48 8d 50 01          	lea    0x1(%rax),%rdx
 1028dc3:	49 89 14 24          	mov    %rdx,(%r12)
vm.Vm.run():
/home/epentland/ai/canopy/mylang-worktrees/claude-parity-measure/.mylang-cache/lox/ports/zig/src/vm.zig:222
 1028dc7:	ff 24 cd 00 07 00 01 	jmp    *0x1000700(,%rcx,8)
