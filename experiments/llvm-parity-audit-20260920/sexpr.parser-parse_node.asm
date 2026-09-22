
.tmp/bench/armsset/maxperf/whole-o3.bin:     file format elf64-x86-64


Disassembly of section .init:

Disassembly of section .plt:

Disassembly of section .text:

000000000040fde0 <sexpr.parser::parse_node>:
  40fde0:	55                   	push   %rbp
  40fde1:	41 57                	push   %r15
  40fde3:	41 56                	push   %r14
  40fde5:	41 55                	push   %r13
  40fde7:	41 54                	push   %r12
  40fde9:	53                   	push   %rbx
  40fdea:	48 81 ec f8 06 00 00 	sub    $0x6f8,%rsp
  40fdf1:	49 89 cd             	mov    %rcx,%r13
  40fdf4:	49 89 d6             	mov    %rdx,%r14
  40fdf7:	49 89 f7             	mov    %rsi,%r15
  40fdfa:	48 89 fb             	mov    %rdi,%rbx
  40fdfd:	c5 f8 57 c0          	vxorps %xmm0,%xmm0,%xmm0
  40fe01:	c5 fc 11 84 24 80 00 	vmovups %ymm0,0x80(%rsp)
  40fe08:	00 00 
  40fe0a:	c5 fc 11 44 24 60    	vmovups %ymm0,0x60(%rsp)
  40fe10:	48 89 f7             	mov    %rsi,%rdi
  40fe13:	c5 f8 77             	vzeroupper
  40fe16:	e8 55 b7 00 00       	call   41b570 <myl_qbe_heap>
  40fe1b:	49 89 c4             	mov    %rax,%r12
  40fe1e:	c4 c1 78 10 46 30    	vmovups 0x30(%r14),%xmm0
  40fe24:	49 8b 46 40          	mov    0x40(%r14),%rax
  40fe28:	c4 c1 7c 10 4e 10    	vmovups 0x10(%r14),%ymm1
  40fe2e:	c5 fc 11 8c 24 a0 00 	vmovups %ymm1,0xa0(%rsp)
  40fe35:	00 00 
  40fe37:	48 89 84 24 d0 00 00 	mov    %rax,0xd0(%rsp)
  40fe3e:	00 
  40fe3f:	c5 f8 29 84 24 c0 00 	vmovaps %xmm0,0xc0(%rsp)
  40fe46:	00 00 
  40fe48:	8b 84 24 a0 00 00 00 	mov    0xa0(%rsp),%eax
  40fe4f:	48 83 f8 08          	cmp    $0x8,%rax
  40fe53:	0f 87 fc 05 00 00    	ja     410455 <sexpr.parser::parse_node+0x675>
  40fe59:	48 8d 0d 44 54 01 00 	lea    0x15444(%rip),%rcx        # 4252a4 <_fini+0x960>
  40fe60:	48 63 04 81          	movslq (%rcx,%rax,4),%rax
  40fe64:	48 01 c8             	add    %rcx,%rax
  40fe67:	ff e0                	jmp    *%rax
  40fe69:	49 8b 44 24 10       	mov    0x10(%r12),%rax
  40fe6e:	48 89 04 24          	mov    %rax,(%rsp)
  40fe72:	48 8d 44 24 18       	lea    0x18(%rsp),%rax
  40fe77:	4c 89 74 24 18       	mov    %r14,0x18(%rsp)
  40fe7c:	48 89 44 24 08       	mov    %rax,0x8(%rsp)
  40fe81:	48 c7 c5 a0 83 42 00 	mov    $0x4283a0,%rbp
  40fe88:	48 89 6c 24 10       	mov    %rbp,0x10(%rsp)
  40fe8d:	48 89 e0             	mov    %rsp,%rax
  40fe90:	48 89 44 24 40       	mov    %rax,0x40(%rsp)
  40fe95:	48 8d 44 24 60       	lea    0x60(%rsp),%rax
  40fe9a:	48 89 44 24 48       	mov    %rax,0x48(%rsp)
  40fe9f:	48 c7 c0 50 20 43 00 	mov    $0x432050,%rax
  40fea6:	48 89 44 24 50       	mov    %rax,0x50(%rsp)
  40feab:	48 8d 44 24 40       	lea    0x40(%rsp),%rax
  40feb0:	48 89 44 24 20       	mov    %rax,0x20(%rsp)
  40feb5:	48 8d 44 24 38       	lea    0x38(%rsp),%rax
  40feba:	4c 89 74 24 38       	mov    %r14,0x38(%rsp)
  40febf:	48 89 44 24 28       	mov    %rax,0x28(%rsp)
  40fec4:	48 89 6c 24 30       	mov    %rbp,0x30(%rsp)
  40fec9:	48 8d bc 24 88 03 00 	lea    0x388(%rsp),%rdi
  40fed0:	00 
  40fed1:	4c 89 fe             	mov    %r15,%rsi
  40fed4:	4c 89 f2             	mov    %r14,%rdx
  40fed7:	c5 f8 77             	vzeroupper
  40feda:	e8 a1 72 ff ff       	call   407180 <sexpr.parser::advance>
  40fedf:	83 bc 24 88 03 00 00 	cmpl   $0x0,0x388(%rsp)
  40fee6:	00 
  40fee7:	0f 84 3e 08 00 00    	je     41072b <sexpr.parser::parse_node+0x94b>
  40feed:	c5 fc 10 84 24 90 03 	vmovups 0x390(%rsp),%ymm0
  40fef4:	00 00 
  40fef6:	c5 fc 11 84 24 78 02 	vmovups %ymm0,0x278(%rsp)
  40fefd:	00 00 
  40feff:	c7 03 01 00 00 00    	movl   $0x1,(%rbx)
  40ff05:	c5 fc 10 84 24 74 02 	vmovups 0x274(%rsp),%ymm0
  40ff0c:	00 00 
  40ff0e:	c5 fc 11 43 04       	vmovups %ymm0,0x4(%rbx)
  40ff13:	8b 84 24 94 02 00 00 	mov    0x294(%rsp),%eax
  40ff1a:	89 43 24             	mov    %eax,0x24(%rbx)
  40ff1d:	e9 d0 0b 00 00       	jmp    410af2 <sexpr.parser::parse_node+0xd12>
  40ff22:	49 8b 16             	mov    (%r14),%rdx
  40ff25:	49 8b 44 24 10       	mov    0x10(%r12),%rax
  40ff2a:	48 89 04 24          	mov    %rax,(%rsp)
  40ff2e:	48 8d 44 24 18       	lea    0x18(%rsp),%rax
  40ff33:	4c 89 74 24 18       	mov    %r14,0x18(%rsp)
  40ff38:	48 89 44 24 08       	mov    %rax,0x8(%rsp)
  40ff3d:	48 c7 c0 a0 83 42 00 	mov    $0x4283a0,%rax
  40ff44:	48 89 44 24 10       	mov    %rax,0x10(%rsp)
  40ff49:	48 89 e0             	mov    %rsp,%rax
  40ff4c:	48 89 44 24 40       	mov    %rax,0x40(%rsp)
  40ff51:	48 8d 44 24 60       	lea    0x60(%rsp),%rax
  40ff56:	48 89 44 24 48       	mov    %rax,0x48(%rsp)
  40ff5b:	48 c7 c0 50 20 43 00 	mov    $0x432050,%rax
  40ff62:	48 89 44 24 50       	mov    %rax,0x50(%rsp)
  40ff67:	48 8d 44 24 40       	lea    0x40(%rsp),%rax
  40ff6c:	48 89 44 24 20       	mov    %rax,0x20(%rsp)
  40ff71:	48 89 54 24 38       	mov    %rdx,0x38(%rsp)
  40ff76:	48 8d 6c 24 38       	lea    0x38(%rsp),%rbp
  40ff7b:	48 89 6c 24 28       	mov    %rbp,0x28(%rsp)
  40ff80:	48 c7 c0 d0 1e 43 00 	mov    $0x431ed0,%rax
  40ff87:	48 89 44 24 30       	mov    %rax,0x30(%rsp)
  40ff8c:	4c 8d ac 24 68 06 00 	lea    0x668(%rsp),%r13
  40ff93:	00 
  40ff94:	48 8d 8c 24 a0 00 00 	lea    0xa0(%rsp),%rcx
  40ff9b:	00 
  40ff9c:	4c 89 ef             	mov    %r13,%rdi
  40ff9f:	4c 89 fe             	mov    %r15,%rsi
  40ffa2:	c5 f8 77             	vzeroupper
  40ffa5:	e8 76 0f 00 00       	call   410f20 <sexpr.parser::parse_leaf>
  40ffaa:	83 bc 24 68 06 00 00 	cmpl   $0x0,0x668(%rsp)
  40ffb1:	00 
  40ffb2:	0f 84 b7 04 00 00    	je     41046f <sexpr.parser::parse_node+0x68f>
  40ffb8:	c4 c1 7c 10 45 08    	vmovups 0x8(%r13),%ymm0
  40ffbe:	c5 fc 11 84 24 e8 01 	vmovups %ymm0,0x1e8(%rsp)
  40ffc5:	00 00 
  40ffc7:	c7 03 01 00 00 00    	movl   $0x1,(%rbx)
  40ffcd:	c5 fc 10 84 24 e4 01 	vmovups 0x1e4(%rsp),%ymm0
  40ffd4:	00 00 
  40ffd6:	c5 fc 11 43 04       	vmovups %ymm0,0x4(%rbx)
  40ffdb:	8b 84 24 04 02 00 00 	mov    0x204(%rsp),%eax
  40ffe2:	89 43 24             	mov    %eax,0x24(%rbx)
  40ffe5:	e9 08 0b 00 00       	jmp    410af2 <sexpr.parser::parse_node+0xd12>
  40ffea:	49 8b 16             	mov    (%r14),%rdx
  40ffed:	49 8b 44 24 10       	mov    0x10(%r12),%rax
  40fff2:	48 89 04 24          	mov    %rax,(%rsp)
  40fff6:	48 8d 44 24 18       	lea    0x18(%rsp),%rax
  40fffb:	4c 89 74 24 18       	mov    %r14,0x18(%rsp)
  410000:	48 89 44 24 08       	mov    %rax,0x8(%rsp)
  410005:	48 c7 c0 a0 83 42 00 	mov    $0x4283a0,%rax
  41000c:	48 89 44 24 10       	mov    %rax,0x10(%rsp)
  410011:	48 89 e0             	mov    %rsp,%rax
  410014:	48 89 44 24 40       	mov    %rax,0x40(%rsp)
  410019:	48 8d 44 24 60       	lea    0x60(%rsp),%rax
  41001e:	48 89 44 24 48       	mov    %rax,0x48(%rsp)
  410023:	48 c7 c0 50 20 43 00 	mov    $0x432050,%rax
  41002a:	48 89 44 24 50       	mov    %rax,0x50(%rsp)
  41002f:	48 8d 44 24 40       	lea    0x40(%rsp),%rax
  410034:	48 89 44 24 20       	mov    %rax,0x20(%rsp)
  410039:	48 89 54 24 38       	mov    %rdx,0x38(%rsp)
  41003e:	48 8d 6c 24 38       	lea    0x38(%rsp),%rbp
  410043:	48 89 6c 24 28       	mov    %rbp,0x28(%rsp)
  410048:	48 c7 c0 d0 1e 43 00 	mov    $0x431ed0,%rax
  41004f:	48 89 44 24 30       	mov    %rax,0x30(%rsp)
  410054:	4c 8d ac 24 b0 06 00 	lea    0x6b0(%rsp),%r13
  41005b:	00 
  41005c:	48 8d 8c 24 a0 00 00 	lea    0xa0(%rsp),%rcx
  410063:	00 
  410064:	4c 89 ef             	mov    %r13,%rdi
  410067:	4c 89 fe             	mov    %r15,%rsi
  41006a:	c5 f8 77             	vzeroupper
  41006d:	e8 ae 0e 00 00       	call   410f20 <sexpr.parser::parse_leaf>
  410072:	83 bc 24 b0 06 00 00 	cmpl   $0x0,0x6b0(%rsp)
  410079:	00 
  41007a:	0f 84 be 04 00 00    	je     41053e <sexpr.parser::parse_node+0x75e>
  410080:	c4 c1 7c 10 45 08    	vmovups 0x8(%r13),%ymm0
  410086:	c5 fc 11 84 24 30 02 	vmovups %ymm0,0x230(%rsp)
  41008d:	00 00 
  41008f:	c7 03 01 00 00 00    	movl   $0x1,(%rbx)
  410095:	c5 fc 10 84 24 2c 02 	vmovups 0x22c(%rsp),%ymm0
  41009c:	00 00 
  41009e:	c5 fc 11 43 04       	vmovups %ymm0,0x4(%rbx)
  4100a3:	8b 84 24 4c 02 00 00 	mov    0x24c(%rsp),%eax
  4100aa:	89 43 24             	mov    %eax,0x24(%rbx)
  4100ad:	e9 40 0a 00 00       	jmp    410af2 <sexpr.parser::parse_node+0xd12>
  4100b2:	49 8b 06             	mov    (%r14),%rax
  4100b5:	c5 f8 10 84 24 c8 00 	vmovups 0xc8(%rsp),%xmm0
  4100bc:	00 00 
  4100be:	48 8b 8c 24 b8 00 00 	mov    0xb8(%rsp),%rcx
  4100c5:	00 
  4100c6:	48 89 8c 24 d8 00 00 	mov    %rcx,0xd8(%rsp)
  4100cd:	00 
  4100ce:	8b 94 24 c0 00 00 00 	mov    0xc0(%rsp),%edx
  4100d5:	89 94 24 e0 00 00 00 	mov    %edx,0xe0(%rsp)
  4100dc:	c7 44 24 60 02 00 00 	movl   $0x2,0x60(%rsp)
  4100e3:	00 
  4100e4:	48 89 44 24 68       	mov    %rax,0x68(%rsp)
  4100e9:	c5 f8 29 44 24 70    	vmovaps %xmm0,0x70(%rsp)
  4100ef:	48 89 8c 24 80 00 00 	mov    %rcx,0x80(%rsp)
  4100f6:	00 
  4100f7:	89 94 24 88 00 00 00 	mov    %edx,0x88(%rsp)
  4100fe:	49 8b 44 24 10       	mov    0x10(%r12),%rax
  410103:	48 89 04 24          	mov    %rax,(%rsp)
  410107:	48 8d 44 24 18       	lea    0x18(%rsp),%rax
  41010c:	4c 89 74 24 18       	mov    %r14,0x18(%rsp)
  410111:	48 89 44 24 08       	mov    %rax,0x8(%rsp)
  410116:	48 c7 c0 a0 83 42 00 	mov    $0x4283a0,%rax
  41011d:	48 89 44 24 10       	mov    %rax,0x10(%rsp)
  410122:	48 89 e1             	mov    %rsp,%rcx
  410125:	48 89 4c 24 40       	mov    %rcx,0x40(%rsp)
  41012a:	48 8d 4c 24 60       	lea    0x60(%rsp),%rcx
  41012f:	48 89 4c 24 48       	mov    %rcx,0x48(%rsp)
  410134:	48 c7 c1 50 20 43 00 	mov    $0x432050,%rcx
  41013b:	48 89 4c 24 50       	mov    %rcx,0x50(%rsp)
  410140:	48 8d 4c 24 40       	lea    0x40(%rsp),%rcx
  410145:	48 89 4c 24 20       	mov    %rcx,0x20(%rsp)
  41014a:	48 8d 4c 24 38       	lea    0x38(%rsp),%rcx
  41014f:	4c 89 74 24 38       	mov    %r14,0x38(%rsp)
  410154:	48 89 4c 24 28       	mov    %rcx,0x28(%rsp)
  410159:	48 89 44 24 30       	mov    %rax,0x30(%rsp)
  41015e:	48 8d bc 24 60 03 00 	lea    0x360(%rsp),%rdi
  410165:	00 
  410166:	4c 89 fe             	mov    %r15,%rsi
  410169:	4c 89 f2             	mov    %r14,%rdx
  41016c:	c5 f8 77             	vzeroupper
  41016f:	e8 0c 70 ff ff       	call   407180 <sexpr.parser::advance>
  410174:	83 bc 24 60 03 00 00 	cmpl   $0x0,0x360(%rsp)
  41017b:	00 
  41017c:	0f 84 8b 04 00 00    	je     41060d <sexpr.parser::parse_node+0x82d>
  410182:	c5 fc 10 84 24 68 03 	vmovups 0x368(%rsp),%ymm0
  410189:	00 00 
  41018b:	c5 fc 11 84 24 54 02 	vmovups %ymm0,0x254(%rsp)
  410192:	00 00 
  410194:	c7 03 01 00 00 00    	movl   $0x1,(%rbx)
  41019a:	c5 fc 10 84 24 50 02 	vmovups 0x250(%rsp),%ymm0
  4101a1:	00 00 
  4101a3:	c5 fc 11 43 04       	vmovups %ymm0,0x4(%rbx)
  4101a8:	8b 84 24 70 02 00 00 	mov    0x270(%rsp),%eax
  4101af:	89 43 24             	mov    %eax,0x24(%rbx)
  4101b2:	e9 3b 09 00 00       	jmp    410af2 <sexpr.parser::parse_node+0xd12>
  4101b7:	49 8b 16             	mov    (%r14),%rdx
  4101ba:	49 8b 44 24 10       	mov    0x10(%r12),%rax
  4101bf:	48 89 04 24          	mov    %rax,(%rsp)
  4101c3:	48 8d 44 24 18       	lea    0x18(%rsp),%rax
  4101c8:	4c 89 74 24 18       	mov    %r14,0x18(%rsp)
  4101cd:	48 89 44 24 08       	mov    %rax,0x8(%rsp)
  4101d2:	48 c7 c0 a0 83 42 00 	mov    $0x4283a0,%rax
  4101d9:	48 89 44 24 10       	mov    %rax,0x10(%rsp)
  4101de:	48 89 e0             	mov    %rsp,%rax
  4101e1:	48 89 44 24 40       	mov    %rax,0x40(%rsp)
  4101e6:	48 8d 44 24 60       	lea    0x60(%rsp),%rax
  4101eb:	48 89 44 24 48       	mov    %rax,0x48(%rsp)
  4101f0:	48 c7 c0 50 20 43 00 	mov    $0x432050,%rax
  4101f7:	48 89 44 24 50       	mov    %rax,0x50(%rsp)
  4101fc:	48 8d 44 24 40       	lea    0x40(%rsp),%rax
  410201:	48 89 44 24 20       	mov    %rax,0x20(%rsp)
  410206:	48 89 54 24 38       	mov    %rdx,0x38(%rsp)
  41020b:	48 8d 6c 24 38       	lea    0x38(%rsp),%rbp
  410210:	48 89 6c 24 28       	mov    %rbp,0x28(%rsp)
  410215:	48 c7 c0 d0 1e 43 00 	mov    $0x431ed0,%rax
  41021c:	48 89 44 24 30       	mov    %rax,0x30(%rsp)
  410221:	4c 8d ac 24 90 05 00 	lea    0x590(%rsp),%r13
  410228:	00 
  410229:	48 8d 8c 24 a0 00 00 	lea    0xa0(%rsp),%rcx
  410230:	00 
  410231:	4c 89 ef             	mov    %r13,%rdi
  410234:	4c 89 fe             	mov    %r15,%rsi
  410237:	c5 f8 77             	vzeroupper
  41023a:	e8 e1 0c 00 00       	call   410f20 <sexpr.parser::parse_leaf>
  41023f:	83 bc 24 90 05 00 00 	cmpl   $0x0,0x590(%rsp)
  410246:	00 
  410247:	0f 84 0f 04 00 00    	je     41065c <sexpr.parser::parse_node+0x87c>
  41024d:	c4 c1 7c 10 45 08    	vmovups 0x8(%r13),%ymm0
  410253:	c5 fc 11 84 24 10 01 	vmovups %ymm0,0x110(%rsp)
  41025a:	00 00 
  41025c:	c7 03 01 00 00 00    	movl   $0x1,(%rbx)
  410262:	c5 fc 10 84 24 0c 01 	vmovups 0x10c(%rsp),%ymm0
  410269:	00 00 
  41026b:	c5 fc 11 43 04       	vmovups %ymm0,0x4(%rbx)
  410270:	8b 84 24 2c 01 00 00 	mov    0x12c(%rsp),%eax
  410277:	89 43 24             	mov    %eax,0x24(%rbx)
  41027a:	e9 73 08 00 00       	jmp    410af2 <sexpr.parser::parse_node+0xd12>
  41027f:	48 c7 c0 50 27 43 00 	mov    $0x432750,%rax
  410286:	e9 97 01 00 00       	jmp    410422 <sexpr.parser::parse_node+0x642>
  41028b:	49 8b 16             	mov    (%r14),%rdx
  41028e:	49 8b 44 24 10       	mov    0x10(%r12),%rax
  410293:	48 89 04 24          	mov    %rax,(%rsp)
  410297:	48 8d 44 24 18       	lea    0x18(%rsp),%rax
  41029c:	4c 89 74 24 18       	mov    %r14,0x18(%rsp)
  4102a1:	48 89 44 24 08       	mov    %rax,0x8(%rsp)
  4102a6:	48 c7 c0 a0 83 42 00 	mov    $0x4283a0,%rax
  4102ad:	48 89 44 24 10       	mov    %rax,0x10(%rsp)
  4102b2:	48 89 e0             	mov    %rsp,%rax
  4102b5:	48 89 44 24 40       	mov    %rax,0x40(%rsp)
  4102ba:	48 8d 44 24 60       	lea    0x60(%rsp),%rax
  4102bf:	48 89 44 24 48       	mov    %rax,0x48(%rsp)
  4102c4:	48 c7 c0 50 20 43 00 	mov    $0x432050,%rax
  4102cb:	48 89 44 24 50       	mov    %rax,0x50(%rsp)
  4102d0:	48 8d 44 24 40       	lea    0x40(%rsp),%rax
  4102d5:	48 89 44 24 20       	mov    %rax,0x20(%rsp)
  4102da:	48 89 54 24 38       	mov    %rdx,0x38(%rsp)
  4102df:	48 8d 6c 24 38       	lea    0x38(%rsp),%rbp
  4102e4:	48 89 6c 24 28       	mov    %rbp,0x28(%rsp)
  4102e9:	48 c7 c0 d0 1e 43 00 	mov    $0x431ed0,%rax
  4102f0:	48 89 44 24 30       	mov    %rax,0x30(%rsp)
  4102f5:	4c 8d ac 24 20 06 00 	lea    0x620(%rsp),%r13
  4102fc:	00 
  4102fd:	48 8d 8c 24 a0 00 00 	lea    0xa0(%rsp),%rcx
  410304:	00 
  410305:	4c 89 ef             	mov    %r13,%rdi
  410308:	4c 89 fe             	mov    %r15,%rsi
  41030b:	c5 f8 77             	vzeroupper
  41030e:	e8 0d 0c 00 00       	call   410f20 <sexpr.parser::parse_leaf>
  410313:	83 bc 24 20 06 00 00 	cmpl   $0x0,0x620(%rsp)
  41031a:	00 
  41031b:	0f 84 ad 04 00 00    	je     4107ce <sexpr.parser::parse_node+0x9ee>
  410321:	c4 c1 7c 10 45 08    	vmovups 0x8(%r13),%ymm0
  410327:	c5 fc 11 84 24 a0 01 	vmovups %ymm0,0x1a0(%rsp)
  41032e:	00 00 
  410330:	c7 03 01 00 00 00    	movl   $0x1,(%rbx)
  410336:	c5 fc 10 84 24 9c 01 	vmovups 0x19c(%rsp),%ymm0
  41033d:	00 00 
  41033f:	c5 fc 11 43 04       	vmovups %ymm0,0x4(%rbx)
  410344:	8b 84 24 bc 01 00 00 	mov    0x1bc(%rsp),%eax
  41034b:	89 43 24             	mov    %eax,0x24(%rbx)
  41034e:	e9 9f 07 00 00       	jmp    410af2 <sexpr.parser::parse_node+0xd12>
  410353:	49 8b 16             	mov    (%r14),%rdx
  410356:	49 8b 44 24 10       	mov    0x10(%r12),%rax
  41035b:	48 89 04 24          	mov    %rax,(%rsp)
  41035f:	48 8d 44 24 18       	lea    0x18(%rsp),%rax
  410364:	4c 89 74 24 18       	mov    %r14,0x18(%rsp)
  410369:	48 89 44 24 08       	mov    %rax,0x8(%rsp)
  41036e:	48 c7 c0 a0 83 42 00 	mov    $0x4283a0,%rax
  410375:	48 89 44 24 10       	mov    %rax,0x10(%rsp)
  41037a:	48 89 e0             	mov    %rsp,%rax
  41037d:	48 89 44 24 40       	mov    %rax,0x40(%rsp)
  410382:	48 8d 44 24 60       	lea    0x60(%rsp),%rax
  410387:	48 89 44 24 48       	mov    %rax,0x48(%rsp)
  41038c:	48 c7 c0 50 20 43 00 	mov    $0x432050,%rax
  410393:	48 89 44 24 50       	mov    %rax,0x50(%rsp)
  410398:	48 8d 44 24 40       	lea    0x40(%rsp),%rax
  41039d:	48 89 44 24 20       	mov    %rax,0x20(%rsp)
  4103a2:	48 89 54 24 38       	mov    %rdx,0x38(%rsp)
  4103a7:	48 8d 6c 24 38       	lea    0x38(%rsp),%rbp
  4103ac:	48 89 6c 24 28       	mov    %rbp,0x28(%rsp)
  4103b1:	48 c7 c0 d0 1e 43 00 	mov    $0x431ed0,%rax
  4103b8:	48 89 44 24 30       	mov    %rax,0x30(%rsp)
  4103bd:	4c 8d ac 24 d8 05 00 	lea    0x5d8(%rsp),%r13
  4103c4:	00 
  4103c5:	48 8d 8c 24 a0 00 00 	lea    0xa0(%rsp),%rcx
  4103cc:	00 
  4103cd:	4c 89 ef             	mov    %r13,%rdi
  4103d0:	4c 89 fe             	mov    %r15,%rsi
  4103d3:	c5 f8 77             	vzeroupper
  4103d6:	e8 45 0b 00 00       	call   410f20 <sexpr.parser::parse_leaf>
  4103db:	83 bc 24 d8 05 00 00 	cmpl   $0x0,0x5d8(%rsp)
  4103e2:	00 
  4103e3:	0f 84 b4 04 00 00    	je     41089d <sexpr.parser::parse_node+0xabd>
  4103e9:	c4 c1 7c 10 45 08    	vmovups 0x8(%r13),%ymm0
  4103ef:	c5 fc 11 84 24 58 01 	vmovups %ymm0,0x158(%rsp)
  4103f6:	00 00 
  4103f8:	c7 03 01 00 00 00    	movl   $0x1,(%rbx)
  4103fe:	c5 fc 10 84 24 54 01 	vmovups 0x154(%rsp),%ymm0
  410405:	00 00 
  410407:	c5 fc 11 43 04       	vmovups %ymm0,0x4(%rbx)
  41040c:	8b 84 24 74 01 00 00 	mov    0x174(%rsp),%eax
  410413:	89 43 24             	mov    %eax,0x24(%rbx)
  410416:	e9 d7 06 00 00       	jmp    410af2 <sexpr.parser::parse_node+0xd12>
  41041b:	48 c7 c0 58 27 43 00 	mov    $0x432758,%rax
  410422:	48 8b 00             	mov    (%rax),%rax
  410425:	8b 8c 24 b8 00 00 00 	mov    0xb8(%rsp),%ecx
  41042c:	8b 94 24 bc 00 00 00 	mov    0xbc(%rsp),%edx
  410433:	8b b4 24 c0 00 00 00 	mov    0xc0(%rsp),%esi
  41043a:	c7 03 01 00 00 00    	movl   $0x1,(%rbx)
  410440:	48 89 43 08          	mov    %rax,0x8(%rbx)
  410444:	48 89 4b 10          	mov    %rcx,0x10(%rbx)
  410448:	48 89 53 18          	mov    %rdx,0x18(%rbx)
  41044c:	48 89 73 20          	mov    %rsi,0x20(%rbx)
  410450:	e9 9d 06 00 00       	jmp    410af2 <sexpr.parser::parse_node+0xd12>
  410455:	c5 f8 57 c0          	vxorps %xmm0,%xmm0,%xmm0
  410459:	c5 fc 11 43 20       	vmovups %ymm0,0x20(%rbx)
  41045e:	c5 fc 11 03          	vmovups %ymm0,(%rbx)
  410462:	48 c7 43 40 00 00 00 	movq   $0x0,0x40(%rbx)
  410469:	00 
  41046a:	e9 83 06 00 00       	jmp    410af2 <sexpr.parser::parse_node+0xd12>
  41046f:	c4 c1 7c 10 45 08    	vmovups 0x8(%r13),%ymm0
  410475:	c4 c1 7c 10 4d 28    	vmovups 0x28(%r13),%ymm1
  41047b:	c5 fc 11 8c 24 80 00 	vmovups %ymm1,0x80(%rsp)
  410482:	00 00 
  410484:	c5 fc 11 44 24 60    	vmovups %ymm0,0x60(%rsp)
  41048a:	49 8b 44 24 10       	mov    0x10(%r12),%rax
  41048f:	48 89 04 24          	mov    %rax,(%rsp)
  410493:	4c 89 74 24 18       	mov    %r14,0x18(%rsp)
  410498:	48 8d 44 24 18       	lea    0x18(%rsp),%rax
  41049d:	48 89 44 24 08       	mov    %rax,0x8(%rsp)
  4104a2:	48 c7 c0 a0 83 42 00 	mov    $0x4283a0,%rax
  4104a9:	48 89 44 24 10       	mov    %rax,0x10(%rsp)
  4104ae:	48 89 e1             	mov    %rsp,%rcx
  4104b1:	48 89 4c 24 40       	mov    %rcx,0x40(%rsp)
  4104b6:	48 8d 4c 24 60       	lea    0x60(%rsp),%rcx
  4104bb:	48 89 4c 24 48       	mov    %rcx,0x48(%rsp)
  4104c0:	48 c7 c1 50 20 43 00 	mov    $0x432050,%rcx
  4104c7:	48 89 4c 24 50       	mov    %rcx,0x50(%rsp)
  4104cc:	48 8d 4c 24 40       	lea    0x40(%rsp),%rcx
  4104d1:	48 89 4c 24 20       	mov    %rcx,0x20(%rsp)
  4104d6:	4c 89 74 24 38       	mov    %r14,0x38(%rsp)
  4104db:	48 89 6c 24 28       	mov    %rbp,0x28(%rsp)
  4104e0:	48 89 44 24 30       	mov    %rax,0x30(%rsp)
  4104e5:	48 8d bc 24 10 03 00 	lea    0x310(%rsp),%rdi
  4104ec:	00 
  4104ed:	4c 89 fe             	mov    %r15,%rsi
  4104f0:	4c 89 f2             	mov    %r14,%rdx
  4104f3:	c5 f8 77             	vzeroupper
  4104f6:	e8 85 6c ff ff       	call   407180 <sexpr.parser::advance>
  4104fb:	83 bc 24 10 03 00 00 	cmpl   $0x0,0x310(%rsp)
  410502:	00 
  410503:	0f 84 63 04 00 00    	je     41096c <sexpr.parser::parse_node+0xb8c>
  410509:	c5 fc 10 84 24 18 03 	vmovups 0x318(%rsp),%ymm0
  410510:	00 00 
  410512:	c5 fc 11 84 24 c4 01 	vmovups %ymm0,0x1c4(%rsp)
  410519:	00 00 
  41051b:	c7 03 01 00 00 00    	movl   $0x1,(%rbx)
  410521:	c5 fc 10 84 24 c0 01 	vmovups 0x1c0(%rsp),%ymm0
  410528:	00 00 
  41052a:	c5 fc 11 43 04       	vmovups %ymm0,0x4(%rbx)
  41052f:	8b 84 24 e0 01 00 00 	mov    0x1e0(%rsp),%eax
  410536:	89 43 24             	mov    %eax,0x24(%rbx)
  410539:	e9 b4 05 00 00       	jmp    410af2 <sexpr.parser::parse_node+0xd12>
  41053e:	c4 c1 7c 10 45 08    	vmovups 0x8(%r13),%ymm0
  410544:	c4 c1 7c 10 4d 28    	vmovups 0x28(%r13),%ymm1
  41054a:	c5 fc 11 8c 24 80 00 	vmovups %ymm1,0x80(%rsp)
  410551:	00 00 
  410553:	c5 fc 11 44 24 60    	vmovups %ymm0,0x60(%rsp)
  410559:	49 8b 44 24 10       	mov    0x10(%r12),%rax
  41055e:	48 89 04 24          	mov    %rax,(%rsp)
  410562:	4c 89 74 24 18       	mov    %r14,0x18(%rsp)
  410567:	48 8d 44 24 18       	lea    0x18(%rsp),%rax
  41056c:	48 89 44 24 08       	mov    %rax,0x8(%rsp)
  410571:	48 c7 c0 a0 83 42 00 	mov    $0x4283a0,%rax
  410578:	48 89 44 24 10       	mov    %rax,0x10(%rsp)
  41057d:	48 89 e1             	mov    %rsp,%rcx
  410580:	48 89 4c 24 40       	mov    %rcx,0x40(%rsp)
  410585:	48 8d 4c 24 60       	lea    0x60(%rsp),%rcx
  41058a:	48 89 4c 24 48       	mov    %rcx,0x48(%rsp)
  41058f:	48 c7 c1 50 20 43 00 	mov    $0x432050,%rcx
  410596:	48 89 4c 24 50       	mov    %rcx,0x50(%rsp)
  41059b:	48 8d 4c 24 40       	lea    0x40(%rsp),%rcx
  4105a0:	48 89 4c 24 20       	mov    %rcx,0x20(%rsp)
  4105a5:	4c 89 74 24 38       	mov    %r14,0x38(%rsp)
  4105aa:	48 89 6c 24 28       	mov    %rbp,0x28(%rsp)
  4105af:	48 89 44 24 30       	mov    %rax,0x30(%rsp)
  4105b4:	48 8d bc 24 38 03 00 	lea    0x338(%rsp),%rdi
  4105bb:	00 
  4105bc:	4c 89 fe             	mov    %r15,%rsi
  4105bf:	4c 89 f2             	mov    %r14,%rdx
  4105c2:	c5 f8 77             	vzeroupper
  4105c5:	e8 b6 6b ff ff       	call   407180 <sexpr.parser::advance>
  4105ca:	83 bc 24 38 03 00 00 	cmpl   $0x0,0x338(%rsp)
  4105d1:	00 
  4105d2:	0f 84 e3 03 00 00    	je     4109bb <sexpr.parser::parse_node+0xbdb>
  4105d8:	c5 fc 10 84 24 40 03 	vmovups 0x340(%rsp),%ymm0
  4105df:	00 00 
  4105e1:	c5 fc 11 84 24 0c 02 	vmovups %ymm0,0x20c(%rsp)
  4105e8:	00 00 
  4105ea:	c7 03 01 00 00 00    	movl   $0x1,(%rbx)
  4105f0:	c5 fc 10 84 24 08 02 	vmovups 0x208(%rsp),%ymm0
  4105f7:	00 00 
  4105f9:	c5 fc 11 43 04       	vmovups %ymm0,0x4(%rbx)
  4105fe:	8b 84 24 28 02 00 00 	mov    0x228(%rsp),%eax
  410605:	89 43 24             	mov    %eax,0x24(%rbx)
  410608:	e9 e5 04 00 00       	jmp    410af2 <sexpr.parser::parse_node+0xd12>
  41060d:	c5 fc 10 44 24 60    	vmovups 0x60(%rsp),%ymm0
  410613:	c5 fc 10 8c 24 80 00 	vmovups 0x80(%rsp),%ymm1
  41061a:	00 00 
  41061c:	c5 fc 11 8c 24 28 05 	vmovups %ymm1,0x528(%rsp)
  410623:	00 00 
  410625:	c5 fc 11 84 24 08 05 	vmovups %ymm0,0x508(%rsp)
  41062c:	00 00 
  41062e:	c7 03 00 00 00 00    	movl   $0x0,(%rbx)
  410634:	c5 fc 10 84 24 04 05 	vmovups 0x504(%rsp),%ymm0
  41063b:	00 00 
  41063d:	c5 fc 10 8c 24 24 05 	vmovups 0x524(%rsp),%ymm1
  410644:	00 00 
  410646:	c5 fc 11 43 04       	vmovups %ymm0,0x4(%rbx)
  41064b:	c5 fc 11 4b 24       	vmovups %ymm1,0x24(%rbx)
  410650:	8b 84 24 44 05 00 00 	mov    0x544(%rsp),%eax
  410657:	e9 93 04 00 00       	jmp    410aef <sexpr.parser::parse_node+0xd0f>
  41065c:	c4 c1 7c 10 45 08    	vmovups 0x8(%r13),%ymm0
  410662:	c4 c1 7c 10 4d 28    	vmovups 0x28(%r13),%ymm1
  410668:	c5 fc 11 8c 24 80 00 	vmovups %ymm1,0x80(%rsp)
  41066f:	00 00 
  410671:	c5 fc 11 44 24 60    	vmovups %ymm0,0x60(%rsp)
  410677:	49 8b 44 24 10       	mov    0x10(%r12),%rax
  41067c:	48 89 04 24          	mov    %rax,(%rsp)
  410680:	4c 89 74 24 18       	mov    %r14,0x18(%rsp)
  410685:	48 8d 44 24 18       	lea    0x18(%rsp),%rax
  41068a:	48 89 44 24 08       	mov    %rax,0x8(%rsp)
  41068f:	48 c7 c0 a0 83 42 00 	mov    $0x4283a0,%rax
  410696:	48 89 44 24 10       	mov    %rax,0x10(%rsp)
  41069b:	48 89 e1             	mov    %rsp,%rcx
  41069e:	48 89 4c 24 40       	mov    %rcx,0x40(%rsp)
  4106a3:	48 8d 4c 24 60       	lea    0x60(%rsp),%rcx
  4106a8:	48 89 4c 24 48       	mov    %rcx,0x48(%rsp)
  4106ad:	48 c7 c1 50 20 43 00 	mov    $0x432050,%rcx
  4106b4:	48 89 4c 24 50       	mov    %rcx,0x50(%rsp)
  4106b9:	48 8d 4c 24 40       	lea    0x40(%rsp),%rcx
  4106be:	48 89 4c 24 20       	mov    %rcx,0x20(%rsp)
  4106c3:	4c 89 74 24 38       	mov    %r14,0x38(%rsp)
  4106c8:	48 89 6c 24 28       	mov    %rbp,0x28(%rsp)
  4106cd:	48 89 44 24 30       	mov    %rax,0x30(%rsp)
  4106d2:	48 8d bc 24 98 02 00 	lea    0x298(%rsp),%rdi
  4106d9:	00 
  4106da:	4c 89 fe             	mov    %r15,%rsi
  4106dd:	4c 89 f2             	mov    %r14,%rdx
  4106e0:	c5 f8 77             	vzeroupper
  4106e3:	e8 98 6a ff ff       	call   407180 <sexpr.parser::advance>
  4106e8:	83 bc 24 98 02 00 00 	cmpl   $0x0,0x298(%rsp)
  4106ef:	00 
  4106f0:	0f 84 14 03 00 00    	je     410a0a <sexpr.parser::parse_node+0xc2a>
  4106f6:	c5 fc 10 84 24 a0 02 	vmovups 0x2a0(%rsp),%ymm0
  4106fd:	00 00 
  4106ff:	c5 fc 11 84 24 ec 00 	vmovups %ymm0,0xec(%rsp)
  410706:	00 00 
  410708:	c7 03 01 00 00 00    	movl   $0x1,(%rbx)
  41070e:	c5 fc 10 84 24 e8 00 	vmovups 0xe8(%rsp),%ymm0
  410715:	00 00 
  410717:	c5 fc 11 43 04       	vmovups %ymm0,0x4(%rbx)
  41071c:	8b 84 24 08 01 00 00 	mov    0x108(%rsp),%eax
  410723:	89 43 24             	mov    %eax,0x24(%rbx)
  410726:	e9 c7 03 00 00       	jmp    410af2 <sexpr.parser::parse_node+0xd12>
  41072b:	4c 8d 84 24 b8 00 00 	lea    0xb8(%rsp),%r8
  410732:	00 
  410733:	49 8b 44 24 10       	mov    0x10(%r12),%rax
  410738:	48 89 04 24          	mov    %rax,(%rsp)
  41073c:	4c 89 74 24 18       	mov    %r14,0x18(%rsp)
  410741:	48 8d 44 24 18       	lea    0x18(%rsp),%rax
  410746:	48 89 44 24 08       	mov    %rax,0x8(%rsp)
  41074b:	48 89 6c 24 10       	mov    %rbp,0x10(%rsp)
  410750:	48 89 e0             	mov    %rsp,%rax
  410753:	48 89 44 24 40       	mov    %rax,0x40(%rsp)
  410758:	48 8d 44 24 60       	lea    0x60(%rsp),%rax
  41075d:	48 89 44 24 48       	mov    %rax,0x48(%rsp)
  410762:	48 c7 c0 50 20 43 00 	mov    $0x432050,%rax
  410769:	48 89 44 24 50       	mov    %rax,0x50(%rsp)
  41076e:	48 8d 44 24 40       	lea    0x40(%rsp),%rax
  410773:	48 89 44 24 20       	mov    %rax,0x20(%rsp)
  410778:	4c 89 74 24 38       	mov    %r14,0x38(%rsp)
  41077d:	48 8d 44 24 38       	lea    0x38(%rsp),%rax
  410782:	48 89 44 24 28       	mov    %rax,0x28(%rsp)
  410787:	48 89 6c 24 30       	mov    %rbp,0x30(%rsp)
  41078c:	48 8d bc 24 48 05 00 	lea    0x548(%rsp),%rdi
  410793:	00 
  410794:	4c 89 fe             	mov    %r15,%rsi
  410797:	4c 89 f2             	mov    %r14,%rdx
  41079a:	4c 89 e9             	mov    %r13,%rcx
  41079d:	e8 6e 45 ff ff       	call   404d10 <sexpr.parser::parse_list>
  4107a2:	48 8b 84 24 88 05 00 	mov    0x588(%rsp),%rax
  4107a9:	00 
  4107aa:	48 89 43 40          	mov    %rax,0x40(%rbx)
  4107ae:	c5 fc 10 84 24 48 05 	vmovups 0x548(%rsp),%ymm0
  4107b5:	00 00 
  4107b7:	c5 fc 10 8c 24 68 05 	vmovups 0x568(%rsp),%ymm1
  4107be:	00 00 
  4107c0:	c5 fc 11 4b 20       	vmovups %ymm1,0x20(%rbx)
  4107c5:	c5 fc 11 03          	vmovups %ymm0,(%rbx)
  4107c9:	e9 24 03 00 00       	jmp    410af2 <sexpr.parser::parse_node+0xd12>
  4107ce:	c4 c1 7c 10 45 08    	vmovups 0x8(%r13),%ymm0
  4107d4:	c4 c1 7c 10 4d 28    	vmovups 0x28(%r13),%ymm1
  4107da:	c5 fc 11 8c 24 80 00 	vmovups %ymm1,0x80(%rsp)
  4107e1:	00 00 
  4107e3:	c5 fc 11 44 24 60    	vmovups %ymm0,0x60(%rsp)
  4107e9:	49 8b 44 24 10       	mov    0x10(%r12),%rax
  4107ee:	48 89 04 24          	mov    %rax,(%rsp)
  4107f2:	4c 89 74 24 18       	mov    %r14,0x18(%rsp)
  4107f7:	48 8d 44 24 18       	lea    0x18(%rsp),%rax
  4107fc:	48 89 44 24 08       	mov    %rax,0x8(%rsp)
  410801:	48 c7 c0 a0 83 42 00 	mov    $0x4283a0,%rax
  410808:	48 89 44 24 10       	mov    %rax,0x10(%rsp)
  41080d:	48 89 e1             	mov    %rsp,%rcx
  410810:	48 89 4c 24 40       	mov    %rcx,0x40(%rsp)
  410815:	48 8d 4c 24 60       	lea    0x60(%rsp),%rcx
  41081a:	48 89 4c 24 48       	mov    %rcx,0x48(%rsp)
  41081f:	48 c7 c1 50 20 43 00 	mov    $0x432050,%rcx
  410826:	48 89 4c 24 50       	mov    %rcx,0x50(%rsp)
  41082b:	48 8d 4c 24 40       	lea    0x40(%rsp),%rcx
  410830:	48 89 4c 24 20       	mov    %rcx,0x20(%rsp)
  410835:	4c 89 74 24 38       	mov    %r14,0x38(%rsp)
  41083a:	48 89 6c 24 28       	mov    %rbp,0x28(%rsp)
  41083f:	48 89 44 24 30       	mov    %rax,0x30(%rsp)
  410844:	48 8d bc 24 e8 02 00 	lea    0x2e8(%rsp),%rdi
  41084b:	00 
  41084c:	4c 89 fe             	mov    %r15,%rsi
  41084f:	4c 89 f2             	mov    %r14,%rdx
  410852:	c5 f8 77             	vzeroupper
  410855:	e8 26 69 ff ff       	call   407180 <sexpr.parser::advance>
  41085a:	83 bc 24 e8 02 00 00 	cmpl   $0x0,0x2e8(%rsp)
  410861:	00 
  410862:	0f 84 f1 01 00 00    	je     410a59 <sexpr.parser::parse_node+0xc79>
  410868:	c5 fc 10 84 24 f0 02 	vmovups 0x2f0(%rsp),%ymm0
  41086f:	00 00 
  410871:	c5 fc 11 84 24 7c 01 	vmovups %ymm0,0x17c(%rsp)
  410878:	00 00 
  41087a:	c7 03 01 00 00 00    	movl   $0x1,(%rbx)
  410880:	c5 fc 10 84 24 78 01 	vmovups 0x178(%rsp),%ymm0
  410887:	00 00 
  410889:	c5 fc 11 43 04       	vmovups %ymm0,0x4(%rbx)
  41088e:	8b 84 24 98 01 00 00 	mov    0x198(%rsp),%eax
  410895:	89 43 24             	mov    %eax,0x24(%rbx)
  410898:	e9 55 02 00 00       	jmp    410af2 <sexpr.parser::parse_node+0xd12>
  41089d:	c4 c1 7c 10 45 08    	vmovups 0x8(%r13),%ymm0
  4108a3:	c4 c1 7c 10 4d 28    	vmovups 0x28(%r13),%ymm1
  4108a9:	c5 fc 11 8c 24 80 00 	vmovups %ymm1,0x80(%rsp)
  4108b0:	00 00 
  4108b2:	c5 fc 11 44 24 60    	vmovups %ymm0,0x60(%rsp)
  4108b8:	49 8b 44 24 10       	mov    0x10(%r12),%rax
  4108bd:	48 89 04 24          	mov    %rax,(%rsp)
  4108c1:	4c 89 74 24 18       	mov    %r14,0x18(%rsp)
  4108c6:	48 8d 44 24 18       	lea    0x18(%rsp),%rax
  4108cb:	48 89 44 24 08       	mov    %rax,0x8(%rsp)
  4108d0:	48 c7 c0 a0 83 42 00 	mov    $0x4283a0,%rax
  4108d7:	48 89 44 24 10       	mov    %rax,0x10(%rsp)
  4108dc:	48 89 e1             	mov    %rsp,%rcx
  4108df:	48 89 4c 24 40       	mov    %rcx,0x40(%rsp)
  4108e4:	48 8d 4c 24 60       	lea    0x60(%rsp),%rcx
  4108e9:	48 89 4c 24 48       	mov    %rcx,0x48(%rsp)
  4108ee:	48 c7 c1 50 20 43 00 	mov    $0x432050,%rcx
  4108f5:	48 89 4c 24 50       	mov    %rcx,0x50(%rsp)
  4108fa:	48 8d 4c 24 40       	lea    0x40(%rsp),%rcx
  4108ff:	48 89 4c 24 20       	mov    %rcx,0x20(%rsp)
  410904:	4c 89 74 24 38       	mov    %r14,0x38(%rsp)
  410909:	48 89 6c 24 28       	mov    %rbp,0x28(%rsp)
  41090e:	48 89 44 24 30       	mov    %rax,0x30(%rsp)
  410913:	48 8d bc 24 c0 02 00 	lea    0x2c0(%rsp),%rdi
  41091a:	00 
  41091b:	4c 89 fe             	mov    %r15,%rsi
  41091e:	4c 89 f2             	mov    %r14,%rdx
  410921:	c5 f8 77             	vzeroupper
  410924:	e8 57 68 ff ff       	call   407180 <sexpr.parser::advance>
  410929:	83 bc 24 c0 02 00 00 	cmpl   $0x0,0x2c0(%rsp)
  410930:	00 
  410931:	0f 84 6e 01 00 00    	je     410aa5 <sexpr.parser::parse_node+0xcc5>
  410937:	c5 fc 10 84 24 c8 02 	vmovups 0x2c8(%rsp),%ymm0
  41093e:	00 00 
  410940:	c5 fc 11 84 24 34 01 	vmovups %ymm0,0x134(%rsp)
  410947:	00 00 
  410949:	c7 03 01 00 00 00    	movl   $0x1,(%rbx)
  41094f:	c5 fc 10 84 24 30 01 	vmovups 0x130(%rsp),%ymm0
  410956:	00 00 
  410958:	c5 fc 11 43 04       	vmovups %ymm0,0x4(%rbx)
  41095d:	8b 84 24 50 01 00 00 	mov    0x150(%rsp),%eax
  410964:	89 43 24             	mov    %eax,0x24(%rbx)
  410967:	e9 86 01 00 00       	jmp    410af2 <sexpr.parser::parse_node+0xd12>
  41096c:	c5 fc 10 44 24 60    	vmovups 0x60(%rsp),%ymm0
  410972:	c5 fc 10 8c 24 80 00 	vmovups 0x80(%rsp),%ymm1
  410979:	00 00 
  41097b:	c5 fc 11 8c 24 a0 04 	vmovups %ymm1,0x4a0(%rsp)
  410982:	00 00 
  410984:	c5 fc 11 84 24 80 04 	vmovups %ymm0,0x480(%rsp)
  41098b:	00 00 
  41098d:	c7 03 00 00 00 00    	movl   $0x0,(%rbx)
  410993:	c5 fc 10 84 24 7c 04 	vmovups 0x47c(%rsp),%ymm0
  41099a:	00 00 
  41099c:	c5 fc 10 8c 24 9c 04 	vmovups 0x49c(%rsp),%ymm1
  4109a3:	00 00 
  4109a5:	c5 fc 11 43 04       	vmovups %ymm0,0x4(%rbx)
  4109aa:	c5 fc 11 4b 24       	vmovups %ymm1,0x24(%rbx)
  4109af:	8b 84 24 bc 04 00 00 	mov    0x4bc(%rsp),%eax
  4109b6:	e9 34 01 00 00       	jmp    410aef <sexpr.parser::parse_node+0xd0f>
  4109bb:	c5 fc 10 44 24 60    	vmovups 0x60(%rsp),%ymm0
  4109c1:	c5 fc 10 8c 24 80 00 	vmovups 0x80(%rsp),%ymm1
  4109c8:	00 00 
  4109ca:	c5 fc 11 8c 24 e4 04 	vmovups %ymm1,0x4e4(%rsp)
  4109d1:	00 00 
  4109d3:	c5 fc 11 84 24 c4 04 	vmovups %ymm0,0x4c4(%rsp)
  4109da:	00 00 
  4109dc:	c7 03 00 00 00 00    	movl   $0x0,(%rbx)
  4109e2:	c5 fc 10 84 24 c0 04 	vmovups 0x4c0(%rsp),%ymm0
  4109e9:	00 00 
  4109eb:	c5 fc 10 8c 24 e0 04 	vmovups 0x4e0(%rsp),%ymm1
  4109f2:	00 00 
  4109f4:	c5 fc 11 43 04       	vmovups %ymm0,0x4(%rbx)
  4109f9:	c5 fc 11 4b 24       	vmovups %ymm1,0x24(%rbx)
  4109fe:	8b 84 24 00 05 00 00 	mov    0x500(%rsp),%eax
  410a05:	e9 e5 00 00 00       	jmp    410aef <sexpr.parser::parse_node+0xd0f>
  410a0a:	c5 fc 10 44 24 60    	vmovups 0x60(%rsp),%ymm0
  410a10:	c5 fc 10 8c 24 80 00 	vmovups 0x80(%rsp),%ymm1
  410a17:	00 00 
  410a19:	c5 fc 11 8c 24 d4 03 	vmovups %ymm1,0x3d4(%rsp)
  410a20:	00 00 
  410a22:	c5 fc 11 84 24 b4 03 	vmovups %ymm0,0x3b4(%rsp)
  410a29:	00 00 
  410a2b:	c7 03 00 00 00 00    	movl   $0x0,(%rbx)
  410a31:	c5 fc 10 84 24 b0 03 	vmovups 0x3b0(%rsp),%ymm0
  410a38:	00 00 
  410a3a:	c5 fc 10 8c 24 d0 03 	vmovups 0x3d0(%rsp),%ymm1
  410a41:	00 00 
  410a43:	c5 fc 11 43 04       	vmovups %ymm0,0x4(%rbx)
  410a48:	c5 fc 11 4b 24       	vmovups %ymm1,0x24(%rbx)
  410a4d:	8b 84 24 f0 03 00 00 	mov    0x3f0(%rsp),%eax
  410a54:	e9 96 00 00 00       	jmp    410aef <sexpr.parser::parse_node+0xd0f>
  410a59:	c5 fc 10 44 24 60    	vmovups 0x60(%rsp),%ymm0
  410a5f:	c5 fc 10 8c 24 80 00 	vmovups 0x80(%rsp),%ymm1
  410a66:	00 00 
  410a68:	c5 fc 11 8c 24 5c 04 	vmovups %ymm1,0x45c(%rsp)
  410a6f:	00 00 
  410a71:	c5 fc 11 84 24 3c 04 	vmovups %ymm0,0x43c(%rsp)
  410a78:	00 00 
  410a7a:	c7 03 00 00 00 00    	movl   $0x0,(%rbx)
  410a80:	c5 fc 10 84 24 38 04 	vmovups 0x438(%rsp),%ymm0
  410a87:	00 00 
  410a89:	c5 fc 10 8c 24 58 04 	vmovups 0x458(%rsp),%ymm1
  410a90:	00 00 
  410a92:	c5 fc 11 43 04       	vmovups %ymm0,0x4(%rbx)
  410a97:	c5 fc 11 4b 24       	vmovups %ymm1,0x24(%rbx)
  410a9c:	8b 84 24 78 04 00 00 	mov    0x478(%rsp),%eax
  410aa3:	eb 4a                	jmp    410aef <sexpr.parser::parse_node+0xd0f>
  410aa5:	c5 fc 10 44 24 60    	vmovups 0x60(%rsp),%ymm0
  410aab:	c5 fc 10 8c 24 80 00 	vmovups 0x80(%rsp),%ymm1
  410ab2:	00 00 
  410ab4:	c5 fc 11 8c 24 18 04 	vmovups %ymm1,0x418(%rsp)
  410abb:	00 00 
  410abd:	c5 fc 11 84 24 f8 03 	vmovups %ymm0,0x3f8(%rsp)
  410ac4:	00 00 
  410ac6:	c7 03 00 00 00 00    	movl   $0x0,(%rbx)
  410acc:	c5 fc 10 84 24 f4 03 	vmovups 0x3f4(%rsp),%ymm0
  410ad3:	00 00 
  410ad5:	c5 fc 10 8c 24 14 04 	vmovups 0x414(%rsp),%ymm1
  410adc:	00 00 
  410ade:	c5 fc 11 43 04       	vmovups %ymm0,0x4(%rbx)
  410ae3:	c5 fc 11 4b 24       	vmovups %ymm1,0x24(%rbx)
  410ae8:	8b 84 24 34 04 00 00 	mov    0x434(%rsp),%eax
  410aef:	89 43 44             	mov    %eax,0x44(%rbx)
  410af2:	48 89 d8             	mov    %rbx,%rax
  410af5:	48 81 c4 f8 06 00 00 	add    $0x6f8,%rsp
  410afc:	5b                   	pop    %rbx
  410afd:	41 5c                	pop    %r12
  410aff:	41 5d                	pop    %r13
  410b01:	41 5e                	pop    %r14
  410b03:	41 5f                	pop    %r15
  410b05:	5d                   	pop    %rbp
  410b06:	c5 f8 77             	vzeroupper
  410b09:	c3                   	ret

Disassembly of section .fini:
