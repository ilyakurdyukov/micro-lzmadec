## Micro LZMA decoder

Code Golf in Assembly with the goal of writing the smallest LZMA decoder.

Includes `x86_64` Linux version and `x86`/`x86_64` static version for use in compressed executables (see `test_static.c` for an example of usage).

Needs `nasm` to compile.

### Results

x86_64 Linux binary: 828 bytes (120 headers, 708 code)  
x86_64 static: 489 bytes  
x86 static: 487 bytes  

Yet it can be improved a little, especially the static version.

### Probability Model Map

Notes for a better understanding of the code.

##### Original:
```
IsMatch: 0, 192      # state << 4 | posState
IsRep: 192, 12       # state
IsRepG0: 204, 12     # state
IsRepG1: 216, 12     # state
IsRepG2: 228, 12     # state
IsRep0Long: 240, 192 # state << 4 | posState
PosSlot: 432, 256
SpecPos: 688, 114
Align: 802, 16
LenCoder: 818, 2 + 512
RepLenCoder: 1332, 2 + 512
Literal: 1846, 0
```
##### New:
```
IsRep{,G0,G1,G2}: 0, 4*12       # state * 4
IsMatch, IsRep0Long: 48, 2*192	# (state << 4 | posState) * 2
PosSlot: 432, 256
Align: 688, 16
SpecPos: 704, 114 + 1 (padding)
LenCoder: 819, 2 + 511
RepLenCoder: 1332, 2 + 511 + 203 (padding)
Literal: 2048, 0
```
