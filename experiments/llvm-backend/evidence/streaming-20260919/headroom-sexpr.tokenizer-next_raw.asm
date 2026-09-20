
.tmp/llvm-streaming-20260919/final/maxperf-text-safe/compact-o3.bin:     file format elf64-x86-64


Disassembly of section .init:

Disassembly of section .plt:

Disassembly of section .text:

0000000000406010 <myl_f_522a0393f0b978ec89dcf0a01ed40fe4c77fd2e0c5e149267c4a06b2be768f98>:
  406010:	push   %rbx
  406011:	sub    $0x1e0,%rsp
  406018:	mov    %rdi,%rax
  40601b:	mov    (%rdx),%rsi
  40601e:	mov    0x8(%rdx),%r9
  406022:	mov    (%rsi),%rdi
  406025:	cmp    %rdi,%r9
  406028:	jge    4060ec <myl_f_522a0393f0b978ec89dcf0a01ed40fe4c77fd2e0c5e149267c4a06b2be768f98+0xdc>
  40602e:	lea    0x260eb(%rip),%rcx        # 42c120 <_fini+0x7dc>
  406035:	jmp    406065 <myl_f_522a0393f0b978ec89dcf0a01ed40fe4c77fd2e0c5e149267c4a06b2be768f98+0x55>
  406037:	nopw   0x0(%rax,%rax,1)
  406040:	mov    0x18(%rdx),%rsi
  406044:	inc    %rsi
  406047:	mov    %rsi,0x18(%rdx)
  40604b:	mov    0x8(%rdx),%r9
  40604f:	inc    %r9
  406052:	mov    %r9,0x8(%rdx)
  406056:	mov    (%rdx),%rsi
  406059:	mov    (%rsi),%rdi
  40605c:	cmp    %rdi,%r9
  40605f:	jge    4060ec <myl_f_522a0393f0b978ec89dcf0a01ed40fe4c77fd2e0c5e149267c4a06b2be768f98+0xdc>
  406065:	mov    %r9,%r8
  406068:	sar    $0x3f,%r8
  40606c:	and    %rdi,%r8
  40606f:	add    %r9,%r8
  406072:	mov    0x20(%rsi),%r10
  406076:	movzbl (%r10,%r8,1),%r8d
  40607b:	lea    -0x9(%r8),%r10d
  40607f:	cmp    $0x17,%r10d
  406083:	ja     4060a0 <myl_f_522a0393f0b978ec89dcf0a01ed40fe4c77fd2e0c5e149267c4a06b2be768f98+0x90>
  406085:	movslq (%rcx,%r10,4),%rsi
  406089:	add    %rcx,%rsi
  40608c:	jmp    *%rsi
  40608e:	incq   0x10(%rdx)
  406092:	mov    $0x1,%esi
  406097:	jmp    406047 <myl_f_522a0393f0b978ec89dcf0a01ed40fe4c77fd2e0c5e149267c4a06b2be768f98+0x37>
  406099:	nopl   0x0(%rax)
  4060a0:	cmp    $0x3b,%r8d
  4060a4:	jne    4060ec <myl_f_522a0393f0b978ec89dcf0a01ed40fe4c77fd2e0c5e149267c4a06b2be768f98+0xdc>
  4060a6:	cs nopw 0x0(%rax,%rax,1)
  4060b0:	cmp    %rdi,%r9
  4060b3:	jge    406056 <myl_f_522a0393f0b978ec89dcf0a01ed40fe4c77fd2e0c5e149267c4a06b2be768f98+0x46>
  4060b5:	mov    %r9,%r8
  4060b8:	sar    $0x3f,%r8
  4060bc:	and    %rdi,%r8
  4060bf:	add    %r9,%r8
  4060c2:	mov    0x20(%rsi),%rsi
  4060c6:	cmpb   $0xa,(%rsi,%r8,1)
  4060cb:	je     406056 <myl_f_522a0393f0b978ec89dcf0a01ed40fe4c77fd2e0c5e149267c4a06b2be768f98+0x46>
  4060cd:	incq   0x18(%rdx)
  4060d1:	mov    (%rdx),%rsi
  4060d4:	mov    0x8(%rdx),%r9
  4060d8:	inc    %r9
  4060db:	mov    %r9,0x8(%rdx)
  4060df:	mov    (%rsi),%rdi
  4060e2:	cmp    %rdi,%r9
  4060e5:	jl     4060b5 <myl_f_522a0393f0b978ec89dcf0a01ed40fe4c77fd2e0c5e149267c4a06b2be768f98+0xa5>
  4060e7:	jmp    406056 <myl_f_522a0393f0b978ec89dcf0a01ed40fe4c77fd2e0c5e149267c4a06b2be768f98+0x46>
  4060ec:	mov    (%rdx),%rdi
  4060ef:	mov    0x10(%rdx),%rcx
  4060f3:	mov    0x18(%rdx),%r8
  4060f7:	mov    (%rdi),%rsi
  4060fa:	cmp    %rsi,%r9
  4060fd:	jge    40614e <myl_f_522a0393f0b978ec89dcf0a01ed40fe4c77fd2e0c5e149267c4a06b2be768f98+0x13e>
  4060ff:	mov    %r9,%r11
  406102:	sar    $0x3f,%r11
  406106:	and    %rsi,%r11
  406109:	add    %r9,%r11
  40610c:	mov    0x20(%rdi),%r10
  406110:	movzbl (%r10,%r11,1),%edi
  406115:	cmp    $0x22,%edi
  406118:	je     4061bd <myl_f_522a0393f0b978ec89dcf0a01ed40fe4c77fd2e0c5e149267c4a06b2be768f98+0x1ad>
  40611e:	cmp    $0x28,%edi
  406121:	je     40617c <myl_f_522a0393f0b978ec89dcf0a01ed40fe4c77fd2e0c5e149267c4a06b2be768f98+0x16c>
  406123:	cmp    $0x29,%edi
  406126:	jne    4061fc <myl_f_522a0393f0b978ec89dcf0a01ed40fe4c77fd2e0c5e149267c4a06b2be768f98+0x1ec>
  40612c:	lea    0x1(%r8),%rsi
  406130:	mov    %rsi,0x18(%rdx)
  406134:	mov    0x8(%rdx),%rsi
  406138:	inc    %rsi
  40613b:	mov    %rsi,0x8(%rdx)
  40613f:	movl   $0x0,(%rax)
  406145:	movl   $0x1,0x8(%rax)
  40614c:	jmp    40619c <myl_f_522a0393f0b978ec89dcf0a01ed40fe4c77fd2e0c5e149267c4a06b2be768f98+0x18c>
  40614e:	movl   $0x0,(%rax)
  406154:	movl   $0x8,0x8(%rax)
  40615b:	mov    %r9,0x10(%rax)
  40615f:	mov    %r9,0x18(%rax)
  406163:	mov    %rcx,0x20(%rax)
  406167:	mov    %r8,0x28(%rax)
  40616b:	mov    %r9,0x30(%rax)
  40616f:	mov    %r9,0x38(%rax)
  406173:	mov    %r9,0x40(%rax)
  406177:	jmp    4063ea <myl_f_522a0393f0b978ec89dcf0a01ed40fe4c77fd2e0c5e149267c4a06b2be768f98+0x3da>
  40617c:	lea    0x1(%r8),%rsi
  406180:	mov    %rsi,0x18(%rdx)
  406184:	mov    0x8(%rdx),%rsi
  406188:	inc    %rsi
  40618b:	mov    %rsi,0x8(%rdx)
  40618f:	movl   $0x0,(%rax)
  406195:	movl   $0x0,0x8(%rax)
  40619c:	mov    %r9,0x10(%rax)
  4061a0:	mov    %rsi,0x18(%rax)
  4061a4:	mov    %rcx,0x20(%rax)
  4061a8:	mov    %r8,0x28(%rax)
  4061ac:	mov    %r9,0x30(%rax)
  4061b0:	mov    %r9,0x38(%rax)
  4061b4:	mov    %rsi,0x40(%rax)
  4061b8:	jmp    4063ea <myl_f_522a0393f0b978ec89dcf0a01ed40fe4c77fd2e0c5e149267c4a06b2be768f98+0x3da>
  4061bd:	lea    0xd8(%rsp),%rdi
  4061c5:	mov    %rax,%rbx
  4061c8:	call   403e90 <myl_f_22a60c4dacd8f24cb076d3980502ca5a577d3fdc45db8138d037c148f04f136b>
  4061cd:	mov    %rbx,%rax
  4061d0:	mov    0x118(%rsp),%rcx
  4061d8:	mov    %rcx,0x40(%rbx)
  4061dc:	vmovups 0xd8(%rsp),%ymm0
  4061e5:	vmovups 0xf8(%rsp),%ymm1
  4061ee:	vmovups %ymm1,0x20(%rbx)
  4061f3:	vmovups %ymm0,(%rbx)
  4061f7:	jmp    4063ea <myl_f_522a0393f0b978ec89dcf0a01ed40fe4c77fd2e0c5e149267c4a06b2be768f98+0x3da>
  4061fc:	cmp    $0x30,%dil
  406200:	jb     406233 <myl_f_522a0393f0b978ec89dcf0a01ed40fe4c77fd2e0c5e149267c4a06b2be768f98+0x223>
  406202:	cmp    $0x39,%dil
  406206:	jbe    4062e5 <myl_f_522a0393f0b978ec89dcf0a01ed40fe4c77fd2e0c5e149267c4a06b2be768f98+0x2d5>
  40620c:	cmp    $0x61,%dil
  406210:	jb     40634d <myl_f_522a0393f0b978ec89dcf0a01ed40fe4c77fd2e0c5e149267c4a06b2be768f98+0x33d>
  406216:	cmp    $0x7b,%dil
  40621a:	setb   %sil
  40621e:	cmp    $0x7e,%edi
  406221:	sete   %dil
  406225:	or     %sil,%dil
  406228:	jne    406367 <myl_f_522a0393f0b978ec89dcf0a01ed40fe4c77fd2e0c5e149267c4a06b2be768f98+0x357>
  40622e:	jmp    4063ce <myl_f_522a0393f0b978ec89dcf0a01ed40fe4c77fd2e0c5e149267c4a06b2be768f98+0x3be>
  406233:	cmp    $0x2f,%edi
  406236:	ja     4063ce <myl_f_522a0393f0b978ec89dcf0a01ed40fe4c77fd2e0c5e149267c4a06b2be768f98+0x3be>
  40623c:	mov    %edi,%edi
  40623e:	movabs $0x882200000000,%r11
  406248:	bt     %rdi,%r11
  40624c:	jae    4062a7 <myl_f_522a0393f0b978ec89dcf0a01ed40fe4c77fd2e0c5e149267c4a06b2be768f98+0x297>
  40624e:	lea    0x120(%rsp),%rdi
  406256:	mov    %rax,%rbx
  406259:	call   402d40 <myl_f_05bad94abe02b55566d03c0ef8a0ac1a7f3d2609e72b12cfd054ca93b71064a0>
  40625e:	mov    %rbx,%rax
  406261:	vmovups 0x120(%rsp),%ymm0
  40626a:	vmovups 0x140(%rsp),%ymm1
  406273:	vmovups %ymm1,0x30(%rsp)
  406279:	vmovups %ymm0,0x10(%rsp)
  40627f:	movl   $0x0,(%rbx)
  406285:	vmovups 0xc(%rsp),%ymm0
  40628b:	vmovups 0x2c(%rsp),%ymm1
  406291:	vmovups %ymm0,0x4(%rbx)
  406296:	vmovups %ymm1,0x24(%rbx)
  40629b:	mov    0x4c(%rsp),%ecx
  40629f:	mov    %ecx,0x44(%rbx)
  4062a2:	jmp    4063ea <myl_f_522a0393f0b978ec89dcf0a01ed40fe4c77fd2e0c5e149267c4a06b2be768f98+0x3da>
  4062a7:	cmp    $0x2a,%rdi
  4062ab:	je     406367 <myl_f_522a0393f0b978ec89dcf0a01ed40fe4c77fd2e0c5e149267c4a06b2be768f98+0x357>
  4062b1:	cmp    $0x2d,%rdi
  4062b5:	jne    4063ce <myl_f_522a0393f0b978ec89dcf0a01ed40fe4c77fd2e0c5e149267c4a06b2be768f98+0x3be>
  4062bb:	lea    0x1(%r9),%rdi
  4062bf:	cmp    %rsi,%rdi
  4062c2:	jge    40624e <myl_f_522a0393f0b978ec89dcf0a01ed40fe4c77fd2e0c5e149267c4a06b2be768f98+0x23e>
  4062c4:	xor    %r11d,%r11d
  4062c7:	cmp    $0xffffffffffffffff,%r9
  4062cb:	cmovl  %rsi,%r11
  4062cf:	add    %rdi,%r11
  4062d2:	movzbl (%r10,%r11,1),%esi
  4062d7:	add    $0xc6,%sil
  4062db:	cmp    $0xf6,%sil
  4062df:	jb     40624e <myl_f_522a0393f0b978ec89dcf0a01ed40fe4c77fd2e0c5e149267c4a06b2be768f98+0x23e>
  4062e5:	lea    0x1a0(%rsp),%rdi
  4062ed:	mov    %rax,%rbx
  4062f0:	call   407df0 <myl_f_73f351c18f47dd990165f2548f3afcb7d5b743c0da8680d6a4223dfb5b0f824c>
  4062f5:	mov    %rbx,%rax
  4062f8:	vmovups 0x1a0(%rsp),%ymm0
  406301:	vmovups 0x1c0(%rsp),%ymm1
  40630a:	vmovups %ymm1,0xb8(%rsp)
  406313:	vmovups %ymm0,0x98(%rsp)
  40631c:	movl   $0x0,(%rbx)
  406322:	vmovups 0x94(%rsp),%ymm0
  40632b:	vmovups 0xb4(%rsp),%ymm1
  406334:	vmovups %ymm0,0x4(%rbx)
  406339:	vmovups %ymm1,0x24(%rbx)
  40633e:	mov    0xd4(%rsp),%ecx
  406345:	mov    %ecx,0x44(%rbx)
  406348:	jmp    4063ea <myl_f_522a0393f0b978ec89dcf0a01ed40fe4c77fd2e0c5e149267c4a06b2be768f98+0x3da>
  40634d:	cmp    $0x41,%dil
  406351:	jb     4063c0 <myl_f_522a0393f0b978ec89dcf0a01ed40fe4c77fd2e0c5e149267c4a06b2be768f98+0x3b0>
  406353:	cmp    $0x5b,%dil
  406357:	setae  %sil
  40635b:	cmp    $0x5f,%edi
  40635e:	setne  %dil
  406362:	test   %dil,%sil
  406365:	jne    4063ce <myl_f_522a0393f0b978ec89dcf0a01ed40fe4c77fd2e0c5e149267c4a06b2be768f98+0x3be>
  406367:	lea    0x160(%rsp),%rdi
  40636f:	mov    %rax,%rbx
  406372:	call   417a60 <myl_f_c7216ff81b82e9d60b2aefddc873a7cdb611d664b3deb9b17e22a05b9481cf8a>
  406377:	mov    %rbx,%rax
  40637a:	vmovups 0x160(%rsp),%ymm0
  406383:	vmovups 0x180(%rsp),%ymm1
  40638c:	vmovups %ymm1,0x74(%rsp)
  406392:	vmovups %ymm0,0x54(%rsp)
  406398:	movl   $0x0,(%rbx)
  40639e:	vmovups 0x50(%rsp),%ymm0
  4063a4:	vmovups 0x70(%rsp),%ymm1
  4063aa:	vmovups %ymm0,0x4(%rbx)
  4063af:	vmovups %ymm1,0x24(%rbx)
  4063b4:	mov    0x90(%rsp),%ecx
  4063bb:	mov    %ecx,0x44(%rbx)
  4063be:	jmp    4063ea <myl_f_522a0393f0b978ec89dcf0a01ed40fe4c77fd2e0c5e149267c4a06b2be768f98+0x3da>
  4063c0:	add    $0xc4,%dil
  4063c4:	cmp    $0x2,%dil
  4063c8:	jbe    40624e <myl_f_522a0393f0b978ec89dcf0a01ed40fe4c77fd2e0c5e149267c4a06b2be768f98+0x23e>
  4063ce:	mov    $0x4397d8,%rdx
  4063d5:	mov    (%rdx),%rdx
  4063d8:	movl   $0x1,(%rax)
  4063de:	mov    %rdx,0x8(%rax)
  4063e2:	mov    %r9,0x10(%rax)
  4063e6:	mov    %rcx,0x18(%rax)
  4063ea:	add    $0x1e0,%rsp
  4063f1:	pop    %rbx
  4063f2:	vzeroupper
  4063f5:	ret

Disassembly of section .fini:
