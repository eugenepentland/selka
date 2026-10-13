
/home/epentland/ai/canopy/mylang-memory-20261012/.tmp/lox-eda-20261012/reference-binaries/lox-zig-fast:     file format elf64-x86-64


Disassembly of section .text:

0000000001029e74 <main.main+0x3994>:
value.valuesEqual():
/home/epentland/ai/canopy/mylang-worktrees/claude-parity-measure/.mylang-cache/lox/ports/zig/src/value.zig:55 (discriminator 2)
 1029e74:	80 fa 03             	cmp    $0x3,%dl
 1029e77:	75 25                	jne    1029e9e <main.main+0x39be>
/home/epentland/ai/canopy/mylang-worktrees/claude-parity-measure/.mylang-cache/lox/ports/zig/src/value.zig:51 (discriminator 2)
 1029e79:	c4 e1 f9 7e ca       	vmovq  %xmm1,%rdx
/home/epentland/ai/canopy/mylang-worktrees/claude-parity-measure/.mylang-cache/lox/ports/zig/src/value.zig:55 (discriminator 8)
 1029e7e:	c4 e1 f9 7e c6       	vmovq  %xmm0,%rsi
 1029e83:	39 f2                	cmp    %esi,%edx
 1029e85:	eb 12                	jmp    1029e99 <main.main+0x39b9>
/home/epentland/ai/canopy/mylang-worktrees/claude-parity-measure/.mylang-cache/lox/ports/zig/src/value.zig:47
 1029e87:	80 fa 01             	cmp    $0x1,%dl
 1029e8a:	75 12                	jne    1029e9e <main.main+0x39be>
/home/epentland/ai/canopy/mylang-worktrees/claude-parity-measure/.mylang-cache/lox/ports/zig/src/value.zig:45 (discriminator 6)
 1029e8c:	c4 e1 f9 7e ca       	vmovq  %xmm1,%rdx
/home/epentland/ai/canopy/mylang-worktrees/claude-parity-measure/.mylang-cache/lox/ports/zig/src/value.zig:47 (discriminator 6)
 1029e91:	c4 e1 f9 7e c6       	vmovq  %xmm0,%rsi
 1029e96:	40 38 f2             	cmp    %sil,%dl
 1029e99:	0f 94 c2             	sete   %dl
 1029e9c:	eb 02                	jmp    1029ea0 <main.main+0x39c0>
vm.Vm.run():
 1029e9e:	31 d2                	xor    %edx,%edx
 1029ea0:	48 01 c8             	add    %rcx,%rax
heap.Runtime.push():
/home/epentland/ai/canopy/mylang-worktrees/claude-parity-measure/.mylang-cache/lox/ports/zig/src/heap.zig:115
 1029ea3:	88 10                	mov    %dl,(%rax)
 1029ea5:	c6 40 08 01          	movb   $0x1,0x8(%rax)
/home/epentland/ai/canopy/mylang-worktrees/claude-parity-measure/.mylang-cache/lox/ports/zig/src/heap.zig:116
 1029ea9:	48 ff 85 b0 f6 ff ff 	incq   -0x950(%rbp)
vm.Vm.run():
/home/epentland/ai/canopy/mylang-worktrees/claude-parity-measure/.mylang-cache/lox/ports/zig/src/vm.zig:405
 1029eb0:	e9 fe ee ff ff       	jmp    1028db3 <main.main+0x28d3>
