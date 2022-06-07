## Micro LZMA decoder

Code Golf in Assembly with the goal of writing the smallest LZMA decoder.

Includes `x86_64` Linux version and `x86`/`x86_64` static version for use in compressed executables (see `test_static.c` for an example of usage).

Needs `nasm` to compile.

### Results

x86_64 Linux binary: 828 bytes (120 headers, 708 code)  
x86_64 static: 490 bytes  
x86 static: 490 bytes  

Yet it can be improved a little, especially the static version.
