; -*- tab-width: 8 -*-
; Copyright (c) 2022, Ilya Kurdyukov
; All rights reserved.
;
; Micro LZMA decoder utility for x86_64 Linux
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

; build: nasm -f bin -O9 lzmadec.x86_64.asm -o lzmadec && chmod +x lzmadec
;
; usage: ./lzmadec < input.lzma > output.bin
;
; exit codes:
; 0 - success
; 1 - error at reading header or wrong header
; 2 - cannot allocate memory for dictionary
; 3 - error at reading
; 4 - error at decoding, lzma stream is damaged
; 5 - cannot write output

; Ways to make the code even smaller:
; 1. Place code in unused fields in the ELF header.
; 2. Remove error reporting via exit codes.
; 3. Immediate writing of each byte (makes decompression very slow). 

%ifndef @pie
%define @pie 0
%endif

BITS 64
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
	dq _code_seg		; p_paddr (unused)
	dq _code_end-_code_seg	; p_filesz
	dq _code_end-_code_seg	; p_memsz
	dq 0x1000		; p_align

%assign loc_pos 0
%macro LOC 1-3 4, dword
%assign loc_pos loc_pos+%2
%ifidn %3, none
%xdefine %1 [rbp-loc_pos]
%else
%xdefine %1 %3 [rbp-loc_pos]
%endif
%endmacro
LOC _dummyA, 8
LOC OutSize, 8, qword
LOC DictSize
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
LOC _dummy2, 8
LOC _state, 8

%define _rc_bit rdi
%define Pos r9d
%define Total r13

; 12*5 - (12*2+6+4) = 26 ; call rdi
; 12*5 - (12*3+5) = 19 ; call [rbp-N]

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
	and	ecx, _pb	; posState
	; ecx = 0..255
	shl	esi, 4		; state * 16

	; probs + state * 16 + posState
	add	esi, ecx
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
	mov	dl, 192/2
	lea	ebx, [rsi+rdx*2]	; IsRep0Long, 192
	lea	esi, [rax+rdx*4]	; IsRep, 384 + state
	add	al, -7
	sbb	al, al
	and	al, 3
	push	rax		; _state
	call	_rc_bit
	jc	.2
%if 1
	; [3*4 -> 4*2, -4]
	movups	xmm0, [rbp-loc_rep]
	movups	[rbp-loc_rep-4], xmm0
%else
	; 0 0 1 2
	; shufps xmm0, xmm0, 0x90 [3*4 -> 4, -9]
	mov	eax, _rep0
	xchg	_rep1, eax
	xchg	_rep2, eax
	mov	_rep3, eax
%endif
	; state = state < 7 ? 0 : 3
;	lea	esi, [rdx*8+rdx]		; -2, 818+46 = 192/2*9
;	lea	esi, [rdx*8+rdx+818-192/2*9]	; -1
;	mov	esi, 818	; LenCoder
	jmp	_case_len

.2:	add	esi, 12
	call	_rc_bit
	jc	.3
	mov	esi, ebx
	call	_rc_bit
	jc	.5
	; state = state < 7 ? 9 : 11
	or	_state, 9
	jmp	_copy

.3:	mov	dl, 3
	mov	ebx, _rep0
.6:	dec	edx
	lea	esi, [rsi+12]
	xchg	[rbp-loc_rep+rdx*4], ebx
	je	.4
	call	_rc_bit
	jc	.6
.4:	mov	_rep0, ebx
.5:	; state = state < 7 ? 8 : 11
	or	_state, 8
;	mov	esi, 1332+46	; RepLenCoder
	mov	dl, 154		; 154*9 = 1332+54
_case_len:
	lea	esi, [rdx*8+rdx]
	cdq
	call	_rc_bit
	inc	esi
	lea	ebx, [rsi+rcx*8]	; +1 unnecessary
	mov	cl, 3
	jnc	.4
	sub	ebx, -128
	mov	dl, 8/8
	call	_rc_bit
	jnc	.4
	mov	cl, 8
	add	edx, 16/8-(1<<8)/8
	mov	ebx, esi
	inc	bh			; +1 unnecessary
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
	lea	ebx, [rdx-1+rbx*8+(432-128)/8+(3+2)*8]	; PosSlot
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
	mov	eax, Range
	cmp	Code, eax
	jb	.3
	sub	Code, eax
	bts	ebx, ecx
.3:	cmp	ecx, 4
	jne	.1
	mov	edx, 802+16	; Align
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
.0:	pop	rdi
.1:	push	@sys_exit
	pop	rax
	syscall

_rc_norm:
	cmp	byte [rbp-loc_range+3], 0
	jne	.1
%if 1	; -2
	shl	qword [rbp-loc_range], 8
%else
	shl	Range, 8
	shl	Code, 8
%endif
	push	rcx
	push	rsi
	push	rdi
	; ax dx si di + cx r11
	xor	edi, edi	; 0 (stdin)
	lea	rsi, [rbp-loc_code]
	lea	edx, [rdi+1]
%if @sys_read == 0
	mov	eax, edi
%else
	lea	eax, [rdi+@sys_read]
%endif
	syscall
	push	3
	dec	eax
	jne	_end.2
	pop	rax
	pop	rdi
	pop	rsi
	pop	rcx
.1:	ret

_write:
	cdq
	xchg	edx, Pos
	mov	rsi, r12
	push	rdi
	push	1
	pop	rdi
%if @sys_write == 1
	mov	eax, edi
%else
	lea	eax, [rdi+@sys_write-1]
%endif
	syscall
	push	5
	cmp	eax, edx
	jne	_end.2
	pop	rax
	pop	rdi
	ret

_start:	enter	loc_pos1, 0
	xor	edi, edi	; 0 (stdin)
	or	eax, -1		; 0xffffffff
	; movd xmm0, eax [4]
	; shufps xmm0, xmm0, 0 [4]
	add	rax, 2		; 0x100000001
	push	rax
	push	rax
	; (3)+1+4+8+(1)+4
	lea	edx, [rdi+5+8+5]
	lea	rsi, [rbp-24+3]
%if @sys_read == 0
	mov	eax, edi
%else
	lea	eax, [rdi+@sys_read]
%endif
	syscall
	mov	ecx, [rbp-7]
	bswap	ecx
	push	rcx	; Code
	push	-1	; Range
	or	dh, [rbp-8]
	sub	edx, eax
	push	1
.err:	jne	_end.0
	; rdx = 0, rax = 5+8+5, rdi = 0
	lodsb
	cmp	al, 9*5*5
	jae	_end.0
	mov	ebx, (768<<5)+31
	clc
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
	add	ebx, 1846/2
%endif

	lodsd
	mov	dh, 0x1000>>8
	cmp	eax, edx
	jae	.3
	xchg	eax, edx
.3:	lea	rsi, [rax+rbx*2]

	xor	r9, r9	; off
	or	r8, -1	; fd
	; xor	edi, edi	; addr
	lea	eax, [rdi+@sys_mmap]
	; prot: 1-read, 2-write, 4-exec
	lea	edx, [rdi+3]
	; map: 2-private, 0x20-anonymous
	lea	r10d, [rdi+0x22]
	syscall
	; err = ret >= -4095u
	; (but negative pointers aren't used)
	add	rdi, rax
	push	2
	js	.err
	mov	ecx, ebx
	xchg	r14, rax	; _prob
	mov	ax, 1<<10
	rep	stosw
	push	rcx		; _state
	mov	r12, rdi	; Dict
	xor	ebx, ebx	; Prev = 0
	; Pos = r9 = 0
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
	pushf
	jae	.1
	mov	Range, edx
	add	Code, edx
	sub	eax, 2048-31
.1:	shr	eax, 5		; eax >= 0
	sub	[r14+rsi*2], ax
	popf
	cmc
	pop	rdx
	ret

_code_end:

