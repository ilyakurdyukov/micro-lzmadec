## Micro LZMA decoder

Code Golf in Assembly with the goal of writing the smallest LZMA decoder.

Includes `x86_64` Linux version and `x86`/`x86_64` static version for use in compressed executables (see `test_static.c` for an example of usage).

Needs `nasm` to compile.

### Results

x86_64 Linux binary: 830 bytes (120 headers, 710 code)  
x86_64 static: 492 bytes  
x86 static: 492 bytes  

Yet it can be improved a little, especially the static version.
