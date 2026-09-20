
.tmp/llvm-streaming-20260919/final/maxperf-text-safe/compact-o3.bin:     file format elf64-x86-64


Disassembly of section .init:

Disassembly of section .plt:

Disassembly of section .text:

0000000000403e90 <myl_f_22a60c4dacd8f24cb076d3980502ca5a577d3fdc45db8138d037c148f04f136b>:
  403e90:	push   %r14
  403e92:	push   %rbx
  403e93:	mov    %rdi,%rax
  403e96:	mov    (%rdx),%r10
  403e99:	mov    0x8(%rdx),%rsi
  403e9d:	mov    (%r10),%r11
  403ea0:	cmp    %r11,%rsi
  403ea3:	jge    403edf <myl_f_22a60c4dacd8f24cb076d3980502ca5a577d3fdc45db8138d037c148f04f136b+0x4f>
  403ea5:	mov    %rsi,%rdi
  403ea8:	sar    $0x3f,%rdi
  403eac:	and    %r11,%rdi
  403eaf:	add    %rsi,%rdi
  403eb2:	mov    0x20(%r10),%rsi
  403eb6:	cmpb   $0xa,(%rsi,%rdi,1)
  403eba:	jne    403eca <myl_f_22a60c4dacd8f24cb076d3980502ca5a577d3fdc45db8138d037c148f04f136b+0x3a>
  403ebc:	incq   0x10(%rdx)
  403ec0:	movq   $0x1,0x18(%rdx)
  403ec8:	jmp    403ece <myl_f_22a60c4dacd8f24cb076d3980502ca5a577d3fdc45db8138d037c148f04f136b+0x3e>
  403eca:	incq   0x18(%rdx)
  403ece:	mov    (%rdx),%r10
  403ed1:	mov    0x8(%rdx),%rsi
  403ed5:	inc    %rsi
  403ed8:	mov    %rsi,0x8(%rdx)
  403edc:	mov    (%r10),%r11
  403edf:	cmp    %r11,%rsi
  403ee2:	jge    403f87 <myl_f_22a60c4dacd8f24cb076d3980502ca5a577d3fdc45db8138d037c148f04f136b+0xf7>
  403ee8:	mov    %rsi,%rdi
  403eeb:	jmp    403f13 <myl_f_22a60c4dacd8f24cb076d3980502ca5a577d3fdc45db8138d037c148f04f136b+0x83>
  403eed:	nopl   (%rax)
  403ef0:	incq   0x10(%rdx)
  403ef4:	mov    $0x1,%edi
  403ef9:	mov    %rdi,0x18(%rdx)
  403efd:	mov    0x8(%rdx),%rdi
  403f01:	inc    %rdi
  403f04:	mov    %rdi,0x8(%rdx)
  403f08:	mov    (%rdx),%r10
  403f0b:	mov    (%r10),%r11
  403f0e:	cmp    %r11,%rdi
  403f11:	jge    403f87 <myl_f_22a60c4dacd8f24cb076d3980502ca5a577d3fdc45db8138d037c148f04f136b+0xf7>
  403f13:	mov    %rdi,%rbx
  403f16:	sar    $0x3f,%rbx
  403f1a:	and    %rbx,%r11
  403f1d:	add    %rdi,%r11
  403f20:	mov    0x20(%r10),%r10
  403f24:	movzbl (%r10,%r11,1),%r10d
  403f29:	cmp    $0xa,%r10d
  403f2d:	je     403ef0 <myl_f_22a60c4dacd8f24cb076d3980502ca5a577d3fdc45db8138d037c148f04f136b+0x60>
  403f2f:	cmp    $0x5c,%r10d
  403f33:	je     403f50 <myl_f_22a60c4dacd8f24cb076d3980502ca5a577d3fdc45db8138d037c148f04f136b+0xc0>
  403f35:	cmp    $0x22,%r10d
  403f39:	je     403fb8 <myl_f_22a60c4dacd8f24cb076d3980502ca5a577d3fdc45db8138d037c148f04f136b+0x128>
  403f3b:	mov    0x18(%rdx),%rdi
  403f3f:	inc    %rdi
  403f42:	jmp    403ef9 <myl_f_22a60c4dacd8f24cb076d3980502ca5a577d3fdc45db8138d037c148f04f136b+0x69>
  403f44:	data16 data16 cs nopw 0x0(%rax,%rax,1)
  403f50:	incq   0x18(%rdx)
  403f54:	mov    (%rdx),%r10
  403f57:	mov    0x8(%rdx),%rdi
  403f5b:	inc    %rdi
  403f5e:	mov    %rdi,0x8(%rdx)
  403f62:	mov    (%r10),%r11
  403f65:	cmp    %r11,%rdi
  403f68:	jge    403f08 <myl_f_22a60c4dacd8f24cb076d3980502ca5a577d3fdc45db8138d037c148f04f136b+0x78>
  403f6a:	mov    %rdi,%rbx
  403f6d:	sar    $0x3f,%rbx
  403f71:	and    %r11,%rbx
  403f74:	add    %rdi,%rbx
  403f77:	mov    0x20(%r10),%rdi
  403f7b:	cmpb   $0xa,(%rdi,%rbx,1)
  403f7f:	je     403ef0 <myl_f_22a60c4dacd8f24cb076d3980502ca5a577d3fdc45db8138d037c148f04f136b+0x60>
  403f85:	jmp    403f3b <myl_f_22a60c4dacd8f24cb076d3980502ca5a577d3fdc45db8138d037c148f04f136b+0xab>
  403f87:	mov    $0x439860,%rdx
  403f8e:	mov    (%rdx),%r10
  403f91:	movl   $0x1,(%rax)
  403f97:	mov    $0x18,%edx
  403f9c:	mov    $0x10,%r8d
  403fa2:	mov    $0x8,%r11d
  403fa8:	mov    %r10,(%rax,%r11,1)
  403fac:	mov    %r9,(%rax,%r8,1)
  403fb0:	mov    %rcx,(%rax,%rdx,1)
  403fb4:	pop    %rbx
  403fb5:	pop    %r14
  403fb7:	ret
  403fb8:	mov    (%rdx),%r11
  403fbb:	mov    (%r11),%r14
  403fbe:	mov    %rdi,%r10
  403fc1:	cmp    %r14,%rdi
  403fc4:	jge    403ff4 <myl_f_22a60c4dacd8f24cb076d3980502ca5a577d3fdc45db8138d037c148f04f136b+0x164>
  403fc6:	and    %r14,%rbx
  403fc9:	add    %rdi,%rbx
  403fcc:	mov    0x20(%r11),%r10
  403fd0:	cmpb   $0xa,(%r10,%rbx,1)
  403fd5:	jne    403fe5 <myl_f_22a60c4dacd8f24cb076d3980502ca5a577d3fdc45db8138d037c148f04f136b+0x155>
  403fd7:	incq   0x10(%rdx)
  403fdb:	movq   $0x1,0x18(%rdx)
  403fe3:	jmp    403fe9 <myl_f_22a60c4dacd8f24cb076d3980502ca5a577d3fdc45db8138d037c148f04f136b+0x159>
  403fe5:	incq   0x18(%rdx)
  403fe9:	mov    0x8(%rdx),%r10
  403fed:	inc    %r10
  403ff0:	mov    %r10,0x8(%rdx)
  403ff4:	movl   $0x0,(%rax)
  403ffa:	movl   $0x3,0x8(%rax)
  404001:	mov    %r9,0x10(%rax)
  404005:	mov    %r10,0x18(%rax)
  404009:	mov    %rcx,0x20(%rax)
  40400d:	mov    %r8,0x28(%rax)
  404011:	mov    $0x40,%edx
  404016:	mov    $0x38,%r8d
  40401c:	mov    $0x30,%r11d
  404022:	mov    %r9,%r10
  404025:	mov    %rsi,%r9
  404028:	mov    %rdi,%rcx
  40402b:	jmp    403fa8 <myl_f_22a60c4dacd8f24cb076d3980502ca5a577d3fdc45db8138d037c148f04f136b+0x118>

Disassembly of section .fini:
