
experiments/new-core-s4-emission-20261006/entry-attributes-01/result_propagate/baseline/program:     file format elf64-x86-64


Disassembly of section .text:

000000000103270a <myl_core_err_trace_append_preserve_most>:
 103270a:	55                   	push   %rbp
 103270b:	48 89 e5             	mov    %rsp,%rbp
 103270e:	51                   	push   %rcx
 103270f:	50                   	push   %rax
 1032710:	4c 8d 1d 51 62 02 00 	lea    0x26251(%rip),%r11        # 1058968 <error_trace>
 1032717:	48 8b 05 52 62 02 00 	mov    0x26252(%rip),%rax        # 1058970 <error_trace+0x8>
 103271e:	48 8d 48 01          	lea    0x1(%rax),%rcx
 1032722:	83 e0 1f             	and    $0x1f,%eax
 1032725:	49 89 7c c3 10       	mov    %rdi,0x10(%r11,%rax,8)
 103272a:	48 89 0d 3f 62 02 00 	mov    %rcx,0x2623f(%rip)        # 1058970 <error_trace+0x8>
 1032731:	58                   	pop    %rax
 1032732:	59                   	pop    %rcx
 1032733:	5d                   	pop    %rbp
 1032734:	c3                   	ret

Disassembly of section .init:

Disassembly of section .fini:

Disassembly of section .plt:
