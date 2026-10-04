
/home/epentland/ai/canopy/mylang-worktrees/runtime-parity-harness-20261003/.mylang-cache/runtime-candidate-730a86e6-releasefast/runner/bin/text-my-llvm:     file format elf64-x86-64


Disassembly of section .text:

0000000001091f90 <myl_native_text_join>:
 1091f90:	push   %rbp
 1091f91:	mov    %rsp,%rbp
 1091f94:	push   %r15
 1091f96:	push   %r14
 1091f98:	push   %r13
 1091f9a:	push   %r12
 1091f9c:	push   %rbx
 1091f9d:	sub    $0x68,%rsp
 1091fa1:	mov    %rsi,-0x50(%rbp)
 1091fa5:	mov    %rdx,-0x48(%rbp)
 1091fa9:	mov    0x10(%rsi),%r13d
 1091fad:	and    $0x1,%r13d
 1091fb1:	mov    (%rdx),%rax
 1091fb4:	mov    0x20(%rdx),%r12
 1091fb8:	test   %rax,%rax
 1091fbb:	je     1092004 <myl_native_text_join+0x74>
 1091fbd:	mov    (%r12),%rcx
 1091fc1:	mov    (%rcx),%r14
 1091fc4:	mov    0x8(%rcx),%r15
 1091fc8:	and    0x10(%rcx),%r13d
 1091fcc:	cmp    $0x1,%rax
 1091fd0:	je     109200a <myl_native_text_join+0x7a>
 1091fd2:	mov    $0x1,%ecx
 1091fd7:	nopw   0x0(%rax,%rax,1)
 1091fe0:	mov    (%r12,%rcx,8),%rdx
 1091fe4:	add    0x8(%rdx),%r15
 1091fe8:	jb     109205d <myl_native_text_join+0xcd>
 1091fea:	add    0x8(%rsi),%r15
 1091fee:	jb     109205d <myl_native_text_join+0xcd>
 1091ff0:	and    0x10(%rdx),%r13d
 1091ff4:	add    (%rdx),%r14
 1091ff7:	add    (%rsi),%r14
 1091ffa:	inc    %rcx
 1091ffd:	cmp    %rcx,%rax
 1092000:	jne    1091fe0 <myl_native_text_join+0x50>
 1092002:	jmp    109200a <myl_native_text_join+0x7a>
 1092004:	xor    %r14d,%r14d
 1092007:	xor    %r15d,%r15d
 109200a:	mov    0x10(%rdi),%rax
 109200e:	mov    %rax,-0x90(%rbp)
 1092015:	lea    -0x50(%rbp),%rax
 1092019:	mov    %rax,-0x88(%rbp)
 1092020:	movq   $0x1031628,-0x80(%rbp)
 1092028:	lea    -0x90(%rbp),%rcx
 109202f:	mov    %rcx,-0x70(%rbp)
 1092033:	lea    -0x48(%rbp),%rax
 1092037:	mov    %rax,-0x68(%rbp)
 109203b:	movq   $0x1031628,-0x60(%rbp)
 1092043:	lea    -0x70(%rbp),%rsi
 1092047:	mov    %rsi,0x10(%rdi)
 109204b:	cmp    %r15,%r14
 109204e:	jne    1092064 <myl_native_text_join+0xd4>
 1092050:	cmp    $0xffffffffffffffe7,%r15
 1092054:	jbe    10920c7 <myl_native_text_join+0x137>
 1092056:	xor    %eax,%eax
 1092058:	jmp    109224b <myl_native_text_join+0x2bb>
 109205d:	xor    %eax,%eax
 109205f:	jmp    1092259 <myl_native_text_join+0x2c9>
 1092064:	cmp    $0x100,%r15
 109206b:	jb     10920c7 <myl_native_text_join+0x137>
 109206d:	mov    %r15,%rax
 1092070:	shr    $0x20,%rax
 1092074:	jne    1092050 <myl_native_text_join+0xc0>
 1092076:	lea    -0x1(%r14),%rax
 109207a:	shr    $0x7,%rax
 109207e:	lea    0x17(,%rax,4),%rax
 1092086:	and    $0xfffffffffffffff8,%rax
 109208a:	cmp    $0x1,%r14
 109208e:	mov    $0x10,%ecx
 1092093:	cmovae %rax,%rcx
 1092097:	lea    0x7(%r15),%rax
 109209b:	movabs $0x1fffffff8,%rsi
 10920a5:	and    %rax,%rsi
 10920a8:	add    %rcx,%rsi
 10920ab:	mov    %rdi,-0x30(%rbp)
 10920af:	call   108d210 <myl_native_heap_alloc_block>
 10920b4:	test   %rax,%rax
 10920b7:	je     1092148 <myl_native_text_join+0x1b8>
 10920bd:	mov    %r14,(%rax)
 10920c0:	mov    $0x8,%ebx
 10920c5:	jmp    1092101 <myl_native_text_join+0x171>
 10920c7:	xor    %eax,%eax
 10920c9:	cmp    $0xffffffffffffffe7,%r15
 10920cd:	ja     109224b <myl_native_text_join+0x2bb>
 10920d3:	cmpq   $0x0,0x1608(%rdi)
 10920db:	je     109224b <myl_native_text_join+0x2bb>
 10920e1:	lea    0x18(%r15),%rsi
 10920e5:	mov    0x70(%rdi),%edx
 10920e8:	xor    %ebx,%ebx
 10920ea:	mov    %rdi,-0x30(%rbp)
 10920ee:	xor    %ecx,%ecx
 10920f0:	call   10a5690 <raw_bytes>
 10920f5:	test   %rax,%rax
 10920f8:	je     1092148 <myl_native_text_join+0x1b8>
 10920fa:	movq   $0x0,(%rax)
 1092101:	mov    %r15,0x8(%rax)
 1092105:	mov    %ebx,0x10(%rax)
 1092108:	mov    %rax,-0x38(%rbp)
 109210c:	movl   $0x0,0x14(%rax)
 1092113:	mov    -0x48(%rbp),%rbx
 1092117:	mov    (%rbx),%rax
 109211a:	test   %rax,%rax
 109211d:	je     1092229 <myl_native_text_join+0x299>
 1092123:	mov    -0x38(%rbp),%rcx
 1092127:	add    $0x18,%rcx
 109212b:	mov    %rcx,-0x40(%rbp)
 109212f:	mov    (%r12),%rsi
 1092133:	mov    0x8(%rsi),%rdx
 1092137:	test   %rdx,%rdx
 109213a:	je     109214f <myl_native_text_join+0x1bf>
 109213c:	testb  $0x4,0x10(%rsi)
 1092140:	jne    1092154 <myl_native_text_join+0x1c4>
 1092142:	add    $0x18,%rsi
 1092146:	jmp    1092163 <myl_native_text_join+0x1d3>
 1092148:	xor    %eax,%eax
 109214a:	jmp    109223c <myl_native_text_join+0x2ac>
 109214f:	xor    %r15d,%r15d
 1092152:	jmp    1092177 <myl_native_text_join+0x1e7>
 1092154:	mov    0x18(%rsi),%rax
 1092158:	mov    0x14(%rsi),%ecx
 109215b:	lea    (%rax,%rcx,1),%rsi
 109215f:	add    $0x18,%rsi
 1092163:	mov    -0x40(%rbp),%rdi
 1092167:	call   10ab100 <memcpy@plt>
 109216c:	mov    (%r12),%rax
 1092170:	mov    0x8(%rax),%r15
 1092174:	mov    (%rbx),%rax
 1092177:	cmp    $0x2,%rax
 109217b:	jb     1092229 <myl_native_text_join+0x299>
 1092181:	mov    $0x1,%ebx
 1092186:	jmp    10921a5 <myl_native_text_join+0x215>
 1092188:	nopl   0x0(%rax,%rax,1)
 1092190:	xor    %eax,%eax
 1092192:	add    %rax,%r15
 1092195:	inc    %rbx
 1092198:	mov    -0x48(%rbp),%rax
 109219c:	cmp    (%rax),%rbx
 109219f:	jae    1092229 <myl_native_text_join+0x299>
 10921a5:	mov    -0x50(%rbp),%rsi
 10921a9:	mov    0x8(%rsi),%rdx
 10921ad:	test   %rdx,%rdx
 10921b0:	je     10921e4 <myl_native_text_join+0x254>
 10921b2:	testb  $0x4,0x10(%rsi)
 10921b6:	jne    10921c0 <myl_native_text_join+0x230>
 10921b8:	add    $0x18,%rsi
 10921bc:	jmp    10921cf <myl_native_text_join+0x23f>
 10921be:	xchg   %ax,%ax
 10921c0:	mov    0x18(%rsi),%rax
 10921c4:	mov    0x14(%rsi),%ecx
 10921c7:	lea    (%rax,%rcx,1),%rsi
 10921cb:	add    $0x18,%rsi
 10921cf:	mov    -0x40(%rbp),%rax
 10921d3:	lea    (%rax,%r15,1),%rdi
 10921d7:	call   10ab100 <memcpy@plt>
 10921dc:	mov    -0x50(%rbp),%rax
 10921e0:	add    0x8(%rax),%r15
 10921e4:	mov    (%r12,%rbx,8),%rsi
 10921e8:	mov    0x8(%rsi),%rdx
 10921ec:	test   %rdx,%rdx
 10921ef:	je     1092190 <myl_native_text_join+0x200>
 10921f1:	testb  $0x4,0x10(%rsi)
 10921f5:	jne    1092200 <myl_native_text_join+0x270>
 10921f7:	add    $0x18,%rsi
 10921fb:	jmp    109220f <myl_native_text_join+0x27f>
 10921fd:	nopl   (%rax)
 1092200:	mov    0x18(%rsi),%rax
 1092204:	mov    0x14(%rsi),%ecx
 1092207:	lea    (%rax,%rcx,1),%rsi
 109220b:	add    $0x18,%rsi
 109220f:	mov    -0x40(%rbp),%rax
 1092213:	lea    (%rax,%r15,1),%rdi
 1092217:	call   10ab100 <memcpy@plt>
 109221c:	mov    (%r12,%rbx,8),%rax
 1092220:	mov    0x8(%rax),%rax
 1092224:	jmp    1092192 <myl_native_text_join+0x202>
 1092229:	test   %r13d,%r13d
 109222c:	je     1092282 <myl_native_text_join+0x2f2>
 109222e:	mov    -0x38(%rbp),%rax
 1092232:	mov    %r14,(%rax)
 1092235:	movl   $0x1,0x10(%rax)
 109223c:	mov    -0x30(%rbp),%rdi
 1092240:	lea    -0x90(%rbp),%rcx
 1092247:	lea    -0x70(%rbp),%rsi
 109224b:	mov    0x10(%rdi),%rdx
 109224f:	cmp    %rsi,%rdx
 1092252:	je     1092268 <myl_native_text_join+0x2d8>
 1092254:	cmp    %rcx,%rdx
 1092257:	je     1092275 <myl_native_text_join+0x2e5>
 1092259:	add    $0x68,%rsp
 109225d:	pop    %rbx
 109225e:	pop    %r12
 1092260:	pop    %r13
 1092262:	pop    %r14
 1092264:	pop    %r15
 1092266:	pop    %rbp
 1092267:	ret
 1092268:	mov    -0x70(%rbp),%rdx
 109226c:	mov    %rdx,0x10(%rdi)
 1092270:	cmp    %rcx,%rdx
 1092273:	jne    1092259 <myl_native_text_join+0x2c9>
 1092275:	mov    -0x90(%rbp),%rcx
 109227c:	mov    %rcx,0x10(%rdi)
 1092280:	jmp    1092259 <myl_native_text_join+0x2c9>
 1092282:	mov    -0x38(%rbp),%rbx
 1092286:	mov    %rbx,%rdi
 1092289:	mov    %r14,%rsi
 109228c:	call   108f0b0 <publish_wide>
 1092291:	mov    %rbx,%rax
 1092294:	jmp    109223c <myl_native_text_join+0x2ac>

Disassembly of section .init:

Disassembly of section .fini:

Disassembly of section .plt:
