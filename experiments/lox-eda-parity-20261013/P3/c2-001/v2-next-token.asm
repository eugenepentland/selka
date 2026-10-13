
/home/epentland/ai/canopy/mylang/.tmp/lox-eda-parity/P3/c2-001/candidate-v2-application:     file format elf64-x86-64


Disassembly of section .text:

00000000010dddc0 <my.sexpr_parser::next_token>:
 10dddc0:	55                   	push   %rbp
 10dddc1:	41 57                	push   %r15
 10dddc3:	41 56                	push   %r14
 10dddc5:	41 55                	push   %r13
 10dddc7:	41 54                	push   %r12
 10dddc9:	53                   	push   %rbx
 10dddca:	48 83 ec 58          	sub    $0x58,%rsp
 10dddce:	4d 89 ce             	mov    %r9,%r14
 10dddd1:	4d 89 c7             	mov    %r8,%r15
 10dddd4:	48 89 d5             	mov    %rdx,%rbp
 10dddd7:	49 89 f4             	mov    %rsi,%r12
 10dddda:	48 89 7c 24 28       	mov    %rdi,0x28(%rsp)
 10ddddf:	48 bb 00 00 00 00 00 	movabs $0x800000000000,%rbx
 10ddde6:	80 00 00 
 10ddde9:	4c 8b 6e 08          	mov    0x8(%rsi),%r13
 10ddded:	48 8b 32             	mov    (%rdx),%rsi
 10dddf0:	48 85 f6             	test   %rsi,%rsi
 10dddf3:	48 89 4c 24 50       	mov    %rcx,0x50(%rsp)
 10dddf8:	78 48                	js     10dde42 <my.sexpr_parser::next_token+0x82>
 10dddfa:	49 39 dd             	cmp    %rbx,%r13
 10dddfd:	0f 87 0a 10 00 00    	ja     10dee0d <my.sexpr_parser::next_token+0x104d>
 10dde03:	48 b8 00 00 00 00 00 	movabs $0x8000000000000000,%rax
 10dde0a:	00 00 80 
 10dde0d:	48 8b 4d 08          	mov    0x8(%rbp),%rcx
 10dde11:	4c 89 ea             	mov    %r13,%rdx
 10dde14:	48 f7 d2             	not    %rdx
 10dde17:	48 01 c2             	add    %rax,%rdx
 10dde1a:	48 89 4c 24 18       	mov    %rcx,0x18(%rsp)
 10dde1f:	48 39 d1             	cmp    %rdx,%rcx
 10dde22:	7f 2c                	jg     10dde50 <my.sexpr_parser::next_token+0x90>
 10dde24:	48 8b 4d 10          	mov    0x10(%rbp),%rcx
 10dde28:	48 39 d1             	cmp    %rdx,%rcx
 10dde2b:	7f 23                	jg     10dde50 <my.sexpr_parser::next_token+0x90>
 10dde2d:	4c 39 ee             	cmp    %r13,%rsi
 10dde30:	0f 83 81 05 00 00    	jae    10de3b7 <my.sexpr_parser::next_token+0x5f7>
 10dde36:	48 8d 15 0f 9b f2 ff 	lea    -0xd64f1(%rip),%rdx        # 100794c <core_number_pairs+0x2bc>
 10dde3d:	e9 d6 01 00 00       	jmp    10de018 <my.sexpr_parser::next_token+0x258>
 10dde42:	49 39 dd             	cmp    %rbx,%r13
 10dde45:	0f 87 ea 08 00 00    	ja     10de735 <my.sexpr_parser::next_token+0x975>
 10dde4b:	0f 1f 44 00 00       	nopl   0x0(%rax,%rax,1)
 10dde50:	48 c7 c0 ff ff ff ff 	mov    $0xffffffffffffffff,%rax
 10dde57:	4c 39 ee             	cmp    %r13,%rsi
 10dde5a:	7d 2a                	jge    10dde86 <my.sexpr_parser::next_token+0xc6>
 10dde5c:	48 89 f0             	mov    %rsi,%rax
 10dde5f:	48 c1 f8 3f          	sar    $0x3f,%rax
 10dde63:	4c 21 e8             	and    %r13,%rax
 10dde66:	48 01 f0             	add    %rsi,%rax
 10dde69:	4c 39 e8             	cmp    %r13,%rax
 10dde6c:	0f 83 f6 0e 00 00    	jae    10ded68 <my.sexpr_parser::next_token+0xfa8>
 10dde72:	66 66 66 66 66 2e 0f 	data16 data16 data16 data16 cs nopw 0x0(%rax,%rax,1)
 10dde79:	1f 84 00 00 00 00 00 
 10dde80:	41 0f b6 44 04 20    	movzbl 0x20(%r12,%rax,1),%eax
 10dde86:	48 83 f8 3b          	cmp    $0x3b,%rax
 10dde8a:	0f 87 c5 00 00 00    	ja     10ddf55 <my.sexpr_parser::next_token+0x195>
 10dde90:	48 b9 00 26 00 00 01 	movabs $0x100002600,%rcx
 10dde97:	00 00 00 
 10dde9a:	48 0f a3 c1          	bt     %rax,%rcx
 10dde9e:	73 40                	jae    10ddee0 <my.sexpr_parser::next_token+0x120>
 10ddea0:	4c 89 e7             	mov    %r12,%rdi
 10ddea3:	48 89 ee             	mov    %rbp,%rsi
 10ddea6:	e8 c5 50 04 00       	call   1122f70 <my.sexpr_tokenizer::advance>
 10ddeab:	4d 8b 6c 24 08       	mov    0x8(%r12),%r13
 10ddeb0:	49 39 dd             	cmp    %rbx,%r13
 10ddeb3:	0f 87 80 0e 00 00    	ja     10ded39 <my.sexpr_parser::next_token+0xf79>
 10ddeb9:	48 8b 75 00          	mov    0x0(%rbp),%rsi
 10ddebd:	4c 39 ee             	cmp    %r13,%rsi
 10ddec0:	0f 8d 8f 00 00 00    	jge    10ddf55 <my.sexpr_parser::next_token+0x195>
 10ddec6:	48 89 f0             	mov    %rsi,%rax
 10ddec9:	48 c1 f8 3f          	sar    $0x3f,%rax
 10ddecd:	4c 21 e8             	and    %r13,%rax
 10dded0:	48 01 f0             	add    %rsi,%rax
 10dded3:	4c 39 e8             	cmp    %r13,%rax
 10dded6:	72 a8                	jb     10dde80 <my.sexpr_parser::next_token+0xc0>
 10dded8:	e9 6d 0e 00 00       	jmp    10ded4a <my.sexpr_parser::next_token+0xf8a>
 10ddedd:	0f 1f 00             	nopl   (%rax)
 10ddee0:	48 83 f8 3b          	cmp    $0x3b,%rax
 10ddee4:	0f 85 6b 00 00 00    	jne    10ddf55 <my.sexpr_parser::next_token+0x195>
 10ddeea:	66 66 66 66 66 66 2e 	data16 data16 data16 data16 data16 cs nopw 0x0(%rax,%rax,1)
 10ddef1:	0f 1f 84 00 00 00 00 
 10ddef8:	00 
 10ddef9:	0f 1f 80 00 00 00 00 	nopl   0x0(%rax)
 10ddf00:	48 8b 75 00          	mov    0x0(%rbp),%rsi
 10ddf04:	4c 39 ee             	cmp    %r13,%rsi
 10ddf07:	0f 8d 43 ff ff ff    	jge    10dde50 <my.sexpr_parser::next_token+0x90>
 10ddf0d:	48 89 f0             	mov    %rsi,%rax
 10ddf10:	48 c1 f8 3f          	sar    $0x3f,%rax
 10ddf14:	4c 21 e8             	and    %r13,%rax
 10ddf17:	48 01 f0             	add    %rsi,%rax
 10ddf1a:	4c 39 e8             	cmp    %r13,%rax
 10ddf1d:	0f 83 dd 0d 00 00    	jae    10ded00 <my.sexpr_parser::next_token+0xf40>
 10ddf23:	41 80 7c 04 20 0a    	cmpb   $0xa,0x20(%r12,%rax,1)
 10ddf29:	0f 84 21 ff ff ff    	je     10dde50 <my.sexpr_parser::next_token+0x90>
 10ddf2f:	4c 89 e7             	mov    %r12,%rdi
 10ddf32:	48 89 ee             	mov    %rbp,%rsi
 10ddf35:	e8 36 50 04 00       	call   1122f70 <my.sexpr_tokenizer::advance>
 10ddf3a:	4d 8b 6c 24 08       	mov    0x8(%r12),%r13
 10ddf3f:	49 39 dd             	cmp    %rbx,%r13
 10ddf42:	76 bc                	jbe    10ddf00 <my.sexpr_parser::next_token+0x140>
 10ddf44:	48 8d 3d 65 77 08 00 	lea    0x87765(%rip),%rdi        # 11656b0 <core_durable_error.verbs+0x14f70>
 10ddf4b:	4c 89 ee             	mov    %r13,%rsi
 10ddf4e:	31 d2                	xor    %edx,%edx
 10ddf50:	e8 ab 7e fa ff       	call   1085e00 <myl_core_trap>
 10ddf55:	48 8b 45 08          	mov    0x8(%rbp),%rax
 10ddf59:	48 89 44 24 18       	mov    %rax,0x18(%rsp)
 10ddf5e:	48 8b 45 10          	mov    0x10(%rbp),%rax
 10ddf62:	48 89 44 24 10       	mov    %rax,0x10(%rsp)
 10ddf67:	49 89 f2             	mov    %rsi,%r10
 10ddf6a:	4c 89 7c 24 40       	mov    %r15,0x40(%rsp)
 10ddf6f:	4c 89 74 24 48       	mov    %r14,0x48(%rsp)
 10ddf74:	49 39 dd             	cmp    %rbx,%r13
 10ddf77:	0f 87 35 0e 00 00    	ja     10dedb2 <my.sexpr_parser::next_token+0xff2>
 10ddf7d:	41 b9 08 00 00 00    	mov    $0x8,%r9d
 10ddf83:	4d 89 d7             	mov    %r10,%r15
 10ddf86:	4d 89 d6             	mov    %r10,%r14
 10ddf89:	4d 39 ea             	cmp    %r13,%r10
 10ddf8c:	0f 8d 50 13 00 00    	jge    10df2e2 <my.sexpr_parser::next_token+0x1522>
 10ddf92:	4c 89 d0             	mov    %r10,%rax
 10ddf95:	48 c1 f8 3f          	sar    $0x3f,%rax
 10ddf99:	4c 21 e8             	and    %r13,%rax
 10ddf9c:	4c 01 d0             	add    %r10,%rax
 10ddf9f:	4c 39 e8             	cmp    %r13,%rax
 10ddfa2:	0f 83 85 0e 00 00    	jae    10dee2d <my.sexpr_parser::next_token+0x106d>
 10ddfa8:	49 8d 4c 24 20       	lea    0x20(%r12),%rcx
 10ddfad:	48 89 4c 24 20       	mov    %rcx,0x20(%rsp)
 10ddfb2:	41 0f b6 44 04 20    	movzbl 0x20(%r12,%rax,1),%eax
 10ddfb8:	83 f8 22             	cmp    $0x22,%eax
 10ddfbb:	4c 89 54 24 08       	mov    %r10,0x8(%rsp)
 10ddfc0:	0f 84 34 01 00 00    	je     10de0fa <my.sexpr_parser::next_token+0x33a>
 10ddfc6:	83 f8 29             	cmp    $0x29,%eax
 10ddfc9:	0f 84 0c 01 00 00    	je     10de0db <my.sexpr_parser::next_token+0x31b>
 10ddfcf:	83 f8 28             	cmp    $0x28,%eax
 10ddfd2:	0f 85 7c 02 00 00    	jne    10de254 <my.sexpr_parser::next_token+0x494>
 10ddfd8:	4c 89 e7             	mov    %r12,%rdi
 10ddfdb:	48 89 ee             	mov    %rbp,%rsi
 10ddfde:	e8 8d 4f 04 00       	call   1122f70 <my.sexpr_tokenizer::advance>
 10ddfe3:	4c 8b 54 24 08       	mov    0x8(%rsp),%r10
 10ddfe8:	4c 8b 7d 00          	mov    0x0(%rbp),%r15
 10ddfec:	45 31 c9             	xor    %r9d,%r9d
 10ddfef:	e9 eb 12 00 00       	jmp    10df2df <my.sexpr_parser::next_token+0x151f>
 10ddff4:	66 66 66 2e 0f 1f 84 	data16 data16 cs nopw 0x0(%rax,%rax,1)
 10ddffb:	00 00 00 00 00 
 10de000:	49 89 f8             	mov    %rdi,%r8
 10de003:	48 ff c6             	inc    %rsi
 10de006:	49 89 f2             	mov    %rsi,%r10
 10de009:	4c 89 c1             	mov    %r8,%rcx
 10de00c:	4c 89 d6             	mov    %r10,%rsi
 10de00f:	4d 39 ea             	cmp    %r13,%r10
 10de012:	0f 8d f2 03 00 00    	jge    10de40a <my.sexpr_parser::next_token+0x64a>
 10de018:	4c 39 ee             	cmp    %r13,%rsi
 10de01b:	0f 83 fd 0d 00 00    	jae    10dee1e <my.sexpr_parser::next_token+0x105e>
 10de021:	41 0f b6 7c 34 20    	movzbl 0x20(%r12,%rsi,1),%edi
 10de027:	44 8d 47 f7          	lea    -0x9(%rdi),%r8d
 10de02b:	41 83 f8 17          	cmp    $0x17,%r8d
 10de02f:	77 1f                	ja     10de050 <my.sexpr_parser::next_token+0x290>
 10de031:	4a 63 3c 82          	movslq (%rdx,%r8,4),%rdi
 10de035:	48 01 d7             	add    %rdx,%rdi
 10de038:	ff e7                	jmp    *%rdi
 10de03a:	48 89 cf             	mov    %rcx,%rdi
 10de03d:	48 ff c7             	inc    %rdi
 10de040:	0f 80 0a 0e 00 00    	jo     10dee50 <my.sexpr_parser::next_token+0x1090>
 10de046:	48 39 c7             	cmp    %rax,%rdi
 10de049:	75 b5                	jne    10de000 <my.sexpr_parser::next_token+0x240>
 10de04b:	e9 ef 0d 00 00       	jmp    10dee3f <my.sexpr_parser::next_token+0x107f>
 10de050:	49 89 c8             	mov    %rcx,%r8
 10de053:	49 89 f2             	mov    %rsi,%r10
 10de056:	83 ff 3b             	cmp    $0x3b,%edi
 10de059:	0f 85 58 03 00 00    	jne    10de3b7 <my.sexpr_parser::next_token+0x5f7>
 10de05f:	66 66 66 66 66 66 2e 	data16 data16 data16 data16 data16 cs nopw 0x0(%rax,%rax,1)
 10de066:	0f 1f 84 00 00 00 00 
 10de06d:	00 
 10de06e:	66 66 66 66 66 66 2e 	data16 data16 data16 data16 data16 cs nopw 0x0(%rax,%rax,1)
 10de075:	0f 1f 84 00 00 00 00 
 10de07c:	00 
 10de07d:	0f 1f 00             	nopl   (%rax)
 10de080:	4d 39 ea             	cmp    %r13,%r10
 10de083:	0f 83 00 0d 00 00    	jae    10ded89 <my.sexpr_parser::next_token+0xfc9>
 10de089:	43 80 7c 14 20 0a    	cmpb   $0xa,0x20(%r12,%r10,1)
 10de08f:	0f 84 74 ff ff ff    	je     10de009 <my.sexpr_parser::next_token+0x249>
 10de095:	49 ff c0             	inc    %r8
 10de098:	0f 80 fd 0c 00 00    	jo     10ded9b <my.sexpr_parser::next_token+0xfdb>
 10de09e:	49 ff c2             	inc    %r10
 10de0a1:	4d 39 d5             	cmp    %r10,%r13
 10de0a4:	75 da                	jne    10de080 <my.sexpr_parser::next_token+0x2c0>
 10de0a6:	e9 53 03 00 00       	jmp    10de3fe <my.sexpr_parser::next_token+0x63e>
 10de0ab:	4c 8b 44 24 18       	mov    0x18(%rsp),%r8
 10de0b0:	4c 89 c1             	mov    %r8,%rcx
 10de0b3:	48 ff c1             	inc    %rcx
 10de0b6:	0f 80 fd 0d 00 00    	jo     10deeb9 <my.sexpr_parser::next_token+0x10f9>
 10de0bc:	48 39 c1             	cmp    %rax,%rcx
 10de0bf:	0f 84 e3 0d 00 00    	je     10deea8 <my.sexpr_parser::next_token+0x10e8>
 10de0c5:	48 ff c6             	inc    %rsi
 10de0c8:	41 b8 01 00 00 00    	mov    $0x1,%r8d
 10de0ce:	49 89 f2             	mov    %rsi,%r10
 10de0d1:	48 89 4c 24 18       	mov    %rcx,0x18(%rsp)
 10de0d6:	e9 2e ff ff ff       	jmp    10de009 <my.sexpr_parser::next_token+0x249>
 10de0db:	4c 89 e7             	mov    %r12,%rdi
 10de0de:	48 89 ee             	mov    %rbp,%rsi
 10de0e1:	e8 8a 4e 04 00       	call   1122f70 <my.sexpr_tokenizer::advance>
 10de0e6:	4c 8b 54 24 08       	mov    0x8(%rsp),%r10
 10de0eb:	4c 8b 7d 00          	mov    0x0(%rbp),%r15
 10de0ef:	41 b9 01 00 00 00    	mov    $0x1,%r9d
 10de0f5:	e9 e5 11 00 00       	jmp    10df2df <my.sexpr_parser::next_token+0x151f>
 10de0fa:	4d 85 d2             	test   %r10,%r10
 10de0fd:	0f 88 dc 01 00 00    	js     10de2df <my.sexpr_parser::next_token+0x51f>
 10de103:	48 be 00 00 00 00 00 	movabs $0x8000000000000000,%rsi
 10de10a:	00 00 80 
 10de10d:	4c 89 e8             	mov    %r13,%rax
 10de110:	48 f7 d0             	not    %rax
 10de113:	48 01 f0             	add    %rsi,%rax
 10de116:	48 39 44 24 18       	cmp    %rax,0x18(%rsp)
 10de11b:	0f 8f be 01 00 00    	jg     10de2df <my.sexpr_parser::next_token+0x51f>
 10de121:	48 39 44 24 10       	cmp    %rax,0x10(%rsp)
 10de126:	0f 8f b3 01 00 00    	jg     10de2df <my.sexpr_parser::next_token+0x51f>
 10de12c:	4d 8d 72 01          	lea    0x1(%r10),%r14
 10de130:	4c 8b 4c 24 10       	mov    0x10(%rsp),%r9
 10de135:	49 8d 49 01          	lea    0x1(%r9),%rcx
 10de139:	4d 39 ee             	cmp    %r13,%r14
 10de13c:	0f 83 a1 06 00 00    	jae    10de7e3 <my.sexpr_parser::next_token+0xa23>
 10de142:	48 8d 56 02          	lea    0x2(%rsi),%rdx
 10de146:	4c 8b 64 24 18       	mov    0x18(%rsp),%r12
 10de14b:	4c 89 e0             	mov    %r12,%rax
 10de14e:	4d 89 f7             	mov    %r14,%r15
 10de151:	eb 39                	jmp    10de18c <my.sexpr_parser::next_token+0x3cc>
 10de153:	66 66 66 66 66 66 2e 	data16 data16 data16 data16 data16 cs nopw 0x0(%rax,%rax,1)
 10de15a:	0f 1f 84 00 00 00 00 
 10de161:	00 
 10de162:	66 66 66 66 66 66 2e 	data16 data16 data16 data16 data16 cs nopw 0x0(%rax,%rax,1)
 10de169:	0f 1f 84 00 00 00 00 
 10de170:	00 
 10de171:	66 66 66 66 66 66 2e 	data16 data16 data16 data16 data16 cs nopw 0x0(%rax,%rax,1)
 10de178:	0f 1f 84 00 00 00 00 
 10de17f:	00 
 10de180:	49 ff c7             	inc    %r15
 10de183:	4d 39 ef             	cmp    %r13,%r15
 10de186:	0f 8d 67 06 00 00    	jge    10de7f3 <my.sexpr_parser::next_token+0xa33>
 10de18c:	4d 39 ef             	cmp    %r13,%r15
 10de18f:	0f 83 e2 0b 00 00    	jae    10ded77 <my.sexpr_parser::next_token+0xfb7>
 10de195:	48 8b 7c 24 20       	mov    0x20(%rsp),%rdi
 10de19a:	42 0f b6 3c 3f       	movzbl (%rdi,%r15,1),%edi
 10de19f:	83 ff 5c             	cmp    $0x5c,%edi
 10de1a2:	74 5c                	je     10de200 <my.sexpr_parser::next_token+0x440>
 10de1a4:	83 ff 22             	cmp    $0x22,%edi
 10de1a7:	0f 84 6c 04 00 00    	je     10de619 <my.sexpr_parser::next_token+0x859>
 10de1ad:	49 89 c8             	mov    %rcx,%r8
 10de1b0:	40 80 ff 0a          	cmp    $0xa,%dil
 10de1b4:	75 7b                	jne    10de231 <my.sexpr_parser::next_token+0x471>
 10de1b6:	48 89 c7             	mov    %rax,%rdi
 10de1b9:	48 ff c7             	inc    %rdi
 10de1bc:	0f 80 37 0c 00 00    	jo     10dedf9 <my.sexpr_parser::next_token+0x1039>
 10de1c2:	b9 01 00 00 00       	mov    $0x1,%ecx
 10de1c7:	48 89 f8             	mov    %rdi,%rax
 10de1ca:	eb b4                	jmp    10de180 <my.sexpr_parser::next_token+0x3c0>
 10de1cc:	66 66 66 66 66 66 2e 	data16 data16 data16 data16 data16 cs nopw 0x0(%rax,%rax,1)
 10de1d3:	0f 1f 84 00 00 00 00 
 10de1da:	00 
 10de1db:	66 66 66 66 66 66 2e 	data16 data16 data16 data16 data16 cs nopw 0x0(%rax,%rax,1)
 10de1e2:	0f 1f 84 00 00 00 00 
 10de1e9:	00 
 10de1ea:	66 66 66 66 66 66 2e 	data16 data16 data16 data16 data16 cs nopw 0x0(%rax,%rax,1)
 10de1f1:	0f 1f 84 00 00 00 00 
 10de1f8:	00 
 10de1f9:	0f 1f 80 00 00 00 00 	nopl   0x0(%rax)
 10de200:	49 89 c8             	mov    %rcx,%r8
 10de203:	49 ff c0             	inc    %r8
 10de206:	0f 80 b7 0b 00 00    	jo     10dedc3 <my.sexpr_parser::next_token+0x1003>
 10de20c:	49 39 d0             	cmp    %rdx,%r8
 10de20f:	0f 8c c2 0b 00 00    	jl     10dedd7 <my.sexpr_parser::next_token+0x1017>
 10de215:	49 ff c7             	inc    %r15
 10de218:	4d 39 ef             	cmp    %r13,%r15
 10de21b:	0f 8d cf 05 00 00    	jge    10de7f0 <my.sexpr_parser::next_token+0xa30>
 10de221:	48 8b 4c 24 20       	mov    0x20(%rsp),%rcx
 10de226:	42 0f b6 3c 39       	movzbl (%rcx,%r15,1),%edi
 10de22b:	40 80 ff 0a          	cmp    $0xa,%dil
 10de22f:	74 85                	je     10de1b6 <my.sexpr_parser::next_token+0x3f6>
 10de231:	4c 89 c1             	mov    %r8,%rcx
 10de234:	48 ff c1             	inc    %rcx
 10de237:	0f 80 a8 0b 00 00    	jo     10dede5 <my.sexpr_parser::next_token+0x1025>
 10de23d:	48 39 d1             	cmp    %rdx,%rcx
 10de240:	0f 8d 3a ff ff ff    	jge    10de180 <my.sexpr_parser::next_token+0x3c0>
 10de246:	48 8d 3d 93 77 08 00 	lea    0x87793(%rip),%rdi        # 11659e0 <core_durable_error.verbs+0x152a0>
 10de24d:	31 d2                	xor    %edx,%edx
 10de24f:	e8 ac 7b fa ff       	call   1085e00 <myl_core_trap>
 10de254:	8d 48 d0             	lea    -0x30(%rax),%ecx
 10de257:	80 f9 09             	cmp    $0x9,%cl
 10de25a:	0f 87 5c 01 00 00    	ja     10de3bc <my.sexpr_parser::next_token+0x5fc>
 10de260:	4d 85 d2             	test   %r10,%r10
 10de263:	0f 88 bc 01 00 00    	js     10de425 <my.sexpr_parser::next_token+0x665>
 10de269:	4c 89 ea             	mov    %r13,%rdx
 10de26c:	48 f7 d2             	not    %rdx
 10de26f:	48 b9 00 00 00 00 00 	movabs $0x8000000000000000,%rcx
 10de276:	00 00 80 
 10de279:	48 01 d1             	add    %rdx,%rcx
 10de27c:	48 39 4c 24 18       	cmp    %rcx,0x18(%rsp)
 10de281:	0f 8f 9e 01 00 00    	jg     10de425 <my.sexpr_parser::next_token+0x665>
 10de287:	48 39 4c 24 10       	cmp    %rcx,0x10(%rsp)
 10de28c:	0f 8f 93 01 00 00    	jg     10de425 <my.sexpr_parser::next_token+0x665>
 10de292:	31 c0                	xor    %eax,%eax
 10de294:	49 8d 4c 24 20       	lea    0x20(%r12),%rcx
 10de299:	42 80 3c 11 2d       	cmpb   $0x2d,(%rcx,%r10,1)
 10de29e:	0f 94 c0             	sete   %al
 10de2a1:	4c 01 d0             	add    %r10,%rax
 10de2a4:	4c 39 e8             	cmp    %r13,%rax
 10de2a7:	4d 89 ef             	mov    %r13,%r15
 10de2aa:	4c 0f 47 f8          	cmova  %rax,%r15
 10de2ae:	0f 83 95 04 00 00    	jae    10de749 <my.sexpr_parser::next_token+0x989>
 10de2b4:	4c 39 e8             	cmp    %r13,%rax
 10de2b7:	0f 83 ca 0b 00 00    	jae    10dee87 <my.sexpr_parser::next_token+0x10c7>
 10de2bd:	49 8d 4c 24 20       	lea    0x20(%r12),%rcx
 10de2c2:	0f b6 0c 01          	movzbl (%rcx,%rax,1),%ecx
 10de2c6:	80 c1 d0             	add    $0xd0,%cl
 10de2c9:	80 f9 0a             	cmp    $0xa,%cl
 10de2cc:	0f 83 74 04 00 00    	jae    10de746 <my.sexpr_parser::next_token+0x986>
 10de2d2:	48 ff c0             	inc    %rax
 10de2d5:	4c 39 e8             	cmp    %r13,%rax
 10de2d8:	7c da                	jl     10de2b4 <my.sexpr_parser::next_token+0x4f4>
 10de2da:	e9 6a 04 00 00       	jmp    10de749 <my.sexpr_parser::next_token+0x989>
 10de2df:	4c 89 e7             	mov    %r12,%rdi
 10de2e2:	48 89 ee             	mov    %rbp,%rsi
 10de2e5:	e8 86 4c 04 00       	call   1122f70 <my.sexpr_tokenizer::advance>
 10de2ea:	49 8b 54 24 08       	mov    0x8(%r12),%rdx
 10de2ef:	48 39 da             	cmp    %rbx,%rdx
 10de2f2:	0f 87 71 09 00 00    	ja     10dec69 <my.sexpr_parser::next_token+0xea9>
 10de2f8:	4c 8b 75 00          	mov    0x0(%rbp),%r14
 10de2fc:	4d 8d 6c 24 20       	lea    0x20(%r12),%r13
 10de301:	eb 61                	jmp    10de364 <my.sexpr_parser::next_token+0x5a4>
 10de303:	66 66 66 66 66 66 2e 	data16 data16 data16 data16 data16 cs nopw 0x0(%rax,%rax,1)
 10de30a:	0f 1f 84 00 00 00 00 
 10de311:	00 
 10de312:	66 66 66 66 66 66 2e 	data16 data16 data16 data16 data16 cs nopw 0x0(%rax,%rax,1)
 10de319:	0f 1f 84 00 00 00 00 
 10de320:	00 
 10de321:	66 66 66 66 66 66 2e 	data16 data16 data16 data16 data16 cs nopw 0x0(%rax,%rax,1)
 10de328:	0f 1f 84 00 00 00 00 
 10de32f:	00 
 10de330:	66 66 66 66 66 66 2e 	data16 data16 data16 data16 data16 cs nopw 0x0(%rax,%rax,1)
 10de337:	0f 1f 84 00 00 00 00 
 10de33e:	00 
 10de33f:	90                   	nop
 10de340:	4c 89 e7             	mov    %r12,%rdi
 10de343:	48 89 ee             	mov    %rbp,%rsi
 10de346:	e8 25 4c 04 00       	call   1122f70 <my.sexpr_tokenizer::advance>
 10de34b:	4c 89 e7             	mov    %r12,%rdi
 10de34e:	48 89 ee             	mov    %rbp,%rsi
 10de351:	e8 1a 4c 04 00       	call   1122f70 <my.sexpr_tokenizer::advance>
 10de356:	49 8b 54 24 08       	mov    0x8(%r12),%rdx
 10de35b:	48 39 da             	cmp    %rbx,%rdx
 10de35e:	0f 87 05 09 00 00    	ja     10dec69 <my.sexpr_parser::next_token+0xea9>
 10de364:	4c 8b 7d 00          	mov    0x0(%rbp),%r15
 10de368:	49 39 d7             	cmp    %rdx,%r15
 10de36b:	48 8b 4c 24 08       	mov    0x8(%rsp),%rcx
 10de370:	0f 8d 8c 03 00 00    	jge    10de702 <my.sexpr_parser::next_token+0x942>
 10de376:	4c 89 f8             	mov    %r15,%rax
 10de379:	48 c1 f8 3f          	sar    $0x3f,%rax
 10de37d:	48 21 d0             	and    %rdx,%rax
 10de380:	4c 01 f8             	add    %r15,%rax
 10de383:	48 39 d0             	cmp    %rdx,%rax
 10de386:	0f 83 cd 09 00 00    	jae    10ded59 <my.sexpr_parser::next_token+0xf99>
 10de38c:	41 0f b6 44 05 00    	movzbl 0x0(%r13,%rax,1),%eax
 10de392:	83 f8 5c             	cmp    $0x5c,%eax
 10de395:	74 a9                	je     10de340 <my.sexpr_parser::next_token+0x580>
 10de397:	83 f8 22             	cmp    $0x22,%eax
 10de39a:	75 af                	jne    10de34b <my.sexpr_parser::next_token+0x58b>
 10de39c:	4c 89 e7             	mov    %r12,%rdi
 10de39f:	48 89 ee             	mov    %rbp,%rsi
 10de3a2:	e8 c9 4b 04 00       	call   1122f70 <my.sexpr_tokenizer::advance>
 10de3a7:	41 b9 03 00 00 00    	mov    $0x3,%r9d
 10de3ad:	4c 8b 54 24 08       	mov    0x8(%rsp),%r10
 10de3b2:	e9 2b 0f 00 00       	jmp    10df2e2 <my.sexpr_parser::next_token+0x1522>
 10de3b7:	49 89 f2             	mov    %rsi,%r10
 10de3ba:	eb 4b                	jmp    10de407 <my.sexpr_parser::next_token+0x647>
 10de3bc:	83 f8 2d             	cmp    $0x2d,%eax
 10de3bf:	75 72                	jne    10de433 <my.sexpr_parser::next_token+0x673>
 10de3c1:	49 8d 72 01          	lea    0x1(%r10),%rsi
 10de3c5:	4c 39 ee             	cmp    %r13,%rsi
 10de3c8:	0f 8d 97 02 00 00    	jge    10de665 <my.sexpr_parser::next_token+0x8a5>
 10de3ce:	31 c9                	xor    %ecx,%ecx
 10de3d0:	49 83 fa ff          	cmp    $0xffffffffffffffff,%r10
 10de3d4:	49 0f 4c cd          	cmovl  %r13,%rcx
 10de3d8:	48 01 f1             	add    %rsi,%rcx
 10de3db:	4c 39 e9             	cmp    %r13,%rcx
 10de3de:	0f 83 2d 0b 00 00    	jae    10def11 <my.sexpr_parser::next_token+0x1151>
 10de3e4:	49 8d 54 24 20       	lea    0x20(%r12),%rdx
 10de3e9:	0f b6 0c 0a          	movzbl (%rdx,%rcx,1),%ecx
 10de3ed:	80 c1 d0             	add    $0xd0,%cl
 10de3f0:	80 f9 0a             	cmp    $0xa,%cl
 10de3f3:	0f 82 67 fe ff ff    	jb     10de260 <my.sexpr_parser::next_token+0x4a0>
 10de3f9:	e9 67 02 00 00       	jmp    10de665 <my.sexpr_parser::next_token+0x8a5>
 10de3fe:	4c 01 e9             	add    %r13,%rcx
 10de401:	48 29 f1             	sub    %rsi,%rcx
 10de404:	4d 89 ea             	mov    %r13,%r10
 10de407:	49 89 c8             	mov    %rcx,%r8
 10de40a:	4c 89 55 00          	mov    %r10,0x0(%rbp)
 10de40e:	48 8b 44 24 18       	mov    0x18(%rsp),%rax
 10de413:	48 89 45 08          	mov    %rax,0x8(%rbp)
 10de417:	4c 89 44 24 10       	mov    %r8,0x10(%rsp)
 10de41c:	4c 89 45 10          	mov    %r8,0x10(%rbp)
 10de420:	e9 45 fb ff ff       	jmp    10ddf6a <my.sexpr_parser::next_token+0x1aa>
 10de425:	83 f8 2d             	cmp    $0x2d,%eax
 10de428:	0f 85 a8 0b 00 00    	jne    10defd6 <my.sexpr_parser::next_token+0x1216>
 10de42e:	e9 8a 0b 00 00       	jmp    10defbd <my.sexpr_parser::next_token+0x11fd>
 10de433:	89 c1                	mov    %eax,%ecx
 10de435:	83 e1 df             	and    $0xffffffdf,%ecx
 10de438:	83 c1 bf             	add    $0xffffffbf,%ecx
 10de43b:	83 f9 1a             	cmp    $0x1a,%ecx
 10de43e:	0f 83 05 02 00 00    	jae    10de649 <my.sexpr_parser::next_token+0x889>
 10de444:	4d 85 d2             	test   %r10,%r10
 10de447:	0f 88 91 00 00 00    	js     10de4de <my.sexpr_parser::next_token+0x71e>
 10de44d:	4c 89 e9             	mov    %r13,%rcx
 10de450:	48 f7 d1             	not    %rcx
 10de453:	48 b8 00 00 00 00 00 	movabs $0x8000000000000000,%rax
 10de45a:	00 00 80 
 10de45d:	48 01 c8             	add    %rcx,%rax
 10de460:	48 39 44 24 18       	cmp    %rax,0x18(%rsp)
 10de465:	7f 77                	jg     10de4de <my.sexpr_parser::next_token+0x71e>
 10de467:	48 39 44 24 10       	cmp    %rax,0x10(%rsp)
 10de46c:	7f 70                	jg     10de4de <my.sexpr_parser::next_token+0x71e>
 10de46e:	4d 39 d5             	cmp    %r10,%r13
 10de471:	4c 89 d6             	mov    %r10,%rsi
 10de474:	49 0f 47 f5          	cmova  %r13,%rsi
 10de478:	c5 f9 6e 05 f0 5d f2 	vmovd  -0xda210(%rip),%xmm0        # 1004270 <__anon_1393+0x50>
 10de47f:	ff 
 10de480:	4d 89 d7             	mov    %r10,%r15
 10de483:	48 8b 7c 24 10       	mov    0x10(%rsp),%rdi
 10de488:	e9 0e 01 00 00       	jmp    10de59b <my.sexpr_parser::next_token+0x7db>
 10de48d:	66 66 66 66 66 66 2e 	data16 data16 data16 data16 data16 cs nopw 0x0(%rax,%rax,1)
 10de494:	0f 1f 84 00 00 00 00 
 10de49b:	00 
 10de49c:	66 66 66 66 66 66 2e 	data16 data16 data16 data16 data16 cs nopw 0x0(%rax,%rax,1)
 10de4a3:	0f 1f 84 00 00 00 00 
 10de4aa:	00 
 10de4ab:	66 66 66 66 66 66 2e 	data16 data16 data16 data16 data16 cs nopw 0x0(%rax,%rax,1)
 10de4b2:	0f 1f 84 00 00 00 00 
 10de4b9:	00 
 10de4ba:	66 0f 1f 44 00 00    	nopw   0x0(%rax,%rax,1)
 10de4c0:	4c 89 e7             	mov    %r12,%rdi
 10de4c3:	48 89 ee             	mov    %rbp,%rsi
 10de4c6:	e8 a5 4a 04 00       	call   1122f70 <my.sexpr_tokenizer::advance>
 10de4cb:	4c 8b 54 24 08       	mov    0x8(%rsp),%r10
 10de4d0:	4d 8b 6c 24 08       	mov    0x8(%r12),%r13
 10de4d5:	49 39 dd             	cmp    %rbx,%r13
 10de4d8:	0f 87 98 09 00 00    	ja     10dee76 <my.sexpr_parser::next_token+0x10b6>
 10de4de:	4c 8b 7d 00          	mov    0x0(%rbp),%r15
 10de4e2:	41 b9 02 00 00 00    	mov    $0x2,%r9d
 10de4e8:	4d 39 ef             	cmp    %r13,%r15
 10de4eb:	0f 8d ee 0d 00 00    	jge    10df2df <my.sexpr_parser::next_token+0x151f>
 10de4f1:	4c 89 f8             	mov    %r15,%rax
 10de4f4:	48 c1 f8 3f          	sar    $0x3f,%rax
 10de4f8:	4c 21 e8             	and    %r13,%rax
 10de4fb:	4c 01 f8             	add    %r15,%rax
 10de4fe:	4c 39 e8             	cmp    %r13,%rax
 10de501:	0f 83 5d 09 00 00    	jae    10dee64 <my.sexpr_parser::next_token+0x10a4>
 10de507:	49 8d 4c 24 20       	lea    0x20(%r12),%rcx
 10de50c:	0f b6 04 01          	movzbl (%rcx,%rax,1),%eax
 10de510:	89 c2                	mov    %eax,%edx
 10de512:	81 e2 df 00 00 00    	and    $0xdf,%edx
 10de518:	83 c2 bf             	add    $0xffffffbf,%edx
 10de51b:	b1 01                	mov    $0x1,%cl
 10de51d:	83 fa 1a             	cmp    $0x1a,%edx
 10de520:	73 52                	jae    10de574 <my.sexpr_parser::next_token+0x7b4>
 10de522:	c5 f9 6e c0          	vmovd  %eax,%xmm0
 10de526:	c4 e2 79 78 c0       	vpbroadcastb %xmm0,%xmm0
 10de52b:	c5 f9 74 05 3d 5d f2 	vpcmpeqb -0xda2c3(%rip),%xmm0,%xmm0        # 1004270 <__anon_1393+0x50>
 10de532:	ff 
 10de533:	c4 e2 79 21 c0       	vpmovsxbd %xmm0,%xmm0
 10de538:	c5 f8 50 d0          	vmovmskps %xmm0,%edx
 10de53c:	85 d2                	test   %edx,%edx
 10de53e:	75 80                	jne    10de4c0 <my.sexpr_parser::next_token+0x700>
 10de540:	89 c2                	mov    %eax,%edx
 10de542:	83 e2 fd             	and    $0xfffffffd,%edx
 10de545:	83 fa 2d             	cmp    $0x2d,%edx
 10de548:	0f 84 72 ff ff ff    	je     10de4c0 <my.sexpr_parser::next_token+0x700>
 10de54e:	89 c2                	mov    %eax,%edx
 10de550:	83 e2 fb             	and    $0xfffffffb,%edx
 10de553:	83 fa 2a             	cmp    $0x2a,%edx
 10de556:	0f 84 64 ff ff ff    	je     10de4c0 <my.sexpr_parser::next_token+0x700>
 10de55c:	83 c0 d5             	add    $0xffffffd5,%eax
 10de55f:	3c 02                	cmp    $0x2,%al
 10de561:	0f 82 59 ff ff ff    	jb     10de4c0 <my.sexpr_parser::next_token+0x700>
 10de567:	84 c9                	test   %cl,%cl
 10de569:	0f 85 51 ff ff ff    	jne    10de4c0 <my.sexpr_parser::next_token+0x700>
 10de56f:	e9 6b 0d 00 00       	jmp    10df2df <my.sexpr_parser::next_token+0x151f>
 10de574:	48 83 f8 2a          	cmp    $0x2a,%rax
 10de578:	74 a8                	je     10de522 <my.sexpr_parser::next_token+0x762>
 10de57a:	83 f8 5f             	cmp    $0x5f,%eax
 10de57d:	74 a3                	je     10de522 <my.sexpr_parser::next_token+0x762>
 10de57f:	83 f8 7e             	cmp    $0x7e,%eax
 10de582:	74 9e                	je     10de522 <my.sexpr_parser::next_token+0x762>
 10de584:	8d 48 d0             	lea    -0x30(%rax),%ecx
 10de587:	80 f9 0a             	cmp    $0xa,%cl
 10de58a:	0f 92 c1             	setb   %cl
 10de58d:	eb 93                	jmp    10de522 <my.sexpr_parser::next_token+0x762>
 10de58f:	49 ff c7             	inc    %r15
 10de592:	4d 39 fd             	cmp    %r15,%r13
 10de595:	0f 84 20 02 00 00    	je     10de7bb <my.sexpr_parser::next_token+0x9fb>
 10de59b:	4d 39 ef             	cmp    %r13,%r15
 10de59e:	0f 83 f5 08 00 00    	jae    10dee99 <my.sexpr_parser::next_token+0x10d9>
 10de5a4:	48 8b 44 24 20       	mov    0x20(%rsp),%rax
 10de5a9:	42 0f b6 04 38       	movzbl (%rax,%r15,1),%eax
 10de5ae:	89 c2                	mov    %eax,%edx
 10de5b0:	81 e2 df 00 00 00    	and    $0xdf,%edx
 10de5b6:	83 c2 bf             	add    $0xffffffbf,%edx
 10de5b9:	b1 01                	mov    $0x1,%cl
 10de5bb:	83 fa 1a             	cmp    $0x1a,%edx
 10de5be:	73 3e                	jae    10de5fe <my.sexpr_parser::next_token+0x83e>
 10de5c0:	c5 f9 6e c8          	vmovd  %eax,%xmm1
 10de5c4:	c4 e2 79 78 c9       	vpbroadcastb %xmm1,%xmm1
 10de5c9:	c5 f1 74 c8          	vpcmpeqb %xmm0,%xmm1,%xmm1
 10de5cd:	c4 e2 79 21 c9       	vpmovsxbd %xmm1,%xmm1
 10de5d2:	c5 f8 50 d1          	vmovmskps %xmm1,%edx
 10de5d6:	85 d2                	test   %edx,%edx
 10de5d8:	75 b5                	jne    10de58f <my.sexpr_parser::next_token+0x7cf>
 10de5da:	89 c2                	mov    %eax,%edx
 10de5dc:	83 e2 fd             	and    $0xfffffffd,%edx
 10de5df:	83 fa 2d             	cmp    $0x2d,%edx
 10de5e2:	74 ab                	je     10de58f <my.sexpr_parser::next_token+0x7cf>
 10de5e4:	89 c2                	mov    %eax,%edx
 10de5e6:	83 e2 fb             	and    $0xfffffffb,%edx
 10de5e9:	83 fa 2a             	cmp    $0x2a,%edx
 10de5ec:	74 a1                	je     10de58f <my.sexpr_parser::next_token+0x7cf>
 10de5ee:	83 c0 d5             	add    $0xffffffd5,%eax
 10de5f1:	3c 02                	cmp    $0x2,%al
 10de5f3:	72 9a                	jb     10de58f <my.sexpr_parser::next_token+0x7cf>
 10de5f5:	84 c9                	test   %cl,%cl
 10de5f7:	75 96                	jne    10de58f <my.sexpr_parser::next_token+0x7cf>
 10de5f9:	e9 c0 01 00 00       	jmp    10de7be <my.sexpr_parser::next_token+0x9fe>
 10de5fe:	48 83 f8 2a          	cmp    $0x2a,%rax
 10de602:	74 bc                	je     10de5c0 <my.sexpr_parser::next_token+0x800>
 10de604:	83 f8 5f             	cmp    $0x5f,%eax
 10de607:	74 b7                	je     10de5c0 <my.sexpr_parser::next_token+0x800>
 10de609:	83 f8 7e             	cmp    $0x7e,%eax
 10de60c:	74 b2                	je     10de5c0 <my.sexpr_parser::next_token+0x800>
 10de60e:	8d 48 d0             	lea    -0x30(%rax),%ecx
 10de611:	80 f9 0a             	cmp    $0xa,%cl
 10de614:	0f 92 c1             	setb   %cl
 10de617:	eb a7                	jmp    10de5c0 <my.sexpr_parser::next_token+0x800>
 10de619:	49 8d 7f 01          	lea    0x1(%r15),%rdi
 10de61d:	48 89 7d 00          	mov    %rdi,0x0(%rbp)
 10de621:	48 89 45 08          	mov    %rax,0x8(%rbp)
 10de625:	48 89 c8             	mov    %rcx,%rax
 10de628:	48 ff c0             	inc    %rax
 10de62b:	0f 80 9c 08 00 00    	jo     10deecd <my.sexpr_parser::next_token+0x110d>
 10de631:	48 39 d0             	cmp    %rdx,%rax
 10de634:	0f 8c a7 08 00 00    	jl     10deee1 <my.sexpr_parser::next_token+0x1121>
 10de63a:	48 89 45 10          	mov    %rax,0x10(%rbp)
 10de63e:	41 b9 03 00 00 00    	mov    $0x3,%r9d
 10de644:	e9 99 0c 00 00       	jmp    10df2e2 <my.sexpr_parser::next_token+0x1522>
 10de649:	48 83 f8 2a          	cmp    $0x2a,%rax
 10de64d:	0f 84 f1 fd ff ff    	je     10de444 <my.sexpr_parser::next_token+0x684>
 10de653:	83 f8 5f             	cmp    $0x5f,%eax
 10de656:	0f 84 e8 fd ff ff    	je     10de444 <my.sexpr_parser::next_token+0x684>
 10de65c:	83 f8 7e             	cmp    $0x7e,%eax
 10de65f:	0f 84 df fd ff ff    	je     10de444 <my.sexpr_parser::next_token+0x684>
 10de665:	89 c1                	mov    %eax,%ecx
 10de667:	83 e1 fb             	and    $0xfffffffb,%ecx
 10de66a:	83 f9 2b             	cmp    $0x2b,%ecx
 10de66d:	74 1e                	je     10de68d <my.sexpr_parser::next_token+0x8cd>
 10de66f:	89 c1                	mov    %eax,%ecx
 10de671:	83 e1 f7             	and    $0xfffffff7,%ecx
 10de674:	83 f9 25             	cmp    $0x25,%ecx
 10de677:	74 14                	je     10de68d <my.sexpr_parser::next_token+0x8cd>
 10de679:	3c 21                	cmp    $0x21,%al
 10de67b:	74 10                	je     10de68d <my.sexpr_parser::next_token+0x8cd>
 10de67d:	3c 3d                	cmp    $0x3d,%al
 10de67f:	74 0c                	je     10de68d <my.sexpr_parser::next_token+0x8cd>
 10de681:	83 e0 fd             	and    $0xfffffffd,%eax
 10de684:	83 f8 3c             	cmp    $0x3c,%eax
 10de687:	0f 85 f6 01 00 00    	jne    10de883 <my.sexpr_parser::next_token+0xac3>
 10de68d:	4c 89 e7             	mov    %r12,%rdi
 10de690:	48 89 ee             	mov    %rbp,%rsi
 10de693:	e8 d8 48 04 00       	call   1122f70 <my.sexpr_tokenizer::advance>
 10de698:	49 8b 54 24 08       	mov    0x8(%r12),%rdx
 10de69d:	48 39 da             	cmp    %rbx,%rdx
 10de6a0:	0f 87 49 08 00 00    	ja     10deeef <my.sexpr_parser::next_token+0x112f>
 10de6a6:	4c 8b 7d 00          	mov    0x0(%rbp),%r15
 10de6aa:	41 b9 02 00 00 00    	mov    $0x2,%r9d
 10de6b0:	49 39 d7             	cmp    %rdx,%r15
 10de6b3:	4c 8b 54 24 08       	mov    0x8(%rsp),%r10
 10de6b8:	49 8d 4c 24 20       	lea    0x20(%r12),%rcx
 10de6bd:	0f 8d 1c 0c 00 00    	jge    10df2df <my.sexpr_parser::next_token+0x151f>
 10de6c3:	4c 89 f8             	mov    %r15,%rax
 10de6c6:	48 c1 f8 3f          	sar    $0x3f,%rax
 10de6ca:	48 21 d0             	and    %rdx,%rax
 10de6cd:	4c 01 f8             	add    %r15,%rax
 10de6d0:	48 39 d0             	cmp    %rdx,%rax
 10de6d3:	0f 83 47 08 00 00    	jae    10def20 <my.sexpr_parser::next_token+0x1160>
 10de6d9:	80 3c 01 3d          	cmpb   $0x3d,(%rcx,%rax,1)
 10de6dd:	0f 85 fc 0b 00 00    	jne    10df2df <my.sexpr_parser::next_token+0x151f>
 10de6e3:	4c 89 e7             	mov    %r12,%rdi
 10de6e6:	48 89 ee             	mov    %rbp,%rsi
 10de6e9:	e8 82 48 04 00       	call   1122f70 <my.sexpr_tokenizer::advance>
 10de6ee:	41 b9 02 00 00 00    	mov    $0x2,%r9d
 10de6f4:	4c 8b 54 24 08       	mov    0x8(%rsp),%r10
 10de6f9:	4c 8b 7d 00          	mov    0x0(%rbp),%r15
 10de6fd:	e9 dd 0b 00 00       	jmp    10df2df <my.sexpr_parser::next_token+0x151f>
 10de702:	4c 8b 64 24 18       	mov    0x18(%rsp),%r12
 10de707:	4c 89 65 18          	mov    %r12,0x18(%rbp)
 10de70b:	48 8b 44 24 10       	mov    0x10(%rsp),%rax
 10de710:	48 89 45 20          	mov    %rax,0x20(%rbp)
 10de714:	48 89 4d 28          	mov    %rcx,0x28(%rbp)
 10de718:	48 8d 3d 01 fc 08 00 	lea    0x8fc01(%rip),%rdi        # 116e320 <core_durable_error.verbs+0x1dbe0>
 10de71f:	e8 9c 9a fd ff       	call   10b81c0 <myl_core_err_trace_origin_preserve_most>
 10de724:	48 8d 3d 05 71 08 00 	lea    0x87105(%rip),%rdi        # 1165830 <core_durable_error.verbs+0x150f0>
 10de72b:	e8 d0 9a fd ff       	call   10b8200 <myl_core_err_trace_append_preserve_most>
 10de730:	e9 e2 00 00 00       	jmp    10de817 <my.sexpr_parser::next_token+0xa57>
 10de735:	48 8d 3d 74 6f 08 00 	lea    0x86f74(%rip),%rdi        # 11656b0 <core_durable_error.verbs+0x14f70>
 10de73c:	4c 89 ee             	mov    %r13,%rsi
 10de73f:	31 d2                	xor    %edx,%edx
 10de741:	e8 ba 76 fa ff       	call   1085e00 <myl_core_trap>
 10de746:	49 89 c7             	mov    %rax,%r15
 10de749:	49 8d 77 01          	lea    0x1(%r15),%rsi
 10de74d:	bf 04 00 00 00       	mov    $0x4,%edi
 10de752:	4c 39 ee             	cmp    %r13,%rsi
 10de755:	0f 8d 61 01 00 00    	jge    10de8bc <my.sexpr_parser::next_token+0xafc>
 10de75b:	4d 39 ef             	cmp    %r13,%r15
 10de75e:	0f 83 cb 07 00 00    	jae    10def2f <my.sexpr_parser::next_token+0x116f>
 10de764:	49 8d 44 24 20       	lea    0x20(%r12),%rax
 10de769:	42 80 3c 38 2e       	cmpb   $0x2e,(%rax,%r15,1)
 10de76e:	0f 85 48 01 00 00    	jne    10de8bc <my.sexpr_parser::next_token+0xafc>
 10de774:	4c 39 ee             	cmp    %r13,%rsi
 10de777:	0f 83 04 08 00 00    	jae    10def81 <my.sexpr_parser::next_token+0x11c1>
 10de77d:	49 8d 44 24 20       	lea    0x20(%r12),%rax
 10de782:	0f b6 04 30          	movzbl (%rax,%rsi,1),%eax
 10de786:	04 d0                	add    $0xd0,%al
 10de788:	3c 09                	cmp    $0x9,%al
 10de78a:	0f 87 2c 01 00 00    	ja     10de8bc <my.sexpr_parser::next_token+0xafc>
 10de790:	49 8d 45 ff          	lea    -0x1(%r13),%rax
 10de794:	43 0f b6 4c 3c 21    	movzbl 0x21(%r12,%r15,1),%ecx
 10de79a:	80 c1 d0             	add    $0xd0,%cl
 10de79d:	49 ff c7             	inc    %r15
 10de7a0:	80 f9 0a             	cmp    $0xa,%cl
 10de7a3:	0f 83 0e 01 00 00    	jae    10de8b7 <my.sexpr_parser::next_token+0xaf7>
 10de7a9:	4c 39 f8             	cmp    %r15,%rax
 10de7ac:	75 e6                	jne    10de794 <my.sexpr_parser::next_token+0x9d4>
 10de7ae:	bf 05 00 00 00       	mov    $0x5,%edi
 10de7b3:	4d 89 ef             	mov    %r13,%r15
 10de7b6:	e9 01 01 00 00       	jmp    10de8bc <my.sexpr_parser::next_token+0xafc>
 10de7bb:	49 89 f7             	mov    %rsi,%r15
 10de7be:	4c 89 fa             	mov    %r15,%rdx
 10de7c1:	4c 29 d2             	sub    %r10,%rdx
 10de7c4:	48 89 f8             	mov    %rdi,%rax
 10de7c7:	48 01 d0             	add    %rdx,%rax
 10de7ca:	0f 80 8f 07 00 00    	jo     10def5f <my.sexpr_parser::next_token+0x119f>
 10de7d0:	48 89 45 10          	mov    %rax,0x10(%rbp)
 10de7d4:	4c 89 7d 00          	mov    %r15,0x0(%rbp)
 10de7d8:	41 b9 02 00 00 00    	mov    $0x2,%r9d
 10de7de:	e9 fc 0a 00 00       	jmp    10df2df <my.sexpr_parser::next_token+0x151f>
 10de7e3:	4d 89 f7             	mov    %r14,%r15
 10de7e6:	4c 8b 64 24 18       	mov    0x18(%rsp),%r12
 10de7eb:	4c 89 e0             	mov    %r12,%rax
 10de7ee:	eb 03                	jmp    10de7f3 <my.sexpr_parser::next_token+0xa33>
 10de7f0:	4c 89 c1             	mov    %r8,%rcx
 10de7f3:	4c 89 7d 00          	mov    %r15,0x0(%rbp)
 10de7f7:	48 89 45 08          	mov    %rax,0x8(%rbp)
 10de7fb:	48 89 4d 10          	mov    %rcx,0x10(%rbp)
 10de7ff:	4c 89 65 18          	mov    %r12,0x18(%rbp)
 10de803:	4c 89 4d 20          	mov    %r9,0x20(%rbp)
 10de807:	4c 89 55 28          	mov    %r10,0x28(%rbp)
 10de80b:	48 8d 3d 7e 70 08 00 	lea    0x8707e(%rip),%rdi        # 1165890 <core_durable_error.verbs+0x15150>
 10de812:	e8 a9 99 fd ff       	call   10b81c0 <myl_core_err_trace_origin_preserve_most>
 10de817:	48 8d 3d 52 27 08 00 	lea    0x82752(%rip),%rdi        # 1160f70 <core_durable_error.verbs+0x10830>
 10de81e:	e8 dd 99 fd ff       	call   10b8200 <myl_core_err_trace_append_preserve_most>
 10de823:	48 8d 1d 96 5e f8 ff 	lea    -0x7a16a(%rip),%rbx        # 10646c0 <core_number_pairs+0x5d030>
 10de82a:	41 be 03 00 00 00    	mov    $0x3,%r14d
 10de830:	4c 8b 7c 24 28       	mov    0x28(%rsp),%r15
 10de835:	48 8d 3d b4 ec 07 00 	lea    0x7ecb4(%rip),%rdi        # 115d4f0 <core_durable_error.verbs+0xcdb0>
 10de83c:	e8 bf 99 fd ff       	call   10b8200 <myl_core_err_trace_append_preserve_most>
 10de841:	48 8b bc 24 90 00 00 	mov    0x90(%rsp),%rdi
 10de848:	00 
 10de849:	e8 32 68 fa ff       	call   1085080 <myl_core_drop_owned>
 10de84e:	48 8d 3d 7b 9d 07 00 	lea    0x79d7b(%rip),%rdi        # 11585d0 <core_durable_error.verbs+0x7e90>
 10de855:	e8 66 99 fd ff       	call   10b81c0 <myl_core_err_trace_origin_preserve_most>
 10de85a:	4c 89 f8             	mov    %r15,%rax
 10de85d:	49 c7 07 01 00 00 00 	movq   $0x1,(%r15)
 10de864:	4d 89 77 08          	mov    %r14,0x8(%r15)
 10de868:	4d 89 67 68          	mov    %r12,0x68(%r15)
 10de86c:	48 8b 4c 24 10       	mov    0x10(%rsp),%rcx
 10de871:	49 89 4f 70          	mov    %rcx,0x70(%r15)
 10de875:	48 8b 4c 24 08       	mov    0x8(%rsp),%rcx
 10de87a:	49 89 4f 78          	mov    %rcx,0x78(%r15)
 10de87e:	e9 b0 0a 00 00       	jmp    10df333 <my.sexpr_parser::next_token+0x1573>
 10de883:	4c 8b 64 24 18       	mov    0x18(%rsp),%r12
 10de888:	4c 89 65 18          	mov    %r12,0x18(%rbp)
 10de88c:	48 8b 44 24 10       	mov    0x10(%rsp),%rax
 10de891:	48 89 45 20          	mov    %rax,0x20(%rbp)
 10de895:	4c 89 55 28          	mov    %r10,0x28(%rbp)
 10de899:	48 8d 3d 00 27 08 00 	lea    0x82700(%rip),%rdi        # 1160fa0 <core_durable_error.verbs+0x10860>
 10de8a0:	e8 1b 99 fd ff       	call   10b81c0 <myl_core_err_trace_origin_preserve_most>
 10de8a5:	48 8d 1d d4 5d f8 ff 	lea    -0x7a22c(%rip),%rbx        # 1064680 <core_number_pairs+0x5cff0>
 10de8ac:	41 be 02 00 00 00    	mov    $0x2,%r14d
 10de8b2:	e9 79 ff ff ff       	jmp    10de830 <my.sexpr_parser::next_token+0xa70>
 10de8b7:	bf 05 00 00 00       	mov    $0x5,%edi
 10de8bc:	4c 89 fa             	mov    %r15,%rdx
 10de8bf:	4c 29 d2             	sub    %r10,%rdx
 10de8c2:	48 8b 74 24 10       	mov    0x10(%rsp),%rsi
 10de8c7:	48 01 d6             	add    %rdx,%rsi
 10de8ca:	0f 80 30 06 00 00    	jo     10def00 <my.sexpr_parser::next_token+0x1140>
 10de8d0:	48 89 75 10          	mov    %rsi,0x10(%rbp)
 10de8d4:	4c 89 7d 00          	mov    %r15,0x0(%rbp)
 10de8d8:	4d 39 ef             	cmp    %r13,%r15
 10de8db:	0f 8d 72 01 00 00    	jge    10dea53 <my.sexpr_parser::next_token+0xc93>
 10de8e1:	0f 83 5a 06 00 00    	jae    10def41 <my.sexpr_parser::next_token+0x1181>
 10de8e7:	49 8d 44 24 20       	lea    0x20(%r12),%rax
 10de8ec:	42 80 3c 38 6d       	cmpb   $0x6d,(%rax,%r15,1)
 10de8f1:	0f 85 5c 01 00 00    	jne    10dea53 <my.sexpr_parser::next_token+0xc93>
 10de8f7:	49 8d 47 01          	lea    0x1(%r15),%rax
 10de8fb:	4c 39 e8             	cmp    %r13,%rax
 10de8fe:	0f 8d 4f 01 00 00    	jge    10dea53 <my.sexpr_parser::next_token+0xc93>
 10de904:	49 8d 4c 24 20       	lea    0x20(%r12),%rcx
 10de909:	0f b6 04 01          	movzbl (%rcx,%rax,1),%eax
 10de90d:	83 f8 69             	cmp    $0x69,%eax
 10de910:	0f 84 8b 00 00 00    	je     10de9a1 <my.sexpr_parser::next_token+0xbe1>
 10de916:	83 f8 6d             	cmp    $0x6d,%eax
 10de919:	0f 85 34 01 00 00    	jne    10dea53 <my.sexpr_parser::next_token+0xc93>
 10de91f:	49 8d 47 02          	lea    0x2(%r15),%rax
 10de923:	4c 39 e8             	cmp    %r13,%rax
 10de926:	0f 8d 01 01 00 00    	jge    10dea2d <my.sexpr_parser::next_token+0xc6d>
 10de92c:	49 8d 4c 24 20       	lea    0x20(%r12),%rcx
 10de931:	0f b6 04 01          	movzbl (%rcx,%rax,1),%eax
 10de935:	89 c2                	mov    %eax,%edx
 10de937:	81 e2 df 00 00 00    	and    $0xdf,%edx
 10de93d:	83 c2 bf             	add    $0xffffffbf,%edx
 10de940:	b1 01                	mov    $0x1,%cl
 10de942:	83 fa 1a             	cmp    $0x1a,%edx
 10de945:	0f 83 8b 03 00 00    	jae    10decd6 <my.sexpr_parser::next_token+0xf16>
 10de94b:	c5 f9 6e c0          	vmovd  %eax,%xmm0
 10de94f:	c4 e2 79 78 c0       	vpbroadcastb %xmm0,%xmm0
 10de954:	c5 f9 74 05 14 59 f2 	vpcmpeqb -0xda6ec(%rip),%xmm0,%xmm0        # 1004270 <__anon_1393+0x50>
 10de95b:	ff 
 10de95c:	c4 e2 79 21 c0       	vpmovsxbd %xmm0,%xmm0
 10de961:	c5 f8 50 d0          	vmovmskps %xmm0,%edx
 10de965:	85 d2                	test   %edx,%edx
 10de967:	0f 85 e6 00 00 00    	jne    10dea53 <my.sexpr_parser::next_token+0xc93>
 10de96d:	89 c2                	mov    %eax,%edx
 10de96f:	83 e2 fd             	and    $0xfffffffd,%edx
 10de972:	83 fa 2d             	cmp    $0x2d,%edx
 10de975:	0f 84 d8 00 00 00    	je     10dea53 <my.sexpr_parser::next_token+0xc93>
 10de97b:	89 c2                	mov    %eax,%edx
 10de97d:	83 e2 fb             	and    $0xfffffffb,%edx
 10de980:	83 fa 2a             	cmp    $0x2a,%edx
 10de983:	0f 84 ca 00 00 00    	je     10dea53 <my.sexpr_parser::next_token+0xc93>
 10de989:	83 c0 d5             	add    $0xffffffd5,%eax
 10de98c:	3c 02                	cmp    $0x2,%al
 10de98e:	0f 82 bf 00 00 00    	jb     10dea53 <my.sexpr_parser::next_token+0xc93>
 10de994:	84 c9                	test   %cl,%cl
 10de996:	0f 84 91 00 00 00    	je     10dea2d <my.sexpr_parser::next_token+0xc6d>
 10de99c:	e9 b2 00 00 00       	jmp    10dea53 <my.sexpr_parser::next_token+0xc93>
 10de9a1:	49 8d 47 02          	lea    0x2(%r15),%rax
 10de9a5:	4c 39 e8             	cmp    %r13,%rax
 10de9a8:	0f 8d a5 00 00 00    	jge    10dea53 <my.sexpr_parser::next_token+0xc93>
 10de9ae:	49 8d 4c 24 20       	lea    0x20(%r12),%rcx
 10de9b3:	80 3c 01 6c          	cmpb   $0x6c,(%rcx,%rax,1)
 10de9b7:	0f 85 96 00 00 00    	jne    10dea53 <my.sexpr_parser::next_token+0xc93>
 10de9bd:	49 8d 47 03          	lea    0x3(%r15),%rax
 10de9c1:	4c 39 e8             	cmp    %r13,%rax
 10de9c4:	7d 5c                	jge    10dea22 <my.sexpr_parser::next_token+0xc62>
 10de9c6:	49 8d 4c 24 20       	lea    0x20(%r12),%rcx
 10de9cb:	0f b6 04 01          	movzbl (%rcx,%rax,1),%eax
 10de9cf:	89 c2                	mov    %eax,%edx
 10de9d1:	81 e2 df 00 00 00    	and    $0xdf,%edx
 10de9d7:	83 c2 bf             	add    $0xffffffbf,%edx
 10de9da:	b1 01                	mov    $0x1,%cl
 10de9dc:	83 fa 1a             	cmp    $0x1a,%edx
 10de9df:	0f 83 2a 03 00 00    	jae    10ded0f <my.sexpr_parser::next_token+0xf4f>
 10de9e5:	c5 f9 6e c0          	vmovd  %eax,%xmm0
 10de9e9:	c4 e2 79 78 c0       	vpbroadcastb %xmm0,%xmm0
 10de9ee:	c5 f9 74 05 7a 58 f2 	vpcmpeqb -0xda786(%rip),%xmm0,%xmm0        # 1004270 <__anon_1393+0x50>
 10de9f5:	ff 
 10de9f6:	c4 e2 79 21 c0       	vpmovsxbd %xmm0,%xmm0
 10de9fb:	c5 f8 50 d0          	vmovmskps %xmm0,%edx
 10de9ff:	85 d2                	test   %edx,%edx
 10dea01:	75 50                	jne    10dea53 <my.sexpr_parser::next_token+0xc93>
 10dea03:	89 c2                	mov    %eax,%edx
 10dea05:	83 e2 fd             	and    $0xfffffffd,%edx
 10dea08:	83 fa 2d             	cmp    $0x2d,%edx
 10dea0b:	74 46                	je     10dea53 <my.sexpr_parser::next_token+0xc93>
 10dea0d:	89 c2                	mov    %eax,%edx
 10dea0f:	83 e2 fb             	and    $0xfffffffb,%edx
 10dea12:	83 fa 2a             	cmp    $0x2a,%edx
 10dea15:	74 3c                	je     10dea53 <my.sexpr_parser::next_token+0xc93>
 10dea17:	83 c0 d5             	add    $0xffffffd5,%eax
 10dea1a:	3c 02                	cmp    $0x2,%al
 10dea1c:	72 35                	jb     10dea53 <my.sexpr_parser::next_token+0xc93>
 10dea1e:	84 c9                	test   %cl,%cl
 10dea20:	75 31                	jne    10dea53 <my.sexpr_parser::next_token+0xc93>
 10dea22:	4c 89 e7             	mov    %r12,%rdi
 10dea25:	48 89 ee             	mov    %rbp,%rsi
 10dea28:	e8 43 45 04 00       	call   1122f70 <my.sexpr_tokenizer::advance>
 10dea2d:	4c 89 e7             	mov    %r12,%rdi
 10dea30:	48 89 ee             	mov    %rbp,%rsi
 10dea33:	e8 38 45 04 00       	call   1122f70 <my.sexpr_tokenizer::advance>
 10dea38:	4c 89 e7             	mov    %r12,%rdi
 10dea3b:	48 89 ee             	mov    %rbp,%rsi
 10dea3e:	e8 2d 45 04 00       	call   1122f70 <my.sexpr_tokenizer::advance>
 10dea43:	4c 8b 54 24 08       	mov    0x8(%rsp),%r10
 10dea48:	41 b9 06 00 00 00    	mov    $0x6,%r9d
 10dea4e:	e9 8c 08 00 00       	jmp    10df2df <my.sexpr_parser::next_token+0x151f>
 10dea53:	48 89 74 24 30       	mov    %rsi,0x30(%rsp)
 10dea58:	48 89 7c 24 38       	mov    %rdi,0x38(%rsp)
 10dea5d:	4c 89 e7             	mov    %r12,%rdi
 10dea60:	48 89 ee             	mov    %rbp,%rsi
 10dea63:	e8 18 75 05 00       	call   1135f80 <my.sexpr_tokenizer::si_suffix_len>
 10dea68:	48 85 c0             	test   %rax,%rax
 10dea6b:	74 28                	je     10dea95 <my.sexpr_parser::next_token+0xcd5>
 10dea6d:	49 89 c6             	mov    %rax,%r14
 10dea70:	66 66 66 66 66 66 2e 	data16 data16 data16 data16 data16 cs nopw 0x0(%rax,%rax,1)
 10dea77:	0f 1f 84 00 00 00 00 
 10dea7e:	00 
 10dea7f:	90                   	nop
 10dea80:	4c 89 e7             	mov    %r12,%rdi
 10dea83:	48 89 ee             	mov    %rbp,%rsi
 10dea86:	e8 e5 44 04 00       	call   1122f70 <my.sexpr_tokenizer::advance>
 10dea8b:	49 ff ce             	dec    %r14
 10dea8e:	75 f0                	jne    10dea80 <my.sexpr_parser::next_token+0xcc0>
 10dea90:	e9 3b 08 00 00       	jmp    10df2d0 <my.sexpr_parser::next_token+0x1510>
 10dea95:	49 8b 54 24 08       	mov    0x8(%r12),%rdx
 10dea9a:	48 39 da             	cmp    %rbx,%rdx
 10dea9d:	4c 8b 4c 24 38       	mov    0x38(%rsp),%r9
 10deaa2:	0f 87 c8 04 00 00    	ja     10def70 <my.sexpr_parser::next_token+0x11b0>
 10deaa8:	49 39 d7             	cmp    %rdx,%r15
 10deaab:	4c 8b 54 24 08       	mov    0x8(%rsp),%r10
 10deab0:	0f 8d 29 08 00 00    	jge    10df2df <my.sexpr_parser::next_token+0x151f>
 10deab6:	0f 83 d4 04 00 00    	jae    10def90 <my.sexpr_parser::next_token+0x11d0>
 10deabc:	49 8d 44 24 20       	lea    0x20(%r12),%rax
 10deac1:	42 0f b6 04 38       	movzbl (%rax,%r15,1),%eax
 10deac6:	3c 25                	cmp    $0x25,%al
 10deac8:	75 7f                	jne    10deb49 <my.sexpr_parser::next_token+0xd89>
 10deaca:	49 8d 4f 01          	lea    0x1(%r15),%rcx
 10deace:	48 39 d1             	cmp    %rdx,%rcx
 10dead1:	0f 83 42 09 00 00    	jae    10df419 <my.sexpr_parser::next_token+0x1659>
 10dead7:	49 8d 74 24 20       	lea    0x20(%r12),%rsi
 10deadc:	0f b6 34 0e          	movzbl (%rsi,%rcx,1),%esi
 10deae0:	89 f1                	mov    %esi,%ecx
 10deae2:	81 e1 df 00 00 00    	and    $0xdf,%ecx
 10deae8:	83 c1 bf             	add    $0xffffffbf,%ecx
 10deaeb:	40 b7 01             	mov    $0x1,%dil
 10deaee:	83 f9 1a             	cmp    $0x1a,%ecx
 10deaf1:	0f 83 83 01 00 00    	jae    10dec7a <my.sexpr_parser::next_token+0xeba>
 10deaf7:	c5 f9 6e c6          	vmovd  %esi,%xmm0
 10deafb:	c4 e2 79 78 c0       	vpbroadcastb %xmm0,%xmm0
 10deb00:	c5 f9 74 05 68 57 f2 	vpcmpeqb -0xda898(%rip),%xmm0,%xmm0        # 1004270 <__anon_1393+0x50>
 10deb07:	ff 
 10deb08:	c4 e2 79 21 c0       	vpmovsxbd %xmm0,%xmm0
 10deb0d:	c5 78 50 c0          	vmovmskps %xmm0,%r8d
 10deb11:	b9 25 00 00 00       	mov    $0x25,%ecx
 10deb16:	45 85 c0             	test   %r8d,%r8d
 10deb19:	75 52                	jne    10deb6d <my.sexpr_parser::next_token+0xdad>
 10deb1b:	41 89 f0             	mov    %esi,%r8d
 10deb1e:	41 83 e0 fd          	and    $0xfffffffd,%r8d
 10deb22:	41 83 f8 2d          	cmp    $0x2d,%r8d
 10deb26:	74 45                	je     10deb6d <my.sexpr_parser::next_token+0xdad>
 10deb28:	41 89 f0             	mov    %esi,%r8d
 10deb2b:	41 83 e0 fb          	and    $0xfffffffb,%r8d
 10deb2f:	41 83 f8 2a          	cmp    $0x2a,%r8d
 10deb33:	74 38                	je     10deb6d <my.sexpr_parser::next_token+0xdad>
 10deb35:	83 c6 d5             	add    $0xffffffd5,%esi
 10deb38:	40 80 fe 02          	cmp    $0x2,%sil
 10deb3c:	72 2f                	jb     10deb6d <my.sexpr_parser::next_token+0xdad>
 10deb3e:	40 84 ff             	test   %dil,%dil
 10deb41:	0f 84 d2 08 00 00    	je     10df419 <my.sexpr_parser::next_token+0x1659>
 10deb47:	eb 24                	jmp    10deb6d <my.sexpr_parser::next_token+0xdad>
 10deb49:	0f b6 c8             	movzbl %al,%ecx
 10deb4c:	89 cf                	mov    %ecx,%edi
 10deb4e:	81 e7 df 00 00 00    	and    $0xdf,%edi
 10deb54:	83 c7 bf             	add    $0xffffffbf,%edi
 10deb57:	40 b6 01             	mov    $0x1,%sil
 10deb5a:	83 ff 1a             	cmp    $0x1a,%edi
 10deb5d:	72 19                	jb     10deb78 <my.sexpr_parser::next_token+0xdb8>
 10deb5f:	3c 2a                	cmp    $0x2a,%al
 10deb61:	74 15                	je     10deb78 <my.sexpr_parser::next_token+0xdb8>
 10deb63:	83 f9 5f             	cmp    $0x5f,%ecx
 10deb66:	74 10                	je     10deb78 <my.sexpr_parser::next_token+0xdb8>
 10deb68:	83 f9 7e             	cmp    $0x7e,%ecx
 10deb6b:	74 0b                	je     10deb78 <my.sexpr_parser::next_token+0xdb8>
 10deb6d:	8d 70 d0             	lea    -0x30(%rax),%esi
 10deb70:	40 80 fe 0a          	cmp    $0xa,%sil
 10deb74:	40 0f 92 c6          	setb   %sil
 10deb78:	c5 f9 6e c0          	vmovd  %eax,%xmm0
 10deb7c:	c4 e2 79 78 c0       	vpbroadcastb %xmm0,%xmm0
 10deb81:	c5 f9 74 05 e7 56 f2 	vpcmpeqb -0xda919(%rip),%xmm0,%xmm0        # 1004270 <__anon_1393+0x50>
 10deb88:	ff 
 10deb89:	c4 e2 79 21 c0       	vpmovsxbd %xmm0,%xmm0
 10deb8e:	c5 f8 50 f8          	vmovmskps %xmm0,%edi
 10deb92:	85 ff                	test   %edi,%edi
 10deb94:	75 21                	jne    10debb7 <my.sexpr_parser::next_token+0xdf7>
 10deb96:	89 cf                	mov    %ecx,%edi
 10deb98:	83 e7 fd             	and    $0xfffffffd,%edi
 10deb9b:	83 ff 2d             	cmp    $0x2d,%edi
 10deb9e:	74 17                	je     10debb7 <my.sexpr_parser::next_token+0xdf7>
 10deba0:	83 e1 fb             	and    $0xfffffffb,%ecx
 10deba3:	83 f9 2a             	cmp    $0x2a,%ecx
 10deba6:	74 0f                	je     10debb7 <my.sexpr_parser::next_token+0xdf7>
 10deba8:	04 d5                	add    $0xd5,%al
 10debaa:	3c 02                	cmp    $0x2,%al
 10debac:	72 09                	jb     10debb7 <my.sexpr_parser::next_token+0xdf7>
 10debae:	40 84 f6             	test   %sil,%sil
 10debb1:	0f 84 28 07 00 00    	je     10df2df <my.sexpr_parser::next_token+0x151f>
 10debb7:	4c 89 fe             	mov    %r15,%rsi
 10debba:	4d 39 ef             	cmp    %r13,%r15
 10debbd:	4c 8b 44 24 30       	mov    0x30(%rsp),%r8
 10debc2:	0f 8d e0 00 00 00    	jge    10deca8 <my.sexpr_parser::next_token+0xee8>
 10debc8:	c5 f9 6e 05 a0 56 f2 	vmovd  -0xda960(%rip),%xmm0        # 1004270 <__anon_1393+0x50>
 10debcf:	ff 
 10debd0:	4c 89 fe             	mov    %r15,%rsi
 10debd3:	eb 0c                	jmp    10debe1 <my.sexpr_parser::next_token+0xe21>
 10debd5:	48 ff c6             	inc    %rsi
 10debd8:	49 39 f5             	cmp    %rsi,%r13
 10debdb:	0f 84 c4 00 00 00    	je     10deca5 <my.sexpr_parser::next_token+0xee5>
 10debe1:	48 89 f0             	mov    %rsi,%rax
 10debe4:	48 c1 f8 3f          	sar    $0x3f,%rax
 10debe8:	48 21 d0             	and    %rdx,%rax
 10debeb:	48 8d 0c 30          	lea    (%rax,%rsi,1),%rcx
 10debef:	48 39 d1             	cmp    %rdx,%rcx
 10debf2:	0f 83 5b 03 00 00    	jae    10def53 <my.sexpr_parser::next_token+0x1193>
 10debf8:	48 03 44 24 20       	add    0x20(%rsp),%rax
 10debfd:	0f b6 04 06          	movzbl (%rsi,%rax,1),%eax
 10dec01:	89 c7                	mov    %eax,%edi
 10dec03:	81 e7 df 00 00 00    	and    $0xdf,%edi
 10dec09:	83 c7 bf             	add    $0xffffffbf,%edi
 10dec0c:	b1 01                	mov    $0x1,%cl
 10dec0e:	83 ff 1a             	cmp    $0x1a,%edi
 10dec11:	73 3b                	jae    10dec4e <my.sexpr_parser::next_token+0xe8e>
 10dec13:	c5 f9 6e c8          	vmovd  %eax,%xmm1
 10dec17:	c4 e2 79 78 c9       	vpbroadcastb %xmm1,%xmm1
 10dec1c:	c5 f1 74 c8          	vpcmpeqb %xmm0,%xmm1,%xmm1
 10dec20:	c4 e2 79 21 c9       	vpmovsxbd %xmm1,%xmm1
 10dec25:	c5 f8 50 f9          	vmovmskps %xmm1,%edi
 10dec29:	85 ff                	test   %edi,%edi
 10dec2b:	75 a8                	jne    10debd5 <my.sexpr_parser::next_token+0xe15>
 10dec2d:	89 c7                	mov    %eax,%edi
 10dec2f:	83 e7 fd             	and    $0xfffffffd,%edi
 10dec32:	83 ff 2d             	cmp    $0x2d,%edi
 10dec35:	74 9e                	je     10debd5 <my.sexpr_parser::next_token+0xe15>
 10dec37:	89 c7                	mov    %eax,%edi
 10dec39:	83 e7 fb             	and    $0xfffffffb,%edi
 10dec3c:	83 ff 2a             	cmp    $0x2a,%edi
 10dec3f:	74 94                	je     10debd5 <my.sexpr_parser::next_token+0xe15>
 10dec41:	83 c0 d5             	add    $0xffffffd5,%eax
 10dec44:	3c 02                	cmp    $0x2,%al
 10dec46:	72 8d                	jb     10debd5 <my.sexpr_parser::next_token+0xe15>
 10dec48:	84 c9                	test   %cl,%cl
 10dec4a:	75 89                	jne    10debd5 <my.sexpr_parser::next_token+0xe15>
 10dec4c:	eb 5a                	jmp    10deca8 <my.sexpr_parser::next_token+0xee8>
 10dec4e:	48 83 f8 2a          	cmp    $0x2a,%rax
 10dec52:	74 bf                	je     10dec13 <my.sexpr_parser::next_token+0xe53>
 10dec54:	83 f8 5f             	cmp    $0x5f,%eax
 10dec57:	74 ba                	je     10dec13 <my.sexpr_parser::next_token+0xe53>
 10dec59:	83 f8 7e             	cmp    $0x7e,%eax
 10dec5c:	74 b5                	je     10dec13 <my.sexpr_parser::next_token+0xe53>
 10dec5e:	8d 48 d0             	lea    -0x30(%rax),%ecx
 10dec61:	80 f9 0a             	cmp    $0xa,%cl
 10dec64:	0f 92 c1             	setb   %cl
 10dec67:	eb aa                	jmp    10dec13 <my.sexpr_parser::next_token+0xe53>
 10dec69:	48 8d 3d 40 6a 08 00 	lea    0x86a40(%rip),%rdi        # 11656b0 <core_durable_error.verbs+0x14f70>
 10dec70:	48 89 d6             	mov    %rdx,%rsi
 10dec73:	31 d2                	xor    %edx,%edx
 10dec75:	e8 86 71 fa ff       	call   1085e00 <myl_core_trap>
 10dec7a:	48 83 fe 2a          	cmp    $0x2a,%rsi
 10dec7e:	0f 84 73 fe ff ff    	je     10deaf7 <my.sexpr_parser::next_token+0xd37>
 10dec84:	83 fe 5f             	cmp    $0x5f,%esi
 10dec87:	0f 84 6a fe ff ff    	je     10deaf7 <my.sexpr_parser::next_token+0xd37>
 10dec8d:	83 fe 7e             	cmp    $0x7e,%esi
 10dec90:	0f 84 61 fe ff ff    	je     10deaf7 <my.sexpr_parser::next_token+0xd37>
 10dec96:	8d 4e d0             	lea    -0x30(%rsi),%ecx
 10dec99:	80 f9 0a             	cmp    $0xa,%cl
 10dec9c:	40 0f 92 c7          	setb   %dil
 10deca0:	e9 52 fe ff ff       	jmp    10deaf7 <my.sexpr_parser::next_token+0xd37>
 10deca5:	4c 89 ee             	mov    %r13,%rsi
 10deca8:	48 89 f2             	mov    %rsi,%rdx
 10decab:	4c 29 fa             	sub    %r15,%rdx
 10decae:	0f 80 eb 02 00 00    	jo     10def9f <my.sexpr_parser::next_token+0x11df>
 10decb4:	4c 89 c0             	mov    %r8,%rax
 10decb7:	48 01 d0             	add    %rdx,%rax
 10decba:	0f 80 ee 02 00 00    	jo     10defae <my.sexpr_parser::next_token+0x11ee>
 10decc0:	48 89 45 10          	mov    %rax,0x10(%rbp)
 10decc4:	48 89 75 00          	mov    %rsi,0x0(%rbp)
 10decc8:	41 b9 02 00 00 00    	mov    $0x2,%r9d
 10decce:	49 89 f7             	mov    %rsi,%r15
 10decd1:	e9 09 06 00 00       	jmp    10df2df <my.sexpr_parser::next_token+0x151f>
 10decd6:	48 83 f8 2a          	cmp    $0x2a,%rax
 10decda:	0f 84 6b fc ff ff    	je     10de94b <my.sexpr_parser::next_token+0xb8b>
 10dece0:	83 f8 5f             	cmp    $0x5f,%eax
 10dece3:	0f 84 62 fc ff ff    	je     10de94b <my.sexpr_parser::next_token+0xb8b>
 10dece9:	83 f8 7e             	cmp    $0x7e,%eax
 10decec:	0f 84 59 fc ff ff    	je     10de94b <my.sexpr_parser::next_token+0xb8b>
 10decf2:	8d 48 d0             	lea    -0x30(%rax),%ecx
 10decf5:	80 f9 0a             	cmp    $0xa,%cl
 10decf8:	0f 92 c1             	setb   %cl
 10decfb:	e9 4b fc ff ff       	jmp    10de94b <my.sexpr_parser::next_token+0xb8b>
 10ded00:	48 8d 3d d9 69 08 00 	lea    0x869d9(%rip),%rdi        # 11656e0 <core_durable_error.verbs+0x14fa0>
 10ded07:	4c 89 ea             	mov    %r13,%rdx
 10ded0a:	e8 f1 70 fa ff       	call   1085e00 <myl_core_trap>
 10ded0f:	48 83 f8 2a          	cmp    $0x2a,%rax
 10ded13:	0f 84 cc fc ff ff    	je     10de9e5 <my.sexpr_parser::next_token+0xc25>
 10ded19:	83 f8 5f             	cmp    $0x5f,%eax
 10ded1c:	0f 84 c3 fc ff ff    	je     10de9e5 <my.sexpr_parser::next_token+0xc25>
 10ded22:	83 f8 7e             	cmp    $0x7e,%eax
 10ded25:	0f 84 ba fc ff ff    	je     10de9e5 <my.sexpr_parser::next_token+0xc25>
 10ded2b:	8d 48 d0             	lea    -0x30(%rax),%ecx
 10ded2e:	80 f9 0a             	cmp    $0xa,%cl
 10ded31:	0f 92 c1             	setb   %cl
 10ded34:	e9 ac fc ff ff       	jmp    10de9e5 <my.sexpr_parser::next_token+0xc25>
 10ded39:	48 8d 3d 70 69 08 00 	lea    0x86970(%rip),%rdi        # 11656b0 <core_durable_error.verbs+0x14f70>
 10ded40:	4c 89 ee             	mov    %r13,%rsi
 10ded43:	31 d2                	xor    %edx,%edx
 10ded45:	e8 b6 70 fa ff       	call   1085e00 <myl_core_trap>
 10ded4a:	48 8d 3d 8f 69 08 00 	lea    0x8698f(%rip),%rdi        # 11656e0 <core_durable_error.verbs+0x14fa0>
 10ded51:	4c 89 ea             	mov    %r13,%rdx
 10ded54:	e8 a7 70 fa ff       	call   1085e00 <myl_core_trap>
 10ded59:	48 8d 3d 80 69 08 00 	lea    0x86980(%rip),%rdi        # 11656e0 <core_durable_error.verbs+0x14fa0>
 10ded60:	4c 89 fe             	mov    %r15,%rsi
 10ded63:	e8 98 70 fa ff       	call   1085e00 <myl_core_trap>
 10ded68:	48 8d 3d 71 69 08 00 	lea    0x86971(%rip),%rdi        # 11656e0 <core_durable_error.verbs+0x14fa0>
 10ded6f:	4c 89 ea             	mov    %r13,%rdx
 10ded72:	e8 89 70 fa ff       	call   1085e00 <myl_core_trap>
 10ded77:	48 8d 3d e2 6a 08 00 	lea    0x86ae2(%rip),%rdi        # 1165860 <core_durable_error.verbs+0x15120>
 10ded7e:	4c 89 fe             	mov    %r15,%rsi
 10ded81:	4c 89 ea             	mov    %r13,%rdx
 10ded84:	e8 77 70 fa ff       	call   1085e00 <myl_core_trap>
 10ded89:	48 8d 3d f0 68 08 00 	lea    0x868f0(%rip),%rdi        # 1165680 <core_durable_error.verbs+0x14f40>
 10ded90:	4c 89 ee             	mov    %r13,%rsi
 10ded93:	4c 89 ea             	mov    %r13,%rdx
 10ded96:	e8 65 70 fa ff       	call   1085e00 <myl_core_trap>
 10ded9b:	48 ff c8             	dec    %rax
 10ded9e:	48 8d 3d ab 68 08 00 	lea    0x868ab(%rip),%rdi        # 1165650 <core_durable_error.verbs+0x14f10>
 10deda5:	ba 01 00 00 00       	mov    $0x1,%edx
 10dedaa:	48 89 c6             	mov    %rax,%rsi
 10dedad:	e8 4e 70 fa ff       	call   1085e00 <myl_core_trap>
 10dedb2:	48 8d 3d f7 68 08 00 	lea    0x868f7(%rip),%rdi        # 11656b0 <core_durable_error.verbs+0x14f70>
 10dedb9:	4c 89 ee             	mov    %r13,%rsi
 10dedbc:	31 d2                	xor    %edx,%edx
 10dedbe:	e8 3d 70 fa ff       	call   1085e00 <myl_core_trap>
 10dedc3:	48 8d 3d f6 6a 08 00 	lea    0x86af6(%rip),%rdi        # 11658c0 <core_durable_error.verbs+0x15180>
 10dedca:	ba 01 00 00 00       	mov    $0x1,%edx
 10dedcf:	48 89 ce             	mov    %rcx,%rsi
 10dedd2:	e8 29 70 fa ff       	call   1085e00 <myl_core_trap>
 10dedd7:	48 8d 3d 12 6b 08 00 	lea    0x86b12(%rip),%rdi        # 11658f0 <core_durable_error.verbs+0x151b0>
 10dedde:	31 d2                	xor    %edx,%edx
 10dede0:	e8 1b 70 fa ff       	call   1085e00 <myl_core_trap>
 10dede5:	48 8d 3d c4 6b 08 00 	lea    0x86bc4(%rip),%rdi        # 11659b0 <core_durable_error.verbs+0x15270>
 10dedec:	ba 01 00 00 00       	mov    $0x1,%edx
 10dedf1:	4c 89 c6             	mov    %r8,%rsi
 10dedf4:	e8 07 70 fa ff       	call   1085e00 <myl_core_trap>
 10dedf9:	48 8d 3d 80 6b 08 00 	lea    0x86b80(%rip),%rdi        # 1165980 <core_durable_error.verbs+0x15240>
 10dee00:	ba 01 00 00 00       	mov    $0x1,%edx
 10dee05:	48 89 c6             	mov    %rax,%rsi
 10dee08:	e8 f3 6f fa ff       	call   1085e00 <myl_core_trap>
 10dee0d:	48 8d 3d dc f4 08 00 	lea    0x8f4dc(%rip),%rdi        # 116e2f0 <core_durable_error.verbs+0x1dbb0>
 10dee14:	4c 89 ee             	mov    %r13,%rsi
 10dee17:	31 d2                	xor    %edx,%edx
 10dee19:	e8 e2 6f fa ff       	call   1085e00 <myl_core_trap>
 10dee1e:	48 8d 3d 3b 67 08 00 	lea    0x8673b(%rip),%rdi        # 1165560 <core_durable_error.verbs+0x14e20>
 10dee25:	4c 89 ea             	mov    %r13,%rdx
 10dee28:	e8 d3 6f fa ff       	call   1085e00 <myl_core_trap>
 10dee2d:	48 8d 3d ac 68 08 00 	lea    0x868ac(%rip),%rdi        # 11656e0 <core_durable_error.verbs+0x14fa0>
 10dee34:	4c 89 d6             	mov    %r10,%rsi
 10dee37:	4c 89 ea             	mov    %r13,%rdx
 10dee3a:	e8 c1 6f fa ff       	call   1085e00 <myl_core_trap>
 10dee3f:	48 8d 3d 7a 67 08 00 	lea    0x8677a(%rip),%rdi        # 11655c0 <core_durable_error.verbs+0x14e80>
 10dee46:	48 89 c6             	mov    %rax,%rsi
 10dee49:	31 d2                	xor    %edx,%edx
 10dee4b:	e8 b0 6f fa ff       	call   1085e00 <myl_core_trap>
 10dee50:	48 8d 3d 39 67 08 00 	lea    0x86739(%rip),%rdi        # 1165590 <core_durable_error.verbs+0x14e50>
 10dee57:	ba 01 00 00 00       	mov    $0x1,%edx
 10dee5c:	48 89 ce             	mov    %rcx,%rsi
 10dee5f:	e8 9c 6f fa ff       	call   1085e00 <myl_core_trap>
 10dee64:	48 8d 3d 75 68 08 00 	lea    0x86875(%rip),%rdi        # 11656e0 <core_durable_error.verbs+0x14fa0>
 10dee6b:	4c 89 fe             	mov    %r15,%rsi
 10dee6e:	4c 89 ea             	mov    %r13,%rdx
 10dee71:	e8 8a 6f fa ff       	call   1085e00 <myl_core_trap>
 10dee76:	48 8d 3d 33 68 08 00 	lea    0x86833(%rip),%rdi        # 11656b0 <core_durable_error.verbs+0x14f70>
 10dee7d:	4c 89 ee             	mov    %r13,%rsi
 10dee80:	31 d2                	xor    %edx,%edx
 10dee82:	e8 79 6f fa ff       	call   1085e00 <myl_core_trap>
 10dee87:	48 8d 3d b2 6b 08 00 	lea    0x86bb2(%rip),%rdi        # 1165a40 <core_durable_error.verbs+0x15300>
 10dee8e:	4c 89 fe             	mov    %r15,%rsi
 10dee91:	4c 89 ea             	mov    %r13,%rdx
 10dee94:	e8 67 6f fa ff       	call   1085e00 <myl_core_trap>
 10dee99:	48 8d 3d 20 6d 08 00 	lea    0x86d20(%rip),%rdi        # 1165bc0 <core_durable_error.verbs+0x15480>
 10deea0:	4c 89 ea             	mov    %r13,%rdx
 10deea3:	e8 58 6f fa ff       	call   1085e00 <myl_core_trap>
 10deea8:	48 8d 3d 71 67 08 00 	lea    0x86771(%rip),%rdi        # 1165620 <core_durable_error.verbs+0x14ee0>
 10deeaf:	48 89 c6             	mov    %rax,%rsi
 10deeb2:	31 d2                	xor    %edx,%edx
 10deeb4:	e8 47 6f fa ff       	call   1085e00 <myl_core_trap>
 10deeb9:	48 8d 3d 30 67 08 00 	lea    0x86730(%rip),%rdi        # 11655f0 <core_durable_error.verbs+0x14eb0>
 10deec0:	ba 01 00 00 00       	mov    $0x1,%edx
 10deec5:	4c 89 c6             	mov    %r8,%rsi
 10deec8:	e8 33 6f fa ff       	call   1085e00 <myl_core_trap>
 10deecd:	48 8d 3d 4c 6a 08 00 	lea    0x86a4c(%rip),%rdi        # 1165920 <core_durable_error.verbs+0x151e0>
 10deed4:	ba 01 00 00 00       	mov    $0x1,%edx
 10deed9:	48 89 ce             	mov    %rcx,%rsi
 10deedc:	e8 1f 6f fa ff       	call   1085e00 <myl_core_trap>
 10deee1:	48 8d 3d 68 6a 08 00 	lea    0x86a68(%rip),%rdi        # 1165950 <core_durable_error.verbs+0x15210>
 10deee8:	31 d2                	xor    %edx,%edx
 10deeea:	e8 11 6f fa ff       	call   1085e00 <myl_core_trap>
 10deeef:	48 8d 3d ba 67 08 00 	lea    0x867ba(%rip),%rdi        # 11656b0 <core_durable_error.verbs+0x14f70>
 10deef6:	48 89 d6             	mov    %rdx,%rsi
 10deef9:	31 d2                	xor    %edx,%edx
 10deefb:	e8 00 6f fa ff       	call   1085e00 <myl_core_trap>
 10def00:	48 8d 3d 69 6b 08 00 	lea    0x86b69(%rip),%rdi        # 1165a70 <core_durable_error.verbs+0x15330>
 10def07:	48 8b 74 24 10       	mov    0x10(%rsp),%rsi
 10def0c:	e8 ef 6e fa ff       	call   1085e00 <myl_core_trap>
 10def11:	48 8d 3d f8 6a 08 00 	lea    0x86af8(%rip),%rdi        # 1165a10 <core_durable_error.verbs+0x152d0>
 10def18:	4c 89 ea             	mov    %r13,%rdx
 10def1b:	e8 e0 6e fa ff       	call   1085e00 <myl_core_trap>
 10def20:	48 8d 3d b9 67 08 00 	lea    0x867b9(%rip),%rdi        # 11656e0 <core_durable_error.verbs+0x14fa0>
 10def27:	4c 89 fe             	mov    %r15,%rsi
 10def2a:	e8 d1 6e fa ff       	call   1085e00 <myl_core_trap>
 10def2f:	48 8d 3d 9a 6b 08 00 	lea    0x86b9a(%rip),%rdi        # 1165ad0 <core_durable_error.verbs+0x15390>
 10def36:	4c 89 fe             	mov    %r15,%rsi
 10def39:	4c 89 ea             	mov    %r13,%rdx
 10def3c:	e8 bf 6e fa ff       	call   1085e00 <myl_core_trap>
 10def41:	48 8d 3d 98 67 08 00 	lea    0x86798(%rip),%rdi        # 11656e0 <core_durable_error.verbs+0x14fa0>
 10def48:	4c 89 fe             	mov    %r15,%rsi
 10def4b:	4c 89 ea             	mov    %r13,%rdx
 10def4e:	e8 ad 6e fa ff       	call   1085e00 <myl_core_trap>
 10def53:	48 8d 3d 06 6c 08 00 	lea    0x86c06(%rip),%rdi        # 1165b60 <core_durable_error.verbs+0x15420>
 10def5a:	e8 a1 6e fa ff       	call   1085e00 <myl_core_trap>
 10def5f:	48 8d 3d 2a 6c 08 00 	lea    0x86c2a(%rip),%rdi        # 1165b90 <core_durable_error.verbs+0x15450>
 10def66:	48 8b 74 24 10       	mov    0x10(%rsp),%rsi
 10def6b:	e8 90 6e fa ff       	call   1085e00 <myl_core_trap>
 10def70:	48 8d 3d 39 67 08 00 	lea    0x86739(%rip),%rdi        # 11656b0 <core_durable_error.verbs+0x14f70>
 10def77:	48 89 d6             	mov    %rdx,%rsi
 10def7a:	31 d2                	xor    %edx,%edx
 10def7c:	e8 7f 6e fa ff       	call   1085e00 <myl_core_trap>
 10def81:	48 8d 3d 18 6b 08 00 	lea    0x86b18(%rip),%rdi        # 1165aa0 <core_durable_error.verbs+0x15360>
 10def88:	4c 89 ea             	mov    %r13,%rdx
 10def8b:	e8 70 6e fa ff       	call   1085e00 <myl_core_trap>
 10def90:	48 8d 3d 49 67 08 00 	lea    0x86749(%rip),%rdi        # 11656e0 <core_durable_error.verbs+0x14fa0>
 10def97:	4c 89 fe             	mov    %r15,%rsi
 10def9a:	e8 61 6e fa ff       	call   1085e00 <myl_core_trap>
 10def9f:	48 8d 3d 5a 6b 08 00 	lea    0x86b5a(%rip),%rdi        # 1165b00 <core_durable_error.verbs+0x153c0>
 10defa6:	4c 89 fa             	mov    %r15,%rdx
 10defa9:	e8 52 6e fa ff       	call   1085e00 <myl_core_trap>
 10defae:	48 8d 3d 7b 6b 08 00 	lea    0x86b7b(%rip),%rdi        # 1165b30 <core_durable_error.verbs+0x153f0>
 10defb5:	4c 89 c6             	mov    %r8,%rsi
 10defb8:	e8 43 6e fa ff       	call   1085e00 <myl_core_trap>
 10defbd:	4c 89 e7             	mov    %r12,%rdi
 10defc0:	48 89 ee             	mov    %rbp,%rsi
 10defc3:	e8 a8 3f 04 00       	call   1122f70 <my.sexpr_tokenizer::advance>
 10defc8:	4d 8b 6c 24 08       	mov    0x8(%r12),%r13
 10defcd:	49 39 dd             	cmp    %rbx,%r13
 10defd0:	0f 87 cc 05 00 00    	ja     10df5a2 <my.sexpr_parser::next_token+0x17e2>
 10defd6:	4c 8b 7d 00          	mov    0x0(%rbp),%r15
 10defda:	bf 04 00 00 00       	mov    $0x4,%edi
 10defdf:	4d 39 ef             	cmp    %r13,%r15
 10defe2:	0f 8d a5 00 00 00    	jge    10df08d <my.sexpr_parser::next_token+0x12cd>
 10defe8:	4c 89 f8             	mov    %r15,%rax
 10defeb:	48 c1 f8 3f          	sar    $0x3f,%rax
 10defef:	4c 21 e8             	and    %r13,%rax
 10deff2:	4c 01 f8             	add    %r15,%rax
 10deff5:	4c 39 e8             	cmp    %r13,%rax
 10deff8:	0f 83 1a 06 00 00    	jae    10df618 <my.sexpr_parser::next_token+0x1858>
 10deffe:	49 8d 4c 24 20       	lea    0x20(%r12),%rcx
 10df003:	0f b6 04 01          	movzbl (%rcx,%rax,1),%eax
 10df007:	8d 48 d0             	lea    -0x30(%rax),%ecx
 10df00a:	80 f9 09             	cmp    $0x9,%cl
 10df00d:	76 ae                	jbe    10defbd <my.sexpr_parser::next_token+0x11fd>
 10df00f:	3c 2e                	cmp    $0x2e,%al
 10df011:	75 7a                	jne    10df08d <my.sexpr_parser::next_token+0x12cd>
 10df013:	49 8d 77 01          	lea    0x1(%r15),%rsi
 10df017:	4c 39 ee             	cmp    %r13,%rsi
 10df01a:	7d 71                	jge    10df08d <my.sexpr_parser::next_token+0x12cd>
 10df01c:	31 c0                	xor    %eax,%eax
 10df01e:	49 83 ff ff          	cmp    $0xffffffffffffffff,%r15
 10df022:	49 0f 4c c5          	cmovl  %r13,%rax
 10df026:	48 01 f0             	add    %rsi,%rax
 10df029:	4c 39 e8             	cmp    %r13,%rax
 10df02c:	0f 83 6b 06 00 00    	jae    10df69d <my.sexpr_parser::next_token+0x18dd>
 10df032:	49 8d 4c 24 20       	lea    0x20(%r12),%rcx
 10df037:	0f b6 04 01          	movzbl (%rcx,%rax,1),%eax
 10df03b:	04 d0                	add    $0xd0,%al
 10df03d:	3c 0a                	cmp    $0xa,%al
 10df03f:	73 4c                	jae    10df08d <my.sexpr_parser::next_token+0x12cd>
 10df041:	4c 89 e7             	mov    %r12,%rdi
 10df044:	48 89 ee             	mov    %rbp,%rsi
 10df047:	e8 24 3f 04 00       	call   1122f70 <my.sexpr_tokenizer::advance>
 10df04c:	4d 8b 6c 24 08       	mov    0x8(%r12),%r13
 10df051:	49 39 dd             	cmp    %rbx,%r13
 10df054:	0f 87 ad 05 00 00    	ja     10df607 <my.sexpr_parser::next_token+0x1847>
 10df05a:	4c 8b 7d 00          	mov    0x0(%rbp),%r15
 10df05e:	bf 05 00 00 00       	mov    $0x5,%edi
 10df063:	4d 39 ef             	cmp    %r13,%r15
 10df066:	7d 25                	jge    10df08d <my.sexpr_parser::next_token+0x12cd>
 10df068:	4c 89 f8             	mov    %r15,%rax
 10df06b:	48 c1 f8 3f          	sar    $0x3f,%rax
 10df06f:	4c 21 e8             	and    %r13,%rax
 10df072:	4c 01 f8             	add    %r15,%rax
 10df075:	4c 39 e8             	cmp    %r13,%rax
 10df078:	0f 83 ac 05 00 00    	jae    10df62a <my.sexpr_parser::next_token+0x186a>
 10df07e:	49 8d 4c 24 20       	lea    0x20(%r12),%rcx
 10df083:	0f b6 04 01          	movzbl (%rcx,%rax,1),%eax
 10df087:	04 d0                	add    $0xd0,%al
 10df089:	3c 09                	cmp    $0x9,%al
 10df08b:	76 b4                	jbe    10df041 <my.sexpr_parser::next_token+0x1281>
 10df08d:	4d 39 ef             	cmp    %r13,%r15
 10df090:	0f 8d d1 01 00 00    	jge    10df267 <my.sexpr_parser::next_token+0x14a7>
 10df096:	4c 89 f8             	mov    %r15,%rax
 10df099:	48 c1 f8 3f          	sar    $0x3f,%rax
 10df09d:	4c 21 e8             	and    %r13,%rax
 10df0a0:	4c 01 f8             	add    %r15,%rax
 10df0a3:	4c 39 e8             	cmp    %r13,%rax
 10df0a6:	0f 83 b0 05 00 00    	jae    10df65c <my.sexpr_parser::next_token+0x189c>
 10df0ac:	49 8d 4c 24 20       	lea    0x20(%r12),%rcx
 10df0b1:	80 3c 01 6d          	cmpb   $0x6d,(%rcx,%rax,1)
 10df0b5:	0f 85 ac 01 00 00    	jne    10df267 <my.sexpr_parser::next_token+0x14a7>
 10df0bb:	49 8d 77 01          	lea    0x1(%r15),%rsi
 10df0bf:	4c 39 ee             	cmp    %r13,%rsi
 10df0c2:	0f 8d 9f 01 00 00    	jge    10df267 <my.sexpr_parser::next_token+0x14a7>
 10df0c8:	31 c0                	xor    %eax,%eax
 10df0ca:	49 83 ff ff          	cmp    $0xffffffffffffffff,%r15
 10df0ce:	49 0f 4c c5          	cmovl  %r13,%rax
 10df0d2:	48 01 f0             	add    %rsi,%rax
 10df0d5:	4c 39 e8             	cmp    %r13,%rax
 10df0d8:	0f 83 b0 05 00 00    	jae    10df68e <my.sexpr_parser::next_token+0x18ce>
 10df0de:	49 8d 4c 24 20       	lea    0x20(%r12),%rcx
 10df0e3:	0f b6 04 01          	movzbl (%rcx,%rax,1),%eax
 10df0e7:	83 f8 69             	cmp    $0x69,%eax
 10df0ea:	0f 84 a1 00 00 00    	je     10df191 <my.sexpr_parser::next_token+0x13d1>
 10df0f0:	83 f8 6d             	cmp    $0x6d,%eax
 10df0f3:	0f 85 6e 01 00 00    	jne    10df267 <my.sexpr_parser::next_token+0x14a7>
 10df0f9:	49 8d 77 02          	lea    0x2(%r15),%rsi
 10df0fd:	4c 39 ee             	cmp    %r13,%rsi
 10df100:	0f 8d 43 01 00 00    	jge    10df249 <my.sexpr_parser::next_token+0x1489>
 10df106:	31 c0                	xor    %eax,%eax
 10df108:	49 83 ff fe          	cmp    $0xfffffffffffffffe,%r15
 10df10c:	49 0f 4c c5          	cmovl  %r13,%rax
 10df110:	48 01 f0             	add    %rsi,%rax
 10df113:	4c 39 e8             	cmp    %r13,%rax
 10df116:	0f 83 9c 05 00 00    	jae    10df6b8 <my.sexpr_parser::next_token+0x18f8>
 10df11c:	49 8d 4c 24 20       	lea    0x20(%r12),%rcx
 10df121:	0f b6 04 01          	movzbl (%rcx,%rax,1),%eax
 10df125:	89 c2                	mov    %eax,%edx
 10df127:	81 e2 df 00 00 00    	and    $0xdf,%edx
 10df12d:	83 c2 bf             	add    $0xffffffbf,%edx
 10df130:	b1 01                	mov    $0x1,%cl
 10df132:	83 fa 1a             	cmp    $0x1a,%edx
 10df135:	0f 83 78 04 00 00    	jae    10df5b3 <my.sexpr_parser::next_token+0x17f3>
 10df13b:	c5 f9 6e c0          	vmovd  %eax,%xmm0
 10df13f:	c4 e2 79 78 c0       	vpbroadcastb %xmm0,%xmm0
 10df144:	c5 f9 74 05 24 51 f2 	vpcmpeqb -0xdaedc(%rip),%xmm0,%xmm0        # 1004270 <__anon_1393+0x50>
 10df14b:	ff 
 10df14c:	c4 e2 79 21 c0       	vpmovsxbd %xmm0,%xmm0
 10df151:	c5 f8 50 d0          	vmovmskps %xmm0,%edx
 10df155:	85 d2                	test   %edx,%edx
 10df157:	0f 85 0a 01 00 00    	jne    10df267 <my.sexpr_parser::next_token+0x14a7>
 10df15d:	89 c2                	mov    %eax,%edx
 10df15f:	83 e2 fd             	and    $0xfffffffd,%edx
 10df162:	83 fa 2d             	cmp    $0x2d,%edx
 10df165:	0f 84 fc 00 00 00    	je     10df267 <my.sexpr_parser::next_token+0x14a7>
 10df16b:	89 c2                	mov    %eax,%edx
 10df16d:	83 e2 fb             	and    $0xfffffffb,%edx
 10df170:	83 fa 2a             	cmp    $0x2a,%edx
 10df173:	0f 84 ee 00 00 00    	je     10df267 <my.sexpr_parser::next_token+0x14a7>
 10df179:	83 c0 d5             	add    $0xffffffd5,%eax
 10df17c:	3c 02                	cmp    $0x2,%al
 10df17e:	0f 82 e3 00 00 00    	jb     10df267 <my.sexpr_parser::next_token+0x14a7>
 10df184:	84 c9                	test   %cl,%cl
 10df186:	0f 84 bd 00 00 00    	je     10df249 <my.sexpr_parser::next_token+0x1489>
 10df18c:	e9 d6 00 00 00       	jmp    10df267 <my.sexpr_parser::next_token+0x14a7>
 10df191:	49 8d 77 02          	lea    0x2(%r15),%rsi
 10df195:	4c 39 ee             	cmp    %r13,%rsi
 10df198:	0f 8d c9 00 00 00    	jge    10df267 <my.sexpr_parser::next_token+0x14a7>
 10df19e:	31 c0                	xor    %eax,%eax
 10df1a0:	49 83 ff fe          	cmp    $0xfffffffffffffffe,%r15
 10df1a4:	49 0f 4c c5          	cmovl  %r13,%rax
 10df1a8:	48 01 f0             	add    %rsi,%rax
 10df1ab:	4c 39 e8             	cmp    %r13,%rax
 10df1ae:	0f 83 13 05 00 00    	jae    10df6c7 <my.sexpr_parser::next_token+0x1907>
 10df1b4:	49 8d 4c 24 20       	lea    0x20(%r12),%rcx
 10df1b9:	80 3c 01 6c          	cmpb   $0x6c,(%rcx,%rax,1)
 10df1bd:	0f 85 a4 00 00 00    	jne    10df267 <my.sexpr_parser::next_token+0x14a7>
 10df1c3:	49 8d 77 03          	lea    0x3(%r15),%rsi
 10df1c7:	4c 39 ee             	cmp    %r13,%rsi
 10df1ca:	7d 72                	jge    10df23e <my.sexpr_parser::next_token+0x147e>
 10df1cc:	31 c0                	xor    %eax,%eax
 10df1ce:	49 83 ff fd          	cmp    $0xfffffffffffffffd,%r15
 10df1d2:	49 0f 4c c5          	cmovl  %r13,%rax
 10df1d6:	48 01 f0             	add    %rsi,%rax
 10df1d9:	4c 39 e8             	cmp    %r13,%rax
 10df1dc:	0f 83 f4 04 00 00    	jae    10df6d6 <my.sexpr_parser::next_token+0x1916>
 10df1e2:	49 8d 4c 24 20       	lea    0x20(%r12),%rcx
 10df1e7:	0f b6 04 01          	movzbl (%rcx,%rax,1),%eax
 10df1eb:	89 c2                	mov    %eax,%edx
 10df1ed:	81 e2 df 00 00 00    	and    $0xdf,%edx
 10df1f3:	83 c2 bf             	add    $0xffffffbf,%edx
 10df1f6:	b1 01                	mov    $0x1,%cl
 10df1f8:	83 fa 1a             	cmp    $0x1a,%edx
 10df1fb:	0f 83 dc 03 00 00    	jae    10df5dd <my.sexpr_parser::next_token+0x181d>
 10df201:	c5 f9 6e c0          	vmovd  %eax,%xmm0
 10df205:	c4 e2 79 78 c0       	vpbroadcastb %xmm0,%xmm0
 10df20a:	c5 f9 74 05 5e 50 f2 	vpcmpeqb -0xdafa2(%rip),%xmm0,%xmm0        # 1004270 <__anon_1393+0x50>
 10df211:	ff 
 10df212:	c4 e2 79 21 c0       	vpmovsxbd %xmm0,%xmm0
 10df217:	c5 f8 50 d0          	vmovmskps %xmm0,%edx
 10df21b:	85 d2                	test   %edx,%edx
 10df21d:	75 48                	jne    10df267 <my.sexpr_parser::next_token+0x14a7>
 10df21f:	89 c2                	mov    %eax,%edx
 10df221:	83 e2 fd             	and    $0xfffffffd,%edx
 10df224:	83 fa 2d             	cmp    $0x2d,%edx
 10df227:	74 3e                	je     10df267 <my.sexpr_parser::next_token+0x14a7>
 10df229:	89 c2                	mov    %eax,%edx
 10df22b:	83 e2 fb             	and    $0xfffffffb,%edx
 10df22e:	83 fa 2a             	cmp    $0x2a,%edx
 10df231:	74 34                	je     10df267 <my.sexpr_parser::next_token+0x14a7>
 10df233:	83 c0 d5             	add    $0xffffffd5,%eax
 10df236:	3c 02                	cmp    $0x2,%al
 10df238:	72 2d                	jb     10df267 <my.sexpr_parser::next_token+0x14a7>
 10df23a:	84 c9                	test   %cl,%cl
 10df23c:	75 29                	jne    10df267 <my.sexpr_parser::next_token+0x14a7>
 10df23e:	4c 89 e7             	mov    %r12,%rdi
 10df241:	48 89 ee             	mov    %rbp,%rsi
 10df244:	e8 27 3d 04 00       	call   1122f70 <my.sexpr_tokenizer::advance>
 10df249:	4c 89 e7             	mov    %r12,%rdi
 10df24c:	48 89 ee             	mov    %rbp,%rsi
 10df24f:	e8 1c 3d 04 00       	call   1122f70 <my.sexpr_tokenizer::advance>
 10df254:	4c 89 e7             	mov    %r12,%rdi
 10df257:	48 89 ee             	mov    %rbp,%rsi
 10df25a:	e8 11 3d 04 00       	call   1122f70 <my.sexpr_tokenizer::advance>
 10df25f:	41 b9 06 00 00 00    	mov    $0x6,%r9d
 10df265:	eb 73                	jmp    10df2da <my.sexpr_parser::next_token+0x151a>
 10df267:	49 89 fe             	mov    %rdi,%r14
 10df26a:	4c 89 e7             	mov    %r12,%rdi
 10df26d:	48 89 ee             	mov    %rbp,%rsi
 10df270:	e8 0b 6d 05 00       	call   1135f80 <my.sexpr_tokenizer::si_suffix_len>
 10df275:	48 85 c0             	test   %rax,%rax
 10df278:	0f 84 cb 00 00 00    	je     10df349 <my.sexpr_parser::next_token+0x1589>
 10df27e:	49 89 c5             	mov    %rax,%r13
 10df281:	66 66 66 66 66 66 2e 	data16 data16 data16 data16 data16 cs nopw 0x0(%rax,%rax,1)
 10df288:	0f 1f 84 00 00 00 00 
 10df28f:	00 
 10df290:	66 66 66 66 66 66 2e 	data16 data16 data16 data16 data16 cs nopw 0x0(%rax,%rax,1)
 10df297:	0f 1f 84 00 00 00 00 
 10df29e:	00 
 10df29f:	66 66 66 66 66 66 2e 	data16 data16 data16 data16 data16 cs nopw 0x0(%rax,%rax,1)
 10df2a6:	0f 1f 84 00 00 00 00 
 10df2ad:	00 
 10df2ae:	66 66 66 66 66 66 2e 	data16 data16 data16 data16 data16 cs nopw 0x0(%rax,%rax,1)
 10df2b5:	0f 1f 84 00 00 00 00 
 10df2bc:	00 
 10df2bd:	0f 1f 00             	nopl   (%rax)
 10df2c0:	4c 89 e7             	mov    %r12,%rdi
 10df2c3:	48 89 ee             	mov    %rbp,%rsi
 10df2c6:	e8 a5 3c 04 00       	call   1122f70 <my.sexpr_tokenizer::advance>
 10df2cb:	49 ff cd             	dec    %r13
 10df2ce:	75 f0                	jne    10df2c0 <my.sexpr_parser::next_token+0x1500>
 10df2d0:	4c 8b 7d 00          	mov    0x0(%rbp),%r15
 10df2d4:	41 b9 07 00 00 00    	mov    $0x7,%r9d
 10df2da:	4c 8b 54 24 08       	mov    0x8(%rsp),%r10
 10df2df:	4d 89 d6             	mov    %r10,%r14
 10df2e2:	48 8b 44 24 28       	mov    0x28(%rsp),%rax
 10df2e7:	4c 89 48 08          	mov    %r9,0x8(%rax)
 10df2eb:	4c 89 70 10          	mov    %r14,0x10(%rax)
 10df2ef:	4c 89 78 18          	mov    %r15,0x18(%rax)
 10df2f3:	48 8b 4c 24 18       	mov    0x18(%rsp),%rcx
 10df2f8:	48 89 48 20          	mov    %rcx,0x20(%rax)
 10df2fc:	48 8b 4c 24 10       	mov    0x10(%rsp),%rcx
 10df301:	48 89 48 28          	mov    %rcx,0x28(%rax)
 10df305:	4c 89 50 30          	mov    %r10,0x30(%rax)
 10df309:	48 c7 00 00 00 00 00 	movq   $0x0,(%rax)
 10df310:	48 8b 4c 24 50       	mov    0x50(%rsp),%rcx
 10df315:	48 89 48 68          	mov    %rcx,0x68(%rax)
 10df319:	48 8b 4c 24 40       	mov    0x40(%rsp),%rcx
 10df31e:	48 89 48 70          	mov    %rcx,0x70(%rax)
 10df322:	48 8b 4c 24 48       	mov    0x48(%rsp),%rcx
 10df327:	48 89 48 78          	mov    %rcx,0x78(%rax)
 10df32b:	48 8b 9c 24 90 00 00 	mov    0x90(%rsp),%rbx
 10df332:	00 
 10df333:	48 89 98 80 00 00 00 	mov    %rbx,0x80(%rax)
 10df33a:	48 83 c4 58          	add    $0x58,%rsp
 10df33e:	5b                   	pop    %rbx
 10df33f:	41 5c                	pop    %r12
 10df341:	41 5d                	pop    %r13
 10df343:	41 5e                	pop    %r14
 10df345:	41 5f                	pop    %r15
 10df347:	5d                   	pop    %rbp
 10df348:	c3                   	ret
 10df349:	49 8b 54 24 08       	mov    0x8(%r12),%rdx
 10df34e:	48 39 da             	cmp    %rbx,%rdx
 10df351:	0f 87 17 03 00 00    	ja     10df66e <my.sexpr_parser::next_token+0x18ae>
 10df357:	4d 89 f1             	mov    %r14,%r9
 10df35a:	49 39 d7             	cmp    %rdx,%r15
 10df35d:	4c 8b 54 24 08       	mov    0x8(%rsp),%r10
 10df362:	4d 8d 6c 24 20       	lea    0x20(%r12),%r13
 10df367:	0f 8d 72 ff ff ff    	jge    10df2df <my.sexpr_parser::next_token+0x151f>
 10df36d:	4c 89 f8             	mov    %r15,%rax
 10df370:	48 c1 f8 3f          	sar    $0x3f,%rax
 10df374:	48 21 d0             	and    %rdx,%rax
 10df377:	4c 01 f8             	add    %r15,%rax
 10df37a:	48 39 d0             	cmp    %rdx,%rax
 10df37d:	0f 83 fc 02 00 00    	jae    10df67f <my.sexpr_parser::next_token+0x18bf>
 10df383:	41 0f b6 44 05 00    	movzbl 0x0(%r13,%rax,1),%eax
 10df389:	3c 25                	cmp    $0x25,%al
 10df38b:	0f 85 a7 00 00 00    	jne    10df438 <my.sexpr_parser::next_token+0x1678>
 10df391:	49 8d 77 01          	lea    0x1(%r15),%rsi
 10df395:	48 39 d6             	cmp    %rdx,%rsi
 10df398:	7d 7f                	jge    10df419 <my.sexpr_parser::next_token+0x1659>
 10df39a:	31 c9                	xor    %ecx,%ecx
 10df39c:	49 83 ff ff          	cmp    $0xffffffffffffffff,%r15
 10df3a0:	48 0f 4c ca          	cmovl  %rdx,%rcx
 10df3a4:	48 01 f1             	add    %rsi,%rcx
 10df3a7:	48 39 d1             	cmp    %rdx,%rcx
 10df3aa:	0f 83 fc 02 00 00    	jae    10df6ac <my.sexpr_parser::next_token+0x18ec>
 10df3b0:	41 0f b6 74 0d 00    	movzbl 0x0(%r13,%rcx,1),%esi
 10df3b6:	89 f1                	mov    %esi,%ecx
 10df3b8:	81 e1 df 00 00 00    	and    $0xdf,%ecx
 10df3be:	83 c1 bf             	add    $0xffffffbf,%ecx
 10df3c1:	40 b7 01             	mov    $0x1,%dil
 10df3c4:	83 f9 1a             	cmp    $0x1a,%ecx
 10df3c7:	0f 83 aa 01 00 00    	jae    10df577 <my.sexpr_parser::next_token+0x17b7>
 10df3cd:	c5 f9 6e c6          	vmovd  %esi,%xmm0
 10df3d1:	c4 e2 79 78 c0       	vpbroadcastb %xmm0,%xmm0
 10df3d6:	c5 f9 74 05 92 4e f2 	vpcmpeqb -0xdb16e(%rip),%xmm0,%xmm0        # 1004270 <__anon_1393+0x50>
 10df3dd:	ff 
 10df3de:	c4 e2 79 21 c0       	vpmovsxbd %xmm0,%xmm0
 10df3e3:	c5 78 50 c0          	vmovmskps %xmm0,%r8d
 10df3e7:	b9 25 00 00 00       	mov    $0x25,%ecx
 10df3ec:	45 85 c0             	test   %r8d,%r8d
 10df3ef:	75 6b                	jne    10df45c <my.sexpr_parser::next_token+0x169c>
 10df3f1:	41 89 f0             	mov    %esi,%r8d
 10df3f4:	41 83 e0 fd          	and    $0xfffffffd,%r8d
 10df3f8:	41 83 f8 2d          	cmp    $0x2d,%r8d
 10df3fc:	74 5e                	je     10df45c <my.sexpr_parser::next_token+0x169c>
 10df3fe:	41 89 f0             	mov    %esi,%r8d
 10df401:	41 83 e0 fb          	and    $0xfffffffb,%r8d
 10df405:	41 83 f8 2a          	cmp    $0x2a,%r8d
 10df409:	74 51                	je     10df45c <my.sexpr_parser::next_token+0x169c>
 10df40b:	83 c6 d5             	add    $0xffffffd5,%esi
 10df40e:	40 80 fe 02          	cmp    $0x2,%sil
 10df412:	72 48                	jb     10df45c <my.sexpr_parser::next_token+0x169c>
 10df414:	40 84 ff             	test   %dil,%dil
 10df417:	75 43                	jne    10df45c <my.sexpr_parser::next_token+0x169c>
 10df419:	4c 89 e7             	mov    %r12,%rdi
 10df41c:	48 89 ee             	mov    %rbp,%rsi
 10df41f:	e8 4c 3b 04 00       	call   1122f70 <my.sexpr_tokenizer::advance>
 10df424:	4c 8b 54 24 08       	mov    0x8(%rsp),%r10
 10df429:	4c 8b 7d 00          	mov    0x0(%rbp),%r15
 10df42d:	41 b9 07 00 00 00    	mov    $0x7,%r9d
 10df433:	e9 a7 fe ff ff       	jmp    10df2df <my.sexpr_parser::next_token+0x151f>
 10df438:	0f b6 c8             	movzbl %al,%ecx
 10df43b:	89 cf                	mov    %ecx,%edi
 10df43d:	81 e7 df 00 00 00    	and    $0xdf,%edi
 10df443:	83 c7 bf             	add    $0xffffffbf,%edi
 10df446:	40 b6 01             	mov    $0x1,%sil
 10df449:	83 ff 1a             	cmp    $0x1a,%edi
 10df44c:	72 19                	jb     10df467 <my.sexpr_parser::next_token+0x16a7>
 10df44e:	3c 2a                	cmp    $0x2a,%al
 10df450:	74 15                	je     10df467 <my.sexpr_parser::next_token+0x16a7>
 10df452:	83 f9 5f             	cmp    $0x5f,%ecx
 10df455:	74 10                	je     10df467 <my.sexpr_parser::next_token+0x16a7>
 10df457:	83 f9 7e             	cmp    $0x7e,%ecx
 10df45a:	74 0b                	je     10df467 <my.sexpr_parser::next_token+0x16a7>
 10df45c:	8d 70 d0             	lea    -0x30(%rax),%esi
 10df45f:	40 80 fe 0a          	cmp    $0xa,%sil
 10df463:	40 0f 92 c6          	setb   %sil
 10df467:	c5 f9 6e c0          	vmovd  %eax,%xmm0
 10df46b:	c4 e2 79 78 c0       	vpbroadcastb %xmm0,%xmm0
 10df470:	c5 f9 74 05 f8 4d f2 	vpcmpeqb -0xdb208(%rip),%xmm0,%xmm0        # 1004270 <__anon_1393+0x50>
 10df477:	ff 
 10df478:	c4 e2 79 21 c0       	vpmovsxbd %xmm0,%xmm0
 10df47d:	c5 f8 50 f8          	vmovmskps %xmm0,%edi
 10df481:	85 ff                	test   %edi,%edi
 10df483:	75 44                	jne    10df4c9 <my.sexpr_parser::next_token+0x1709>
 10df485:	89 cf                	mov    %ecx,%edi
 10df487:	83 e7 fd             	and    $0xfffffffd,%edi
 10df48a:	83 ff 2d             	cmp    $0x2d,%edi
 10df48d:	74 3a                	je     10df4c9 <my.sexpr_parser::next_token+0x1709>
 10df48f:	83 e1 fb             	and    $0xfffffffb,%ecx
 10df492:	83 f9 2a             	cmp    $0x2a,%ecx
 10df495:	74 32                	je     10df4c9 <my.sexpr_parser::next_token+0x1709>
 10df497:	04 d5                	add    $0xd5,%al
 10df499:	3c 02                	cmp    $0x2,%al
 10df49b:	72 2c                	jb     10df4c9 <my.sexpr_parser::next_token+0x1709>
 10df49d:	4d 89 d6             	mov    %r10,%r14
 10df4a0:	40 84 f6             	test   %sil,%sil
 10df4a3:	0f 84 39 fe ff ff    	je     10df2e2 <my.sexpr_parser::next_token+0x1522>
 10df4a9:	eb 1e                	jmp    10df4c9 <my.sexpr_parser::next_token+0x1709>
 10df4ab:	4c 89 e7             	mov    %r12,%rdi
 10df4ae:	48 89 ee             	mov    %rbp,%rsi
 10df4b1:	e8 ba 3a 04 00       	call   1122f70 <my.sexpr_tokenizer::advance>
 10df4b6:	4c 8b 54 24 08       	mov    0x8(%rsp),%r10
 10df4bb:	49 8b 54 24 08       	mov    0x8(%r12),%rdx
 10df4c0:	48 39 da             	cmp    %rbx,%rdx
 10df4c3:	0f 87 82 01 00 00    	ja     10df64b <my.sexpr_parser::next_token+0x188b>
 10df4c9:	4c 8b 7d 00          	mov    0x0(%rbp),%r15
 10df4cd:	41 b9 02 00 00 00    	mov    $0x2,%r9d
 10df4d3:	49 39 d7             	cmp    %rdx,%r15
 10df4d6:	0f 8d 03 fe ff ff    	jge    10df2df <my.sexpr_parser::next_token+0x151f>
 10df4dc:	4c 89 f8             	mov    %r15,%rax
 10df4df:	48 c1 f8 3f          	sar    $0x3f,%rax
 10df4e3:	48 21 d0             	and    %rdx,%rax
 10df4e6:	4c 01 f8             	add    %r15,%rax
 10df4e9:	48 39 d0             	cmp    %rdx,%rax
 10df4ec:	0f 83 4a 01 00 00    	jae    10df63c <my.sexpr_parser::next_token+0x187c>
 10df4f2:	41 0f b6 44 05 00    	movzbl 0x0(%r13,%rax,1),%eax
 10df4f8:	89 c2                	mov    %eax,%edx
 10df4fa:	81 e2 df 00 00 00    	and    $0xdf,%edx
 10df500:	83 c2 bf             	add    $0xffffffbf,%edx
 10df503:	b1 01                	mov    $0x1,%cl
 10df505:	83 fa 1a             	cmp    $0x1a,%edx
 10df508:	73 52                	jae    10df55c <my.sexpr_parser::next_token+0x179c>
 10df50a:	c5 f9 6e c0          	vmovd  %eax,%xmm0
 10df50e:	c4 e2 79 78 c0       	vpbroadcastb %xmm0,%xmm0
 10df513:	c5 f9 74 05 55 4d f2 	vpcmpeqb -0xdb2ab(%rip),%xmm0,%xmm0        # 1004270 <__anon_1393+0x50>
 10df51a:	ff 
 10df51b:	c4 e2 79 21 c0       	vpmovsxbd %xmm0,%xmm0
 10df520:	c5 f8 50 d0          	vmovmskps %xmm0,%edx
 10df524:	85 d2                	test   %edx,%edx
 10df526:	75 83                	jne    10df4ab <my.sexpr_parser::next_token+0x16eb>
 10df528:	89 c2                	mov    %eax,%edx
 10df52a:	83 e2 fd             	and    $0xfffffffd,%edx
 10df52d:	83 fa 2d             	cmp    $0x2d,%edx
 10df530:	0f 84 75 ff ff ff    	je     10df4ab <my.sexpr_parser::next_token+0x16eb>
 10df536:	89 c2                	mov    %eax,%edx
 10df538:	83 e2 fb             	and    $0xfffffffb,%edx
 10df53b:	83 fa 2a             	cmp    $0x2a,%edx
 10df53e:	0f 84 67 ff ff ff    	je     10df4ab <my.sexpr_parser::next_token+0x16eb>
 10df544:	83 c0 d5             	add    $0xffffffd5,%eax
 10df547:	3c 02                	cmp    $0x2,%al
 10df549:	0f 82 5c ff ff ff    	jb     10df4ab <my.sexpr_parser::next_token+0x16eb>
 10df54f:	84 c9                	test   %cl,%cl
 10df551:	0f 85 54 ff ff ff    	jne    10df4ab <my.sexpr_parser::next_token+0x16eb>
 10df557:	e9 83 fd ff ff       	jmp    10df2df <my.sexpr_parser::next_token+0x151f>
 10df55c:	48 83 f8 2a          	cmp    $0x2a,%rax
 10df560:	74 a8                	je     10df50a <my.sexpr_parser::next_token+0x174a>
 10df562:	83 f8 5f             	cmp    $0x5f,%eax
 10df565:	74 a3                	je     10df50a <my.sexpr_parser::next_token+0x174a>
 10df567:	83 f8 7e             	cmp    $0x7e,%eax
 10df56a:	74 9e                	je     10df50a <my.sexpr_parser::next_token+0x174a>
 10df56c:	8d 48 d0             	lea    -0x30(%rax),%ecx
 10df56f:	80 f9 0a             	cmp    $0xa,%cl
 10df572:	0f 92 c1             	setb   %cl
 10df575:	eb 93                	jmp    10df50a <my.sexpr_parser::next_token+0x174a>
 10df577:	48 83 fe 2a          	cmp    $0x2a,%rsi
 10df57b:	0f 84 4c fe ff ff    	je     10df3cd <my.sexpr_parser::next_token+0x160d>
 10df581:	83 fe 5f             	cmp    $0x5f,%esi
 10df584:	0f 84 43 fe ff ff    	je     10df3cd <my.sexpr_parser::next_token+0x160d>
 10df58a:	83 fe 7e             	cmp    $0x7e,%esi
 10df58d:	0f 84 3a fe ff ff    	je     10df3cd <my.sexpr_parser::next_token+0x160d>
 10df593:	8d 4e d0             	lea    -0x30(%rsi),%ecx
 10df596:	80 f9 0a             	cmp    $0xa,%cl
 10df599:	40 0f 92 c7          	setb   %dil
 10df59d:	e9 2b fe ff ff       	jmp    10df3cd <my.sexpr_parser::next_token+0x160d>
 10df5a2:	48 8d 3d 07 61 08 00 	lea    0x86107(%rip),%rdi        # 11656b0 <core_durable_error.verbs+0x14f70>
 10df5a9:	4c 89 ee             	mov    %r13,%rsi
 10df5ac:	31 d2                	xor    %edx,%edx
 10df5ae:	e8 4d 68 fa ff       	call   1085e00 <myl_core_trap>
 10df5b3:	48 83 f8 2a          	cmp    $0x2a,%rax
 10df5b7:	0f 84 7e fb ff ff    	je     10df13b <my.sexpr_parser::next_token+0x137b>
 10df5bd:	83 f8 5f             	cmp    $0x5f,%eax
 10df5c0:	0f 84 75 fb ff ff    	je     10df13b <my.sexpr_parser::next_token+0x137b>
 10df5c6:	83 f8 7e             	cmp    $0x7e,%eax
 10df5c9:	0f 84 6c fb ff ff    	je     10df13b <my.sexpr_parser::next_token+0x137b>
 10df5cf:	8d 48 d0             	lea    -0x30(%rax),%ecx
 10df5d2:	80 f9 0a             	cmp    $0xa,%cl
 10df5d5:	0f 92 c1             	setb   %cl
 10df5d8:	e9 5e fb ff ff       	jmp    10df13b <my.sexpr_parser::next_token+0x137b>
 10df5dd:	48 83 f8 2a          	cmp    $0x2a,%rax
 10df5e1:	0f 84 1a fc ff ff    	je     10df201 <my.sexpr_parser::next_token+0x1441>
 10df5e7:	83 f8 5f             	cmp    $0x5f,%eax
 10df5ea:	0f 84 11 fc ff ff    	je     10df201 <my.sexpr_parser::next_token+0x1441>
 10df5f0:	83 f8 7e             	cmp    $0x7e,%eax
 10df5f3:	0f 84 08 fc ff ff    	je     10df201 <my.sexpr_parser::next_token+0x1441>
 10df5f9:	8d 48 d0             	lea    -0x30(%rax),%ecx
 10df5fc:	80 f9 0a             	cmp    $0xa,%cl
 10df5ff:	0f 92 c1             	setb   %cl
 10df602:	e9 fa fb ff ff       	jmp    10df201 <my.sexpr_parser::next_token+0x1441>
 10df607:	48 8d 3d a2 60 08 00 	lea    0x860a2(%rip),%rdi        # 11656b0 <core_durable_error.verbs+0x14f70>
 10df60e:	4c 89 ee             	mov    %r13,%rsi
 10df611:	31 d2                	xor    %edx,%edx
 10df613:	e8 e8 67 fa ff       	call   1085e00 <myl_core_trap>
 10df618:	48 8d 3d c1 60 08 00 	lea    0x860c1(%rip),%rdi        # 11656e0 <core_durable_error.verbs+0x14fa0>
 10df61f:	4c 89 fe             	mov    %r15,%rsi
 10df622:	4c 89 ea             	mov    %r13,%rdx
 10df625:	e8 d6 67 fa ff       	call   1085e00 <myl_core_trap>
 10df62a:	48 8d 3d af 60 08 00 	lea    0x860af(%rip),%rdi        # 11656e0 <core_durable_error.verbs+0x14fa0>
 10df631:	4c 89 fe             	mov    %r15,%rsi
 10df634:	4c 89 ea             	mov    %r13,%rdx
 10df637:	e8 c4 67 fa ff       	call   1085e00 <myl_core_trap>
 10df63c:	48 8d 3d 9d 60 08 00 	lea    0x8609d(%rip),%rdi        # 11656e0 <core_durable_error.verbs+0x14fa0>
 10df643:	4c 89 fe             	mov    %r15,%rsi
 10df646:	e8 b5 67 fa ff       	call   1085e00 <myl_core_trap>
 10df64b:	48 8d 3d 5e 60 08 00 	lea    0x8605e(%rip),%rdi        # 11656b0 <core_durable_error.verbs+0x14f70>
 10df652:	48 89 d6             	mov    %rdx,%rsi
 10df655:	31 d2                	xor    %edx,%edx
 10df657:	e8 a4 67 fa ff       	call   1085e00 <myl_core_trap>
 10df65c:	48 8d 3d 7d 60 08 00 	lea    0x8607d(%rip),%rdi        # 11656e0 <core_durable_error.verbs+0x14fa0>
 10df663:	4c 89 fe             	mov    %r15,%rsi
 10df666:	4c 89 ea             	mov    %r13,%rdx
 10df669:	e8 92 67 fa ff       	call   1085e00 <myl_core_trap>
 10df66e:	48 8d 3d 3b 60 08 00 	lea    0x8603b(%rip),%rdi        # 11656b0 <core_durable_error.verbs+0x14f70>
 10df675:	48 89 d6             	mov    %rdx,%rsi
 10df678:	31 d2                	xor    %edx,%edx
 10df67a:	e8 81 67 fa ff       	call   1085e00 <myl_core_trap>
 10df67f:	48 8d 3d 5a 60 08 00 	lea    0x8605a(%rip),%rdi        # 11656e0 <core_durable_error.verbs+0x14fa0>
 10df686:	4c 89 fe             	mov    %r15,%rsi
 10df689:	e8 72 67 fa ff       	call   1085e00 <myl_core_trap>
 10df68e:	48 8d 3d 7b 63 08 00 	lea    0x8637b(%rip),%rdi        # 1165a10 <core_durable_error.verbs+0x152d0>
 10df695:	4c 89 ea             	mov    %r13,%rdx
 10df698:	e8 63 67 fa ff       	call   1085e00 <myl_core_trap>
 10df69d:	48 8d 3d 6c 63 08 00 	lea    0x8636c(%rip),%rdi        # 1165a10 <core_durable_error.verbs+0x152d0>
 10df6a4:	4c 89 ea             	mov    %r13,%rdx
 10df6a7:	e8 54 67 fa ff       	call   1085e00 <myl_core_trap>
 10df6ac:	48 8d 3d 5d 63 08 00 	lea    0x8635d(%rip),%rdi        # 1165a10 <core_durable_error.verbs+0x152d0>
 10df6b3:	e8 48 67 fa ff       	call   1085e00 <myl_core_trap>
 10df6b8:	48 8d 3d 51 63 08 00 	lea    0x86351(%rip),%rdi        # 1165a10 <core_durable_error.verbs+0x152d0>
 10df6bf:	4c 89 ea             	mov    %r13,%rdx
 10df6c2:	e8 39 67 fa ff       	call   1085e00 <myl_core_trap>
 10df6c7:	48 8d 3d 42 63 08 00 	lea    0x86342(%rip),%rdi        # 1165a10 <core_durable_error.verbs+0x152d0>
 10df6ce:	4c 89 ea             	mov    %r13,%rdx
 10df6d1:	e8 2a 67 fa ff       	call   1085e00 <myl_core_trap>
 10df6d6:	48 8d 3d 33 63 08 00 	lea    0x86333(%rip),%rdi        # 1165a10 <core_durable_error.verbs+0x152d0>
 10df6dd:	4c 89 ea             	mov    %r13,%rdx
 10df6e0:	e8 1b 67 fa ff       	call   1085e00 <myl_core_trap>

Disassembly of section .plt:
