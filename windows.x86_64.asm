; -*- tab-width: 8 -*-
; Copyright (c) 2022, Ilya Kurdyukov
; All rights reserved.
;
; Micro LZMA decoder utility for x86_64 Windows
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

; build: nasm -f bin -O9 windows.x86_64.asm -o lzmadec64.exe
;
; usage: lzmadec64.exe < input.lzma > output.bin
;
; exit codes:
; 0 - success
; 1 - error at reading header or wrong header
; 2 - cannot allocate memory for dictionary
; 3 - error at reading
; 4 - error at decoding, lzma stream is damaged
; 5 - cannot write output

BITS 64
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
dd _text_end - _text		; size of code
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
dd _text_end - _text, _text - _mz_header
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
_ReadWriteFile:
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

%assign loc_pos 0
%macro LOC 1-3 4, dword
%assign loc_pos loc_pos+%2
%ifidn %3, none
%xdefine %1 [rbp-loc_pos]
%else
%xdefine %1 %3 [rbp-loc_pos]
%endif
%endmacro
LOC _stdout
LOC _stdin

LOC _dummyA, 8
LOC OutSize, 8, qword
LOC DictSize1
LOC _dummyB
%assign loc_pos1 loc_pos	; 24
LOC _rep0
LOC _rep1
LOC _rep2
LOC _rep3
%assign loc_rep loc_pos		; 40
LOC Code, 8
%assign loc_code loc_pos
LOC Range
%assign loc_range loc_pos
LOC _dummyF
LOC _dummy1, 8
LOC _pb, 8
LOC _lp, 7, none
LOC _lc, 1, none
LOC DictSize, 8
LOC _dummy2, 8
LOC _state, 8

%define _rc_bit rdi
%define Pos r9d
%define Total r13

%macro READ_REP0 1
	mov	%1, Pos
	sub	%1, _rep0
	jae	%%1
	add	%1, DictSize
%%1:
%endmacro

_loop:	xor	r15d, r15d	; _len
	mov	rcx, Total
	mov	bh, cl
	pop	rsi		; _state
	push	rsi
	and	ecx, _pb	; posState, 0..15
	shl	esi, 5		; state * 16

	; probs + state * 16 + posState
	lea	esi, [rsi+rcx*2+64]
	call	_rc_bit
	cdq
	pop	rax
	jc	_case_rep
	mov	ecx, _lc
	and	bh, ch	; _lp
	shl	ebx, cl
	mov	bl, 0
	lea	ecx, [rbx+rbx*2+2048]
_case_lit:
	lea	ebx, [rdx+1]
	; state = 0x546543210000 >> state * 4 & 15;
	; state = state < 4 ? 0 : state - (state > 9 ? 6 : 3)
.4:	add	al, -3
	sbb	dl, dl
	and	al, dl
	cmp	al, 7
	jae	.4
	push	rax		; _state
%if 0	; -2 bytes, but slower
	add	al, -4
	sbb	bh, bh
%else
	cmp	al, 7-3
	jb	.2
	mov	bh, 1	 ; offset
%endif
	READ_REP0 eax
	; dl = -1, dh = 0, bl = 1
	xor	dl, [r12+rax]
.1:	xor	dh, bl
	and	bh, dh
.2:	shl	edx, 1
	mov	esi, ebx
	and	esi, edx
	add	esi, ebx
	add	esi, ecx
	call	_rc_bit
	adc	bl, bl
	jnc	.1
	jmp	_copy.2

_case_rep:
	mov	ebx, esi
	lea	esi, [rdx+rax*4+16]	; IsRep
	add	al, -7
	sbb	al, al
	and	al, 3
	push	rax		; _state
	call	_rc_bit
	jc	.2
	; r3=r2, r2=r1, r1=r0
%if 1
	; [3*4 -> 4*2, -4]
	movups	xmm0, [rbp-loc_rep]
	movups	[rbp-loc_rep-4], xmm0
%else
	; 0 0 1 2
	; shufps xmm0, xmm0, 0x90 [3*4 -> 4, -9]
	mov	rsi, [rbp-loc_rep+8]
	xchg	rsi, [rbp-loc_rep+4]
	mov	_rep3, esi
%endif
	; state = state < 7 ? 0 : 3
	mov	dl, 819/9	; LenCoder
	jmp	_case_len

.2:	inc	esi
	call	_rc_bit
	jc	.3
	lea	esi, [rbx+1]	; IsRep0Long
	call	_rc_bit
	jc	.5
	; state = state < 7 ? 9 : 11
	or	_state, 9
	jmp	_copy

.3:	mov	dl, 3
	mov	ebx, _rep0
.6:	inc	esi
	dec	edx
	xchg	[rbp-loc_rep+rdx*4], ebx
	je	.4
	call	_rc_bit
	jc	.6
.4:	mov	_rep0, ebx
.5:	; state = state < 7 ? 8 : 11
	or	_state, 8
	mov	dl, 1332/9	; RepLenCoder
_case_len:
	lea	esi, [rdx*8+rdx]
	cdq
	call	_rc_bit
	inc	esi
	lea	ebx, [rsi+rcx*8]	; +1 unnecessary
	mov	cl, 3
	jnc	.4
	mov	dl, 8/8
	call	_rc_bit
	jnc	.3
	; the first byte of BitTree tables is not used,
	; so it's safe to add 255 instead of 256 here
	lea	ebx, [rsi+127]
	mov	cl, 8
	add	edx, 16/8-(1<<8)/8	; edx = -29
.3:	sub	ebx, -128	; +128
.4:	; BitTree
	push	1
	pop	rsi
	push	rsi
.5:	push	rsi
	add	esi, ebx
	call	_rc_bit
	pop	rsi
	adc	esi, esi
	loop	.5
	lea	ebx, [rsi+rdx*8+2-8-1]
	mov	r15d, ebx
	cmp	_state, 4
	pop	rdx	; edx = 1
	jae	_copy
_case_dist:
	add	_state, 7
	sub	ebx, 3+2-1
	sbb	eax, eax
	and	ebx, eax
	lea	ebx, [rdx-1+rbx*8+(432+16-128)/8+(3+2)*8]	; PosSlot
	; BitTree
	push	rdx
.5:	lea	esi, [rdx+rbx*8]
	call	_rc_bit
	adc	edx, edx
	mov	ecx, edx
	sub	ecx, 1<<6
	jb	.5
	pop	rbx	; ebx = 1
_case_model:
	cmp	ecx, 4
	jb	.9
	mov	esi, ebx
	shr	ecx, 1
%if 1
	; -3
	rcl	ebx, cl
	dec	ecx
%else
	adc	ebx, ebx
	dec	ecx
	shl	ebx, cl
%endif
	not	dl	; 256-edx-1
	mov	dh, 2
	add	edx, ebx
;	lea	edx, [rdx+rbx+688+16+64-256*3]	; SpecPos
	cmp	ecx, 6
	jb	.4
.1:	dec	ecx
	call	_rc_norm
	shr	Range, 1
	mov	edx, Range
	cmp	Code, edx
	jb	.3
	sub	Code, edx
	bts	ebx, ecx
.3:	cmp	ecx, 4
	jne	.1
	cdq		; Align
.4:
.5:	push	rsi
	add	esi, edx
	call	_rc_bit
	pop	rsi
	adc	esi, esi
	loop	.5
.6:	adc	ecx, ecx
	shr	esi, 1
	jne	.6
	add	ecx, ebx
.9:	inc	ecx
	mov	_rep0, ecx
	je	_end
	; movss xmm0, _rep0 [5]
_copy:	mov	ecx, _rep0
	cmp	Total, rcx
.4:	push	4
	jb	_end.2
	cmp	DictSize, ecx
	jb	_end.2
	pop	rbx
.1:	READ_REP0 ecx
	mov	bl, [r12+rcx]
.2:	mov	[r12+r9], bl	; Dict + Pos
	inc	Total
	inc	Pos
	cmp	OutSize, Total
	jb	.4
	cmp	Pos, DictSize
	jb	.8
	call	_write
.8:	dec	r15d
	jns	.1
	push	rdi
.9:	pop	rdi
	cmp	OutSize, Total
.10:	jne	_loop
	cmp	Code, 0
	jne	.10
_end:	neg	Code
	jc	_copy.4
	push	0	; exit code
.2:	call	_write
.0:	pop	rcx
.1:	and	rsp, -16
	call	ExitProcess

_rc_norm:
	cmp	byte [rbp-loc_range+3], 0
	jne	.1
%if 1	; -2
	shl	qword [rbp-loc_range], 8
%else
	shl	Range, 8
	shl	Code, 8
%endif
	xor	eax, eax
	push	rdx
	push	3
	lea	rdx, [rbp-loc_code]
	lea	r8d, [rax+1]
.2:	push	rcx
	mov	ecx, [rbp-8+rax*4]
	push	r9
	push	r8
	push	0
	mov	r9, rsp
	enter	40, 0
	and	rsp, -16
	and	qword [rsp+32], 0
%if 0	; 4 byte less, but position dependent
	call	qword [RVA(_ReadWriteFile)+_image_base+rax*8]
%else
	lea	r10, [rel _ReadWriteFile]
	call	qword [r10+rax*8]
%endif
	test	eax, eax
	leave
	pop	rdx
	pop	rax
	pop	r9
	pop	rcx
	je	_end.2
	cmp	edx, eax
	jne	_end.2
	pop	rax
	pop	rdx
.1:	ret

_write:
	xor	r8d, r8d
	xchg	r8d, Pos
	push	rdx
	push	1
	pop	rax
	mov	rdx, r12
	push	5
	jmp	_rc_norm.2

_start:	enter	loc_pos1, 0
	xor	ebx, ebx
	push	rbx
	push	rbx
	sub	rsp, 32
	mov	rdi, GetStdHandle
	lea	ecx, [rbx-11]	; STD_OUTPUT_HANDLE
	call	rdi
	mov	_stdout, eax
	lea	ecx, [rbx-10]	; STD_INPUT_HANDLE
	call	rdi
	mov	_stdin, eax
	xchg	ecx, eax

	lea	rsi, [rbp-loc_pos1+3]
	lea	r9, [rbp-loc_pos1-8]
	lea	r8d, [rbx+5+8+5]
	push	rsi
	pop	rdx
	call	ReadFile
	neg	eax
	sbb	eax, eax
	add	rsp, 40
	pop	rdx
	and	edx, eax

	; eax = -1, if no error at reading
;	or	eax, -1		; 0xffffffff
	add	rax, 2		; 0x100000001
	push	rax
	push	rax
	mov	ecx, [rsi+14]
	bswap	ecx
	push	rcx	; Code
	push	-1	; Range
	or	dh, [rsi+13]
	sub	edx, 5+8+5
	push	1
.err:	jne	_end.0
	lodsb
	cmp	al, 9*5*5
	jae	_end.0
	mov	ebx, (768<<5)+31
	clc
	cdq
.1:	adc	edx, edx
	add	al, -9*5
	jc	.1
	push	rdx	; _pb
	cdq
.2:	shr	ebx, 1
	add	al, 9
	jnc	.2
	xchg	ah, bl
	xchg	ecx, eax
	shl	ebx, cl
	push	rcx	; _lc, _lp
%if 1	; -3, allocates 404 bytes more
	add	bh, 8
%else
	add	ebx, 1846
%endif

	lodsd
	mov	dh, 0x1000>>8
	cmp	eax, edx
	jae	.3
	xchg	eax, edx
.3:	push	rax	; DictSize
	lea	rsi, [rax+rbx*2]

	push	rsi
	pop	rdx
	xor	ecx, ecx
	mov	r8d, 0x1000	; MEM_COMMIT
	lea	r9d, [rcx+4]	; PAGE_READWRITE
	enter	32, 0
	call	VirtualAlloc
	leave
	test	rax, rax
	xchg	rdi, rax
	push	2
	je	.err

	mov	ecx, ebx
	mov	r14, rdi	; _prob
	mov	ax, 1<<10
	rep	stosw
	push	rcx		; _state
	mov	r12, rdi	; Dict
	xor	ebx, ebx	; Prev = 0
	mov	Pos, ecx
	xor	Total, Total
	call	_copy.9
_rc_bit1:
	push	rdx
	call	_rc_norm
	movzx	eax, word [r14+rsi*2]
	mov	edx, Range
	shr	edx, 11
	imul	edx, eax	; bound
	sub	Range, edx
	sub	Code, edx
	jae	.1
	mov	Range, edx
	add	Code, edx
	cdq
	sub	eax, 2048-31
.1:	shr	eax, 5		; eax >= 0
	sub	[r14+rsi*2], ax
	neg	edx
	pop	rdx
	ret

align 512, db 0
_text_end:

