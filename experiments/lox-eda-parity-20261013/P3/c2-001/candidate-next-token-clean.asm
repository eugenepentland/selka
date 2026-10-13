
/home/epentland/ai/canopy/mylang/.tmp/lox-eda-parity/P3/c2-001/candidate-v2-application:     file format elf64-x86-64


Disassembly of section .text:

00000000010dddc0 <my.sexpr_parser::next_token>:
 10dddc0:	push   %rbp
 10dddc1:	push   %r15
 10dddc3:	push   %r14
 10dddc5:	push   %r13
 10dddc7:	push   %r12
 10dddc9:	push   %rbx
 10dddca:	sub    $0x58,%rsp
 10dddce:	mov    %r9,%r14
 10dddd1:	mov    %r8,%r15
 10dddd4:	mov    %rdx,%rbp
 10dddd7:	mov    %rsi,%r12
 10dddda:	mov    %rdi,0x28(%rsp)
 10ddddf:	movabs $0x800000000000,%rbx
 10ddde9:	mov    0x8(%rsi),%r13
 10ddded:	mov    (%rdx),%rsi
 10dddf0:	test   %rsi,%rsi
 10dddf3:	mov    %rcx,0x50(%rsp)
 10dddf8:	js     10dde42 <my.sexpr_parser::next_token+0x82>
 10dddfa:	cmp    %rbx,%r13
 10dddfd:	ja     10dee0d <my.sexpr_parser::next_token+0x104d>
 10dde03:	movabs $0x8000000000000000,%rax
 10dde0d:	mov    0x8(%rbp),%rcx
 10dde11:	mov    %r13,%rdx
 10dde14:	not    %rdx
 10dde17:	add    %rax,%rdx
 10dde1a:	mov    %rcx,0x18(%rsp)
 10dde1f:	cmp    %rdx,%rcx
 10dde22:	jg     10dde50 <my.sexpr_parser::next_token+0x90>
 10dde24:	mov    0x10(%rbp),%rcx
 10dde28:	cmp    %rdx,%rcx
 10dde2b:	jg     10dde50 <my.sexpr_parser::next_token+0x90>
 10dde2d:	cmp    %r13,%rsi
 10dde30:	jae    10de3b7 <my.sexpr_parser::next_token+0x5f7>
 10dde36:	lea    -0xd64f1(%rip),%rdx        # 100794c <core_number_pairs+0x2bc>
 10dde3d:	jmp    10de018 <my.sexpr_parser::next_token+0x258>
 10dde42:	cmp    %rbx,%r13
 10dde45:	ja     10de735 <my.sexpr_parser::next_token+0x975>
 10dde4b:	nopl   0x0(%rax,%rax,1)
 10dde50:	mov    $0xffffffffffffffff,%rax
 10dde57:	cmp    %r13,%rsi
 10dde5a:	jge    10dde86 <my.sexpr_parser::next_token+0xc6>
 10dde5c:	mov    %rsi,%rax
 10dde5f:	sar    $0x3f,%rax
 10dde63:	and    %r13,%rax
 10dde66:	add    %rsi,%rax
 10dde69:	cmp    %r13,%rax
 10dde6c:	jae    10ded68 <my.sexpr_parser::next_token+0xfa8>
 10dde72:	data16 data16 data16 data16 cs nopw 0x0(%rax,%rax,1)
 10dde80:	movzbl 0x20(%r12,%rax,1),%eax
 10dde86:	cmp    $0x3b,%rax
 10dde8a:	ja     10ddf55 <my.sexpr_parser::next_token+0x195>
 10dde90:	movabs $0x100002600,%rcx
 10dde9a:	bt     %rax,%rcx
 10dde9e:	jae    10ddee0 <my.sexpr_parser::next_token+0x120>
 10ddea0:	mov    %r12,%rdi
 10ddea3:	mov    %rbp,%rsi
 10ddea6:	call   1122f70 <my.sexpr_tokenizer::advance>
 10ddeab:	mov    0x8(%r12),%r13
 10ddeb0:	cmp    %rbx,%r13
 10ddeb3:	ja     10ded39 <my.sexpr_parser::next_token+0xf79>
 10ddeb9:	mov    0x0(%rbp),%rsi
 10ddebd:	cmp    %r13,%rsi
 10ddec0:	jge    10ddf55 <my.sexpr_parser::next_token+0x195>
 10ddec6:	mov    %rsi,%rax
 10ddec9:	sar    $0x3f,%rax
 10ddecd:	and    %r13,%rax
 10dded0:	add    %rsi,%rax
 10dded3:	cmp    %r13,%rax
 10dded6:	jb     10dde80 <my.sexpr_parser::next_token+0xc0>
 10dded8:	jmp    10ded4a <my.sexpr_parser::next_token+0xf8a>
 10ddedd:	nopl   (%rax)
 10ddee0:	cmp    $0x3b,%rax
 10ddee4:	jne    10ddf55 <my.sexpr_parser::next_token+0x195>
 10ddeea:	data16 data16 data16 data16 data16 cs nopw 0x0(%rax,%rax,1)
 10ddef9:	nopl   0x0(%rax)
 10ddf00:	mov    0x0(%rbp),%rsi
 10ddf04:	cmp    %r13,%rsi
 10ddf07:	jge    10dde50 <my.sexpr_parser::next_token+0x90>
 10ddf0d:	mov    %rsi,%rax
 10ddf10:	sar    $0x3f,%rax
 10ddf14:	and    %r13,%rax
 10ddf17:	add    %rsi,%rax
 10ddf1a:	cmp    %r13,%rax
 10ddf1d:	jae    10ded00 <my.sexpr_parser::next_token+0xf40>
 10ddf23:	cmpb   $0xa,0x20(%r12,%rax,1)
 10ddf29:	je     10dde50 <my.sexpr_parser::next_token+0x90>
 10ddf2f:	mov    %r12,%rdi
 10ddf32:	mov    %rbp,%rsi
 10ddf35:	call   1122f70 <my.sexpr_tokenizer::advance>
 10ddf3a:	mov    0x8(%r12),%r13
 10ddf3f:	cmp    %rbx,%r13
 10ddf42:	jbe    10ddf00 <my.sexpr_parser::next_token+0x140>
 10ddf44:	lea    0x87765(%rip),%rdi        # 11656b0 <core_durable_error.verbs+0x14f70>
 10ddf4b:	mov    %r13,%rsi
 10ddf4e:	xor    %edx,%edx
 10ddf50:	call   1085e00 <myl_core_trap>
 10ddf55:	mov    0x8(%rbp),%rax
 10ddf59:	mov    %rax,0x18(%rsp)
 10ddf5e:	mov    0x10(%rbp),%rax
 10ddf62:	mov    %rax,0x10(%rsp)
 10ddf67:	mov    %rsi,%r10
 10ddf6a:	mov    %r15,0x40(%rsp)
 10ddf6f:	mov    %r14,0x48(%rsp)
 10ddf74:	cmp    %rbx,%r13
 10ddf77:	ja     10dedb2 <my.sexpr_parser::next_token+0xff2>
 10ddf7d:	mov    $0x8,%r9d
 10ddf83:	mov    %r10,%r15
 10ddf86:	mov    %r10,%r14
 10ddf89:	cmp    %r13,%r10
 10ddf8c:	jge    10df2e2 <my.sexpr_parser::next_token+0x1522>
 10ddf92:	mov    %r10,%rax
 10ddf95:	sar    $0x3f,%rax
 10ddf99:	and    %r13,%rax
 10ddf9c:	add    %r10,%rax
 10ddf9f:	cmp    %r13,%rax
 10ddfa2:	jae    10dee2d <my.sexpr_parser::next_token+0x106d>
 10ddfa8:	lea    0x20(%r12),%rcx
 10ddfad:	mov    %rcx,0x20(%rsp)
 10ddfb2:	movzbl 0x20(%r12,%rax,1),%eax
 10ddfb8:	cmp    $0x22,%eax
 10ddfbb:	mov    %r10,0x8(%rsp)
 10ddfc0:	je     10de0fa <my.sexpr_parser::next_token+0x33a>
 10ddfc6:	cmp    $0x29,%eax
 10ddfc9:	je     10de0db <my.sexpr_parser::next_token+0x31b>
 10ddfcf:	cmp    $0x28,%eax
 10ddfd2:	jne    10de254 <my.sexpr_parser::next_token+0x494>
 10ddfd8:	mov    %r12,%rdi
 10ddfdb:	mov    %rbp,%rsi
 10ddfde:	call   1122f70 <my.sexpr_tokenizer::advance>
 10ddfe3:	mov    0x8(%rsp),%r10
 10ddfe8:	mov    0x0(%rbp),%r15
 10ddfec:	xor    %r9d,%r9d
 10ddfef:	jmp    10df2df <my.sexpr_parser::next_token+0x151f>
 10ddff4:	data16 data16 cs nopw 0x0(%rax,%rax,1)
 10de000:	mov    %rdi,%r8
 10de003:	inc    %rsi
 10de006:	mov    %rsi,%r10
 10de009:	mov    %r8,%rcx
 10de00c:	mov    %r10,%rsi
 10de00f:	cmp    %r13,%r10
 10de012:	jge    10de40a <my.sexpr_parser::next_token+0x64a>
 10de018:	cmp    %r13,%rsi
 10de01b:	jae    10dee1e <my.sexpr_parser::next_token+0x105e>
 10de021:	movzbl 0x20(%r12,%rsi,1),%edi
 10de027:	lea    -0x9(%rdi),%r8d
 10de02b:	cmp    $0x17,%r8d
 10de02f:	ja     10de050 <my.sexpr_parser::next_token+0x290>
 10de031:	movslq (%rdx,%r8,4),%rdi
 10de035:	add    %rdx,%rdi
 10de038:	jmp    *%rdi
 10de03a:	mov    %rcx,%rdi
 10de03d:	inc    %rdi
 10de040:	jo     10dee50 <my.sexpr_parser::next_token+0x1090>
 10de046:	cmp    %rax,%rdi
 10de049:	jne    10de000 <my.sexpr_parser::next_token+0x240>
 10de04b:	jmp    10dee3f <my.sexpr_parser::next_token+0x107f>
 10de050:	mov    %rcx,%r8
 10de053:	mov    %rsi,%r10
 10de056:	cmp    $0x3b,%edi
 10de059:	jne    10de3b7 <my.sexpr_parser::next_token+0x5f7>
 10de05f:	data16 data16 data16 data16 data16 cs nopw 0x0(%rax,%rax,1)
 10de06e:	data16 data16 data16 data16 data16 cs nopw 0x0(%rax,%rax,1)
 10de07d:	nopl   (%rax)
 10de080:	cmp    %r13,%r10
 10de083:	jae    10ded89 <my.sexpr_parser::next_token+0xfc9>
 10de089:	cmpb   $0xa,0x20(%r12,%r10,1)
 10de08f:	je     10de009 <my.sexpr_parser::next_token+0x249>
 10de095:	inc    %r8
 10de098:	jo     10ded9b <my.sexpr_parser::next_token+0xfdb>
 10de09e:	inc    %r10
 10de0a1:	cmp    %r10,%r13
 10de0a4:	jne    10de080 <my.sexpr_parser::next_token+0x2c0>
 10de0a6:	jmp    10de3fe <my.sexpr_parser::next_token+0x63e>
 10de0ab:	mov    0x18(%rsp),%r8
 10de0b0:	mov    %r8,%rcx
 10de0b3:	inc    %rcx
 10de0b6:	jo     10deeb9 <my.sexpr_parser::next_token+0x10f9>
 10de0bc:	cmp    %rax,%rcx
 10de0bf:	je     10deea8 <my.sexpr_parser::next_token+0x10e8>
 10de0c5:	inc    %rsi
 10de0c8:	mov    $0x1,%r8d
 10de0ce:	mov    %rsi,%r10
 10de0d1:	mov    %rcx,0x18(%rsp)
 10de0d6:	jmp    10de009 <my.sexpr_parser::next_token+0x249>
 10de0db:	mov    %r12,%rdi
 10de0de:	mov    %rbp,%rsi
 10de0e1:	call   1122f70 <my.sexpr_tokenizer::advance>
 10de0e6:	mov    0x8(%rsp),%r10
 10de0eb:	mov    0x0(%rbp),%r15
 10de0ef:	mov    $0x1,%r9d
 10de0f5:	jmp    10df2df <my.sexpr_parser::next_token+0x151f>
 10de0fa:	test   %r10,%r10
 10de0fd:	js     10de2df <my.sexpr_parser::next_token+0x51f>
 10de103:	movabs $0x8000000000000000,%rsi
 10de10d:	mov    %r13,%rax
 10de110:	not    %rax
 10de113:	add    %rsi,%rax
 10de116:	cmp    %rax,0x18(%rsp)
 10de11b:	jg     10de2df <my.sexpr_parser::next_token+0x51f>
 10de121:	cmp    %rax,0x10(%rsp)
 10de126:	jg     10de2df <my.sexpr_parser::next_token+0x51f>
 10de12c:	lea    0x1(%r10),%r14
 10de130:	mov    0x10(%rsp),%r9
 10de135:	lea    0x1(%r9),%rcx
 10de139:	cmp    %r13,%r14
 10de13c:	jae    10de7e3 <my.sexpr_parser::next_token+0xa23>
 10de142:	lea    0x2(%rsi),%rdx
 10de146:	mov    0x18(%rsp),%r12
 10de14b:	mov    %r12,%rax
 10de14e:	mov    %r14,%r15
 10de151:	jmp    10de18c <my.sexpr_parser::next_token+0x3cc>
 10de153:	data16 data16 data16 data16 data16 cs nopw 0x0(%rax,%rax,1)
 10de162:	data16 data16 data16 data16 data16 cs nopw 0x0(%rax,%rax,1)
 10de171:	data16 data16 data16 data16 data16 cs nopw 0x0(%rax,%rax,1)
 10de180:	inc    %r15
 10de183:	cmp    %r13,%r15
 10de186:	jge    10de7f3 <my.sexpr_parser::next_token+0xa33>
 10de18c:	cmp    %r13,%r15
 10de18f:	jae    10ded77 <my.sexpr_parser::next_token+0xfb7>
 10de195:	mov    0x20(%rsp),%rdi
 10de19a:	movzbl (%rdi,%r15,1),%edi
 10de19f:	cmp    $0x5c,%edi
 10de1a2:	je     10de200 <my.sexpr_parser::next_token+0x440>
 10de1a4:	cmp    $0x22,%edi
 10de1a7:	je     10de619 <my.sexpr_parser::next_token+0x859>
 10de1ad:	mov    %rcx,%r8
 10de1b0:	cmp    $0xa,%dil
 10de1b4:	jne    10de231 <my.sexpr_parser::next_token+0x471>
 10de1b6:	mov    %rax,%rdi
 10de1b9:	inc    %rdi
 10de1bc:	jo     10dedf9 <my.sexpr_parser::next_token+0x1039>
 10de1c2:	mov    $0x1,%ecx
 10de1c7:	mov    %rdi,%rax
 10de1ca:	jmp    10de180 <my.sexpr_parser::next_token+0x3c0>
 10de1cc:	data16 data16 data16 data16 data16 cs nopw 0x0(%rax,%rax,1)
 10de1db:	data16 data16 data16 data16 data16 cs nopw 0x0(%rax,%rax,1)
 10de1ea:	data16 data16 data16 data16 data16 cs nopw 0x0(%rax,%rax,1)
 10de1f9:	nopl   0x0(%rax)
 10de200:	mov    %rcx,%r8
 10de203:	inc    %r8
 10de206:	jo     10dedc3 <my.sexpr_parser::next_token+0x1003>
 10de20c:	cmp    %rdx,%r8
 10de20f:	jl     10dedd7 <my.sexpr_parser::next_token+0x1017>
 10de215:	inc    %r15
 10de218:	cmp    %r13,%r15
 10de21b:	jge    10de7f0 <my.sexpr_parser::next_token+0xa30>
 10de221:	mov    0x20(%rsp),%rcx
 10de226:	movzbl (%rcx,%r15,1),%edi
 10de22b:	cmp    $0xa,%dil
 10de22f:	je     10de1b6 <my.sexpr_parser::next_token+0x3f6>
 10de231:	mov    %r8,%rcx
 10de234:	inc    %rcx
 10de237:	jo     10dede5 <my.sexpr_parser::next_token+0x1025>
 10de23d:	cmp    %rdx,%rcx
 10de240:	jge    10de180 <my.sexpr_parser::next_token+0x3c0>
 10de246:	lea    0x87793(%rip),%rdi        # 11659e0 <core_durable_error.verbs+0x152a0>
 10de24d:	xor    %edx,%edx
 10de24f:	call   1085e00 <myl_core_trap>
 10de254:	lea    -0x30(%rax),%ecx
 10de257:	cmp    $0x9,%cl
 10de25a:	ja     10de3bc <my.sexpr_parser::next_token+0x5fc>
 10de260:	test   %r10,%r10
 10de263:	js     10de425 <my.sexpr_parser::next_token+0x665>
 10de269:	mov    %r13,%rdx
 10de26c:	not    %rdx
 10de26f:	movabs $0x8000000000000000,%rcx
 10de279:	add    %rdx,%rcx
 10de27c:	cmp    %rcx,0x18(%rsp)
 10de281:	jg     10de425 <my.sexpr_parser::next_token+0x665>
 10de287:	cmp    %rcx,0x10(%rsp)
 10de28c:	jg     10de425 <my.sexpr_parser::next_token+0x665>
 10de292:	xor    %eax,%eax
 10de294:	lea    0x20(%r12),%rcx
 10de299:	cmpb   $0x2d,(%rcx,%r10,1)
 10de29e:	sete   %al
 10de2a1:	add    %r10,%rax
 10de2a4:	cmp    %r13,%rax
 10de2a7:	mov    %r13,%r15
 10de2aa:	cmova  %rax,%r15
 10de2ae:	jae    10de749 <my.sexpr_parser::next_token+0x989>
 10de2b4:	cmp    %r13,%rax
 10de2b7:	jae    10dee87 <my.sexpr_parser::next_token+0x10c7>
 10de2bd:	lea    0x20(%r12),%rcx
 10de2c2:	movzbl (%rcx,%rax,1),%ecx
 10de2c6:	add    $0xd0,%cl
 10de2c9:	cmp    $0xa,%cl
 10de2cc:	jae    10de746 <my.sexpr_parser::next_token+0x986>
 10de2d2:	inc    %rax
 10de2d5:	cmp    %r13,%rax
 10de2d8:	jl     10de2b4 <my.sexpr_parser::next_token+0x4f4>
 10de2da:	jmp    10de749 <my.sexpr_parser::next_token+0x989>
 10de2df:	mov    %r12,%rdi
 10de2e2:	mov    %rbp,%rsi
 10de2e5:	call   1122f70 <my.sexpr_tokenizer::advance>
 10de2ea:	mov    0x8(%r12),%rdx
 10de2ef:	cmp    %rbx,%rdx
 10de2f2:	ja     10dec69 <my.sexpr_parser::next_token+0xea9>
 10de2f8:	mov    0x0(%rbp),%r14
 10de2fc:	lea    0x20(%r12),%r13
 10de301:	jmp    10de364 <my.sexpr_parser::next_token+0x5a4>
 10de303:	data16 data16 data16 data16 data16 cs nopw 0x0(%rax,%rax,1)
 10de312:	data16 data16 data16 data16 data16 cs nopw 0x0(%rax,%rax,1)
 10de321:	data16 data16 data16 data16 data16 cs nopw 0x0(%rax,%rax,1)
 10de330:	data16 data16 data16 data16 data16 cs nopw 0x0(%rax,%rax,1)
 10de33f:	nop
 10de340:	mov    %r12,%rdi
 10de343:	mov    %rbp,%rsi
 10de346:	call   1122f70 <my.sexpr_tokenizer::advance>
 10de34b:	mov    %r12,%rdi
 10de34e:	mov    %rbp,%rsi
 10de351:	call   1122f70 <my.sexpr_tokenizer::advance>
 10de356:	mov    0x8(%r12),%rdx
 10de35b:	cmp    %rbx,%rdx
 10de35e:	ja     10dec69 <my.sexpr_parser::next_token+0xea9>
 10de364:	mov    0x0(%rbp),%r15
 10de368:	cmp    %rdx,%r15
 10de36b:	mov    0x8(%rsp),%rcx
 10de370:	jge    10de702 <my.sexpr_parser::next_token+0x942>
 10de376:	mov    %r15,%rax
 10de379:	sar    $0x3f,%rax
 10de37d:	and    %rdx,%rax
 10de380:	add    %r15,%rax
 10de383:	cmp    %rdx,%rax
 10de386:	jae    10ded59 <my.sexpr_parser::next_token+0xf99>
 10de38c:	movzbl 0x0(%r13,%rax,1),%eax
 10de392:	cmp    $0x5c,%eax
 10de395:	je     10de340 <my.sexpr_parser::next_token+0x580>
 10de397:	cmp    $0x22,%eax
 10de39a:	jne    10de34b <my.sexpr_parser::next_token+0x58b>
 10de39c:	mov    %r12,%rdi
 10de39f:	mov    %rbp,%rsi
 10de3a2:	call   1122f70 <my.sexpr_tokenizer::advance>
 10de3a7:	mov    $0x3,%r9d
 10de3ad:	mov    0x8(%rsp),%r10
 10de3b2:	jmp    10df2e2 <my.sexpr_parser::next_token+0x1522>
 10de3b7:	mov    %rsi,%r10
 10de3ba:	jmp    10de407 <my.sexpr_parser::next_token+0x647>
 10de3bc:	cmp    $0x2d,%eax
 10de3bf:	jne    10de433 <my.sexpr_parser::next_token+0x673>
 10de3c1:	lea    0x1(%r10),%rsi
 10de3c5:	cmp    %r13,%rsi
 10de3c8:	jge    10de665 <my.sexpr_parser::next_token+0x8a5>
 10de3ce:	xor    %ecx,%ecx
 10de3d0:	cmp    $0xffffffffffffffff,%r10
 10de3d4:	cmovl  %r13,%rcx
 10de3d8:	add    %rsi,%rcx
 10de3db:	cmp    %r13,%rcx
 10de3de:	jae    10def11 <my.sexpr_parser::next_token+0x1151>
 10de3e4:	lea    0x20(%r12),%rdx
 10de3e9:	movzbl (%rdx,%rcx,1),%ecx
 10de3ed:	add    $0xd0,%cl
 10de3f0:	cmp    $0xa,%cl
 10de3f3:	jb     10de260 <my.sexpr_parser::next_token+0x4a0>
 10de3f9:	jmp    10de665 <my.sexpr_parser::next_token+0x8a5>
 10de3fe:	add    %r13,%rcx
 10de401:	sub    %rsi,%rcx
 10de404:	mov    %r13,%r10
 10de407:	mov    %rcx,%r8
 10de40a:	mov    %r10,0x0(%rbp)
 10de40e:	mov    0x18(%rsp),%rax
 10de413:	mov    %rax,0x8(%rbp)
 10de417:	mov    %r8,0x10(%rsp)
 10de41c:	mov    %r8,0x10(%rbp)
 10de420:	jmp    10ddf6a <my.sexpr_parser::next_token+0x1aa>
 10de425:	cmp    $0x2d,%eax
 10de428:	jne    10defd6 <my.sexpr_parser::next_token+0x1216>
 10de42e:	jmp    10defbd <my.sexpr_parser::next_token+0x11fd>
 10de433:	mov    %eax,%ecx
 10de435:	and    $0xffffffdf,%ecx
 10de438:	add    $0xffffffbf,%ecx
 10de43b:	cmp    $0x1a,%ecx
 10de43e:	jae    10de649 <my.sexpr_parser::next_token+0x889>
 10de444:	test   %r10,%r10
 10de447:	js     10de4de <my.sexpr_parser::next_token+0x71e>
 10de44d:	mov    %r13,%rcx
 10de450:	not    %rcx
 10de453:	movabs $0x8000000000000000,%rax
 10de45d:	add    %rcx,%rax
 10de460:	cmp    %rax,0x18(%rsp)
 10de465:	jg     10de4de <my.sexpr_parser::next_token+0x71e>
 10de467:	cmp    %rax,0x10(%rsp)
 10de46c:	jg     10de4de <my.sexpr_parser::next_token+0x71e>
 10de46e:	cmp    %r10,%r13
 10de471:	mov    %r10,%rsi
 10de474:	cmova  %r13,%rsi
 10de478:	vmovd  -0xda210(%rip),%xmm0        # 1004270 <__anon_1393+0x50>
 10de480:	mov    %r10,%r15
 10de483:	mov    0x10(%rsp),%rdi
 10de488:	jmp    10de59b <my.sexpr_parser::next_token+0x7db>
 10de48d:	data16 data16 data16 data16 data16 cs nopw 0x0(%rax,%rax,1)
 10de49c:	data16 data16 data16 data16 data16 cs nopw 0x0(%rax,%rax,1)
 10de4ab:	data16 data16 data16 data16 data16 cs nopw 0x0(%rax,%rax,1)
 10de4ba:	nopw   0x0(%rax,%rax,1)
 10de4c0:	mov    %r12,%rdi
 10de4c3:	mov    %rbp,%rsi
 10de4c6:	call   1122f70 <my.sexpr_tokenizer::advance>
 10de4cb:	mov    0x8(%rsp),%r10
 10de4d0:	mov    0x8(%r12),%r13
 10de4d5:	cmp    %rbx,%r13
 10de4d8:	ja     10dee76 <my.sexpr_parser::next_token+0x10b6>
 10de4de:	mov    0x0(%rbp),%r15
 10de4e2:	mov    $0x2,%r9d
 10de4e8:	cmp    %r13,%r15
 10de4eb:	jge    10df2df <my.sexpr_parser::next_token+0x151f>
 10de4f1:	mov    %r15,%rax
 10de4f4:	sar    $0x3f,%rax
 10de4f8:	and    %r13,%rax
 10de4fb:	add    %r15,%rax
 10de4fe:	cmp    %r13,%rax
 10de501:	jae    10dee64 <my.sexpr_parser::next_token+0x10a4>
 10de507:	lea    0x20(%r12),%rcx
 10de50c:	movzbl (%rcx,%rax,1),%eax
 10de510:	mov    %eax,%edx
 10de512:	and    $0xdf,%edx
 10de518:	add    $0xffffffbf,%edx
 10de51b:	mov    $0x1,%cl
 10de51d:	cmp    $0x1a,%edx
 10de520:	jae    10de574 <my.sexpr_parser::next_token+0x7b4>
 10de522:	vmovd  %eax,%xmm0
 10de526:	vpbroadcastb %xmm0,%xmm0
 10de52b:	vpcmpeqb -0xda2c3(%rip),%xmm0,%xmm0        # 1004270 <__anon_1393+0x50>
 10de533:	vpmovsxbd %xmm0,%xmm0
 10de538:	vmovmskps %xmm0,%edx
 10de53c:	test   %edx,%edx
 10de53e:	jne    10de4c0 <my.sexpr_parser::next_token+0x700>
 10de540:	mov    %eax,%edx
 10de542:	and    $0xfffffffd,%edx
 10de545:	cmp    $0x2d,%edx
 10de548:	je     10de4c0 <my.sexpr_parser::next_token+0x700>
 10de54e:	mov    %eax,%edx
 10de550:	and    $0xfffffffb,%edx
 10de553:	cmp    $0x2a,%edx
 10de556:	je     10de4c0 <my.sexpr_parser::next_token+0x700>
 10de55c:	add    $0xffffffd5,%eax
 10de55f:	cmp    $0x2,%al
 10de561:	jb     10de4c0 <my.sexpr_parser::next_token+0x700>
 10de567:	test   %cl,%cl
 10de569:	jne    10de4c0 <my.sexpr_parser::next_token+0x700>
 10de56f:	jmp    10df2df <my.sexpr_parser::next_token+0x151f>
 10de574:	cmp    $0x2a,%rax
 10de578:	je     10de522 <my.sexpr_parser::next_token+0x762>
 10de57a:	cmp    $0x5f,%eax
 10de57d:	je     10de522 <my.sexpr_parser::next_token+0x762>
 10de57f:	cmp    $0x7e,%eax
 10de582:	je     10de522 <my.sexpr_parser::next_token+0x762>
 10de584:	lea    -0x30(%rax),%ecx
 10de587:	cmp    $0xa,%cl
 10de58a:	setb   %cl
 10de58d:	jmp    10de522 <my.sexpr_parser::next_token+0x762>
 10de58f:	inc    %r15
 10de592:	cmp    %r15,%r13
 10de595:	je     10de7bb <my.sexpr_parser::next_token+0x9fb>
 10de59b:	cmp    %r13,%r15
 10de59e:	jae    10dee99 <my.sexpr_parser::next_token+0x10d9>
 10de5a4:	mov    0x20(%rsp),%rax
 10de5a9:	movzbl (%rax,%r15,1),%eax
 10de5ae:	mov    %eax,%edx
 10de5b0:	and    $0xdf,%edx
 10de5b6:	add    $0xffffffbf,%edx
 10de5b9:	mov    $0x1,%cl
 10de5bb:	cmp    $0x1a,%edx
 10de5be:	jae    10de5fe <my.sexpr_parser::next_token+0x83e>
 10de5c0:	vmovd  %eax,%xmm1
 10de5c4:	vpbroadcastb %xmm1,%xmm1
 10de5c9:	vpcmpeqb %xmm0,%xmm1,%xmm1
 10de5cd:	vpmovsxbd %xmm1,%xmm1
 10de5d2:	vmovmskps %xmm1,%edx
 10de5d6:	test   %edx,%edx
 10de5d8:	jne    10de58f <my.sexpr_parser::next_token+0x7cf>
 10de5da:	mov    %eax,%edx
 10de5dc:	and    $0xfffffffd,%edx
 10de5df:	cmp    $0x2d,%edx
 10de5e2:	je     10de58f <my.sexpr_parser::next_token+0x7cf>
 10de5e4:	mov    %eax,%edx
 10de5e6:	and    $0xfffffffb,%edx
 10de5e9:	cmp    $0x2a,%edx
 10de5ec:	je     10de58f <my.sexpr_parser::next_token+0x7cf>
 10de5ee:	add    $0xffffffd5,%eax
 10de5f1:	cmp    $0x2,%al
 10de5f3:	jb     10de58f <my.sexpr_parser::next_token+0x7cf>
 10de5f5:	test   %cl,%cl
 10de5f7:	jne    10de58f <my.sexpr_parser::next_token+0x7cf>
 10de5f9:	jmp    10de7be <my.sexpr_parser::next_token+0x9fe>
 10de5fe:	cmp    $0x2a,%rax
 10de602:	je     10de5c0 <my.sexpr_parser::next_token+0x800>
 10de604:	cmp    $0x5f,%eax
 10de607:	je     10de5c0 <my.sexpr_parser::next_token+0x800>
 10de609:	cmp    $0x7e,%eax
 10de60c:	je     10de5c0 <my.sexpr_parser::next_token+0x800>
 10de60e:	lea    -0x30(%rax),%ecx
 10de611:	cmp    $0xa,%cl
 10de614:	setb   %cl
 10de617:	jmp    10de5c0 <my.sexpr_parser::next_token+0x800>
 10de619:	lea    0x1(%r15),%rdi
 10de61d:	mov    %rdi,0x0(%rbp)
 10de621:	mov    %rax,0x8(%rbp)
 10de625:	mov    %rcx,%rax
 10de628:	inc    %rax
 10de62b:	jo     10deecd <my.sexpr_parser::next_token+0x110d>
 10de631:	cmp    %rdx,%rax
 10de634:	jl     10deee1 <my.sexpr_parser::next_token+0x1121>
 10de63a:	mov    %rax,0x10(%rbp)
 10de63e:	mov    $0x3,%r9d
 10de644:	jmp    10df2e2 <my.sexpr_parser::next_token+0x1522>
 10de649:	cmp    $0x2a,%rax
 10de64d:	je     10de444 <my.sexpr_parser::next_token+0x684>
 10de653:	cmp    $0x5f,%eax
 10de656:	je     10de444 <my.sexpr_parser::next_token+0x684>
 10de65c:	cmp    $0x7e,%eax
 10de65f:	je     10de444 <my.sexpr_parser::next_token+0x684>
 10de665:	mov    %eax,%ecx
 10de667:	and    $0xfffffffb,%ecx
 10de66a:	cmp    $0x2b,%ecx
 10de66d:	je     10de68d <my.sexpr_parser::next_token+0x8cd>
 10de66f:	mov    %eax,%ecx
 10de671:	and    $0xfffffff7,%ecx
 10de674:	cmp    $0x25,%ecx
 10de677:	je     10de68d <my.sexpr_parser::next_token+0x8cd>
 10de679:	cmp    $0x21,%al
 10de67b:	je     10de68d <my.sexpr_parser::next_token+0x8cd>
 10de67d:	cmp    $0x3d,%al
 10de67f:	je     10de68d <my.sexpr_parser::next_token+0x8cd>
 10de681:	and    $0xfffffffd,%eax
 10de684:	cmp    $0x3c,%eax
 10de687:	jne    10de883 <my.sexpr_parser::next_token+0xac3>
 10de68d:	mov    %r12,%rdi
 10de690:	mov    %rbp,%rsi
 10de693:	call   1122f70 <my.sexpr_tokenizer::advance>
 10de698:	mov    0x8(%r12),%rdx
 10de69d:	cmp    %rbx,%rdx
 10de6a0:	ja     10deeef <my.sexpr_parser::next_token+0x112f>
 10de6a6:	mov    0x0(%rbp),%r15
 10de6aa:	mov    $0x2,%r9d
 10de6b0:	cmp    %rdx,%r15
 10de6b3:	mov    0x8(%rsp),%r10
 10de6b8:	lea    0x20(%r12),%rcx
 10de6bd:	jge    10df2df <my.sexpr_parser::next_token+0x151f>
 10de6c3:	mov    %r15,%rax
 10de6c6:	sar    $0x3f,%rax
 10de6ca:	and    %rdx,%rax
 10de6cd:	add    %r15,%rax
 10de6d0:	cmp    %rdx,%rax
 10de6d3:	jae    10def20 <my.sexpr_parser::next_token+0x1160>
 10de6d9:	cmpb   $0x3d,(%rcx,%rax,1)
 10de6dd:	jne    10df2df <my.sexpr_parser::next_token+0x151f>
 10de6e3:	mov    %r12,%rdi
 10de6e6:	mov    %rbp,%rsi
 10de6e9:	call   1122f70 <my.sexpr_tokenizer::advance>
 10de6ee:	mov    $0x2,%r9d
 10de6f4:	mov    0x8(%rsp),%r10
 10de6f9:	mov    0x0(%rbp),%r15
 10de6fd:	jmp    10df2df <my.sexpr_parser::next_token+0x151f>
 10de702:	mov    0x18(%rsp),%r12
 10de707:	mov    %r12,0x18(%rbp)
 10de70b:	mov    0x10(%rsp),%rax
 10de710:	mov    %rax,0x20(%rbp)
 10de714:	mov    %rcx,0x28(%rbp)
 10de718:	lea    0x8fc01(%rip),%rdi        # 116e320 <core_durable_error.verbs+0x1dbe0>
 10de71f:	call   10b81c0 <myl_core_err_trace_origin_preserve_most>
 10de724:	lea    0x87105(%rip),%rdi        # 1165830 <core_durable_error.verbs+0x150f0>
 10de72b:	call   10b8200 <myl_core_err_trace_append_preserve_most>
 10de730:	jmp    10de817 <my.sexpr_parser::next_token+0xa57>
 10de735:	lea    0x86f74(%rip),%rdi        # 11656b0 <core_durable_error.verbs+0x14f70>
 10de73c:	mov    %r13,%rsi
 10de73f:	xor    %edx,%edx
 10de741:	call   1085e00 <myl_core_trap>
 10de746:	mov    %rax,%r15
 10de749:	lea    0x1(%r15),%rsi
 10de74d:	mov    $0x4,%edi
 10de752:	cmp    %r13,%rsi
 10de755:	jge    10de8bc <my.sexpr_parser::next_token+0xafc>
 10de75b:	cmp    %r13,%r15
 10de75e:	jae    10def2f <my.sexpr_parser::next_token+0x116f>
 10de764:	lea    0x20(%r12),%rax
 10de769:	cmpb   $0x2e,(%rax,%r15,1)
 10de76e:	jne    10de8bc <my.sexpr_parser::next_token+0xafc>
 10de774:	cmp    %r13,%rsi
 10de777:	jae    10def81 <my.sexpr_parser::next_token+0x11c1>
 10de77d:	lea    0x20(%r12),%rax
 10de782:	movzbl (%rax,%rsi,1),%eax
 10de786:	add    $0xd0,%al
 10de788:	cmp    $0x9,%al
 10de78a:	ja     10de8bc <my.sexpr_parser::next_token+0xafc>
 10de790:	lea    -0x1(%r13),%rax
 10de794:	movzbl 0x21(%r12,%r15,1),%ecx
 10de79a:	add    $0xd0,%cl
 10de79d:	inc    %r15
 10de7a0:	cmp    $0xa,%cl
 10de7a3:	jae    10de8b7 <my.sexpr_parser::next_token+0xaf7>
 10de7a9:	cmp    %r15,%rax
 10de7ac:	jne    10de794 <my.sexpr_parser::next_token+0x9d4>
 10de7ae:	mov    $0x5,%edi
 10de7b3:	mov    %r13,%r15
 10de7b6:	jmp    10de8bc <my.sexpr_parser::next_token+0xafc>
 10de7bb:	mov    %rsi,%r15
 10de7be:	mov    %r15,%rdx
 10de7c1:	sub    %r10,%rdx
 10de7c4:	mov    %rdi,%rax
 10de7c7:	add    %rdx,%rax
 10de7ca:	jo     10def5f <my.sexpr_parser::next_token+0x119f>
 10de7d0:	mov    %rax,0x10(%rbp)
 10de7d4:	mov    %r15,0x0(%rbp)
 10de7d8:	mov    $0x2,%r9d
 10de7de:	jmp    10df2df <my.sexpr_parser::next_token+0x151f>
 10de7e3:	mov    %r14,%r15
 10de7e6:	mov    0x18(%rsp),%r12
 10de7eb:	mov    %r12,%rax
 10de7ee:	jmp    10de7f3 <my.sexpr_parser::next_token+0xa33>
 10de7f0:	mov    %r8,%rcx
 10de7f3:	mov    %r15,0x0(%rbp)
 10de7f7:	mov    %rax,0x8(%rbp)
 10de7fb:	mov    %rcx,0x10(%rbp)
 10de7ff:	mov    %r12,0x18(%rbp)
 10de803:	mov    %r9,0x20(%rbp)
 10de807:	mov    %r10,0x28(%rbp)
 10de80b:	lea    0x8707e(%rip),%rdi        # 1165890 <core_durable_error.verbs+0x15150>
 10de812:	call   10b81c0 <myl_core_err_trace_origin_preserve_most>
 10de817:	lea    0x82752(%rip),%rdi        # 1160f70 <core_durable_error.verbs+0x10830>
 10de81e:	call   10b8200 <myl_core_err_trace_append_preserve_most>
 10de823:	lea    -0x7a16a(%rip),%rbx        # 10646c0 <core_number_pairs+0x5d030>
 10de82a:	mov    $0x3,%r14d
 10de830:	mov    0x28(%rsp),%r15
 10de835:	lea    0x7ecb4(%rip),%rdi        # 115d4f0 <core_durable_error.verbs+0xcdb0>
 10de83c:	call   10b8200 <myl_core_err_trace_append_preserve_most>
 10de841:	mov    0x90(%rsp),%rdi
 10de849:	call   1085080 <myl_core_drop_owned>
 10de84e:	lea    0x79d7b(%rip),%rdi        # 11585d0 <core_durable_error.verbs+0x7e90>
 10de855:	call   10b81c0 <myl_core_err_trace_origin_preserve_most>
 10de85a:	mov    %r15,%rax
 10de85d:	movq   $0x1,(%r15)
 10de864:	mov    %r14,0x8(%r15)
 10de868:	mov    %r12,0x68(%r15)
 10de86c:	mov    0x10(%rsp),%rcx
 10de871:	mov    %rcx,0x70(%r15)
 10de875:	mov    0x8(%rsp),%rcx
 10de87a:	mov    %rcx,0x78(%r15)
 10de87e:	jmp    10df333 <my.sexpr_parser::next_token+0x1573>
 10de883:	mov    0x18(%rsp),%r12
 10de888:	mov    %r12,0x18(%rbp)
 10de88c:	mov    0x10(%rsp),%rax
 10de891:	mov    %rax,0x20(%rbp)
 10de895:	mov    %r10,0x28(%rbp)
 10de899:	lea    0x82700(%rip),%rdi        # 1160fa0 <core_durable_error.verbs+0x10860>
 10de8a0:	call   10b81c0 <myl_core_err_trace_origin_preserve_most>
 10de8a5:	lea    -0x7a22c(%rip),%rbx        # 1064680 <core_number_pairs+0x5cff0>
 10de8ac:	mov    $0x2,%r14d
 10de8b2:	jmp    10de830 <my.sexpr_parser::next_token+0xa70>
 10de8b7:	mov    $0x5,%edi
 10de8bc:	mov    %r15,%rdx
 10de8bf:	sub    %r10,%rdx
 10de8c2:	mov    0x10(%rsp),%rsi
 10de8c7:	add    %rdx,%rsi
 10de8ca:	jo     10def00 <my.sexpr_parser::next_token+0x1140>
 10de8d0:	mov    %rsi,0x10(%rbp)
 10de8d4:	mov    %r15,0x0(%rbp)
 10de8d8:	cmp    %r13,%r15
 10de8db:	jge    10dea53 <my.sexpr_parser::next_token+0xc93>
 10de8e1:	jae    10def41 <my.sexpr_parser::next_token+0x1181>
 10de8e7:	lea    0x20(%r12),%rax
 10de8ec:	cmpb   $0x6d,(%rax,%r15,1)
 10de8f1:	jne    10dea53 <my.sexpr_parser::next_token+0xc93>
 10de8f7:	lea    0x1(%r15),%rax
 10de8fb:	cmp    %r13,%rax
 10de8fe:	jge    10dea53 <my.sexpr_parser::next_token+0xc93>
 10de904:	lea    0x20(%r12),%rcx
 10de909:	movzbl (%rcx,%rax,1),%eax
 10de90d:	cmp    $0x69,%eax
 10de910:	je     10de9a1 <my.sexpr_parser::next_token+0xbe1>
 10de916:	cmp    $0x6d,%eax
 10de919:	jne    10dea53 <my.sexpr_parser::next_token+0xc93>
 10de91f:	lea    0x2(%r15),%rax
 10de923:	cmp    %r13,%rax
 10de926:	jge    10dea2d <my.sexpr_parser::next_token+0xc6d>
 10de92c:	lea    0x20(%r12),%rcx
 10de931:	movzbl (%rcx,%rax,1),%eax
 10de935:	mov    %eax,%edx
 10de937:	and    $0xdf,%edx
 10de93d:	add    $0xffffffbf,%edx
 10de940:	mov    $0x1,%cl
 10de942:	cmp    $0x1a,%edx
 10de945:	jae    10decd6 <my.sexpr_parser::next_token+0xf16>
 10de94b:	vmovd  %eax,%xmm0
 10de94f:	vpbroadcastb %xmm0,%xmm0
 10de954:	vpcmpeqb -0xda6ec(%rip),%xmm0,%xmm0        # 1004270 <__anon_1393+0x50>
 10de95c:	vpmovsxbd %xmm0,%xmm0
 10de961:	vmovmskps %xmm0,%edx
 10de965:	test   %edx,%edx
 10de967:	jne    10dea53 <my.sexpr_parser::next_token+0xc93>
 10de96d:	mov    %eax,%edx
 10de96f:	and    $0xfffffffd,%edx
 10de972:	cmp    $0x2d,%edx
 10de975:	je     10dea53 <my.sexpr_parser::next_token+0xc93>
 10de97b:	mov    %eax,%edx
 10de97d:	and    $0xfffffffb,%edx
 10de980:	cmp    $0x2a,%edx
 10de983:	je     10dea53 <my.sexpr_parser::next_token+0xc93>
 10de989:	add    $0xffffffd5,%eax
 10de98c:	cmp    $0x2,%al
 10de98e:	jb     10dea53 <my.sexpr_parser::next_token+0xc93>
 10de994:	test   %cl,%cl
 10de996:	je     10dea2d <my.sexpr_parser::next_token+0xc6d>
 10de99c:	jmp    10dea53 <my.sexpr_parser::next_token+0xc93>
 10de9a1:	lea    0x2(%r15),%rax
 10de9a5:	cmp    %r13,%rax
 10de9a8:	jge    10dea53 <my.sexpr_parser::next_token+0xc93>
 10de9ae:	lea    0x20(%r12),%rcx
 10de9b3:	cmpb   $0x6c,(%rcx,%rax,1)
 10de9b7:	jne    10dea53 <my.sexpr_parser::next_token+0xc93>
 10de9bd:	lea    0x3(%r15),%rax
 10de9c1:	cmp    %r13,%rax
 10de9c4:	jge    10dea22 <my.sexpr_parser::next_token+0xc62>
 10de9c6:	lea    0x20(%r12),%rcx
 10de9cb:	movzbl (%rcx,%rax,1),%eax
 10de9cf:	mov    %eax,%edx
 10de9d1:	and    $0xdf,%edx
 10de9d7:	add    $0xffffffbf,%edx
 10de9da:	mov    $0x1,%cl
 10de9dc:	cmp    $0x1a,%edx
 10de9df:	jae    10ded0f <my.sexpr_parser::next_token+0xf4f>
 10de9e5:	vmovd  %eax,%xmm0
 10de9e9:	vpbroadcastb %xmm0,%xmm0
 10de9ee:	vpcmpeqb -0xda786(%rip),%xmm0,%xmm0        # 1004270 <__anon_1393+0x50>
 10de9f6:	vpmovsxbd %xmm0,%xmm0
 10de9fb:	vmovmskps %xmm0,%edx
 10de9ff:	test   %edx,%edx
 10dea01:	jne    10dea53 <my.sexpr_parser::next_token+0xc93>
 10dea03:	mov    %eax,%edx
 10dea05:	and    $0xfffffffd,%edx
 10dea08:	cmp    $0x2d,%edx
 10dea0b:	je     10dea53 <my.sexpr_parser::next_token+0xc93>
 10dea0d:	mov    %eax,%edx
 10dea0f:	and    $0xfffffffb,%edx
 10dea12:	cmp    $0x2a,%edx
 10dea15:	je     10dea53 <my.sexpr_parser::next_token+0xc93>
 10dea17:	add    $0xffffffd5,%eax
 10dea1a:	cmp    $0x2,%al
 10dea1c:	jb     10dea53 <my.sexpr_parser::next_token+0xc93>
 10dea1e:	test   %cl,%cl
 10dea20:	jne    10dea53 <my.sexpr_parser::next_token+0xc93>
 10dea22:	mov    %r12,%rdi
 10dea25:	mov    %rbp,%rsi
 10dea28:	call   1122f70 <my.sexpr_tokenizer::advance>
 10dea2d:	mov    %r12,%rdi
 10dea30:	mov    %rbp,%rsi
 10dea33:	call   1122f70 <my.sexpr_tokenizer::advance>
 10dea38:	mov    %r12,%rdi
 10dea3b:	mov    %rbp,%rsi
 10dea3e:	call   1122f70 <my.sexpr_tokenizer::advance>
 10dea43:	mov    0x8(%rsp),%r10
 10dea48:	mov    $0x6,%r9d
 10dea4e:	jmp    10df2df <my.sexpr_parser::next_token+0x151f>
 10dea53:	mov    %rsi,0x30(%rsp)
 10dea58:	mov    %rdi,0x38(%rsp)
 10dea5d:	mov    %r12,%rdi
 10dea60:	mov    %rbp,%rsi
 10dea63:	call   1135f80 <my.sexpr_tokenizer::si_suffix_len>
 10dea68:	test   %rax,%rax
 10dea6b:	je     10dea95 <my.sexpr_parser::next_token+0xcd5>
 10dea6d:	mov    %rax,%r14
 10dea70:	data16 data16 data16 data16 data16 cs nopw 0x0(%rax,%rax,1)
 10dea7f:	nop
 10dea80:	mov    %r12,%rdi
 10dea83:	mov    %rbp,%rsi
 10dea86:	call   1122f70 <my.sexpr_tokenizer::advance>
 10dea8b:	dec    %r14
 10dea8e:	jne    10dea80 <my.sexpr_parser::next_token+0xcc0>
 10dea90:	jmp    10df2d0 <my.sexpr_parser::next_token+0x1510>
 10dea95:	mov    0x8(%r12),%rdx
 10dea9a:	cmp    %rbx,%rdx
 10dea9d:	mov    0x38(%rsp),%r9
 10deaa2:	ja     10def70 <my.sexpr_parser::next_token+0x11b0>
 10deaa8:	cmp    %rdx,%r15
 10deaab:	mov    0x8(%rsp),%r10
 10deab0:	jge    10df2df <my.sexpr_parser::next_token+0x151f>
 10deab6:	jae    10def90 <my.sexpr_parser::next_token+0x11d0>
 10deabc:	lea    0x20(%r12),%rax
 10deac1:	movzbl (%rax,%r15,1),%eax
 10deac6:	cmp    $0x25,%al
 10deac8:	jne    10deb49 <my.sexpr_parser::next_token+0xd89>
 10deaca:	lea    0x1(%r15),%rcx
 10deace:	cmp    %rdx,%rcx
 10dead1:	jae    10df419 <my.sexpr_parser::next_token+0x1659>
 10dead7:	lea    0x20(%r12),%rsi
 10deadc:	movzbl (%rsi,%rcx,1),%esi
 10deae0:	mov    %esi,%ecx
 10deae2:	and    $0xdf,%ecx
 10deae8:	add    $0xffffffbf,%ecx
 10deaeb:	mov    $0x1,%dil
 10deaee:	cmp    $0x1a,%ecx
 10deaf1:	jae    10dec7a <my.sexpr_parser::next_token+0xeba>
 10deaf7:	vmovd  %esi,%xmm0
 10deafb:	vpbroadcastb %xmm0,%xmm0
 10deb00:	vpcmpeqb -0xda898(%rip),%xmm0,%xmm0        # 1004270 <__anon_1393+0x50>
 10deb08:	vpmovsxbd %xmm0,%xmm0
 10deb0d:	vmovmskps %xmm0,%r8d
 10deb11:	mov    $0x25,%ecx
 10deb16:	test   %r8d,%r8d
 10deb19:	jne    10deb6d <my.sexpr_parser::next_token+0xdad>
 10deb1b:	mov    %esi,%r8d
 10deb1e:	and    $0xfffffffd,%r8d
 10deb22:	cmp    $0x2d,%r8d
 10deb26:	je     10deb6d <my.sexpr_parser::next_token+0xdad>
 10deb28:	mov    %esi,%r8d
 10deb2b:	and    $0xfffffffb,%r8d
 10deb2f:	cmp    $0x2a,%r8d
 10deb33:	je     10deb6d <my.sexpr_parser::next_token+0xdad>
 10deb35:	add    $0xffffffd5,%esi
 10deb38:	cmp    $0x2,%sil
 10deb3c:	jb     10deb6d <my.sexpr_parser::next_token+0xdad>
 10deb3e:	test   %dil,%dil
 10deb41:	je     10df419 <my.sexpr_parser::next_token+0x1659>
 10deb47:	jmp    10deb6d <my.sexpr_parser::next_token+0xdad>
 10deb49:	movzbl %al,%ecx
 10deb4c:	mov    %ecx,%edi
 10deb4e:	and    $0xdf,%edi
 10deb54:	add    $0xffffffbf,%edi
 10deb57:	mov    $0x1,%sil
 10deb5a:	cmp    $0x1a,%edi
 10deb5d:	jb     10deb78 <my.sexpr_parser::next_token+0xdb8>
 10deb5f:	cmp    $0x2a,%al
 10deb61:	je     10deb78 <my.sexpr_parser::next_token+0xdb8>
 10deb63:	cmp    $0x5f,%ecx
 10deb66:	je     10deb78 <my.sexpr_parser::next_token+0xdb8>
 10deb68:	cmp    $0x7e,%ecx
 10deb6b:	je     10deb78 <my.sexpr_parser::next_token+0xdb8>
 10deb6d:	lea    -0x30(%rax),%esi
 10deb70:	cmp    $0xa,%sil
 10deb74:	setb   %sil
 10deb78:	vmovd  %eax,%xmm0
 10deb7c:	vpbroadcastb %xmm0,%xmm0
 10deb81:	vpcmpeqb -0xda919(%rip),%xmm0,%xmm0        # 1004270 <__anon_1393+0x50>
 10deb89:	vpmovsxbd %xmm0,%xmm0
 10deb8e:	vmovmskps %xmm0,%edi
 10deb92:	test   %edi,%edi
 10deb94:	jne    10debb7 <my.sexpr_parser::next_token+0xdf7>
 10deb96:	mov    %ecx,%edi
 10deb98:	and    $0xfffffffd,%edi
 10deb9b:	cmp    $0x2d,%edi
 10deb9e:	je     10debb7 <my.sexpr_parser::next_token+0xdf7>
 10deba0:	and    $0xfffffffb,%ecx
 10deba3:	cmp    $0x2a,%ecx
 10deba6:	je     10debb7 <my.sexpr_parser::next_token+0xdf7>
 10deba8:	add    $0xd5,%al
 10debaa:	cmp    $0x2,%al
 10debac:	jb     10debb7 <my.sexpr_parser::next_token+0xdf7>
 10debae:	test   %sil,%sil
 10debb1:	je     10df2df <my.sexpr_parser::next_token+0x151f>
 10debb7:	mov    %r15,%rsi
 10debba:	cmp    %r13,%r15
 10debbd:	mov    0x30(%rsp),%r8
 10debc2:	jge    10deca8 <my.sexpr_parser::next_token+0xee8>
 10debc8:	vmovd  -0xda960(%rip),%xmm0        # 1004270 <__anon_1393+0x50>
 10debd0:	mov    %r15,%rsi
 10debd3:	jmp    10debe1 <my.sexpr_parser::next_token+0xe21>
 10debd5:	inc    %rsi
 10debd8:	cmp    %rsi,%r13
 10debdb:	je     10deca5 <my.sexpr_parser::next_token+0xee5>
 10debe1:	mov    %rsi,%rax
 10debe4:	sar    $0x3f,%rax
 10debe8:	and    %rdx,%rax
 10debeb:	lea    (%rax,%rsi,1),%rcx
 10debef:	cmp    %rdx,%rcx
 10debf2:	jae    10def53 <my.sexpr_parser::next_token+0x1193>
 10debf8:	add    0x20(%rsp),%rax
 10debfd:	movzbl (%rsi,%rax,1),%eax
 10dec01:	mov    %eax,%edi
 10dec03:	and    $0xdf,%edi
 10dec09:	add    $0xffffffbf,%edi
 10dec0c:	mov    $0x1,%cl
 10dec0e:	cmp    $0x1a,%edi
 10dec11:	jae    10dec4e <my.sexpr_parser::next_token+0xe8e>
 10dec13:	vmovd  %eax,%xmm1
 10dec17:	vpbroadcastb %xmm1,%xmm1
 10dec1c:	vpcmpeqb %xmm0,%xmm1,%xmm1
 10dec20:	vpmovsxbd %xmm1,%xmm1
 10dec25:	vmovmskps %xmm1,%edi
 10dec29:	test   %edi,%edi
 10dec2b:	jne    10debd5 <my.sexpr_parser::next_token+0xe15>
 10dec2d:	mov    %eax,%edi
 10dec2f:	and    $0xfffffffd,%edi
 10dec32:	cmp    $0x2d,%edi
 10dec35:	je     10debd5 <my.sexpr_parser::next_token+0xe15>
 10dec37:	mov    %eax,%edi
 10dec39:	and    $0xfffffffb,%edi
 10dec3c:	cmp    $0x2a,%edi
 10dec3f:	je     10debd5 <my.sexpr_parser::next_token+0xe15>
 10dec41:	add    $0xffffffd5,%eax
 10dec44:	cmp    $0x2,%al
 10dec46:	jb     10debd5 <my.sexpr_parser::next_token+0xe15>
 10dec48:	test   %cl,%cl
 10dec4a:	jne    10debd5 <my.sexpr_parser::next_token+0xe15>
 10dec4c:	jmp    10deca8 <my.sexpr_parser::next_token+0xee8>
 10dec4e:	cmp    $0x2a,%rax
 10dec52:	je     10dec13 <my.sexpr_parser::next_token+0xe53>
 10dec54:	cmp    $0x5f,%eax
 10dec57:	je     10dec13 <my.sexpr_parser::next_token+0xe53>
 10dec59:	cmp    $0x7e,%eax
 10dec5c:	je     10dec13 <my.sexpr_parser::next_token+0xe53>
 10dec5e:	lea    -0x30(%rax),%ecx
 10dec61:	cmp    $0xa,%cl
 10dec64:	setb   %cl
 10dec67:	jmp    10dec13 <my.sexpr_parser::next_token+0xe53>
 10dec69:	lea    0x86a40(%rip),%rdi        # 11656b0 <core_durable_error.verbs+0x14f70>
 10dec70:	mov    %rdx,%rsi
 10dec73:	xor    %edx,%edx
 10dec75:	call   1085e00 <myl_core_trap>
 10dec7a:	cmp    $0x2a,%rsi
 10dec7e:	je     10deaf7 <my.sexpr_parser::next_token+0xd37>
 10dec84:	cmp    $0x5f,%esi
 10dec87:	je     10deaf7 <my.sexpr_parser::next_token+0xd37>
 10dec8d:	cmp    $0x7e,%esi
 10dec90:	je     10deaf7 <my.sexpr_parser::next_token+0xd37>
 10dec96:	lea    -0x30(%rsi),%ecx
 10dec99:	cmp    $0xa,%cl
 10dec9c:	setb   %dil
 10deca0:	jmp    10deaf7 <my.sexpr_parser::next_token+0xd37>
 10deca5:	mov    %r13,%rsi
 10deca8:	mov    %rsi,%rdx
 10decab:	sub    %r15,%rdx
 10decae:	jo     10def9f <my.sexpr_parser::next_token+0x11df>
 10decb4:	mov    %r8,%rax
 10decb7:	add    %rdx,%rax
 10decba:	jo     10defae <my.sexpr_parser::next_token+0x11ee>
 10decc0:	mov    %rax,0x10(%rbp)
 10decc4:	mov    %rsi,0x0(%rbp)
 10decc8:	mov    $0x2,%r9d
 10decce:	mov    %rsi,%r15
 10decd1:	jmp    10df2df <my.sexpr_parser::next_token+0x151f>
 10decd6:	cmp    $0x2a,%rax
 10decda:	je     10de94b <my.sexpr_parser::next_token+0xb8b>
 10dece0:	cmp    $0x5f,%eax
 10dece3:	je     10de94b <my.sexpr_parser::next_token+0xb8b>
 10dece9:	cmp    $0x7e,%eax
 10decec:	je     10de94b <my.sexpr_parser::next_token+0xb8b>
 10decf2:	lea    -0x30(%rax),%ecx
 10decf5:	cmp    $0xa,%cl
 10decf8:	setb   %cl
 10decfb:	jmp    10de94b <my.sexpr_parser::next_token+0xb8b>
 10ded00:	lea    0x869d9(%rip),%rdi        # 11656e0 <core_durable_error.verbs+0x14fa0>
 10ded07:	mov    %r13,%rdx
 10ded0a:	call   1085e00 <myl_core_trap>
 10ded0f:	cmp    $0x2a,%rax
 10ded13:	je     10de9e5 <my.sexpr_parser::next_token+0xc25>
 10ded19:	cmp    $0x5f,%eax
 10ded1c:	je     10de9e5 <my.sexpr_parser::next_token+0xc25>
 10ded22:	cmp    $0x7e,%eax
 10ded25:	je     10de9e5 <my.sexpr_parser::next_token+0xc25>
 10ded2b:	lea    -0x30(%rax),%ecx
 10ded2e:	cmp    $0xa,%cl
 10ded31:	setb   %cl
 10ded34:	jmp    10de9e5 <my.sexpr_parser::next_token+0xc25>
 10ded39:	lea    0x86970(%rip),%rdi        # 11656b0 <core_durable_error.verbs+0x14f70>
 10ded40:	mov    %r13,%rsi
 10ded43:	xor    %edx,%edx
 10ded45:	call   1085e00 <myl_core_trap>
 10ded4a:	lea    0x8698f(%rip),%rdi        # 11656e0 <core_durable_error.verbs+0x14fa0>
 10ded51:	mov    %r13,%rdx
 10ded54:	call   1085e00 <myl_core_trap>
 10ded59:	lea    0x86980(%rip),%rdi        # 11656e0 <core_durable_error.verbs+0x14fa0>
 10ded60:	mov    %r15,%rsi
 10ded63:	call   1085e00 <myl_core_trap>
 10ded68:	lea    0x86971(%rip),%rdi        # 11656e0 <core_durable_error.verbs+0x14fa0>
 10ded6f:	mov    %r13,%rdx
 10ded72:	call   1085e00 <myl_core_trap>
 10ded77:	lea    0x86ae2(%rip),%rdi        # 1165860 <core_durable_error.verbs+0x15120>
 10ded7e:	mov    %r15,%rsi
 10ded81:	mov    %r13,%rdx
 10ded84:	call   1085e00 <myl_core_trap>
 10ded89:	lea    0x868f0(%rip),%rdi        # 1165680 <core_durable_error.verbs+0x14f40>
 10ded90:	mov    %r13,%rsi
 10ded93:	mov    %r13,%rdx
 10ded96:	call   1085e00 <myl_core_trap>
 10ded9b:	dec    %rax
 10ded9e:	lea    0x868ab(%rip),%rdi        # 1165650 <core_durable_error.verbs+0x14f10>
 10deda5:	mov    $0x1,%edx
 10dedaa:	mov    %rax,%rsi
 10dedad:	call   1085e00 <myl_core_trap>
 10dedb2:	lea    0x868f7(%rip),%rdi        # 11656b0 <core_durable_error.verbs+0x14f70>
 10dedb9:	mov    %r13,%rsi
 10dedbc:	xor    %edx,%edx
 10dedbe:	call   1085e00 <myl_core_trap>
 10dedc3:	lea    0x86af6(%rip),%rdi        # 11658c0 <core_durable_error.verbs+0x15180>
 10dedca:	mov    $0x1,%edx
 10dedcf:	mov    %rcx,%rsi
 10dedd2:	call   1085e00 <myl_core_trap>
 10dedd7:	lea    0x86b12(%rip),%rdi        # 11658f0 <core_durable_error.verbs+0x151b0>
 10dedde:	xor    %edx,%edx
 10dede0:	call   1085e00 <myl_core_trap>
 10dede5:	lea    0x86bc4(%rip),%rdi        # 11659b0 <core_durable_error.verbs+0x15270>
 10dedec:	mov    $0x1,%edx
 10dedf1:	mov    %r8,%rsi
 10dedf4:	call   1085e00 <myl_core_trap>
 10dedf9:	lea    0x86b80(%rip),%rdi        # 1165980 <core_durable_error.verbs+0x15240>
 10dee00:	mov    $0x1,%edx
 10dee05:	mov    %rax,%rsi
 10dee08:	call   1085e00 <myl_core_trap>
 10dee0d:	lea    0x8f4dc(%rip),%rdi        # 116e2f0 <core_durable_error.verbs+0x1dbb0>
 10dee14:	mov    %r13,%rsi
 10dee17:	xor    %edx,%edx
 10dee19:	call   1085e00 <myl_core_trap>
 10dee1e:	lea    0x8673b(%rip),%rdi        # 1165560 <core_durable_error.verbs+0x14e20>
 10dee25:	mov    %r13,%rdx
 10dee28:	call   1085e00 <myl_core_trap>
 10dee2d:	lea    0x868ac(%rip),%rdi        # 11656e0 <core_durable_error.verbs+0x14fa0>
 10dee34:	mov    %r10,%rsi
 10dee37:	mov    %r13,%rdx
 10dee3a:	call   1085e00 <myl_core_trap>
 10dee3f:	lea    0x8677a(%rip),%rdi        # 11655c0 <core_durable_error.verbs+0x14e80>
 10dee46:	mov    %rax,%rsi
 10dee49:	xor    %edx,%edx
 10dee4b:	call   1085e00 <myl_core_trap>
 10dee50:	lea    0x86739(%rip),%rdi        # 1165590 <core_durable_error.verbs+0x14e50>
 10dee57:	mov    $0x1,%edx
 10dee5c:	mov    %rcx,%rsi
 10dee5f:	call   1085e00 <myl_core_trap>
 10dee64:	lea    0x86875(%rip),%rdi        # 11656e0 <core_durable_error.verbs+0x14fa0>
 10dee6b:	mov    %r15,%rsi
 10dee6e:	mov    %r13,%rdx
 10dee71:	call   1085e00 <myl_core_trap>
 10dee76:	lea    0x86833(%rip),%rdi        # 11656b0 <core_durable_error.verbs+0x14f70>
 10dee7d:	mov    %r13,%rsi
 10dee80:	xor    %edx,%edx
 10dee82:	call   1085e00 <myl_core_trap>
 10dee87:	lea    0x86bb2(%rip),%rdi        # 1165a40 <core_durable_error.verbs+0x15300>
 10dee8e:	mov    %r15,%rsi
 10dee91:	mov    %r13,%rdx
 10dee94:	call   1085e00 <myl_core_trap>
 10dee99:	lea    0x86d20(%rip),%rdi        # 1165bc0 <core_durable_error.verbs+0x15480>
 10deea0:	mov    %r13,%rdx
 10deea3:	call   1085e00 <myl_core_trap>
 10deea8:	lea    0x86771(%rip),%rdi        # 1165620 <core_durable_error.verbs+0x14ee0>
 10deeaf:	mov    %rax,%rsi
 10deeb2:	xor    %edx,%edx
 10deeb4:	call   1085e00 <myl_core_trap>
 10deeb9:	lea    0x86730(%rip),%rdi        # 11655f0 <core_durable_error.verbs+0x14eb0>
 10deec0:	mov    $0x1,%edx
 10deec5:	mov    %r8,%rsi
 10deec8:	call   1085e00 <myl_core_trap>
 10deecd:	lea    0x86a4c(%rip),%rdi        # 1165920 <core_durable_error.verbs+0x151e0>
 10deed4:	mov    $0x1,%edx
 10deed9:	mov    %rcx,%rsi
 10deedc:	call   1085e00 <myl_core_trap>
 10deee1:	lea    0x86a68(%rip),%rdi        # 1165950 <core_durable_error.verbs+0x15210>
 10deee8:	xor    %edx,%edx
 10deeea:	call   1085e00 <myl_core_trap>
 10deeef:	lea    0x867ba(%rip),%rdi        # 11656b0 <core_durable_error.verbs+0x14f70>
 10deef6:	mov    %rdx,%rsi
 10deef9:	xor    %edx,%edx
 10deefb:	call   1085e00 <myl_core_trap>
 10def00:	lea    0x86b69(%rip),%rdi        # 1165a70 <core_durable_error.verbs+0x15330>
 10def07:	mov    0x10(%rsp),%rsi
 10def0c:	call   1085e00 <myl_core_trap>
 10def11:	lea    0x86af8(%rip),%rdi        # 1165a10 <core_durable_error.verbs+0x152d0>
 10def18:	mov    %r13,%rdx
 10def1b:	call   1085e00 <myl_core_trap>
 10def20:	lea    0x867b9(%rip),%rdi        # 11656e0 <core_durable_error.verbs+0x14fa0>
 10def27:	mov    %r15,%rsi
 10def2a:	call   1085e00 <myl_core_trap>
 10def2f:	lea    0x86b9a(%rip),%rdi        # 1165ad0 <core_durable_error.verbs+0x15390>
 10def36:	mov    %r15,%rsi
 10def39:	mov    %r13,%rdx
 10def3c:	call   1085e00 <myl_core_trap>
 10def41:	lea    0x86798(%rip),%rdi        # 11656e0 <core_durable_error.verbs+0x14fa0>
 10def48:	mov    %r15,%rsi
 10def4b:	mov    %r13,%rdx
 10def4e:	call   1085e00 <myl_core_trap>
 10def53:	lea    0x86c06(%rip),%rdi        # 1165b60 <core_durable_error.verbs+0x15420>
 10def5a:	call   1085e00 <myl_core_trap>
 10def5f:	lea    0x86c2a(%rip),%rdi        # 1165b90 <core_durable_error.verbs+0x15450>
 10def66:	mov    0x10(%rsp),%rsi
 10def6b:	call   1085e00 <myl_core_trap>
 10def70:	lea    0x86739(%rip),%rdi        # 11656b0 <core_durable_error.verbs+0x14f70>
 10def77:	mov    %rdx,%rsi
 10def7a:	xor    %edx,%edx
 10def7c:	call   1085e00 <myl_core_trap>
 10def81:	lea    0x86b18(%rip),%rdi        # 1165aa0 <core_durable_error.verbs+0x15360>
 10def88:	mov    %r13,%rdx
 10def8b:	call   1085e00 <myl_core_trap>
 10def90:	lea    0x86749(%rip),%rdi        # 11656e0 <core_durable_error.verbs+0x14fa0>
 10def97:	mov    %r15,%rsi
 10def9a:	call   1085e00 <myl_core_trap>
 10def9f:	lea    0x86b5a(%rip),%rdi        # 1165b00 <core_durable_error.verbs+0x153c0>
 10defa6:	mov    %r15,%rdx
 10defa9:	call   1085e00 <myl_core_trap>
 10defae:	lea    0x86b7b(%rip),%rdi        # 1165b30 <core_durable_error.verbs+0x153f0>
 10defb5:	mov    %r8,%rsi
 10defb8:	call   1085e00 <myl_core_trap>
 10defbd:	mov    %r12,%rdi
 10defc0:	mov    %rbp,%rsi
 10defc3:	call   1122f70 <my.sexpr_tokenizer::advance>
 10defc8:	mov    0x8(%r12),%r13
 10defcd:	cmp    %rbx,%r13
 10defd0:	ja     10df5a2 <my.sexpr_parser::next_token+0x17e2>
 10defd6:	mov    0x0(%rbp),%r15
 10defda:	mov    $0x4,%edi
 10defdf:	cmp    %r13,%r15
 10defe2:	jge    10df08d <my.sexpr_parser::next_token+0x12cd>
 10defe8:	mov    %r15,%rax
 10defeb:	sar    $0x3f,%rax
 10defef:	and    %r13,%rax
 10deff2:	add    %r15,%rax
 10deff5:	cmp    %r13,%rax
 10deff8:	jae    10df618 <my.sexpr_parser::next_token+0x1858>
 10deffe:	lea    0x20(%r12),%rcx
 10df003:	movzbl (%rcx,%rax,1),%eax
 10df007:	lea    -0x30(%rax),%ecx
 10df00a:	cmp    $0x9,%cl
 10df00d:	jbe    10defbd <my.sexpr_parser::next_token+0x11fd>
 10df00f:	cmp    $0x2e,%al
 10df011:	jne    10df08d <my.sexpr_parser::next_token+0x12cd>
 10df013:	lea    0x1(%r15),%rsi
 10df017:	cmp    %r13,%rsi
 10df01a:	jge    10df08d <my.sexpr_parser::next_token+0x12cd>
 10df01c:	xor    %eax,%eax
 10df01e:	cmp    $0xffffffffffffffff,%r15
 10df022:	cmovl  %r13,%rax
 10df026:	add    %rsi,%rax
 10df029:	cmp    %r13,%rax
 10df02c:	jae    10df69d <my.sexpr_parser::next_token+0x18dd>
 10df032:	lea    0x20(%r12),%rcx
 10df037:	movzbl (%rcx,%rax,1),%eax
 10df03b:	add    $0xd0,%al
 10df03d:	cmp    $0xa,%al
 10df03f:	jae    10df08d <my.sexpr_parser::next_token+0x12cd>
 10df041:	mov    %r12,%rdi
 10df044:	mov    %rbp,%rsi
 10df047:	call   1122f70 <my.sexpr_tokenizer::advance>
 10df04c:	mov    0x8(%r12),%r13
 10df051:	cmp    %rbx,%r13
 10df054:	ja     10df607 <my.sexpr_parser::next_token+0x1847>
 10df05a:	mov    0x0(%rbp),%r15
 10df05e:	mov    $0x5,%edi
 10df063:	cmp    %r13,%r15
 10df066:	jge    10df08d <my.sexpr_parser::next_token+0x12cd>
 10df068:	mov    %r15,%rax
 10df06b:	sar    $0x3f,%rax
 10df06f:	and    %r13,%rax
 10df072:	add    %r15,%rax
 10df075:	cmp    %r13,%rax
 10df078:	jae    10df62a <my.sexpr_parser::next_token+0x186a>
 10df07e:	lea    0x20(%r12),%rcx
 10df083:	movzbl (%rcx,%rax,1),%eax
 10df087:	add    $0xd0,%al
 10df089:	cmp    $0x9,%al
 10df08b:	jbe    10df041 <my.sexpr_parser::next_token+0x1281>
 10df08d:	cmp    %r13,%r15
 10df090:	jge    10df267 <my.sexpr_parser::next_token+0x14a7>
 10df096:	mov    %r15,%rax
 10df099:	sar    $0x3f,%rax
 10df09d:	and    %r13,%rax
 10df0a0:	add    %r15,%rax
 10df0a3:	cmp    %r13,%rax
 10df0a6:	jae    10df65c <my.sexpr_parser::next_token+0x189c>
 10df0ac:	lea    0x20(%r12),%rcx
 10df0b1:	cmpb   $0x6d,(%rcx,%rax,1)
 10df0b5:	jne    10df267 <my.sexpr_parser::next_token+0x14a7>
 10df0bb:	lea    0x1(%r15),%rsi
 10df0bf:	cmp    %r13,%rsi
 10df0c2:	jge    10df267 <my.sexpr_parser::next_token+0x14a7>
 10df0c8:	xor    %eax,%eax
 10df0ca:	cmp    $0xffffffffffffffff,%r15
 10df0ce:	cmovl  %r13,%rax
 10df0d2:	add    %rsi,%rax
 10df0d5:	cmp    %r13,%rax
 10df0d8:	jae    10df68e <my.sexpr_parser::next_token+0x18ce>
 10df0de:	lea    0x20(%r12),%rcx
 10df0e3:	movzbl (%rcx,%rax,1),%eax
 10df0e7:	cmp    $0x69,%eax
 10df0ea:	je     10df191 <my.sexpr_parser::next_token+0x13d1>
 10df0f0:	cmp    $0x6d,%eax
 10df0f3:	jne    10df267 <my.sexpr_parser::next_token+0x14a7>
 10df0f9:	lea    0x2(%r15),%rsi
 10df0fd:	cmp    %r13,%rsi
 10df100:	jge    10df249 <my.sexpr_parser::next_token+0x1489>
 10df106:	xor    %eax,%eax
 10df108:	cmp    $0xfffffffffffffffe,%r15
 10df10c:	cmovl  %r13,%rax
 10df110:	add    %rsi,%rax
 10df113:	cmp    %r13,%rax
 10df116:	jae    10df6b8 <my.sexpr_parser::next_token+0x18f8>
 10df11c:	lea    0x20(%r12),%rcx
 10df121:	movzbl (%rcx,%rax,1),%eax
 10df125:	mov    %eax,%edx
 10df127:	and    $0xdf,%edx
 10df12d:	add    $0xffffffbf,%edx
 10df130:	mov    $0x1,%cl
 10df132:	cmp    $0x1a,%edx
 10df135:	jae    10df5b3 <my.sexpr_parser::next_token+0x17f3>
 10df13b:	vmovd  %eax,%xmm0
 10df13f:	vpbroadcastb %xmm0,%xmm0
 10df144:	vpcmpeqb -0xdaedc(%rip),%xmm0,%xmm0        # 1004270 <__anon_1393+0x50>
 10df14c:	vpmovsxbd %xmm0,%xmm0
 10df151:	vmovmskps %xmm0,%edx
 10df155:	test   %edx,%edx
 10df157:	jne    10df267 <my.sexpr_parser::next_token+0x14a7>
 10df15d:	mov    %eax,%edx
 10df15f:	and    $0xfffffffd,%edx
 10df162:	cmp    $0x2d,%edx
 10df165:	je     10df267 <my.sexpr_parser::next_token+0x14a7>
 10df16b:	mov    %eax,%edx
 10df16d:	and    $0xfffffffb,%edx
 10df170:	cmp    $0x2a,%edx
 10df173:	je     10df267 <my.sexpr_parser::next_token+0x14a7>
 10df179:	add    $0xffffffd5,%eax
 10df17c:	cmp    $0x2,%al
 10df17e:	jb     10df267 <my.sexpr_parser::next_token+0x14a7>
 10df184:	test   %cl,%cl
 10df186:	je     10df249 <my.sexpr_parser::next_token+0x1489>
 10df18c:	jmp    10df267 <my.sexpr_parser::next_token+0x14a7>
 10df191:	lea    0x2(%r15),%rsi
 10df195:	cmp    %r13,%rsi
 10df198:	jge    10df267 <my.sexpr_parser::next_token+0x14a7>
 10df19e:	xor    %eax,%eax
 10df1a0:	cmp    $0xfffffffffffffffe,%r15
 10df1a4:	cmovl  %r13,%rax
 10df1a8:	add    %rsi,%rax
 10df1ab:	cmp    %r13,%rax
 10df1ae:	jae    10df6c7 <my.sexpr_parser::next_token+0x1907>
 10df1b4:	lea    0x20(%r12),%rcx
 10df1b9:	cmpb   $0x6c,(%rcx,%rax,1)
 10df1bd:	jne    10df267 <my.sexpr_parser::next_token+0x14a7>
 10df1c3:	lea    0x3(%r15),%rsi
 10df1c7:	cmp    %r13,%rsi
 10df1ca:	jge    10df23e <my.sexpr_parser::next_token+0x147e>
 10df1cc:	xor    %eax,%eax
 10df1ce:	cmp    $0xfffffffffffffffd,%r15
 10df1d2:	cmovl  %r13,%rax
 10df1d6:	add    %rsi,%rax
 10df1d9:	cmp    %r13,%rax
 10df1dc:	jae    10df6d6 <my.sexpr_parser::next_token+0x1916>
 10df1e2:	lea    0x20(%r12),%rcx
 10df1e7:	movzbl (%rcx,%rax,1),%eax
 10df1eb:	mov    %eax,%edx
 10df1ed:	and    $0xdf,%edx
 10df1f3:	add    $0xffffffbf,%edx
 10df1f6:	mov    $0x1,%cl
 10df1f8:	cmp    $0x1a,%edx
 10df1fb:	jae    10df5dd <my.sexpr_parser::next_token+0x181d>
 10df201:	vmovd  %eax,%xmm0
 10df205:	vpbroadcastb %xmm0,%xmm0
 10df20a:	vpcmpeqb -0xdafa2(%rip),%xmm0,%xmm0        # 1004270 <__anon_1393+0x50>
 10df212:	vpmovsxbd %xmm0,%xmm0
 10df217:	vmovmskps %xmm0,%edx
 10df21b:	test   %edx,%edx
 10df21d:	jne    10df267 <my.sexpr_parser::next_token+0x14a7>
 10df21f:	mov    %eax,%edx
 10df221:	and    $0xfffffffd,%edx
 10df224:	cmp    $0x2d,%edx
 10df227:	je     10df267 <my.sexpr_parser::next_token+0x14a7>
 10df229:	mov    %eax,%edx
 10df22b:	and    $0xfffffffb,%edx
 10df22e:	cmp    $0x2a,%edx
 10df231:	je     10df267 <my.sexpr_parser::next_token+0x14a7>
 10df233:	add    $0xffffffd5,%eax
 10df236:	cmp    $0x2,%al
 10df238:	jb     10df267 <my.sexpr_parser::next_token+0x14a7>
 10df23a:	test   %cl,%cl
 10df23c:	jne    10df267 <my.sexpr_parser::next_token+0x14a7>
 10df23e:	mov    %r12,%rdi
 10df241:	mov    %rbp,%rsi
 10df244:	call   1122f70 <my.sexpr_tokenizer::advance>
 10df249:	mov    %r12,%rdi
 10df24c:	mov    %rbp,%rsi
 10df24f:	call   1122f70 <my.sexpr_tokenizer::advance>
 10df254:	mov    %r12,%rdi
 10df257:	mov    %rbp,%rsi
 10df25a:	call   1122f70 <my.sexpr_tokenizer::advance>
 10df25f:	mov    $0x6,%r9d
 10df265:	jmp    10df2da <my.sexpr_parser::next_token+0x151a>
 10df267:	mov    %rdi,%r14
 10df26a:	mov    %r12,%rdi
 10df26d:	mov    %rbp,%rsi
 10df270:	call   1135f80 <my.sexpr_tokenizer::si_suffix_len>
 10df275:	test   %rax,%rax
 10df278:	je     10df349 <my.sexpr_parser::next_token+0x1589>
 10df27e:	mov    %rax,%r13
 10df281:	data16 data16 data16 data16 data16 cs nopw 0x0(%rax,%rax,1)
 10df290:	data16 data16 data16 data16 data16 cs nopw 0x0(%rax,%rax,1)
 10df29f:	data16 data16 data16 data16 data16 cs nopw 0x0(%rax,%rax,1)
 10df2ae:	data16 data16 data16 data16 data16 cs nopw 0x0(%rax,%rax,1)
 10df2bd:	nopl   (%rax)
 10df2c0:	mov    %r12,%rdi
 10df2c3:	mov    %rbp,%rsi
 10df2c6:	call   1122f70 <my.sexpr_tokenizer::advance>
 10df2cb:	dec    %r13
 10df2ce:	jne    10df2c0 <my.sexpr_parser::next_token+0x1500>
 10df2d0:	mov    0x0(%rbp),%r15
 10df2d4:	mov    $0x7,%r9d
 10df2da:	mov    0x8(%rsp),%r10
 10df2df:	mov    %r10,%r14
 10df2e2:	mov    0x28(%rsp),%rax
 10df2e7:	mov    %r9,0x8(%rax)
 10df2eb:	mov    %r14,0x10(%rax)
 10df2ef:	mov    %r15,0x18(%rax)
 10df2f3:	mov    0x18(%rsp),%rcx
 10df2f8:	mov    %rcx,0x20(%rax)
 10df2fc:	mov    0x10(%rsp),%rcx
 10df301:	mov    %rcx,0x28(%rax)
 10df305:	mov    %r10,0x30(%rax)
 10df309:	movq   $0x0,(%rax)
 10df310:	mov    0x50(%rsp),%rcx
 10df315:	mov    %rcx,0x68(%rax)
 10df319:	mov    0x40(%rsp),%rcx
 10df31e:	mov    %rcx,0x70(%rax)
 10df322:	mov    0x48(%rsp),%rcx
 10df327:	mov    %rcx,0x78(%rax)
 10df32b:	mov    0x90(%rsp),%rbx
 10df333:	mov    %rbx,0x80(%rax)
 10df33a:	add    $0x58,%rsp
 10df33e:	pop    %rbx
 10df33f:	pop    %r12
 10df341:	pop    %r13
 10df343:	pop    %r14
 10df345:	pop    %r15
 10df347:	pop    %rbp
 10df348:	ret
 10df349:	mov    0x8(%r12),%rdx
 10df34e:	cmp    %rbx,%rdx
 10df351:	ja     10df66e <my.sexpr_parser::next_token+0x18ae>
 10df357:	mov    %r14,%r9
 10df35a:	cmp    %rdx,%r15
 10df35d:	mov    0x8(%rsp),%r10
 10df362:	lea    0x20(%r12),%r13
 10df367:	jge    10df2df <my.sexpr_parser::next_token+0x151f>
 10df36d:	mov    %r15,%rax
 10df370:	sar    $0x3f,%rax
 10df374:	and    %rdx,%rax
 10df377:	add    %r15,%rax
 10df37a:	cmp    %rdx,%rax
 10df37d:	jae    10df67f <my.sexpr_parser::next_token+0x18bf>
 10df383:	movzbl 0x0(%r13,%rax,1),%eax
 10df389:	cmp    $0x25,%al
 10df38b:	jne    10df438 <my.sexpr_parser::next_token+0x1678>
 10df391:	lea    0x1(%r15),%rsi
 10df395:	cmp    %rdx,%rsi
 10df398:	jge    10df419 <my.sexpr_parser::next_token+0x1659>
 10df39a:	xor    %ecx,%ecx
 10df39c:	cmp    $0xffffffffffffffff,%r15
 10df3a0:	cmovl  %rdx,%rcx
 10df3a4:	add    %rsi,%rcx
 10df3a7:	cmp    %rdx,%rcx
 10df3aa:	jae    10df6ac <my.sexpr_parser::next_token+0x18ec>
 10df3b0:	movzbl 0x0(%r13,%rcx,1),%esi
 10df3b6:	mov    %esi,%ecx
 10df3b8:	and    $0xdf,%ecx
 10df3be:	add    $0xffffffbf,%ecx
 10df3c1:	mov    $0x1,%dil
 10df3c4:	cmp    $0x1a,%ecx
 10df3c7:	jae    10df577 <my.sexpr_parser::next_token+0x17b7>
 10df3cd:	vmovd  %esi,%xmm0
 10df3d1:	vpbroadcastb %xmm0,%xmm0
 10df3d6:	vpcmpeqb -0xdb16e(%rip),%xmm0,%xmm0        # 1004270 <__anon_1393+0x50>
 10df3de:	vpmovsxbd %xmm0,%xmm0
 10df3e3:	vmovmskps %xmm0,%r8d
 10df3e7:	mov    $0x25,%ecx
 10df3ec:	test   %r8d,%r8d
 10df3ef:	jne    10df45c <my.sexpr_parser::next_token+0x169c>
 10df3f1:	mov    %esi,%r8d
 10df3f4:	and    $0xfffffffd,%r8d
 10df3f8:	cmp    $0x2d,%r8d
 10df3fc:	je     10df45c <my.sexpr_parser::next_token+0x169c>
 10df3fe:	mov    %esi,%r8d
 10df401:	and    $0xfffffffb,%r8d
 10df405:	cmp    $0x2a,%r8d
 10df409:	je     10df45c <my.sexpr_parser::next_token+0x169c>
 10df40b:	add    $0xffffffd5,%esi
 10df40e:	cmp    $0x2,%sil
 10df412:	jb     10df45c <my.sexpr_parser::next_token+0x169c>
 10df414:	test   %dil,%dil
 10df417:	jne    10df45c <my.sexpr_parser::next_token+0x169c>
 10df419:	mov    %r12,%rdi
 10df41c:	mov    %rbp,%rsi
 10df41f:	call   1122f70 <my.sexpr_tokenizer::advance>
 10df424:	mov    0x8(%rsp),%r10
 10df429:	mov    0x0(%rbp),%r15
 10df42d:	mov    $0x7,%r9d
 10df433:	jmp    10df2df <my.sexpr_parser::next_token+0x151f>
 10df438:	movzbl %al,%ecx
 10df43b:	mov    %ecx,%edi
 10df43d:	and    $0xdf,%edi
 10df443:	add    $0xffffffbf,%edi
 10df446:	mov    $0x1,%sil
 10df449:	cmp    $0x1a,%edi
 10df44c:	jb     10df467 <my.sexpr_parser::next_token+0x16a7>
 10df44e:	cmp    $0x2a,%al
 10df450:	je     10df467 <my.sexpr_parser::next_token+0x16a7>
 10df452:	cmp    $0x5f,%ecx
 10df455:	je     10df467 <my.sexpr_parser::next_token+0x16a7>
 10df457:	cmp    $0x7e,%ecx
 10df45a:	je     10df467 <my.sexpr_parser::next_token+0x16a7>
 10df45c:	lea    -0x30(%rax),%esi
 10df45f:	cmp    $0xa,%sil
 10df463:	setb   %sil
 10df467:	vmovd  %eax,%xmm0
 10df46b:	vpbroadcastb %xmm0,%xmm0
 10df470:	vpcmpeqb -0xdb208(%rip),%xmm0,%xmm0        # 1004270 <__anon_1393+0x50>
 10df478:	vpmovsxbd %xmm0,%xmm0
 10df47d:	vmovmskps %xmm0,%edi
 10df481:	test   %edi,%edi
 10df483:	jne    10df4c9 <my.sexpr_parser::next_token+0x1709>
 10df485:	mov    %ecx,%edi
 10df487:	and    $0xfffffffd,%edi
 10df48a:	cmp    $0x2d,%edi
 10df48d:	je     10df4c9 <my.sexpr_parser::next_token+0x1709>
 10df48f:	and    $0xfffffffb,%ecx
 10df492:	cmp    $0x2a,%ecx
 10df495:	je     10df4c9 <my.sexpr_parser::next_token+0x1709>
 10df497:	add    $0xd5,%al
 10df499:	cmp    $0x2,%al
 10df49b:	jb     10df4c9 <my.sexpr_parser::next_token+0x1709>
 10df49d:	mov    %r10,%r14
 10df4a0:	test   %sil,%sil
 10df4a3:	je     10df2e2 <my.sexpr_parser::next_token+0x1522>
 10df4a9:	jmp    10df4c9 <my.sexpr_parser::next_token+0x1709>
 10df4ab:	mov    %r12,%rdi
 10df4ae:	mov    %rbp,%rsi
 10df4b1:	call   1122f70 <my.sexpr_tokenizer::advance>
 10df4b6:	mov    0x8(%rsp),%r10
 10df4bb:	mov    0x8(%r12),%rdx
 10df4c0:	cmp    %rbx,%rdx
 10df4c3:	ja     10df64b <my.sexpr_parser::next_token+0x188b>
 10df4c9:	mov    0x0(%rbp),%r15
 10df4cd:	mov    $0x2,%r9d
 10df4d3:	cmp    %rdx,%r15
 10df4d6:	jge    10df2df <my.sexpr_parser::next_token+0x151f>
 10df4dc:	mov    %r15,%rax
 10df4df:	sar    $0x3f,%rax
 10df4e3:	and    %rdx,%rax
 10df4e6:	add    %r15,%rax
 10df4e9:	cmp    %rdx,%rax
 10df4ec:	jae    10df63c <my.sexpr_parser::next_token+0x187c>
 10df4f2:	movzbl 0x0(%r13,%rax,1),%eax
 10df4f8:	mov    %eax,%edx
 10df4fa:	and    $0xdf,%edx
 10df500:	add    $0xffffffbf,%edx
 10df503:	mov    $0x1,%cl
 10df505:	cmp    $0x1a,%edx
 10df508:	jae    10df55c <my.sexpr_parser::next_token+0x179c>
 10df50a:	vmovd  %eax,%xmm0
 10df50e:	vpbroadcastb %xmm0,%xmm0
 10df513:	vpcmpeqb -0xdb2ab(%rip),%xmm0,%xmm0        # 1004270 <__anon_1393+0x50>
 10df51b:	vpmovsxbd %xmm0,%xmm0
 10df520:	vmovmskps %xmm0,%edx
 10df524:	test   %edx,%edx
 10df526:	jne    10df4ab <my.sexpr_parser::next_token+0x16eb>
 10df528:	mov    %eax,%edx
 10df52a:	and    $0xfffffffd,%edx
 10df52d:	cmp    $0x2d,%edx
 10df530:	je     10df4ab <my.sexpr_parser::next_token+0x16eb>
 10df536:	mov    %eax,%edx
 10df538:	and    $0xfffffffb,%edx
 10df53b:	cmp    $0x2a,%edx
 10df53e:	je     10df4ab <my.sexpr_parser::next_token+0x16eb>
 10df544:	add    $0xffffffd5,%eax
 10df547:	cmp    $0x2,%al
 10df549:	jb     10df4ab <my.sexpr_parser::next_token+0x16eb>
 10df54f:	test   %cl,%cl
 10df551:	jne    10df4ab <my.sexpr_parser::next_token+0x16eb>
 10df557:	jmp    10df2df <my.sexpr_parser::next_token+0x151f>
 10df55c:	cmp    $0x2a,%rax
 10df560:	je     10df50a <my.sexpr_parser::next_token+0x174a>
 10df562:	cmp    $0x5f,%eax
 10df565:	je     10df50a <my.sexpr_parser::next_token+0x174a>
 10df567:	cmp    $0x7e,%eax
 10df56a:	je     10df50a <my.sexpr_parser::next_token+0x174a>
 10df56c:	lea    -0x30(%rax),%ecx
 10df56f:	cmp    $0xa,%cl
 10df572:	setb   %cl
 10df575:	jmp    10df50a <my.sexpr_parser::next_token+0x174a>
 10df577:	cmp    $0x2a,%rsi
 10df57b:	je     10df3cd <my.sexpr_parser::next_token+0x160d>
 10df581:	cmp    $0x5f,%esi
 10df584:	je     10df3cd <my.sexpr_parser::next_token+0x160d>
 10df58a:	cmp    $0x7e,%esi
 10df58d:	je     10df3cd <my.sexpr_parser::next_token+0x160d>
 10df593:	lea    -0x30(%rsi),%ecx
 10df596:	cmp    $0xa,%cl
 10df599:	setb   %dil
 10df59d:	jmp    10df3cd <my.sexpr_parser::next_token+0x160d>
 10df5a2:	lea    0x86107(%rip),%rdi        # 11656b0 <core_durable_error.verbs+0x14f70>
 10df5a9:	mov    %r13,%rsi
 10df5ac:	xor    %edx,%edx
 10df5ae:	call   1085e00 <myl_core_trap>
 10df5b3:	cmp    $0x2a,%rax
 10df5b7:	je     10df13b <my.sexpr_parser::next_token+0x137b>
 10df5bd:	cmp    $0x5f,%eax
 10df5c0:	je     10df13b <my.sexpr_parser::next_token+0x137b>
 10df5c6:	cmp    $0x7e,%eax
 10df5c9:	je     10df13b <my.sexpr_parser::next_token+0x137b>
 10df5cf:	lea    -0x30(%rax),%ecx
 10df5d2:	cmp    $0xa,%cl
 10df5d5:	setb   %cl
 10df5d8:	jmp    10df13b <my.sexpr_parser::next_token+0x137b>
 10df5dd:	cmp    $0x2a,%rax
 10df5e1:	je     10df201 <my.sexpr_parser::next_token+0x1441>
 10df5e7:	cmp    $0x5f,%eax
 10df5ea:	je     10df201 <my.sexpr_parser::next_token+0x1441>
 10df5f0:	cmp    $0x7e,%eax
 10df5f3:	je     10df201 <my.sexpr_parser::next_token+0x1441>
 10df5f9:	lea    -0x30(%rax),%ecx
 10df5fc:	cmp    $0xa,%cl
 10df5ff:	setb   %cl
 10df602:	jmp    10df201 <my.sexpr_parser::next_token+0x1441>
 10df607:	lea    0x860a2(%rip),%rdi        # 11656b0 <core_durable_error.verbs+0x14f70>
 10df60e:	mov    %r13,%rsi
 10df611:	xor    %edx,%edx
 10df613:	call   1085e00 <myl_core_trap>
 10df618:	lea    0x860c1(%rip),%rdi        # 11656e0 <core_durable_error.verbs+0x14fa0>
 10df61f:	mov    %r15,%rsi
 10df622:	mov    %r13,%rdx
 10df625:	call   1085e00 <myl_core_trap>
 10df62a:	lea    0x860af(%rip),%rdi        # 11656e0 <core_durable_error.verbs+0x14fa0>
 10df631:	mov    %r15,%rsi
 10df634:	mov    %r13,%rdx
 10df637:	call   1085e00 <myl_core_trap>
 10df63c:	lea    0x8609d(%rip),%rdi        # 11656e0 <core_durable_error.verbs+0x14fa0>
 10df643:	mov    %r15,%rsi
 10df646:	call   1085e00 <myl_core_trap>
 10df64b:	lea    0x8605e(%rip),%rdi        # 11656b0 <core_durable_error.verbs+0x14f70>
 10df652:	mov    %rdx,%rsi
 10df655:	xor    %edx,%edx
 10df657:	call   1085e00 <myl_core_trap>
 10df65c:	lea    0x8607d(%rip),%rdi        # 11656e0 <core_durable_error.verbs+0x14fa0>
 10df663:	mov    %r15,%rsi
 10df666:	mov    %r13,%rdx
 10df669:	call   1085e00 <myl_core_trap>
 10df66e:	lea    0x8603b(%rip),%rdi        # 11656b0 <core_durable_error.verbs+0x14f70>
 10df675:	mov    %rdx,%rsi
 10df678:	xor    %edx,%edx
 10df67a:	call   1085e00 <myl_core_trap>
 10df67f:	lea    0x8605a(%rip),%rdi        # 11656e0 <core_durable_error.verbs+0x14fa0>
 10df686:	mov    %r15,%rsi
 10df689:	call   1085e00 <myl_core_trap>
 10df68e:	lea    0x8637b(%rip),%rdi        # 1165a10 <core_durable_error.verbs+0x152d0>
 10df695:	mov    %r13,%rdx
 10df698:	call   1085e00 <myl_core_trap>
 10df69d:	lea    0x8636c(%rip),%rdi        # 1165a10 <core_durable_error.verbs+0x152d0>
 10df6a4:	mov    %r13,%rdx
 10df6a7:	call   1085e00 <myl_core_trap>
 10df6ac:	lea    0x8635d(%rip),%rdi        # 1165a10 <core_durable_error.verbs+0x152d0>
 10df6b3:	call   1085e00 <myl_core_trap>
 10df6b8:	lea    0x86351(%rip),%rdi        # 1165a10 <core_durable_error.verbs+0x152d0>
 10df6bf:	mov    %r13,%rdx
 10df6c2:	call   1085e00 <myl_core_trap>
 10df6c7:	lea    0x86342(%rip),%rdi        # 1165a10 <core_durable_error.verbs+0x152d0>
 10df6ce:	mov    %r13,%rdx
 10df6d1:	call   1085e00 <myl_core_trap>
 10df6d6:	lea    0x86333(%rip),%rdi        # 1165a10 <core_durable_error.verbs+0x152d0>
 10df6dd:	mov    %r13,%rdx
 10df6e0:	call   1085e00 <myl_core_trap>

Disassembly of section .plt:
