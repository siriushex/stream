# 1 "lib/sha1.c"
# 1 "<command-line>"
# 1 "lib/sha1.c"
# 44 "lib/sha1.c"
# 1 "/usr/include/string.h" 1 3 4
# 27 "/usr/include/string.h" 3 4
# 1 "/usr/include/features.h" 1 3 4
# 361 "/usr/include/features.h" 3 4
# 1 "/usr/include/sys/cdefs.h" 1 3 4
# 373 "/usr/include/sys/cdefs.h" 3 4
# 1 "/usr/include/bits/wordsize.h" 1 3 4
# 374 "/usr/include/sys/cdefs.h" 2 3 4
# 362 "/usr/include/features.h" 2 3 4
# 385 "/usr/include/features.h" 3 4
# 1 "/usr/include/gnu/stubs.h" 1 3 4



# 1 "/usr/include/bits/wordsize.h" 1 3 4
# 5 "/usr/include/gnu/stubs.h" 2 3 4




# 1 "/usr/include/gnu/stubs-64.h" 1 3 4
# 10 "/usr/include/gnu/stubs.h" 2 3 4
# 386 "/usr/include/features.h" 2 3 4
# 28 "/usr/include/string.h" 2 3 4






# 1 "/opt/rh/devtoolset-2/root/usr/lib/gcc/x86_64-redhat-linux/4.8.2/include/stddef.h" 1 3 4
# 212 "/opt/rh/devtoolset-2/root/usr/lib/gcc/x86_64-redhat-linux/4.8.2/include/stddef.h" 3 4
typedef long unsigned int size_t;
# 35 "/usr/include/string.h" 2 3 4









extern void *memcpy (void *__restrict __dest,
       __const void *__restrict __src, size_t __n)
     __attribute__ ((__nothrow__)) __attribute__ ((__nonnull__ (1, 2)));


extern void *memmove (void *__dest, __const void *__src, size_t __n)
     __attribute__ ((__nothrow__)) __attribute__ ((__nonnull__ (1, 2)));






extern void *memccpy (void *__restrict __dest, __const void *__restrict __src,
        int __c, size_t __n)
     __attribute__ ((__nothrow__)) __attribute__ ((__nonnull__ (1, 2)));





extern void *memset (void *__s, int __c, size_t __n) __attribute__ ((__nothrow__)) __attribute__ ((__nonnull__ (1)));


extern int memcmp (__const void *__s1, __const void *__s2, size_t __n)
     __attribute__ ((__nothrow__)) __attribute__ ((__pure__)) __attribute__ ((__nonnull__ (1, 2)));
# 95 "/usr/include/string.h" 3 4
extern void *memchr (__const void *__s, int __c, size_t __n)
      __attribute__ ((__nothrow__)) __attribute__ ((__pure__)) __attribute__ ((__nonnull__ (1)));


# 126 "/usr/include/string.h" 3 4


extern char *strcpy (char *__restrict __dest, __const char *__restrict __src)
     __attribute__ ((__nothrow__)) __attribute__ ((__nonnull__ (1, 2)));

extern char *strncpy (char *__restrict __dest,
        __const char *__restrict __src, size_t __n)
     __attribute__ ((__nothrow__)) __attribute__ ((__nonnull__ (1, 2)));


extern char *strcat (char *__restrict __dest, __const char *__restrict __src)
     __attribute__ ((__nothrow__)) __attribute__ ((__nonnull__ (1, 2)));

extern char *strncat (char *__restrict __dest, __const char *__restrict __src,
        size_t __n) __attribute__ ((__nothrow__)) __attribute__ ((__nonnull__ (1, 2)));


extern int strcmp (__const char *__s1, __const char *__s2)
     __attribute__ ((__nothrow__)) __attribute__ ((__pure__)) __attribute__ ((__nonnull__ (1, 2)));

extern int strncmp (__const char *__s1, __const char *__s2, size_t __n)
     __attribute__ ((__nothrow__)) __attribute__ ((__pure__)) __attribute__ ((__nonnull__ (1, 2)));


extern int strcoll (__const char *__s1, __const char *__s2)
     __attribute__ ((__nothrow__)) __attribute__ ((__pure__)) __attribute__ ((__nonnull__ (1, 2)));

extern size_t strxfrm (char *__restrict __dest,
         __const char *__restrict __src, size_t __n)
     __attribute__ ((__nothrow__)) __attribute__ ((__nonnull__ (2)));






# 1 "/usr/include/xlocale.h" 1 3 4
# 28 "/usr/include/xlocale.h" 3 4
typedef struct __locale_struct
{

  struct __locale_data *__locales[13];


  const unsigned short int *__ctype_b;
  const int *__ctype_tolower;
  const int *__ctype_toupper;


  const char *__names[13];
} *__locale_t;


typedef __locale_t locale_t;
# 163 "/usr/include/string.h" 2 3 4


extern int strcoll_l (__const char *__s1, __const char *__s2, __locale_t __l)
     __attribute__ ((__nothrow__)) __attribute__ ((__pure__)) __attribute__ ((__nonnull__ (1, 2, 3)));

extern size_t strxfrm_l (char *__dest, __const char *__src, size_t __n,
    __locale_t __l) __attribute__ ((__nothrow__)) __attribute__ ((__nonnull__ (2, 4)));





extern char *strdup (__const char *__s)
     __attribute__ ((__nothrow__)) __attribute__ ((__malloc__)) __attribute__ ((__nonnull__ (1)));






extern char *strndup (__const char *__string, size_t __n)
     __attribute__ ((__nothrow__)) __attribute__ ((__malloc__)) __attribute__ ((__nonnull__ (1)));
# 210 "/usr/include/string.h" 3 4

# 235 "/usr/include/string.h" 3 4
extern char *strchr (__const char *__s, int __c)
     __attribute__ ((__nothrow__)) __attribute__ ((__pure__)) __attribute__ ((__nonnull__ (1)));
# 262 "/usr/include/string.h" 3 4
extern char *strrchr (__const char *__s, int __c)
     __attribute__ ((__nothrow__)) __attribute__ ((__pure__)) __attribute__ ((__nonnull__ (1)));


# 281 "/usr/include/string.h" 3 4



extern size_t strcspn (__const char *__s, __const char *__reject)
     __attribute__ ((__nothrow__)) __attribute__ ((__pure__)) __attribute__ ((__nonnull__ (1, 2)));


extern size_t strspn (__const char *__s, __const char *__accept)
     __attribute__ ((__nothrow__)) __attribute__ ((__pure__)) __attribute__ ((__nonnull__ (1, 2)));
# 314 "/usr/include/string.h" 3 4
extern char *strpbrk (__const char *__s, __const char *__accept)
     __attribute__ ((__nothrow__)) __attribute__ ((__pure__)) __attribute__ ((__nonnull__ (1, 2)));
# 342 "/usr/include/string.h" 3 4
extern char *strstr (__const char *__haystack, __const char *__needle)
     __attribute__ ((__nothrow__)) __attribute__ ((__pure__)) __attribute__ ((__nonnull__ (1, 2)));




extern char *strtok (char *__restrict __s, __const char *__restrict __delim)
     __attribute__ ((__nothrow__)) __attribute__ ((__nonnull__ (2)));




extern char *__strtok_r (char *__restrict __s,
    __const char *__restrict __delim,
    char **__restrict __save_ptr)
     __attribute__ ((__nothrow__)) __attribute__ ((__nonnull__ (2, 3)));

extern char *strtok_r (char *__restrict __s, __const char *__restrict __delim,
         char **__restrict __save_ptr)
     __attribute__ ((__nothrow__)) __attribute__ ((__nonnull__ (2, 3)));
# 397 "/usr/include/string.h" 3 4


extern size_t strlen (__const char *__s)
     __attribute__ ((__nothrow__)) __attribute__ ((__pure__)) __attribute__ ((__nonnull__ (1)));





extern size_t strnlen (__const char *__string, size_t __maxlen)
     __attribute__ ((__nothrow__)) __attribute__ ((__pure__)) __attribute__ ((__nonnull__ (1)));





extern char *strerror (int __errnum) __attribute__ ((__nothrow__));

# 427 "/usr/include/string.h" 3 4
extern int strerror_r (int __errnum, char *__buf, size_t __buflen) __asm__ ("" "__xpg_strerror_r") __attribute__ ((__nothrow__))

                        __attribute__ ((__nonnull__ (2)));
# 445 "/usr/include/string.h" 3 4
extern char *strerror_l (int __errnum, __locale_t __l) __attribute__ ((__nothrow__));





extern void __bzero (void *__s, size_t __n) __attribute__ ((__nothrow__)) __attribute__ ((__nonnull__ (1)));



extern void bcopy (__const void *__src, void *__dest, size_t __n)
     __attribute__ ((__nothrow__)) __attribute__ ((__nonnull__ (1, 2)));


extern void bzero (void *__s, size_t __n) __attribute__ ((__nothrow__)) __attribute__ ((__nonnull__ (1)));


extern int bcmp (__const void *__s1, __const void *__s2, size_t __n)
     __attribute__ ((__nothrow__)) __attribute__ ((__pure__)) __attribute__ ((__nonnull__ (1, 2)));
# 489 "/usr/include/string.h" 3 4
extern char *index (__const char *__s, int __c)
     __attribute__ ((__nothrow__)) __attribute__ ((__pure__)) __attribute__ ((__nonnull__ (1)));
# 517 "/usr/include/string.h" 3 4
extern char *rindex (__const char *__s, int __c)
     __attribute__ ((__nothrow__)) __attribute__ ((__pure__)) __attribute__ ((__nonnull__ (1)));




extern int ffs (int __i) __attribute__ ((__nothrow__)) __attribute__ ((__const__));
# 536 "/usr/include/string.h" 3 4
extern int strcasecmp (__const char *__s1, __const char *__s2)
     __attribute__ ((__nothrow__)) __attribute__ ((__pure__)) __attribute__ ((__nonnull__ (1, 2)));


extern int strncasecmp (__const char *__s1, __const char *__s2, size_t __n)
     __attribute__ ((__nothrow__)) __attribute__ ((__pure__)) __attribute__ ((__nonnull__ (1, 2)));
# 559 "/usr/include/string.h" 3 4
extern char *strsep (char **__restrict __stringp,
       __const char *__restrict __delim)
     __attribute__ ((__nothrow__)) __attribute__ ((__nonnull__ (1, 2)));




extern char *strsignal (int __sig) __attribute__ ((__nothrow__));


extern char *__stpcpy (char *__restrict __dest, __const char *__restrict __src)
     __attribute__ ((__nothrow__)) __attribute__ ((__nonnull__ (1, 2)));
extern char *stpcpy (char *__restrict __dest, __const char *__restrict __src)
     __attribute__ ((__nothrow__)) __attribute__ ((__nonnull__ (1, 2)));



extern char *__stpncpy (char *__restrict __dest,
   __const char *__restrict __src, size_t __n)
     __attribute__ ((__nothrow__)) __attribute__ ((__nonnull__ (1, 2)));
extern char *stpncpy (char *__restrict __dest,
        __const char *__restrict __src, size_t __n)
     __attribute__ ((__nothrow__)) __attribute__ ((__nonnull__ (1, 2)));
# 646 "/usr/include/string.h" 3 4

# 45 "lib/sha1.c" 2

# 1 "lib/sha1.h" 1
# 47 "lib/sha1.h"
typedef struct
{
 unsigned int state[5];
 unsigned int bytesHandled;
 unsigned char buffer[64];
}
SHA_CTXL;

extern void SHA1L_Init (SHA_CTXL *context);
extern void SHA1L_Update (SHA_CTXL *context, const unsigned char *input, unsigned long input_bytes);
extern void SHA1L_Final (unsigned char digest[20], SHA_CTXL *context);
# 47 "lib/sha1.c" 2


static void unaligned_write32_be (unsigned char *dst, unsigned int value)
{
 *dst++ = value >> 24;
 *dst++ = value >> 16;
 *dst++ = value >> 8;
 *dst++ = value >> 0;
}

void sha1_compress(unsigned int *state, const unsigned char *block)
{
# 77 "lib/sha1.c"
    unsigned int a = state[0];
    unsigned int b = state[1];
    unsigned int c = state[2];
    unsigned int d = state[3];
    unsigned int e = state[4];
    unsigned int schedule[16];
    unsigned int temp;

    schedule[0] = (unsigned int)block[0 * 4 + 0] << 24 | (unsigned int)block[0 * 4 + 1] << 16 | (unsigned int)block[0 * 4 + 2] << 8 | (unsigned int)block[0 * 4 + 3]; e += (a << 5 | a >> 27) + ((b & c) | (~b & d)) + (unsigned int)(0x5A827999) + schedule[0 & 0xF]; b = b << 30 | b >> 2;
    schedule[1] = (unsigned int)block[1 * 4 + 0] << 24 | (unsigned int)block[1 * 4 + 1] << 16 | (unsigned int)block[1 * 4 + 2] << 8 | (unsigned int)block[1 * 4 + 3]; d += (e << 5 | e >> 27) + ((a & b) | (~a & c)) + (unsigned int)(0x5A827999) + schedule[1 & 0xF]; a = a << 30 | a >> 2;
    schedule[2] = (unsigned int)block[2 * 4 + 0] << 24 | (unsigned int)block[2 * 4 + 1] << 16 | (unsigned int)block[2 * 4 + 2] << 8 | (unsigned int)block[2 * 4 + 3]; c += (d << 5 | d >> 27) + ((e & a) | (~e & b)) + (unsigned int)(0x5A827999) + schedule[2 & 0xF]; e = e << 30 | e >> 2;
    schedule[3] = (unsigned int)block[3 * 4 + 0] << 24 | (unsigned int)block[3 * 4 + 1] << 16 | (unsigned int)block[3 * 4 + 2] << 8 | (unsigned int)block[3 * 4 + 3]; b += (c << 5 | c >> 27) + ((d & e) | (~d & a)) + (unsigned int)(0x5A827999) + schedule[3 & 0xF]; d = d << 30 | d >> 2;
    schedule[4] = (unsigned int)block[4 * 4 + 0] << 24 | (unsigned int)block[4 * 4 + 1] << 16 | (unsigned int)block[4 * 4 + 2] << 8 | (unsigned int)block[4 * 4 + 3]; a += (b << 5 | b >> 27) + ((c & d) | (~c & e)) + (unsigned int)(0x5A827999) + schedule[4 & 0xF]; c = c << 30 | c >> 2;
    schedule[5] = (unsigned int)block[5 * 4 + 0] << 24 | (unsigned int)block[5 * 4 + 1] << 16 | (unsigned int)block[5 * 4 + 2] << 8 | (unsigned int)block[5 * 4 + 3]; e += (a << 5 | a >> 27) + ((b & c) | (~b & d)) + (unsigned int)(0x5A827999) + schedule[5 & 0xF]; b = b << 30 | b >> 2;
    schedule[6] = (unsigned int)block[6 * 4 + 0] << 24 | (unsigned int)block[6 * 4 + 1] << 16 | (unsigned int)block[6 * 4 + 2] << 8 | (unsigned int)block[6 * 4 + 3]; d += (e << 5 | e >> 27) + ((a & b) | (~a & c)) + (unsigned int)(0x5A827999) + schedule[6 & 0xF]; a = a << 30 | a >> 2;
    schedule[7] = (unsigned int)block[7 * 4 + 0] << 24 | (unsigned int)block[7 * 4 + 1] << 16 | (unsigned int)block[7 * 4 + 2] << 8 | (unsigned int)block[7 * 4 + 3]; c += (d << 5 | d >> 27) + ((e & a) | (~e & b)) + (unsigned int)(0x5A827999) + schedule[7 & 0xF]; e = e << 30 | e >> 2;
    schedule[8] = (unsigned int)block[8 * 4 + 0] << 24 | (unsigned int)block[8 * 4 + 1] << 16 | (unsigned int)block[8 * 4 + 2] << 8 | (unsigned int)block[8 * 4 + 3]; b += (c << 5 | c >> 27) + ((d & e) | (~d & a)) + (unsigned int)(0x5A827999) + schedule[8 & 0xF]; d = d << 30 | d >> 2;
    schedule[9] = (unsigned int)block[9 * 4 + 0] << 24 | (unsigned int)block[9 * 4 + 1] << 16 | (unsigned int)block[9 * 4 + 2] << 8 | (unsigned int)block[9 * 4 + 3]; a += (b << 5 | b >> 27) + ((c & d) | (~c & e)) + (unsigned int)(0x5A827999) + schedule[9 & 0xF]; c = c << 30 | c >> 2;
    schedule[10] = (unsigned int)block[10 * 4 + 0] << 24 | (unsigned int)block[10 * 4 + 1] << 16 | (unsigned int)block[10 * 4 + 2] << 8 | (unsigned int)block[10 * 4 + 3]; e += (a << 5 | a >> 27) + ((b & c) | (~b & d)) + (unsigned int)(0x5A827999) + schedule[10 & 0xF]; b = b << 30 | b >> 2;
    schedule[11] = (unsigned int)block[11 * 4 + 0] << 24 | (unsigned int)block[11 * 4 + 1] << 16 | (unsigned int)block[11 * 4 + 2] << 8 | (unsigned int)block[11 * 4 + 3]; d += (e << 5 | e >> 27) + ((a & b) | (~a & c)) + (unsigned int)(0x5A827999) + schedule[11 & 0xF]; a = a << 30 | a >> 2;
    schedule[12] = (unsigned int)block[12 * 4 + 0] << 24 | (unsigned int)block[12 * 4 + 1] << 16 | (unsigned int)block[12 * 4 + 2] << 8 | (unsigned int)block[12 * 4 + 3]; c += (d << 5 | d >> 27) + ((e & a) | (~e & b)) + (unsigned int)(0x5A827999) + schedule[12 & 0xF]; e = e << 30 | e >> 2;
    schedule[13] = (unsigned int)block[13 * 4 + 0] << 24 | (unsigned int)block[13 * 4 + 1] << 16 | (unsigned int)block[13 * 4 + 2] << 8 | (unsigned int)block[13 * 4 + 3]; b += (c << 5 | c >> 27) + ((d & e) | (~d & a)) + (unsigned int)(0x5A827999) + schedule[13 & 0xF]; d = d << 30 | d >> 2;
    schedule[14] = (unsigned int)block[14 * 4 + 0] << 24 | (unsigned int)block[14 * 4 + 1] << 16 | (unsigned int)block[14 * 4 + 2] << 8 | (unsigned int)block[14 * 4 + 3]; a += (b << 5 | b >> 27) + ((c & d) | (~c & e)) + (unsigned int)(0x5A827999) + schedule[14 & 0xF]; c = c << 30 | c >> 2;
    schedule[15] = (unsigned int)block[15 * 4 + 0] << 24 | (unsigned int)block[15 * 4 + 1] << 16 | (unsigned int)block[15 * 4 + 2] << 8 | (unsigned int)block[15 * 4 + 3]; e += (a << 5 | a >> 27) + ((b & c) | (~b & d)) + (unsigned int)(0x5A827999) + schedule[15 & 0xF]; b = b << 30 | b >> 2;
    temp = schedule[(16 - 3) & 0xF] ^ schedule[(16 - 8) & 0xF] ^ schedule[(16 - 14) & 0xF] ^ schedule[(16 - 16) & 0xF]; schedule[16 & 0xF] = temp << 1 | temp >> 31; d += (e << 5 | e >> 27) + ((a & b) | (~a & c)) + (unsigned int)(0x5A827999) + schedule[16 & 0xF]; a = a << 30 | a >> 2;
    temp = schedule[(17 - 3) & 0xF] ^ schedule[(17 - 8) & 0xF] ^ schedule[(17 - 14) & 0xF] ^ schedule[(17 - 16) & 0xF]; schedule[17 & 0xF] = temp << 1 | temp >> 31; c += (d << 5 | d >> 27) + ((e & a) | (~e & b)) + (unsigned int)(0x5A827999) + schedule[17 & 0xF]; e = e << 30 | e >> 2;
    temp = schedule[(18 - 3) & 0xF] ^ schedule[(18 - 8) & 0xF] ^ schedule[(18 - 14) & 0xF] ^ schedule[(18 - 16) & 0xF]; schedule[18 & 0xF] = temp << 1 | temp >> 31; b += (c << 5 | c >> 27) + ((d & e) | (~d & a)) + (unsigned int)(0x5A827999) + schedule[18 & 0xF]; d = d << 30 | d >> 2;
    temp = schedule[(19 - 3) & 0xF] ^ schedule[(19 - 8) & 0xF] ^ schedule[(19 - 14) & 0xF] ^ schedule[(19 - 16) & 0xF]; schedule[19 & 0xF] = temp << 1 | temp >> 31; a += (b << 5 | b >> 27) + ((c & d) | (~c & e)) + (unsigned int)(0x5A827999) + schedule[19 & 0xF]; c = c << 30 | c >> 2;
    temp = schedule[(20 - 3) & 0xF] ^ schedule[(20 - 8) & 0xF] ^ schedule[(20 - 14) & 0xF] ^ schedule[(20 - 16) & 0xF]; schedule[20 & 0xF] = temp << 1 | temp >> 31; e += (a << 5 | a >> 27) + (b ^ c ^ d) + (unsigned int)(0x6ED9EBA1) + schedule[20 & 0xF]; b = b << 30 | b >> 2;
    temp = schedule[(21 - 3) & 0xF] ^ schedule[(21 - 8) & 0xF] ^ schedule[(21 - 14) & 0xF] ^ schedule[(21 - 16) & 0xF]; schedule[21 & 0xF] = temp << 1 | temp >> 31; d += (e << 5 | e >> 27) + (a ^ b ^ c) + (unsigned int)(0x6ED9EBA1) + schedule[21 & 0xF]; a = a << 30 | a >> 2;
    temp = schedule[(22 - 3) & 0xF] ^ schedule[(22 - 8) & 0xF] ^ schedule[(22 - 14) & 0xF] ^ schedule[(22 - 16) & 0xF]; schedule[22 & 0xF] = temp << 1 | temp >> 31; c += (d << 5 | d >> 27) + (e ^ a ^ b) + (unsigned int)(0x6ED9EBA1) + schedule[22 & 0xF]; e = e << 30 | e >> 2;
    temp = schedule[(23 - 3) & 0xF] ^ schedule[(23 - 8) & 0xF] ^ schedule[(23 - 14) & 0xF] ^ schedule[(23 - 16) & 0xF]; schedule[23 & 0xF] = temp << 1 | temp >> 31; b += (c << 5 | c >> 27) + (d ^ e ^ a) + (unsigned int)(0x6ED9EBA1) + schedule[23 & 0xF]; d = d << 30 | d >> 2;
    temp = schedule[(24 - 3) & 0xF] ^ schedule[(24 - 8) & 0xF] ^ schedule[(24 - 14) & 0xF] ^ schedule[(24 - 16) & 0xF]; schedule[24 & 0xF] = temp << 1 | temp >> 31; a += (b << 5 | b >> 27) + (c ^ d ^ e) + (unsigned int)(0x6ED9EBA1) + schedule[24 & 0xF]; c = c << 30 | c >> 2;
    temp = schedule[(25 - 3) & 0xF] ^ schedule[(25 - 8) & 0xF] ^ schedule[(25 - 14) & 0xF] ^ schedule[(25 - 16) & 0xF]; schedule[25 & 0xF] = temp << 1 | temp >> 31; e += (a << 5 | a >> 27) + (b ^ c ^ d) + (unsigned int)(0x6ED9EBA1) + schedule[25 & 0xF]; b = b << 30 | b >> 2;
    temp = schedule[(26 - 3) & 0xF] ^ schedule[(26 - 8) & 0xF] ^ schedule[(26 - 14) & 0xF] ^ schedule[(26 - 16) & 0xF]; schedule[26 & 0xF] = temp << 1 | temp >> 31; d += (e << 5 | e >> 27) + (a ^ b ^ c) + (unsigned int)(0x6ED9EBA1) + schedule[26 & 0xF]; a = a << 30 | a >> 2;
    temp = schedule[(27 - 3) & 0xF] ^ schedule[(27 - 8) & 0xF] ^ schedule[(27 - 14) & 0xF] ^ schedule[(27 - 16) & 0xF]; schedule[27 & 0xF] = temp << 1 | temp >> 31; c += (d << 5 | d >> 27) + (e ^ a ^ b) + (unsigned int)(0x6ED9EBA1) + schedule[27 & 0xF]; e = e << 30 | e >> 2;
    temp = schedule[(28 - 3) & 0xF] ^ schedule[(28 - 8) & 0xF] ^ schedule[(28 - 14) & 0xF] ^ schedule[(28 - 16) & 0xF]; schedule[28 & 0xF] = temp << 1 | temp >> 31; b += (c << 5 | c >> 27) + (d ^ e ^ a) + (unsigned int)(0x6ED9EBA1) + schedule[28 & 0xF]; d = d << 30 | d >> 2;
    temp = schedule[(29 - 3) & 0xF] ^ schedule[(29 - 8) & 0xF] ^ schedule[(29 - 14) & 0xF] ^ schedule[(29 - 16) & 0xF]; schedule[29 & 0xF] = temp << 1 | temp >> 31; a += (b << 5 | b >> 27) + (c ^ d ^ e) + (unsigned int)(0x6ED9EBA1) + schedule[29 & 0xF]; c = c << 30 | c >> 2;
    temp = schedule[(30 - 3) & 0xF] ^ schedule[(30 - 8) & 0xF] ^ schedule[(30 - 14) & 0xF] ^ schedule[(30 - 16) & 0xF]; schedule[30 & 0xF] = temp << 1 | temp >> 31; e += (a << 5 | a >> 27) + (b ^ c ^ d) + (unsigned int)(0x6ED9EBA1) + schedule[30 & 0xF]; b = b << 30 | b >> 2;
    temp = schedule[(31 - 3) & 0xF] ^ schedule[(31 - 8) & 0xF] ^ schedule[(31 - 14) & 0xF] ^ schedule[(31 - 16) & 0xF]; schedule[31 & 0xF] = temp << 1 | temp >> 31; d += (e << 5 | e >> 27) + (a ^ b ^ c) + (unsigned int)(0x6ED9EBA1) + schedule[31 & 0xF]; a = a << 30 | a >> 2;
    temp = schedule[(32 - 3) & 0xF] ^ schedule[(32 - 8) & 0xF] ^ schedule[(32 - 14) & 0xF] ^ schedule[(32 - 16) & 0xF]; schedule[32 & 0xF] = temp << 1 | temp >> 31; c += (d << 5 | d >> 27) + (e ^ a ^ b) + (unsigned int)(0x6ED9EBA1) + schedule[32 & 0xF]; e = e << 30 | e >> 2;
    temp = schedule[(33 - 3) & 0xF] ^ schedule[(33 - 8) & 0xF] ^ schedule[(33 - 14) & 0xF] ^ schedule[(33 - 16) & 0xF]; schedule[33 & 0xF] = temp << 1 | temp >> 31; b += (c << 5 | c >> 27) + (d ^ e ^ a) + (unsigned int)(0x6ED9EBA1) + schedule[33 & 0xF]; d = d << 30 | d >> 2;
    temp = schedule[(34 - 3) & 0xF] ^ schedule[(34 - 8) & 0xF] ^ schedule[(34 - 14) & 0xF] ^ schedule[(34 - 16) & 0xF]; schedule[34 & 0xF] = temp << 1 | temp >> 31; a += (b << 5 | b >> 27) + (c ^ d ^ e) + (unsigned int)(0x6ED9EBA1) + schedule[34 & 0xF]; c = c << 30 | c >> 2;
    temp = schedule[(35 - 3) & 0xF] ^ schedule[(35 - 8) & 0xF] ^ schedule[(35 - 14) & 0xF] ^ schedule[(35 - 16) & 0xF]; schedule[35 & 0xF] = temp << 1 | temp >> 31; e += (a << 5 | a >> 27) + (b ^ c ^ d) + (unsigned int)(0x6ED9EBA1) + schedule[35 & 0xF]; b = b << 30 | b >> 2;
    temp = schedule[(36 - 3) & 0xF] ^ schedule[(36 - 8) & 0xF] ^ schedule[(36 - 14) & 0xF] ^ schedule[(36 - 16) & 0xF]; schedule[36 & 0xF] = temp << 1 | temp >> 31; d += (e << 5 | e >> 27) + (a ^ b ^ c) + (unsigned int)(0x6ED9EBA1) + schedule[36 & 0xF]; a = a << 30 | a >> 2;
    temp = schedule[(37 - 3) & 0xF] ^ schedule[(37 - 8) & 0xF] ^ schedule[(37 - 14) & 0xF] ^ schedule[(37 - 16) & 0xF]; schedule[37 & 0xF] = temp << 1 | temp >> 31; c += (d << 5 | d >> 27) + (e ^ a ^ b) + (unsigned int)(0x6ED9EBA1) + schedule[37 & 0xF]; e = e << 30 | e >> 2;
    temp = schedule[(38 - 3) & 0xF] ^ schedule[(38 - 8) & 0xF] ^ schedule[(38 - 14) & 0xF] ^ schedule[(38 - 16) & 0xF]; schedule[38 & 0xF] = temp << 1 | temp >> 31; b += (c << 5 | c >> 27) + (d ^ e ^ a) + (unsigned int)(0x6ED9EBA1) + schedule[38 & 0xF]; d = d << 30 | d >> 2;
    temp = schedule[(39 - 3) & 0xF] ^ schedule[(39 - 8) & 0xF] ^ schedule[(39 - 14) & 0xF] ^ schedule[(39 - 16) & 0xF]; schedule[39 & 0xF] = temp << 1 | temp >> 31; a += (b << 5 | b >> 27) + (c ^ d ^ e) + (unsigned int)(0x6ED9EBA1) + schedule[39 & 0xF]; c = c << 30 | c >> 2;
    temp = schedule[(40 - 3) & 0xF] ^ schedule[(40 - 8) & 0xF] ^ schedule[(40 - 14) & 0xF] ^ schedule[(40 - 16) & 0xF]; schedule[40 & 0xF] = temp << 1 | temp >> 31; e += (a << 5 | a >> 27) + ((b & c) ^ (b & d) ^ (c & d)) + (unsigned int)(0x8F1BBCDC) + schedule[40 & 0xF]; b = b << 30 | b >> 2;
    temp = schedule[(41 - 3) & 0xF] ^ schedule[(41 - 8) & 0xF] ^ schedule[(41 - 14) & 0xF] ^ schedule[(41 - 16) & 0xF]; schedule[41 & 0xF] = temp << 1 | temp >> 31; d += (e << 5 | e >> 27) + ((a & b) ^ (a & c) ^ (b & c)) + (unsigned int)(0x8F1BBCDC) + schedule[41 & 0xF]; a = a << 30 | a >> 2;
    temp = schedule[(42 - 3) & 0xF] ^ schedule[(42 - 8) & 0xF] ^ schedule[(42 - 14) & 0xF] ^ schedule[(42 - 16) & 0xF]; schedule[42 & 0xF] = temp << 1 | temp >> 31; c += (d << 5 | d >> 27) + ((e & a) ^ (e & b) ^ (a & b)) + (unsigned int)(0x8F1BBCDC) + schedule[42 & 0xF]; e = e << 30 | e >> 2;
    temp = schedule[(43 - 3) & 0xF] ^ schedule[(43 - 8) & 0xF] ^ schedule[(43 - 14) & 0xF] ^ schedule[(43 - 16) & 0xF]; schedule[43 & 0xF] = temp << 1 | temp >> 31; b += (c << 5 | c >> 27) + ((d & e) ^ (d & a) ^ (e & a)) + (unsigned int)(0x8F1BBCDC) + schedule[43 & 0xF]; d = d << 30 | d >> 2;
    temp = schedule[(44 - 3) & 0xF] ^ schedule[(44 - 8) & 0xF] ^ schedule[(44 - 14) & 0xF] ^ schedule[(44 - 16) & 0xF]; schedule[44 & 0xF] = temp << 1 | temp >> 31; a += (b << 5 | b >> 27) + ((c & d) ^ (c & e) ^ (d & e)) + (unsigned int)(0x8F1BBCDC) + schedule[44 & 0xF]; c = c << 30 | c >> 2;
    temp = schedule[(45 - 3) & 0xF] ^ schedule[(45 - 8) & 0xF] ^ schedule[(45 - 14) & 0xF] ^ schedule[(45 - 16) & 0xF]; schedule[45 & 0xF] = temp << 1 | temp >> 31; e += (a << 5 | a >> 27) + ((b & c) ^ (b & d) ^ (c & d)) + (unsigned int)(0x8F1BBCDC) + schedule[45 & 0xF]; b = b << 30 | b >> 2;
    temp = schedule[(46 - 3) & 0xF] ^ schedule[(46 - 8) & 0xF] ^ schedule[(46 - 14) & 0xF] ^ schedule[(46 - 16) & 0xF]; schedule[46 & 0xF] = temp << 1 | temp >> 31; d += (e << 5 | e >> 27) + ((a & b) ^ (a & c) ^ (b & c)) + (unsigned int)(0x8F1BBCDC) + schedule[46 & 0xF]; a = a << 30 | a >> 2;
    temp = schedule[(47 - 3) & 0xF] ^ schedule[(47 - 8) & 0xF] ^ schedule[(47 - 14) & 0xF] ^ schedule[(47 - 16) & 0xF]; schedule[47 & 0xF] = temp << 1 | temp >> 31; c += (d << 5 | d >> 27) + ((e & a) ^ (e & b) ^ (a & b)) + (unsigned int)(0x8F1BBCDC) + schedule[47 & 0xF]; e = e << 30 | e >> 2;
    temp = schedule[(48 - 3) & 0xF] ^ schedule[(48 - 8) & 0xF] ^ schedule[(48 - 14) & 0xF] ^ schedule[(48 - 16) & 0xF]; schedule[48 & 0xF] = temp << 1 | temp >> 31; b += (c << 5 | c >> 27) + ((d & e) ^ (d & a) ^ (e & a)) + (unsigned int)(0x8F1BBCDC) + schedule[48 & 0xF]; d = d << 30 | d >> 2;
    temp = schedule[(49 - 3) & 0xF] ^ schedule[(49 - 8) & 0xF] ^ schedule[(49 - 14) & 0xF] ^ schedule[(49 - 16) & 0xF]; schedule[49 & 0xF] = temp << 1 | temp >> 31; a += (b << 5 | b >> 27) + ((c & d) ^ (c & e) ^ (d & e)) + (unsigned int)(0x8F1BBCDC) + schedule[49 & 0xF]; c = c << 30 | c >> 2;
    temp = schedule[(50 - 3) & 0xF] ^ schedule[(50 - 8) & 0xF] ^ schedule[(50 - 14) & 0xF] ^ schedule[(50 - 16) & 0xF]; schedule[50 & 0xF] = temp << 1 | temp >> 31; e += (a << 5 | a >> 27) + ((b & c) ^ (b & d) ^ (c & d)) + (unsigned int)(0x8F1BBCDC) + schedule[50 & 0xF]; b = b << 30 | b >> 2;
    temp = schedule[(51 - 3) & 0xF] ^ schedule[(51 - 8) & 0xF] ^ schedule[(51 - 14) & 0xF] ^ schedule[(51 - 16) & 0xF]; schedule[51 & 0xF] = temp << 1 | temp >> 31; d += (e << 5 | e >> 27) + ((a & b) ^ (a & c) ^ (b & c)) + (unsigned int)(0x8F1BBCDC) + schedule[51 & 0xF]; a = a << 30 | a >> 2;
    temp = schedule[(52 - 3) & 0xF] ^ schedule[(52 - 8) & 0xF] ^ schedule[(52 - 14) & 0xF] ^ schedule[(52 - 16) & 0xF]; schedule[52 & 0xF] = temp << 1 | temp >> 31; c += (d << 5 | d >> 27) + ((e & a) ^ (e & b) ^ (a & b)) + (unsigned int)(0x8F1BBCDC) + schedule[52 & 0xF]; e = e << 30 | e >> 2;
    temp = schedule[(53 - 3) & 0xF] ^ schedule[(53 - 8) & 0xF] ^ schedule[(53 - 14) & 0xF] ^ schedule[(53 - 16) & 0xF]; schedule[53 & 0xF] = temp << 1 | temp >> 31; b += (c << 5 | c >> 27) + ((d & e) ^ (d & a) ^ (e & a)) + (unsigned int)(0x8F1BBCDC) + schedule[53 & 0xF]; d = d << 30 | d >> 2;
    temp = schedule[(54 - 3) & 0xF] ^ schedule[(54 - 8) & 0xF] ^ schedule[(54 - 14) & 0xF] ^ schedule[(54 - 16) & 0xF]; schedule[54 & 0xF] = temp << 1 | temp >> 31; a += (b << 5 | b >> 27) + ((c & d) ^ (c & e) ^ (d & e)) + (unsigned int)(0x8F1BBCDC) + schedule[54 & 0xF]; c = c << 30 | c >> 2;
    temp = schedule[(55 - 3) & 0xF] ^ schedule[(55 - 8) & 0xF] ^ schedule[(55 - 14) & 0xF] ^ schedule[(55 - 16) & 0xF]; schedule[55 & 0xF] = temp << 1 | temp >> 31; e += (a << 5 | a >> 27) + ((b & c) ^ (b & d) ^ (c & d)) + (unsigned int)(0x8F1BBCDC) + schedule[55 & 0xF]; b = b << 30 | b >> 2;
    temp = schedule[(56 - 3) & 0xF] ^ schedule[(56 - 8) & 0xF] ^ schedule[(56 - 14) & 0xF] ^ schedule[(56 - 16) & 0xF]; schedule[56 & 0xF] = temp << 1 | temp >> 31; d += (e << 5 | e >> 27) + ((a & b) ^ (a & c) ^ (b & c)) + (unsigned int)(0x8F1BBCDC) + schedule[56 & 0xF]; a = a << 30 | a >> 2;
    temp = schedule[(57 - 3) & 0xF] ^ schedule[(57 - 8) & 0xF] ^ schedule[(57 - 14) & 0xF] ^ schedule[(57 - 16) & 0xF]; schedule[57 & 0xF] = temp << 1 | temp >> 31; c += (d << 5 | d >> 27) + ((e & a) ^ (e & b) ^ (a & b)) + (unsigned int)(0x8F1BBCDC) + schedule[57 & 0xF]; e = e << 30 | e >> 2;
    temp = schedule[(58 - 3) & 0xF] ^ schedule[(58 - 8) & 0xF] ^ schedule[(58 - 14) & 0xF] ^ schedule[(58 - 16) & 0xF]; schedule[58 & 0xF] = temp << 1 | temp >> 31; b += (c << 5 | c >> 27) + ((d & e) ^ (d & a) ^ (e & a)) + (unsigned int)(0x8F1BBCDC) + schedule[58 & 0xF]; d = d << 30 | d >> 2;
    temp = schedule[(59 - 3) & 0xF] ^ schedule[(59 - 8) & 0xF] ^ schedule[(59 - 14) & 0xF] ^ schedule[(59 - 16) & 0xF]; schedule[59 & 0xF] = temp << 1 | temp >> 31; a += (b << 5 | b >> 27) + ((c & d) ^ (c & e) ^ (d & e)) + (unsigned int)(0x8F1BBCDC) + schedule[59 & 0xF]; c = c << 30 | c >> 2;
    temp = schedule[(60 - 3) & 0xF] ^ schedule[(60 - 8) & 0xF] ^ schedule[(60 - 14) & 0xF] ^ schedule[(60 - 16) & 0xF]; schedule[60 & 0xF] = temp << 1 | temp >> 31; e += (a << 5 | a >> 27) + (b ^ c ^ d) + (unsigned int)(0xCA62C1D6) + schedule[60 & 0xF]; b = b << 30 | b >> 2;
    temp = schedule[(61 - 3) & 0xF] ^ schedule[(61 - 8) & 0xF] ^ schedule[(61 - 14) & 0xF] ^ schedule[(61 - 16) & 0xF]; schedule[61 & 0xF] = temp << 1 | temp >> 31; d += (e << 5 | e >> 27) + (a ^ b ^ c) + (unsigned int)(0xCA62C1D6) + schedule[61 & 0xF]; a = a << 30 | a >> 2;
    temp = schedule[(62 - 3) & 0xF] ^ schedule[(62 - 8) & 0xF] ^ schedule[(62 - 14) & 0xF] ^ schedule[(62 - 16) & 0xF]; schedule[62 & 0xF] = temp << 1 | temp >> 31; c += (d << 5 | d >> 27) + (e ^ a ^ b) + (unsigned int)(0xCA62C1D6) + schedule[62 & 0xF]; e = e << 30 | e >> 2;
    temp = schedule[(63 - 3) & 0xF] ^ schedule[(63 - 8) & 0xF] ^ schedule[(63 - 14) & 0xF] ^ schedule[(63 - 16) & 0xF]; schedule[63 & 0xF] = temp << 1 | temp >> 31; b += (c << 5 | c >> 27) + (d ^ e ^ a) + (unsigned int)(0xCA62C1D6) + schedule[63 & 0xF]; d = d << 30 | d >> 2;
    temp = schedule[(64 - 3) & 0xF] ^ schedule[(64 - 8) & 0xF] ^ schedule[(64 - 14) & 0xF] ^ schedule[(64 - 16) & 0xF]; schedule[64 & 0xF] = temp << 1 | temp >> 31; a += (b << 5 | b >> 27) + (c ^ d ^ e) + (unsigned int)(0xCA62C1D6) + schedule[64 & 0xF]; c = c << 30 | c >> 2;
    temp = schedule[(65 - 3) & 0xF] ^ schedule[(65 - 8) & 0xF] ^ schedule[(65 - 14) & 0xF] ^ schedule[(65 - 16) & 0xF]; schedule[65 & 0xF] = temp << 1 | temp >> 31; e += (a << 5 | a >> 27) + (b ^ c ^ d) + (unsigned int)(0xCA62C1D6) + schedule[65 & 0xF]; b = b << 30 | b >> 2;
    temp = schedule[(66 - 3) & 0xF] ^ schedule[(66 - 8) & 0xF] ^ schedule[(66 - 14) & 0xF] ^ schedule[(66 - 16) & 0xF]; schedule[66 & 0xF] = temp << 1 | temp >> 31; d += (e << 5 | e >> 27) + (a ^ b ^ c) + (unsigned int)(0xCA62C1D6) + schedule[66 & 0xF]; a = a << 30 | a >> 2;
    temp = schedule[(67 - 3) & 0xF] ^ schedule[(67 - 8) & 0xF] ^ schedule[(67 - 14) & 0xF] ^ schedule[(67 - 16) & 0xF]; schedule[67 & 0xF] = temp << 1 | temp >> 31; c += (d << 5 | d >> 27) + (e ^ a ^ b) + (unsigned int)(0xCA62C1D6) + schedule[67 & 0xF]; e = e << 30 | e >> 2;
    temp = schedule[(68 - 3) & 0xF] ^ schedule[(68 - 8) & 0xF] ^ schedule[(68 - 14) & 0xF] ^ schedule[(68 - 16) & 0xF]; schedule[68 & 0xF] = temp << 1 | temp >> 31; b += (c << 5 | c >> 27) + (d ^ e ^ a) + (unsigned int)(0xCA62C1D6) + schedule[68 & 0xF]; d = d << 30 | d >> 2;
    temp = schedule[(69 - 3) & 0xF] ^ schedule[(69 - 8) & 0xF] ^ schedule[(69 - 14) & 0xF] ^ schedule[(69 - 16) & 0xF]; schedule[69 & 0xF] = temp << 1 | temp >> 31; a += (b << 5 | b >> 27) + (c ^ d ^ e) + (unsigned int)(0xCA62C1D6) + schedule[69 & 0xF]; c = c << 30 | c >> 2;
    temp = schedule[(70 - 3) & 0xF] ^ schedule[(70 - 8) & 0xF] ^ schedule[(70 - 14) & 0xF] ^ schedule[(70 - 16) & 0xF]; schedule[70 & 0xF] = temp << 1 | temp >> 31; e += (a << 5 | a >> 27) + (b ^ c ^ d) + (unsigned int)(0xCA62C1D6) + schedule[70 & 0xF]; b = b << 30 | b >> 2;
    temp = schedule[(71 - 3) & 0xF] ^ schedule[(71 - 8) & 0xF] ^ schedule[(71 - 14) & 0xF] ^ schedule[(71 - 16) & 0xF]; schedule[71 & 0xF] = temp << 1 | temp >> 31; d += (e << 5 | e >> 27) + (a ^ b ^ c) + (unsigned int)(0xCA62C1D6) + schedule[71 & 0xF]; a = a << 30 | a >> 2;
    temp = schedule[(72 - 3) & 0xF] ^ schedule[(72 - 8) & 0xF] ^ schedule[(72 - 14) & 0xF] ^ schedule[(72 - 16) & 0xF]; schedule[72 & 0xF] = temp << 1 | temp >> 31; c += (d << 5 | d >> 27) + (e ^ a ^ b) + (unsigned int)(0xCA62C1D6) + schedule[72 & 0xF]; e = e << 30 | e >> 2;
    temp = schedule[(73 - 3) & 0xF] ^ schedule[(73 - 8) & 0xF] ^ schedule[(73 - 14) & 0xF] ^ schedule[(73 - 16) & 0xF]; schedule[73 & 0xF] = temp << 1 | temp >> 31; b += (c << 5 | c >> 27) + (d ^ e ^ a) + (unsigned int)(0xCA62C1D6) + schedule[73 & 0xF]; d = d << 30 | d >> 2;
    temp = schedule[(74 - 3) & 0xF] ^ schedule[(74 - 8) & 0xF] ^ schedule[(74 - 14) & 0xF] ^ schedule[(74 - 16) & 0xF]; schedule[74 & 0xF] = temp << 1 | temp >> 31; a += (b << 5 | b >> 27) + (c ^ d ^ e) + (unsigned int)(0xCA62C1D6) + schedule[74 & 0xF]; c = c << 30 | c >> 2;
    temp = schedule[(75 - 3) & 0xF] ^ schedule[(75 - 8) & 0xF] ^ schedule[(75 - 14) & 0xF] ^ schedule[(75 - 16) & 0xF]; schedule[75 & 0xF] = temp << 1 | temp >> 31; e += (a << 5 | a >> 27) + (b ^ c ^ d) + (unsigned int)(0xCA62C1D6) + schedule[75 & 0xF]; b = b << 30 | b >> 2;
    temp = schedule[(76 - 3) & 0xF] ^ schedule[(76 - 8) & 0xF] ^ schedule[(76 - 14) & 0xF] ^ schedule[(76 - 16) & 0xF]; schedule[76 & 0xF] = temp << 1 | temp >> 31; d += (e << 5 | e >> 27) + (a ^ b ^ c) + (unsigned int)(0xCA62C1D6) + schedule[76 & 0xF]; a = a << 30 | a >> 2;
    temp = schedule[(77 - 3) & 0xF] ^ schedule[(77 - 8) & 0xF] ^ schedule[(77 - 14) & 0xF] ^ schedule[(77 - 16) & 0xF]; schedule[77 & 0xF] = temp << 1 | temp >> 31; c += (d << 5 | d >> 27) + (e ^ a ^ b) + (unsigned int)(0xCA62C1D6) + schedule[77 & 0xF]; e = e << 30 | e >> 2;
    temp = schedule[(78 - 3) & 0xF] ^ schedule[(78 - 8) & 0xF] ^ schedule[(78 - 14) & 0xF] ^ schedule[(78 - 16) & 0xF]; schedule[78 & 0xF] = temp << 1 | temp >> 31; b += (c << 5 | c >> 27) + (d ^ e ^ a) + (unsigned int)(0xCA62C1D6) + schedule[78 & 0xF]; d = d << 30 | d >> 2;
    temp = schedule[(79 - 3) & 0xF] ^ schedule[(79 - 8) & 0xF] ^ schedule[(79 - 14) & 0xF] ^ schedule[(79 - 16) & 0xF]; schedule[79 & 0xF] = temp << 1 | temp >> 31; a += (b << 5 | b >> 27) + (c ^ d ^ e) + (unsigned int)(0xCA62C1D6) + schedule[79 & 0xF]; c = c << 30 | c >> 2;

    state[0] += a;
    state[1] += b;
    state[2] += c;
    state[3] += d;
    state[4] += e;
}

static void SHA1_Transform (unsigned int *state, const unsigned char *in, int repeat)
{
 while(repeat-- > 0)
 {
  sha1_compress(state, in);
  in += 64;
 }
}

void SHA1L_Init (SHA_CTXL *context)
{
 context->bytesHandled = 0;
 context->state[0] = 0x67452301U;
 context->state[1] = 0xEFCDAB89U;
 context->state[2] = 0x98BADCFEU;
 context->state[3] = 0x10325476U;
 context->state[4] = 0xC3D2E1F0U;
}

void SHA1L_Update (SHA_CTXL *context, const unsigned char *input, unsigned long input_bytes)
{
 int byteIndex;
 int startLen;
 int remainderLen;
 int finalRemainder;

 byteIndex = (context->bytesHandled & 0x3F);
 context->bytesHandled += input_bytes;
 startLen = (64 - byteIndex);
 remainderLen = (input_bytes - startLen);
 if (remainderLen >= 0) {
  memcpy (&context->buffer[byteIndex], input, startLen);
  SHA1_Transform (context->state, context->buffer, 1);
  SHA1_Transform (context->state, &input[startLen], (remainderLen / 64));
  finalRemainder = startLen + (remainderLen & ~0x3F);
  byteIndex = 0;
 }
 else
  finalRemainder = 0;

 memcpy (&context->buffer[byteIndex], &input[finalRemainder], (input_bytes - finalRemainder));
}

void SHA1L_Final (unsigned char digest[20], SHA_CTXL *context)
{
 unsigned char finalblock[64 + 8];
 unsigned int blockStartOffset;
 unsigned int finalBlockLength;
 int i;

 memset(finalblock, 0, sizeof(finalblock));
 finalblock[0] = 0x80;
 blockStartOffset = (context->bytesHandled & 0x3F);
 finalBlockLength = (((blockStartOffset < 56) ? 56 : 120) - blockStartOffset);
 unaligned_write32_be (&finalblock[finalBlockLength + 0], context->bytesHandled >> 29);
 unaligned_write32_be (&finalblock[finalBlockLength + 4], context->bytesHandled << 3);
 SHA1L_Update (context, finalblock, finalBlockLength + 8);
 for (i = 0; i < 5; i++)
  unaligned_write32_be (&digest[i*4], context->state[i]);
}
