#define _GNU_SOURCE 1  /* REG_RIP */
#include <stdlib.h>
#include <stdio.h>
#include <string.h>
#include <stdint.h>
#include <sys/mman.h>

static uint8_t* loadfile(const char *fn, size_t *num) {
	size_t n, j = 0; uint8_t *buf = 0;
	FILE *f = fopen(fn, "rb");
	if (f) {
		fseek(f, 0, SEEK_END);
		n = ftell(f);
		fseek(f, 0, SEEK_SET);
		if (n) {
			buf = (uint8_t*)malloc(n);
			if (buf) j = fread(buf, 1, n, f);
		}
		fclose(f);
	}
	if (num) *num = j;
	return buf;
}

#define TRY_CATCH 0
#if TRY_CATCH
#include <setjmp.h>
#include <signal.h>
static jmp_buf try_return;
static void sighandler(int sig, siginfo_t *si, void *data) {
	const ucontext_t *ctx = (ucontext_t*)data;
	fprintf(stderr, "!!! %s at address %p\n", sig == SIGSEGV ? "SIGSEGV" : "SIGBUS", (void*)si->si_addr);
#if defined(__x86_64__)
	fprintf(stderr, "RIP: %p\n", (void*)ctx->uc_mcontext.gregs[REG_RIP]);
#elif defined(__i386__)
	fprintf(stderr, "EIP: %p\n", (void*)ctx->uc_mcontext.gregs[REG_EIP]);
#endif
	longjmp(try_return, 1);
}
static void sethandler() {
	struct sigaction sa;
	sa.sa_flags = SA_SIGINFO;
	sigemptyset(&sa.sa_mask);
	sa.sa_sigaction = sighandler;
	sigaction(SIGSEGV, &sa, NULL);
	sigaction(SIGBUS, &sa, NULL);
}
#endif

int main(int argc, char **argv) {
	size_t code_size, src_size;
	unsigned long long out_size;
	uint8_t *code1, *code2, *src, *out, *out2, *temp; char *end;
	uint32_t *header; int tsize = 2048, code_extra;
	if (argc != 1 + 3) return 1;
	code1 = loadfile(argv[1], &code_size);
	if (!code1) {
		fprintf(stderr, "!!! error loading code\n");
		return 1;
	}
	header = (uint32_t*)code1;
	if (code_size < 4 * 7 || code_size - 4 * 7 != header[0]) {
		fprintf(stderr, "!!! code header is wrong\n");
		return 1;
	}
	code_size = header[0];
	fprintf(stderr, "code size = %u\n", (int)code_size);

	src = loadfile(argv[2], &src_size);
	if (!src) {
		fprintf(stderr, "!!! error loading src data\n");
		return 1;
	}
	out_size = strtoull(argv[3], &end, 0);
	if (!!*end) {
		fprintf(stderr, "!!! error reading out size\n");
		return 1;
	}
	if (!(out = malloc(out_size))) {
		fprintf(stderr, "!!! malloc failed (out)\n");
		return 1;
	}

#if defined(__x86_64__)
	code_extra = 3 + 3 * 10 + 6;
#elif defined(__i386__)
	code_extra = 3 + 3 * 5 + 7;
#else
#error
#endif

	code2 = mmap(NULL, code_extra + code_size,
			PROT_EXEC + PROT_READ + PROT_WRITE,
			MAP_PRIVATE + MAP_ANONYMOUS, -1, 0);
	if (!code2) {
		fprintf(stderr, "!!! mmap failed\n");
		return 1;
	}

	{
		uint8_t *p = code2, *c = src + 14;
		int pb, lp, lc = src[0];
		pb = lc / 9; lc %= 9; lp = pb % 5; pb /= 5;

		if (pb >= 5 || c[-1] || *(int64_t*)(src + 5) != -1) {
			fprintf(stderr, "!!! wrong lzma stream\n");
			return 1;
		}

		tsize += 768 << (lc + lp);
		if (!(temp = malloc(tsize * 2))) {
			fprintf(stderr, "!!! malloc failed (temp)\n");
			return 1;
		}

#if defined(__x86_64__)
		*p++ = 0x53;	// push rdi
		*p++ = 0x56;	// push rsi
		*p++ = 0x57;	// push rbx

		p[0] = 0x49; p[1] = 0xb8;
		*(uint64_t*)(p + 2) = (uintptr_t)src + 18;
		p += 10;

		p[0] = 0x49; p[1] = 0xb9;
		*(uint64_t*)(p + 2) = (uintptr_t)out;
		p += 10;

		p[0] = 0x49; p[1] = 0xba;
		*(uint64_t*)(p + 2) = (uintptr_t)temp;
		p += 10;
#elif defined(__i386__)
		*p++ = 0x53;	// push edi
		*p++ = 0x56;	// push esi
		*p++ = 0x57;	// push ebx

		p[0] = 0x68;
		*(uint32_t*)(p + 1) = (uintptr_t)src + 18;
		p += 5;

		p[0] = 0x68;
		*(uint32_t*)(p + 1) = (uintptr_t)out;
		p += 5;

		p[0] = 0x68;
		*(uint32_t*)(p + 1) = (uintptr_t)temp;
		p += 5;
#endif

		memcpy(p, header + 7, code_size);

		*(uint32_t*)(p + header[1]) =
				c[0] << 24 | c[1] << 16 | c[2] << 8 | c[3];
		*(uint32_t*)(p + header[2]) = tsize;
		// negative low byte of the dest addr
		*(uint8_t*)(p + header[3]) = -(intptr_t)out;
		*(uint8_t*)(p + header[4]) = (1 << pb) - 1;
		*(uint8_t*)(p + header[5]) = (1 << lp) - 1;
		*(uint8_t*)(p + header[6]) = lc;

		p += code_size;

#if defined(__x86_64__)
		*p++ = 0x49; *p++ = 0x91;	// xchg rax, r9
		*p++ = 0x5f;	// pop rdi
		*p++ = 0x5e;	// pop rsi
		*p++ = 0x5b;	// pop rbx
		*p++ = 0xc3;	// ret
#elif defined(__i386__)
		*p++ = 0x59;	// pop ecx
		*p++ = 0x58;	// pop eax
		*p++ = 0x59;	// pop ecx
		*p++ = 0x5f;	// pop edi
		*p++ = 0x5e;	// pop esi
		*p++ = 0x5b;	// pop ebx
		*p++ = 0xc3;	// ret
#endif
		if (p != code2 + code_size + code_extra) {
			fprintf(stderr, "!!! code size mismatch\n");
			return 1;
		}
	}

	fprintf(stderr, "src = %p\n", src);
	fprintf(stderr, "dest = %p\n", out);
	fprintf(stderr, "tmp = %p, %i*2\n", temp, tsize);
	fprintf(stderr, "code = %p\n", code2);
#if TRY_CATCH
	out2 = 0;
	sethandler();
	if (setjmp(try_return)) {

	} else
#endif
	out2 = ((uint8_t*(*)(void))code2)();
	if (out2 != out + out_size) {
		fprintf(stderr, "!!! wrong result size\n");
	}

	fwrite(out, 1, out_size, stdout);
	return 0;
}
