
.tmp/lox-eda-parity/P2/base:     file format elf64-x86-64


Disassembly of section .text:

000000000105ceb0 <my.vm::run>:
 105ceb0:	55                   	push   %rbp
 105ceb1:	41 57                	push   %r15
 105ceb3:	41 56                	push   %r14
 105ceb5:	41 55                	push   %r13
 105ceb7:	41 54                	push   %r12
 105ceb9:	53                   	push   %rbx
 105ceba:	48 81 ec 28 08 00 00 	sub    $0x828,%rsp
 105cec1:	48 89 4c 24 68       	mov    %rcx,0x68(%rsp)
 105cec6:	48 89 54 24 48       	mov    %rdx,0x48(%rsp)
 105cecb:	49 89 f0             	mov    %rsi,%r8
 105cece:	48 89 bc 24 60 01 00 	mov    %rdi,0x160(%rsp)
 105ced5:	00 
 105ced6:	4c 8b b6 90 00 00 00 	mov    0x90(%rsi),%r14
 105cedd:	4c 89 f6             	mov    %r14,%rsi
 105cee0:	48 ff ce             	dec    %rsi
 105cee3:	0f 80 fd 38 00 00    	jo     10607e6 <my.vm::run+0x3936>
 105cee9:	49 8b a8 80 00 00 00 	mov    0x80(%r8),%rbp
 105cef0:	49 8b 80 88 00 00 00 	mov    0x88(%r8),%rax
 105cef7:	48 8b 50 08          	mov    0x8(%rax),%rdx
 105cefb:	48 39 d6             	cmp    %rdx,%rsi
 105cefe:	0f 83 f8 2f 00 00    	jae    105fefc <my.vm::run+0x304c>
 105cf04:	48 89 f1             	mov    %rsi,%rcx
 105cf07:	48 c1 e1 05          	shl    $0x5,%rcx
 105cf0b:	48 8b 54 08 20       	mov    0x20(%rax,%rcx,1),%rdx
 105cf10:	48 89 54 24 10       	mov    %rdx,0x10(%rsp)
 105cf15:	48 8b 74 08 28       	mov    0x28(%rax,%rcx,1),%rsi
 105cf1a:	4c 8b 7c 08 30       	mov    0x30(%rax,%rcx,1),%r15
 105cf1f:	48 8b 44 08 38       	mov    0x38(%rax,%rcx,1),%rax
 105cf24:	48 89 44 24 20       	mov    %rax,0x20(%rsp)
 105cf29:	4c 89 c7             	mov    %r8,%rdi
 105cf2c:	49 89 f5             	mov    %rsi,%r13
 105cf2f:	4c 89 fa             	mov    %r15,%rdx
 105cf32:	4c 89 c3             	mov    %r8,%rbx
 105cf35:	e8 f6 dd 00 00       	call   106ad30 <my.heap::function_instruction>
 105cf3a:	49 ff c7             	inc    %r15
 105cf3d:	0f 80 9e 2f 00 00    	jo     105fee1 <my.vm::run+0x3031>
 105cf43:	49 89 d9             	mov    %rbx,%r9
 105cf46:	4c 8d 25 03 a5 fa ff 	lea    -0x55afd(%rip),%r12        # 1007450 <core_number_pairs+0x1f0>
 105cf4d:	48 89 5c 24 50       	mov    %rbx,0x50(%rsp)
 105cf52:	66 66 66 66 66 2e 0f 	data16 data16 data16 data16 cs nopw 0x0(%rax,%rax,1)
 105cf59:	1f 84 00 00 00 00 00 
 105cf60:	48 89 eb             	mov    %rbp,%rbx
 105cf63:	49 8b 89 88 00 00 00 	mov    0x88(%r9),%rcx
 105cf6a:	4d 89 f2             	mov    %r14,%r10
 105cf6d:	49 8d 6e ff          	lea    -0x1(%r14),%rbp
 105cf71:	48 89 ea             	mov    %rbp,%rdx
 105cf74:	4d 85 f6             	test   %r14,%r14
 105cf77:	7f 07                	jg     105cf80 <my.vm::run+0xd0>
 105cf79:	48 8b 51 08          	mov    0x8(%rcx),%rdx
 105cf7d:	48 01 ea             	add    %rbp,%rdx
 105cf80:	48 c1 e2 05          	shl    $0x5,%rdx
 105cf84:	48 8b 74 24 10       	mov    0x10(%rsp),%rsi
 105cf89:	48 89 74 11 20       	mov    %rsi,0x20(%rcx,%rdx,1)
 105cf8e:	4d 89 eb             	mov    %r13,%r11
 105cf91:	4c 89 6c 11 28       	mov    %r13,0x28(%rcx,%rdx,1)
 105cf96:	4c 89 7c 11 30       	mov    %r15,0x30(%rcx,%rdx,1)
 105cf9b:	48 8b 74 24 20       	mov    0x20(%rsp),%rsi
 105cfa0:	48 89 74 11 38       	mov    %rsi,0x38(%rcx,%rdx,1)
 105cfa5:	49 89 89 88 00 00 00 	mov    %rcx,0x88(%r9)
 105cfac:	48 83 f8 24          	cmp    $0x24,%rax
 105cfb0:	0f 87 14 1e 00 00    	ja     105edca <my.vm::run+0x1f1a>
 105cfb6:	49 63 0c 84          	movslq (%r12,%rax,4),%rcx
 105cfba:	4c 01 e1             	add    %r12,%rcx
 105cfbd:	ff e1                	jmp    *%rcx
 105cfbf:	49 8b 89 80 00 00 00 	mov    0x80(%r9),%rcx
 105cfc6:	48 89 ce             	mov    %rcx,%rsi
 105cfc9:	48 ff ce             	dec    %rsi
 105cfcc:	0f 80 03 30 00 00    	jo     105ffd5 <my.vm::run+0x3125>
 105cfd2:	49 8b 49 78          	mov    0x78(%r9),%rcx
 105cfd6:	48 8b 51 08          	mov    0x8(%rcx),%rdx
 105cfda:	48 89 f7             	mov    %rsi,%rdi
 105cfdd:	48 39 d6             	cmp    %rdx,%rsi
 105cfe0:	0f 83 fc 27 00 00    	jae    105f7e2 <my.vm::run+0x2932>
 105cfe6:	48 c1 e7 04          	shl    $0x4,%rdi
 105cfea:	80 7c 39 20 02       	cmpb   $0x2,0x20(%rcx,%rdi,1)
 105cfef:	75 5b                	jne    105d04c <my.vm::run+0x19c>
 105cff1:	48 89 f5             	mov    %rsi,%rbp
 105cff4:	48 ff cd             	dec    %rbp
 105cff7:	0f 80 65 31 00 00    	jo     1060162 <my.vm::run+0x32b2>
 105cffd:	c5 fb 10 44 39 28    	vmovsd 0x28(%rcx,%rdi,1),%xmm0
 105d003:	48 89 ee             	mov    %rbp,%rsi
 105d006:	48 39 d5             	cmp    %rdx,%rbp
 105d009:	0f 83 ee 27 00 00    	jae    105f7fd <my.vm::run+0x294d>
 105d00f:	48 83 c1 20          	add    $0x20,%rcx
 105d013:	48 c1 e6 04          	shl    $0x4,%rsi
 105d017:	80 3c 31 02          	cmpb   $0x2,(%rcx,%rsi,1)
 105d01b:	75 2f                	jne    105d04c <my.vm::run+0x19c>
 105d01d:	48 01 f1             	add    %rsi,%rcx
 105d020:	c5 fb 10 49 08       	vmovsd 0x8(%rcx),%xmm1
 105d025:	48 83 c0 f0          	add    $0xfffffffffffffff0,%rax
 105d029:	48 83 f8 04          	cmp    $0x4,%rax
 105d02d:	0f 87 3b 22 00 00    	ja     105f26e <my.vm::run+0x23be>
 105d033:	48 8d 15 3e a5 fa ff 	lea    -0x55ac2(%rip),%rdx        # 1007578 <core_number_pairs+0x318>
 105d03a:	48 63 04 82          	movslq (%rdx,%rax,4),%rax
 105d03e:	48 01 d0             	add    %rdx,%rax
 105d041:	ff e0                	jmp    *%rax
 105d043:	c5 f9 2e c8          	vucomisd %xmm0,%xmm1
 105d047:	e9 0f 22 00 00       	jmp    105f25b <my.vm::run+0x23ab>
 105d04c:	48 8d 0d ad 60 fb ff 	lea    -0x49f53(%rip),%rcx        # 1013100 <core_number_pairs+0xbea0>
 105d053:	48 8d 7c 24 70       	lea    0x70(%rsp),%rdi
 105d058:	4c 89 ce             	mov    %r9,%rsi
 105d05b:	48 8b 54 24 48       	mov    0x48(%rsp),%rdx
 105d060:	4c 89 cb             	mov    %r9,%rbx
 105d063:	e8 38 6d 00 00       	call   1063da0 <my.vm::runtime_error>
 105d068:	f6 44 24 70 01       	testb  $0x1,0x70(%rsp)
 105d06d:	0f 84 21 2e 00 00    	je     105fe94 <my.vm::run+0x2fe4>
 105d073:	48 8b ab 80 00 00 00 	mov    0x80(%rbx),%rbp
 105d07a:	4c 8b 93 90 00 00 00 	mov    0x90(%rbx),%r10
 105d081:	4d 89 eb             	mov    %r13,%r11
 105d084:	49 89 d9             	mov    %rbx,%r9
 105d087:	e9 04 26 00 00       	jmp    105f690 <my.vm::run+0x27e0>
 105d08c:	49 8b b1 80 00 00 00 	mov    0x80(%r9),%rsi
 105d093:	48 89 f0             	mov    %rsi,%rax
 105d096:	48 ff c8             	dec    %rax
 105d099:	0f 80 6a 33 00 00    	jo     1060409 <my.vm::run+0x3559>
 105d09f:	48 89 44 24 38       	mov    %rax,0x38(%rsp)
 105d0a4:	48 89 c6             	mov    %rax,%rsi
 105d0a7:	48 ff ce             	dec    %rsi
 105d0aa:	0f 80 7b 32 00 00    	jo     106032b <my.vm::run+0x347b>
 105d0b0:	49 8b 69 78          	mov    0x78(%r9),%rbp
 105d0b4:	48 8b 55 08          	mov    0x8(%rbp),%rdx
 105d0b8:	48 39 d6             	cmp    %rdx,%rsi
 105d0bb:	0f 83 b6 28 00 00    	jae    105f977 <my.vm::run+0x2ac7>
 105d0c1:	48 89 f0             	mov    %rsi,%rax
 105d0c4:	48 c1 e0 04          	shl    $0x4,%rax
 105d0c8:	80 7c 05 20 03       	cmpb   $0x3,0x20(%rbp,%rax,1)
 105d0cd:	0f 85 54 1d 00 00    	jne    105ee27 <my.vm::run+0x1f77>
 105d0d3:	48 8b 5c 05 28       	mov    0x28(%rbp,%rax,1),%rbx
 105d0d8:	49 8b 09             	mov    (%r9),%rcx
 105d0db:	48 8b 41 08          	mov    0x8(%rcx),%rax
 105d0df:	48 89 de             	mov    %rbx,%rsi
 105d0e2:	48 39 c3             	cmp    %rax,%rbx
 105d0e5:	0f 83 80 2b 00 00    	jae    105fc6b <my.vm::run+0x2dbb>
 105d0eb:	48 6b c6 38          	imul   $0x38,%rsi,%rax
 105d0ef:	83 7c 01 20 06       	cmpl   $0x6,0x20(%rcx,%rax,1)
 105d0f4:	0f 85 2d 1d 00 00    	jne    105ee27 <my.vm::run+0x1f77>
 105d0fa:	48 8b 4c 24 38       	mov    0x38(%rsp),%rcx
 105d0ff:	48 89 c8             	mov    %rcx,%rax
 105d102:	48 39 d1             	cmp    %rdx,%rcx
 105d105:	0f 83 8e 2c 00 00    	jae    105fd99 <my.vm::run+0x2ee9>
 105d10b:	48 8d 55 20          	lea    0x20(%rbp),%rdx
 105d10f:	48 c1 e0 04          	shl    $0x4,%rax
 105d113:	0f b6 0c 02          	movzbl (%rdx,%rax,1),%ecx
 105d117:	83 f9 03             	cmp    $0x3,%ecx
 105d11a:	0f 85 fa 35 00 00    	jne    106071a <my.vm::run+0x386a>
 105d120:	48 01 c2             	add    %rax,%rdx
 105d123:	48 89 54 24 58       	mov    %rdx,0x58(%rsp)
 105d128:	48 8b 72 08          	mov    0x8(%rdx),%rsi
 105d12c:	4c 89 cf             	mov    %r9,%rdi
 105d12f:	4d 89 ce             	mov    %r9,%r14
 105d132:	e8 a9 e7 00 00       	call   106b8e0 <my.heap::class_obj>
 105d137:	49 89 d4             	mov    %rdx,%r12
 105d13a:	48 89 4c 24 18       	mov    %rcx,0x18(%rsp)
 105d13f:	be 20 00 00 00       	mov    $0x20,%esi
 105d144:	48 89 d7             	mov    %rdx,%rdi
 105d147:	e8 74 75 fc ff       	call   10246c0 <myl_core_list_copy>
 105d14c:	48 89 44 24 40       	mov    %rax,0x40(%rsp)
 105d151:	4c 89 e7             	mov    %r12,%rdi
 105d154:	e8 a7 76 fc ff       	call   1024800 <myl_core_drop_owned>
 105d159:	4c 89 f7             	mov    %r14,%rdi
 105d15c:	48 89 de             	mov    %rbx,%rsi
 105d15f:	e8 7c e7 00 00       	call   106b8e0 <my.heap::class_obj>
 105d164:	49 89 d4             	mov    %rdx,%r12
 105d167:	be 20 00 00 00       	mov    $0x20,%esi
 105d16c:	48 89 d7             	mov    %rdx,%rdi
 105d16f:	e8 4c 75 fc ff       	call   10246c0 <myl_core_list_copy>
 105d174:	48 89 c3             	mov    %rax,%rbx
 105d177:	4c 89 e7             	mov    %r12,%rdi
 105d17a:	e8 81 76 fc ff       	call   1024800 <myl_core_drop_owned>
 105d17f:	4c 8b 73 08          	mov    0x8(%rbx),%r14
 105d183:	4d 85 f6             	test   %r14,%r14
 105d186:	0f 84 26 22 00 00    	je     105f3b2 <my.vm::run+0x2502>
 105d18c:	4c 8d 63 38          	lea    0x38(%rbx),%r12
 105d190:	48 8b 4c 24 18       	mov    0x18(%rsp),%rcx
 105d195:	48 8b 7c 24 40       	mov    0x40(%rsp),%rdi
 105d19a:	eb 31                	jmp    105d1cd <my.vm::run+0x31d>
 105d19c:	66 66 66 66 66 66 2e 	data16 data16 data16 data16 data16 cs nopw 0x0(%rax,%rax,1)
 105d1a3:	0f 1f 84 00 00 00 00 
 105d1aa:	00 
 105d1ab:	66 66 66 66 66 66 2e 	data16 data16 data16 data16 data16 cs nopw 0x0(%rax,%rax,1)
 105d1b2:	0f 1f 84 00 00 00 00 
 105d1b9:	00 
 105d1ba:	66 0f 1f 44 00 00    	nopw   0x0(%rax,%rax,1)
 105d1c0:	49 83 c4 20          	add    $0x20,%r12
 105d1c4:	49 ff ce             	dec    %r14
 105d1c7:	0f 84 ef 21 00 00    	je     105f3bc <my.vm::run+0x250c>
 105d1cd:	49 8b 54 24 e8       	mov    -0x18(%r12),%rdx
 105d1d2:	48 83 fa ff          	cmp    $0xffffffffffffffff,%rdx
 105d1d6:	74 e8                	je     105d1c0 <my.vm::run+0x310>
 105d1d8:	4d 8b 0c 24          	mov    (%r12),%r9
 105d1dc:	41 8b 44 24 f0       	mov    -0x10(%r12),%eax
 105d1e1:	45 8b 44 24 f8       	mov    -0x8(%r12),%r8d
 105d1e6:	48 89 ce             	mov    %rcx,%rsi
 105d1e9:	89 c1                	mov    %eax,%ecx
 105d1eb:	e8 50 de 00 00       	call   106b040 <my.table::set>
 105d1f0:	48 89 d7             	mov    %rdx,%rdi
 105d1f3:	eb cb                	jmp    105d1c0 <my.vm::run+0x310>
 105d1f5:	48 8d 7c 24 70       	lea    0x70(%rsp),%rdi
 105d1fa:	4c 89 ce             	mov    %r9,%rsi
 105d1fd:	48 8b 54 24 10       	mov    0x10(%rsp),%rdx
 105d202:	4c 89 d9             	mov    %r11,%rcx
 105d205:	4d 89 f8             	mov    %r15,%r8
 105d208:	4d 89 ce             	mov    %r9,%r14
 105d20b:	4c 8b 4c 24 20       	mov    0x20(%rsp),%r9
 105d210:	e8 6b 70 00 00       	call   1064280 <my.vm::read_constant>
 105d215:	0f b6 44 24 70       	movzbl 0x70(%rsp),%eax
 105d21a:	83 f8 03             	cmp    $0x3,%eax
 105d21d:	0f 85 91 2e 00 00    	jne    10600b4 <my.vm::run+0x3204>
 105d223:	49 8b b6 80 00 00 00 	mov    0x80(%r14),%rsi
 105d22a:	48 89 f1             	mov    %rsi,%rcx
 105d22d:	48 ff c9             	dec    %rcx
 105d230:	0f 80 a3 30 00 00    	jo     10602d9 <my.vm::run+0x3429>
 105d236:	48 89 ce             	mov    %rcx,%rsi
 105d239:	48 ff ce             	dec    %rsi
 105d23c:	0f 80 54 34 00 00    	jo     1060696 <my.vm::run+0x37e6>
 105d242:	48 8b 84 24 98 00 00 	mov    0x98(%rsp),%rax
 105d249:	00 
 105d24a:	48 89 44 24 20       	mov    %rax,0x20(%rsp)
 105d24f:	4c 8b bc 24 90 00 00 	mov    0x90(%rsp),%r15
 105d256:	00 
 105d257:	4c 8b ac 24 88 00 00 	mov    0x88(%rsp),%r13
 105d25e:	00 
 105d25f:	48 8b 6c 24 78       	mov    0x78(%rsp),%rbp
 105d264:	48 8b 84 24 80 00 00 	mov    0x80(%rsp),%rax
 105d26b:	00 
 105d26c:	48 89 44 24 10       	mov    %rax,0x10(%rsp)
 105d271:	4d 8b 76 78          	mov    0x78(%r14),%r14
 105d275:	49 8b 56 08          	mov    0x8(%r14),%rdx
 105d279:	48 39 d6             	cmp    %rdx,%rsi
 105d27c:	0f 83 4d 28 00 00    	jae    105facf <my.vm::run+0x2c1f>
 105d282:	48 89 f0             	mov    %rsi,%rax
 105d285:	48 89 4c 24 38       	mov    %rcx,0x38(%rsp)
 105d28a:	4c 89 6c 24 18       	mov    %r13,0x18(%rsp)
 105d28f:	48 c1 e0 04          	shl    $0x4,%rax
 105d293:	41 0f b6 4c 06 20    	movzbl 0x20(%r14,%rax,1),%ecx
 105d299:	83 f9 03             	cmp    $0x3,%ecx
 105d29c:	0f 85 2f 2e 00 00    	jne    10600d1 <my.vm::run+0x3221>
 105d2a2:	4d 8d 2c 06          	lea    (%r14,%rax,1),%r13
 105d2a6:	49 83 c5 20          	add    $0x20,%r13
 105d2aa:	49 8b 75 08          	mov    0x8(%r13),%rsi
 105d2ae:	4c 8b 64 24 50       	mov    0x50(%rsp),%r12
 105d2b3:	4c 89 e7             	mov    %r12,%rdi
 105d2b6:	e8 25 e6 00 00       	call   106b8e0 <my.heap::class_obj>
 105d2bb:	48 89 d3             	mov    %rdx,%rbx
 105d2be:	48 89 4c 24 40       	mov    %rcx,0x40(%rsp)
 105d2c3:	be 20 00 00 00       	mov    $0x20,%esi
 105d2c8:	48 89 d7             	mov    %rdx,%rdi
 105d2cb:	e8 f0 73 fc ff       	call   10246c0 <myl_core_list_copy>
 105d2d0:	48 89 44 24 58       	mov    %rax,0x58(%rsp)
 105d2d5:	48 89 df             	mov    %rbx,%rdi
 105d2d8:	e8 23 75 fc ff       	call   1024800 <myl_core_drop_owned>
 105d2dd:	4c 89 e7             	mov    %r12,%rdi
 105d2e0:	48 89 ee             	mov    %rbp,%rsi
 105d2e3:	e8 78 dc 00 00       	call   106af60 <my.heap::string_hash>
 105d2e8:	49 8b 56 08          	mov    0x8(%r14),%rdx
 105d2ec:	48 8b 74 24 38       	mov    0x38(%rsp),%rsi
 105d2f1:	48 89 f1             	mov    %rsi,%rcx
 105d2f4:	48 39 d6             	cmp    %rdx,%rsi
 105d2f7:	0f 83 3e 28 00 00    	jae    105fb3b <my.vm::run+0x2c8b>
 105d2fd:	49 83 c6 20          	add    $0x20,%r14
 105d301:	48 c1 e1 04          	shl    $0x4,%rcx
 105d305:	4d 8b 4c 0e 08       	mov    0x8(%r14,%rcx,1),%r9
 105d30a:	45 8b 04 0e          	mov    (%r14,%rcx,1),%r8d
 105d30e:	48 8b 7c 24 58       	mov    0x58(%rsp),%rdi
 105d313:	48 8b 74 24 40       	mov    0x40(%rsp),%rsi
 105d318:	48 89 ea             	mov    %rbp,%rdx
 105d31b:	89 c1                	mov    %eax,%ecx
 105d31d:	e8 1e dd 00 00       	call   106b040 <my.table::set>
 105d322:	41 0f b6 45 00       	movzbl 0x0(%r13),%eax
 105d327:	83 f8 03             	cmp    $0x3,%eax
 105d32a:	0f 85 be 2d 00 00    	jne    10600ee <my.vm::run+0x323e>
 105d330:	48 89 d3             	mov    %rdx,%rbx
 105d333:	49 89 cc             	mov    %rcx,%r12
 105d336:	49 8b 6d 08          	mov    0x8(%r13),%rbp
 105d33a:	4c 8b 74 24 50       	mov    0x50(%rsp),%r14
 105d33f:	4c 89 f7             	mov    %r14,%rdi
 105d342:	48 89 ee             	mov    %rbp,%rsi
 105d345:	e8 96 e5 00 00       	call   106b8e0 <my.heap::class_obj>
 105d34a:	49 89 c5             	mov    %rax,%r13
 105d34d:	48 89 d7             	mov    %rdx,%rdi
 105d350:	e8 ab 74 fc ff       	call   1024800 <myl_core_drop_owned>
 105d355:	49 8b 0e             	mov    (%r14),%rcx
 105d358:	48 8b 51 08          	mov    0x8(%rcx),%rdx
 105d35c:	48 39 d5             	cmp    %rdx,%rbp
 105d35f:	0f 83 f6 27 00 00    	jae    105fb5b <my.vm::run+0x2cab>
 105d365:	48 89 e8             	mov    %rbp,%rax
 105d368:	4c 8b 5c 24 18       	mov    0x18(%rsp),%r11
 105d36d:	4c 6b c0 38          	imul   $0x38,%rax,%r8
 105d371:	42 0f b6 54 01 20    	movzbl 0x20(%rcx,%r8,1),%edx
 105d377:	4a 8b 74 01 28       	mov    0x28(%rcx,%r8,1),%rsi
 105d37c:	4a 8b 44 01 30       	mov    0x30(%rcx,%r8,1),%rax
 105d381:	4a 8b 7c 01 38       	mov    0x38(%rcx,%r8,1),%rdi
 105d386:	4a 8b 6c 01 40       	mov    0x40(%rcx,%r8,1),%rbp
 105d38b:	4e 8b 74 01 48       	mov    0x48(%rcx,%r8,1),%r14
 105d390:	4a c7 44 01 20 06 00 	movq   $0x6,0x20(%rcx,%r8,1)
 105d397:	00 00 
 105d399:	4e 89 6c 01 28       	mov    %r13,0x28(%rcx,%r8,1)
 105d39e:	4a 89 5c 01 30       	mov    %rbx,0x30(%rcx,%r8,1)
 105d3a3:	4e 89 64 01 38       	mov    %r12,0x38(%rcx,%r8,1)
 105d3a8:	83 fa 09             	cmp    $0x9,%edx
 105d3ab:	4c 8d 25 9e a0 fa ff 	lea    -0x55f62(%rip),%r12        # 1007450 <core_number_pairs+0x1f0>
 105d3b2:	77 1b                	ja     105d3cf <my.vm::run+0x51f>
 105d3b4:	b9 d0 02 00 00       	mov    $0x2d0,%ecx
 105d3b9:	0f a3 d1             	bt     %edx,%ecx
 105d3bc:	0f 83 5a 1d 00 00    	jae    105f11c <my.vm::run+0x226c>
 105d3c2:	48 89 c7             	mov    %rax,%rdi
 105d3c5:	e8 36 74 fc ff       	call   1024800 <myl_core_drop_owned>
 105d3ca:	4c 8b 5c 24 18       	mov    0x18(%rsp),%r11
 105d3cf:	4c 8b 4c 24 50       	mov    0x50(%rsp),%r9
 105d3d4:	48 8b 6c 24 38       	mov    0x38(%rsp),%rbp
 105d3d9:	e9 a3 1e 00 00       	jmp    105f281 <my.vm::run+0x23d1>
 105d3de:	48 8d bc 24 40 02 00 	lea    0x240(%rsp),%rdi
 105d3e5:	00 
 105d3e6:	4c 89 ce             	mov    %r9,%rsi
 105d3e9:	48 8b 54 24 10       	mov    0x10(%rsp),%rdx
 105d3ee:	4c 89 d9             	mov    %r11,%rcx
 105d3f1:	4d 89 f8             	mov    %r15,%r8
 105d3f4:	4d 89 cf             	mov    %r9,%r15
 105d3f7:	4c 8b 4c 24 20       	mov    0x20(%rsp),%r9
 105d3fc:	e8 cf 75 00 00       	call   10649d0 <my.vm::read_short>
 105d401:	48 89 dd             	mov    %rbx,%rbp
 105d404:	48 89 de             	mov    %rbx,%rsi
 105d407:	48 ff ce             	dec    %rsi
 105d40a:	0f 80 a5 2f 00 00    	jo     10603b5 <my.vm::run+0x3505>
 105d410:	48 8b 94 24 40 02 00 	mov    0x240(%rsp),%rdx
 105d417:	00 
 105d418:	48 8b 84 24 48 02 00 	mov    0x248(%rsp),%rax
 105d41f:	00 
 105d420:	48 89 44 24 10       	mov    %rax,0x10(%rsp)
 105d425:	4c 8b 9c 24 50 02 00 	mov    0x250(%rsp),%r11
 105d42c:	00 
 105d42d:	4c 8b 84 24 58 02 00 	mov    0x258(%rsp),%r8
 105d434:	00 
 105d435:	48 8b 84 24 60 02 00 	mov    0x260(%rsp),%rax
 105d43c:	00 
 105d43d:	48 89 44 24 20       	mov    %rax,0x20(%rsp)
 105d442:	49 8b 4f 78          	mov    0x78(%r15),%rcx
 105d446:	48 8b 41 08          	mov    0x8(%rcx),%rax
 105d44a:	48 39 c6             	cmp    %rax,%rsi
 105d44d:	4d 89 f9             	mov    %r15,%r9
 105d450:	0f 83 2e 24 00 00    	jae    105f884 <my.vm::run+0x29d4>
 105d456:	48 89 f7             	mov    %rsi,%rdi
 105d459:	4d 89 f2             	mov    %r14,%r10
 105d45c:	48 c1 e7 04          	shl    $0x4,%rdi
 105d460:	0f b6 44 39 20       	movzbl 0x20(%rcx,%rdi,1),%eax
 105d465:	85 c0                	test   %eax,%eax
 105d467:	4d 89 c7             	mov    %r8,%r15
 105d46a:	74 1b                	je     105d487 <my.vm::run+0x5d7>
 105d46c:	83 f8 01             	cmp    $0x1,%eax
 105d46f:	0f 85 1b 22 00 00    	jne    105f690 <my.vm::run+0x27e0>
 105d475:	48 8d 04 39          	lea    (%rcx,%rdi,1),%rax
 105d479:	48 83 c0 20          	add    $0x20,%rax
 105d47d:	f6 40 08 01          	testb  $0x1,0x8(%rax)
 105d481:	0f 85 09 22 00 00    	jne    105f690 <my.vm::run+0x27e0>
 105d487:	4c 89 f8             	mov    %r15,%rax
 105d48a:	48 01 d0             	add    %rdx,%rax
 105d48d:	0f 80 03 33 00 00    	jo     1060796 <my.vm::run+0x38e6>
 105d493:	49 89 c7             	mov    %rax,%r15
 105d496:	e9 f5 21 00 00       	jmp    105f690 <my.vm::run+0x27e0>
 105d49b:	48 8d bc 24 18 02 00 	lea    0x218(%rsp),%rdi
 105d4a2:	00 
 105d4a3:	4d 89 f8             	mov    %r15,%r8
 105d4a6:	4d 89 cf             	mov    %r9,%r15
 105d4a9:	4c 89 ce             	mov    %r9,%rsi
 105d4ac:	48 8b 54 24 10       	mov    0x10(%rsp),%rdx
 105d4b1:	4c 89 d9             	mov    %r11,%rcx
 105d4b4:	4c 8b 4c 24 20       	mov    0x20(%rsp),%r9
 105d4b9:	e8 12 75 00 00       	call   10649d0 <my.vm::read_short>
 105d4be:	48 8b 94 24 18 02 00 	mov    0x218(%rsp),%rdx
 105d4c5:	00 
 105d4c6:	48 8b b4 24 30 02 00 	mov    0x230(%rsp),%rsi
 105d4cd:	00 
 105d4ce:	48 89 f0             	mov    %rsi,%rax
 105d4d1:	48 29 d0             	sub    %rdx,%rax
 105d4d4:	0f 80 72 30 00 00    	jo     106054c <my.vm::run+0x369c>
 105d4da:	48 89 c1             	mov    %rax,%rcx
 105d4dd:	48 8b 84 24 20 02 00 	mov    0x220(%rsp),%rax
 105d4e4:	00 
 105d4e5:	48 89 44 24 10       	mov    %rax,0x10(%rsp)
 105d4ea:	4c 8b 9c 24 28 02 00 	mov    0x228(%rsp),%r11
 105d4f1:	00 
 105d4f2:	48 8b 84 24 38 02 00 	mov    0x238(%rsp),%rax
 105d4f9:	00 
 105d4fa:	e9 09 0a 00 00       	jmp    105df08 <my.vm::run+0x1058>
 105d4ff:	48 8d 7c 24 70       	lea    0x70(%rsp),%rdi
 105d504:	4d 89 ce             	mov    %r9,%r14
 105d507:	4c 89 ce             	mov    %r9,%rsi
 105d50a:	48 8b 54 24 10       	mov    0x10(%rsp),%rdx
 105d50f:	4c 89 d9             	mov    %r11,%rcx
 105d512:	4d 89 f8             	mov    %r15,%r8
 105d515:	4c 8b 4c 24 20       	mov    0x20(%rsp),%r9
 105d51a:	e8 61 6d 00 00       	call   1064280 <my.vm::read_constant>
 105d51f:	0f b6 44 24 70       	movzbl 0x70(%rsp),%eax
 105d524:	83 f8 03             	cmp    $0x3,%eax
 105d527:	0f 85 30 2b 00 00    	jne    106005d <my.vm::run+0x31ad>
 105d52d:	4c 8b ac 24 98 00 00 	mov    0x98(%rsp),%r13
 105d534:	00 
 105d535:	4c 8b bc 24 90 00 00 	mov    0x90(%rsp),%r15
 105d53c:	00 
 105d53d:	48 8b ac 24 88 00 00 	mov    0x88(%rsp),%rbp
 105d544:	00 
 105d545:	48 8b 5c 24 78       	mov    0x78(%rsp),%rbx
 105d54a:	48 8b 84 24 80 00 00 	mov    0x80(%rsp),%rax
 105d551:	00 
 105d552:	48 89 44 24 10       	mov    %rax,0x10(%rsp)
 105d557:	64 48 8b 04 25 c8 fe 	mov    %fs:0xfffffffffffffec8,%rax
 105d55e:	ff ff 
 105d560:	48 85 c0             	test   %rax,%rax
 105d563:	0f 84 b0 24 00 00    	je     105fa19 <my.vm::run+0x2b69>
 105d569:	48 8b 08             	mov    (%rax),%rcx
 105d56c:	64 48 89 0c 25 c8 fe 	mov    %rcx,%fs:0xfffffffffffffec8
 105d573:	ff ff 
 105d575:	c7 00 00 00 00 01    	movl   $0x1000000,(%rax)
 105d57b:	c5 f9 57 c0          	vxorpd %xmm0,%xmm0,%xmm0
 105d57f:	c5 f9 11 40 08       	vmovupd %xmm0,0x8(%rax)
 105d584:	48 c7 40 18 00 00 00 	movq   $0x0,0x18(%rax)
 105d58b:	00 
 105d58c:	48 c7 84 24 70 01 00 	movq   $0x6,0x170(%rsp)
 105d593:	00 06 00 00 00 
 105d598:	48 89 9c 24 78 01 00 	mov    %rbx,0x178(%rsp)
 105d59f:	00 
 105d5a0:	48 89 84 24 80 01 00 	mov    %rax,0x180(%rsp)
 105d5a7:	00 
 105d5a8:	48 c7 84 24 88 01 00 	movq   $0x0,0x188(%rsp)
 105d5af:	00 00 00 00 00 
 105d5b4:	48 8d bc 24 90 04 00 	lea    0x490(%rsp),%rdi
 105d5bb:	00 
 105d5bc:	48 8d 94 24 70 01 00 	lea    0x170(%rsp),%rdx
 105d5c3:	00 
 105d5c4:	4c 89 f6             	mov    %r14,%rsi
 105d5c7:	e8 94 dc ff ff       	call   105b260 <my.heap::allocate>
 105d5cc:	0f b6 84 24 70 01 00 	movzbl 0x170(%rsp),%eax
 105d5d3:	00 
 105d5d4:	ff c8                	dec    %eax
 105d5d6:	83 f8 08             	cmp    $0x8,%eax
 105d5d9:	77 1d                	ja     105d5f8 <my.vm::run+0x748>
 105d5db:	48 8d 0d 02 9f fa ff 	lea    -0x560fe(%rip),%rcx        # 10074e4 <core_number_pairs+0x284>
 105d5e2:	48 63 04 81          	movslq (%rcx,%rax,4),%rax
 105d5e6:	48 01 c8             	add    %rcx,%rax
 105d5e9:	ff e0                	jmp    *%rax
 105d5eb:	48 8b bc 24 80 01 00 	mov    0x180(%rsp),%rdi
 105d5f2:	00 
 105d5f3:	e8 08 72 fc ff       	call   1024800 <myl_core_drop_owned>
 105d5f8:	48 8b 84 24 90 04 00 	mov    0x490(%rsp),%rax
 105d5ff:	00 
 105d600:	4d 89 f1             	mov    %r14,%r9
 105d603:	49 8b 4e 78          	mov    0x78(%r14),%rcx
 105d607:	49 8b b6 80 00 00 00 	mov    0x80(%r14),%rsi
 105d60e:	48 8b 51 08          	mov    0x8(%rcx),%rdx
 105d612:	48 39 d6             	cmp    %rdx,%rsi
 105d615:	4c 89 6c 24 20       	mov    %r13,0x20(%rsp)
 105d61a:	0f 83 0a 24 00 00    	jae    105fa2a <my.vm::run+0x2b7a>
 105d620:	48 89 f7             	mov    %rsi,%rdi
 105d623:	49 89 eb             	mov    %rbp,%r11
 105d626:	48 c1 e7 04          	shl    $0x4,%rdi
 105d62a:	48 c7 44 39 20 03 00 	movq   $0x3,0x20(%rcx,%rdi,1)
 105d631:	00 00 
 105d633:	48 89 44 39 28       	mov    %rax,0x28(%rcx,%rdi,1)
 105d638:	49 89 49 78          	mov    %rcx,0x78(%r9)
 105d63c:	49 8b b1 80 00 00 00 	mov    0x80(%r9),%rsi
 105d643:	48 89 f5             	mov    %rsi,%rbp
 105d646:	48 ff c5             	inc    %rbp
 105d649:	0f 81 32 1c 00 00    	jno    105f281 <my.vm::run+0x23d1>
 105d64f:	e9 bf 2e 00 00       	jmp    1060513 <my.vm::run+0x3663>
 105d654:	48 8d 7c 24 70       	lea    0x70(%rsp),%rdi
 105d659:	4d 89 ce             	mov    %r9,%r14
 105d65c:	4c 89 ce             	mov    %r9,%rsi
 105d65f:	48 8b 54 24 10       	mov    0x10(%rsp),%rdx
 105d664:	4c 89 d9             	mov    %r11,%rcx
 105d667:	4d 89 f8             	mov    %r15,%r8
 105d66a:	4c 8b 4c 24 20       	mov    0x20(%rsp),%r9
 105d66f:	e8 0c 6c 00 00       	call   1064280 <my.vm::read_constant>
 105d674:	0f b6 44 24 70       	movzbl 0x70(%rsp),%eax
 105d679:	83 f8 03             	cmp    $0x3,%eax
 105d67c:	0f 85 89 2a 00 00    	jne    106010b <my.vm::run+0x325b>
 105d682:	48 89 de             	mov    %rbx,%rsi
 105d685:	48 ff ce             	dec    %rsi
 105d688:	0f 80 5a 2f 00 00    	jo     10605e8 <my.vm::run+0x3738>
 105d68e:	48 8b 9c 24 98 00 00 	mov    0x98(%rsp),%rbx
 105d695:	00 
 105d696:	4c 8b bc 24 90 00 00 	mov    0x90(%rsp),%r15
 105d69d:	00 
 105d69e:	4c 8b ac 24 88 00 00 	mov    0x88(%rsp),%r13
 105d6a5:	00 
 105d6a6:	4c 8b 44 24 78       	mov    0x78(%rsp),%r8
 105d6ab:	48 8b 84 24 80 00 00 	mov    0x80(%rsp),%rax
 105d6b2:	00 
 105d6b3:	48 89 44 24 10       	mov    %rax,0x10(%rsp)
 105d6b8:	4d 89 f1             	mov    %r14,%r9
 105d6bb:	49 89 b6 80 00 00 00 	mov    %rsi,0x80(%r14)
 105d6c2:	49 8b 46 78          	mov    0x78(%r14),%rax
 105d6c6:	48 8b 50 08          	mov    0x8(%rax),%rdx
 105d6ca:	48 39 d6             	cmp    %rdx,%rsi
 105d6cd:	0f 83 c6 23 00 00    	jae    105fa99 <my.vm::run+0x2be9>
 105d6d3:	48 89 f1             	mov    %rsi,%rcx
 105d6d6:	48 c1 e1 04          	shl    $0x4,%rcx
 105d6da:	0f b6 54 08 20       	movzbl 0x20(%rax,%rcx,1),%edx
 105d6df:	83 fa 03             	cmp    $0x3,%edx
 105d6e2:	0f 85 1e 29 00 00    	jne    1060006 <my.vm::run+0x3156>
 105d6e8:	48 01 c8             	add    %rcx,%rax
 105d6eb:	48 83 c0 20          	add    $0x20,%rax
 105d6ef:	48 8b 48 08          	mov    0x8(%rax),%rcx
 105d6f3:	48 8d bc 24 38 07 00 	lea    0x738(%rsp),%rdi
 105d6fa:	00 
 105d6fb:	4c 89 ce             	mov    %r9,%rsi
 105d6fe:	48 8b 54 24 48       	mov    0x48(%rsp),%rdx
 105d703:	4d 89 ce             	mov    %r9,%r14
 105d706:	e8 15 6d 00 00       	call   1064420 <my.vm::bind_method>
 105d70b:	f6 84 24 38 07 00 00 	testb  $0x1,0x738(%rsp)
 105d712:	01 
 105d713:	0f 84 7b 27 00 00    	je     105fe94 <my.vm::run+0x2fe4>
 105d719:	48 89 5c 24 20       	mov    %rbx,0x20(%rsp)
 105d71e:	49 8b ae 80 00 00 00 	mov    0x80(%r14),%rbp
 105d725:	4d 8b 96 90 00 00 00 	mov    0x90(%r14),%r10
 105d72c:	4d 89 eb             	mov    %r13,%r11
 105d72f:	4d 89 f1             	mov    %r14,%r9
 105d732:	e9 59 1f 00 00       	jmp    105f690 <my.vm::run+0x27e0>
 105d737:	48 89 de             	mov    %rbx,%rsi
 105d73a:	48 ff ce             	dec    %rsi
 105d73d:	0f 80 46 2c 00 00    	jo     1060389 <my.vm::run+0x34d9>
 105d743:	49 89 b1 80 00 00 00 	mov    %rsi,0x80(%r9)
 105d74a:	49 8b 41 78          	mov    0x78(%r9),%rax
 105d74e:	48 8b 50 08          	mov    0x8(%rax),%rdx
 105d752:	48 39 d6             	cmp    %rdx,%rsi
 105d755:	0f 83 47 21 00 00    	jae    105f8a2 <my.vm::run+0x29f2>
 105d75b:	48 89 f1             	mov    %rsi,%rcx
 105d75e:	48 8b 6c 24 20       	mov    0x20(%rsp),%rbp
 105d763:	48 c1 e1 04          	shl    $0x4,%rcx
 105d767:	c5 f9 10 44 08 20    	vmovupd 0x20(%rax,%rcx,1),%xmm0
 105d76d:	c5 f9 29 44 24 20    	vmovapd %xmm0,0x20(%rsp)
 105d773:	4c 89 cf             	mov    %r9,%rdi
 105d776:	48 89 ee             	mov    %rbp,%rsi
 105d779:	4c 89 cb             	mov    %r9,%rbx
 105d77c:	e8 6f 7a 00 00       	call   10651f0 <my.vm::close_upvalues>
 105d781:	48 8b b3 90 00 00 00 	mov    0x90(%rbx),%rsi
 105d788:	49 89 f2             	mov    %rsi,%r10
 105d78b:	49 ff ca             	dec    %r10
 105d78e:	0f 80 86 2b 00 00    	jo     106031a <my.vm::run+0x346a>
 105d794:	49 89 d9             	mov    %rbx,%r9
 105d797:	4c 89 93 90 00 00 00 	mov    %r10,0x90(%rbx)
 105d79e:	0f 84 12 27 00 00    	je     105feb6 <my.vm::run+0x3006>
 105d7a4:	49 89 a9 80 00 00 00 	mov    %rbp,0x80(%r9)
 105d7ab:	49 8b 41 78          	mov    0x78(%r9),%rax
 105d7af:	48 8b 50 08          	mov    0x8(%rax),%rdx
 105d7b3:	48 89 e9             	mov    %rbp,%rcx
 105d7b6:	48 39 d5             	cmp    %rdx,%rbp
 105d7b9:	0f 83 f2 23 00 00    	jae    105fbb1 <my.vm::run+0x2d01>
 105d7bf:	48 c1 e1 04          	shl    $0x4,%rcx
 105d7c3:	c5 f9 28 44 24 20    	vmovapd 0x20(%rsp),%xmm0
 105d7c9:	c5 f9 54 05 0f 6c fa 	vandpd -0x593f1(%rip),%xmm0,%xmm0        # 10043e0 <__anon_2214+0xb0>
 105d7d0:	ff 
 105d7d1:	c5 f9 11 44 08 20    	vmovupd %xmm0,0x20(%rax,%rcx,1)
 105d7d7:	49 89 41 78          	mov    %rax,0x78(%r9)
 105d7db:	48 ff c5             	inc    %rbp
 105d7de:	49 89 a9 80 00 00 00 	mov    %rbp,0x80(%r9)
 105d7e5:	4c 89 d6             	mov    %r10,%rsi
 105d7e8:	48 ff ce             	dec    %rsi
 105d7eb:	0f 80 cd 2e 00 00    	jo     10606be <my.vm::run+0x380e>
 105d7f1:	49 8b 81 88 00 00 00 	mov    0x88(%r9),%rax
 105d7f8:	48 8b 50 08          	mov    0x8(%rax),%rdx
 105d7fc:	48 39 d6             	cmp    %rdx,%rsi
 105d7ff:	0f 82 8b 16 00 00    	jb     105ee90 <my.vm::run+0x1fe0>
 105d805:	48 89 f1             	mov    %rsi,%rcx
 105d808:	48 c1 f9 3f          	sar    $0x3f,%rcx
 105d80c:	48 21 d1             	and    %rdx,%rcx
 105d80f:	48 01 f1             	add    %rsi,%rcx
 105d812:	48 39 d1             	cmp    %rdx,%rcx
 105d815:	0f 82 78 16 00 00    	jb     105ee93 <my.vm::run+0x1fe3>
 105d81b:	e9 7a 32 00 00       	jmp    1060a9a <my.vm::run+0x3bea>
 105d820:	4c 89 cf             	mov    %r9,%rdi
 105d823:	4c 89 de             	mov    %r11,%rsi
 105d826:	4c 89 fa             	mov    %r15,%rdx
 105d829:	4d 89 ce             	mov    %r9,%r14
 105d82c:	e8 ff d4 00 00       	call   106ad30 <my.heap::function_instruction>
 105d831:	4d 89 fc             	mov    %r15,%r12
 105d834:	49 ff c4             	inc    %r12
 105d837:	0f 80 e4 2d 00 00    	jo     1060621 <my.vm::run+0x3771>
 105d83d:	4c 89 f7             	mov    %r14,%rdi
 105d840:	48 8b 74 24 10       	mov    0x10(%rsp),%rsi
 105d845:	48 89 c2             	mov    %rax,%rdx
 105d848:	e8 e3 da 00 00       	call   106b330 <my.heap::closure_upvalue>
 105d84d:	48 89 c3             	mov    %rax,%rbx
 105d850:	48 8d bc 24 f0 03 00 	lea    0x3f0(%rsp),%rdi
 105d857:	00 
 105d858:	4c 89 f6             	mov    %r14,%rsi
 105d85b:	48 89 c2             	mov    %rax,%rdx
 105d85e:	e8 cd d9 00 00       	call   106b230 <my.heap::upvalue_obj>
 105d863:	48 8b 84 24 f0 03 00 	mov    0x3f0(%rsp),%rax
 105d86a:	00 
 105d86b:	49 8b 7e 78          	mov    0x78(%r14),%rdi
 105d86f:	49 8b 8e 80 00 00 00 	mov    0x80(%r14),%rcx
 105d876:	48 89 ce             	mov    %rcx,%rsi
 105d879:	48 ff ce             	dec    %rsi
 105d87c:	0f 90 c2             	seto   %dl
 105d87f:	48 83 f8 ff          	cmp    $0xffffffffffffffff,%rax
 105d883:	4d 89 f1             	mov    %r14,%r9
 105d886:	0f 84 e6 16 00 00    	je     105ef72 <my.vm::run+0x20c2>
 105d88c:	84 d2                	test   %dl,%dl
 105d88e:	0f 85 dd 2e 00 00    	jne    1060771 <my.vm::run+0x38c1>
 105d894:	4d 89 eb             	mov    %r13,%r11
 105d897:	48 8b 57 08          	mov    0x8(%rdi),%rdx
 105d89b:	48 39 d6             	cmp    %rdx,%rsi
 105d89e:	0f 83 76 23 00 00    	jae    105fc1a <my.vm::run+0x2d6a>
 105d8a4:	48 89 f1             	mov    %rsi,%rcx
 105d8a7:	48 c1 e1 04          	shl    $0x4,%rcx
 105d8ab:	c5 f9 10 44 0f 20    	vmovupd 0x20(%rdi,%rcx,1),%xmm0
 105d8b1:	48 39 d0             	cmp    %rdx,%rax
 105d8b4:	0f 83 7b 23 00 00    	jae    105fc35 <my.vm::run+0x2d85>
 105d8ba:	48 89 c1             	mov    %rax,%rcx
 105d8bd:	48 83 c7 20          	add    $0x20,%rdi
 105d8c1:	48 c1 e1 04          	shl    $0x4,%rcx
 105d8c5:	c5 f9 54 05 13 6b fa 	vandpd -0x594ed(%rip),%xmm0,%xmm0        # 10043e0 <__anon_2214+0xb0>
 105d8cc:	ff 
 105d8cd:	c5 f9 11 04 0f       	vmovupd %xmm0,(%rdi,%rcx,1)
 105d8d2:	49 8b a9 80 00 00 00 	mov    0x80(%r9),%rbp
 105d8d9:	e9 a7 17 00 00       	jmp    105f085 <my.vm::run+0x21d5>
 105d8de:	48 89 dd             	mov    %rbx,%rbp
 105d8e1:	48 ff cd             	dec    %rbp
 105d8e4:	0f 80 6e 2c 00 00    	jo     1060558 <my.vm::run+0x36a8>
 105d8ea:	49 89 a9 80 00 00 00 	mov    %rbp,0x80(%r9)
 105d8f1:	49 8b 41 78          	mov    0x78(%r9),%rax
 105d8f5:	48 8b 50 08          	mov    0x8(%rax),%rdx
 105d8f9:	48 39 d5             	cmp    %rdx,%rbp
 105d8fc:	0f 82 8e 1d 00 00    	jb     105f690 <my.vm::run+0x27e0>
 105d902:	48 89 e8             	mov    %rbp,%rax
 105d905:	48 c1 f8 3f          	sar    $0x3f,%rax
 105d909:	48 21 d0             	and    %rdx,%rax
 105d90c:	48 01 e8             	add    %rbp,%rax
 105d90f:	48 39 d0             	cmp    %rdx,%rax
 105d912:	0f 82 78 1d 00 00    	jb     105f690 <my.vm::run+0x27e0>
 105d918:	e9 50 31 00 00       	jmp    1060a6d <my.vm::run+0x3bbd>
 105d91d:	49 8b b1 80 00 00 00 	mov    0x80(%r9),%rsi
 105d924:	48 89 f0             	mov    %rsi,%rax
 105d927:	48 ff c8             	dec    %rax
 105d92a:	0f 80 34 2b 00 00    	jo     1060464 <my.vm::run+0x35b4>
 105d930:	49 8b 69 78          	mov    0x78(%r9),%rbp
 105d934:	48 8b 55 08          	mov    0x8(%rbp),%rdx
 105d938:	49 89 c4             	mov    %rax,%r12
 105d93b:	48 89 44 24 38       	mov    %rax,0x38(%rsp)
 105d940:	48 39 d0             	cmp    %rdx,%rax
 105d943:	0f 83 79 1f 00 00    	jae    105f8c2 <my.vm::run+0x2a12>
 105d949:	49 c1 e4 04          	shl    $0x4,%r12
 105d94d:	42 80 7c 25 20 03    	cmpb   $0x3,0x20(%rbp,%r12,1)
 105d953:	0f 85 79 14 00 00    	jne    105edd2 <my.vm::run+0x1f22>
 105d959:	4a 8b 74 25 28       	mov    0x28(%rbp,%r12,1),%rsi
 105d95e:	49 8b 01             	mov    (%r9),%rax
 105d961:	48 8b 50 08          	mov    0x8(%rax),%rdx
 105d965:	48 89 f1             	mov    %rsi,%rcx
 105d968:	48 39 d6             	cmp    %rdx,%rsi
 105d96b:	0f 83 df 22 00 00    	jae    105fc50 <my.vm::run+0x2da0>
 105d971:	48 6b c9 38          	imul   $0x38,%rcx,%rcx
 105d975:	83 7c 08 20 07       	cmpl   $0x7,0x20(%rax,%rcx,1)
 105d97a:	0f 85 52 14 00 00    	jne    105edd2 <my.vm::run+0x1f22>
 105d980:	48 89 74 24 18       	mov    %rsi,0x18(%rsp)
 105d985:	48 8d bc 24 e0 01 00 	lea    0x1e0(%rsp),%rdi
 105d98c:	00 
 105d98d:	4c 89 ce             	mov    %r9,%rsi
 105d990:	48 8b 54 24 10       	mov    0x10(%rsp),%rdx
 105d995:	4c 89 d9             	mov    %r11,%rcx
 105d998:	4d 89 f8             	mov    %r15,%r8
 105d99b:	4d 89 ce             	mov    %r9,%r14
 105d99e:	4c 8b 4c 24 20       	mov    0x20(%rsp),%r9
 105d9a3:	e8 d8 68 00 00       	call   1064280 <my.vm::read_constant>
 105d9a8:	0f b6 84 24 e0 01 00 	movzbl 0x1e0(%rsp),%eax
 105d9af:	00 
 105d9b0:	83 f8 03             	cmp    $0x3,%eax
 105d9b3:	0f 85 9b 2d 00 00    	jne    1060754 <my.vm::run+0x38a4>
 105d9b9:	48 8b 84 24 08 02 00 	mov    0x208(%rsp),%rax
 105d9c0:	00 
 105d9c1:	48 89 44 24 20       	mov    %rax,0x20(%rsp)
 105d9c6:	4c 8b bc 24 00 02 00 	mov    0x200(%rsp),%r15
 105d9cd:	00 
 105d9ce:	4c 8b ac 24 f8 01 00 	mov    0x1f8(%rsp),%r13
 105d9d5:	00 
 105d9d6:	48 8b 9c 24 e8 01 00 	mov    0x1e8(%rsp),%rbx
 105d9dd:	00 
 105d9de:	48 8b 84 24 f0 01 00 	mov    0x1f0(%rsp),%rax
 105d9e5:	00 
 105d9e6:	48 89 44 24 10       	mov    %rax,0x10(%rsp)
 105d9eb:	4c 89 f7             	mov    %r14,%rdi
 105d9ee:	48 89 de             	mov    %rbx,%rsi
 105d9f1:	e8 6a d5 00 00       	call   106af60 <my.heap::string_hash>
 105d9f6:	4c 89 f7             	mov    %r14,%rdi
 105d9f9:	48 8b 74 24 18       	mov    0x18(%rsp),%rsi
 105d9fe:	48 89 5c 24 58       	mov    %rbx,0x58(%rsp)
 105da03:	48 89 da             	mov    %rbx,%rdx
 105da06:	89 c1                	mov    %eax,%ecx
 105da08:	e8 33 da 00 00       	call   106b440 <my.heap::instance_field>
 105da0d:	3c 01                	cmp    $0x1,%al
 105da0f:	0f 85 2b 19 00 00    	jne    105f340 <my.vm::run+0x2490>
 105da15:	49 8d 04 2c          	lea    (%r12,%rbp,1),%rax
 105da19:	48 83 c0 20          	add    $0x20,%rax
 105da1d:	0f b6 d2             	movzbl %dl,%edx
 105da20:	48 89 10             	mov    %rdx,(%rax)
 105da23:	48 89 48 08          	mov    %rcx,0x8(%rax)
 105da27:	48 8b 6c 24 38       	mov    0x38(%rsp),%rbp
 105da2c:	48 ff c5             	inc    %rbp
 105da2f:	49 89 ae 80 00 00 00 	mov    %rbp,0x80(%r14)
 105da36:	4d 8b 96 90 00 00 00 	mov    0x90(%r14),%r10
 105da3d:	4c 8d 25 0c 9a fa ff 	lea    -0x565f4(%rip),%r12        # 1007450 <core_number_pairs+0x1f0>
 105da44:	e9 e3 fc ff ff       	jmp    105d72c <my.vm::run+0x87c>
 105da49:	48 8d bc 24 00 03 00 	lea    0x300(%rsp),%rdi
 105da50:	00 
 105da51:	4c 89 ce             	mov    %r9,%rsi
 105da54:	48 8b 54 24 10       	mov    0x10(%rsp),%rdx
 105da59:	4c 89 d9             	mov    %r11,%rcx
 105da5c:	4d 89 f8             	mov    %r15,%r8
 105da5f:	4c 89 cb             	mov    %r9,%rbx
 105da62:	4c 8b 4c 24 20       	mov    0x20(%rsp),%r9
 105da67:	e8 14 68 00 00       	call   1064280 <my.vm::read_constant>
 105da6c:	0f b6 84 24 00 03 00 	movzbl 0x300(%rsp),%eax
 105da73:	00 
 105da74:	83 f8 03             	cmp    $0x3,%eax
 105da77:	0f 85 c3 25 00 00    	jne    1060040 <my.vm::run+0x3190>
 105da7d:	48 8b 83 80 00 00 00 	mov    0x80(%rbx),%rax
 105da84:	48 89 c6             	mov    %rax,%rsi
 105da87:	48 ff ce             	dec    %rsi
 105da8a:	0f 80 94 2a 00 00    	jo     1060524 <my.vm::run+0x3674>
 105da90:	48 89 df             	mov    %rbx,%rdi
 105da93:	48 8b 8c 24 28 03 00 	mov    0x328(%rsp),%rcx
 105da9a:	00 
 105da9b:	4c 8b bc 24 20 03 00 	mov    0x320(%rsp),%r15
 105daa2:	00 
 105daa3:	4c 8b 84 24 18 03 00 	mov    0x318(%rsp),%r8
 105daaa:	00 
 105daab:	48 8b 9c 24 08 03 00 	mov    0x308(%rsp),%rbx
 105dab2:	00 
 105dab3:	48 8b 84 24 10 03 00 	mov    0x310(%rsp),%rax
 105daba:	00 
 105dabb:	48 89 44 24 10       	mov    %rax,0x10(%rsp)
 105dac0:	48 8b 47 78          	mov    0x78(%rdi),%rax
 105dac4:	48 8b 50 08          	mov    0x8(%rax),%rdx
 105dac8:	48 39 d6             	cmp    %rdx,%rsi
 105dacb:	48 89 4c 24 20       	mov    %rcx,0x20(%rsp)
 105dad0:	4c 89 44 24 18       	mov    %r8,0x18(%rsp)
 105dad5:	0f 83 d9 1f 00 00    	jae    105fab4 <my.vm::run+0x2c04>
 105dadb:	48 89 f1             	mov    %rsi,%rcx
 105dade:	48 c1 e1 04          	shl    $0x4,%rcx
 105dae2:	4c 8b 64 08 28       	mov    0x28(%rax,%rcx,1),%r12
 105dae7:	8b 6c 08 20          	mov    0x20(%rax,%rcx,1),%ebp
 105daeb:	48 89 de             	mov    %rbx,%rsi
 105daee:	49 89 fe             	mov    %rdi,%r14
 105daf1:	e8 6a d4 00 00       	call   106af60 <my.heap::string_hash>
 105daf6:	49 8b 7e 30          	mov    0x30(%r14),%rdi
 105dafa:	49 8b 76 38          	mov    0x38(%r14),%rsi
 105dafe:	48 89 da             	mov    %rbx,%rdx
 105db01:	89 c1                	mov    %eax,%ecx
 105db03:	41 89 e8             	mov    %ebp,%r8d
 105db06:	4d 89 e1             	mov    %r12,%r9
 105db09:	e8 32 d5 00 00       	call   106b040 <my.table::set>
 105db0e:	4d 89 f1             	mov    %r14,%r9
 105db11:	49 89 56 30          	mov    %rdx,0x30(%r14)
 105db15:	49 89 4e 38          	mov    %rcx,0x38(%r14)
 105db19:	a8 01                	test   $0x1,%al
 105db1b:	0f 84 32 14 00 00    	je     105ef53 <my.vm::run+0x20a3>
 105db21:	49 89 d4             	mov    %rdx,%r12
 105db24:	49 89 cd             	mov    %rcx,%r13
 105db27:	4c 89 cf             	mov    %r9,%rdi
 105db2a:	48 89 de             	mov    %rbx,%rsi
 105db2d:	4d 89 ce             	mov    %r9,%r14
 105db30:	e8 2b d4 00 00       	call   106af60 <my.heap::string_hash>
 105db35:	4c 89 e7             	mov    %r12,%rdi
 105db38:	4c 89 ee             	mov    %r13,%rsi
 105db3b:	48 89 da             	mov    %rbx,%rdx
 105db3e:	89 c1                	mov    %eax,%ecx
 105db40:	e8 0b cf 00 00       	call   106aa50 <my.table::delete>
 105db45:	49 89 46 30          	mov    %rax,0x30(%r14)
 105db49:	49 89 56 38          	mov    %rdx,0x38(%r14)
 105db4d:	4c 89 f7             	mov    %r14,%rdi
 105db50:	48 89 de             	mov    %rbx,%rsi
 105db53:	e8 f8 d0 00 00       	call   106ac50 <my.heap::string_chars>
 105db58:	48 89 c3             	mov    %rax,%rbx
 105db5b:	48 8d 3d 9e 54 fb ff 	lea    -0x4ab62(%rip),%rdi        # 1013000 <core_number_pairs+0xbda0>
 105db62:	48 89 c6             	mov    %rax,%rsi
 105db65:	e8 96 20 fd ff       	call   102fc00 <myl_core_bytes_concat>
 105db6a:	49 89 c4             	mov    %rax,%r12
 105db6d:	48 89 df             	mov    %rbx,%rdi
 105db70:	e8 8b 6c fc ff       	call   1024800 <myl_core_drop_owned>
 105db75:	48 8d 35 c4 54 fb ff 	lea    -0x4ab3c(%rip),%rsi        # 1013040 <core_number_pairs+0xbde0>
 105db7c:	4c 89 e7             	mov    %r12,%rdi
 105db7f:	e8 7c 20 fd ff       	call   102fc00 <myl_core_bytes_concat>
 105db84:	48 89 c3             	mov    %rax,%rbx
 105db87:	4c 89 e7             	mov    %r12,%rdi
 105db8a:	e8 71 6c fc ff       	call   1024800 <myl_core_drop_owned>
 105db8f:	48 8d 7c 24 70       	lea    0x70(%rsp),%rdi
 105db94:	4c 89 f6             	mov    %r14,%rsi
 105db97:	48 8b 54 24 48       	mov    0x48(%rsp),%rdx
 105db9c:	48 89 d9             	mov    %rbx,%rcx
 105db9f:	e8 fc 61 00 00       	call   1063da0 <my.vm::runtime_error>
 105dba4:	48 89 df             	mov    %rbx,%rdi
 105dba7:	e8 54 6c fc ff       	call   1024800 <myl_core_drop_owned>
 105dbac:	f6 44 24 70 01       	testb  $0x1,0x70(%rsp)
 105dbb1:	0f 84 dd 22 00 00    	je     105fe94 <my.vm::run+0x2fe4>
 105dbb7:	49 8b ae 80 00 00 00 	mov    0x80(%r14),%rbp
 105dbbe:	4d 8b 96 90 00 00 00 	mov    0x90(%r14),%r10
 105dbc5:	4c 8d 25 84 98 fa ff 	lea    -0x5677c(%rip),%r12        # 1007450 <core_number_pairs+0x1f0>
 105dbcc:	4c 8b 5c 24 18       	mov    0x18(%rsp),%r11
 105dbd1:	4d 89 f1             	mov    %r14,%r9
 105dbd4:	e9 b7 1a 00 00       	jmp    105f690 <my.vm::run+0x27e0>
 105dbd9:	49 8b 41 78          	mov    0x78(%r9),%rax
 105dbdd:	48 8b 50 08          	mov    0x8(%rax),%rdx
 105dbe1:	48 89 d9             	mov    %rbx,%rcx
 105dbe4:	48 39 d3             	cmp    %rdx,%rbx
 105dbe7:	0f 83 2b 1c 00 00    	jae    105f818 <my.vm::run+0x2968>
 105dbed:	48 c1 e1 04          	shl    $0x4,%rcx
 105dbf1:	48 c7 44 08 20 01 00 	movq   $0x1,0x20(%rax,%rcx,1)
 105dbf8:	00 00 
 105dbfa:	c6 44 08 28 01       	movb   $0x1,0x28(%rax,%rcx,1)
 105dbff:	49 89 41 78          	mov    %rax,0x78(%r9)
 105dc03:	48 89 dd             	mov    %rbx,%rbp
 105dc06:	48 ff c5             	inc    %rbp
 105dc09:	0f 81 8e 02 00 00    	jno    105de9d <my.vm::run+0xfed>
 105dc0f:	e9 cd 27 00 00       	jmp    10603e1 <my.vm::run+0x3531>
 105dc14:	48 89 de             	mov    %rbx,%rsi
 105dc17:	48 ff ce             	dec    %rsi
 105dc1a:	0f 80 18 29 00 00    	jo     1060538 <my.vm::run+0x3688>
 105dc20:	49 89 b1 80 00 00 00 	mov    %rsi,0x80(%r9)
 105dc27:	49 8b 41 78          	mov    0x78(%r9),%rax
 105dc2b:	48 8b 50 08          	mov    0x8(%rax),%rdx
 105dc2f:	48 89 f1             	mov    %rsi,%rcx
 105dc32:	48 39 d6             	cmp    %rdx,%rsi
 105dc35:	0f 83 a7 1c 00 00    	jae    105f8e2 <my.vm::run+0x2a32>
 105dc3b:	48 89 f5             	mov    %rsi,%rbp
 105dc3e:	48 ff cd             	dec    %rbp
 105dc41:	0f 80 d3 27 00 00    	jo     106041a <my.vm::run+0x356a>
 105dc47:	48 c1 e1 04          	shl    $0x4,%rcx
 105dc4b:	44 0f b6 44 08 20    	movzbl 0x20(%rax,%rcx,1),%r8d
 105dc51:	48 8b 7c 08 28       	mov    0x28(%rax,%rcx,1),%rdi
 105dc56:	4c 89 cb             	mov    %r9,%rbx
 105dc59:	49 89 a9 80 00 00 00 	mov    %rbp,0x80(%r9)
 105dc60:	48 89 e9             	mov    %rbp,%rcx
 105dc63:	48 39 d5             	cmp    %rdx,%rbp
 105dc66:	0f 83 26 1d 00 00    	jae    105f992 <my.vm::run+0x2ae2>
 105dc6c:	48 8d 50 20          	lea    0x20(%rax),%rdx
 105dc70:	48 c1 e1 04          	shl    $0x4,%rcx
 105dc74:	44 0f b6 0c 0a       	movzbl (%rdx,%rcx,1),%r9d
 105dc79:	48 8b 74 0a 08       	mov    0x8(%rdx,%rcx,1),%rsi
 105dc7e:	41 83 f9 02          	cmp    $0x2,%r9d
 105dc82:	0f 84 8c 15 00 00    	je     105f214 <my.vm::run+0x2364>
 105dc88:	41 83 f9 01          	cmp    $0x1,%r9d
 105dc8c:	0f 84 6a 15 00 00    	je     105f1fc <my.vm::run+0x234c>
 105dc92:	45 85 c9             	test   %r9d,%r9d
 105dc95:	0f 85 9f 15 00 00    	jne    105f23a <my.vm::run+0x238a>
 105dc9b:	45 84 c0             	test   %r8b,%r8b
 105dc9e:	40 0f 94 c6          	sete   %sil
 105dca2:	e9 71 16 00 00       	jmp    105f318 <my.vm::run+0x2468>
 105dca7:	49 8b 41 78          	mov    0x78(%r9),%rax
 105dcab:	48 8b 50 08          	mov    0x8(%rax),%rdx
 105dcaf:	48 89 d9             	mov    %rbx,%rcx
 105dcb2:	48 39 d3             	cmp    %rdx,%rbx
 105dcb5:	0f 83 78 1b 00 00    	jae    105f833 <my.vm::run+0x2983>
 105dcbb:	48 c1 e1 04          	shl    $0x4,%rcx
 105dcbf:	48 c7 44 08 20 01 00 	movq   $0x1,0x20(%rax,%rcx,1)
 105dcc6:	00 00 
 105dcc8:	c6 44 08 28 00       	movb   $0x0,0x28(%rax,%rcx,1)
 105dccd:	49 89 41 78          	mov    %rax,0x78(%r9)
 105dcd1:	48 89 dd             	mov    %rbx,%rbp
 105dcd4:	48 ff c5             	inc    %rbp
 105dcd7:	0f 81 c0 01 00 00    	jno    105de9d <my.vm::run+0xfed>
 105dcdd:	e9 cd 28 00 00       	jmp    10605af <my.vm::run+0x36ff>
 105dce2:	48 8d bc 24 00 03 00 	lea    0x300(%rsp),%rdi
 105dce9:	00 
 105dcea:	4c 89 ce             	mov    %r9,%rsi
 105dced:	48 8b 54 24 10       	mov    0x10(%rsp),%rdx
 105dcf2:	4c 89 d9             	mov    %r11,%rcx
 105dcf5:	4d 89 f8             	mov    %r15,%r8
 105dcf8:	4d 89 ce             	mov    %r9,%r14
 105dcfb:	4c 8b 4c 24 20       	mov    0x20(%rsp),%r9
 105dd00:	e8 7b 65 00 00       	call   1064280 <my.vm::read_constant>
 105dd05:	0f b6 84 24 00 03 00 	movzbl 0x300(%rsp),%eax
 105dd0c:	00 
 105dd0d:	83 f8 03             	cmp    $0x3,%eax
 105dd10:	0f 85 0d 23 00 00    	jne    1060023 <my.vm::run+0x3173>
 105dd16:	48 8b 84 24 28 03 00 	mov    0x328(%rsp),%rax
 105dd1d:	00 
 105dd1e:	48 89 44 24 20       	mov    %rax,0x20(%rsp)
 105dd23:	4c 8b bc 24 20 03 00 	mov    0x320(%rsp),%r15
 105dd2a:	00 
 105dd2b:	48 8b ac 24 18 03 00 	mov    0x318(%rsp),%rbp
 105dd32:	00 
 105dd33:	48 8b 9c 24 08 03 00 	mov    0x308(%rsp),%rbx
 105dd3a:	00 
 105dd3b:	48 8b 84 24 10 03 00 	mov    0x310(%rsp),%rax
 105dd42:	00 
 105dd43:	48 89 44 24 10       	mov    %rax,0x10(%rsp)
 105dd48:	4d 8b 66 30          	mov    0x30(%r14),%r12
 105dd4c:	4d 8b 6e 38          	mov    0x38(%r14),%r13
 105dd50:	4c 89 f7             	mov    %r14,%rdi
 105dd53:	48 89 de             	mov    %rbx,%rsi
 105dd56:	e8 05 d2 00 00       	call   106af60 <my.heap::string_hash>
 105dd5b:	4c 89 e7             	mov    %r12,%rdi
 105dd5e:	4c 89 ee             	mov    %r13,%rsi
 105dd61:	48 89 da             	mov    %rbx,%rdx
 105dd64:	89 c1                	mov    %eax,%ecx
 105dd66:	e8 d5 d0 00 00       	call   106ae40 <my.table::get>
 105dd6b:	3c 01                	cmp    $0x1,%al
 105dd6d:	0f 85 53 11 00 00    	jne    105eec6 <my.vm::run+0x2016>
 105dd73:	49 8b 7e 78          	mov    0x78(%r14),%rdi
 105dd77:	49 8b b6 80 00 00 00 	mov    0x80(%r14),%rsi
 105dd7e:	48 8b 47 08          	mov    0x8(%rdi),%rax
 105dd82:	49 89 f0             	mov    %rsi,%r8
 105dd85:	48 39 c6             	cmp    %rax,%rsi
 105dd88:	4d 89 f1             	mov    %r14,%r9
 105dd8b:	0f 83 10 1f 00 00    	jae    105fca1 <my.vm::run+0x2df1>
 105dd91:	49 c1 e0 04          	shl    $0x4,%r8
 105dd95:	0f b6 c2             	movzbl %dl,%eax
 105dd98:	4a 89 44 07 20       	mov    %rax,0x20(%rdi,%r8,1)
 105dd9d:	4a 89 4c 07 28       	mov    %rcx,0x28(%rdi,%r8,1)
 105dda2:	48 89 f0             	mov    %rsi,%rax
 105dda5:	48 ff c0             	inc    %rax
 105dda8:	4c 8d 25 a1 96 fa ff 	lea    -0x5695f(%rip),%r12        # 1007450 <core_number_pairs+0x1f0>
 105ddaf:	0f 80 f0 29 00 00    	jo     10607a5 <my.vm::run+0x38f5>
 105ddb5:	49 89 eb             	mov    %rbp,%r11
 105ddb8:	49 89 81 80 00 00 00 	mov    %rax,0x80(%r9)
 105ddbf:	4d 8b 91 90 00 00 00 	mov    0x90(%r9),%r10
 105ddc6:	48 89 c5             	mov    %rax,%rbp
 105ddc9:	e9 c2 18 00 00       	jmp    105f690 <my.vm::run+0x27e0>
 105ddce:	48 8d bc 24 90 02 00 	lea    0x290(%rsp),%rdi
 105ddd5:	00 
 105ddd6:	4c 89 ce             	mov    %r9,%rsi
 105ddd9:	48 8b 54 24 10       	mov    0x10(%rsp),%rdx
 105ddde:	4c 89 d9             	mov    %r11,%rcx
 105dde1:	4d 89 f8             	mov    %r15,%r8
 105dde4:	4d 89 cf             	mov    %r9,%r15
 105dde7:	4c 8b 4c 24 20       	mov    0x20(%rsp),%r9
 105ddec:	e8 8f 64 00 00       	call   1064280 <my.vm::read_constant>
 105ddf1:	4d 89 f9             	mov    %r15,%r9
 105ddf4:	c5 f9 28 84 24 90 02 	vmovapd 0x290(%rsp),%xmm0
 105ddfb:	00 00 
 105ddfd:	48 8b 84 24 a0 02 00 	mov    0x2a0(%rsp),%rax
 105de04:	00 
 105de05:	48 89 44 24 10       	mov    %rax,0x10(%rsp)
 105de0a:	4c 8b 9c 24 a8 02 00 	mov    0x2a8(%rsp),%r11
 105de11:	00 
 105de12:	4c 8b bc 24 b0 02 00 	mov    0x2b0(%rsp),%r15
 105de19:	00 
 105de1a:	48 8b 84 24 b8 02 00 	mov    0x2b8(%rsp),%rax
 105de21:	00 
 105de22:	48 89 44 24 20       	mov    %rax,0x20(%rsp)
 105de27:	49 8b 41 78          	mov    0x78(%r9),%rax
 105de2b:	48 8b 50 08          	mov    0x8(%rax),%rdx
 105de2f:	48 89 d9             	mov    %rbx,%rcx
 105de32:	48 39 d3             	cmp    %rdx,%rbx
 105de35:	0f 83 13 1a 00 00    	jae    105f84e <my.vm::run+0x299e>
 105de3b:	48 c1 e1 04          	shl    $0x4,%rcx
 105de3f:	c5 f9 54 05 99 65 fa 	vandpd -0x59a67(%rip),%xmm0,%xmm0        # 10043e0 <__anon_2214+0xb0>
 105de46:	ff 
 105de47:	c5 f9 11 44 08 20    	vmovupd %xmm0,0x20(%rax,%rcx,1)
 105de4d:	49 89 41 78          	mov    %rax,0x78(%r9)
 105de51:	48 89 dd             	mov    %rbx,%rbp
 105de54:	48 ff c5             	inc    %rbp
 105de57:	0f 80 7a 26 00 00    	jo     10604d7 <my.vm::run+0x3627>
 105de5d:	4d 89 f2             	mov    %r14,%r10
 105de60:	49 89 a9 80 00 00 00 	mov    %rbp,0x80(%r9)
 105de67:	e9 24 18 00 00       	jmp    105f690 <my.vm::run+0x27e0>
 105de6c:	49 8b 41 78          	mov    0x78(%r9),%rax
 105de70:	48 8b 50 08          	mov    0x8(%rax),%rdx
 105de74:	48 89 d9             	mov    %rbx,%rcx
 105de77:	48 39 d3             	cmp    %rdx,%rbx
 105de7a:	0f 83 e9 19 00 00    	jae    105f869 <my.vm::run+0x29b9>
 105de80:	48 c1 e1 04          	shl    $0x4,%rcx
 105de84:	48 c7 44 08 20 00 00 	movq   $0x0,0x20(%rax,%rcx,1)
 105de8b:	00 00 
 105de8d:	49 89 41 78          	mov    %rax,0x78(%r9)
 105de91:	48 89 dd             	mov    %rbx,%rbp
 105de94:	48 ff c5             	inc    %rbp
 105de97:	0f 80 0d 28 00 00    	jo     10606aa <my.vm::run+0x37fa>
 105de9d:	49 89 a9 80 00 00 00 	mov    %rbp,0x80(%r9)
 105dea4:	e9 e7 17 00 00       	jmp    105f690 <my.vm::run+0x27e0>
 105dea9:	48 8d bc 24 68 02 00 	lea    0x268(%rsp),%rdi
 105deb0:	00 
 105deb1:	4d 89 f8             	mov    %r15,%r8
 105deb4:	4d 89 cf             	mov    %r9,%r15
 105deb7:	4c 89 ce             	mov    %r9,%rsi
 105deba:	48 8b 54 24 10       	mov    0x10(%rsp),%rdx
 105debf:	4c 89 d9             	mov    %r11,%rcx
 105dec2:	4c 8b 4c 24 20       	mov    0x20(%rsp),%r9
 105dec7:	e8 04 6b 00 00       	call   10649d0 <my.vm::read_short>
 105decc:	48 8b 94 24 68 02 00 	mov    0x268(%rsp),%rdx
 105ded3:	00 
 105ded4:	48 8b b4 24 80 02 00 	mov    0x280(%rsp),%rsi
 105dedb:	00 
 105dedc:	48 89 f0             	mov    %rsi,%rax
 105dedf:	48 01 d0             	add    %rdx,%rax
 105dee2:	0f 80 98 26 00 00    	jo     1060580 <my.vm::run+0x36d0>
 105dee8:	48 89 c1             	mov    %rax,%rcx
 105deeb:	48 8b 84 24 70 02 00 	mov    0x270(%rsp),%rax
 105def2:	00 
 105def3:	48 89 44 24 10       	mov    %rax,0x10(%rsp)
 105def8:	4c 8b 9c 24 78 02 00 	mov    0x278(%rsp),%r11
 105deff:	00 
 105df00:	48 8b 84 24 88 02 00 	mov    0x288(%rsp),%rax
 105df07:	00 
 105df08:	48 89 44 24 20       	mov    %rax,0x20(%rsp)
 105df0d:	48 89 dd             	mov    %rbx,%rbp
 105df10:	4d 89 f2             	mov    %r14,%r10
 105df13:	4d 89 f9             	mov    %r15,%r9
 105df16:	49 89 cf             	mov    %rcx,%r15
 105df19:	e9 72 17 00 00       	jmp    105f690 <my.vm::run+0x27e0>
 105df1e:	48 89 dd             	mov    %rbx,%rbp
 105df21:	48 ff cd             	dec    %rbp
 105df24:	0f 80 26 25 00 00    	jo     1060450 <my.vm::run+0x35a0>
 105df2a:	49 89 a9 80 00 00 00 	mov    %rbp,0x80(%r9)
 105df31:	49 8b 41 78          	mov    0x78(%r9),%rax
 105df35:	48 8b 50 08          	mov    0x8(%rax),%rdx
 105df39:	48 89 ee             	mov    %rbp,%rsi
 105df3c:	48 39 d5             	cmp    %rdx,%rbp
 105df3f:	0f 83 b8 19 00 00    	jae    105f8fd <my.vm::run+0x2a4d>
 105df45:	48 c1 e6 04          	shl    $0x4,%rsi
 105df49:	48 8b 4c 30 28       	mov    0x28(%rax,%rsi,1),%rcx
 105df4e:	8b 54 30 20          	mov    0x20(%rax,%rsi,1),%edx
 105df52:	4c 89 cf             	mov    %r9,%rdi
 105df55:	48 8b 74 24 48       	mov    0x48(%rsp),%rsi
 105df5a:	4c 89 cb             	mov    %r9,%rbx
 105df5d:	e8 de 66 00 00       	call   1064640 <my.output::print_value>
 105df62:	49 89 d9             	mov    %rbx,%r9
 105df65:	4c 8d 25 e4 94 fa ff 	lea    -0x56b1c(%rip),%r12        # 1007450 <core_number_pairs+0x1f0>
 105df6c:	4d 89 eb             	mov    %r13,%r11
 105df6f:	4d 89 f2             	mov    %r14,%r10
 105df72:	e9 19 17 00 00       	jmp    105f690 <my.vm::run+0x27e0>
 105df77:	4c 89 fd             	mov    %r15,%rbp
 105df7a:	4d 89 cf             	mov    %r9,%r15
 105df7d:	4c 89 cf             	mov    %r9,%rdi
 105df80:	4c 89 de             	mov    %r11,%rsi
 105df83:	48 89 ea             	mov    %rbp,%rdx
 105df86:	e8 a5 cd 00 00       	call   106ad30 <my.heap::function_instruction>
 105df8b:	48 89 e9             	mov    %rbp,%rcx
 105df8e:	48 ff c1             	inc    %rcx
 105df91:	0f 80 18 25 00 00    	jo     10604af <my.vm::run+0x35ff>
 105df97:	48 8b 74 24 20       	mov    0x20(%rsp),%rsi
 105df9c:	48 01 c6             	add    %rax,%rsi
 105df9f:	0f 80 d0 24 00 00    	jo     1060475 <my.vm::run+0x35c5>
 105dfa5:	4d 89 f9             	mov    %r15,%r9
 105dfa8:	49 8b 47 78          	mov    0x78(%r15),%rax
 105dfac:	48 8b 50 08          	mov    0x8(%rax),%rdx
 105dfb0:	48 39 d6             	cmp    %rdx,%rsi
 105dfb3:	4d 89 eb             	mov    %r13,%r11
 105dfb6:	4d 89 f2             	mov    %r14,%r10
 105dfb9:	0f 83 ee 19 00 00    	jae    105f9ad <my.vm::run+0x2afd>
 105dfbf:	48 89 f7             	mov    %rsi,%rdi
 105dfc2:	48 c1 e7 04          	shl    $0x4,%rdi
 105dfc6:	c5 f9 10 44 38 20    	vmovupd 0x20(%rax,%rdi,1),%xmm0
 105dfcc:	48 89 de             	mov    %rbx,%rsi
 105dfcf:	48 39 d3             	cmp    %rdx,%rbx
 105dfd2:	0f 83 26 1a 00 00    	jae    105f9fe <my.vm::run+0x2b4e>
 105dfd8:	48 8d 50 20          	lea    0x20(%rax),%rdx
 105dfdc:	48 c1 e6 04          	shl    $0x4,%rsi
 105dfe0:	c5 f9 54 05 f8 63 fa 	vandpd -0x59c08(%rip),%xmm0,%xmm0        # 10043e0 <__anon_2214+0xb0>
 105dfe7:	ff 
 105dfe8:	c5 f9 11 04 32       	vmovupd %xmm0,(%rdx,%rsi,1)
 105dfed:	49 89 41 78          	mov    %rax,0x78(%r9)
 105dff1:	48 89 dd             	mov    %rbx,%rbp
 105dff4:	48 ff c5             	inc    %rbp
 105dff7:	0f 80 2e 24 00 00    	jo     106042b <my.vm::run+0x357b>
 105dffd:	49 89 a9 80 00 00 00 	mov    %rbp,0x80(%r9)
 105e004:	49 89 cf             	mov    %rcx,%r15
 105e007:	e9 84 16 00 00       	jmp    105f690 <my.vm::run+0x27e0>
 105e00c:	49 8b b1 80 00 00 00 	mov    0x80(%r9),%rsi
 105e013:	48 89 f3             	mov    %rsi,%rbx
 105e016:	48 ff cb             	dec    %rbx
 105e019:	0f 80 66 26 00 00    	jo     1060685 <my.vm::run+0x37d5>
 105e01f:	48 89 d8             	mov    %rbx,%rax
 105e022:	48 ff c8             	dec    %rax
 105e025:	0f 80 1e 26 00 00    	jo     1060649 <my.vm::run+0x3799>
 105e02b:	4d 8b 61 78          	mov    0x78(%r9),%r12
 105e02f:	49 8b 54 24 08       	mov    0x8(%r12),%rdx
 105e034:	48 89 c7             	mov    %rax,%rdi
 105e037:	48 39 d0             	cmp    %rdx,%rax
 105e03a:	0f 83 88 19 00 00    	jae    105f9c8 <my.vm::run+0x2b18>
 105e040:	48 c1 e7 04          	shl    $0x4,%rdi
 105e044:	41 80 7c 3c 20 03    	cmpb   $0x3,0x20(%r12,%rdi,1)
 105e04a:	48 89 44 24 38       	mov    %rax,0x38(%rsp)
 105e04f:	48 89 7c 24 58       	mov    %rdi,0x58(%rsp)
 105e054:	0f 85 6d 14 00 00    	jne    105f4c7 <my.vm::run+0x2617>
 105e05a:	49 8b 74 3c 28       	mov    0x28(%r12,%rdi,1),%rsi
 105e05f:	49 8b 09             	mov    (%r9),%rcx
 105e062:	48 8b 51 08          	mov    0x8(%rcx),%rdx
 105e066:	48 39 d6             	cmp    %rdx,%rsi
 105e069:	0f 83 17 1c 00 00    	jae    105fc86 <my.vm::run+0x2dd6>
 105e06f:	48 89 f0             	mov    %rsi,%rax
 105e072:	48 6b f0 38          	imul   $0x38,%rax,%rsi
 105e076:	8b 54 31 20          	mov    0x20(%rcx,%rsi,1),%edx
 105e07a:	31 ff                	xor    %edi,%edi
 105e07c:	31 ed                	xor    %ebp,%ebp
 105e07e:	31 c0                	xor    %eax,%eax
 105e080:	ff ca                	dec    %edx
 105e082:	83 fa 08             	cmp    $0x8,%edx
 105e085:	0f 87 42 14 00 00    	ja     105f4cd <my.vm::run+0x261d>
 105e08b:	48 01 f1             	add    %rsi,%rcx
 105e08e:	48 83 c1 20          	add    $0x20,%rcx
 105e092:	48 8d 35 f3 94 fa ff 	lea    -0x56b0d(%rip),%rsi        # 100758c <core_number_pairs+0x32c>
 105e099:	48 63 14 96          	movslq (%rsi,%rdx,4),%rdx
 105e09d:	48 01 f2             	add    %rsi,%rdx
 105e0a0:	31 f6                	xor    %esi,%esi
 105e0a2:	ff e2                	jmp    *%rdx
 105e0a4:	48 8b 79 08          	mov    0x8(%rcx),%rdi
 105e0a8:	4d 89 ce             	mov    %r9,%r14
 105e0ab:	e8 d0 6f fc ff       	call   1025080 <myl_core_owned_octets_copy>
 105e0b0:	e9 04 14 00 00       	jmp    105f4b9 <my.vm::run+0x2609>
 105e0b5:	4c 89 fd             	mov    %r15,%rbp
 105e0b8:	4d 89 cf             	mov    %r9,%r15
 105e0bb:	4c 89 cf             	mov    %r9,%rdi
 105e0be:	4c 89 de             	mov    %r11,%rsi
 105e0c1:	48 89 ea             	mov    %rbp,%rdx
 105e0c4:	e8 67 cc 00 00       	call   106ad30 <my.heap::function_instruction>
 105e0c9:	48 89 e9             	mov    %rbp,%rcx
 105e0cc:	48 ff c1             	inc    %rcx
 105e0cf:	0f 80 dc 21 00 00    	jo     10602b1 <my.vm::run+0x3401>
 105e0d5:	48 89 dd             	mov    %rbx,%rbp
 105e0d8:	48 89 de             	mov    %rbx,%rsi
 105e0db:	48 ff ce             	dec    %rsi
 105e0de:	0f 80 79 25 00 00    	jo     106065d <my.vm::run+0x37ad>
 105e0e4:	4d 89 f9             	mov    %r15,%r9
 105e0e7:	49 8b 7f 78          	mov    0x78(%r15),%rdi
 105e0eb:	48 8b 57 08          	mov    0x8(%rdi),%rdx
 105e0ef:	48 39 d6             	cmp    %rdx,%rsi
 105e0f2:	4d 89 eb             	mov    %r13,%r11
 105e0f5:	4d 89 f2             	mov    %r14,%r10
 105e0f8:	0f 83 e5 18 00 00    	jae    105f9e3 <my.vm::run+0x2b33>
 105e0fe:	49 89 f0             	mov    %rsi,%r8
 105e101:	48 8b 74 24 20       	mov    0x20(%rsp),%rsi
 105e106:	48 01 c6             	add    %rax,%rsi
 105e109:	0f 80 ed 24 00 00    	jo     10605fc <my.vm::run+0x374c>
 105e10f:	49 c1 e0 04          	shl    $0x4,%r8
 105e113:	c4 a1 79 10 44 07 20 	vmovupd 0x20(%rdi,%r8,1),%xmm0
 105e11a:	48 39 d6             	cmp    %rdx,%rsi
 105e11d:	0f 83 40 19 00 00    	jae    105fa63 <my.vm::run+0x2bb3>
 105e123:	48 89 f0             	mov    %rsi,%rax
 105e126:	48 8d 57 20          	lea    0x20(%rdi),%rdx
 105e12a:	48 c1 e0 04          	shl    $0x4,%rax
 105e12e:	c5 f9 54 05 aa 62 fa 	vandpd -0x59d56(%rip),%xmm0,%xmm0        # 10043e0 <__anon_2214+0xb0>
 105e135:	ff 
 105e136:	c5 f9 11 04 02       	vmovupd %xmm0,(%rdx,%rax,1)
 105e13b:	49 89 79 78          	mov    %rdi,0x78(%r9)
 105e13f:	49 89 cf             	mov    %rcx,%r15
 105e142:	e9 49 15 00 00       	jmp    105f690 <my.vm::run+0x27e0>
 105e147:	4c 89 cf             	mov    %r9,%rdi
 105e14a:	4c 89 de             	mov    %r11,%rsi
 105e14d:	4c 89 fa             	mov    %r15,%rdx
 105e150:	4c 89 cb             	mov    %r9,%rbx
 105e153:	e8 d8 cb 00 00       	call   106ad30 <my.heap::function_instruction>
 105e158:	4d 89 fc             	mov    %r15,%r12
 105e15b:	49 ff c4             	inc    %r12
 105e15e:	0f 80 9b 23 00 00    	jo     10604ff <my.vm::run+0x364f>
 105e164:	48 89 df             	mov    %rbx,%rdi
 105e167:	48 8b 74 24 10       	mov    0x10(%rsp),%rsi
 105e16c:	48 89 c2             	mov    %rax,%rdx
 105e16f:	e8 bc d1 00 00       	call   106b330 <my.heap::closure_upvalue>
 105e174:	48 8d bc 24 c0 02 00 	lea    0x2c0(%rsp),%rdi
 105e17b:	00 
 105e17c:	48 89 de             	mov    %rbx,%rsi
 105e17f:	48 89 c2             	mov    %rax,%rdx
 105e182:	e8 a9 d0 00 00       	call   106b230 <my.heap::upvalue_obj>
 105e187:	48 8b b4 24 c0 02 00 	mov    0x2c0(%rsp),%rsi
 105e18e:	00 
 105e18f:	48 83 fe ff          	cmp    $0xffffffffffffffff,%rsi
 105e193:	0f 84 96 0e 00 00    	je     105f02f <my.vm::run+0x217f>
 105e199:	48 8b 43 78          	mov    0x78(%rbx),%rax
 105e19d:	48 8b 50 08          	mov    0x8(%rax),%rdx
 105e1a1:	48 39 d6             	cmp    %rdx,%rsi
 105e1a4:	4d 89 eb             	mov    %r13,%r11
 105e1a7:	49 89 d9             	mov    %rbx,%r9
 105e1aa:	0f 83 34 1a 00 00    	jae    105fbe4 <my.vm::run+0x2d34>
 105e1b0:	48 89 f1             	mov    %rsi,%rcx
 105e1b3:	48 c1 e1 04          	shl    $0x4,%rcx
 105e1b7:	c5 f9 10 44 08 20    	vmovupd 0x20(%rax,%rcx,1),%xmm0
 105e1bd:	49 8b b1 80 00 00 00 	mov    0x80(%r9),%rsi
 105e1c4:	48 89 f1             	mov    %rsi,%rcx
 105e1c7:	48 39 d6             	cmp    %rdx,%rsi
 105e1ca:	0f 83 2f 1a 00 00    	jae    105fbff <my.vm::run+0x2d4f>
 105e1d0:	48 83 c0 20          	add    $0x20,%rax
 105e1d4:	48 c1 e1 04          	shl    $0x4,%rcx
 105e1d8:	c5 f9 54 05 00 62 fa 	vandpd -0x59e00(%rip),%xmm0,%xmm0        # 10043e0 <__anon_2214+0xb0>
 105e1df:	ff 
 105e1e0:	c5 f9 11 04 08       	vmovupd %xmm0,(%rax,%rcx,1)
 105e1e5:	48 89 f5             	mov    %rsi,%rbp
 105e1e8:	48 ff c5             	inc    %rbp
 105e1eb:	0f 81 8d 0e 00 00    	jno    105f07e <my.vm::run+0x21ce>
 105e1f1:	e9 8f 25 00 00       	jmp    1060785 <my.vm::run+0x38d5>
 105e1f6:	48 89 de             	mov    %rbx,%rsi
 105e1f9:	48 ff ce             	dec    %rsi
 105e1fc:	0f 80 6a 23 00 00    	jo     106056c <my.vm::run+0x36bc>
 105e202:	4d 89 ce             	mov    %r9,%r14
 105e205:	49 8b 41 78          	mov    0x78(%r9),%rax
 105e209:	48 8b 50 08          	mov    0x8(%rax),%rdx
 105e20d:	48 39 d6             	cmp    %rdx,%rsi
 105e210:	0f 83 02 17 00 00    	jae    105f918 <my.vm::run+0x2a68>
 105e216:	48 89 f1             	mov    %rsi,%rcx
 105e219:	4c 8b 4c 24 20       	mov    0x20(%rsp),%r9
 105e21e:	48 c1 e1 04          	shl    $0x4,%rcx
 105e222:	48 8b 5c 08 20       	mov    0x20(%rax,%rcx,1),%rbx
 105e227:	4c 8b 64 08 28       	mov    0x28(%rax,%rcx,1),%r12
 105e22c:	48 8d 7c 24 70       	lea    0x70(%rsp),%rdi
 105e231:	4c 89 f6             	mov    %r14,%rsi
 105e234:	48 8b 54 24 10       	mov    0x10(%rsp),%rdx
 105e239:	4c 89 d9             	mov    %r11,%rcx
 105e23c:	4d 89 f8             	mov    %r15,%r8
 105e23f:	e8 3c 60 00 00       	call   1064280 <my.vm::read_constant>
 105e244:	0f b6 44 24 70       	movzbl 0x70(%rsp),%eax
 105e249:	83 f8 03             	cmp    $0x3,%eax
 105e24c:	0f 85 97 1d 00 00    	jne    105ffe9 <my.vm::run+0x3139>
 105e252:	48 8b 84 24 98 00 00 	mov    0x98(%rsp),%rax
 105e259:	00 
 105e25a:	48 89 44 24 20       	mov    %rax,0x20(%rsp)
 105e25f:	4c 8b bc 24 90 00 00 	mov    0x90(%rsp),%r15
 105e266:	00 
 105e267:	48 8b ac 24 88 00 00 	mov    0x88(%rsp),%rbp
 105e26e:	00 
 105e26f:	4c 8b 6c 24 78       	mov    0x78(%rsp),%r13
 105e274:	48 8b 84 24 80 00 00 	mov    0x80(%rsp),%rax
 105e27b:	00 
 105e27c:	48 89 44 24 10       	mov    %rax,0x10(%rsp)
 105e281:	4c 89 f7             	mov    %r14,%rdi
 105e284:	4c 89 ee             	mov    %r13,%rsi
 105e287:	e8 d4 cc 00 00       	call   106af60 <my.heap::string_hash>
 105e28c:	49 8b 7e 30          	mov    0x30(%r14),%rdi
 105e290:	49 8b 76 38          	mov    0x38(%r14),%rsi
 105e294:	4c 89 ea             	mov    %r13,%rdx
 105e297:	89 c1                	mov    %eax,%ecx
 105e299:	41 89 d8             	mov    %ebx,%r8d
 105e29c:	4d 89 e1             	mov    %r12,%r9
 105e29f:	e8 9c cd 00 00       	call   106b040 <my.table::set>
 105e2a4:	49 89 56 30          	mov    %rdx,0x30(%r14)
 105e2a8:	49 89 4e 38          	mov    %rcx,0x38(%r14)
 105e2ac:	49 8b b6 80 00 00 00 	mov    0x80(%r14),%rsi
 105e2b3:	48 89 f1             	mov    %rsi,%rcx
 105e2b6:	48 ff c9             	dec    %rcx
 105e2b9:	0f 80 80 21 00 00    	jo     106043f <my.vm::run+0x358f>
 105e2bf:	4d 89 f1             	mov    %r14,%r9
 105e2c2:	49 89 8e 80 00 00 00 	mov    %rcx,0x80(%r14)
 105e2c9:	49 8b 46 78          	mov    0x78(%r14),%rax
 105e2cd:	4d 8b 96 90 00 00 00 	mov    0x90(%r14),%r10
 105e2d4:	48 8b 50 08          	mov    0x8(%rax),%rdx
 105e2d8:	48 89 c8             	mov    %rcx,%rax
 105e2db:	48 39 d1             	cmp    %rdx,%rcx
 105e2de:	4c 8d 25 6b 91 fa ff 	lea    -0x56e95(%rip),%r12        # 1007450 <core_number_pairs+0x1f0>
 105e2e5:	49 89 eb             	mov    %rbp,%r11
 105e2e8:	0f 83 fc 17 00 00    	jae    105faea <my.vm::run+0x2c3a>
 105e2ee:	48 89 c5             	mov    %rax,%rbp
 105e2f1:	e9 9a 13 00 00       	jmp    105f690 <my.vm::run+0x27e0>
 105e2f6:	48 8d 7c 24 70       	lea    0x70(%rsp),%rdi
 105e2fb:	4c 89 ce             	mov    %r9,%rsi
 105e2fe:	48 8b 54 24 10       	mov    0x10(%rsp),%rdx
 105e303:	4c 89 d9             	mov    %r11,%rcx
 105e306:	4d 89 f8             	mov    %r15,%r8
 105e309:	4c 89 cb             	mov    %r9,%rbx
 105e30c:	4c 8b 4c 24 20       	mov    0x20(%rsp),%r9
 105e311:	e8 6a 5f 00 00       	call   1064280 <my.vm::read_constant>
 105e316:	0f b6 44 24 70       	movzbl 0x70(%rsp),%eax
 105e31b:	83 f8 03             	cmp    $0x3,%eax
 105e31e:	0f 85 04 1e 00 00    	jne    1060128 <my.vm::run+0x3278>
 105e324:	4c 8b ac 24 98 00 00 	mov    0x98(%rsp),%r13
 105e32b:	00 
 105e32c:	4c 8b bc 24 90 00 00 	mov    0x90(%rsp),%r15
 105e333:	00 
 105e334:	48 8b bc 24 88 00 00 	mov    0x88(%rsp),%rdi
 105e33b:	00 
 105e33c:	4c 8b 44 24 78       	mov    0x78(%rsp),%r8
 105e341:	48 8b 84 24 80 00 00 	mov    0x80(%rsp),%rax
 105e348:	00 
 105e349:	48 89 44 24 10       	mov    %rax,0x10(%rsp)
 105e34e:	48 8b 03             	mov    (%rbx),%rax
 105e351:	48 8b 50 08          	mov    0x8(%rax),%rdx
 105e355:	4c 89 c1             	mov    %r8,%rcx
 105e358:	49 39 d0             	cmp    %rdx,%r8
 105e35b:	0f 83 e7 16 00 00    	jae    105fa48 <my.vm::run+0x2b98>
 105e361:	48 89 7c 24 18       	mov    %rdi,0x18(%rsp)
 105e366:	48 6b d1 38          	imul   $0x38,%rcx,%rdx
 105e36a:	8b 4c 10 20          	mov    0x20(%rax,%rdx,1),%ecx
 105e36e:	83 f9 02             	cmp    $0x2,%ecx
 105e371:	0f 85 05 1c 00 00    	jne    105ff7c <my.vm::run+0x30cc>
 105e377:	48 01 d0             	add    %rdx,%rax
 105e37a:	48 83 c0 20          	add    $0x20,%rax
 105e37e:	48 8b 70 10          	mov    0x10(%rax),%rsi
 105e382:	4c 89 c7             	mov    %r8,%rdi
 105e385:	48 89 74 24 38       	mov    %rsi,0x38(%rsp)
 105e38a:	e8 d1 e7 ff ff       	call   105cb60 <my.object::new_closure>
 105e38f:	49 89 c6             	mov    %rax,%r14
 105e392:	49 89 d4             	mov    %rdx,%r12
 105e395:	be 08 00 00 00       	mov    $0x8,%esi
 105e39a:	48 89 d7             	mov    %rdx,%rdi
 105e39d:	e8 1e 63 fc ff       	call   10246c0 <myl_core_list_copy>
 105e3a2:	48 c7 84 24 a8 01 00 	movq   $0x4,0x1a8(%rsp)
 105e3a9:	00 04 00 00 00 
 105e3ae:	4c 89 74 24 58       	mov    %r14,0x58(%rsp)
 105e3b3:	4c 89 b4 24 b0 01 00 	mov    %r14,0x1b0(%rsp)
 105e3ba:	00 
 105e3bb:	48 89 84 24 b8 01 00 	mov    %rax,0x1b8(%rsp)
 105e3c2:	00 
 105e3c3:	48 8d bc 24 00 03 00 	lea    0x300(%rsp),%rdi
 105e3ca:	00 
 105e3cb:	48 8d 94 24 a8 01 00 	lea    0x1a8(%rsp),%rdx
 105e3d2:	00 
 105e3d3:	48 89 de             	mov    %rbx,%rsi
 105e3d6:	e8 85 ce ff ff       	call   105b260 <my.heap::allocate>
 105e3db:	0f b6 84 24 a8 01 00 	movzbl 0x1a8(%rsp),%eax
 105e3e2:	00 
 105e3e3:	ff c8                	dec    %eax
 105e3e5:	83 f8 08             	cmp    $0x8,%eax
 105e3e8:	77 1d                	ja     105e407 <my.vm::run+0x1557>
 105e3ea:	48 8d 0d 3f 91 fa ff 	lea    -0x56ec1(%rip),%rcx        # 1007530 <core_number_pairs+0x2d0>
 105e3f1:	48 63 04 81          	movslq (%rcx,%rax,4),%rax
 105e3f5:	48 01 c8             	add    %rcx,%rax
 105e3f8:	ff e0                	jmp    *%rax
 105e3fa:	48 8b bc 24 b8 01 00 	mov    0x1b8(%rsp),%rdi
 105e401:	00 
 105e402:	e8 f9 63 fc ff       	call   1024800 <myl_core_drop_owned>
 105e407:	4c 8b 84 24 00 03 00 	mov    0x300(%rsp),%r8
 105e40e:	00 
 105e40f:	48 89 df             	mov    %rbx,%rdi
 105e412:	48 8b 43 78          	mov    0x78(%rbx),%rax
 105e416:	48 8b b3 80 00 00 00 	mov    0x80(%rbx),%rsi
 105e41d:	48 8b 50 08          	mov    0x8(%rax),%rdx
 105e421:	48 89 f1             	mov    %rsi,%rcx
 105e424:	48 39 d6             	cmp    %rdx,%rsi
 105e427:	0f 83 4e 17 00 00    	jae    105fb7b <my.vm::run+0x2ccb>
 105e42d:	48 c1 e1 04          	shl    $0x4,%rcx
 105e431:	48 c7 44 08 20 03 00 	movq   $0x3,0x20(%rax,%rcx,1)
 105e438:	00 00 
 105e43a:	4c 89 44 24 60       	mov    %r8,0x60(%rsp)
 105e43f:	4c 89 44 08 28       	mov    %r8,0x28(%rax,%rcx,1)
 105e444:	48 89 f0             	mov    %rsi,%rax
 105e447:	48 ff c0             	inc    %rax
 105e44a:	0f 80 73 21 00 00    	jo     10605c3 <my.vm::run+0x3713>
 105e450:	4c 89 6c 24 20       	mov    %r13,0x20(%rsp)
 105e455:	48 89 87 80 00 00 00 	mov    %rax,0x80(%rdi)
 105e45c:	be 08 00 00 00       	mov    $0x8,%esi
 105e461:	4c 89 e7             	mov    %r12,%rdi
 105e464:	e8 57 62 fc ff       	call   10246c0 <myl_core_list_copy>
 105e469:	48 89 c5             	mov    %rax,%rbp
 105e46c:	4c 89 e7             	mov    %r12,%rdi
 105e46f:	e8 8c 63 fc ff       	call   1024800 <myl_core_drop_owned>
 105e474:	48 83 7c 24 38 00    	cmpq   $0x0,0x38(%rsp)
 105e47a:	0f 8e 14 0c 00 00    	jle    105f094 <my.vm::run+0x21e4>
 105e480:	45 31 e4             	xor    %r12d,%r12d
 105e483:	4c 8b 5c 24 18       	mov    0x18(%rsp),%r11
 105e488:	49 89 de             	mov    %rbx,%r14
 105e48b:	48 89 6c 24 40       	mov    %rbp,0x40(%rsp)
 105e490:	eb 36                	jmp    105e4c8 <my.vm::run+0x1618>
 105e492:	4c 89 ab 98 00 00 00 	mov    %r13,0x98(%rbx)
 105e499:	48 8b 6c 24 40       	mov    0x40(%rsp),%rbp
 105e49e:	48 8b 55 08          	mov    0x8(%rbp),%rdx
 105e4a2:	49 39 d4             	cmp    %rdx,%r12
 105e4a5:	4c 8b 74 24 50       	mov    0x50(%rsp),%r14
 105e4aa:	4c 8b 5c 24 18       	mov    0x18(%rsp),%r11
 105e4af:	0f 83 11 1b 00 00    	jae    105ffc6 <my.vm::run+0x3116>
 105e4b5:	4e 89 6c e5 20       	mov    %r13,0x20(%rbp,%r12,8)
 105e4ba:	49 ff c4             	inc    %r12
 105e4bd:	4c 3b 64 24 38       	cmp    0x38(%rsp),%r12
 105e4c2:	0f 84 d4 0b 00 00    	je     105f09c <my.vm::run+0x21ec>
 105e4c8:	4c 89 f7             	mov    %r14,%rdi
 105e4cb:	4c 89 de             	mov    %r11,%rsi
 105e4ce:	4c 89 fa             	mov    %r15,%rdx
 105e4d1:	4c 89 db             	mov    %r11,%rbx
 105e4d4:	e8 57 c8 00 00       	call   106ad30 <my.heap::function_instruction>
 105e4d9:	4d 89 fd             	mov    %r15,%r13
 105e4dc:	49 ff c5             	inc    %r13
 105e4df:	0f 80 61 1a 00 00    	jo     105ff46 <my.vm::run+0x3096>
 105e4e5:	48 89 c5             	mov    %rax,%rbp
 105e4e8:	4d 89 f7             	mov    %r14,%r15
 105e4eb:	4c 89 f7             	mov    %r14,%rdi
 105e4ee:	48 89 de             	mov    %rbx,%rsi
 105e4f1:	4c 89 ea             	mov    %r13,%rdx
 105e4f4:	e8 37 c8 00 00       	call   106ad30 <my.heap::function_instruction>
 105e4f9:	4c 89 e9             	mov    %r13,%rcx
 105e4fc:	48 ff c1             	inc    %rcx
 105e4ff:	0f 80 2d 1a 00 00    	jo     105ff32 <my.vm::run+0x3082>
 105e505:	48 89 cb             	mov    %rcx,%rbx
 105e508:	48 83 fd 01          	cmp    $0x1,%rbp
 105e50c:	0f 85 be 00 00 00    	jne    105e5d0 <my.vm::run+0x1720>
 105e512:	49 89 c6             	mov    %rax,%r14
 105e515:	4c 03 74 24 20       	add    0x20(%rsp),%r14
 105e51a:	0f 80 92 1a 00 00    	jo     105ffb2 <my.vm::run+0x3102>
 105e520:	48 8b 74 24 50       	mov    0x50(%rsp),%rsi
 105e525:	4c 8b ae 98 00 00 00 	mov    0x98(%rsi),%r13
 105e52c:	49 83 fd ff          	cmp    $0xffffffffffffffff,%r13
 105e530:	49 89 df             	mov    %rbx,%r15
 105e533:	0f 84 cc 00 00 00    	je     105e605 <my.vm::run+0x1755>
 105e539:	48 8d bc 24 70 04 00 	lea    0x470(%rsp),%rdi
 105e540:	00 
 105e541:	4c 89 ea             	mov    %r13,%rdx
 105e544:	e8 e7 cc 00 00       	call   106b230 <my.heap::upvalue_obj>
 105e549:	48 c7 c5 ff ff ff ff 	mov    $0xffffffffffffffff,%rbp
 105e550:	4c 39 b4 24 70 04 00 	cmp    %r14,0x470(%rsp)
 105e557:	00 
 105e558:	0f 8e b7 00 00 00    	jle    105e615 <my.vm::run+0x1765>
 105e55e:	48 8b 5c 24 50       	mov    0x50(%rsp),%rbx
 105e563:	66 66 66 66 66 66 2e 	data16 data16 data16 data16 data16 cs nopw 0x0(%rax,%rax,1)
 105e56a:	0f 1f 84 00 00 00 00 
 105e571:	00 
 105e572:	66 66 66 66 66 2e 0f 	data16 data16 data16 data16 cs nopw 0x0(%rax,%rax,1)
 105e579:	1f 84 00 00 00 00 00 
 105e580:	4c 89 ed             	mov    %r13,%rbp
 105e583:	48 8d bc 24 50 04 00 	lea    0x450(%rsp),%rdi
 105e58a:	00 
 105e58b:	48 89 de             	mov    %rbx,%rsi
 105e58e:	4c 89 ea             	mov    %r13,%rdx
 105e591:	e8 9a cc 00 00       	call   106b230 <my.heap::upvalue_obj>
 105e596:	4c 8b ac 24 68 04 00 	mov    0x468(%rsp),%r13
 105e59d:	00 
 105e59e:	49 83 fd ff          	cmp    $0xffffffffffffffff,%r13
 105e5a2:	0f 84 95 00 00 00    	je     105e63d <my.vm::run+0x178d>
 105e5a8:	48 8d bc 24 30 04 00 	lea    0x430(%rsp),%rdi
 105e5af:	00 
 105e5b0:	48 89 de             	mov    %rbx,%rsi
 105e5b3:	4c 89 ea             	mov    %r13,%rdx
 105e5b6:	e8 75 cc 00 00       	call   106b230 <my.heap::upvalue_obj>
 105e5bb:	4c 39 b4 24 30 04 00 	cmp    %r14,0x430(%rsp)
 105e5c2:	00 
 105e5c3:	7f bb                	jg     105e580 <my.vm::run+0x16d0>
 105e5c5:	eb 53                	jmp    105e61a <my.vm::run+0x176a>
 105e5c7:	66 0f 1f 84 00 00 00 	nopw   0x0(%rax,%rax,1)
 105e5ce:	00 00 
 105e5d0:	4c 89 ff             	mov    %r15,%rdi
 105e5d3:	48 8b 74 24 10       	mov    0x10(%rsp),%rsi
 105e5d8:	48 89 c2             	mov    %rax,%rdx
 105e5db:	e8 50 cd 00 00       	call   106b330 <my.heap::closure_upvalue>
 105e5e0:	48 8b 6c 24 40       	mov    0x40(%rsp),%rbp
 105e5e5:	48 8b 55 08          	mov    0x8(%rbp),%rdx
 105e5e9:	49 39 d4             	cmp    %rdx,%r12
 105e5ec:	0f 83 b1 19 00 00    	jae    105ffa3 <my.vm::run+0x30f3>
 105e5f2:	49 89 c5             	mov    %rax,%r13
 105e5f5:	4c 8b 5c 24 18       	mov    0x18(%rsp),%r11
 105e5fa:	4d 89 fe             	mov    %r15,%r14
 105e5fd:	49 89 df             	mov    %rbx,%r15
 105e600:	e9 b0 fe ff ff       	jmp    105e4b5 <my.vm::run+0x1605>
 105e605:	49 c7 c5 ff ff ff ff 	mov    $0xffffffffffffffff,%r13
 105e60c:	48 c7 c5 ff ff ff ff 	mov    $0xffffffffffffffff,%rbp
 105e613:	eb 2f                	jmp    105e644 <my.vm::run+0x1794>
 105e615:	48 8b 5c 24 50       	mov    0x50(%rsp),%rbx
 105e61a:	48 8d bc 24 10 04 00 	lea    0x410(%rsp),%rdi
 105e621:	00 
 105e622:	48 89 de             	mov    %rbx,%rsi
 105e625:	4c 89 ea             	mov    %r13,%rdx
 105e628:	e8 03 cc 00 00       	call   106b230 <my.heap::upvalue_obj>
 105e62d:	4c 39 b4 24 10 04 00 	cmp    %r14,0x410(%rsp)
 105e634:	00 
 105e635:	0f 84 5e fe ff ff    	je     105e499 <my.vm::run+0x15e9>
 105e63b:	eb 07                	jmp    105e644 <my.vm::run+0x1794>
 105e63d:	49 c7 c5 ff ff ff ff 	mov    $0xffffffffffffffff,%r13
 105e644:	48 c7 84 24 e0 01 00 	movq   $0x5,0x1e0(%rsp)
 105e64b:	00 05 00 00 00 
 105e650:	4c 89 b4 24 e8 01 00 	mov    %r14,0x1e8(%rsp)
 105e657:	00 
 105e658:	48 c7 84 24 f0 01 00 	movq   $0x0,0x1f0(%rsp)
 105e65f:	00 00 00 00 00 
 105e664:	4c 89 ac 24 00 02 00 	mov    %r13,0x200(%rsp)
 105e66b:	00 
 105e66c:	48 8d 7c 24 70       	lea    0x70(%rsp),%rdi
 105e671:	48 8d 94 24 e0 01 00 	lea    0x1e0(%rsp),%rdx
 105e678:	00 
 105e679:	48 8b 5c 24 50       	mov    0x50(%rsp),%rbx
 105e67e:	48 89 de             	mov    %rbx,%rsi
 105e681:	e8 da cb ff ff       	call   105b260 <my.heap::allocate>
 105e686:	4c 8b 6c 24 70       	mov    0x70(%rsp),%r13
 105e68b:	48 83 fd ff          	cmp    $0xffffffffffffffff,%rbp
 105e68f:	0f 84 fd fd ff ff    	je     105e492 <my.vm::run+0x15e2>
 105e695:	48 8d bc 24 e0 02 00 	lea    0x2e0(%rsp),%rdi
 105e69c:	00 
 105e69d:	48 89 de             	mov    %rbx,%rsi
 105e6a0:	48 89 ea             	mov    %rbp,%rdx
 105e6a3:	e8 88 cb 00 00       	call   106b230 <my.heap::upvalue_obj>
 105e6a8:	48 8b b4 24 f0 02 00 	mov    0x2f0(%rsp),%rsi
 105e6af:	00 
 105e6b0:	44 0f b6 8c 24 e8 02 	movzbl 0x2e8(%rsp),%r9d
 105e6b7:	00 00 
 105e6b9:	4c 8b 94 24 e0 02 00 	mov    0x2e0(%rsp),%r10
 105e6c0:	00 
 105e6c1:	4c 8b 03             	mov    (%rbx),%r8
 105e6c4:	49 8b 50 08          	mov    0x8(%r8),%rdx
 105e6c8:	48 39 d5             	cmp    %rdx,%rbp
 105e6cb:	0f 83 86 00 00 00    	jae    105e757 <my.vm::run+0x18a7>
 105e6d1:	48 89 e8             	mov    %rbp,%rax
 105e6d4:	4c 6b d8 38          	imul   $0x38,%rax,%r11
 105e6d8:	43 0f b6 54 18 20    	movzbl 0x20(%r8,%r11,1),%edx
 105e6de:	4b 8b 44 18 28       	mov    0x28(%r8,%r11,1),%rax
 105e6e3:	4b 8b 7c 18 30       	mov    0x30(%r8,%r11,1),%rdi
 105e6e8:	4b 8b 4c 18 38       	mov    0x38(%r8,%r11,1),%rcx
 105e6ed:	4b 8b 6c 18 40       	mov    0x40(%r8,%r11,1),%rbp
 105e6f2:	4b 8b 5c 18 48       	mov    0x48(%r8,%r11,1),%rbx
 105e6f7:	4b c7 44 18 20 05 00 	movq   $0x5,0x20(%r8,%r11,1)
 105e6fe:	00 00 
 105e700:	4f 89 54 18 28       	mov    %r10,0x28(%r8,%r11,1)
 105e705:	45 0f b6 c9          	movzbl %r9b,%r9d
 105e709:	4f 89 4c 18 30       	mov    %r9,0x30(%r8,%r11,1)
 105e70e:	4b 89 74 18 38       	mov    %rsi,0x38(%r8,%r11,1)
 105e713:	4f 89 6c 18 40       	mov    %r13,0x40(%r8,%r11,1)
 105e718:	ff ca                	dec    %edx
 105e71a:	83 fa 08             	cmp    $0x8,%edx
 105e71d:	0f 87 76 fd ff ff    	ja     105e499 <my.vm::run+0x15e9>
 105e723:	48 8d 35 2a 8e fa ff 	lea    -0x571d6(%rip),%rsi        # 1007554 <core_number_pairs+0x2f4>
 105e72a:	48 63 14 96          	movslq (%rsi,%rdx,4),%rdx
 105e72e:	48 01 f2             	add    %rsi,%rdx
 105e731:	ff e2                	jmp    *%rdx
 105e733:	e8 c8 60 fc ff       	call   1024800 <myl_core_drop_owned>
 105e738:	e9 5c fd ff ff       	jmp    105e499 <my.vm::run+0x15e9>
 105e73d:	48 89 cf             	mov    %rcx,%rdi
 105e740:	e8 bb 60 fc ff       	call   1024800 <myl_core_drop_owned>
 105e745:	48 89 ef             	mov    %rbp,%rdi
 105e748:	e8 b3 60 fc ff       	call   1024800 <myl_core_drop_owned>
 105e74d:	48 89 df             	mov    %rbx,%rdi
 105e750:	eb e1                	jmp    105e733 <my.vm::run+0x1883>
 105e752:	48 89 c7             	mov    %rax,%rdi
 105e755:	eb dc                	jmp    105e733 <my.vm::run+0x1883>
 105e757:	48 89 e8             	mov    %rbp,%rax
 105e75a:	48 c1 f8 3f          	sar    $0x3f,%rax
 105e75e:	48 21 d0             	and    %rdx,%rax
 105e761:	48 01 e8             	add    %rbp,%rax
 105e764:	48 39 d0             	cmp    %rdx,%rax
 105e767:	0f 82 67 ff ff ff    	jb     105e6d4 <my.vm::run+0x1824>
 105e76d:	e9 e8 21 00 00       	jmp    106095a <my.vm::run+0x3aaa>
 105e772:	49 8b 81 80 00 00 00 	mov    0x80(%r9),%rax
 105e779:	48 89 c6             	mov    %rax,%rsi
 105e77c:	48 ff ce             	dec    %rsi
 105e77f:	0f 80 40 1b 00 00    	jo     10602c5 <my.vm::run+0x3415>
 105e785:	4c 89 cb             	mov    %r9,%rbx
 105e788:	49 8b 41 78          	mov    0x78(%r9),%rax
 105e78c:	48 8b 50 08          	mov    0x8(%rax),%rdx
 105e790:	49 89 f1             	mov    %rsi,%r9
 105e793:	49 c1 f9 3f          	sar    $0x3f,%r9
 105e797:	49 21 d1             	and    %rdx,%r9
 105e79a:	48 89 f1             	mov    %rsi,%rcx
 105e79d:	48 39 d6             	cmp    %rdx,%rsi
 105e7a0:	0f 83 92 11 00 00    	jae    105f938 <my.vm::run+0x2a88>
 105e7a6:	48 8d 78 20          	lea    0x20(%rax),%rdi
 105e7aa:	48 c1 e1 04          	shl    $0x4,%rcx
 105e7ae:	44 0f b6 44 08 20    	movzbl 0x20(%rax,%rcx,1),%r8d
 105e7b4:	48 8b 44 08 28       	mov    0x28(%rax,%rcx,1),%rax
 105e7b9:	41 83 f8 02          	cmp    $0x2,%r8d
 105e7bd:	0f 84 a2 09 00 00    	je     105f165 <my.vm::run+0x22b5>
 105e7c3:	41 83 f8 03          	cmp    $0x3,%r8d
 105e7c7:	0f 85 ec 09 00 00    	jne    105f1b9 <my.vm::run+0x2309>
 105e7cd:	4c 8b 13             	mov    (%rbx),%r10
 105e7d0:	49 8b 4a 08          	mov    0x8(%r10),%rcx
 105e7d4:	48 39 c8             	cmp    %rcx,%rax
 105e7d7:	0f 83 86 15 00 00    	jae    105fd63 <my.vm::run+0x2eb3>
 105e7dd:	49 89 c0             	mov    %rax,%r8
 105e7e0:	49 6b c0 38          	imul   $0x38,%r8,%rax
 105e7e4:	41 83 7c 02 20 01    	cmpl   $0x1,0x20(%r10,%rax,1)
 105e7ea:	0f 85 c9 09 00 00    	jne    105f1b9 <my.vm::run+0x2309>
 105e7f0:	48 89 f0             	mov    %rsi,%rax
 105e7f3:	48 ff c8             	dec    %rax
 105e7f6:	0f 80 7c 20 00 00    	jo     1060878 <my.vm::run+0x39c8>
 105e7fc:	49 89 c0             	mov    %rax,%r8
 105e7ff:	48 39 d0             	cmp    %rdx,%rax
 105e802:	0f 83 cc 15 00 00    	jae    105fdd4 <my.vm::run+0x2f24>
 105e808:	49 c1 e0 04          	shl    $0x4,%r8
 105e80c:	42 80 3c 07 03       	cmpb   $0x3,(%rdi,%r8,1)
 105e811:	0f 85 a2 09 00 00    	jne    105f1b9 <my.vm::run+0x2309>
 105e817:	4e 8b 44 07 08       	mov    0x8(%rdi,%r8,1),%r8
 105e81c:	49 39 c8             	cmp    %rcx,%r8
 105e81f:	0f 83 e5 15 00 00    	jae    105fe0a <my.vm::run+0x2f5a>
 105e825:	4d 89 c3             	mov    %r8,%r11
 105e828:	49 83 c2 20          	add    $0x20,%r10
 105e82c:	49 6b cb 38          	imul   $0x38,%r11,%rcx
 105e830:	41 83 3c 0a 01       	cmpl   $0x1,(%r10,%rcx,1)
 105e835:	0f 85 7e 09 00 00    	jne    105f1b9 <my.vm::run+0x2309>
 105e83b:	48 39 d6             	cmp    %rdx,%rsi
 105e83e:	0f 83 e1 15 00 00    	jae    105fe25 <my.vm::run+0x2f75>
 105e844:	49 89 f1             	mov    %rsi,%r9
 105e847:	49 c1 e1 04          	shl    $0x4,%r9
 105e84b:	42 0f b6 0c 0f       	movzbl (%rdi,%r9,1),%ecx
 105e850:	83 f9 03             	cmp    $0x3,%ecx
 105e853:	0f 85 6b 20 00 00    	jne    10608c4 <my.vm::run+0x3a14>
 105e859:	4a 8b 4c 0f 08       	mov    0x8(%rdi,%r9,1),%rcx
 105e85e:	48 39 d0             	cmp    %rdx,%rax
 105e861:	0f 83 cf 15 00 00    	jae    105fe36 <my.vm::run+0x2f86>
 105e867:	49 89 c0             	mov    %rax,%r8
 105e86a:	48 89 de             	mov    %rbx,%rsi
 105e86d:	49 c1 e0 04          	shl    $0x4,%r8
 105e871:	42 0f b6 04 07       	movzbl (%rdi,%r8,1),%eax
 105e876:	83 f8 03             	cmp    $0x3,%eax
 105e879:	0f 85 0a 20 00 00    	jne    1060889 <my.vm::run+0x39d9>
 105e87f:	4c 01 c7             	add    %r8,%rdi
 105e882:	48 8b 57 08          	mov    0x8(%rdi),%rdx
 105e886:	48 8d bc 24 00 03 00 	lea    0x300(%rsp),%rdi
 105e88d:	00 
 105e88e:	e8 ad 0b 01 00       	call   106f440 <my.lox_strings::concat>
 105e893:	48 8b 83 80 00 00 00 	mov    0x80(%rbx),%rax
 105e89a:	48 89 c6             	mov    %rax,%rsi
 105e89d:	48 ff ce             	dec    %rsi
 105e8a0:	0f 80 44 20 00 00    	jo     10608ea <my.vm::run+0x3a3a>
 105e8a6:	49 89 d9             	mov    %rbx,%r9
 105e8a9:	48 8b 84 24 00 03 00 	mov    0x300(%rsp),%rax
 105e8b0:	00 
 105e8b1:	48 8b 4b 78          	mov    0x78(%rbx),%rcx
 105e8b5:	48 8b 51 08          	mov    0x8(%rcx),%rdx
 105e8b9:	48 39 d6             	cmp    %rdx,%rsi
 105e8bc:	4d 89 eb             	mov    %r13,%r11
 105e8bf:	0f 83 8f 15 00 00    	jae    105fe54 <my.vm::run+0x2fa4>
 105e8c5:	48 89 f5             	mov    %rsi,%rbp
 105e8c8:	48 ff cd             	dec    %rbp
 105e8cb:	0f 80 08 20 00 00    	jo     10608d9 <my.vm::run+0x3a29>
 105e8d1:	48 89 ee             	mov    %rbp,%rsi
 105e8d4:	48 39 d5             	cmp    %rdx,%rbp
 105e8d7:	0f 83 92 15 00 00    	jae    105fe6f <my.vm::run+0x2fbf>
 105e8dd:	48 c1 e6 04          	shl    $0x4,%rsi
 105e8e1:	48 c7 44 31 20 03 00 	movq   $0x3,0x20(%rcx,%rsi,1)
 105e8e8:	00 00 
 105e8ea:	48 89 44 31 28       	mov    %rax,0x28(%rcx,%rsi,1)
 105e8ef:	e9 8a 09 00 00       	jmp    105f27e <my.vm::run+0x23ce>
 105e8f4:	48 8d 7c 24 70       	lea    0x70(%rsp),%rdi
 105e8f9:	4c 89 ce             	mov    %r9,%rsi
 105e8fc:	48 8b 54 24 10       	mov    0x10(%rsp),%rdx
 105e901:	4c 89 d9             	mov    %r11,%rcx
 105e904:	4d 89 f8             	mov    %r15,%r8
 105e907:	4d 89 cd             	mov    %r9,%r13
 105e90a:	4c 8b 4c 24 20       	mov    0x20(%rsp),%r9
 105e90f:	e8 6c 59 00 00       	call   1064280 <my.vm::read_constant>
 105e914:	0f b6 44 24 70       	movzbl 0x70(%rsp),%eax
 105e919:	83 f8 03             	cmp    $0x3,%eax
 105e91c:	0f 85 58 17 00 00    	jne    106007a <my.vm::run+0x31ca>
 105e922:	4c 8b a4 24 90 00 00 	mov    0x90(%rsp),%r12
 105e929:	00 
 105e92a:	4c 8b 7c 24 78       	mov    0x78(%rsp),%r15
 105e92f:	48 8b b4 24 88 00 00 	mov    0x88(%rsp),%rsi
 105e936:	00 
 105e937:	4c 89 ef             	mov    %r13,%rdi
 105e93a:	4c 89 e2             	mov    %r12,%rdx
 105e93d:	e8 ee c3 00 00       	call   106ad30 <my.heap::function_instruction>
 105e942:	4c 89 e1             	mov    %r12,%rcx
 105e945:	48 ff c1             	inc    %rcx
 105e948:	0f 80 e7 1c 00 00    	jo     1060635 <my.vm::run+0x3785>
 105e94e:	49 8b 95 88 00 00 00 	mov    0x88(%r13),%rdx
 105e955:	4d 85 f6             	test   %r14,%r14
 105e958:	7f 04                	jg     105e95e <my.vm::run+0x1aae>
 105e95a:	48 03 6a 08          	add    0x8(%rdx),%rbp
 105e95e:	4c 8d 25 eb 8a fa ff 	lea    -0x57515(%rip),%r12        # 1007450 <core_number_pairs+0x1f0>
 105e965:	48 c1 e5 05          	shl    $0x5,%rbp
 105e969:	48 89 4c 2a 30       	mov    %rcx,0x30(%rdx,%rbp,1)
 105e96e:	49 89 95 88 00 00 00 	mov    %rdx,0x88(%r13)
 105e975:	48 89 de             	mov    %rbx,%rsi
 105e978:	48 ff ce             	dec    %rsi
 105e97b:	0f 80 53 1c 00 00    	jo     10605d4 <my.vm::run+0x3724>
 105e981:	49 89 b5 80 00 00 00 	mov    %rsi,0x80(%r13)
 105e988:	49 8b 4d 78          	mov    0x78(%r13),%rcx
 105e98c:	48 8b 51 08          	mov    0x8(%rcx),%rdx
 105e990:	48 39 d6             	cmp    %rdx,%rsi
 105e993:	0f 83 6c 11 00 00    	jae    105fb05 <my.vm::run+0x2c55>
 105e999:	48 89 f7             	mov    %rsi,%rdi
 105e99c:	48 c1 e7 04          	shl    $0x4,%rdi
 105e9a0:	0f b6 54 39 20       	movzbl 0x20(%rcx,%rdi,1),%edx
 105e9a5:	83 fa 03             	cmp    $0x3,%edx
 105e9a8:	0f 85 97 17 00 00    	jne    1060145 <my.vm::run+0x3295>
 105e9ae:	48 01 f9             	add    %rdi,%rcx
 105e9b1:	48 83 c1 20          	add    $0x20,%rcx
 105e9b5:	48 8b 49 08          	mov    0x8(%rcx),%rcx
 105e9b9:	48 8d bc 24 58 05 00 	lea    0x558(%rsp),%rdi
 105e9c0:	00 
 105e9c1:	4c 89 ee             	mov    %r13,%rsi
 105e9c4:	48 8b 54 24 48       	mov    0x48(%rsp),%rdx
 105e9c9:	4d 89 f8             	mov    %r15,%r8
 105e9cc:	49 89 c1             	mov    %rax,%r9
 105e9cf:	e8 fc 66 00 00       	call   10650d0 <my.vm::invoke_from_class>
 105e9d4:	f6 84 24 58 05 00 00 	testb  $0x1,0x558(%rsp)
 105e9db:	01 
 105e9dc:	0f 84 b2 14 00 00    	je     105fe94 <my.vm::run+0x2fe4>
 105e9e2:	4d 8b 95 90 00 00 00 	mov    0x90(%r13),%r10
 105e9e9:	4c 89 d6             	mov    %r10,%rsi
 105e9ec:	48 ff ce             	dec    %rsi
 105e9ef:	0f 80 dd 1c 00 00    	jo     10606d2 <my.vm::run+0x3822>
 105e9f5:	4d 89 e9             	mov    %r13,%r9
 105e9f8:	49 8b ad 80 00 00 00 	mov    0x80(%r13),%rbp
 105e9ff:	49 8b 85 88 00 00 00 	mov    0x88(%r13),%rax
 105ea06:	48 8b 50 08          	mov    0x8(%rax),%rdx
 105ea0a:	48 39 d6             	cmp    %rdx,%rsi
 105ea0d:	0f 82 7d 04 00 00    	jb     105ee90 <my.vm::run+0x1fe0>
 105ea13:	48 89 f1             	mov    %rsi,%rcx
 105ea16:	48 c1 f9 3f          	sar    $0x3f,%rcx
 105ea1a:	48 21 d1             	and    %rdx,%rcx
 105ea1d:	48 01 f1             	add    %rsi,%rcx
 105ea20:	48 39 d1             	cmp    %rdx,%rcx
 105ea23:	0f 82 6a 04 00 00    	jb     105ee93 <my.vm::run+0x1fe3>
 105ea29:	e9 ae 20 00 00       	jmp    1060adc <my.vm::run+0x3c2c>
 105ea2e:	48 89 de             	mov    %rbx,%rsi
 105ea31:	48 ff ce             	dec    %rsi
 105ea34:	0f 80 63 18 00 00    	jo     106029d <my.vm::run+0x33ed>
 105ea3a:	4c 89 cf             	mov    %r9,%rdi
 105ea3d:	4c 89 cb             	mov    %r9,%rbx
 105ea40:	e8 ab 67 00 00       	call   10651f0 <my.vm::close_upvalues>
 105ea45:	48 8b b3 80 00 00 00 	mov    0x80(%rbx),%rsi
 105ea4c:	48 89 f5             	mov    %rsi,%rbp
 105ea4f:	48 ff cd             	dec    %rbp
 105ea52:	0f 80 b8 1b 00 00    	jo     1060610 <my.vm::run+0x3760>
 105ea58:	49 89 d9             	mov    %rbx,%r9
 105ea5b:	48 89 ab 80 00 00 00 	mov    %rbp,0x80(%rbx)
 105ea62:	48 8b 43 78          	mov    0x78(%rbx),%rax
 105ea66:	4c 8b 93 90 00 00 00 	mov    0x90(%rbx),%r10
 105ea6d:	48 8b 50 08          	mov    0x8(%rax),%rdx
 105ea71:	48 39 d5             	cmp    %rdx,%rbp
 105ea74:	4d 89 eb             	mov    %r13,%r11
 105ea77:	0f 82 13 0c 00 00    	jb     105f690 <my.vm::run+0x27e0>
 105ea7d:	48 89 e8             	mov    %rbp,%rax
 105ea80:	48 c1 f8 3f          	sar    $0x3f,%rax
 105ea84:	48 21 d0             	and    %rdx,%rax
 105ea87:	48 01 e8             	add    %rbp,%rax
 105ea8a:	48 39 d0             	cmp    %rdx,%rax
 105ea8d:	0f 82 fd 0b 00 00    	jb     105f690 <my.vm::run+0x27e0>
 105ea93:	e9 ef 1e 00 00       	jmp    1060987 <my.vm::run+0x3ad7>
 105ea98:	48 89 dd             	mov    %rbx,%rbp
 105ea9b:	48 ff cd             	dec    %rbp
 105ea9e:	0f 80 51 19 00 00    	jo     10603f5 <my.vm::run+0x3545>
 105eaa4:	49 89 a9 80 00 00 00 	mov    %rbp,0x80(%r9)
 105eaab:	49 8b 41 78          	mov    0x78(%r9),%rax
 105eaaf:	48 8b 50 08          	mov    0x8(%rax),%rdx
 105eab3:	48 89 e9             	mov    %rbp,%rcx
 105eab6:	48 c1 f9 3f          	sar    $0x3f,%rcx
 105eaba:	48 21 d1             	and    %rdx,%rcx
 105eabd:	48 89 ef             	mov    %rbp,%rdi
 105eac0:	48 39 d5             	cmp    %rdx,%rbp
 105eac3:	0f 83 81 0e 00 00    	jae    105f94a <my.vm::run+0x2a9a>
 105eac9:	48 c1 e7 04          	shl    $0x4,%rdi
 105eacd:	0f b6 54 38 20       	movzbl 0x20(%rax,%rdi,1),%edx
 105ead2:	85 d2                	test   %edx,%edx
 105ead4:	0f 84 f8 06 00 00    	je     105f1d2 <my.vm::run+0x2322>
 105eada:	83 fa 01             	cmp    $0x1,%edx
 105eadd:	0f 85 f3 06 00 00    	jne    105f1d6 <my.vm::run+0x2326>
 105eae3:	48 8d 14 38          	lea    (%rax,%rdi,1),%rdx
 105eae7:	48 83 c2 20          	add    $0x20,%rdx
 105eaeb:	0f b6 52 08          	movzbl 0x8(%rdx),%edx
 105eaef:	f6 d2                	not    %dl
 105eaf1:	80 e2 01             	and    $0x1,%dl
 105eaf4:	e9 df 06 00 00       	jmp    105f1d8 <my.vm::run+0x2328>
 105eaf9:	4c 89 cf             	mov    %r9,%rdi
 105eafc:	4c 89 de             	mov    %r11,%rsi
 105eaff:	4c 89 fa             	mov    %r15,%rdx
 105eb02:	4d 89 fd             	mov    %r15,%r13
 105eb05:	4d 89 cf             	mov    %r9,%r15
 105eb08:	e8 23 c2 00 00       	call   106ad30 <my.heap::function_instruction>
 105eb0d:	4c 89 e9             	mov    %r13,%rcx
 105eb10:	48 ff c1             	inc    %rcx
 105eb13:	0f 80 d2 19 00 00    	jo     10604eb <my.vm::run+0x363b>
 105eb19:	49 8b 97 88 00 00 00 	mov    0x88(%r15),%rdx
 105eb20:	4d 85 f6             	test   %r14,%r14
 105eb23:	4d 89 f9             	mov    %r15,%r9
 105eb26:	7f 04                	jg     105eb2c <my.vm::run+0x1c7c>
 105eb28:	48 03 6a 08          	add    0x8(%rdx),%rbp
 105eb2c:	48 c1 e5 05          	shl    $0x5,%rbp
 105eb30:	48 89 4c 2a 30       	mov    %rcx,0x30(%rdx,%rbp,1)
 105eb35:	49 89 91 88 00 00 00 	mov    %rdx,0x88(%r9)
 105eb3c:	48 89 d9             	mov    %rbx,%rcx
 105eb3f:	48 ff c9             	dec    %rcx
 105eb42:	0f 80 7b 19 00 00    	jo     10604c3 <my.vm::run+0x3613>
 105eb48:	48 89 ce             	mov    %rcx,%rsi
 105eb4b:	48 29 c6             	sub    %rax,%rsi
 105eb4e:	0f 80 49 19 00 00    	jo     106049d <my.vm::run+0x35ed>
 105eb54:	49 8b 49 78          	mov    0x78(%r9),%rcx
 105eb58:	48 8b 51 08          	mov    0x8(%rcx),%rdx
 105eb5c:	48 39 d6             	cmp    %rdx,%rsi
 105eb5f:	0f 83 19 0f 00 00    	jae    105fa7e <my.vm::run+0x2bce>
 105eb65:	48 89 f7             	mov    %rsi,%rdi
 105eb68:	48 c1 e7 04          	shl    $0x4,%rdi
 105eb6c:	4c 8b 44 39 28       	mov    0x28(%rcx,%rdi,1),%r8
 105eb71:	8b 4c 39 20          	mov    0x20(%rcx,%rdi,1),%ecx
 105eb75:	48 8b 54 24 68       	mov    0x68(%rsp),%rdx
 105eb7a:	48 89 14 24          	mov    %rdx,(%rsp)
 105eb7e:	48 8d bc 24 48 06 00 	lea    0x648(%rsp),%rdi
 105eb85:	00 
 105eb86:	4c 89 ce             	mov    %r9,%rsi
 105eb89:	48 8b 54 24 48       	mov    0x48(%rsp),%rdx
 105eb8e:	4c 89 cb             	mov    %r9,%rbx
 105eb91:	49 89 c1             	mov    %rax,%r9
 105eb94:	e8 07 5f 00 00       	call   1064aa0 <my.vm::call_value>
 105eb99:	f6 84 24 48 06 00 00 	testb  $0x1,0x648(%rsp)
 105eba0:	01 
 105eba1:	0f 84 ed 12 00 00    	je     105fe94 <my.vm::run+0x2fe4>
 105eba7:	4c 8b 93 90 00 00 00 	mov    0x90(%rbx),%r10
 105ebae:	4c 89 d6             	mov    %r10,%rsi
 105ebb1:	48 ff ce             	dec    %rsi
 105ebb4:	0f 80 2c 1b 00 00    	jo     10606e6 <my.vm::run+0x3836>
 105ebba:	49 89 d9             	mov    %rbx,%r9
 105ebbd:	48 8b ab 80 00 00 00 	mov    0x80(%rbx),%rbp
 105ebc4:	48 8b 83 88 00 00 00 	mov    0x88(%rbx),%rax
 105ebcb:	48 8b 50 08          	mov    0x8(%rax),%rdx
 105ebcf:	48 39 d6             	cmp    %rdx,%rsi
 105ebd2:	0f 82 b8 02 00 00    	jb     105ee90 <my.vm::run+0x1fe0>
 105ebd8:	48 89 f1             	mov    %rsi,%rcx
 105ebdb:	48 c1 f9 3f          	sar    $0x3f,%rcx
 105ebdf:	48 21 d1             	and    %rdx,%rcx
 105ebe2:	48 01 f1             	add    %rsi,%rcx
 105ebe5:	48 39 d1             	cmp    %rdx,%rcx
 105ebe8:	0f 82 a5 02 00 00    	jb     105ee93 <my.vm::run+0x1fe3>
 105ebee:	e9 be 1d 00 00       	jmp    10609b1 <my.vm::run+0x3b01>
 105ebf3:	4c 8d 64 24 70       	lea    0x70(%rsp),%r12
 105ebf8:	4c 89 e7             	mov    %r12,%rdi
 105ebfb:	4c 89 ce             	mov    %r9,%rsi
 105ebfe:	48 8b 54 24 10       	mov    0x10(%rsp),%rdx
 105ec03:	4c 89 d9             	mov    %r11,%rcx
 105ec06:	4d 89 f8             	mov    %r15,%r8
 105ec09:	4c 89 cb             	mov    %r9,%rbx
 105ec0c:	4c 8b 4c 24 20       	mov    0x20(%rsp),%r9
 105ec11:	e8 6a 56 00 00       	call   1064280 <my.vm::read_constant>
 105ec16:	0f b6 44 24 70       	movzbl 0x70(%rsp),%eax
 105ec1b:	83 f8 03             	cmp    $0x3,%eax
 105ec1e:	0f 85 73 14 00 00    	jne    1060097 <my.vm::run+0x31e7>
 105ec24:	4c 8b ac 24 90 00 00 	mov    0x90(%rsp),%r13
 105ec2b:	00 
 105ec2c:	4c 8b 7c 24 78       	mov    0x78(%rsp),%r15
 105ec31:	48 8b b4 24 88 00 00 	mov    0x88(%rsp),%rsi
 105ec38:	00 
 105ec39:	48 89 df             	mov    %rbx,%rdi
 105ec3c:	4c 89 ea             	mov    %r13,%rdx
 105ec3f:	e8 ec c0 00 00       	call   106ad30 <my.heap::function_instruction>
 105ec44:	4c 89 e9             	mov    %r13,%rcx
 105ec47:	48 ff c1             	inc    %rcx
 105ec4a:	0f 80 39 18 00 00    	jo     1060489 <my.vm::run+0x35d9>
 105ec50:	48 8b 93 88 00 00 00 	mov    0x88(%rbx),%rdx
 105ec57:	4d 85 f6             	test   %r14,%r14
 105ec5a:	49 89 d8             	mov    %rbx,%r8
 105ec5d:	7f 04                	jg     105ec63 <my.vm::run+0x1db3>
 105ec5f:	48 03 6a 08          	add    0x8(%rdx),%rbp
 105ec63:	48 c1 e5 05          	shl    $0x5,%rbp
 105ec67:	48 89 4c 2a 30       	mov    %rcx,0x30(%rdx,%rbp,1)
 105ec6c:	49 89 90 88 00 00 00 	mov    %rdx,0x88(%r8)
 105ec73:	49 8b 98 80 00 00 00 	mov    0x80(%r8),%rbx
 105ec7a:	48 89 d9             	mov    %rbx,%rcx
 105ec7d:	48 ff c9             	dec    %rcx
 105ec80:	0f 80 eb 19 00 00    	jo     1060671 <my.vm::run+0x37c1>
 105ec86:	48 89 ce             	mov    %rcx,%rsi
 105ec89:	48 29 c6             	sub    %rax,%rsi
 105ec8c:	0f 80 0b 19 00 00    	jo     106059d <my.vm::run+0x36ed>
 105ec92:	49 8b 68 78          	mov    0x78(%r8),%rbp
 105ec96:	48 8b 55 08          	mov    0x8(%rbp),%rdx
 105ec9a:	48 39 d6             	cmp    %rdx,%rsi
 105ec9d:	0f 83 7d 0e 00 00    	jae    105fb20 <my.vm::run+0x2c70>
 105eca3:	48 89 f1             	mov    %rsi,%rcx
 105eca6:	48 c1 e1 04          	shl    $0x4,%rcx
 105ecaa:	80 7c 0d 20 03       	cmpb   $0x3,0x20(%rbp,%rcx,1)
 105ecaf:	0f 85 7e 01 00 00    	jne    105ee33 <my.vm::run+0x1f83>
 105ecb5:	4c 8b 6c 0d 28       	mov    0x28(%rbp,%rcx,1),%r13
 105ecba:	49 8b 08             	mov    (%r8),%rcx
 105ecbd:	48 8b 51 08          	mov    0x8(%rcx),%rdx
 105ecc1:	4c 89 ee             	mov    %r13,%rsi
 105ecc4:	49 39 d5             	cmp    %rdx,%r13
 105ecc7:	0f 83 0a 10 00 00    	jae    105fcd7 <my.vm::run+0x2e27>
 105eccd:	48 6b d6 38          	imul   $0x38,%rsi,%rdx
 105ecd1:	83 7c 11 20 07       	cmpl   $0x7,0x20(%rcx,%rdx,1)
 105ecd6:	0f 85 57 01 00 00    	jne    105ee33 <my.vm::run+0x1f83>
 105ecdc:	48 89 44 24 20       	mov    %rax,0x20(%rsp)
 105ece1:	4c 89 c7             	mov    %r8,%rdi
 105ece4:	4c 89 fe             	mov    %r15,%rsi
 105ece7:	4d 89 c6             	mov    %r8,%r14
 105ecea:	e8 71 c2 00 00       	call   106af60 <my.heap::string_hash>
 105ecef:	4c 89 f7             	mov    %r14,%rdi
 105ecf2:	4c 89 ee             	mov    %r13,%rsi
 105ecf5:	4c 89 fa             	mov    %r15,%rdx
 105ecf8:	89 c1                	mov    %eax,%ecx
 105ecfa:	e8 41 c7 00 00       	call   106b440 <my.heap::instance_field>
 105ecff:	3c 01                	cmp    $0x1,%al
 105ed01:	0f 85 70 06 00 00    	jne    105f377 <my.vm::run+0x24c7>
 105ed07:	48 89 d8             	mov    %rbx,%rax
 105ed0a:	4c 8b 4c 24 20       	mov    0x20(%rsp),%r9
 105ed0f:	4c 29 c8             	sub    %r9,%rax
 105ed12:	0f 80 9a 1b 00 00    	jo     10608b2 <my.vm::run+0x3a02>
 105ed18:	48 89 c6             	mov    %rax,%rsi
 105ed1b:	48 ff ce             	dec    %rsi
 105ed1e:	0f 80 7a 1b 00 00    	jo     106089e <my.vm::run+0x39ee>
 105ed24:	49 89 c8             	mov    %rcx,%r8
 105ed27:	48 8b 45 08          	mov    0x8(%rbp),%rax
 105ed2b:	48 39 c6             	cmp    %rax,%rsi
 105ed2e:	0f 83 bb 10 00 00    	jae    105fdef <my.vm::run+0x2f3f>
 105ed34:	48 89 f1             	mov    %rsi,%rcx
 105ed37:	48 83 c5 20          	add    $0x20,%rbp
 105ed3b:	48 c1 e1 04          	shl    $0x4,%rcx
 105ed3f:	0f b6 c2             	movzbl %dl,%eax
 105ed42:	48 89 44 0d 00       	mov    %rax,0x0(%rbp,%rcx,1)
 105ed47:	4c 89 44 0d 08       	mov    %r8,0x8(%rbp,%rcx,1)
 105ed4c:	48 8b 44 24 68       	mov    0x68(%rsp),%rax
 105ed51:	48 89 04 24          	mov    %rax,(%rsp)
 105ed55:	0f b6 ca             	movzbl %dl,%ecx
 105ed58:	4c 8d 64 24 70       	lea    0x70(%rsp),%r12
 105ed5d:	4c 89 e7             	mov    %r12,%rdi
 105ed60:	4c 89 f6             	mov    %r14,%rsi
 105ed63:	48 8b 54 24 48       	mov    0x48(%rsp),%rdx
 105ed68:	e8 33 5d 00 00       	call   1064aa0 <my.vm::call_value>
 105ed6d:	41 f6 04 24 01       	testb  $0x1,(%r12)
 105ed72:	0f 85 e0 00 00 00    	jne    105ee58 <my.vm::run+0x1fa8>
 105ed78:	e9 17 11 00 00       	jmp    105fe94 <my.vm::run+0x2fe4>
 105ed7d:	49 8b b1 80 00 00 00 	mov    0x80(%r9),%rsi
 105ed84:	48 89 f5             	mov    %rsi,%rbp
 105ed87:	48 ff cd             	dec    %rbp
 105ed8a:	0f 80 fc 17 00 00    	jo     106058c <my.vm::run+0x36dc>
 105ed90:	49 8b 41 78          	mov    0x78(%r9),%rax
 105ed94:	48 8b 50 08          	mov    0x8(%rax),%rdx
 105ed98:	48 89 e9             	mov    %rbp,%rcx
 105ed9b:	48 39 d5             	cmp    %rdx,%rbp
 105ed9e:	0f 83 b8 0b 00 00    	jae    105f95c <my.vm::run+0x2aac>
 105eda4:	48 c1 e1 04          	shl    $0x4,%rcx
 105eda8:	80 7c 08 20 02       	cmpb   $0x2,0x20(%rax,%rcx,1)
 105edad:	0f 85 07 01 00 00    	jne    105eeba <my.vm::run+0x200a>
 105edb3:	48 01 c8             	add    %rcx,%rax
 105edb6:	48 83 c0 20          	add    $0x20,%rax
 105edba:	48 c7 00 02 00 00 00 	movq   $0x2,(%rax)
 105edc1:	80 70 0f 80          	xorb   $0x80,0xf(%rax)
 105edc5:	e9 b4 04 00 00       	jmp    105f27e <my.vm::run+0x23ce>
 105edca:	48 89 dd             	mov    %rbx,%rbp
 105edcd:	e9 be 08 00 00       	jmp    105f690 <my.vm::run+0x27e0>
 105edd2:	4c 89 7c 24 40       	mov    %r15,0x40(%rsp)
 105edd7:	48 8d 0d a2 42 fb ff 	lea    -0x4bd5e(%rip),%rcx        # 1013080 <core_number_pairs+0xbe20>
 105edde:	48 8d 9c 24 00 03 00 	lea    0x300(%rsp),%rbx
 105ede5:	00 
 105ede6:	48 89 df             	mov    %rbx,%rdi
 105ede9:	4d 89 cf             	mov    %r9,%r15
 105edec:	4c 89 ce             	mov    %r9,%rsi
 105edef:	48 8b 54 24 48       	mov    0x48(%rsp),%rdx
 105edf4:	e8 a7 4f 00 00       	call   1063da0 <my.vm::runtime_error>
 105edf9:	f6 03 01             	testb  $0x1,(%rbx)
 105edfc:	4c 8d 25 4d 86 fa ff 	lea    -0x579b3(%rip),%r12        # 1007450 <core_number_pairs+0x1f0>
 105ee03:	0f 84 8b 10 00 00    	je     105fe94 <my.vm::run+0x2fe4>
 105ee09:	4d 89 f9             	mov    %r15,%r9
 105ee0c:	49 8b af 80 00 00 00 	mov    0x80(%r15),%rbp
 105ee13:	4d 8b 97 90 00 00 00 	mov    0x90(%r15),%r10
 105ee1a:	4d 89 eb             	mov    %r13,%r11
 105ee1d:	4c 8b 7c 24 40       	mov    0x40(%rsp),%r15
 105ee22:	e9 69 08 00 00       	jmp    105f690 <my.vm::run+0x27e0>
 105ee27:	48 8d 0d 52 44 fb ff 	lea    -0x4bbae(%rip),%rcx        # 1013280 <core_number_pairs+0xc020>
 105ee2e:	e9 20 e2 ff ff       	jmp    105d053 <my.vm::run+0x1a3>
 105ee33:	48 8d 0d 06 44 fb ff 	lea    -0x4bbfa(%rip),%rcx        # 1013240 <core_number_pairs+0xbfe0>
 105ee3a:	4c 89 e7             	mov    %r12,%rdi
 105ee3d:	4d 89 c6             	mov    %r8,%r14
 105ee40:	4c 89 c6             	mov    %r8,%rsi
 105ee43:	48 8b 54 24 48       	mov    0x48(%rsp),%rdx
 105ee48:	e8 53 4f 00 00       	call   1063da0 <my.vm::runtime_error>
 105ee4d:	41 f6 04 24 01       	testb  $0x1,(%r12)
 105ee52:	0f 84 3c 10 00 00    	je     105fe94 <my.vm::run+0x2fe4>
 105ee58:	4d 8b 96 90 00 00 00 	mov    0x90(%r14),%r10
 105ee5f:	4c 89 d6             	mov    %r10,%rsi
 105ee62:	48 ff ce             	dec    %rsi
 105ee65:	0f 80 8f 18 00 00    	jo     10606fa <my.vm::run+0x384a>
 105ee6b:	4d 89 f1             	mov    %r14,%r9
 105ee6e:	49 8b ae 80 00 00 00 	mov    0x80(%r14),%rbp
 105ee75:	49 8b 86 88 00 00 00 	mov    0x88(%r14),%rax
 105ee7c:	48 8b 50 08          	mov    0x8(%rax),%rdx
 105ee80:	48 39 d6             	cmp    %rdx,%rsi
 105ee83:	4c 8d 25 c6 85 fa ff 	lea    -0x57a3a(%rip),%r12        # 1007450 <core_number_pairs+0x1f0>
 105ee8a:	0f 83 39 0d 00 00    	jae    105fbc9 <my.vm::run+0x2d19>
 105ee90:	48 89 f1             	mov    %rsi,%rcx
 105ee93:	48 c1 e1 05          	shl    $0x5,%rcx
 105ee97:	48 8b 54 08 20       	mov    0x20(%rax,%rcx,1),%rdx
 105ee9c:	48 89 54 24 10       	mov    %rdx,0x10(%rsp)
 105eea1:	4c 8b 5c 08 28       	mov    0x28(%rax,%rcx,1),%r11
 105eea6:	4c 8b 7c 08 30       	mov    0x30(%rax,%rcx,1),%r15
 105eeab:	48 8b 44 08 38       	mov    0x38(%rax,%rcx,1),%rax
 105eeb0:	48 89 44 24 20       	mov    %rax,0x20(%rsp)
 105eeb5:	e9 d6 07 00 00       	jmp    105f690 <my.vm::run+0x27e0>
 105eeba:	48 8d 0d df 42 fb ff 	lea    -0x4bd21(%rip),%rcx        # 10131a0 <core_number_pairs+0xbf40>
 105eec1:	e9 8d e1 ff ff       	jmp    105d053 <my.vm::run+0x1a3>
 105eec6:	4c 89 f7             	mov    %r14,%rdi
 105eec9:	48 89 de             	mov    %rbx,%rsi
 105eecc:	e8 7f bd 00 00       	call   106ac50 <my.heap::string_chars>
 105eed1:	48 89 c3             	mov    %rax,%rbx
 105eed4:	48 8d 3d 25 41 fb ff 	lea    -0x4bedb(%rip),%rdi        # 1013000 <core_number_pairs+0xbda0>
 105eedb:	48 89 c6             	mov    %rax,%rsi
 105eede:	e8 1d 0d fd ff       	call   102fc00 <myl_core_bytes_concat>
 105eee3:	49 89 c4             	mov    %rax,%r12
 105eee6:	48 89 df             	mov    %rbx,%rdi
 105eee9:	e8 12 59 fc ff       	call   1024800 <myl_core_drop_owned>
 105eeee:	48 8d 35 4b 41 fb ff 	lea    -0x4beb5(%rip),%rsi        # 1013040 <core_number_pairs+0xbde0>
 105eef5:	4c 89 e7             	mov    %r12,%rdi
 105eef8:	e8 03 0d fd ff       	call   102fc00 <myl_core_bytes_concat>
 105eefd:	48 89 c3             	mov    %rax,%rbx
 105ef00:	4c 89 e7             	mov    %r12,%rdi
 105ef03:	e8 f8 58 fc ff       	call   1024800 <myl_core_drop_owned>
 105ef08:	48 8d 7c 24 70       	lea    0x70(%rsp),%rdi
 105ef0d:	4c 89 f6             	mov    %r14,%rsi
 105ef10:	48 8b 54 24 48       	mov    0x48(%rsp),%rdx
 105ef15:	48 89 d9             	mov    %rbx,%rcx
 105ef18:	e8 83 4e 00 00       	call   1063da0 <my.vm::runtime_error>
 105ef1d:	48 89 df             	mov    %rbx,%rdi
 105ef20:	e8 db 58 fc ff       	call   1024800 <myl_core_drop_owned>
 105ef25:	f6 44 24 70 01       	testb  $0x1,0x70(%rsp)
 105ef2a:	0f 84 64 0f 00 00    	je     105fe94 <my.vm::run+0x2fe4>
 105ef30:	49 8b 86 80 00 00 00 	mov    0x80(%r14),%rax
 105ef37:	4d 8b 96 90 00 00 00 	mov    0x90(%r14),%r10
 105ef3e:	4c 8d 25 0b 85 fa ff 	lea    -0x57af5(%rip),%r12        # 1007450 <core_number_pairs+0x1f0>
 105ef45:	49 89 eb             	mov    %rbp,%r11
 105ef48:	48 89 c5             	mov    %rax,%rbp
 105ef4b:	4d 89 f1             	mov    %r14,%r9
 105ef4e:	e9 3d 07 00 00       	jmp    105f690 <my.vm::run+0x27e0>
 105ef53:	49 8b a9 80 00 00 00 	mov    0x80(%r9),%rbp
 105ef5a:	4d 8b 91 90 00 00 00 	mov    0x90(%r9),%r10
 105ef61:	4c 8d 25 e8 84 fa ff 	lea    -0x57b18(%rip),%r12        # 1007450 <core_number_pairs+0x1f0>
 105ef68:	4c 8b 5c 24 18       	mov    0x18(%rsp),%r11
 105ef6d:	e9 1e 07 00 00       	jmp    105f690 <my.vm::run+0x27e0>
 105ef72:	84 d2                	test   %dl,%dl
 105ef74:	0f 85 80 18 00 00    	jne    10607fa <my.vm::run+0x394a>
 105ef7a:	4d 89 eb             	mov    %r13,%r11
 105ef7d:	4c 8b 84 24 08 04 00 	mov    0x408(%rsp),%r8
 105ef84:	00 
 105ef85:	48 8b 57 08          	mov    0x8(%rdi),%rdx
 105ef89:	48 39 d6             	cmp    %rdx,%rsi
 105ef8c:	0f 83 9b 0d 00 00    	jae    105fd2d <my.vm::run+0x2e7d>
 105ef92:	48 89 f0             	mov    %rsi,%rax
 105ef95:	48 c1 e0 04          	shl    $0x4,%rax
 105ef99:	c5 f9 10 44 07 20    	vmovupd 0x20(%rdi,%rax,1),%xmm0
 105ef9f:	49 8b 31             	mov    (%r9),%rsi
 105efa2:	48 8b 56 08          	mov    0x8(%rsi),%rdx
 105efa6:	4d 89 ca             	mov    %r9,%r10
 105efa9:	48 39 d3             	cmp    %rdx,%rbx
 105efac:	0f 83 96 0d 00 00    	jae    105fd48 <my.vm::run+0x2e98>
 105efb2:	48 89 d8             	mov    %rbx,%rax
 105efb5:	4c 6b c8 38          	imul   $0x38,%rax,%r9
 105efb9:	42 0f b6 54 0e 20    	movzbl 0x20(%rsi,%r9,1),%edx
 105efbf:	4a 8b 44 0e 28       	mov    0x28(%rsi,%r9,1),%rax
 105efc4:	4a 8b 7c 0e 30       	mov    0x30(%rsi,%r9,1),%rdi
 105efc9:	4a 8b 4c 0e 38       	mov    0x38(%rsi,%r9,1),%rcx
 105efce:	4e 8b 7c 0e 40       	mov    0x40(%rsi,%r9,1),%r15
 105efd3:	4a 8b 5c 0e 48       	mov    0x48(%rsi,%r9,1),%rbx
 105efd8:	4a c7 44 0e 20 05 00 	movq   $0x5,0x20(%rsi,%r9,1)
 105efdf:	00 00 
 105efe1:	4a c7 44 0e 28 ff ff 	movq   $0xffffffffffffffff,0x28(%rsi,%r9,1)
 105efe8:	ff ff 
 105efea:	c5 f9 54 05 ee 53 fa 	vandpd -0x5ac12(%rip),%xmm0,%xmm0        # 10043e0 <__anon_2214+0xb0>
 105eff1:	ff 
 105eff2:	c4 a1 79 11 44 0e 30 	vmovupd %xmm0,0x30(%rsi,%r9,1)
 105eff9:	4e 89 44 0e 40       	mov    %r8,0x40(%rsi,%r9,1)
 105effe:	ff ca                	dec    %edx
 105f000:	83 fa 08             	cmp    $0x8,%edx
 105f003:	4d 89 d1             	mov    %r10,%r9
 105f006:	77 1e                	ja     105f026 <my.vm::run+0x2176>
 105f008:	48 8d 35 a1 85 fa ff 	lea    -0x57a5f(%rip),%rsi        # 10075b0 <core_number_pairs+0x350>
 105f00f:	48 63 14 96          	movslq (%rsi,%rdx,4),%rdx
 105f013:	48 01 f2             	add    %rsi,%rdx
 105f016:	ff e2                	jmp    *%rdx
 105f018:	4c 89 cb             	mov    %r9,%rbx
 105f01b:	e8 e0 57 fc ff       	call   1024800 <myl_core_drop_owned>
 105f020:	49 89 d9             	mov    %rbx,%r9
 105f023:	4d 89 eb             	mov    %r13,%r11
 105f026:	49 8b a9 80 00 00 00 	mov    0x80(%r9),%rbp
 105f02d:	eb 56                	jmp    105f085 <my.vm::run+0x21d5>
 105f02f:	48 8b 84 24 d0 02 00 	mov    0x2d0(%rsp),%rax
 105f036:	00 
 105f037:	0f b6 bc 24 c8 02 00 	movzbl 0x2c8(%rsp),%edi
 105f03e:	00 
 105f03f:	48 8b 4b 78          	mov    0x78(%rbx),%rcx
 105f043:	48 8b b3 80 00 00 00 	mov    0x80(%rbx),%rsi
 105f04a:	48 8b 51 08          	mov    0x8(%rcx),%rdx
 105f04e:	49 89 f0             	mov    %rsi,%r8
 105f051:	48 39 d6             	cmp    %rdx,%rsi
 105f054:	4d 89 eb             	mov    %r13,%r11
 105f057:	49 89 d9             	mov    %rbx,%r9
 105f05a:	0f 83 b2 0c 00 00    	jae    105fd12 <my.vm::run+0x2e62>
 105f060:	49 c1 e0 04          	shl    $0x4,%r8
 105f064:	40 0f b6 d7          	movzbl %dil,%edx
 105f068:	4a 89 54 01 20       	mov    %rdx,0x20(%rcx,%r8,1)
 105f06d:	4a 89 44 01 28       	mov    %rax,0x28(%rcx,%r8,1)
 105f072:	48 89 f5             	mov    %rsi,%rbp
 105f075:	48 ff c5             	inc    %rbp
 105f078:	0f 80 90 17 00 00    	jo     106080e <my.vm::run+0x395e>
 105f07e:	49 89 a9 80 00 00 00 	mov    %rbp,0x80(%r9)
 105f085:	4d 8b 91 90 00 00 00 	mov    0x90(%r9),%r10
 105f08c:	4d 89 e7             	mov    %r12,%r15
 105f08f:	e9 ee 05 00 00       	jmp    105f682 <my.vm::run+0x27d2>
 105f094:	4c 8b 5c 24 18       	mov    0x18(%rsp),%r11
 105f099:	49 89 de             	mov    %rbx,%r14
 105f09c:	49 8b 0e             	mov    (%r14),%rcx
 105f09f:	48 8b 51 08          	mov    0x8(%rcx),%rdx
 105f0a3:	48 8b 74 24 60       	mov    0x60(%rsp),%rsi
 105f0a8:	48 39 d6             	cmp    %rdx,%rsi
 105f0ab:	0f 83 e5 0a 00 00    	jae    105fb96 <my.vm::run+0x2ce6>
 105f0b1:	48 89 f0             	mov    %rsi,%rax
 105f0b4:	4c 6b c0 38          	imul   $0x38,%rax,%r8
 105f0b8:	42 0f b6 54 01 20    	movzbl 0x20(%rcx,%r8,1),%edx
 105f0be:	4a 8b 7c 01 28       	mov    0x28(%rcx,%r8,1),%rdi
 105f0c3:	4a 8b 74 01 30       	mov    0x30(%rcx,%r8,1),%rsi
 105f0c8:	4a 8b 44 01 38       	mov    0x38(%rcx,%r8,1),%rax
 105f0cd:	4e 8b 64 01 40       	mov    0x40(%rcx,%r8,1),%r12
 105f0d2:	4e 8b 74 01 48       	mov    0x48(%rcx,%r8,1),%r14
 105f0d7:	4a c7 44 01 20 04 00 	movq   $0x4,0x20(%rcx,%r8,1)
 105f0de:	00 00 
 105f0e0:	4c 8b 4c 24 58       	mov    0x58(%rsp),%r9
 105f0e5:	4e 89 4c 01 28       	mov    %r9,0x28(%rcx,%r8,1)
 105f0ea:	4a 89 6c 01 30       	mov    %rbp,0x30(%rcx,%r8,1)
 105f0ef:	83 fa 09             	cmp    $0x9,%edx
 105f0f2:	77 17                	ja     105f10b <my.vm::run+0x225b>
 105f0f4:	b9 d0 02 00 00       	mov    $0x2d0,%ecx
 105f0f9:	0f a3 d1             	bt     %edx,%ecx
 105f0fc:	73 48                	jae    105f146 <my.vm::run+0x2296>
 105f0fe:	48 89 f7             	mov    %rsi,%rdi
 105f101:	e8 fa 56 fc ff       	call   1024800 <myl_core_drop_owned>
 105f106:	4c 8b 5c 24 18       	mov    0x18(%rsp),%r11
 105f10b:	4c 8b 4c 24 50       	mov    0x50(%rsp),%r9
 105f110:	49 8b a9 80 00 00 00 	mov    0x80(%r9),%rbp
 105f117:	e9 5f 05 00 00       	jmp    105f67b <my.vm::run+0x27cb>
 105f11c:	48 89 f0             	mov    %rsi,%rax
 105f11f:	83 fa 01             	cmp    $0x1,%edx
 105f122:	0f 84 9a e2 ff ff    	je     105d3c2 <my.vm::run+0x512>
 105f128:	83 fa 02             	cmp    $0x2,%edx
 105f12b:	0f 85 9e e2 ff ff    	jne    105d3cf <my.vm::run+0x51f>
 105f131:	e8 ca 56 fc ff       	call   1024800 <myl_core_drop_owned>
 105f136:	48 89 ef             	mov    %rbp,%rdi
 105f139:	e8 c2 56 fc ff       	call   1024800 <myl_core_drop_owned>
 105f13e:	4c 89 f0             	mov    %r14,%rax
 105f141:	e9 7c e2 ff ff       	jmp    105d3c2 <my.vm::run+0x512>
 105f146:	83 fa 01             	cmp    $0x1,%edx
 105f149:	74 b6                	je     105f101 <my.vm::run+0x2251>
 105f14b:	83 fa 02             	cmp    $0x2,%edx
 105f14e:	75 bb                	jne    105f10b <my.vm::run+0x225b>
 105f150:	48 89 c7             	mov    %rax,%rdi
 105f153:	e8 a8 56 fc ff       	call   1024800 <myl_core_drop_owned>
 105f158:	4c 89 e7             	mov    %r12,%rdi
 105f15b:	e8 a0 56 fc ff       	call   1024800 <myl_core_drop_owned>
 105f160:	4c 89 f7             	mov    %r14,%rdi
 105f163:	eb 9c                	jmp    105f101 <my.vm::run+0x2251>
 105f165:	48 89 f5             	mov    %rsi,%rbp
 105f168:	48 ff cd             	dec    %rbp
 105f16b:	0f 80 ae 16 00 00    	jo     106081f <my.vm::run+0x396f>
 105f171:	48 89 e9             	mov    %rbp,%rcx
 105f174:	48 39 d5             	cmp    %rdx,%rbp
 105f177:	0f 83 01 0c 00 00    	jae    105fd7e <my.vm::run+0x2ece>
 105f17d:	48 c1 e1 04          	shl    $0x4,%rcx
 105f181:	80 3c 0f 02          	cmpb   $0x2,(%rdi,%rcx,1)
 105f185:	75 32                	jne    105f1b9 <my.vm::run+0x2309>
 105f187:	48 01 cf             	add    %rcx,%rdi
 105f18a:	c4 e1 f9 6e c0       	vmovq  %rax,%xmm0
 105f18f:	c5 fb 58 47 08       	vaddsd 0x8(%rdi),%xmm0,%xmm0
 105f194:	48 c7 07 02 00 00 00 	movq   $0x2,(%rdi)
 105f19b:	c5 fb 11 47 08       	vmovsd %xmm0,0x8(%rdi)
 105f1a0:	48 ff c5             	inc    %rbp
 105f1a3:	49 89 d9             	mov    %rbx,%r9
 105f1a6:	48 89 ab 80 00 00 00 	mov    %rbp,0x80(%rbx)
 105f1ad:	4c 8b 93 90 00 00 00 	mov    0x90(%rbx),%r10
 105f1b4:	e9 d7 04 00 00       	jmp    105f690 <my.vm::run+0x27e0>
 105f1b9:	48 8d 0d 80 3f fb ff 	lea    -0x4c080(%rip),%rcx        # 1013140 <core_number_pairs+0xbee0>
 105f1c0:	48 8d 7c 24 70       	lea    0x70(%rsp),%rdi
 105f1c5:	48 89 de             	mov    %rbx,%rsi
 105f1c8:	48 8b 54 24 48       	mov    0x48(%rsp),%rdx
 105f1cd:	e9 91 de ff ff       	jmp    105d063 <my.vm::run+0x1b3>
 105f1d2:	b2 01                	mov    $0x1,%dl
 105f1d4:	eb 02                	jmp    105f1d8 <my.vm::run+0x2328>
 105f1d6:	31 d2                	xor    %edx,%edx
 105f1d8:	48 8d 78 20          	lea    0x20(%rax),%rdi
 105f1dc:	49 89 e8             	mov    %rbp,%r8
 105f1df:	49 c1 e0 04          	shl    $0x4,%r8
 105f1e3:	49 01 f8             	add    %rdi,%r8
 105f1e6:	48 c1 e1 04          	shl    $0x4,%rcx
 105f1ea:	4a c7 04 01 01 00 00 	movq   $0x1,(%rcx,%r8,1)
 105f1f1:	00 
 105f1f2:	42 88 54 01 08       	mov    %dl,0x8(%rcx,%r8,1)
 105f1f7:	e9 31 01 00 00       	jmp    105f32d <my.vm::run+0x247d>
 105f1fc:	41 80 f8 01          	cmp    $0x1,%r8b
 105f200:	49 89 d9             	mov    %rbx,%r9
 105f203:	0f 85 09 01 00 00    	jne    105f312 <my.vm::run+0x2462>
 105f209:	31 fe                	xor    %edi,%esi
 105f20b:	40 80 f6 01          	xor    $0x1,%sil
 105f20f:	e9 07 01 00 00       	jmp    105f31b <my.vm::run+0x246b>
 105f214:	41 80 f8 02          	cmp    $0x2,%r8b
 105f218:	0f 85 f8 00 00 00    	jne    105f316 <my.vm::run+0x2466>
 105f21e:	c4 e1 f9 6e c6       	vmovq  %rsi,%xmm0
 105f223:	c4 e1 f9 6e cf       	vmovq  %rdi,%xmm1
 105f228:	c5 fb c2 c1 00       	vcmpeqsd %xmm1,%xmm0,%xmm0
 105f22d:	c4 e1 f9 7e c6       	vmovq  %xmm0,%rsi
 105f232:	83 e6 01             	and    $0x1,%esi
 105f235:	e9 de 00 00 00       	jmp    105f318 <my.vm::run+0x2468>
 105f23a:	41 80 f8 03          	cmp    $0x3,%r8b
 105f23e:	41 0f 94 c0          	sete   %r8b
 105f242:	48 39 fe             	cmp    %rdi,%rsi
 105f245:	40 0f 94 c6          	sete   %sil
 105f249:	44 20 c6             	and    %r8b,%sil
 105f24c:	e9 c7 00 00 00       	jmp    105f318 <my.vm::run+0x2468>
 105f251:	c5 f3 5c c0          	vsubsd %xmm0,%xmm1,%xmm0
 105f255:	eb 1b                	jmp    105f272 <my.vm::run+0x23c2>
 105f257:	c5 f9 2e c1          	vucomisd %xmm1,%xmm0
 105f25b:	48 c7 01 01 00 00 00 	movq   $0x1,(%rcx)
 105f262:	0f 97 41 08          	seta   0x8(%rcx)
 105f266:	eb 16                	jmp    105f27e <my.vm::run+0x23ce>
 105f268:	c5 fb 59 c1          	vmulsd %xmm1,%xmm0,%xmm0
 105f26c:	eb 04                	jmp    105f272 <my.vm::run+0x23c2>
 105f26e:	c5 f3 5e c0          	vdivsd %xmm0,%xmm1,%xmm0
 105f272:	48 c7 01 02 00 00 00 	movq   $0x2,(%rcx)
 105f279:	c5 fb 11 41 08       	vmovsd %xmm0,0x8(%rcx)
 105f27e:	48 ff c5             	inc    %rbp
 105f281:	49 89 a9 80 00 00 00 	mov    %rbp,0x80(%r9)
 105f288:	4d 8b 91 90 00 00 00 	mov    0x90(%r9),%r10
 105f28f:	e9 fc 03 00 00       	jmp    105f690 <my.vm::run+0x27e0>
 105f294:	48 8b bc 24 78 01 00 	mov    0x178(%rsp),%rdi
 105f29b:	00 
 105f29c:	e9 52 e3 ff ff       	jmp    105d5f3 <my.vm::run+0x743>
 105f2a1:	48 8b bc 24 88 01 00 	mov    0x188(%rsp),%rdi
 105f2a8:	00 
 105f2a9:	48 8b 9c 24 90 01 00 	mov    0x190(%rsp),%rbx
 105f2b0:	00 
 105f2b1:	4c 8b b4 24 98 01 00 	mov    0x198(%rsp),%r14
 105f2b8:	00 
 105f2b9:	e8 42 55 fc ff       	call   1024800 <myl_core_drop_owned>
 105f2be:	48 89 df             	mov    %rbx,%rdi
 105f2c1:	e8 3a 55 fc ff       	call   1024800 <myl_core_drop_owned>
 105f2c6:	4c 89 f7             	mov    %r14,%rdi
 105f2c9:	4c 8b 74 24 50       	mov    0x50(%rsp),%r14
 105f2ce:	e9 20 e3 ff ff       	jmp    105d5f3 <my.vm::run+0x743>
 105f2d3:	48 8b bc 24 b0 01 00 	mov    0x1b0(%rsp),%rdi
 105f2da:	00 
 105f2db:	e9 22 f1 ff ff       	jmp    105e402 <my.vm::run+0x1552>
 105f2e0:	48 8b bc 24 c0 01 00 	mov    0x1c0(%rsp),%rdi
 105f2e7:	00 
 105f2e8:	48 8b 9c 24 c8 01 00 	mov    0x1c8(%rsp),%rbx
 105f2ef:	00 
 105f2f0:	4c 8b b4 24 d0 01 00 	mov    0x1d0(%rsp),%r14
 105f2f7:	00 
 105f2f8:	e8 03 55 fc ff       	call   1024800 <myl_core_drop_owned>
 105f2fd:	48 89 df             	mov    %rbx,%rdi
 105f300:	e8 fb 54 fc ff       	call   1024800 <myl_core_drop_owned>
 105f305:	4c 89 f7             	mov    %r14,%rdi
 105f308:	48 8b 5c 24 50       	mov    0x50(%rsp),%rbx
 105f30d:	e9 f0 f0 ff ff       	jmp    105e402 <my.vm::run+0x1552>
 105f312:	31 f6                	xor    %esi,%esi
 105f314:	eb 05                	jmp    105f31b <my.vm::run+0x246b>
 105f316:	31 f6                	xor    %esi,%esi
 105f318:	49 89 d9             	mov    %rbx,%r9
 105f31b:	48 01 ca             	add    %rcx,%rdx
 105f31e:	48 c7 02 01 00 00 00 	movq   $0x1,(%rdx)
 105f325:	40 80 e6 01          	and    $0x1,%sil
 105f329:	40 88 72 08          	mov    %sil,0x8(%rdx)
 105f32d:	49 89 41 78          	mov    %rax,0x78(%r9)
 105f331:	48 ff c5             	inc    %rbp
 105f334:	49 89 a9 80 00 00 00 	mov    %rbp,0x80(%r9)
 105f33b:	e9 50 03 00 00       	jmp    105f690 <my.vm::run+0x27e0>
 105f340:	4c 89 7c 24 40       	mov    %r15,0x40(%rsp)
 105f345:	4c 89 f7             	mov    %r14,%rdi
 105f348:	48 8b 74 24 18       	mov    0x18(%rsp),%rsi
 105f34d:	e8 de c1 00 00       	call   106b530 <my.heap::instance_class>
 105f352:	48 8d 5c 24 70       	lea    0x70(%rsp),%rbx
 105f357:	48 89 df             	mov    %rbx,%rdi
 105f35a:	4d 89 f7             	mov    %r14,%r15
 105f35d:	4c 89 f6             	mov    %r14,%rsi
 105f360:	48 8b 54 24 48       	mov    0x48(%rsp),%rdx
 105f365:	48 89 c1             	mov    %rax,%rcx
 105f368:	4c 8b 44 24 58       	mov    0x58(%rsp),%r8
 105f36d:	e8 ae 50 00 00       	call   1064420 <my.vm::bind_method>
 105f372:	e9 82 fa ff ff       	jmp    105edf9 <my.vm::run+0x1f49>
 105f377:	4c 89 f7             	mov    %r14,%rdi
 105f37a:	4c 89 ee             	mov    %r13,%rsi
 105f37d:	e8 ae c1 00 00       	call   106b530 <my.heap::instance_class>
 105f382:	4c 8d 64 24 70       	lea    0x70(%rsp),%r12
 105f387:	4c 89 e7             	mov    %r12,%rdi
 105f38a:	4c 89 f6             	mov    %r14,%rsi
 105f38d:	48 8b 54 24 48       	mov    0x48(%rsp),%rdx
 105f392:	48 89 c1             	mov    %rax,%rcx
 105f395:	4d 89 f8             	mov    %r15,%r8
 105f398:	4c 8b 4c 24 20       	mov    0x20(%rsp),%r9
 105f39d:	e8 2e 5d 00 00       	call   10650d0 <my.vm::invoke_from_class>
 105f3a2:	41 f6 04 24 01       	testb  $0x1,(%r12)
 105f3a7:	0f 85 ab fa ff ff    	jne    105ee58 <my.vm::run+0x1fa8>
 105f3ad:	e9 e2 0a 00 00       	jmp    105fe94 <my.vm::run+0x2fe4>
 105f3b2:	48 8b 4c 24 18       	mov    0x18(%rsp),%rcx
 105f3b7:	48 8b 7c 24 40       	mov    0x40(%rsp),%rdi
 105f3bc:	49 89 fe             	mov    %rdi,%r14
 105f3bf:	49 89 cc             	mov    %rcx,%r12
 105f3c2:	48 89 df             	mov    %rbx,%rdi
 105f3c5:	e8 36 54 fc ff       	call   1024800 <myl_core_drop_owned>
 105f3ca:	48 8b 4c 24 58       	mov    0x58(%rsp),%rcx
 105f3cf:	0f b6 01             	movzbl (%rcx),%eax
 105f3d2:	83 f8 03             	cmp    $0x3,%eax
 105f3d5:	0f 85 5c 13 00 00    	jne    1060737 <my.vm::run+0x3887>
 105f3db:	48 8b 71 08          	mov    0x8(%rcx),%rsi
 105f3df:	48 8b 7c 24 50       	mov    0x50(%rsp),%rdi
 105f3e4:	4c 89 f3             	mov    %r14,%rbx
 105f3e7:	49 89 fe             	mov    %rdi,%r14
 105f3ea:	48 89 da             	mov    %rbx,%rdx
 105f3ed:	4c 89 e1             	mov    %r12,%rcx
 105f3f0:	e8 eb c5 00 00       	call   106b9e0 <my.heap::set_class_methods>
 105f3f5:	48 89 df             	mov    %rbx,%rdi
 105f3f8:	e8 03 54 fc ff       	call   1024800 <myl_core_drop_owned>
 105f3fd:	4d 89 f1             	mov    %r14,%r9
 105f400:	48 8b 44 24 38       	mov    0x38(%rsp),%rax
 105f405:	49 89 86 80 00 00 00 	mov    %rax,0x80(%r14)
 105f40c:	48 8b 55 08          	mov    0x8(%rbp),%rdx
 105f410:	48 89 c5             	mov    %rax,%rbp
 105f413:	48 39 d0             	cmp    %rdx,%rax
 105f416:	0f 83 9d 09 00 00    	jae    105fdb9 <my.vm::run+0x2f09>
 105f41c:	4d 8b 91 90 00 00 00 	mov    0x90(%r9),%r10
 105f423:	4c 8d 25 26 80 fa ff 	lea    -0x57fda(%rip),%r12        # 1007450 <core_number_pairs+0x1f0>
 105f42a:	4d 89 eb             	mov    %r13,%r11
 105f42d:	e9 5e 02 00 00       	jmp    105f690 <my.vm::run+0x27e0>
 105f432:	48 8b 79 10          	mov    0x10(%rcx),%rdi
 105f436:	be 08 00 00 00       	mov    $0x8,%esi
 105f43b:	eb 74                	jmp    105f4b1 <my.vm::run+0x2601>
 105f43d:	48 8b 79 10          	mov    0x10(%rcx),%rdi
 105f441:	be 10 00 00 00       	mov    $0x10,%esi
 105f446:	eb 69                	jmp    105f4b1 <my.vm::run+0x2601>
 105f448:	48 8b 79 18          	mov    0x18(%rcx),%rdi
 105f44c:	48 8b 69 20          	mov    0x20(%rcx),%rbp
 105f450:	48 8b 41 28          	mov    0x28(%rcx),%rax
 105f454:	48 89 44 24 18       	mov    %rax,0x18(%rsp)
 105f459:	be 08 00 00 00       	mov    $0x8,%esi
 105f45e:	4d 89 ce             	mov    %r9,%r14
 105f461:	e8 5a 52 fc ff       	call   10246c0 <myl_core_list_copy>
 105f466:	48 89 44 24 40       	mov    %rax,0x40(%rsp)
 105f46b:	be 08 00 00 00       	mov    $0x8,%esi
 105f470:	48 89 ef             	mov    %rbp,%rdi
 105f473:	e8 48 52 fc ff       	call   10246c0 <myl_core_list_copy>
 105f478:	48 89 44 24 60       	mov    %rax,0x60(%rsp)
 105f47d:	be 10 00 00 00       	mov    $0x10,%esi
 105f482:	48 8b 7c 24 18       	mov    0x18(%rsp),%rdi
 105f487:	e8 34 52 fc ff       	call   10246c0 <myl_core_list_copy>
 105f48c:	48 89 c5             	mov    %rax,%rbp
 105f48f:	48 8b 7c 24 40       	mov    0x40(%rsp),%rdi
 105f494:	e8 67 53 fc ff       	call   1024800 <myl_core_drop_owned>
 105f499:	48 8b 7c 24 60       	mov    0x60(%rsp),%rdi
 105f49e:	e8 5d 53 fc ff       	call   1024800 <myl_core_drop_owned>
 105f4a3:	48 89 ef             	mov    %rbp,%rdi
 105f4a6:	eb 14                	jmp    105f4bc <my.vm::run+0x260c>
 105f4a8:	48 8b 79 10          	mov    0x10(%rcx),%rdi
 105f4ac:	be 20 00 00 00       	mov    $0x20,%esi
 105f4b1:	4d 89 ce             	mov    %r9,%r14
 105f4b4:	e8 07 52 fc ff       	call   10246c0 <myl_core_list_copy>
 105f4b9:	48 89 c7             	mov    %rax,%rdi
 105f4bc:	e8 3f 53 fc ff       	call   1024800 <myl_core_drop_owned>
 105f4c1:	4d 89 f1             	mov    %r14,%r9
 105f4c4:	4d 89 eb             	mov    %r13,%r11
 105f4c7:	31 c0                	xor    %eax,%eax
 105f4c9:	31 ff                	xor    %edi,%edi
 105f4cb:	31 ed                	xor    %ebp,%ebp
 105f4cd:	31 f6                	xor    %esi,%esi
 105f4cf:	3c 01                	cmp    $0x1,%al
 105f4d1:	0f 85 84 02 00 00    	jne    105f75b <my.vm::run+0x28ab>
 105f4d7:	49 89 f5             	mov    %rsi,%r13
 105f4da:	48 89 7c 24 60       	mov    %rdi,0x60(%rsp)
 105f4df:	48 8d bc 24 00 03 00 	lea    0x300(%rsp),%rdi
 105f4e6:	00 
 105f4e7:	4c 89 ce             	mov    %r9,%rsi
 105f4ea:	48 8b 54 24 10       	mov    0x10(%rsp),%rdx
 105f4ef:	4c 89 d9             	mov    %r11,%rcx
 105f4f2:	4d 89 f8             	mov    %r15,%r8
 105f4f5:	4d 89 ce             	mov    %r9,%r14
 105f4f8:	4c 8b 4c 24 20       	mov    0x20(%rsp),%r9
 105f4fd:	e8 7e 4d 00 00       	call   1064280 <my.vm::read_constant>
 105f502:	0f b6 84 24 00 03 00 	movzbl 0x300(%rsp),%eax
 105f509:	00 
 105f50a:	83 f8 03             	cmp    $0x3,%eax
 105f50d:	0f 85 60 0c 00 00    	jne    1060173 <my.vm::run+0x32c3>
 105f513:	48 8b 84 24 28 03 00 	mov    0x328(%rsp),%rax
 105f51a:	00 
 105f51b:	48 89 44 24 20       	mov    %rax,0x20(%rsp)
 105f520:	48 8b 84 24 20 03 00 	mov    0x320(%rsp),%rax
 105f527:	00 
 105f528:	48 89 44 24 40       	mov    %rax,0x40(%rsp)
 105f52d:	48 8b 84 24 18 03 00 	mov    0x318(%rsp),%rax
 105f534:	00 
 105f535:	48 89 44 24 18       	mov    %rax,0x18(%rsp)
 105f53a:	4c 8b bc 24 08 03 00 	mov    0x308(%rsp),%r15
 105f541:	00 
 105f542:	48 8b 84 24 10 03 00 	mov    0x310(%rsp),%rax
 105f549:	00 
 105f54a:	48 89 44 24 10       	mov    %rax,0x10(%rsp)
 105f54f:	be 20 00 00 00       	mov    $0x20,%esi
 105f554:	48 89 ef             	mov    %rbp,%rdi
 105f557:	e8 64 51 fc ff       	call   10246c0 <myl_core_list_copy>
 105f55c:	48 89 84 24 68 01 00 	mov    %rax,0x168(%rsp)
 105f563:	00 
 105f564:	48 89 ef             	mov    %rbp,%rdi
 105f567:	e8 94 52 fc ff       	call   1024800 <myl_core_drop_owned>
 105f56c:	4c 89 f7             	mov    %r14,%rdi
 105f56f:	4c 89 fe             	mov    %r15,%rsi
 105f572:	e8 e9 b9 00 00       	call   106af60 <my.heap::string_hash>
 105f577:	49 8b 54 24 08       	mov    0x8(%r12),%rdx
 105f57c:	48 39 d3             	cmp    %rdx,%rbx
 105f57f:	0f 83 37 07 00 00    	jae    105fcbc <my.vm::run+0x2e0c>
 105f585:	48 89 dd             	mov    %rbx,%rbp
 105f588:	48 8b 4c 24 58       	mov    0x58(%rsp),%rcx
 105f58d:	49 8d 1c 0c          	lea    (%r12,%rcx,1),%rbx
 105f591:	48 83 c3 20          	add    $0x20,%rbx
 105f595:	49 83 c4 20          	add    $0x20,%r12
 105f599:	48 c1 e5 04          	shl    $0x4,%rbp
 105f59d:	4d 8b 4c 2c 08       	mov    0x8(%r12,%rbp,1),%r9
 105f5a2:	45 8b 04 2c          	mov    (%r12,%rbp,1),%r8d
 105f5a6:	48 8b bc 24 68 01 00 	mov    0x168(%rsp),%rdi
 105f5ad:	00 
 105f5ae:	4c 89 ee             	mov    %r13,%rsi
 105f5b1:	4c 89 fa             	mov    %r15,%rdx
 105f5b4:	89 c1                	mov    %eax,%ecx
 105f5b6:	e8 85 ba 00 00       	call   106b040 <my.table::set>
 105f5bb:	0f b6 03             	movzbl (%rbx),%eax
 105f5be:	83 f8 03             	cmp    $0x3,%eax
 105f5c1:	0f 85 c9 0b 00 00    	jne    1060190 <my.vm::run+0x32e0>
 105f5c7:	48 8b 73 08          	mov    0x8(%rbx),%rsi
 105f5cb:	48 8b 44 24 50       	mov    0x50(%rsp),%rax
 105f5d0:	4c 8b 00             	mov    (%rax),%r8
 105f5d3:	49 8b 40 08          	mov    0x8(%r8),%rax
 105f5d7:	48 39 c6             	cmp    %rax,%rsi
 105f5da:	4c 8b 5c 24 18       	mov    0x18(%rsp),%r11
 105f5df:	0f 83 0d 07 00 00    	jae    105fcf2 <my.vm::run+0x2e42>
 105f5e5:	48 89 f7             	mov    %rsi,%rdi
 105f5e8:	4c 8b 7c 24 40       	mov    0x40(%rsp),%r15
 105f5ed:	4c 6b d7 38          	imul   $0x38,%rdi,%r10
 105f5f1:	43 0f b6 74 10 20    	movzbl 0x20(%r8,%r10,1),%esi
 105f5f7:	4f 8b 4c 10 28       	mov    0x28(%r8,%r10,1),%r9
 105f5fc:	4b 8b 44 10 30       	mov    0x30(%r8,%r10,1),%rax
 105f601:	4b 8b 7c 10 38       	mov    0x38(%r8,%r10,1),%rdi
 105f606:	4f 8b 74 10 40       	mov    0x40(%r8,%r10,1),%r14
 105f60b:	4c 89 74 24 40       	mov    %r14,0x40(%rsp)
 105f610:	4f 8b 74 10 48       	mov    0x48(%r8,%r10,1),%r14
 105f615:	4b c7 44 10 20 07 00 	movq   $0x7,0x20(%r8,%r10,1)
 105f61c:	00 00 
 105f61e:	4c 8b 6c 24 60       	mov    0x60(%rsp),%r13
 105f623:	4f 89 6c 10 28       	mov    %r13,0x28(%r8,%r10,1)
 105f628:	4b 89 54 10 30       	mov    %rdx,0x30(%r8,%r10,1)
 105f62d:	4b 89 4c 10 38       	mov    %rcx,0x38(%r8,%r10,1)
 105f632:	83 fe 09             	cmp    $0x9,%esi
 105f635:	77 1b                	ja     105f652 <my.vm::run+0x27a2>
 105f637:	b9 d0 02 00 00       	mov    $0x2d0,%ecx
 105f63c:	0f a3 f1             	bt     %esi,%ecx
 105f63f:	0f 83 93 00 00 00    	jae    105f6d8 <my.vm::run+0x2828>
 105f645:	48 89 c7             	mov    %rax,%rdi
 105f648:	e8 b3 51 fc ff       	call   1024800 <myl_core_drop_owned>
 105f64d:	4c 8b 5c 24 18       	mov    0x18(%rsp),%r11
 105f652:	49 01 ec             	add    %rbp,%r12
 105f655:	c4 c1 79 10 04 24    	vmovupd (%r12),%xmm0
 105f65b:	c5 f9 54 05 7d 4d fa 	vandpd -0x5b283(%rip),%xmm0,%xmm0        # 10043e0 <__anon_2214+0xb0>
 105f662:	ff 
 105f663:	c5 f9 11 03          	vmovupd %xmm0,(%rbx)
 105f667:	48 8b 6c 24 38       	mov    0x38(%rsp),%rbp
 105f66c:	48 ff c5             	inc    %rbp
 105f66f:	4c 8b 4c 24 50       	mov    0x50(%rsp),%r9
 105f674:	49 89 a9 80 00 00 00 	mov    %rbp,0x80(%r9)
 105f67b:	4d 8b 91 90 00 00 00 	mov    0x90(%r9),%r10
 105f682:	4c 8d 25 c7 7d fa ff 	lea    -0x58239(%rip),%r12        # 1007450 <core_number_pairs+0x1f0>
 105f689:	0f 1f 80 00 00 00 00 	nopl   0x0(%rax)
 105f690:	4c 89 d6             	mov    %r10,%rsi
 105f693:	48 ff ce             	dec    %rsi
 105f696:	0f 80 82 08 00 00    	jo     105ff1e <my.vm::run+0x306e>
 105f69c:	4d 89 d6             	mov    %r10,%r14
 105f69f:	49 8b 81 88 00 00 00 	mov    0x88(%r9),%rax
 105f6a6:	48 8b 50 08          	mov    0x8(%rax),%rdx
 105f6aa:	48 39 d6             	cmp    %rdx,%rsi
 105f6ad:	0f 83 14 01 00 00    	jae    105f7c7 <my.vm::run+0x2917>
 105f6b3:	4c 89 cf             	mov    %r9,%rdi
 105f6b6:	4d 89 dd             	mov    %r11,%r13
 105f6b9:	4c 89 de             	mov    %r11,%rsi
 105f6bc:	4c 89 fa             	mov    %r15,%rdx
 105f6bf:	4c 89 cb             	mov    %r9,%rbx
 105f6c2:	e8 69 b6 00 00       	call   106ad30 <my.heap::function_instruction>
 105f6c7:	49 89 d9             	mov    %rbx,%r9
 105f6ca:	49 ff c7             	inc    %r15
 105f6cd:	0f 81 8d d8 ff ff    	jno    105cf60 <my.vm::run+0xb0>
 105f6d3:	e9 09 08 00 00       	jmp    105fee1 <my.vm::run+0x3031>
 105f6d8:	4c 89 c8             	mov    %r9,%rax
 105f6db:	83 fe 01             	cmp    $0x1,%esi
 105f6de:	0f 84 61 ff ff ff    	je     105f645 <my.vm::run+0x2795>
 105f6e4:	83 fe 02             	cmp    $0x2,%esi
 105f6e7:	0f 85 65 ff ff ff    	jne    105f652 <my.vm::run+0x27a2>
 105f6ed:	e8 0e 51 fc ff       	call   1024800 <myl_core_drop_owned>
 105f6f2:	48 8b 7c 24 40       	mov    0x40(%rsp),%rdi
 105f6f7:	e8 04 51 fc ff       	call   1024800 <myl_core_drop_owned>
 105f6fc:	4c 89 f0             	mov    %r14,%rax
 105f6ff:	e9 41 ff ff ff       	jmp    105f645 <my.vm::run+0x2795>
 105f704:	48 8b 41 08          	mov    0x8(%rcx),%rax
 105f708:	48 89 44 24 60       	mov    %rax,0x60(%rsp)
 105f70d:	48 8b 79 10          	mov    0x10(%rcx),%rdi
 105f711:	48 8b 41 18          	mov    0x18(%rcx),%rax
 105f715:	48 89 44 24 18       	mov    %rax,0x18(%rsp)
 105f71a:	be 20 00 00 00       	mov    $0x20,%esi
 105f71f:	e8 9c 4f fc ff       	call   10246c0 <myl_core_list_copy>
 105f724:	49 89 c6             	mov    %rax,%r14
 105f727:	be 20 00 00 00       	mov    $0x20,%esi
 105f72c:	48 89 c7             	mov    %rax,%rdi
 105f72f:	e8 8c 4f fc ff       	call   10246c0 <myl_core_list_copy>
 105f734:	48 89 c5             	mov    %rax,%rbp
 105f737:	4c 89 f7             	mov    %r14,%rdi
 105f73a:	e8 c1 50 fc ff       	call   1024800 <myl_core_drop_owned>
 105f73f:	48 8b 74 24 18       	mov    0x18(%rsp),%rsi
 105f744:	48 8b 7c 24 60       	mov    0x60(%rsp),%rdi
 105f749:	4c 8b 4c 24 50       	mov    0x50(%rsp),%r9
 105f74e:	4d 89 eb             	mov    %r13,%r11
 105f751:	b0 01                	mov    $0x1,%al
 105f753:	3c 01                	cmp    $0x1,%al
 105f755:	0f 84 7c fd ff ff    	je     105f4d7 <my.vm::run+0x2627>
 105f75b:	48 8d 0d 5e 39 fb ff 	lea    -0x4c6a2(%rip),%rcx        # 10130c0 <core_number_pairs+0xbe60>
 105f762:	48 8d 7c 24 70       	lea    0x70(%rsp),%rdi
 105f767:	4c 89 ce             	mov    %r9,%rsi
 105f76a:	48 8b 54 24 48       	mov    0x48(%rsp),%rdx
 105f76f:	4c 89 cb             	mov    %r9,%rbx
 105f772:	e8 29 46 00 00       	call   1063da0 <my.vm::runtime_error>
 105f777:	f6 44 24 70 01       	testb  $0x1,0x70(%rsp)
 105f77c:	0f 84 12 07 00 00    	je     105fe94 <my.vm::run+0x2fe4>
 105f782:	48 8b ab 80 00 00 00 	mov    0x80(%rbx),%rbp
 105f789:	4c 8b 93 90 00 00 00 	mov    0x90(%rbx),%r10
 105f790:	4c 8d 25 b9 7c fa ff 	lea    -0x58347(%rip),%r12        # 1007450 <core_number_pairs+0x1f0>
 105f797:	e9 e5 d8 ff ff       	jmp    105d081 <my.vm::run+0x1d1>
 105f79c:	48 89 cf             	mov    %rcx,%rdi
 105f79f:	4d 89 ce             	mov    %r9,%r14
 105f7a2:	e8 59 50 fc ff       	call   1024800 <myl_core_drop_owned>
 105f7a7:	4c 89 ff             	mov    %r15,%rdi
 105f7aa:	e8 51 50 fc ff       	call   1024800 <myl_core_drop_owned>
 105f7af:	48 89 df             	mov    %rbx,%rdi
 105f7b2:	e8 49 50 fc ff       	call   1024800 <myl_core_drop_owned>
 105f7b7:	4d 89 f1             	mov    %r14,%r9
 105f7ba:	e9 64 f8 ff ff       	jmp    105f023 <my.vm::run+0x2173>
 105f7bf:	48 89 c7             	mov    %rax,%rdi
 105f7c2:	e9 51 f8 ff ff       	jmp    105f018 <my.vm::run+0x2168>
 105f7c7:	48 89 f0             	mov    %rsi,%rax
 105f7ca:	48 c1 f8 3f          	sar    $0x3f,%rax
 105f7ce:	48 21 d0             	and    %rdx,%rax
 105f7d1:	48 01 f0             	add    %rsi,%rax
 105f7d4:	48 39 d0             	cmp    %rdx,%rax
 105f7d7:	0f 82 d6 fe ff ff    	jb     105f6b3 <my.vm::run+0x2803>
 105f7dd:	e9 60 11 00 00       	jmp    1060942 <my.vm::run+0x3a92>
 105f7e2:	48 89 f7             	mov    %rsi,%rdi
 105f7e5:	48 c1 ff 3f          	sar    $0x3f,%rdi
 105f7e9:	48 21 d7             	and    %rdx,%rdi
 105f7ec:	48 01 f7             	add    %rsi,%rdi
 105f7ef:	48 39 d7             	cmp    %rdx,%rdi
 105f7f2:	0f 82 ee d7 ff ff    	jb     105cfe6 <my.vm::run+0x136>
 105f7f8:	e9 51 11 00 00       	jmp    106094e <my.vm::run+0x3a9e>
 105f7fd:	48 89 ee             	mov    %rbp,%rsi
 105f800:	48 c1 fe 3f          	sar    $0x3f,%rsi
 105f804:	48 21 d6             	and    %rdx,%rsi
 105f807:	48 01 ee             	add    %rbp,%rsi
 105f80a:	48 39 d6             	cmp    %rdx,%rsi
 105f80d:	0f 82 fc d7 ff ff    	jb     105d00f <my.vm::run+0x15f>
 105f813:	e9 51 11 00 00       	jmp    1060969 <my.vm::run+0x3ab9>
 105f818:	48 89 d9             	mov    %rbx,%rcx
 105f81b:	48 c1 f9 3f          	sar    $0x3f,%rcx
 105f81f:	48 21 d1             	and    %rdx,%rcx
 105f822:	48 01 d9             	add    %rbx,%rcx
 105f825:	48 39 d1             	cmp    %rdx,%rcx
 105f828:	0f 82 bf e3 ff ff    	jb     105dbed <my.vm::run+0xd3d>
 105f82e:	e9 1b 13 00 00       	jmp    1060b4e <my.vm::run+0x3c9e>
 105f833:	48 89 d9             	mov    %rbx,%rcx
 105f836:	48 c1 f9 3f          	sar    $0x3f,%rcx
 105f83a:	48 21 d1             	and    %rdx,%rcx
 105f83d:	48 01 d9             	add    %rbx,%rcx
 105f840:	48 39 d1             	cmp    %rdx,%rcx
 105f843:	0f 82 72 e4 ff ff    	jb     105dcbb <my.vm::run+0xe0b>
 105f849:	e9 73 12 00 00       	jmp    1060ac1 <my.vm::run+0x3c11>
 105f84e:	48 89 d9             	mov    %rbx,%rcx
 105f851:	48 c1 f9 3f          	sar    $0x3f,%rcx
 105f855:	48 21 d1             	and    %rdx,%rcx
 105f858:	48 01 d9             	add    %rbx,%rcx
 105f85b:	48 39 d1             	cmp    %rdx,%rcx
 105f85e:	0f 82 d7 e5 ff ff    	jb     105de3b <my.vm::run+0xf8b>
 105f864:	e9 8c 11 00 00       	jmp    10609f5 <my.vm::run+0x3b45>
 105f869:	48 89 d9             	mov    %rbx,%rcx
 105f86c:	48 c1 f9 3f          	sar    $0x3f,%rcx
 105f870:	48 21 d1             	and    %rdx,%rcx
 105f873:	48 01 d9             	add    %rbx,%rcx
 105f876:	48 39 d1             	cmp    %rdx,%rcx
 105f879:	0f 82 01 e6 ff ff    	jb     105de80 <my.vm::run+0xfd0>
 105f87f:	e9 f4 10 00 00       	jmp    1060978 <my.vm::run+0x3ac8>
 105f884:	48 89 f7             	mov    %rsi,%rdi
 105f887:	48 c1 ff 3f          	sar    $0x3f,%rdi
 105f88b:	48 21 c7             	and    %rax,%rdi
 105f88e:	48 01 f7             	add    %rsi,%rdi
 105f891:	48 39 c7             	cmp    %rax,%rdi
 105f894:	4d 89 f2             	mov    %r14,%r10
 105f897:	0f 82 bf db ff ff    	jb     105d45c <my.vm::run+0x5ac>
 105f89d:	e9 5e 12 00 00       	jmp    1060b00 <my.vm::run+0x3c50>
 105f8a2:	48 89 f1             	mov    %rsi,%rcx
 105f8a5:	48 c1 f9 3f          	sar    $0x3f,%rcx
 105f8a9:	48 21 d1             	and    %rdx,%rcx
 105f8ac:	48 01 f1             	add    %rsi,%rcx
 105f8af:	48 39 d1             	cmp    %rdx,%rcx
 105f8b2:	48 8b 6c 24 20       	mov    0x20(%rsp),%rbp
 105f8b7:	0f 82 a6 de ff ff    	jb     105d763 <my.vm::run+0x8b3>
 105f8bd:	e9 fb 10 00 00       	jmp    10609bd <my.vm::run+0x3b0d>
 105f8c2:	48 8b 44 24 38       	mov    0x38(%rsp),%rax
 105f8c7:	49 89 c4             	mov    %rax,%r12
 105f8ca:	49 c1 fc 3f          	sar    $0x3f,%r12
 105f8ce:	49 21 d4             	and    %rdx,%r12
 105f8d1:	49 01 c4             	add    %rax,%r12
 105f8d4:	49 39 d4             	cmp    %rdx,%r12
 105f8d7:	0f 82 6c e0 ff ff    	jb     105d949 <my.vm::run+0xa99>
 105f8dd:	e9 96 12 00 00       	jmp    1060b78 <my.vm::run+0x3cc8>
 105f8e2:	48 89 f1             	mov    %rsi,%rcx
 105f8e5:	48 c1 f9 3f          	sar    $0x3f,%rcx
 105f8e9:	48 21 d1             	and    %rdx,%rcx
 105f8ec:	48 01 f1             	add    %rsi,%rcx
 105f8ef:	48 39 d1             	cmp    %rdx,%rcx
 105f8f2:	0f 82 43 e3 ff ff    	jb     105dc3b <my.vm::run+0xd8b>
 105f8f8:	e9 13 11 00 00       	jmp    1060a10 <my.vm::run+0x3b60>
 105f8fd:	48 89 ee             	mov    %rbp,%rsi
 105f900:	48 c1 fe 3f          	sar    $0x3f,%rsi
 105f904:	48 21 d6             	and    %rdx,%rsi
 105f907:	48 01 ee             	add    %rbp,%rsi
 105f90a:	48 39 d6             	cmp    %rdx,%rsi
 105f90d:	0f 82 32 e6 ff ff    	jb     105df45 <my.vm::run+0x1095>
 105f913:	e9 ce 10 00 00       	jmp    10609e6 <my.vm::run+0x3b36>
 105f918:	48 89 f1             	mov    %rsi,%rcx
 105f91b:	48 c1 f9 3f          	sar    $0x3f,%rcx
 105f91f:	48 21 d1             	and    %rdx,%rcx
 105f922:	48 01 f1             	add    %rsi,%rcx
 105f925:	48 39 d1             	cmp    %rdx,%rcx
 105f928:	4c 8b 4c 24 20       	mov    0x20(%rsp),%r9
 105f92d:	0f 82 eb e8 ff ff    	jb     105e21e <my.vm::run+0x136e>
 105f933:	e9 91 10 00 00       	jmp    10609c9 <my.vm::run+0x3b19>
 105f938:	49 8d 0c 31          	lea    (%r9,%rsi,1),%rcx
 105f93c:	48 39 d1             	cmp    %rdx,%rcx
 105f93f:	0f 82 61 ee ff ff    	jb     105e7a6 <my.vm::run+0x18f6>
 105f945:	e9 4c 10 00 00       	jmp    1060996 <my.vm::run+0x3ae6>
 105f94a:	48 8d 3c 29          	lea    (%rcx,%rbp,1),%rdi
 105f94e:	48 39 d7             	cmp    %rdx,%rdi
 105f951:	0f 82 72 f1 ff ff    	jb     105eac9 <my.vm::run+0x1c19>
 105f957:	e9 cb 11 00 00       	jmp    1060b27 <my.vm::run+0x3c77>
 105f95c:	48 89 e9             	mov    %rbp,%rcx
 105f95f:	48 c1 f9 3f          	sar    $0x3f,%rcx
 105f963:	48 21 d1             	and    %rdx,%rcx
 105f966:	48 01 e9             	add    %rbp,%rcx
 105f969:	48 39 d1             	cmp    %rdx,%rcx
 105f96c:	0f 82 32 f4 ff ff    	jb     105eda4 <my.vm::run+0x1ef4>
 105f972:	e9 c0 10 00 00       	jmp    1060a37 <my.vm::run+0x3b87>
 105f977:	48 89 f0             	mov    %rsi,%rax
 105f97a:	48 c1 f8 3f          	sar    $0x3f,%rax
 105f97e:	48 21 d0             	and    %rdx,%rax
 105f981:	48 01 f0             	add    %rsi,%rax
 105f984:	48 39 d0             	cmp    %rdx,%rax
 105f987:	0f 82 37 d7 ff ff    	jb     105d0c4 <my.vm::run+0x214>
 105f98d:	e9 56 11 00 00       	jmp    1060ae8 <my.vm::run+0x3c38>
 105f992:	48 89 e9             	mov    %rbp,%rcx
 105f995:	48 c1 f9 3f          	sar    $0x3f,%rcx
 105f999:	48 21 d1             	and    %rdx,%rcx
 105f99c:	48 01 e9             	add    %rbp,%rcx
 105f99f:	48 39 d1             	cmp    %rdx,%rcx
 105f9a2:	0f 82 c4 e2 ff ff    	jb     105dc6c <my.vm::run+0xdbc>
 105f9a8:	e9 99 10 00 00       	jmp    1060a46 <my.vm::run+0x3b96>
 105f9ad:	48 89 f7             	mov    %rsi,%rdi
 105f9b0:	48 c1 ff 3f          	sar    $0x3f,%rdi
 105f9b4:	48 21 d7             	and    %rdx,%rdi
 105f9b7:	48 01 f7             	add    %rsi,%rdi
 105f9ba:	48 39 d7             	cmp    %rdx,%rdi
 105f9bd:	0f 82 ff e5 ff ff    	jb     105dfc2 <my.vm::run+0x1112>
 105f9c3:	e9 2c 11 00 00       	jmp    1060af4 <my.vm::run+0x3c44>
 105f9c8:	48 89 c7             	mov    %rax,%rdi
 105f9cb:	48 c1 ff 3f          	sar    $0x3f,%rdi
 105f9cf:	48 21 d7             	and    %rdx,%rdi
 105f9d2:	48 01 c7             	add    %rax,%rdi
 105f9d5:	48 39 d7             	cmp    %rdx,%rdi
 105f9d8:	0f 82 62 e6 ff ff    	jb     105e040 <my.vm::run+0x1190>
 105f9de:	e9 86 11 00 00       	jmp    1060b69 <my.vm::run+0x3cb9>
 105f9e3:	49 89 f0             	mov    %rsi,%r8
 105f9e6:	49 c1 f8 3f          	sar    $0x3f,%r8
 105f9ea:	49 21 d0             	and    %rdx,%r8
 105f9ed:	49 01 f0             	add    %rsi,%r8
 105f9f0:	49 39 d0             	cmp    %rdx,%r8
 105f9f3:	0f 82 08 e7 ff ff    	jb     105e101 <my.vm::run+0x1251>
 105f9f9:	e9 63 10 00 00       	jmp    1060a61 <my.vm::run+0x3bb1>
 105f9fe:	48 89 de             	mov    %rbx,%rsi
 105fa01:	48 c1 fe 3f          	sar    $0x3f,%rsi
 105fa05:	48 21 d6             	and    %rdx,%rsi
 105fa08:	48 01 de             	add    %rbx,%rsi
 105fa0b:	48 39 d6             	cmp    %rdx,%rsi
 105fa0e:	0f 82 c4 e5 ff ff    	jb     105dfd8 <my.vm::run+0x1128>
 105fa14:	e9 89 0f 00 00       	jmp    10609a2 <my.vm::run+0x3af2>
 105fa19:	be 20 00 00 00       	mov    $0x20,%esi
 105fa1e:	31 ff                	xor    %edi,%edi
 105fa20:	e8 1b 40 fc ff       	call   1023a40 <myl_core_list_new_slow>
 105fa25:	e9 62 db ff ff       	jmp    105d58c <my.vm::run+0x6dc>
 105fa2a:	48 89 f7             	mov    %rsi,%rdi
 105fa2d:	48 c1 ff 3f          	sar    $0x3f,%rdi
 105fa31:	48 21 d7             	and    %rdx,%rdi
 105fa34:	48 01 f7             	add    %rsi,%rdi
 105fa37:	48 39 d7             	cmp    %rdx,%rdi
 105fa3a:	49 89 eb             	mov    %rbp,%r11
 105fa3d:	0f 82 e3 db ff ff    	jb     105d626 <my.vm::run+0x776>
 105fa43:	e9 15 11 00 00       	jmp    1060b5d <my.vm::run+0x3cad>
 105fa48:	4c 89 c1             	mov    %r8,%rcx
 105fa4b:	48 c1 f9 3f          	sar    $0x3f,%rcx
 105fa4f:	48 21 d1             	and    %rdx,%rcx
 105fa52:	4c 01 c1             	add    %r8,%rcx
 105fa55:	48 39 d1             	cmp    %rdx,%rcx
 105fa58:	0f 82 03 e9 ff ff    	jb     105e361 <my.vm::run+0x14b1>
 105fa5e:	e9 28 10 00 00       	jmp    1060a8b <my.vm::run+0x3bdb>
 105fa63:	48 89 f0             	mov    %rsi,%rax
 105fa66:	48 c1 f8 3f          	sar    $0x3f,%rax
 105fa6a:	48 21 d0             	and    %rdx,%rax
 105fa6d:	48 01 f0             	add    %rsi,%rax
 105fa70:	48 39 d0             	cmp    %rdx,%rax
 105fa73:	0f 82 ad e6 ff ff    	jb     105e126 <my.vm::run+0x1276>
 105fa79:	e9 91 10 00 00       	jmp    1060b0f <my.vm::run+0x3c5f>
 105fa7e:	48 89 f7             	mov    %rsi,%rdi
 105fa81:	48 c1 ff 3f          	sar    $0x3f,%rdi
 105fa85:	48 21 d7             	and    %rdx,%rdi
 105fa88:	48 01 f7             	add    %rsi,%rdi
 105fa8b:	48 39 d7             	cmp    %rdx,%rdi
 105fa8e:	0f 82 d4 f0 ff ff    	jb     105eb68 <my.vm::run+0x1cb8>
 105fa94:	e9 f0 10 00 00       	jmp    1060b89 <my.vm::run+0x3cd9>
 105fa99:	48 89 f1             	mov    %rsi,%rcx
 105fa9c:	48 c1 f9 3f          	sar    $0x3f,%rcx
 105faa0:	48 21 d1             	and    %rdx,%rcx
 105faa3:	48 01 f1             	add    %rsi,%rcx
 105faa6:	48 39 d1             	cmp    %rdx,%rcx
 105faa9:	0f 82 27 dc ff ff    	jb     105d6d6 <my.vm::run+0x826>
 105faaf:	e9 68 0f 00 00       	jmp    1060a1c <my.vm::run+0x3b6c>
 105fab4:	48 89 f1             	mov    %rsi,%rcx
 105fab7:	48 c1 f9 3f          	sar    $0x3f,%rcx
 105fabb:	48 21 d1             	and    %rdx,%rcx
 105fabe:	48 01 f1             	add    %rsi,%rcx
 105fac1:	48 39 d1             	cmp    %rdx,%rcx
 105fac4:	0f 82 14 e0 ff ff    	jb     105dade <my.vm::run+0xc2e>
 105faca:	e9 67 10 00 00       	jmp    1060b36 <my.vm::run+0x3c86>
 105facf:	48 89 f0             	mov    %rsi,%rax
 105fad2:	48 c1 f8 3f          	sar    $0x3f,%rax
 105fad6:	48 21 d0             	and    %rdx,%rax
 105fad9:	48 01 f0             	add    %rsi,%rax
 105fadc:	48 39 d0             	cmp    %rdx,%rax
 105fadf:	0f 82 a0 d7 ff ff    	jb     105d285 <my.vm::run+0x3d5>
 105fae5:	e9 58 10 00 00       	jmp    1060b42 <my.vm::run+0x3c92>
 105faea:	48 89 c5             	mov    %rax,%rbp
 105faed:	48 c1 f8 3f          	sar    $0x3f,%rax
 105faf1:	48 21 d0             	and    %rdx,%rax
 105faf4:	48 01 e8             	add    %rbp,%rax
 105faf7:	48 39 d0             	cmp    %rdx,%rax
 105fafa:	0f 82 90 fb ff ff    	jb     105f690 <my.vm::run+0x27e0>
 105fb00:	e9 a1 0f 00 00       	jmp    1060aa6 <my.vm::run+0x3bf6>
 105fb05:	48 89 f7             	mov    %rsi,%rdi
 105fb08:	48 c1 ff 3f          	sar    $0x3f,%rdi
 105fb0c:	48 21 d7             	and    %rdx,%rdi
 105fb0f:	48 01 f7             	add    %rsi,%rdi
 105fb12:	48 39 d7             	cmp    %rdx,%rdi
 105fb15:	0f 82 81 ee ff ff    	jb     105e99c <my.vm::run+0x1aec>
 105fb1b:	e9 95 0f 00 00       	jmp    1060ab5 <my.vm::run+0x3c05>
 105fb20:	48 89 f1             	mov    %rsi,%rcx
 105fb23:	48 c1 f9 3f          	sar    $0x3f,%rcx
 105fb27:	48 21 d1             	and    %rdx,%rcx
 105fb2a:	48 01 f1             	add    %rsi,%rcx
 105fb2d:	48 39 d1             	cmp    %rdx,%rcx
 105fb30:	0f 82 70 f1 ff ff    	jb     105eca6 <my.vm::run+0x1df6>
 105fb36:	e9 e0 0f 00 00       	jmp    1060b1b <my.vm::run+0x3c6b>
 105fb3b:	48 8b 74 24 38       	mov    0x38(%rsp),%rsi
 105fb40:	48 89 f1             	mov    %rsi,%rcx
 105fb43:	48 c1 f9 3f          	sar    $0x3f,%rcx
 105fb47:	48 21 d1             	and    %rdx,%rcx
 105fb4a:	48 01 f1             	add    %rsi,%rcx
 105fb4d:	48 39 d1             	cmp    %rdx,%rcx
 105fb50:	0f 82 a7 d7 ff ff    	jb     105d2fd <my.vm::run+0x44d>
 105fb56:	e9 7a 0e 00 00       	jmp    10609d5 <my.vm::run+0x3b25>
 105fb5b:	48 89 e8             	mov    %rbp,%rax
 105fb5e:	48 c1 f8 3f          	sar    $0x3f,%rax
 105fb62:	48 21 d0             	and    %rdx,%rax
 105fb65:	48 01 e8             	add    %rbp,%rax
 105fb68:	48 39 d0             	cmp    %rdx,%rax
 105fb6b:	4c 8b 5c 24 18       	mov    0x18(%rsp),%r11
 105fb70:	0f 82 f7 d7 ff ff    	jb     105d36d <my.vm::run+0x4bd>
 105fb76:	e9 01 0f 00 00       	jmp    1060a7c <my.vm::run+0x3bcc>
 105fb7b:	48 89 f1             	mov    %rsi,%rcx
 105fb7e:	48 c1 f9 3f          	sar    $0x3f,%rcx
 105fb82:	48 21 d1             	and    %rdx,%rcx
 105fb85:	48 01 f1             	add    %rsi,%rcx
 105fb88:	48 39 d1             	cmp    %rdx,%rcx
 105fb8b:	0f 82 9c e8 ff ff    	jb     105e42d <my.vm::run+0x157d>
 105fb91:	e9 6e 0e 00 00       	jmp    1060a04 <my.vm::run+0x3b54>
 105fb96:	48 89 f0             	mov    %rsi,%rax
 105fb99:	48 c1 f8 3f          	sar    $0x3f,%rax
 105fb9d:	48 21 d0             	and    %rdx,%rax
 105fba0:	48 01 f0             	add    %rsi,%rax
 105fba3:	48 39 d0             	cmp    %rdx,%rax
 105fba6:	0f 82 08 f5 ff ff    	jb     105f0b4 <my.vm::run+0x2204>
 105fbac:	e9 1f 0f 00 00       	jmp    1060ad0 <my.vm::run+0x3c20>
 105fbb1:	48 c1 f9 3f          	sar    $0x3f,%rcx
 105fbb5:	48 21 d1             	and    %rdx,%rcx
 105fbb8:	48 01 e9             	add    %rbp,%rcx
 105fbbb:	48 39 d1             	cmp    %rdx,%rcx
 105fbbe:	0f 82 fb db ff ff    	jb     105d7bf <my.vm::run+0x90f>
 105fbc4:	e9 5f 0e 00 00       	jmp    1060a28 <my.vm::run+0x3b78>
 105fbc9:	48 89 f1             	mov    %rsi,%rcx
 105fbcc:	48 c1 f9 3f          	sar    $0x3f,%rcx
 105fbd0:	48 21 d1             	and    %rdx,%rcx
 105fbd3:	48 01 f1             	add    %rsi,%rcx
 105fbd6:	48 39 d1             	cmp    %rdx,%rcx
 105fbd9:	0f 82 b4 f2 ff ff    	jb     105ee93 <my.vm::run+0x1fe3>
 105fbdf:	e9 71 0e 00 00       	jmp    1060a55 <my.vm::run+0x3ba5>
 105fbe4:	48 89 f1             	mov    %rsi,%rcx
 105fbe7:	48 c1 f9 3f          	sar    $0x3f,%rcx
 105fbeb:	48 21 d1             	and    %rdx,%rcx
 105fbee:	48 01 f1             	add    %rsi,%rcx
 105fbf1:	48 39 d1             	cmp    %rdx,%rcx
 105fbf4:	0f 82 b9 e5 ff ff    	jb     105e1b3 <my.vm::run+0x1303>
 105fbfa:	e9 cf 0f 00 00       	jmp    1060bce <my.vm::run+0x3d1e>
 105fbff:	48 89 f1             	mov    %rsi,%rcx
 105fc02:	48 c1 f9 3f          	sar    $0x3f,%rcx
 105fc06:	48 21 d1             	and    %rdx,%rcx
 105fc09:	48 01 f1             	add    %rsi,%rcx
 105fc0c:	48 39 d1             	cmp    %rdx,%rcx
 105fc0f:	0f 82 bb e5 ff ff    	jb     105e1d0 <my.vm::run+0x1320>
 105fc15:	e9 ed 0f 00 00       	jmp    1060c07 <my.vm::run+0x3d57>
 105fc1a:	48 89 f1             	mov    %rsi,%rcx
 105fc1d:	48 c1 f9 3f          	sar    $0x3f,%rcx
 105fc21:	48 21 d1             	and    %rdx,%rcx
 105fc24:	48 01 f1             	add    %rsi,%rcx
 105fc27:	48 39 d1             	cmp    %rdx,%rcx
 105fc2a:	0f 82 77 dc ff ff    	jb     105d8a7 <my.vm::run+0x9f7>
 105fc30:	e9 8d 0f 00 00       	jmp    1060bc2 <my.vm::run+0x3d12>
 105fc35:	48 89 c1             	mov    %rax,%rcx
 105fc38:	48 c1 f9 3f          	sar    $0x3f,%rcx
 105fc3c:	48 21 d1             	and    %rdx,%rcx
 105fc3f:	48 01 c1             	add    %rax,%rcx
 105fc42:	48 39 d1             	cmp    %rdx,%rcx
 105fc45:	0f 82 72 dc ff ff    	jb     105d8bd <my.vm::run+0xa0d>
 105fc4b:	e9 8a 0f 00 00       	jmp    1060bda <my.vm::run+0x3d2a>
 105fc50:	48 89 f1             	mov    %rsi,%rcx
 105fc53:	48 c1 f9 3f          	sar    $0x3f,%rcx
 105fc57:	48 21 d1             	and    %rdx,%rcx
 105fc5a:	48 01 f1             	add    %rsi,%rcx
 105fc5d:	48 39 d1             	cmp    %rdx,%rcx
 105fc60:	0f 82 0b dd ff ff    	jb     105d971 <my.vm::run+0xac1>
 105fc66:	e9 a8 0f 00 00       	jmp    1060c13 <my.vm::run+0x3d63>
 105fc6b:	48 89 de             	mov    %rbx,%rsi
 105fc6e:	48 c1 fe 3f          	sar    $0x3f,%rsi
 105fc72:	48 21 c6             	and    %rax,%rsi
 105fc75:	48 01 de             	add    %rbx,%rsi
 105fc78:	48 39 c6             	cmp    %rax,%rsi
 105fc7b:	0f 82 6a d4 ff ff    	jb     105d0eb <my.vm::run+0x23b>
 105fc81:	e9 c3 0f 00 00       	jmp    1060c49 <my.vm::run+0x3d99>
 105fc86:	48 89 f0             	mov    %rsi,%rax
 105fc89:	48 c1 f8 3f          	sar    $0x3f,%rax
 105fc8d:	48 21 d0             	and    %rdx,%rax
 105fc90:	48 01 f0             	add    %rsi,%rax
 105fc93:	48 39 d0             	cmp    %rdx,%rax
 105fc96:	0f 82 d6 e3 ff ff    	jb     105e072 <my.vm::run+0x11c2>
 105fc9c:	e9 7e 0f 00 00       	jmp    1060c1f <my.vm::run+0x3d6f>
 105fca1:	49 89 f0             	mov    %rsi,%r8
 105fca4:	49 c1 f8 3f          	sar    $0x3f,%r8
 105fca8:	49 21 c0             	and    %rax,%r8
 105fcab:	49 01 f0             	add    %rsi,%r8
 105fcae:	49 39 c0             	cmp    %rax,%r8
 105fcb1:	0f 82 da e0 ff ff    	jb     105dd91 <my.vm::run+0xee1>
 105fcb7:	e9 9f 0f 00 00       	jmp    1060c5b <my.vm::run+0x3dab>
 105fcbc:	48 89 dd             	mov    %rbx,%rbp
 105fcbf:	48 c1 fd 3f          	sar    $0x3f,%rbp
 105fcc3:	48 21 d5             	and    %rdx,%rbp
 105fcc6:	48 01 dd             	add    %rbx,%rbp
 105fcc9:	48 39 d5             	cmp    %rdx,%rbp
 105fccc:	0f 82 b6 f8 ff ff    	jb     105f588 <my.vm::run+0x26d8>
 105fcd2:	e9 21 0f 00 00       	jmp    1060bf8 <my.vm::run+0x3d48>
 105fcd7:	4c 89 ee             	mov    %r13,%rsi
 105fcda:	48 c1 fe 3f          	sar    $0x3f,%rsi
 105fcde:	48 21 d6             	and    %rdx,%rsi
 105fce1:	4c 01 ee             	add    %r13,%rsi
 105fce4:	48 39 d6             	cmp    %rdx,%rsi
 105fce7:	0f 82 e0 ef ff ff    	jb     105eccd <my.vm::run+0x1e1d>
 105fced:	e9 b5 0e 00 00       	jmp    1060ba7 <my.vm::run+0x3cf7>
 105fcf2:	48 89 f7             	mov    %rsi,%rdi
 105fcf5:	48 c1 ff 3f          	sar    $0x3f,%rdi
 105fcf9:	48 21 c7             	and    %rax,%rdi
 105fcfc:	48 01 f7             	add    %rsi,%rdi
 105fcff:	48 39 c7             	cmp    %rax,%rdi
 105fd02:	4c 8b 7c 24 40       	mov    0x40(%rsp),%r15
 105fd07:	0f 82 e0 f8 ff ff    	jb     105f5ed <my.vm::run+0x273d>
 105fd0d:	e9 91 0f 00 00       	jmp    1060ca3 <my.vm::run+0x3df3>
 105fd12:	49 89 f0             	mov    %rsi,%r8
 105fd15:	49 c1 f8 3f          	sar    $0x3f,%r8
 105fd19:	49 21 d0             	and    %rdx,%r8
 105fd1c:	49 01 f0             	add    %rsi,%r8
 105fd1f:	49 39 d0             	cmp    %rdx,%r8
 105fd22:	0f 82 38 f3 ff ff    	jb     105f060 <my.vm::run+0x21b0>
 105fd28:	e9 4c 0f 00 00       	jmp    1060c79 <my.vm::run+0x3dc9>
 105fd2d:	48 89 f0             	mov    %rsi,%rax
 105fd30:	48 c1 f8 3f          	sar    $0x3f,%rax
 105fd34:	48 21 d0             	and    %rdx,%rax
 105fd37:	48 01 f0             	add    %rsi,%rax
 105fd3a:	48 39 d0             	cmp    %rdx,%rax
 105fd3d:	0f 82 52 f2 ff ff    	jb     105ef95 <my.vm::run+0x20e5>
 105fd43:	e9 3d 0f 00 00       	jmp    1060c85 <my.vm::run+0x3dd5>
 105fd48:	48 89 d8             	mov    %rbx,%rax
 105fd4b:	48 c1 f8 3f          	sar    $0x3f,%rax
 105fd4f:	48 21 d0             	and    %rdx,%rax
 105fd52:	48 01 d8             	add    %rbx,%rax
 105fd55:	48 39 d0             	cmp    %rdx,%rax
 105fd58:	0f 82 57 f2 ff ff    	jb     105efb5 <my.vm::run+0x2105>
 105fd5e:	e9 4f 0f 00 00       	jmp    1060cb2 <my.vm::run+0x3e02>
 105fd63:	49 89 c0             	mov    %rax,%r8
 105fd66:	49 c1 f8 3f          	sar    $0x3f,%r8
 105fd6a:	49 21 c8             	and    %rcx,%r8
 105fd6d:	49 01 c0             	add    %rax,%r8
 105fd70:	49 39 c8             	cmp    %rcx,%r8
 105fd73:	0f 82 67 ea ff ff    	jb     105e7e0 <my.vm::run+0x1930>
 105fd79:	e9 13 0f 00 00       	jmp    1060c91 <my.vm::run+0x3de1>
 105fd7e:	48 89 e9             	mov    %rbp,%rcx
 105fd81:	48 c1 f9 3f          	sar    $0x3f,%rcx
 105fd85:	48 21 d1             	and    %rdx,%rcx
 105fd88:	48 01 e9             	add    %rbp,%rcx
 105fd8b:	48 39 d1             	cmp    %rdx,%rcx
 105fd8e:	0f 82 e9 f3 ff ff    	jb     105f17d <my.vm::run+0x22cd>
 105fd94:	e9 50 0e 00 00       	jmp    1060be9 <my.vm::run+0x3d39>
 105fd99:	48 8b 4c 24 38       	mov    0x38(%rsp),%rcx
 105fd9e:	48 89 c8             	mov    %rcx,%rax
 105fda1:	48 c1 f8 3f          	sar    $0x3f,%rax
 105fda5:	48 21 d0             	and    %rdx,%rax
 105fda8:	48 01 c8             	add    %rcx,%rax
 105fdab:	48 39 d0             	cmp    %rdx,%rax
 105fdae:	0f 82 57 d3 ff ff    	jb     105d10b <my.vm::run+0x25b>
 105fdb4:	e9 08 0f 00 00       	jmp    1060cc1 <my.vm::run+0x3e11>
 105fdb9:	48 89 e8             	mov    %rbp,%rax
 105fdbc:	48 c1 f8 3f          	sar    $0x3f,%rax
 105fdc0:	48 21 d0             	and    %rdx,%rax
 105fdc3:	48 01 e8             	add    %rbp,%rax
 105fdc6:	48 39 d0             	cmp    %rdx,%rax
 105fdc9:	0f 82 4d f6 ff ff    	jb     105f41c <my.vm::run+0x256c>
 105fdcf:	e9 57 0e 00 00       	jmp    1060c2b <my.vm::run+0x3d7b>
 105fdd4:	49 89 c0             	mov    %rax,%r8
 105fdd7:	49 c1 f8 3f          	sar    $0x3f,%r8
 105fddb:	49 21 d0             	and    %rdx,%r8
 105fdde:	49 01 c0             	add    %rax,%r8
 105fde1:	49 39 d0             	cmp    %rdx,%r8
 105fde4:	0f 82 1e ea ff ff    	jb     105e808 <my.vm::run+0x1958>
 105fdea:	e9 e3 0e 00 00       	jmp    1060cd2 <my.vm::run+0x3e22>
 105fdef:	48 89 f1             	mov    %rsi,%rcx
 105fdf2:	48 c1 f9 3f          	sar    $0x3f,%rcx
 105fdf6:	48 21 c1             	and    %rax,%rcx
 105fdf9:	48 01 f1             	add    %rsi,%rcx
 105fdfc:	48 39 c1             	cmp    %rax,%rcx
 105fdff:	0f 82 32 ef ff ff    	jb     105ed37 <my.vm::run+0x1e87>
 105fe05:	e9 30 0e 00 00       	jmp    1060c3a <my.vm::run+0x3d8a>
 105fe0a:	4d 89 c3             	mov    %r8,%r11
 105fe0d:	49 c1 fb 3f          	sar    $0x3f,%r11
 105fe11:	49 21 cb             	and    %rcx,%r11
 105fe14:	4d 01 c3             	add    %r8,%r11
 105fe17:	49 39 cb             	cmp    %rcx,%r11
 105fe1a:	0f 82 08 ea ff ff    	jb     105e828 <my.vm::run+0x1978>
 105fe20:	e9 70 0d 00 00       	jmp    1060b95 <my.vm::run+0x3ce5>
 105fe25:	49 01 f1             	add    %rsi,%r9
 105fe28:	49 39 d1             	cmp    %rdx,%r9
 105fe2b:	0f 82 16 ea ff ff    	jb     105e847 <my.vm::run+0x1997>
 105fe31:	e9 80 0d 00 00       	jmp    1060bb6 <my.vm::run+0x3d06>
 105fe36:	49 89 c0             	mov    %rax,%r8
 105fe39:	49 c1 f8 3f          	sar    $0x3f,%r8
 105fe3d:	49 21 d0             	and    %rdx,%r8
 105fe40:	49 01 c0             	add    %rax,%r8
 105fe43:	49 39 d0             	cmp    %rdx,%r8
 105fe46:	48 89 de             	mov    %rbx,%rsi
 105fe49:	0f 82 1e ea ff ff    	jb     105e86d <my.vm::run+0x19bd>
 105fe4f:	e9 16 0e 00 00       	jmp    1060c6a <my.vm::run+0x3dba>
 105fe54:	48 89 f7             	mov    %rsi,%rdi
 105fe57:	48 c1 ff 3f          	sar    $0x3f,%rdi
 105fe5b:	48 21 d7             	and    %rdx,%rdi
 105fe5e:	48 01 f7             	add    %rsi,%rdi
 105fe61:	48 39 d7             	cmp    %rdx,%rdi
 105fe64:	0f 82 5b ea ff ff    	jb     105e8c5 <my.vm::run+0x1a15>
 105fe6a:	e9 72 0e 00 00       	jmp    1060ce1 <my.vm::run+0x3e31>
 105fe6f:	48 89 ee             	mov    %rbp,%rsi
 105fe72:	48 c1 fe 3f          	sar    $0x3f,%rsi
 105fe76:	48 21 d6             	and    %rdx,%rsi
 105fe79:	48 01 ee             	add    %rbp,%rsi
 105fe7c:	48 39 d6             	cmp    %rdx,%rsi
 105fe7f:	0f 82 58 ea ff ff    	jb     105e8dd <my.vm::run+0x1a2d>
 105fe85:	48 8d 3d d4 64 02 00 	lea    0x264d4(%rip),%rdi        # 1086360 <core_durable_error.verbs+0x5310>
 105fe8c:	48 89 ee             	mov    %rbp,%rsi
 105fe8f:	e8 ec 56 fc ff       	call   1025580 <myl_core_trap>
 105fe94:	b9 02 00 00 00       	mov    $0x2,%ecx
 105fe99:	48 8b 84 24 60 01 00 	mov    0x160(%rsp),%rax
 105fea0:	00 
 105fea1:	48 89 08             	mov    %rcx,(%rax)
 105fea4:	48 81 c4 28 08 00 00 	add    $0x828,%rsp
 105feab:	5b                   	pop    %rbx
 105feac:	41 5c                	pop    %r12
 105feae:	41 5d                	pop    %r13
 105feb0:	41 5e                	pop    %r14
 105feb2:	41 5f                	pop    %r15
 105feb4:	5d                   	pop    %rbp
 105feb5:	c3                   	ret
 105feb6:	49 8b 81 80 00 00 00 	mov    0x80(%r9),%rax
 105febd:	48 89 c6             	mov    %rax,%rsi
 105fec0:	48 ff ce             	dec    %rsi
 105fec3:	0f 80 65 0a 00 00    	jo     106092e <my.vm::run+0x3a7e>
 105fec9:	49 89 b1 80 00 00 00 	mov    %rsi,0x80(%r9)
 105fed0:	49 8b 41 78          	mov    0x78(%r9),%rax
 105fed4:	48 8b 50 08          	mov    0x8(%rax),%rdx
 105fed8:	48 39 d6             	cmp    %rdx,%rsi
 105fedb:	73 7d                	jae    105ff5a <my.vm::run+0x30aa>
 105fedd:	31 c9                	xor    %ecx,%ecx
 105fedf:	eb b8                	jmp    105fe99 <my.vm::run+0x2fe9>
 105fee1:	48 8d 3d 38 2f 02 00 	lea    0x22f38(%rip),%rdi        # 1082e20 <core_durable_error.verbs+0x1dd0>
 105fee8:	48 be ff ff ff ff ff 	movabs $0x7fffffffffffffff,%rsi
 105feef:	ff ff 7f 
 105fef2:	ba 01 00 00 00       	mov    $0x1,%edx
 105fef7:	e8 84 56 fc ff       	call   1025580 <myl_core_trap>
 105fefc:	48 89 f1             	mov    %rsi,%rcx
 105feff:	48 c1 f9 3f          	sar    $0x3f,%rcx
 105ff03:	48 21 d1             	and    %rdx,%rcx
 105ff06:	48 01 f1             	add    %rsi,%rcx
 105ff09:	48 39 d1             	cmp    %rdx,%rcx
 105ff0c:	0f 82 f5 cf ff ff    	jb     105cf07 <my.vm::run+0x57>
 105ff12:	48 8d 3d 87 15 02 00 	lea    0x21587(%rip),%rdi        # 10814a0 <core_durable_error.verbs+0x450>
 105ff19:	e8 62 56 fc ff       	call   1025580 <myl_core_trap>
 105ff1e:	48 8d 3d 4b 18 02 00 	lea    0x2184b(%rip),%rdi        # 1081770 <core_durable_error.verbs+0x720>
 105ff25:	ba 01 00 00 00       	mov    $0x1,%edx
 105ff2a:	4c 89 d6             	mov    %r10,%rsi
 105ff2d:	e8 4e 56 fc ff       	call   1025580 <myl_core_trap>
 105ff32:	48 8d 3d e7 2e 02 00 	lea    0x22ee7(%rip),%rdi        # 1082e20 <core_durable_error.verbs+0x1dd0>
 105ff39:	ba 01 00 00 00       	mov    $0x1,%edx
 105ff3e:	4c 89 ee             	mov    %r13,%rsi
 105ff41:	e8 3a 56 fc ff       	call   1025580 <myl_core_trap>
 105ff46:	48 8d 3d d3 2e 02 00 	lea    0x22ed3(%rip),%rdi        # 1082e20 <core_durable_error.verbs+0x1dd0>
 105ff4d:	ba 01 00 00 00       	mov    $0x1,%edx
 105ff52:	4c 89 fe             	mov    %r15,%rsi
 105ff55:	e8 26 56 fc ff       	call   1025580 <myl_core_trap>
 105ff5a:	48 89 f0             	mov    %rsi,%rax
 105ff5d:	48 c1 f8 3f          	sar    $0x3f,%rax
 105ff61:	48 21 d0             	and    %rdx,%rax
 105ff64:	48 01 f0             	add    %rsi,%rax
 105ff67:	48 39 d0             	cmp    %rdx,%rax
 105ff6a:	0f 82 6d ff ff ff    	jb     105fedd <my.vm::run+0x302d>
 105ff70:	48 8d 3d 79 1f 02 00 	lea    0x21f79(%rip),%rdi        # 1081ef0 <core_durable_error.verbs+0xea0>
 105ff77:	e8 04 56 fc ff       	call   1025580 <myl_core_trap>
 105ff7c:	83 f9 09             	cmp    $0x9,%ecx
 105ff7f:	0f 87 89 07 00 00    	ja     106070e <my.vm::run+0x385e>
 105ff85:	89 c8                	mov    %ecx,%eax
 105ff87:	48 8d 0d 7a 75 fa ff 	lea    -0x58a86(%rip),%rcx        # 1007508 <core_number_pairs+0x2a8>
 105ff8e:	48 63 04 81          	movslq (%rcx,%rax,4),%rax
 105ff92:	48 01 c8             	add    %rcx,%rax
 105ff95:	ff e0                	jmp    *%rax
 105ff97:	48 8d 3d b2 6a 02 00 	lea    0x26ab2(%rip),%rdi        # 1086a50 <core_durable_error.verbs+0x5a00>
 105ff9e:	e8 5d a9 fc ff       	call   102a900 <myl_core_assert_fail>
 105ffa3:	48 8d 3d 16 3a 02 00 	lea    0x23a16(%rip),%rdi        # 10839c0 <core_durable_error.verbs+0x2970>
 105ffaa:	4c 89 e6             	mov    %r12,%rsi
 105ffad:	e8 ce 55 fc ff       	call   1025580 <myl_core_trap>
 105ffb2:	48 8d 3d a7 39 02 00 	lea    0x239a7(%rip),%rdi        # 1083960 <core_durable_error.verbs+0x2910>
 105ffb9:	48 8b 74 24 20       	mov    0x20(%rsp),%rsi
 105ffbe:	48 89 c2             	mov    %rax,%rdx
 105ffc1:	e8 ba 55 fc ff       	call   1025580 <myl_core_trap>
 105ffc6:	48 8d 3d c3 39 02 00 	lea    0x239c3(%rip),%rdi        # 1083990 <core_durable_error.verbs+0x2940>
 105ffcd:	4c 89 e6             	mov    %r12,%rsi
 105ffd0:	e8 ab 55 fc ff       	call   1025580 <myl_core_trap>
 105ffd5:	48 8d 3d e4 33 02 00 	lea    0x233e4(%rip),%rdi        # 10833c0 <core_durable_error.verbs+0x2370>
 105ffdc:	ba 01 00 00 00       	mov    $0x1,%edx
 105ffe1:	48 89 ce             	mov    %rcx,%rsi
 105ffe4:	e8 97 55 fc ff       	call   1025580 <myl_core_trap>
 105ffe9:	83 f8 01             	cmp    $0x1,%eax
 105ffec:	0f 84 1b 02 00 00    	je     106020d <my.vm::run+0x335d>
 105fff2:	85 c0                	test   %eax,%eax
 105fff4:	0f 85 1f 02 00 00    	jne    1060219 <my.vm::run+0x3369>
 105fffa:	48 8d 3d 6f 32 02 00 	lea    0x2326f(%rip),%rdi        # 1083270 <core_durable_error.verbs+0x2220>
 1060001:	e8 fa a8 fc ff       	call   102a900 <myl_core_assert_fail>
 1060006:	83 fa 01             	cmp    $0x1,%edx
 1060009:	0f 84 16 02 00 00    	je     1060225 <my.vm::run+0x3375>
 106000f:	85 d2                	test   %edx,%edx
 1060011:	0f 85 1a 02 00 00    	jne    1060231 <my.vm::run+0x3381>
 1060017:	48 8d 3d 52 32 02 00 	lea    0x23252(%rip),%rdi        # 1083270 <core_durable_error.verbs+0x2220>
 106001e:	e8 dd a8 fc ff       	call   102a900 <myl_core_assert_fail>
 1060023:	83 f8 01             	cmp    $0x1,%eax
 1060026:	0f 84 11 02 00 00    	je     106023d <my.vm::run+0x338d>
 106002c:	85 c0                	test   %eax,%eax
 106002e:	0f 85 15 02 00 00    	jne    1060249 <my.vm::run+0x3399>
 1060034:	48 8d 3d 35 32 02 00 	lea    0x23235(%rip),%rdi        # 1083270 <core_durable_error.verbs+0x2220>
 106003b:	e8 c0 a8 fc ff       	call   102a900 <myl_core_assert_fail>
 1060040:	83 f8 01             	cmp    $0x1,%eax
 1060043:	0f 84 0c 02 00 00    	je     1060255 <my.vm::run+0x33a5>
 1060049:	85 c0                	test   %eax,%eax
 106004b:	0f 85 10 02 00 00    	jne    1060261 <my.vm::run+0x33b1>
 1060051:	48 8d 3d 18 32 02 00 	lea    0x23218(%rip),%rdi        # 1083270 <core_durable_error.verbs+0x2220>
 1060058:	e8 a3 a8 fc ff       	call   102a900 <myl_core_assert_fail>
 106005d:	83 f8 01             	cmp    $0x1,%eax
 1060060:	0f 84 07 02 00 00    	je     106026d <my.vm::run+0x33bd>
 1060066:	85 c0                	test   %eax,%eax
 1060068:	0f 85 0b 02 00 00    	jne    1060279 <my.vm::run+0x33c9>
 106006e:	48 8d 3d fb 31 02 00 	lea    0x231fb(%rip),%rdi        # 1083270 <core_durable_error.verbs+0x2220>
 1060075:	e8 86 a8 fc ff       	call   102a900 <myl_core_assert_fail>
 106007a:	83 f8 01             	cmp    $0x1,%eax
 106007d:	0f 84 02 02 00 00    	je     1060285 <my.vm::run+0x33d5>
 1060083:	85 c0                	test   %eax,%eax
 1060085:	0f 85 06 02 00 00    	jne    1060291 <my.vm::run+0x33e1>
 106008b:	48 8d 3d de 31 02 00 	lea    0x231de(%rip),%rdi        # 1083270 <core_durable_error.verbs+0x2220>
 1060092:	e8 69 a8 fc ff       	call   102a900 <myl_core_assert_fail>
 1060097:	83 f8 01             	cmp    $0x1,%eax
 106009a:	0f 84 4a 02 00 00    	je     10602ea <my.vm::run+0x343a>
 10600a0:	85 c0                	test   %eax,%eax
 10600a2:	0f 85 4e 02 00 00    	jne    10602f6 <my.vm::run+0x3446>
 10600a8:	48 8d 3d c1 31 02 00 	lea    0x231c1(%rip),%rdi        # 1083270 <core_durable_error.verbs+0x2220>
 10600af:	e8 4c a8 fc ff       	call   102a900 <myl_core_assert_fail>
 10600b4:	83 f8 01             	cmp    $0x1,%eax
 10600b7:	0f 84 45 02 00 00    	je     1060302 <my.vm::run+0x3452>
 10600bd:	85 c0                	test   %eax,%eax
 10600bf:	0f 85 49 02 00 00    	jne    106030e <my.vm::run+0x345e>
 10600c5:	48 8d 3d a4 31 02 00 	lea    0x231a4(%rip),%rdi        # 1083270 <core_durable_error.verbs+0x2220>
 10600cc:	e8 2f a8 fc ff       	call   102a900 <myl_core_assert_fail>
 10600d1:	83 f9 01             	cmp    $0x1,%ecx
 10600d4:	0f 84 67 02 00 00    	je     1060341 <my.vm::run+0x3491>
 10600da:	85 c9                	test   %ecx,%ecx
 10600dc:	0f 85 6b 02 00 00    	jne    106034d <my.vm::run+0x349d>
 10600e2:	48 8d 3d 87 31 02 00 	lea    0x23187(%rip),%rdi        # 1083270 <core_durable_error.verbs+0x2220>
 10600e9:	e8 12 a8 fc ff       	call   102a900 <myl_core_assert_fail>
 10600ee:	83 f8 01             	cmp    $0x1,%eax
 10600f1:	0f 84 62 02 00 00    	je     1060359 <my.vm::run+0x34a9>
 10600f7:	85 c0                	test   %eax,%eax
 10600f9:	0f 85 66 02 00 00    	jne    1060365 <my.vm::run+0x34b5>
 10600ff:	48 8d 3d 6a 31 02 00 	lea    0x2316a(%rip),%rdi        # 1083270 <core_durable_error.verbs+0x2220>
 1060106:	e8 f5 a7 fc ff       	call   102a900 <myl_core_assert_fail>
 106010b:	83 f8 01             	cmp    $0x1,%eax
 106010e:	0f 84 5d 02 00 00    	je     1060371 <my.vm::run+0x34c1>
 1060114:	85 c0                	test   %eax,%eax
 1060116:	0f 85 61 02 00 00    	jne    106037d <my.vm::run+0x34cd>
 106011c:	48 8d 3d 4d 31 02 00 	lea    0x2314d(%rip),%rdi        # 1083270 <core_durable_error.verbs+0x2220>
 1060123:	e8 d8 a7 fc ff       	call   102a900 <myl_core_assert_fail>
 1060128:	83 f8 01             	cmp    $0x1,%eax
 106012b:	0f 84 6c 02 00 00    	je     106039d <my.vm::run+0x34ed>
 1060131:	85 c0                	test   %eax,%eax
 1060133:	0f 85 70 02 00 00    	jne    10603a9 <my.vm::run+0x34f9>
 1060139:	48 8d 3d 30 31 02 00 	lea    0x23130(%rip),%rdi        # 1083270 <core_durable_error.verbs+0x2220>
 1060140:	e8 bb a7 fc ff       	call   102a900 <myl_core_assert_fail>
 1060145:	83 fa 01             	cmp    $0x1,%edx
 1060148:	0f 84 7b 02 00 00    	je     10603c9 <my.vm::run+0x3519>
 106014e:	85 d2                	test   %edx,%edx
 1060150:	0f 85 7f 02 00 00    	jne    10603d5 <my.vm::run+0x3525>
 1060156:	48 8d 3d 13 31 02 00 	lea    0x23113(%rip),%rdi        # 1083270 <core_durable_error.verbs+0x2220>
 106015d:	e8 9e a7 fc ff       	call   102a900 <myl_core_assert_fail>
 1060162:	48 8d 3d b7 32 02 00 	lea    0x232b7(%rip),%rdi        # 1083420 <core_durable_error.verbs+0x23d0>
 1060169:	ba 01 00 00 00       	mov    $0x1,%edx
 106016e:	e8 0d 54 fc ff       	call   1025580 <myl_core_trap>
 1060173:	83 f8 01             	cmp    $0x1,%eax
 1060176:	0f 84 3a 06 00 00    	je     10607b6 <my.vm::run+0x3906>
 106017c:	85 c0                	test   %eax,%eax
 106017e:	0f 85 3e 06 00 00    	jne    10607c2 <my.vm::run+0x3912>
 1060184:	48 8d 3d e5 30 02 00 	lea    0x230e5(%rip),%rdi        # 1083270 <core_durable_error.verbs+0x2220>
 106018b:	e8 70 a7 fc ff       	call   102a900 <myl_core_assert_fail>
 1060190:	83 f8 01             	cmp    $0x1,%eax
 1060193:	0f 84 35 06 00 00    	je     10607ce <my.vm::run+0x391e>
 1060199:	85 c0                	test   %eax,%eax
 106019b:	0f 85 39 06 00 00    	jne    10607da <my.vm::run+0x392a>
 10601a1:	48 8d 3d c8 30 02 00 	lea    0x230c8(%rip),%rdi        # 1083270 <core_durable_error.verbs+0x2220>
 10601a8:	e8 53 a7 fc ff       	call   102a900 <myl_core_assert_fail>
 10601ad:	48 8d 3d cc 68 02 00 	lea    0x268cc(%rip),%rdi        # 1086a80 <core_durable_error.verbs+0x5a30>
 10601b4:	e8 47 a7 fc ff       	call   102a900 <myl_core_assert_fail>
 10601b9:	48 8d 3d 80 69 02 00 	lea    0x26980(%rip),%rdi        # 1086b40 <core_durable_error.verbs+0x5af0>
 10601c0:	e8 3b a7 fc ff       	call   102a900 <myl_core_assert_fail>
 10601c5:	48 8d 3d e4 68 02 00 	lea    0x268e4(%rip),%rdi        # 1086ab0 <core_durable_error.verbs+0x5a60>
 10601cc:	e8 2f a7 fc ff       	call   102a900 <myl_core_assert_fail>
 10601d1:	48 8d 3d 08 69 02 00 	lea    0x26908(%rip),%rdi        # 1086ae0 <core_durable_error.verbs+0x5a90>
 10601d8:	e8 23 a7 fc ff       	call   102a900 <myl_core_assert_fail>
 10601dd:	48 8d 3d 2c 69 02 00 	lea    0x2692c(%rip),%rdi        # 1086b10 <core_durable_error.verbs+0x5ac0>
 10601e4:	e8 17 a7 fc ff       	call   102a900 <myl_core_assert_fail>
 10601e9:	48 8d 3d 80 69 02 00 	lea    0x26980(%rip),%rdi        # 1086b70 <core_durable_error.verbs+0x5b20>
 10601f0:	e8 0b a7 fc ff       	call   102a900 <myl_core_assert_fail>
 10601f5:	48 8d 3d a4 69 02 00 	lea    0x269a4(%rip),%rdi        # 1086ba0 <core_durable_error.verbs+0x5b50>
 10601fc:	e8 ff a6 fc ff       	call   102a900 <myl_core_assert_fail>
 1060201:	48 8d 3d c8 69 02 00 	lea    0x269c8(%rip),%rdi        # 1086bd0 <core_durable_error.verbs+0x5b80>
 1060208:	e8 f3 a6 fc ff       	call   102a900 <myl_core_assert_fail>
 106020d:	48 8d 3d 8c 30 02 00 	lea    0x2308c(%rip),%rdi        # 10832a0 <core_durable_error.verbs+0x2250>
 1060214:	e8 e7 a6 fc ff       	call   102a900 <myl_core_assert_fail>
 1060219:	48 8d 3d b0 30 02 00 	lea    0x230b0(%rip),%rdi        # 10832d0 <core_durable_error.verbs+0x2280>
 1060220:	e8 db a6 fc ff       	call   102a900 <myl_core_assert_fail>
 1060225:	48 8d 3d 74 30 02 00 	lea    0x23074(%rip),%rdi        # 10832a0 <core_durable_error.verbs+0x2250>
 106022c:	e8 cf a6 fc ff       	call   102a900 <myl_core_assert_fail>
 1060231:	48 8d 3d 98 30 02 00 	lea    0x23098(%rip),%rdi        # 10832d0 <core_durable_error.verbs+0x2280>
 1060238:	e8 c3 a6 fc ff       	call   102a900 <myl_core_assert_fail>
 106023d:	48 8d 3d 5c 30 02 00 	lea    0x2305c(%rip),%rdi        # 10832a0 <core_durable_error.verbs+0x2250>
 1060244:	e8 b7 a6 fc ff       	call   102a900 <myl_core_assert_fail>
 1060249:	48 8d 3d 80 30 02 00 	lea    0x23080(%rip),%rdi        # 10832d0 <core_durable_error.verbs+0x2280>
 1060250:	e8 ab a6 fc ff       	call   102a900 <myl_core_assert_fail>
 1060255:	48 8d 3d 44 30 02 00 	lea    0x23044(%rip),%rdi        # 10832a0 <core_durable_error.verbs+0x2250>
 106025c:	e8 9f a6 fc ff       	call   102a900 <myl_core_assert_fail>
 1060261:	48 8d 3d 68 30 02 00 	lea    0x23068(%rip),%rdi        # 10832d0 <core_durable_error.verbs+0x2280>
 1060268:	e8 93 a6 fc ff       	call   102a900 <myl_core_assert_fail>
 106026d:	48 8d 3d 2c 30 02 00 	lea    0x2302c(%rip),%rdi        # 10832a0 <core_durable_error.verbs+0x2250>
 1060274:	e8 87 a6 fc ff       	call   102a900 <myl_core_assert_fail>
 1060279:	48 8d 3d 50 30 02 00 	lea    0x23050(%rip),%rdi        # 10832d0 <core_durable_error.verbs+0x2280>
 1060280:	e8 7b a6 fc ff       	call   102a900 <myl_core_assert_fail>
 1060285:	48 8d 3d 14 30 02 00 	lea    0x23014(%rip),%rdi        # 10832a0 <core_durable_error.verbs+0x2250>
 106028c:	e8 6f a6 fc ff       	call   102a900 <myl_core_assert_fail>
 1060291:	48 8d 3d 38 30 02 00 	lea    0x23038(%rip),%rdi        # 10832d0 <core_durable_error.verbs+0x2280>
 1060298:	e8 63 a6 fc ff       	call   102a900 <myl_core_assert_fail>
 106029d:	48 8d 3d 6c 14 02 00 	lea    0x2146c(%rip),%rdi        # 1081710 <core_durable_error.verbs+0x6c0>
 10602a4:	ba 01 00 00 00       	mov    $0x1,%edx
 10602a9:	48 89 de             	mov    %rbx,%rsi
 10602ac:	e8 cf 52 fc ff       	call   1025580 <myl_core_trap>
 10602b1:	48 8d 3d 68 2b 02 00 	lea    0x22b68(%rip),%rdi        # 1082e20 <core_durable_error.verbs+0x1dd0>
 10602b8:	ba 01 00 00 00       	mov    $0x1,%edx
 10602bd:	48 89 ee             	mov    %rbp,%rsi
 10602c0:	e8 bb 52 fc ff       	call   1025580 <myl_core_trap>
 10602c5:	48 8d 3d b4 31 02 00 	lea    0x231b4(%rip),%rdi        # 1083480 <core_durable_error.verbs+0x2430>
 10602cc:	ba 01 00 00 00       	mov    $0x1,%edx
 10602d1:	48 89 c6             	mov    %rax,%rsi
 10602d4:	e8 a7 52 fc ff       	call   1025580 <myl_core_trap>
 10602d9:	48 8d 3d 20 39 02 00 	lea    0x23920(%rip),%rdi        # 1083c00 <core_durable_error.verbs+0x2bb0>
 10602e0:	ba 01 00 00 00       	mov    $0x1,%edx
 10602e5:	e8 96 52 fc ff       	call   1025580 <myl_core_trap>
 10602ea:	48 8d 3d af 2f 02 00 	lea    0x22faf(%rip),%rdi        # 10832a0 <core_durable_error.verbs+0x2250>
 10602f1:	e8 0a a6 fc ff       	call   102a900 <myl_core_assert_fail>
 10602f6:	48 8d 3d d3 2f 02 00 	lea    0x22fd3(%rip),%rdi        # 10832d0 <core_durable_error.verbs+0x2280>
 10602fd:	e8 fe a5 fc ff       	call   102a900 <myl_core_assert_fail>
 1060302:	48 8d 3d 97 2f 02 00 	lea    0x22f97(%rip),%rdi        # 10832a0 <core_durable_error.verbs+0x2250>
 1060309:	e8 f2 a5 fc ff       	call   102a900 <myl_core_assert_fail>
 106030e:	48 8d 3d bb 2f 02 00 	lea    0x22fbb(%rip),%rdi        # 10832d0 <core_durable_error.verbs+0x2280>
 1060315:	e8 e6 a5 fc ff       	call   102a900 <myl_core_assert_fail>
 106031a:	48 8d 3d 0f 1b 02 00 	lea    0x21b0f(%rip),%rdi        # 1081e30 <core_durable_error.verbs+0xde0>
 1060321:	ba 01 00 00 00       	mov    $0x1,%edx
 1060326:	e8 55 52 fc ff       	call   1025580 <myl_core_trap>
 106032b:	48 8d 3d de 37 02 00 	lea    0x237de(%rip),%rdi        # 1083b10 <core_durable_error.verbs+0x2ac0>
 1060332:	ba 01 00 00 00       	mov    $0x1,%edx
 1060337:	48 8b 74 24 38       	mov    0x38(%rsp),%rsi
 106033c:	e8 3f 52 fc ff       	call   1025580 <myl_core_trap>
 1060341:	48 8d 3d 58 2f 02 00 	lea    0x22f58(%rip),%rdi        # 10832a0 <core_durable_error.verbs+0x2250>
 1060348:	e8 b3 a5 fc ff       	call   102a900 <myl_core_assert_fail>
 106034d:	48 8d 3d 7c 2f 02 00 	lea    0x22f7c(%rip),%rdi        # 10832d0 <core_durable_error.verbs+0x2280>
 1060354:	e8 a7 a5 fc ff       	call   102a900 <myl_core_assert_fail>
 1060359:	48 8d 3d 40 2f 02 00 	lea    0x22f40(%rip),%rdi        # 10832a0 <core_durable_error.verbs+0x2250>
 1060360:	e8 9b a5 fc ff       	call   102a900 <myl_core_assert_fail>
 1060365:	48 8d 3d 64 2f 02 00 	lea    0x22f64(%rip),%rdi        # 10832d0 <core_durable_error.verbs+0x2280>
 106036c:	e8 8f a5 fc ff       	call   102a900 <myl_core_assert_fail>
 1060371:	48 8d 3d 28 2f 02 00 	lea    0x22f28(%rip),%rdi        # 10832a0 <core_durable_error.verbs+0x2250>
 1060378:	e8 83 a5 fc ff       	call   102a900 <myl_core_assert_fail>
 106037d:	48 8d 3d 4c 2f 02 00 	lea    0x22f4c(%rip),%rdi        # 10832d0 <core_durable_error.verbs+0x2280>
 1060384:	e8 77 a5 fc ff       	call   102a900 <myl_core_assert_fail>
 1060389:	48 8d 3d d0 1a 02 00 	lea    0x21ad0(%rip),%rdi        # 1081e60 <core_durable_error.verbs+0xe10>
 1060390:	ba 01 00 00 00       	mov    $0x1,%edx
 1060395:	48 89 de             	mov    %rbx,%rsi
 1060398:	e8 e3 51 fc ff       	call   1025580 <myl_core_trap>
 106039d:	48 8d 3d fc 2e 02 00 	lea    0x22efc(%rip),%rdi        # 10832a0 <core_durable_error.verbs+0x2250>
 10603a4:	e8 57 a5 fc ff       	call   102a900 <myl_core_assert_fail>
 10603a9:	48 8d 3d 20 2f 02 00 	lea    0x22f20(%rip),%rdi        # 10832d0 <core_durable_error.verbs+0x2280>
 10603b0:	e8 4b a5 fc ff       	call   102a900 <myl_core_assert_fail>
 10603b5:	48 8d 3d c4 18 02 00 	lea    0x218c4(%rip),%rdi        # 1081c80 <core_durable_error.verbs+0xc30>
 10603bc:	ba 01 00 00 00       	mov    $0x1,%edx
 10603c1:	48 89 ee             	mov    %rbp,%rsi
 10603c4:	e8 b7 51 fc ff       	call   1025580 <myl_core_trap>
 10603c9:	48 8d 3d d0 2e 02 00 	lea    0x22ed0(%rip),%rdi        # 10832a0 <core_durable_error.verbs+0x2250>
 10603d0:	e8 2b a5 fc ff       	call   102a900 <myl_core_assert_fail>
 10603d5:	48 8d 3d f4 2e 02 00 	lea    0x22ef4(%rip),%rdi        # 10832d0 <core_durable_error.verbs+0x2280>
 10603dc:	e8 1f a5 fc ff       	call   102a900 <myl_core_assert_fail>
 10603e1:	48 8d 3d d8 14 02 00 	lea    0x214d8(%rip),%rdi        # 10818c0 <core_durable_error.verbs+0x870>
 10603e8:	ba 01 00 00 00       	mov    $0x1,%edx
 10603ed:	48 89 de             	mov    %rbx,%rsi
 10603f0:	e8 8b 51 fc ff       	call   1025580 <myl_core_trap>
 10603f5:	48 8d 3d c4 17 02 00 	lea    0x217c4(%rip),%rdi        # 1081bc0 <core_durable_error.verbs+0xb70>
 10603fc:	ba 01 00 00 00       	mov    $0x1,%edx
 1060401:	48 89 de             	mov    %rbx,%rsi
 1060404:	e8 77 51 fc ff       	call   1025580 <myl_core_trap>
 1060409:	48 8d 3d d0 36 02 00 	lea    0x236d0(%rip),%rdi        # 1083ae0 <core_durable_error.verbs+0x2a90>
 1060410:	ba 01 00 00 00       	mov    $0x1,%edx
 1060415:	e8 66 51 fc ff       	call   1025580 <myl_core_trap>
 106041a:	48 8d 3d 1f 1c 02 00 	lea    0x21c1f(%rip),%rdi        # 1082040 <core_durable_error.verbs+0xff0>
 1060421:	ba 01 00 00 00       	mov    $0x1,%edx
 1060426:	e8 55 51 fc ff       	call   1025580 <myl_core_trap>
 106042b:	48 8d 3d ae 15 02 00 	lea    0x215ae(%rip),%rdi        # 10819e0 <core_durable_error.verbs+0x990>
 1060432:	ba 01 00 00 00       	mov    $0x1,%edx
 1060437:	48 89 de             	mov    %rbx,%rsi
 106043a:	e8 41 51 fc ff       	call   1025580 <myl_core_trap>
 106043f:	48 8d 3d 9a 1b 02 00 	lea    0x21b9a(%rip),%rdi        # 1081fe0 <core_durable_error.verbs+0xf90>
 1060446:	ba 01 00 00 00       	mov    $0x1,%edx
 106044b:	e8 30 51 fc ff       	call   1025580 <myl_core_trap>
 1060450:	48 8d 3d c9 17 02 00 	lea    0x217c9(%rip),%rdi        # 1081c20 <core_durable_error.verbs+0xbd0>
 1060457:	ba 01 00 00 00       	mov    $0x1,%edx
 106045c:	48 89 de             	mov    %rbx,%rsi
 106045f:	e8 1c 51 fc ff       	call   1025580 <myl_core_trap>
 1060464:	48 8d 3d b5 2c 02 00 	lea    0x22cb5(%rip),%rdi        # 1083120 <core_durable_error.verbs+0x20d0>
 106046b:	ba 01 00 00 00       	mov    $0x1,%edx
 1060470:	e8 0b 51 fc ff       	call   1025580 <myl_core_trap>
 1060475:	48 8d 3d 54 10 02 00 	lea    0x21054(%rip),%rdi        # 10814d0 <core_durable_error.verbs+0x480>
 106047c:	48 8b 74 24 20       	mov    0x20(%rsp),%rsi
 1060481:	48 89 c2             	mov    %rax,%rdx
 1060484:	e8 f7 50 fc ff       	call   1025580 <myl_core_trap>
 1060489:	48 8d 3d 90 29 02 00 	lea    0x22990(%rip),%rdi        # 1082e20 <core_durable_error.verbs+0x1dd0>
 1060490:	ba 01 00 00 00       	mov    $0x1,%edx
 1060495:	4c 89 ee             	mov    %r13,%rsi
 1060498:	e8 e3 50 fc ff       	call   1025580 <myl_core_trap>
 106049d:	48 8d 3d 6c 18 02 00 	lea    0x2186c(%rip),%rdi        # 1081d10 <core_durable_error.verbs+0xcc0>
 10604a4:	48 89 ce             	mov    %rcx,%rsi
 10604a7:	48 89 c2             	mov    %rax,%rdx
 10604aa:	e8 d1 50 fc ff       	call   1025580 <myl_core_trap>
 10604af:	48 8d 3d 6a 29 02 00 	lea    0x2296a(%rip),%rdi        # 1082e20 <core_durable_error.verbs+0x1dd0>
 10604b6:	ba 01 00 00 00       	mov    $0x1,%edx
 10604bb:	48 89 ee             	mov    %rbp,%rsi
 10604be:	e8 bd 50 fc ff       	call   1025580 <myl_core_trap>
 10604c3:	48 8d 3d 16 18 02 00 	lea    0x21816(%rip),%rdi        # 1081ce0 <core_durable_error.verbs+0xc90>
 10604ca:	ba 01 00 00 00       	mov    $0x1,%edx
 10604cf:	48 89 de             	mov    %rbx,%rsi
 10604d2:	e8 a9 50 fc ff       	call   1025580 <myl_core_trap>
 10604d7:	48 8d 3d 22 13 02 00 	lea    0x21322(%rip),%rdi        # 1081800 <core_durable_error.verbs+0x7b0>
 10604de:	ba 01 00 00 00       	mov    $0x1,%edx
 10604e3:	48 89 de             	mov    %rbx,%rsi
 10604e6:	e8 95 50 fc ff       	call   1025580 <myl_core_trap>
 10604eb:	48 8d 3d 2e 29 02 00 	lea    0x2292e(%rip),%rdi        # 1082e20 <core_durable_error.verbs+0x1dd0>
 10604f2:	ba 01 00 00 00       	mov    $0x1,%edx
 10604f7:	4c 89 ee             	mov    %r13,%rsi
 10604fa:	e8 81 50 fc ff       	call   1025580 <myl_core_trap>
 10604ff:	48 8d 3d 1a 29 02 00 	lea    0x2291a(%rip),%rdi        # 1082e20 <core_durable_error.verbs+0x1dd0>
 1060506:	ba 01 00 00 00       	mov    $0x1,%edx
 106050b:	4c 89 fe             	mov    %r15,%rsi
 106050e:	e8 6d 50 fc ff       	call   1025580 <myl_core_trap>
 1060513:	48 8d 3d 96 1a 02 00 	lea    0x21a96(%rip),%rdi        # 1081fb0 <core_durable_error.verbs+0xf60>
 106051a:	ba 01 00 00 00       	mov    $0x1,%edx
 106051f:	e8 5c 50 fc ff       	call   1025580 <myl_core_trap>
 1060524:	48 8d 3d 85 29 02 00 	lea    0x22985(%rip),%rdi        # 1082eb0 <core_durable_error.verbs+0x1e60>
 106052b:	ba 01 00 00 00       	mov    $0x1,%edx
 1060530:	48 89 c6             	mov    %rax,%rsi
 1060533:	e8 48 50 fc ff       	call   1025580 <myl_core_trap>
 1060538:	48 8d 3d 21 16 02 00 	lea    0x21621(%rip),%rdi        # 1081b60 <core_durable_error.verbs+0xb10>
 106053f:	ba 01 00 00 00       	mov    $0x1,%edx
 1060544:	48 89 de             	mov    %rbx,%rsi
 1060547:	e8 34 50 fc ff       	call   1025580 <myl_core_trap>
 106054c:	48 8d 3d 6d 10 02 00 	lea    0x2106d(%rip),%rdi        # 10815c0 <core_durable_error.verbs+0x570>
 1060553:	e8 28 50 fc ff       	call   1025580 <myl_core_trap>
 1060558:	48 8d 3d f1 13 02 00 	lea    0x213f1(%rip),%rdi        # 1081950 <core_durable_error.verbs+0x900>
 106055f:	ba 01 00 00 00       	mov    $0x1,%edx
 1060564:	48 89 de             	mov    %rbx,%rsi
 1060567:	e8 14 50 fc ff       	call   1025580 <myl_core_trap>
 106056c:	48 8d 3d 2d 15 02 00 	lea    0x2152d(%rip),%rdi        # 1081aa0 <core_durable_error.verbs+0xa50>
 1060573:	ba 01 00 00 00       	mov    $0x1,%edx
 1060578:	48 89 de             	mov    %rbx,%rsi
 106057b:	e8 00 50 fc ff       	call   1025580 <myl_core_trap>
 1060580:	48 8d 3d d9 0f 02 00 	lea    0x20fd9(%rip),%rdi        # 1081560 <core_durable_error.verbs+0x510>
 1060587:	e8 f4 4f fc ff       	call   1025580 <myl_core_trap>
 106058c:	48 8d 3d 0d 30 02 00 	lea    0x2300d(%rip),%rdi        # 10835a0 <core_durable_error.verbs+0x2550>
 1060593:	ba 01 00 00 00       	mov    $0x1,%edx
 1060598:	e8 e3 4f fc ff       	call   1025580 <myl_core_trap>
 106059d:	48 8d 3d 5c 33 02 00 	lea    0x2335c(%rip),%rdi        # 1083900 <core_durable_error.verbs+0x28b0>
 10605a4:	48 89 ce             	mov    %rcx,%rsi
 10605a7:	48 89 c2             	mov    %rax,%rdx
 10605aa:	e8 d1 4f fc ff       	call   1025580 <myl_core_trap>
 10605af:	48 8d 3d 6a 13 02 00 	lea    0x2136a(%rip),%rdi        # 1081920 <core_durable_error.verbs+0x8d0>
 10605b6:	ba 01 00 00 00       	mov    $0x1,%edx
 10605bb:	48 89 de             	mov    %rbx,%rsi
 10605be:	e8 bd 4f fc ff       	call   1025580 <myl_core_trap>
 10605c3:	48 8d 3d 86 34 02 00 	lea    0x23486(%rip),%rdi        # 1083a50 <core_durable_error.verbs+0x2a00>
 10605ca:	ba 01 00 00 00       	mov    $0x1,%edx
 10605cf:	e8 ac 4f fc ff       	call   1025580 <myl_core_trap>
 10605d4:	48 8d 3d 95 17 02 00 	lea    0x21795(%rip),%rdi        # 1081d70 <core_durable_error.verbs+0xd20>
 10605db:	ba 01 00 00 00       	mov    $0x1,%edx
 10605e0:	48 89 de             	mov    %rbx,%rsi
 10605e3:	e8 98 4f fc ff       	call   1025580 <myl_core_trap>
 10605e8:	48 8d 3d 11 15 02 00 	lea    0x21511(%rip),%rdi        # 1081b00 <core_durable_error.verbs+0xab0>
 10605ef:	ba 01 00 00 00       	mov    $0x1,%edx
 10605f4:	48 89 de             	mov    %rbx,%rsi
 10605f7:	e8 84 4f fc ff       	call   1025580 <myl_core_trap>
 10605fc:	48 8d 3d 0d 14 02 00 	lea    0x2140d(%rip),%rdi        # 1081a10 <core_durable_error.verbs+0x9c0>
 1060603:	48 8b 74 24 20       	mov    0x20(%rsp),%rsi
 1060608:	48 89 c2             	mov    %rax,%rdx
 106060b:	e8 70 4f fc ff       	call   1025580 <myl_core_trap>
 1060610:	48 8d 3d b9 17 02 00 	lea    0x217b9(%rip),%rdi        # 1081dd0 <core_durable_error.verbs+0xd80>
 1060617:	ba 01 00 00 00       	mov    $0x1,%edx
 106061c:	e8 5f 4f fc ff       	call   1025580 <myl_core_trap>
 1060621:	48 8d 3d f8 27 02 00 	lea    0x227f8(%rip),%rdi        # 1082e20 <core_durable_error.verbs+0x1dd0>
 1060628:	ba 01 00 00 00       	mov    $0x1,%edx
 106062d:	4c 89 fe             	mov    %r15,%rsi
 1060630:	e8 4b 4f fc ff       	call   1025580 <myl_core_trap>
 1060635:	48 8d 3d e4 27 02 00 	lea    0x227e4(%rip),%rdi        # 1082e20 <core_durable_error.verbs+0x1dd0>
 106063c:	ba 01 00 00 00       	mov    $0x1,%edx
 1060641:	4c 89 e6             	mov    %r12,%rsi
 1060644:	e8 37 4f fc ff       	call   1025580 <myl_core_trap>
 1060649:	48 8d 3d 90 2b 02 00 	lea    0x22b90(%rip),%rdi        # 10831e0 <core_durable_error.verbs+0x2190>
 1060650:	ba 01 00 00 00       	mov    $0x1,%edx
 1060655:	48 89 de             	mov    %rbx,%rsi
 1060658:	e8 23 4f fc ff       	call   1025580 <myl_core_trap>
 106065d:	48 8d 3d dc 13 02 00 	lea    0x213dc(%rip),%rdi        # 1081a40 <core_durable_error.verbs+0x9f0>
 1060664:	ba 01 00 00 00       	mov    $0x1,%edx
 1060669:	48 89 ee             	mov    %rbp,%rsi
 106066c:	e8 0f 4f fc ff       	call   1025580 <myl_core_trap>
 1060671:	48 8d 3d 58 32 02 00 	lea    0x23258(%rip),%rdi        # 10838d0 <core_durable_error.verbs+0x2880>
 1060678:	ba 01 00 00 00       	mov    $0x1,%edx
 106067d:	48 89 de             	mov    %rbx,%rsi
 1060680:	e8 fb 4e fc ff       	call   1025580 <myl_core_trap>
 1060685:	48 8d 3d 24 2b 02 00 	lea    0x22b24(%rip),%rdi        # 10831b0 <core_durable_error.verbs+0x2160>
 106068c:	ba 01 00 00 00       	mov    $0x1,%edx
 1060691:	e8 ea 4e fc ff       	call   1025580 <myl_core_trap>
 1060696:	48 8d 3d 93 35 02 00 	lea    0x23593(%rip),%rdi        # 1083c30 <core_durable_error.verbs+0x2be0>
 106069d:	ba 01 00 00 00       	mov    $0x1,%edx
 10606a2:	48 89 ce             	mov    %rcx,%rsi
 10606a5:	e8 d6 4e fc ff       	call   1025580 <myl_core_trap>
 10606aa:	48 8d 3d af 11 02 00 	lea    0x211af(%rip),%rdi        # 1081860 <core_durable_error.verbs+0x810>
 10606b1:	ba 01 00 00 00       	mov    $0x1,%edx
 10606b6:	48 89 de             	mov    %rbx,%rsi
 10606b9:	e8 c2 4e fc ff       	call   1025580 <myl_core_trap>
 10606be:	48 8d 3d 5b 18 02 00 	lea    0x2185b(%rip),%rdi        # 1081f20 <core_durable_error.verbs+0xed0>
 10606c5:	ba 01 00 00 00       	mov    $0x1,%edx
 10606ca:	4c 89 d6             	mov    %r10,%rsi
 10606cd:	e8 ae 4e fc ff       	call   1025580 <myl_core_trap>
 10606d2:	48 8d 3d d7 0f 02 00 	lea    0x20fd7(%rip),%rdi        # 10816b0 <core_durable_error.verbs+0x660>
 10606d9:	ba 01 00 00 00       	mov    $0x1,%edx
 10606de:	4c 89 d6             	mov    %r10,%rsi
 10606e1:	e8 9a 4e fc ff       	call   1025580 <myl_core_trap>
 10606e6:	48 8d 3d 03 0f 02 00 	lea    0x20f03(%rip),%rdi        # 10815f0 <core_durable_error.verbs+0x5a0>
 10606ed:	ba 01 00 00 00       	mov    $0x1,%edx
 10606f2:	4c 89 d6             	mov    %r10,%rsi
 10606f5:	e8 86 4e fc ff       	call   1025580 <myl_core_trap>
 10606fa:	48 8d 3d 4f 0f 02 00 	lea    0x20f4f(%rip),%rdi        # 1081650 <core_durable_error.verbs+0x600>
 1060701:	ba 01 00 00 00       	mov    $0x1,%edx
 1060706:	4c 89 d6             	mov    %r10,%rsi
 1060709:	e8 72 4e fc ff       	call   1025580 <myl_core_trap>
 106070e:	48 8d 3d eb 64 02 00 	lea    0x264eb(%rip),%rdi        # 1086c00 <core_durable_error.verbs+0x5bb0>
 1060715:	e8 e6 a1 fc ff       	call   102a900 <myl_core_assert_fail>
 106071a:	83 f9 01             	cmp    $0x1,%ecx
 106071d:	0f 84 0d 01 00 00    	je     1060830 <my.vm::run+0x3980>
 1060723:	85 c9                	test   %ecx,%ecx
 1060725:	0f 85 11 01 00 00    	jne    106083c <my.vm::run+0x398c>
 106072b:	48 8d 3d 3e 2b 02 00 	lea    0x22b3e(%rip),%rdi        # 1083270 <core_durable_error.verbs+0x2220>
 1060732:	e8 c9 a1 fc ff       	call   102a900 <myl_core_assert_fail>
 1060737:	83 f8 01             	cmp    $0x1,%eax
 106073a:	0f 84 08 01 00 00    	je     1060848 <my.vm::run+0x3998>
 1060740:	85 c0                	test   %eax,%eax
 1060742:	0f 85 0c 01 00 00    	jne    1060854 <my.vm::run+0x39a4>
 1060748:	48 8d 3d 21 2b 02 00 	lea    0x22b21(%rip),%rdi        # 1083270 <core_durable_error.verbs+0x2220>
 106074f:	e8 ac a1 fc ff       	call   102a900 <myl_core_assert_fail>
 1060754:	83 f8 01             	cmp    $0x1,%eax
 1060757:	0f 84 03 01 00 00    	je     1060860 <my.vm::run+0x39b0>
 106075d:	85 c0                	test   %eax,%eax
 106075f:	0f 85 07 01 00 00    	jne    106086c <my.vm::run+0x39bc>
 1060765:	48 8d 3d 04 2b 02 00 	lea    0x22b04(%rip),%rdi        # 1083270 <core_durable_error.verbs+0x2220>
 106076c:	e8 8f a1 fc ff       	call   102a900 <myl_core_assert_fail>
 1060771:	48 8d 3d e8 28 02 00 	lea    0x228e8(%rip),%rdi        # 1083060 <core_durable_error.verbs+0x2010>
 1060778:	ba 01 00 00 00       	mov    $0x1,%edx
 106077d:	48 89 ce             	mov    %rcx,%rsi
 1060780:	e8 fb 4d fc ff       	call   1025580 <myl_core_trap>
 1060785:	48 8d 3d 44 28 02 00 	lea    0x22844(%rip),%rdi        # 1082fd0 <core_durable_error.verbs+0x1f80>
 106078c:	ba 01 00 00 00       	mov    $0x1,%edx
 1060791:	e8 ea 4d fc ff       	call   1025580 <myl_core_trap>
 1060796:	48 8d 3d f3 0d 02 00 	lea    0x20df3(%rip),%rdi        # 1081590 <core_durable_error.verbs+0x540>
 106079d:	4c 89 fe             	mov    %r15,%rsi
 10607a0:	e8 db 4d fc ff       	call   1025580 <myl_core_trap>
 10607a5:	48 8d 3d d4 26 02 00 	lea    0x226d4(%rip),%rdi        # 1082e80 <core_durable_error.verbs+0x1e30>
 10607ac:	ba 01 00 00 00       	mov    $0x1,%edx
 10607b1:	e8 ca 4d fc ff       	call   1025580 <myl_core_trap>
 10607b6:	48 8d 3d e3 2a 02 00 	lea    0x22ae3(%rip),%rdi        # 10832a0 <core_durable_error.verbs+0x2250>
 10607bd:	e8 3e a1 fc ff       	call   102a900 <myl_core_assert_fail>
 10607c2:	48 8d 3d 07 2b 02 00 	lea    0x22b07(%rip),%rdi        # 10832d0 <core_durable_error.verbs+0x2280>
 10607c9:	e8 32 a1 fc ff       	call   102a900 <myl_core_assert_fail>
 10607ce:	48 8d 3d cb 2a 02 00 	lea    0x22acb(%rip),%rdi        # 10832a0 <core_durable_error.verbs+0x2250>
 10607d5:	e8 26 a1 fc ff       	call   102a900 <myl_core_assert_fail>
 10607da:	48 8d 3d ef 2a 02 00 	lea    0x22aef(%rip),%rdi        # 10832d0 <core_durable_error.verbs+0x2280>
 10607e1:	e8 1a a1 fc ff       	call   102a900 <myl_core_assert_fail>
 10607e6:	48 8d 3d 83 0c 02 00 	lea    0x20c83(%rip),%rdi        # 1081470 <core_durable_error.verbs+0x420>
 10607ed:	ba 01 00 00 00       	mov    $0x1,%edx
 10607f2:	4c 89 f6             	mov    %r14,%rsi
 10607f5:	e8 86 4d fc ff       	call   1025580 <myl_core_trap>
 10607fa:	48 8d 3d bf 28 02 00 	lea    0x228bf(%rip),%rdi        # 10830c0 <core_durable_error.verbs+0x2070>
 1060801:	ba 01 00 00 00       	mov    $0x1,%edx
 1060806:	48 89 ce             	mov    %rcx,%rsi
 1060809:	e8 72 4d fc ff       	call   1025580 <myl_core_trap>
 106080e:	48 8d 3d 5b 27 02 00 	lea    0x2275b(%rip),%rdi        # 1082f70 <core_durable_error.verbs+0x1f20>
 1060815:	ba 01 00 00 00       	mov    $0x1,%edx
 106081a:	e8 61 4d fc ff       	call   1025580 <myl_core_trap>
 106081f:	48 8d 3d 1a 2d 02 00 	lea    0x22d1a(%rip),%rdi        # 1083540 <core_durable_error.verbs+0x24f0>
 1060826:	ba 01 00 00 00       	mov    $0x1,%edx
 106082b:	e8 50 4d fc ff       	call   1025580 <myl_core_trap>
 1060830:	48 8d 3d 69 2a 02 00 	lea    0x22a69(%rip),%rdi        # 10832a0 <core_durable_error.verbs+0x2250>
 1060837:	e8 c4 a0 fc ff       	call   102a900 <myl_core_assert_fail>
 106083c:	48 8d 3d 8d 2a 02 00 	lea    0x22a8d(%rip),%rdi        # 10832d0 <core_durable_error.verbs+0x2280>
 1060843:	e8 b8 a0 fc ff       	call   102a900 <myl_core_assert_fail>
 1060848:	48 8d 3d 51 2a 02 00 	lea    0x22a51(%rip),%rdi        # 10832a0 <core_durable_error.verbs+0x2250>
 106084f:	e8 ac a0 fc ff       	call   102a900 <myl_core_assert_fail>
 1060854:	48 8d 3d 75 2a 02 00 	lea    0x22a75(%rip),%rdi        # 10832d0 <core_durable_error.verbs+0x2280>
 106085b:	e8 a0 a0 fc ff       	call   102a900 <myl_core_assert_fail>
 1060860:	48 8d 3d 39 2a 02 00 	lea    0x22a39(%rip),%rdi        # 10832a0 <core_durable_error.verbs+0x2250>
 1060867:	e8 94 a0 fc ff       	call   102a900 <myl_core_assert_fail>
 106086c:	48 8d 3d 5d 2a 02 00 	lea    0x22a5d(%rip),%rdi        # 10832d0 <core_durable_error.verbs+0x2280>
 1060873:	e8 88 a0 fc ff       	call   102a900 <myl_core_assert_fail>
 1060878:	48 8d 3d 61 2c 02 00 	lea    0x22c61(%rip),%rdi        # 10834e0 <core_durable_error.verbs+0x2490>
 106087f:	ba 01 00 00 00       	mov    $0x1,%edx
 1060884:	e8 f7 4c fc ff       	call   1025580 <myl_core_trap>
 1060889:	83 f8 01             	cmp    $0x1,%eax
 106088c:	74 70                	je     10608fe <my.vm::run+0x3a4e>
 106088e:	85 c0                	test   %eax,%eax
 1060890:	75 78                	jne    106090a <my.vm::run+0x3a5a>
 1060892:	48 8d 3d d7 29 02 00 	lea    0x229d7(%rip),%rdi        # 1083270 <core_durable_error.verbs+0x2220>
 1060899:	e8 62 a0 fc ff       	call   102a900 <myl_core_assert_fail>
 106089e:	48 8d 3d cb 2f 02 00 	lea    0x22fcb(%rip),%rdi        # 1083870 <core_durable_error.verbs+0x2820>
 10608a5:	ba 01 00 00 00       	mov    $0x1,%edx
 10608aa:	48 89 c6             	mov    %rax,%rsi
 10608ad:	e8 ce 4c fc ff       	call   1025580 <myl_core_trap>
 10608b2:	48 8d 3d 87 2f 02 00 	lea    0x22f87(%rip),%rdi        # 1083840 <core_durable_error.verbs+0x27f0>
 10608b9:	48 89 de             	mov    %rbx,%rsi
 10608bc:	4c 89 ca             	mov    %r9,%rdx
 10608bf:	e8 bc 4c fc ff       	call   1025580 <myl_core_trap>
 10608c4:	83 f9 01             	cmp    $0x1,%ecx
 10608c7:	74 4d                	je     1060916 <my.vm::run+0x3a66>
 10608c9:	85 c9                	test   %ecx,%ecx
 10608cb:	75 55                	jne    1060922 <my.vm::run+0x3a72>
 10608cd:	48 8d 3d 9c 29 02 00 	lea    0x2299c(%rip),%rdi        # 1083270 <core_durable_error.verbs+0x2220>
 10608d4:	e8 27 a0 fc ff       	call   102a900 <myl_core_assert_fail>
 10608d9:	48 8d 3d 50 5a 02 00 	lea    0x25a50(%rip),%rdi        # 1086330 <core_durable_error.verbs+0x52e0>
 10608e0:	ba 01 00 00 00       	mov    $0x1,%edx
 10608e5:	e8 96 4c fc ff       	call   1025580 <myl_core_trap>
 10608ea:	48 8d 3d df 59 02 00 	lea    0x259df(%rip),%rdi        # 10862d0 <core_durable_error.verbs+0x5280>
 10608f1:	ba 01 00 00 00       	mov    $0x1,%edx
 10608f6:	48 89 c6             	mov    %rax,%rsi
 10608f9:	e8 82 4c fc ff       	call   1025580 <myl_core_trap>
 10608fe:	48 8d 3d 9b 29 02 00 	lea    0x2299b(%rip),%rdi        # 10832a0 <core_durable_error.verbs+0x2250>
 1060905:	e8 f6 9f fc ff       	call   102a900 <myl_core_assert_fail>
 106090a:	48 8d 3d bf 29 02 00 	lea    0x229bf(%rip),%rdi        # 10832d0 <core_durable_error.verbs+0x2280>
 1060911:	e8 ea 9f fc ff       	call   102a900 <myl_core_assert_fail>
 1060916:	48 8d 3d 83 29 02 00 	lea    0x22983(%rip),%rdi        # 10832a0 <core_durable_error.verbs+0x2250>
 106091d:	e8 de 9f fc ff       	call   102a900 <myl_core_assert_fail>
 1060922:	48 8d 3d a7 29 02 00 	lea    0x229a7(%rip),%rdi        # 10832d0 <core_durable_error.verbs+0x2280>
 1060929:	e8 d2 9f fc ff       	call   102a900 <myl_core_assert_fail>
 106092e:	48 8d 3d 8b 15 02 00 	lea    0x2158b(%rip),%rdi        # 1081ec0 <core_durable_error.verbs+0xe70>
 1060935:	ba 01 00 00 00       	mov    $0x1,%edx
 106093a:	48 89 c6             	mov    %rax,%rsi
 106093d:	e8 3e 4c fc ff       	call   1025580 <myl_core_trap>
 1060942:	48 8d 3d 57 0e 02 00 	lea    0x20e57(%rip),%rdi        # 10817a0 <core_durable_error.verbs+0x750>
 1060949:	e8 32 4c fc ff       	call   1025580 <myl_core_trap>
 106094e:	48 8d 3d 9b 2a 02 00 	lea    0x22a9b(%rip),%rdi        # 10833f0 <core_durable_error.verbs+0x23a0>
 1060955:	e8 26 4c fc ff       	call   1025580 <myl_core_trap>
 106095a:	48 8d 3d cf 62 02 00 	lea    0x262cf(%rip),%rdi        # 1086c30 <core_durable_error.verbs+0x5be0>
 1060961:	48 89 ee             	mov    %rbp,%rsi
 1060964:	e8 17 4c fc ff       	call   1025580 <myl_core_trap>
 1060969:	48 8d 3d e0 2a 02 00 	lea    0x22ae0(%rip),%rdi        # 1083450 <core_durable_error.verbs+0x2400>
 1060970:	48 89 ee             	mov    %rbp,%rsi
 1060973:	e8 08 4c fc ff       	call   1025580 <myl_core_trap>
 1060978:	48 8d 3d b1 0e 02 00 	lea    0x20eb1(%rip),%rdi        # 1081830 <core_durable_error.verbs+0x7e0>
 106097f:	48 89 de             	mov    %rbx,%rsi
 1060982:	e8 f9 4b fc ff       	call   1025580 <myl_core_trap>
 1060987:	48 8d 3d 72 14 02 00 	lea    0x21472(%rip),%rdi        # 1081e00 <core_durable_error.verbs+0xdb0>
 106098e:	48 89 ee             	mov    %rbp,%rsi
 1060991:	e8 ea 4b fc ff       	call   1025580 <myl_core_trap>
 1060996:	48 8d 3d 13 2b 02 00 	lea    0x22b13(%rip),%rdi        # 10834b0 <core_durable_error.verbs+0x2460>
 106099d:	e8 de 4b fc ff       	call   1025580 <myl_core_trap>
 10609a2:	48 8d 3d 07 10 02 00 	lea    0x21007(%rip),%rdi        # 10819b0 <core_durable_error.verbs+0x960>
 10609a9:	48 89 de             	mov    %rbx,%rsi
 10609ac:	e8 cf 4b fc ff       	call   1025580 <myl_core_trap>
 10609b1:	48 8d 3d 68 0c 02 00 	lea    0x20c68(%rip),%rdi        # 1081620 <core_durable_error.verbs+0x5d0>
 10609b8:	e8 c3 4b fc ff       	call   1025580 <myl_core_trap>
 10609bd:	48 8d 3d cc 14 02 00 	lea    0x214cc(%rip),%rdi        # 1081e90 <core_durable_error.verbs+0xe40>
 10609c4:	e8 b7 4b fc ff       	call   1025580 <myl_core_trap>
 10609c9:	48 8d 3d 00 11 02 00 	lea    0x21100(%rip),%rdi        # 1081ad0 <core_durable_error.verbs+0xa80>
 10609d0:	e8 ab 4b fc ff       	call   1025580 <myl_core_trap>
 10609d5:	48 8d 3d b4 32 02 00 	lea    0x232b4(%rip),%rdi        # 1083c90 <core_durable_error.verbs+0x2c40>
 10609dc:	48 8b 74 24 38       	mov    0x38(%rsp),%rsi
 10609e1:	e8 9a 4b fc ff       	call   1025580 <myl_core_trap>
 10609e6:	48 8d 3d 63 12 02 00 	lea    0x21263(%rip),%rdi        # 1081c50 <core_durable_error.verbs+0xc00>
 10609ed:	48 89 ee             	mov    %rbp,%rsi
 10609f0:	e8 8b 4b fc ff       	call   1025580 <myl_core_trap>
 10609f5:	48 8d 3d d4 0d 02 00 	lea    0x20dd4(%rip),%rdi        # 10817d0 <core_durable_error.verbs+0x780>
 10609fc:	48 89 de             	mov    %rbx,%rsi
 10609ff:	e8 7c 4b fc ff       	call   1025580 <myl_core_trap>
 1060a04:	48 8d 3d 15 30 02 00 	lea    0x23015(%rip),%rdi        # 1083a20 <core_durable_error.verbs+0x29d0>
 1060a0b:	e8 70 4b fc ff       	call   1025580 <myl_core_trap>
 1060a10:	48 8d 3d 79 11 02 00 	lea    0x21179(%rip),%rdi        # 1081b90 <core_durable_error.verbs+0xb40>
 1060a17:	e8 64 4b fc ff       	call   1025580 <myl_core_trap>
 1060a1c:	48 8d 3d 0d 11 02 00 	lea    0x2110d(%rip),%rdi        # 1081b30 <core_durable_error.verbs+0xae0>
 1060a23:	e8 58 4b fc ff       	call   1025580 <myl_core_trap>
 1060a28:	48 8d 3d 21 15 02 00 	lea    0x21521(%rip),%rdi        # 1081f50 <core_durable_error.verbs+0xf00>
 1060a2f:	48 89 ee             	mov    %rbp,%rsi
 1060a32:	e8 49 4b fc ff       	call   1025580 <myl_core_trap>
 1060a37:	48 8d 3d 92 2b 02 00 	lea    0x22b92(%rip),%rdi        # 10835d0 <core_durable_error.verbs+0x2580>
 1060a3e:	48 89 ee             	mov    %rbp,%rsi
 1060a41:	e8 3a 4b fc ff       	call   1025580 <myl_core_trap>
 1060a46:	48 8d 3d 23 16 02 00 	lea    0x21623(%rip),%rdi        # 1082070 <core_durable_error.verbs+0x1020>
 1060a4d:	48 89 ee             	mov    %rbp,%rsi
 1060a50:	e8 2b 4b fc ff       	call   1025580 <myl_core_trap>
 1060a55:	48 8d 3d 24 0c 02 00 	lea    0x20c24(%rip),%rdi        # 1081680 <core_durable_error.verbs+0x630>
 1060a5c:	e8 1f 4b fc ff       	call   1025580 <myl_core_trap>
 1060a61:	48 8d 3d 08 10 02 00 	lea    0x21008(%rip),%rdi        # 1081a70 <core_durable_error.verbs+0xa20>
 1060a68:	e8 13 4b fc ff       	call   1025580 <myl_core_trap>
 1060a6d:	48 8d 3d 0c 0f 02 00 	lea    0x20f0c(%rip),%rdi        # 1081980 <core_durable_error.verbs+0x930>
 1060a74:	48 89 ee             	mov    %rbp,%rsi
 1060a77:	e8 04 4b fc ff       	call   1025580 <myl_core_trap>
 1060a7c:	48 8d 3d 4d 31 02 00 	lea    0x2314d(%rip),%rdi        # 1083bd0 <core_durable_error.verbs+0x2b80>
 1060a83:	48 89 ee             	mov    %rbp,%rsi
 1060a86:	e8 f5 4a fc ff       	call   1025580 <myl_core_trap>
 1060a8b:	48 8d 3d 8e 5f 02 00 	lea    0x25f8e(%rip),%rdi        # 1086a20 <core_durable_error.verbs+0x59d0>
 1060a92:	4c 89 c6             	mov    %r8,%rsi
 1060a95:	e8 e6 4a fc ff       	call   1025580 <myl_core_trap>
 1060a9a:	48 8d 3d 9f 0c 02 00 	lea    0x20c9f(%rip),%rdi        # 1081740 <core_durable_error.verbs+0x6f0>
 1060aa1:	e8 da 4a fc ff       	call   1025580 <myl_core_trap>
 1060aa6:	48 8d 3d 63 15 02 00 	lea    0x21563(%rip),%rdi        # 1082010 <core_durable_error.verbs+0xfc0>
 1060aad:	48 89 ee             	mov    %rbp,%rsi
 1060ab0:	e8 cb 4a fc ff       	call   1025580 <myl_core_trap>
 1060ab5:	48 8d 3d e4 12 02 00 	lea    0x212e4(%rip),%rdi        # 1081da0 <core_durable_error.verbs+0xd50>
 1060abc:	e8 bf 4a fc ff       	call   1025580 <myl_core_trap>
 1060ac1:	48 8d 3d 28 0e 02 00 	lea    0x20e28(%rip),%rdi        # 10818f0 <core_durable_error.verbs+0x8a0>
 1060ac8:	48 89 de             	mov    %rbx,%rsi
 1060acb:	e8 b0 4a fc ff       	call   1025580 <myl_core_trap>
 1060ad0:	48 8d 3d 19 2f 02 00 	lea    0x22f19(%rip),%rdi        # 10839f0 <core_durable_error.verbs+0x29a0>
 1060ad7:	e8 a4 4a fc ff       	call   1025580 <myl_core_trap>
 1060adc:	48 8d 3d fd 0b 02 00 	lea    0x20bfd(%rip),%rdi        # 10816e0 <core_durable_error.verbs+0x690>
 1060ae3:	e8 98 4a fc ff       	call   1025580 <myl_core_trap>
 1060ae8:	48 8d 3d 51 30 02 00 	lea    0x23051(%rip),%rdi        # 1083b40 <core_durable_error.verbs+0x2af0>
 1060aef:	e8 8c 4a fc ff       	call   1025580 <myl_core_trap>
 1060af4:	48 8d 3d 05 0a 02 00 	lea    0x20a05(%rip),%rdi        # 1081500 <core_durable_error.verbs+0x4b0>
 1060afb:	e8 80 4a fc ff       	call   1025580 <myl_core_trap>
 1060b00:	48 8d 3d a9 11 02 00 	lea    0x211a9(%rip),%rdi        # 1081cb0 <core_durable_error.verbs+0xc60>
 1060b07:	48 89 c2             	mov    %rax,%rdx
 1060b0a:	e8 71 4a fc ff       	call   1025580 <myl_core_trap>
 1060b0f:	48 8d 3d 1a 0a 02 00 	lea    0x20a1a(%rip),%rdi        # 1081530 <core_durable_error.verbs+0x4e0>
 1060b16:	e8 65 4a fc ff       	call   1025580 <myl_core_trap>
 1060b1b:	48 8d 3d 0e 2e 02 00 	lea    0x22e0e(%rip),%rdi        # 1083930 <core_durable_error.verbs+0x28e0>
 1060b22:	e8 59 4a fc ff       	call   1025580 <myl_core_trap>
 1060b27:	48 8d 3d c2 10 02 00 	lea    0x210c2(%rip),%rdi        # 1081bf0 <core_durable_error.verbs+0xba0>
 1060b2e:	48 89 ee             	mov    %rbp,%rsi
 1060b31:	e8 4a 4a fc ff       	call   1025580 <myl_core_trap>
 1060b36:	48 8d 3d a3 23 02 00 	lea    0x223a3(%rip),%rdi        # 1082ee0 <core_durable_error.verbs+0x1e90>
 1060b3d:	e8 3e 4a fc ff       	call   1025580 <myl_core_trap>
 1060b42:	48 8d 3d 17 31 02 00 	lea    0x23117(%rip),%rdi        # 1083c60 <core_durable_error.verbs+0x2c10>
 1060b49:	e8 32 4a fc ff       	call   1025580 <myl_core_trap>
 1060b4e:	48 8d 3d 3b 0d 02 00 	lea    0x20d3b(%rip),%rdi        # 1081890 <core_durable_error.verbs+0x840>
 1060b55:	48 89 de             	mov    %rbx,%rsi
 1060b58:	e8 23 4a fc ff       	call   1025580 <myl_core_trap>
 1060b5d:	48 8d 3d 1c 14 02 00 	lea    0x2141c(%rip),%rdi        # 1081f80 <core_durable_error.verbs+0xf30>
 1060b64:	e8 17 4a fc ff       	call   1025580 <myl_core_trap>
 1060b69:	48 8d 3d a0 26 02 00 	lea    0x226a0(%rip),%rdi        # 1083210 <core_durable_error.verbs+0x21c0>
 1060b70:	48 89 c6             	mov    %rax,%rsi
 1060b73:	e8 08 4a fc ff       	call   1025580 <myl_core_trap>
 1060b78:	48 8d 3d d1 25 02 00 	lea    0x225d1(%rip),%rdi        # 1083150 <core_durable_error.verbs+0x2100>
 1060b7f:	48 8b 74 24 38       	mov    0x38(%rsp),%rsi
 1060b84:	e8 f7 49 fc ff       	call   1025580 <myl_core_trap>
 1060b89:	48 8d 3d b0 11 02 00 	lea    0x211b0(%rip),%rdi        # 1081d40 <core_durable_error.verbs+0xcf0>
 1060b90:	e8 eb 49 fc ff       	call   1025580 <myl_core_trap>
 1060b95:	48 8d 3d a4 56 02 00 	lea    0x256a4(%rip),%rdi        # 1086240 <core_durable_error.verbs+0x51f0>
 1060b9c:	4c 89 c6             	mov    %r8,%rsi
 1060b9f:	48 89 ca             	mov    %rcx,%rdx
 1060ba2:	e8 d9 49 fc ff       	call   1025580 <myl_core_trap>
 1060ba7:	48 8d 3d 02 50 02 00 	lea    0x25002(%rip),%rdi        # 1085bb0 <core_durable_error.verbs+0x4b60>
 1060bae:	4c 89 ee             	mov    %r13,%rsi
 1060bb1:	e8 ca 49 fc ff       	call   1025580 <myl_core_trap>
 1060bb6:	48 8d 3d b3 56 02 00 	lea    0x256b3(%rip),%rdi        # 1086270 <core_durable_error.verbs+0x5220>
 1060bbd:	e8 be 49 fc ff       	call   1025580 <myl_core_trap>
 1060bc2:	48 8d 3d c7 24 02 00 	lea    0x224c7(%rip),%rdi        # 1083090 <core_durable_error.verbs+0x2040>
 1060bc9:	e8 b2 49 fc ff       	call   1025580 <myl_core_trap>
 1060bce:	48 8d 3d 3b 23 02 00 	lea    0x2233b(%rip),%rdi        # 1082f10 <core_durable_error.verbs+0x1ec0>
 1060bd5:	e8 a6 49 fc ff       	call   1025580 <myl_core_trap>
 1060bda:	48 8d 3d 1f 24 02 00 	lea    0x2241f(%rip),%rdi        # 1083000 <core_durable_error.verbs+0x1fb0>
 1060be1:	48 89 c6             	mov    %rax,%rsi
 1060be4:	e8 97 49 fc ff       	call   1025580 <myl_core_trap>
 1060be9:	48 8d 3d 80 29 02 00 	lea    0x22980(%rip),%rdi        # 1083570 <core_durable_error.verbs+0x2520>
 1060bf0:	48 89 ee             	mov    %rbp,%rsi
 1060bf3:	e8 88 49 fc ff       	call   1025580 <myl_core_trap>
 1060bf8:	48 8d 3d 41 26 02 00 	lea    0x22641(%rip),%rdi        # 1083240 <core_durable_error.verbs+0x21f0>
 1060bff:	48 89 de             	mov    %rbx,%rsi
 1060c02:	e8 79 49 fc ff       	call   1025580 <myl_core_trap>
 1060c07:	48 8d 3d 92 23 02 00 	lea    0x22392(%rip),%rdi        # 1082fa0 <core_durable_error.verbs+0x1f50>
 1060c0e:	e8 6d 49 fc ff       	call   1025580 <myl_core_trap>
 1060c13:	48 8d 3d 96 4f 02 00 	lea    0x24f96(%rip),%rdi        # 1085bb0 <core_durable_error.verbs+0x4b60>
 1060c1a:	e8 61 49 fc ff       	call   1025580 <myl_core_trap>
 1060c1f:	48 8d 3d da 53 02 00 	lea    0x253da(%rip),%rdi        # 1086000 <core_durable_error.verbs+0x4fb0>
 1060c26:	e8 55 49 fc ff       	call   1025580 <myl_core_trap>
 1060c2b:	48 8d 3d 6e 2f 02 00 	lea    0x22f6e(%rip),%rdi        # 1083ba0 <core_durable_error.verbs+0x2b50>
 1060c32:	48 89 ee             	mov    %rbp,%rsi
 1060c35:	e8 46 49 fc ff       	call   1025580 <myl_core_trap>
 1060c3a:	48 8d 3d 5f 2c 02 00 	lea    0x22c5f(%rip),%rdi        # 10838a0 <core_durable_error.verbs+0x2850>
 1060c41:	48 89 c2             	mov    %rax,%rdx
 1060c44:	e8 37 49 fc ff       	call   1025580 <myl_core_trap>
 1060c49:	48 8d 3d 10 60 02 00 	lea    0x26010(%rip),%rdi        # 1086c60 <core_durable_error.verbs+0x5c10>
 1060c50:	48 89 de             	mov    %rbx,%rsi
 1060c53:	48 89 c2             	mov    %rax,%rdx
 1060c56:	e8 25 49 fc ff       	call   1025580 <myl_core_trap>
 1060c5b:	48 8d 3d ee 21 02 00 	lea    0x221ee(%rip),%rdi        # 1082e50 <core_durable_error.verbs+0x1e00>
 1060c62:	48 89 c2             	mov    %rax,%rdx
 1060c65:	e8 16 49 fc ff       	call   1025580 <myl_core_trap>
 1060c6a:	48 8d 3d 2f 56 02 00 	lea    0x2562f(%rip),%rdi        # 10862a0 <core_durable_error.verbs+0x5250>
 1060c71:	48 89 c6             	mov    %rax,%rsi
 1060c74:	e8 07 49 fc ff       	call   1025580 <myl_core_trap>
 1060c79:	48 8d 3d c0 22 02 00 	lea    0x222c0(%rip),%rdi        # 1082f40 <core_durable_error.verbs+0x1ef0>
 1060c80:	e8 fb 48 fc ff       	call   1025580 <myl_core_trap>
 1060c85:	48 8d 3d 64 24 02 00 	lea    0x22464(%rip),%rdi        # 10830f0 <core_durable_error.verbs+0x20a0>
 1060c8c:	e8 ef 48 fc ff       	call   1025580 <myl_core_trap>
 1060c91:	48 8d 3d a8 55 02 00 	lea    0x255a8(%rip),%rdi        # 1086240 <core_durable_error.verbs+0x51f0>
 1060c98:	48 89 c6             	mov    %rax,%rsi
 1060c9b:	48 89 ca             	mov    %rcx,%rdx
 1060c9e:	e8 dd 48 fc ff       	call   1025580 <myl_core_trap>
 1060ca3:	48 8d 3d d6 24 02 00 	lea    0x224d6(%rip),%rdi        # 1083180 <core_durable_error.verbs+0x2130>
 1060caa:	48 89 c2             	mov    %rax,%rdx
 1060cad:	e8 ce 48 fc ff       	call   1025580 <myl_core_trap>
 1060cb2:	48 8d 3d 77 23 02 00 	lea    0x22377(%rip),%rdi        # 1083030 <core_durable_error.verbs+0x1fe0>
 1060cb9:	48 89 de             	mov    %rbx,%rsi
 1060cbc:	e8 bf 48 fc ff       	call   1025580 <myl_core_trap>
 1060cc1:	48 8d 3d a8 2e 02 00 	lea    0x22ea8(%rip),%rdi        # 1083b70 <core_durable_error.verbs+0x2b20>
 1060cc8:	48 8b 74 24 38       	mov    0x38(%rsp),%rsi
 1060ccd:	e8 ae 48 fc ff       	call   1025580 <myl_core_trap>
 1060cd2:	48 8d 3d 37 28 02 00 	lea    0x22837(%rip),%rdi        # 1083510 <core_durable_error.verbs+0x24c0>
 1060cd9:	48 89 c6             	mov    %rax,%rsi
 1060cdc:	e8 9f 48 fc ff       	call   1025580 <myl_core_trap>
 1060ce1:	48 8d 3d 18 56 02 00 	lea    0x25618(%rip),%rdi        # 1086300 <core_durable_error.verbs+0x52b0>
 1060ce8:	e8 93 48 fc ff       	call   1025580 <myl_core_trap>

Disassembly of section .plt:
