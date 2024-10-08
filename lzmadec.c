#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdint.h>

#if 0
#define DBG_LOG(...) fprintf(stderr, __VA_ARGS__)
#else
#define DBG_LOG(...) (void)0
#endif

#define RC_READ_BYTE \
	a = getchar(); \
	if (a == EOF) return 3;

#define RC_NORMALIZE \
	if (!(range >> 24)) { \
		range <<= 8; RC_READ_BYTE \
		code = code << 8 | a; \
	}

#define RC_BIT(p) \
	RC_NORMALIZE \
	t2 = t0 = *p; t1 = t0 * (range >> 11); \
	bit0 = code < t1; \
	if (bit0) range = t1, t2 -= 2017; \
	else range -= t1, code -= t1; \
	*p = t0 - (t2 >> 5);

#define BIT_TREE \
	value = 1; do { \
		p1 = p3 + value; RC_BIT(p1) \
		value <<= 1; if (!bit0) value++; \
	} while (value < n); \
	value -= n;

int main(int argc, char **argv) {
	uint8_t *dict; int a; uint32_t pos = 0; uint64_t out = 0;
	uint32_t dict_size = 0, num_probs; uint64_t max_size = 0;

	uint16_t *probs = NULL, *p1, *p3;
	unsigned rep0 = 1, rep1 = 1, rep2 = 1, rep3 = 1;
	uint32_t lc, lp, pb, range = ~0, code = 0, t0, t1, t2;
	uint32_t value = 0, state = 0, bit0, len, i, n, k;
	int lzma_sprd = argc > 1 && !strcmp(argv[1], "--sprd");

	RC_READ_BYTE
	pb = a / 9; lc = a % 9; lp = pb % 5; pb /= 5;
	if (pb > 4) return 1;
	for (i = 0; i < 32; i += 8) { RC_READ_BYTE dict_size |= a << i; }
	for (i = 0; i < 64; i += 8) { RC_READ_BYTE max_size |= (uint64_t)a << i; }
	RC_READ_BYTE if (a) return 1;
	for (i = 0; i < 4; i++) { RC_READ_BYTE code = code << 8 | a; }

	if (dict_size < 0x1000) dict_size = 0x1000;
	num_probs = 1846 + (768 << (lc + lp));

	DBG_LOG("lc = %u, lp = %u, pb = %u\n", lc, lp, pb);
	DBG_LOG("DictSize = %d, numProbs = %d\n", dict_size, num_probs);

	probs = malloc(dict_size + num_probs * sizeof(*probs));
	if (!probs) return 2;
	dict = (uint8_t*)(probs + num_probs);
	for (i = 0; i < num_probs; i++) probs[i] = 1024;

	while (max_size != out) {
		len = 0;
		k = out & ((1 << pb) - 1);
		p3 = probs + state * 16 + k; RC_BIT(p3)
		if (bit0) {
			uint32_t offset;
			k = out & ((1 << lp) - 1);
			k = k << lc | value >> (8 - lc);
			p3 = probs + 1846 + 768 * k;
			offset = i = 0;
			if (!lzma_sprd && state >= 7) {
				offset = 0x100;
				i = dict[(pos < rep0 ? dict_size : 0) + pos - rep0];
			}
			len = value = 1;
			do {
				i <<= 1;
				p1 = p3 + offset + (i & offset) + value; RC_BIT(p1)
				value <<= 1;
				if (bit0) offset &= ~i; else value++, offset &= i; 
			} while (value < 256);
			state -= state < 4 ? state : state > 9 ? 6 : 3;
			value &= 255;
			goto copy;

		} else {
			p1 = probs + 192 + state;
			state = state < 7 ? 0 : 3;
			RC_BIT(p1)
			if (bit0) {
				rep3 = rep2; rep2 = rep1; rep1 = rep0;
				p1 = probs + 818;
			} else {
				p1 += 12; RC_BIT(p1)
				if (bit0) {
					p3 += 240; RC_BIT(p3)
					if (bit0) state |= 9, len = 1;
				} else {
					p1 += 12; RC_BIT(p1)
					if (bit0) n = rep1;
					else {
						p1 += 12; RC_BIT(p1)
						if (bit0) n = rep2; else n = rep3, rep3 = rep2;
						rep2 = rep1;
					}
					rep1 = rep0; rep0 = n;
				}
				if (!len) p1 = probs + 1332, state |= 8;
				else state |= 9;
			}

			if (!len) {
				len = 2; n = 8;
				p3 = p1 + k * 8 + 2; RC_BIT(p1)
				if (!bit0) {
					p1++; len = 10;
					p3 += 128; RC_BIT(p1)
					if (!bit0) n = 256, p3 = p1 + n + 1, len += 8;
				}
				BIT_TREE
				len += value;
				if (state < 4) {
					state += 7; n = 64;
					p3 = probs + 304 + (len < 6 ? len : 5) * n;
					BIT_TREE
					rep0 = value;
					if (rep0 > 3) {
						n = (value >> 1) - 1; i = 1 << n;
						rep0 = (2 | (value & 1)) << n;
						if (n < 6) p3 = probs + 687 + rep0 - value;
						else {
							do {
								RC_NORMALIZE
								i >>= 1; range >>= 1;
								if (code >= range)
									code -= range, rep0 += i;
							} while (i != 16);
							p3 = probs + 802;
						}
						n = value = 1;
						do {
							p1 = p3 + value;
							value <<= 1;
							RC_BIT(p1) if (!bit0) value++, rep0 |= n;
							n <<= 1;
						} while (value < i);
					}
					rep0++;
				}
			}
			if (!rep0) break;
			if (rep0 > dict_size || rep0 > out ||
					max_size - out < len) return 4;
			do {
				value = dict[(pos < rep0 ? dict_size : 0) + pos - rep0];
copy:
				out++; dict[pos++] = value;
				if (pos == dict_size) {
					if (fwrite(dict, 1, pos, stdout) != pos) return 5;
					pos = 0;
				}
			} while (--len);
		}
	}
	if (pos && fwrite(dict, 1, pos, stdout) != pos) return 5;
	RC_NORMALIZE
	DBG_LOG("Code = 0x%08x\n", code);
	return code ? 4 : 0;
}

