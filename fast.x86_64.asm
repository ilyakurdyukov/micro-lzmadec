; -*- tab-width: 8 -*-
; Copyright (c) 2022, Ilya Kurdyukov
; All rights reserved.
;
; Micro LZMA decoder utility for x86_64 (fast)
;
; This software is distributed under the terms of the
; Creative Commons Attribution 3.0 License (CC-BY 3.0)
; http://creativecommons.org/licenses/by/3.0/
;
; THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS
; OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
; FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
; AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
; LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
; OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
; THE SOFTWARE.

; Linux build: nasm -f bin -O9 fast.x86_64.asm -o lzmadec64 && chmod +x lzmadec64
; Windows build: nasm -f bin -O9 -d@windows=1 fast.x86_64.asm -o lzmadec64.exe
;
; Usage: lzmadec64 < input.lzma > output.bin

BITS 64

%assign loc_pos 0
%macro LOC 1-3 4, dword
%assign loc_pos loc_pos+%2
%ifidn %3, none
%xdefine %1 [rbp-loc_pos]
%else
%xdefine %1 %3 [rbp-loc_pos]
%endif
%endmacro

%ifdef @windows

ORG 0
section .text

_mz_header:
db 'MZ'	; magic
dw 0, 0, 0, 0, 0, 0, 0
dw 0, 0, 0, 0, 0, 0, 0, 0
dw 0, 0, 0, 0, 0, 0, 0, 0
dw 0, 0, 0, 0, 0, 0
dd _pe_header - _mz_header

%define _image_base 0x400000

_pe_header:
db 'PE',0,0
dw 0x8664	; AMD64
dw 1		; number of sections
dd 0		; time stamp
dd 0, 0		; symbol table (offset, count)
; size of optional header
dw _opt_header_end - _opt_header
dw 0x22e	; characteristics
_opt_header:
dw 0x20b	; magic
db 2, 34	; linker version (major, minor)
dd _code_end - _text		; size of code
dd 0		; size of initialized data
dd 0		; size of uninitialized data
dd 0x1000 + (_start - _text)	; entry point
dd 0x1000	; base of code
dq _image_base	; image base
dd 0x1000	; section alignment
dd 0x200	; file alignment
dw 4, 0		; OS version (major, minor)
dw 0, 0		; image version (major, minor)
dw 5, 2		; subsystem version (major, minor)
dd 0		; Win32 version
dd 0x2000	; size of image
dd _text - _mz_header	; size of header
dd 0		; checksum
dw 3		; subsystem (1 - native, 2 - GUI, 3 - console)
dw 0		; DLL flag
dq 2 << 20, 0x1000	; stack reserve and commit
dq 2 << 20, 0x1000	; heap reserve and commit
dd 0		; loader flags
dd 2		; number of dirs

%define RVA(x) (x - _text) + 0x1000

dd 0, 0		; export
dd RVA(_import), _import_end - _import
_opt_header_end:

db ".text",0,0,0
; virtual size and address
dd 0x1000, 0x1000
; file size and address
dd _code_end - _text, _text - _mz_header
dd 0, 0	; relocs, linenumbers
dw 0, 0	; relocs count, linenumbers count
dd 0x60000060	; attributes

align 512, db 0
_text:

_import:
	dd 0, 0, 0, RVA(_name_kernel32), RVA(_kernel32_tab)
	dd 0, 0, 0, 0, 0
_import_end:

align 8, db 0
_kernel32_tab:
	dq RVA(_name_ExitProcess)
	dq RVA(_name_VirtualAlloc)
	dq RVA(_name_ReadFile)
	dq RVA(_name_WriteFile)
	dq RVA(_name_GetStdHandle)
	dq 0

%macro def_export 1
align 2, db 0
_name_%1:
dw 0
%defstr export_temp %1
db export_temp, 0
%xdefine %1 qword [rel _kernel32_tab+export_next]
%assign export_next export_next+8
%endmacro

_name_kernel32:
db "kernel32.dll", 0

%assign export_next 0
def_export ExitProcess
def_export VirtualAlloc
def_export ReadFile
def_export WriteFile
def_export GetStdHandle

_alloc:
	push	r8
	push	r9
	push	r10
	push	r11
	xor	ecx, ecx
	mov	rdx, [rsp+5*8]
	mov	r8d, 0x1000	; MEM_COMMIT
	lea	r9d, [rcx+4]	; PAGE_READWRITE
	enter	32, 0
	and	rsp, -16
	call	VirtualAlloc
	cmp	rax, 1
	leave
	pop	r11
	pop	r10
	pop	r9
	pop	r8
	ret	8

LOC _stdout
LOC _stdin

_io_read:
	push	r8
	push	r9
	push	r10
	push	r11
	xor	eax, eax
	mov	ecx, _stdin
	mov	rdx, [rsp+5*8]
	mov	r8d, [rsp+6*8]
	push	rax
	mov	r9, rsp
	enter	40, 0
	and	rsp, -16
	mov	[rsp+32], rax
	call	ReadFile
	neg	eax
	sbb	eax, eax
	leave
	pop	rdx
	and	eax, edx
	cmp	eax, [rsp+6*8]
	pop	r11
	pop	r10
	pop	r9
	pop	r8
	ret	2*8

_io_write:
	push	r8
	push	r9
	push	r10
	push	r11
	xor	eax, eax
	mov	ecx, _stdout
	mov	rdx, [rsp+5*8]
	mov	r8d, [rsp+6*8]
	push	rax
	mov	r9, rsp
	enter	40, 0
	and	rsp, -16
	mov	[rsp+32], rax
	call	WriteFile
	neg	eax
	sbb	eax, eax
	leave
	pop	rdx
	and	eax, edx
	cmp	eax, [rsp+6*8]
	pop	r11
	pop	r10
	pop	r9
	pop	r8
	ret	2*8
%else

%ifndef @pie
%define @pie 0
%endif

%if @pie
ORG 0
%else
ORG 0x400000
%endif

%define @sys_read 0
%define @sys_write 1
%define @sys_mmap 9
%define @sys_exit 60

section .text

%define @bits 64

_code_seg:
_elf:	db 0x7f,'ELF',2,1,1,0	; e_ident
	dq 0
	dw 2+@pie	; e_type
	dw 62		; e_machine
	dd 1		; e_version
	dq _start	; e_entry
	dq .ph-_elf	; e_phoff
	dq 0		; e_shoff
	dd 0		; e_flags
	dw 0x40		; e_ehsize
	dw 0x38, 1	; e_phentsize, e_phnum
	dw 0x40, 0	; e_shentsize, e_shnum
	dw 0		; e_shstrndx
.ph:	dd 1, 5			; p_type, p_flags
	dq 0			; p_offset
	dq _code_seg		; p_vaddr
	dq _code_seg		; p_paddr
	dq _code_end-_code_seg	; p_filesz
	dq _code_end-_code_seg	; p_memsz
	dq 0x1000		; p_align

_alloc:
	push	rsi
	push	rdi
	push	r8
	push	r9
	push	r10
	push	r11
	mov	rsi, [rsp+7*8]
	xor	r9, r9	; off
	or	r8, -1	; fd
	xor	edi, edi	; addr
	mov	eax, @sys_mmap
	; prot: 1-read, 2-write, 4-exec
	lea	edx, [rdi+3]
	; map: 2-private, 0x20-anonymous
	lea	r10d, [rdi+0x22]
	syscall
	; err = ret >= -4095u
	lea	rdx, [rax-1]
	shl	rdx, 1
	pop	r11
	pop	r10
	pop	r9
	pop	r8
	pop	rdi
	pop	rsi
	ret	8

_io_read:
	push	rsi
	push	rdi
	; ax dx si di + cx r11
	xor	edi, edi	; 0 (stdin)
	mov	rsi, [rsp+3*8]
	mov	rdx, [rsp+4*8]
	mov	eax, @sys_read
	push	r11
	syscall
	cmp	eax, edx
	pop	r11
	pop	rdi
	pop	rsi
	ret	2*8

_io_write:
	push	rsi
	push	rdi
	; ax dx si di + cx r11
	mov	edi, 1		; 1 (stdout)
	mov	rsi, [rsp+3*8]
	mov	rdx, [rsp+4*8]
	mov	eax, @sys_write
	push	r11
	syscall
	cmp	eax, edx
	pop	r11
	pop	rdi
	pop	rsi
	ret	2*8
%endif

LOC _lp, 3, none
LOC _lc, 1, none
LOC _code, 4, none
LOC _out_size, 8, qword
LOC _dict_size
LOC _pb
LOC _dict_end, 8
LOC _src_fin, 8, qword
LOC _src_end, 8, qword
LOC _src, 8, qword
%assign loc_pos1 loc_pos
LOC _state, 8
%assign loc_state loc_pos
LOC _total, 8, none
LOC _rep0
LOC _rep1
LOC _rep2
LOC _rep3

%define Range r13d
%define CodeB r8b
%define Code r8d
%define Pos r9d
%define PosQ r9
%define Dict r12
%define Prob r14
%define SrcSize 0x1000

_rc_next_read:
	cmp	rax, _src_fin
	jne	_end.3
	push	rcx
	sub	rax, SrcSize
	push	SrcSize
	push	rax
	mov	_src, rax
	call	_io_read
	pop	rcx
	test	eax, eax
	jle	_end.3
	add	rax, _src
	mov	_src_end, rax
	mov	rax, _src
	ret

%macro RC_NEXT 0
	mov	rax, _src
	cmp	rax, _src_end
	jne	%%1
	call	_rc_next_read
%%1:	shl	Code, 8
	shl	Range, 8
	mov	CodeB, [rax]
	inc	rax
	mov	_src, rax
%endmacro

%macro READ_REP0 1
	mov	%1, Pos
	sub	%1, _rep0
	sbb	edx, edx
	and	edx, _dict_size
	add	%1, edx
%endmacro

_start:	enter	loc_pos1, 0

%ifdef @windows
	xor	ebx, ebx
	mov	rdi, GetStdHandle
	enter	32, 0
	and	rsp, -16
	lea	ecx, [rbx-11]	; STD_OUTPUT_HANDLE
	call	rdi
	xchg	edi, eax
	lea	ecx, [rbx-10]	; STD_INPUT_HANDLE
	call	rax
	leave
	mov	_stdout, edi
	mov	_stdin, eax
%endif

	push	0		; _state
	push	0		; _total
	or	eax, -1		; 0xffffffff
	add	rax, 2		; 0x100000001
	push	rax
	push	rax

	mov	_src_end, rsp
	mov	_src_fin, rsp
	sub	rsp, SrcSize-8
	push	rax
	mov	rsi, rsp
	lea	rax, [rsi+5+8+5]
	mov	_src, rax

	push	SrcSize
	push	rsi
	call	_io_read
	cmp	eax, 5+8+5
	jl	_end.1
	cmp	byte [rsi+13], 0
	jne	_end.1
	xor	edx, edx
	movzx	eax, byte [rsi]
	cmp	al, 9*5*5
	jae	_end.1
	imul	edx, eax, 0x39
	mov	ebx, 768/2
	shr	edx, 9
	lea	ecx, [rdx+rdx*8]
	sub	eax, ecx
	mov	ecx, eax
	mov	_lc, eax
	shl	ebx, cl
	lea	eax, [rdx+rdx*8]
	lea	eax, [rax+rdx*4]
;	imul	eax, edx, 0xd
	mov	ecx, edx
	shr	eax, 6
	lea	edx, [rax+rax*4]
	sub	ecx, edx
	mov	edx, 1
	shl	edx, cl
	shl	ebx, cl
	add	ebx, 1846/2
	dec	edx
	mov	_lp, dl
	xor	edx, edx
	bts	edx, eax
	dec	edx
	mov	_pb, edx

	mov	eax, [rsi+1]
	mov	rdx, [rsi+5]
	cmp	eax, 0x1000
	jae	.3
	mov	eax, 0x1000
.3:	mov	_dict_size, eax
	mov	_out_size, rdx

	cmp	rax, rdx
	cmovb	edx, eax
	mov	_dict_end, edx

	lea	rdi, [rax+rbx*4]
	push	rdi
	call	_alloc
	mov	rdi, rax
	jc	_end.2

	mov	ecx, ebx
	mov	eax, 0x10001<<10
	mov	Prob, rdi	; _prob
	rep	stosd
	mov	Dict, rdi	; Dict
	xor	ebx, ebx	; Prev = 0

	xor	Pos, Pos
	or	Range, -1

	mov	Code, [rsi+14]
	bswap	Code
	; first byte should be literal
	cmp	Code, 0x7ffffc00
	jae	_end.4
	jmp	_copy.9

align 16
_loop:	mov	edx, _total
	add	edx, Pos
	mov	bh, dl
	mov	eax, _state
	and	edx, _pb	; posState
	shl	eax, 4		; state * 16

	; probs + state * 16 + posState
	lea	esi, [rax+rdx]
	call	_rc_bit
	jc	_case_rep
	mov	ecx, _lc
	and	bh, ch
	shl	ebx, cl
	and	ebx, -0x100
	lea	r10d, [rbx+rbx*2+1846]	; Literal
_case_lit:
	; state = 0x546543210000 >> state * 4 & 7
	; state = state < 4 ? 0 : state - (state > 9 ? 6 : 3)

	mov	ecx, _state
	mov	rax, 0x546543210000
	shl	ecx, 2
	shr	rax, cl
	and	eax, 7

	mov	ebx, 1
	cmp	eax, 7-3
	mov	[rbp-loc_state], al
	jb	.2
	READ_REP0 eax
	movzx	edx, byte [Dict+rax]
	mov	ebx, 0x101
	xor	edx, 0xff
	inc	Pos
	jmp	.2a

align 16
.2:	inc	Pos
.2b:	lea	esi, [rbx+r10]
	call	_rc_bit
	adc	bl, bl
	jnc	.2b
	cmp	Pos, _dict_end
	mov	[Dict+PosQ-1], bl	; Dict + Pos
	jne	_loop
	jmp	_copy.3

align 16
.1:	xor	dh, bl
	and	bh, dh
.2a:	shl	edx, 1
	lea	eax, [rbx+r10]
	mov	esi, ebx
	and	esi, edx
	add	esi, eax
	call	_rc_bit
	adc	bl, bl
	jnc	.1
	cmp	Pos, _dict_end
	mov	[Dict+PosQ-1], bl	; Dict + Pos
	jne	_loop
	jmp	_copy.3

align 16
_case_rep:
	mov	eax, _state
	mov	ebx, esi
	lea	esi, [rax+192]	; IsRep
	add	eax, -7
	sbb	eax, eax
	and	eax, 3
	mov	[rbp-loc_state], al
	call	_rc_bit
	jc	.2
	mov	eax, _rep0
	mov	ecx, _rep1
	mov	esi, _rep2
	mov	_rep1, eax
	mov	_rep2, ecx
	mov	_rep3, esi
	; state = state < 7 ? 0 : 3
	mov	esi, 818	; LenCoder
	jmp	_case_len

.2:	add	esi, 12		; IsRepG0
	call	_rc_bit
	jc	.3
	lea	esi, [rbx+240]	; IsRep0Long
	call	_rc_bit
	jc	.5
	; state = state < 7 ? 9 : 11
	or	_state, 9

	READ_REP0 eax
	movzx	ebx, byte [Dict+rax]
	mov	[Dict+PosQ], bl	; Dict + Pos
	inc	Pos
	cmp	Pos, _dict_end
	jne	_loop
	jmp	_copy.3

.3:	add	esi, 12		; IsRepG1
	call	_rc_bit
	mov	eax, _rep0	; 1 0 2 3
	mov	ebx, _rep1
	mov	_rep1, eax
	jnc	.4
	add	esi, 12		; IsRepG2
	call	_rc_bit
	mov	eax, ebx
	mov	ebx, _rep2
	mov	_rep2, eax	; 2 0 1 3
	jnc	.4
	mov	eax, ebx
	mov	ebx, _rep3
	mov	_rep3, eax	; 3 0 1 2
.4:	mov	_rep0, ebx
.5:	; state = state < 7 ? 8 : 11
	or	_state, 8
	mov	esi, 1332	; RepLenCoder
_case_len:
	lea	ebx, [rsi+rdx*8+2]
	xor	ecx, ecx
	mov	edx, 3
	call	_rc_bit
	jnc	.4
	inc	esi
	sub	ebx, -128
	mov	ecx, 8
	call	_rc_bit
	jnc	.4
	mov	edx, 8
	mov	ecx, 8+16-256
	lea	ebx, [rsi+257]
.4:	; BitTree
	mov	r10d, ecx
	mov	ecx, 1
.5:	lea	esi, [rbx+rcx]
	call	_rc_bit
	adc	ecx, ecx
	dec	edx
	jne	.5
	mov	eax, _state
	lea	ebx, [rcx+r10+2-8]
	mov	r15d, ebx
	cmp	eax, 4
	jae	_copy
_case_dist:
	add	eax, 7
	sub	ebx, 3+2
	mov	_state, eax
	sbb	eax, eax
	shl	ebx, 6
	and	ebx, eax
	mov	ecx, 1
	add	ebx, (432-128)+(3+2)*64		; PosSlot
	; BitTree
.5:	lea	esi, [rcx+rbx]
	call	_rc_bit
	mov	eax, ecx
	adc	ecx, ecx
	cmp	eax, 32
	jb	.5
	sub	ecx, 1<<6
_case_model:
	cmp	ecx, 4
	lea	esi, [rcx+1]
	jb	.9
	cmp	ecx, 14
	mov	esi, 1
	jb	.3
	shr	ecx, 1
	adc	esi, esi
	sub	ecx, 5
	jmp	.1

.3:	lea	eax, [rcx-(688-1)]	; SpecPos
	shr	ecx, 1
	rcl	esi, cl
	dec	ecx
	mov	ebx, esi
	sub	ebx, eax
	jmp	.4

ALIGN 16
.1:	cmp	Range, 0x1000000
	jae	.2
	RC_NEXT
.2:	shr	Range, 1
	mov	edx, Code
	sub	Code, Range
	cmovb	Code, edx
	cmc
	adc	esi, esi
	dec	ecx
	jne	.1
	mov	ecx, 4
	shl	esi, 4
	mov	ebx, 802	; Align
.4:	mov	edx, 1
	mov	r10d, esi
	push	rcx
.5:	lea	esi, [rbx+rdx]
	call	_rc_bit
	adc	edx, edx
	shrd	r10d, edx, 1
	dec	ecx
	jne	.5
	mov	esi, r10d
	pop	rcx
	rol	esi, cl
	inc	esi
	je	_end.6
.9:	mov	_rep0, esi
_copy:	mov	rdx, _total
	mov	r10d, _rep0
	add	rdx, PosQ
	cmp	_dict_size, r10d
	jb	_end.4
	cmp	rdx, r10
	jb	_end.4
.1:	mov	eax, _dict_end
	mov	ecx, r15d
	mov	r11d, eax
	sub	eax, Pos
	cmp	eax, ecx
	cmovb	ecx, eax

	mov	edx, Pos
	mov	eax, _dict_size
	sub	edx, r10d
	sbb	rsi, rsi
	and	esi, eax
	add	esi, edx
	sub	eax, esi
	cmp	eax, ecx
	lea	rdi, [Dict+PosQ]
	cmovb	ecx, eax

	add	rsi, Dict
	add	Pos, ecx
	sub	r15d, ecx
	rep	movsb
	cmp	Pos, r11d
	je	.4
	test	r15d, r15d
	jne	.1
.2:	movzx	ebx, byte [rdi-1]
	jmp	_loop

.3:	lea	rdi, [Dict+PosQ]
	xor	r15d, r15d
.4:	mov	rdx, _total
	mov	rax, _out_size
	add	rdx, PosQ
	mov	ecx, _dict_size
	sub	rax, rdx
	jb	_end.4
	cmp	rax, rcx
	cmovb	ecx, eax
	mov	_total, rdx
	mov	_dict_end, ecx
	push	PosQ
	push	Dict
	call	_io_write
	jne	_end.5
	xor	Pos, Pos
	test	r15d, r15d
	jne	.1
.9:	test	Code, Code
	jne	.2
	mov	rax, _total
	cmp	_out_size, rax
	jne	_loop
_end:	push	0	; exit code
	test	Pos, Pos
	je	.0
	push	PosQ
	push	Dict
	call	_io_write
	jne	_end.5
.0:
%ifdef @windows
	pop	rcx
	and	rsp, -16
	call	ExitProcess
%else
	pop	rdi
	mov	eax, @sys_exit
	syscall
%endif

.1:	push	1
	jmp	.0
.6:	neg	Code
	jnc	_end
.2:	push	2
	jmp	.0
.3:	push	3
	jmp	.0
.4:	push	4
	jmp	.0
.5:	push	5
	jmp	.0

align 16
_rc_bit:
	mov	edi, edx
	movzx	r11d, word [Prob+rsi*2]
	cmp	Range, 0x1000000
	jae	.1
	RC_NEXT
.1:	mov	edx, Range
	mov	eax, r11d
	shr	edx, 11
	push	rcx
%if 1
	mov	r11d, Code
	imul	edx, eax
	lea	ecx, [rax-31]
	shl	eax, 5
	sub	eax, ecx
	sub	Range, edx
	lea	ecx, [rax+2048-31]
	shr	eax, 5
	shr	ecx, 5
	sub	r11d, edx
	cmovb	Range, edx
	cmovae	Code, r11d
	cmovb	eax, ecx
	cmc
%else
	mov	ecx, Code
	imul	edx, eax
	lea	r11d, [rax+31-2048]
	sub	Range, edx
	sub	ecx, edx
	cmovb	Range, edx
	mov	edx, eax
	cmovae	Code, ecx
	cmovb	edx, r11d
	sbb	ecx, ecx
	shr	edx, 5
	sub	eax, edx
	cmp	ecx, 1
%endif
	pop	rcx
	mov	word [Prob+rsi*2], ax
	mov	edx, edi
	ret

%ifdef @windows
align 512, db 0
%endif
_code_end:

