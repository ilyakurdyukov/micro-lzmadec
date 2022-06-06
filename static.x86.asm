; -*- tab-width: 8 -*-
; Copyright (c) 2022, Ilya Kurdyukov
; All rights reserved.
;
; Micro LZMA decoder for x86 (static)
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

; build: nasm -f bin -O9 static.x86.asm -o static32.bin

BITS 32
ORG 0
section .text
	dd _code_end - _code

; code = bswap32(*(uint32_t*)(src+5+8+1))
; pb = (1 << first / 9 / 5) - 1
; lp = (1 << first / 9 % 5) - 1
; lc = first % 9

	dd _rel_code - 4 - _code
	dd _rel_tsize - 4 - _code
	dd _rel_dst1 - 1 - _code
	dd _rel_pb - 1 - _code
	dd _rel_lp - 1 - _code
	dd _rel_lc - 1 - _code

_code:

%assign loc_pos 0
%macro LOC 1-3 4, dword
%assign loc_pos loc_pos+%2
%ifidn %3, none
%xdefine %1 [ebp-loc_pos]
%else
%xdefine %1 %3 [ebp-loc_pos]
%endif
%endmacro
LOC _rep0
LOC _rep1
LOC _rep2
LOC _rep3
%assign loc_rep loc_pos
LOC Code
%assign loc_code loc_pos
LOC Range
%assign loc_range loc_pos
LOC _state

%define _rc_bit edi
; src + 1+4+8+1+4
%define Src dword [ebp+12]
%define Dest dword [ebp+8]
%define Temp dword [ebp+4]

_start:	enter	0, 0
	xor	eax, eax
	inc	eax
	push	eax
	push	eax
	push	eax
	push	eax
	mov	ecx, 0x12345678
_rel_tsize:
	mov	edi, Temp
	shl	eax, 10
	rep	stosw
	push	0x12345678	; Code
_rel_code:
	push	-1		; Range
	push	ecx		; _state
	xor	ebx, ebx	; Prev = 0
	call	_loop1
_rc_bit1:
	push	edx
	push	esi
	call	_rc_norm
	shl	esi, 1
	add	esi, Temp
	movzx	eax, word [esi]
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
	sub	[esi], ax
	popf
	cmc
	pop	esi
	pop	edx
	ret

_rc_norm:
	cmp	byte [ebp-loc_range+3], 0
	jne	.1
	shl	Range, 8
	shl	Code, 8
	mov	eax, Src
	mov	al, [eax]
	inc	Src
	mov	[ebp-loc_code], al
.1:	ret

_loop1:	pop	_rc_bit
_loop:	mov	ecx, Dest
	add	ecx, 0x55
_rel_dst1:
	mov	bh, cl
	pop	esi		; _state
	push	esi
	and	ecx, 0x55	; posState
_rel_pb:
	shl	esi, 4		; state * 16

	; probs + state * 16 + posState
	add	esi, ecx
	call	_rc_bit
	cdq
	pop	eax
	jc	_case_rep
	and	bh, 0x55
_rel_lp:
	shl	ebx, 0x55
_rel_lc:
	mov	bl, 0
	lea	esi, [ebx+ebx*2+2048]
_case_lit:
	lea	ebx, [edx+1]
	; state = 0x546543210000 >> state * 4 & 15;
	; state = state < 4 ? 0 : state - (state > 9 ? 6 : 3)
.4:	add	al, -3
	sbb	cl, cl
	and	al, cl
	cmp	al, 7
	jae	.4
	push	eax		; _state
%if 0	; -2 bytes, but slower
	; will read one byte before Dest
	add	al, -4
	sbb	dh, dh
%else
	cmp	al, 7-3
	jb	.2
	; mov	edx, 256 ; offset
	mov	dh, 1
%endif
	mov	eax, Dest
	sub	eax, _rep0
	; cl = -1
	xor	cl, [eax]
	mov	ch, 0
	; ch = 0, bl = 1
.1:	xor	ch, bl
	and	dh, ch
.2:	shl	ecx, 1
	push	esi
	mov	eax, edx
	add	esi, edx
	and	eax, ecx
	add	esi, ebx
	add	esi, eax
	call	_rc_bit
	pop	esi
	adc	bl, bl
	jnc	.1
	cdq	; _len
	jmp	_copy.2

_case_rep:
	mov	dl, 192/2
	lea	ebx, [esi+edx*2]	; IsRep0Long, 192
	lea	esi, [eax+edx*4]	; IsRep, 384 + state
	add	al, -7
	sbb	al, al
	and	al, 3
	push	eax		; _state
	call	_rc_bit
	jc	.2
	mov	eax, _rep0
	xchg	_rep1, eax
	xchg	_rep2, eax
	mov	_rep3, eax
	; state = state < 7 ? 0 : 3
	; LenCoder, 192/2*9
	jmp	_case_len

.2:	add	esi, 12
	call	_rc_bit
	jc	.3
	mov	esi, ebx
	call	_rc_bit
	jc	.5
	; state = state < 7 ? 9 : 11
	or	_state, 9
	cdq	; _len
	jmp	_copy.1

.3:	add	esi, 12
	call	_rc_bit
	mov	ebx, _rep0	; 1 0 2 3
	xchg	_rep1, ebx
	jnc	.4
	add	esi, 12
	call	_rc_bit
	xchg	_rep2, ebx	; 2 0 1 3
	jnc	.4
	xchg	_rep3, ebx	; 3 0 1 2
.4:	mov	_rep0, ebx
.5:	; state = state < 7 ? 8 : 11
	or	_state, 8
	mov	dl, 154		; RepLenCoder, 154*9
_case_len:
	lea	esi, [edx*8+edx]
	cdq
	call	_rc_bit
	inc	esi
	lea	ebx, [esi+ecx*8]	; +1 unnecessary
	mov	cl, 3
	jnc	.4
	sub	ebx, -128
	inc	edx	; edx = 8/8
	call	_rc_bit
	jnc	.4
	mov	cl, 8
	add	edx, 16/8-(1<<8)/8
	mov	ebx, esi
	inc	bh			; +1 unnecessary
.4:	; BitTree
	push	1
	pop	esi
	push	esi
.5:	push	esi
	add	esi, ebx
	call	_rc_bit
	pop	esi
	adc	esi, esi
	loop	.5
	lea	ebx, [esi+edx*8+2-8-1]
	cmp	_state, 4
	pop	edx	; edx = 1
	push	ebx	; _len
	jae	_copy
_case_dist:
	add	_state, 7
	sub	ebx, 3+2-1
	sbb	eax, eax
	and	ebx, eax
	lea	ebx, [edx-1+ebx*8+(432-128)/8+(3+2)*8]	; PosSlot
	; BitTree
	push	edx
.5:	lea	esi, [edx+ebx*8]
	call	_rc_bit
	adc	edx, edx
	mov	ecx, edx
	sub	ecx, 1<<6
	jb	.5
	pop	ebx	; ebx = 1
_case_model:
	cmp	ecx, 4
	jb	.9
	mov	esi, ebx
	shr	ecx, 1
	rcl	ebx, cl
	dec	ecx
	not	dl	; 256-edx-1
	mov	dh, 2
	add	edx, ebx
;	lea	edx, [edx+ebx+688+16+64-256*3]	; SpecPos
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
.5:	push	esi
	add	esi, edx
	call	_rc_bit
	pop	esi
	adc	esi, esi
	loop	.5
.6:	adc	ecx, ecx
	shr	esi, 1
	jne	.6
	add	ecx, ebx
.9:	inc	ecx
	mov	_rep0, ecx
	je	_end
_copy:	pop	edx
.1:	mov	eax, Dest
	sub	eax, _rep0
	movzx	ebx, byte [eax]
.2:	mov	eax, Dest
	mov	[eax], bl	; Dict + Pos
	inc	Dest
	dec	edx
	jns	.1
	jmp	_loop
_end:	leave
_code_end:
