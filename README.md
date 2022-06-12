## Micro LZMA decoder

Code Golf in Assembly with the goal of writing the smallest LZMA decoder.

Includes `x86_64` version for Linux and Windows, and `x86`/`x86_64` static version for use in compressed executables (see `test_static.c` for an example of usage).

Needs `nasm` to compile.

### Results

x86_64 Linux binary: 824 bytes (120 headers, 704 code)  
x86_64 Windows binary: 1536 bytes (a lot of headers, tables and padding...)  
x86_64 static: 483 bytes  
x86 static: 480 bytes  

Yet it can be improved a little, especially the static version.

### Limitations

LZMA archives can have a dictionary size of up to 4 GB, your OS must be able to allocate a buffer of this size for this decoder to work.

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
Align: 0, 16
IsRep{,G0,G1,G2}: 16, 4*12       # state * 4
IsMatch, IsRep0Long: 64, 2*192	# (state << 4 | posState) * 2
PosSlot: 448, 256
SpecPos: 704, 114 + 1 (padding)
LenCoder: 819, 2 + 511
RepLenCoder: 1332, 2 + 511 + 203 (padding)
Literal: 2048, 0
```
