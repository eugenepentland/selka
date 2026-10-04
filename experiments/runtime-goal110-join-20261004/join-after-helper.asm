
.mylang-cache/goal110-join/join-runner/bin/text-my-llvm:     file format elf64-x86-64


Disassembly of section .text:

0000000001091f90 <myl_native_text_join>:
 1091f90:	push   %rbp
 1091f91:	mov    %rsp,%rbp
 1091f94:	push   %r15
 1091f96:	push   %r14
 1091f98:	push   %r13
 1091f9a:	push   %r12
 1091f9c:	push   %rbx
 1091f9d:	sub    $0x88,%rsp
 1091fa4:	mov    %rdi,%r8
 1091fa7:	mov    %rsi,-0x68(%rbp)
 1091fab:	mov    %rdx,-0xb0(%rbp)
 1091fb2:	mov    (%rdx),%rbx
 1091fb5:	mov    0x20(%rdx),%rdi
 1091fb9:	mov    0x8(%rsi),%r9
 1091fbd:	mov    0x10(%rsi),%r13d
 1091fc1:	and    $0x1,%r13d
 1091fc5:	cmp    $0x2,%rbx
 1091fc9:	jb     1091fe3 <myl_native_text_join+0x53>
 1091fcb:	lea    -0x1(%rbx),%rcx
 1091fcf:	test   %r9,%r9
 1091fd2:	je     1091fef <myl_native_text_join+0x5f>
 1091fd4:	mov    %r9,%rax
 1091fd7:	mul    %rcx
 1091fda:	jno    1091fef <myl_native_text_join+0x5f>
 1091fdc:	xor    %eax,%eax
 1091fde:	jmp    109229f <myl_native_text_join+0x30f>
 1091fe3:	xor    %r15d,%r15d
 1091fe6:	test   %rbx,%rbx
 1091fe9:	je     1092031 <myl_native_text_join+0xa1>
 1091feb:	xor    %ecx,%ecx
 1091fed:	jmp    1091ffa <myl_native_text_join+0x6a>
 1091fef:	mov    %rcx,%r15
 1091ff2:	imul   %r9,%r15
 1091ff6:	imul   (%rsi),%rcx
 1091ffa:	xor    %eax,%eax
 1091ffc:	mov    %r15,%r14
 1091fff:	mov    %rcx,%r15
 1092002:	xor    %ecx,%ecx
 1092004:	data16 data16 cs nopw 0x0(%rax,%rax,1)
 1092010:	mov    (%rdi,%rcx,8),%rdx
 1092014:	add    0x8(%rdx),%r14
 1092018:	jb     109229f <myl_native_text_join+0x30f>
 109201e:	add    (%rdx),%r15
 1092021:	and    0x10(%rdx),%r13d
 1092025:	inc    %rcx
 1092028:	cmp    %rcx,%rbx
 109202b:	jne    1092010 <myl_native_text_join+0x80>
 109202d:	xor    %ecx,%ecx
 109202f:	jmp    1092036 <myl_native_text_join+0xa6>
 1092031:	mov    $0x1,%cl
 1092033:	xor    %r14d,%r14d
 1092036:	mov    0x10(%r8),%rax
 109203a:	mov    %rax,-0xa8(%rbp)
 1092041:	lea    -0x68(%rbp),%rax
 1092045:	mov    %rax,-0xa0(%rbp)
 109204c:	movq   $0x1031628,-0x98(%rbp)
 1092057:	lea    -0xa8(%rbp),%rdx
 109205e:	mov    %rdx,-0x88(%rbp)
 1092065:	lea    -0xb0(%rbp),%rax
 109206c:	mov    %rax,-0x80(%rbp)
 1092070:	movq   $0x1031628,-0x78(%rbp)
 1092078:	lea    -0x88(%rbp),%rsi
 109207f:	mov    %rsi,0x10(%r8)
 1092083:	cmp    %r14,%r15
 1092086:	mov    %rdi,-0x50(%rbp)
 109208a:	jne    1092099 <myl_native_text_join+0x109>
 109208c:	cmp    $0xffffffffffffffe7,%r14
 1092090:	jbe    109210a <myl_native_text_join+0x17a>
 1092092:	xor    %eax,%eax
 1092094:	jmp    1092291 <myl_native_text_join+0x301>
 1092099:	cmp    $0x100,%r14
 10920a0:	jb     109210a <myl_native_text_join+0x17a>
 10920a2:	mov    %r14,%rax
 10920a5:	shr    $0x20,%rax
 10920a9:	jne    109208c <myl_native_text_join+0xfc>
 10920ab:	mov    %ecx,-0x30(%rbp)
 10920ae:	mov    %r9,-0x38(%rbp)
 10920b2:	lea    -0x1(%r15),%rax
 10920b6:	shr    $0x7,%rax
 10920ba:	lea    0x17(,%rax,4),%rax
 10920c2:	and    $0xfffffffffffffff8,%rax
 10920c6:	cmp    $0x1,%r15
 10920ca:	mov    $0x10,%ecx
 10920cf:	cmovae %rax,%rcx
 10920d3:	lea    0x7(%r14),%rax
 10920d7:	movabs $0x1fffffff8,%rsi
 10920e1:	and    %rax,%rsi
 10920e4:	add    %rcx,%rsi
 10920e7:	mov    %r8,-0x40(%rbp)
 10920eb:	mov    %r8,%rdi
 10920ee:	call   108d210 <myl_native_heap_alloc_block>
 10920f3:	test   %rax,%rax
 10920f6:	je     109217c <myl_native_text_join+0x1ec>
 10920fc:	mov    %rax,%rcx
 10920ff:	mov    %r15,(%rcx)
 1092102:	mov    $0x8,%r12d
 1092108:	jmp    1092150 <myl_native_text_join+0x1c0>
 109210a:	xor    %eax,%eax
 109210c:	cmp    $0xffffffffffffffe7,%r14
 1092110:	ja     1092291 <myl_native_text_join+0x301>
 1092116:	cmpq   $0x0,0x1608(%r8)
 109211e:	je     1092291 <myl_native_text_join+0x301>
 1092124:	mov    %ecx,-0x30(%rbp)
 1092127:	mov    %r9,-0x38(%rbp)
 109212b:	lea    0x18(%r14),%rsi
 109212f:	mov    0x70(%r8),%edx
 1092133:	xor    %r12d,%r12d
 1092136:	mov    %r8,-0x40(%rbp)
 109213a:	mov    %r8,%rdi
 109213d:	xor    %ecx,%ecx
 109213f:	call   10a5850 <raw_bytes>
 1092144:	test   %rax,%rax
 1092147:	je     109217c <myl_native_text_join+0x1ec>
 1092149:	movq   $0x0,(%rax)
 1092150:	mov    %r14,0x8(%rax)
 1092154:	mov    %r12d,0x10(%rax)
 1092158:	movl   $0x0,0x14(%rax)
 109215f:	mov    -0x68(%rbp),%r11
 1092163:	testb  $0x4,0x10(%r11)
 1092168:	mov    -0x40(%rbp),%r8
 109216c:	mov    -0x50(%rbp),%r9
 1092170:	mov    -0x38(%rbp),%r10
 1092174:	jne    1092187 <myl_native_text_join+0x1f7>
 1092176:	add    $0x18,%r11
 109217a:	jmp    1092197 <myl_native_text_join+0x207>
 109217c:	xor    %eax,%eax
 109217e:	mov    -0x40(%rbp),%r8
 1092182:	jmp    1092283 <myl_native_text_join+0x2f3>
 1092187:	mov    0x18(%r11),%rcx
 109218b:	mov    0x14(%r11),%edx
 109218f:	lea    (%rcx,%rdx,1),%r11
 1092193:	add    $0x18,%r11
 1092197:	mov    -0x30(%rbp),%ecx
 109219a:	test   %cl,%cl
 109219c:	mov    %rax,-0x48(%rbp)
 10921a0:	jne    1092270 <myl_native_text_join+0x2e0>
 10921a6:	lea    0x18(%rax),%rcx
 10921aa:	mov    %rcx,-0x60(%rbp)
 10921ae:	mov    (%r9),%rsi
 10921b1:	mov    0x8(%rsi),%rdi
 10921b5:	test   %rdi,%rdi
 10921b8:	mov    %r11,-0x58(%rbp)
 10921bc:	je     109226a <myl_native_text_join+0x2da>
 10921c2:	testb  $0x4,0x10(%rsi)
 10921c6:	jne    10921ce <myl_native_text_join+0x23e>
 10921c8:	add    $0x18,%rsi
 10921cc:	jmp    10921dd <myl_native_text_join+0x24d>
 10921ce:	mov    0x18(%rsi),%rcx
 10921d2:	mov    0x14(%rsi),%edx
 10921d5:	lea    (%rcx,%rdx,1),%rsi
 10921d9:	add    $0x18,%rsi
 10921dd:	cmp    $0x10,%rdi
 10921e1:	jbe    1092211 <myl_native_text_join+0x281>
 10921e3:	mov    %rdi,%r12
 10921e6:	mov    -0x60(%rbp),%rdi
 10921ea:	mov    %r12,%rdx
 10921ed:	mov    %r8,%r14
 10921f0:	mov    %r10,-0x38(%rbp)
 10921f4:	call   10ab2c0 <memcpy@plt>
 10921f9:	mov    %r12,%rdi
 10921fc:	mov    -0x58(%rbp),%r11
 1092200:	mov    -0x38(%rbp),%r10
 1092204:	mov    -0x50(%rbp),%r9
 1092208:	mov    %r14,%r8
 109220b:	mov    -0x48(%rbp),%rax
 109220f:	jmp    109226a <myl_native_text_join+0x2da>
 1092211:	cmp    $0x7,%rdi
 1092215:	jbe    109222d <myl_native_text_join+0x29d>
 1092217:	mov    (%rsi),%rcx
 109221a:	mov    -0x8(%rsi,%rdi,1),%rdx
 109221f:	lea    0x18(%rax),%rsi
 1092223:	mov    %rcx,(%rsi)
 1092226:	mov    %rdx,-0x8(%rsi,%rdi,1)
 109222b:	jmp    109226a <myl_native_text_join+0x2da>
 109222d:	cmp    $0x3,%rdi
 1092231:	jbe    1092245 <myl_native_text_join+0x2b5>
 1092233:	mov    (%rsi),%ecx
 1092235:	mov    -0x4(%rsi,%rdi,1),%edx
 1092239:	lea    0x18(%rax),%rsi
 109223d:	mov    %ecx,(%rsi)
 109223f:	mov    %edx,-0x4(%rsi,%rdi,1)
 1092243:	jmp    109226a <myl_native_text_join+0x2da>
 1092245:	cmp    $0x1,%rdi
 1092249:	jne    1092256 <myl_native_text_join+0x2c6>
 109224b:	movzbl (%rsi),%ecx
 109224e:	lea    0x18(%rax),%rdx
 1092252:	mov    %cl,(%rdx)
 1092254:	jmp    109226a <myl_native_text_join+0x2da>
 1092256:	movzwl (%rsi),%ecx
 1092259:	movzwl -0x2(%rsi,%rdi,1),%edx
 109225e:	lea    0x18(%rax),%rsi
 1092262:	mov    %cx,(%rsi)
 1092265:	mov    %dx,-0x2(%rsi,%rdi,1)
 109226a:	cmp    $0x1,%rbx
 109226e:	jne    10922ce <myl_native_text_join+0x33e>
 1092270:	test   %r13d,%r13d
 1092273:	je     1092443 <myl_native_text_join+0x4b3>
 1092279:	mov    %r15,(%rax)
 109227c:	movl   $0x1,0x10(%rax)
 1092283:	lea    -0xa8(%rbp),%rdx
 109228a:	lea    -0x88(%rbp),%rsi
 1092291:	mov    0x10(%r8),%rcx
 1092295:	cmp    %rsi,%rcx
 1092298:	je     10922b1 <myl_native_text_join+0x321>
 109229a:	cmp    %rdx,%rcx
 109229d:	je     10922c1 <myl_native_text_join+0x331>
 109229f:	add    $0x88,%rsp
 10922a6:	pop    %rbx
 10922a7:	pop    %r12
 10922a9:	pop    %r13
 10922ab:	pop    %r14
 10922ad:	pop    %r15
 10922af:	pop    %rbp
 10922b0:	ret
 10922b1:	mov    -0x88(%rbp),%rcx
 10922b8:	mov    %rcx,0x10(%r8)
 10922bc:	cmp    %rdx,%rcx
 10922bf:	jne    109229f <myl_native_text_join+0x30f>
 10922c1:	mov    -0xa8(%rbp),%rcx
 10922c8:	mov    %rcx,0x10(%r8)
 10922cc:	jmp    109229f <myl_native_text_join+0x30f>
 10922ce:	mov    $0x1,%r14d
 10922d4:	mov    %r8,-0x40(%rbp)
 10922d8:	mov    %r10,-0x38(%rbp)
 10922dc:	jmp    109230d <myl_native_text_join+0x37d>
 10922de:	mov    %r12,%rdx
 10922e1:	call   10ab2c0 <memcpy@plt>
 10922e6:	mov    -0x58(%rbp),%r11
 10922ea:	mov    -0x38(%rbp),%r10
 10922ee:	mov    -0x50(%rbp),%r9
 10922f2:	mov    -0x40(%rbp),%r8
 10922f6:	mov    -0x48(%rbp),%rax
 10922fa:	mov    -0x30(%rbp),%rdi
 10922fe:	add    %r12,%rdi
 1092301:	inc    %r14
 1092304:	cmp    %r14,%rbx
 1092307:	je     1092270 <myl_native_text_join+0x2e0>
 109230d:	test   %r10,%r10
 1092310:	je     10923a7 <myl_native_text_join+0x417>
 1092316:	mov    -0x60(%rbp),%rcx
 109231a:	mov    %rdi,-0x30(%rbp)
 109231e:	add    %rcx,%rdi
 1092321:	cmp    $0x11,%r10
 1092325:	jb     109234a <myl_native_text_join+0x3ba>
 1092327:	mov    %r11,%rsi
 109232a:	mov    %r10,%rdx
 109232d:	mov    %r8,%r12
 1092330:	call   10ab2c0 <memcpy@plt>
 1092335:	mov    -0x58(%rbp),%r11
 1092339:	mov    -0x38(%rbp),%r10
 109233d:	mov    -0x50(%rbp),%r9
 1092341:	mov    %r12,%r8
 1092344:	mov    -0x48(%rbp),%rax
 1092348:	jmp    10923a0 <myl_native_text_join+0x410>
 109234a:	cmp    $0x8,%r10
 109234e:	jb     1092362 <myl_native_text_join+0x3d2>
 1092350:	mov    (%r11),%rcx
 1092353:	mov    -0x8(%r11,%r10,1),%rdx
 1092358:	mov    %rcx,(%rdi)
 109235b:	mov    %rdx,-0x8(%rdi,%r10,1)
 1092360:	jmp    10923a0 <myl_native_text_join+0x410>
 1092362:	cmp    $0x4,%r10
 1092366:	jb     1092379 <myl_native_text_join+0x3e9>
 1092368:	mov    (%r11),%ecx
 109236b:	mov    -0x4(%r11,%r10,1),%edx
 1092370:	mov    %ecx,(%rdi)
 1092372:	mov    %edx,-0x4(%rdi,%r10,1)
 1092377:	jmp    10923a0 <myl_native_text_join+0x410>
 1092379:	cmp    $0x2,%r10
 109237d:	jb     1092394 <myl_native_text_join+0x404>
 109237f:	movzwl (%r11),%ecx
 1092383:	movzwl -0x2(%r11,%r10,1),%edx
 1092389:	mov    %cx,(%rdi)
 109238c:	mov    %dx,-0x2(%rdi,%r10,1)
 1092392:	jmp    10923a0 <myl_native_text_join+0x410>
 1092394:	movzbl (%r11),%ecx
 1092398:	mov    %cl,(%rdi)
 109239a:	nopw   0x0(%rax,%rax,1)
 10923a0:	mov    -0x30(%rbp),%rdi
 10923a4:	add    %r10,%rdi
 10923a7:	mov    (%r9,%r14,8),%rsi
 10923ab:	mov    0x8(%rsi),%r12
 10923af:	test   %r12,%r12
 10923b2:	je     10922fe <myl_native_text_join+0x36e>
 10923b8:	testb  $0x4,0x10(%rsi)
 10923bc:	jne    10923c4 <myl_native_text_join+0x434>
 10923be:	add    $0x18,%rsi
 10923c2:	jmp    10923d3 <myl_native_text_join+0x443>
 10923c4:	mov    0x18(%rsi),%rcx
 10923c8:	mov    0x14(%rsi),%edx
 10923cb:	lea    (%rcx,%rdx,1),%rsi
 10923cf:	add    $0x18,%rsi
 10923d3:	mov    -0x60(%rbp),%rcx
 10923d7:	mov    %rdi,-0x30(%rbp)
 10923db:	add    %rcx,%rdi
 10923de:	cmp    $0x11,%r12
 10923e2:	jae    10922de <myl_native_text_join+0x34e>
 10923e8:	cmp    $0x8,%r12
 10923ec:	jb     1092403 <myl_native_text_join+0x473>
 10923ee:	mov    (%rsi),%rcx
 10923f1:	mov    -0x8(%rsi,%r12,1),%rdx
 10923f6:	mov    %rcx,(%rdi)
 10923f9:	mov    %rdx,-0x8(%rdi,%r12,1)
 10923fe:	jmp    10922fa <myl_native_text_join+0x36a>
 1092403:	cmp    $0x4,%r12
 1092407:	jb     109241c <myl_native_text_join+0x48c>
 1092409:	mov    (%rsi),%ecx
 109240b:	mov    -0x4(%rsi,%r12,1),%edx
 1092410:	mov    %ecx,(%rdi)
 1092412:	mov    %edx,-0x4(%rdi,%r12,1)
 1092417:	jmp    10922fa <myl_native_text_join+0x36a>
 109241c:	cmp    $0x1,%r12
 1092420:	jne    109242c <myl_native_text_join+0x49c>
 1092422:	movzbl (%rsi),%ecx
 1092425:	mov    %cl,(%rdi)
 1092427:	jmp    10922fa <myl_native_text_join+0x36a>
 109242c:	movzwl (%rsi),%ecx
 109242f:	movzwl -0x2(%rsi,%r12,1),%edx
 1092435:	mov    %cx,(%rdi)
 1092438:	mov    %dx,-0x2(%rdi,%r12,1)
 109243e:	jmp    10922fa <myl_native_text_join+0x36a>
 1092443:	mov    %rax,%rdi
 1092446:	mov    %r15,%rsi
 1092449:	mov    %r8,%rbx
 109244c:	call   108f0b0 <publish_wide>
 1092451:	mov    %rbx,%r8
 1092454:	mov    -0x48(%rbp),%rax
 1092458:	jmp    1092283 <myl_native_text_join+0x2f3>

Disassembly of section .init:

Disassembly of section .fini:

Disassembly of section .plt:
