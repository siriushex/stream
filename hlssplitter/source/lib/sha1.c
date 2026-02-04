/****************************************************************************/
/* Copyright (c) 2008 NXP B.V.  All rights are reserved.                    */
/*                                                                          */
/* Redistribution and use in source and binary forms, with or without       */
/* modification, are permitted provided that the following conditions       */
/* are met:                                                                 */
/*                                                                          */
/* Redistributions of source code must retain the above copyright           */
/* notice, this list of conditions and the following disclaimer.            */
/*                                                                          */
/* Redistributions in binary form must reproduce the above copyright        */
/* notice, this list of conditions and the following disclaimer in the      */
/* documentation and/or other materials provided with the distribution.     */
/*                                                                          */
/* Neither the name of NXP nor the names of its                             */
/* contributors may be used to endorse or promote products derived from     */
/* this software without specific prior written permission.                 */
/*                                                                          */
/* THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS      */
/* "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT        */
/* LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR    */
/* A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT     */
/* OWNER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL,    */
/* SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT         */
/* LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE,    */
/* DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY    */
/* THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT      */
/* (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE        */
/* USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH         */
/* DAMAGE.                                                                  */
/*                                                                          */
/****************************************************************************/
/*
        @file     sha1.c
        @brief

    Rev Date      Author      Comments
  ----------------------------------------------------------------------------
      1 20080925  amccurdy    Initial CMS checkin
*/
/*****************************************************************************
*****************************************************************************/

#include <string.h>

#include "sha1.h"


static void unaligned_write32_be (unsigned char *dst, unsigned int value)
{
	*dst++ = value >> 24;
	*dst++ = value >> 16;
	*dst++ = value >> 8;
	*dst++ = value >> 0;
}

void sha1_compress(unsigned int *state, const unsigned char *block)
{
    #define SCHEDULE(i)  \
        temp = schedule[(i - 3) & 0xF] ^ schedule[(i - 8) & 0xF] ^ schedule[(i - 14) & 0xF] ^ schedule[(i - 16) & 0xF];  \
        schedule[i & 0xF] = temp << 1 | temp >> 31;
    #define LOADSCHEDULE(i)  \
        schedule[i] =                           \
          (unsigned int)block[i * 4 + 0] << 24  \
        | (unsigned int)block[i * 4 + 1] << 16  \
        | (unsigned int)block[i * 4 + 2] <<  8  \
        | (unsigned int)block[i * 4 + 3];
    #define ROUND0a(a, b, c, d, e, i)  LOADSCHEDULE(i)  ROUNDTAIL(a, b, e, ((b & c) | (~b & d))         , i, 0x5A827999)
    #define ROUND0b(a, b, c, d, e, i)  SCHEDULE(i)      ROUNDTAIL(a, b, e, ((b & c) | (~b & d))         , i, 0x5A827999)
    #define ROUND1(a, b, c, d, e, i)   SCHEDULE(i)      ROUNDTAIL(a, b, e, (b ^ c ^ d)                  , i, 0x6ED9EBA1)
    #define ROUND2(a, b, c, d, e, i)   SCHEDULE(i)      ROUNDTAIL(a, b, e, ((b & c) ^ (b & d) ^ (c & d)), i, 0x8F1BBCDC)
    #define ROUND3(a, b, c, d, e, i)   SCHEDULE(i)      ROUNDTAIL(a, b, e, (b ^ c ^ d)                  , i, 0xCA62C1D6)

    #define ROUNDTAIL(a, b, e, f, i, k)  \
        e += (a << 5 | a >> 27) + f + (unsigned int)(k) + schedule[i & 0xF];  \
        b = b << 30 | b >> 2;
    unsigned int a = state[0];
    unsigned int b = state[1];
    unsigned int c = state[2];
    unsigned int d = state[3];
    unsigned int e = state[4];
    unsigned int schedule[16];
    unsigned int temp;

    ROUND0a(a, b, c, d, e,  0)
    ROUND0a(e, a, b, c, d,  1)
    ROUND0a(d, e, a, b, c,  2)
    ROUND0a(c, d, e, a, b,  3)
    ROUND0a(b, c, d, e, a,  4)
    ROUND0a(a, b, c, d, e,  5)
    ROUND0a(e, a, b, c, d,  6)
    ROUND0a(d, e, a, b, c,  7)
    ROUND0a(c, d, e, a, b,  8)
    ROUND0a(b, c, d, e, a,  9)
    ROUND0a(a, b, c, d, e, 10)
    ROUND0a(e, a, b, c, d, 11)
    ROUND0a(d, e, a, b, c, 12)
    ROUND0a(c, d, e, a, b, 13)
    ROUND0a(b, c, d, e, a, 14)
    ROUND0a(a, b, c, d, e, 15)
    ROUND0b(e, a, b, c, d, 16)
    ROUND0b(d, e, a, b, c, 17)
    ROUND0b(c, d, e, a, b, 18)
    ROUND0b(b, c, d, e, a, 19)
    ROUND1(a, b, c, d, e, 20)
    ROUND1(e, a, b, c, d, 21)
    ROUND1(d, e, a, b, c, 22)
    ROUND1(c, d, e, a, b, 23)
    ROUND1(b, c, d, e, a, 24)
    ROUND1(a, b, c, d, e, 25)
    ROUND1(e, a, b, c, d, 26)
    ROUND1(d, e, a, b, c, 27)
    ROUND1(c, d, e, a, b, 28)
    ROUND1(b, c, d, e, a, 29)
    ROUND1(a, b, c, d, e, 30)
    ROUND1(e, a, b, c, d, 31)
    ROUND1(d, e, a, b, c, 32)
    ROUND1(c, d, e, a, b, 33)
    ROUND1(b, c, d, e, a, 34)
    ROUND1(a, b, c, d, e, 35)
    ROUND1(e, a, b, c, d, 36)
    ROUND1(d, e, a, b, c, 37)
    ROUND1(c, d, e, a, b, 38)
    ROUND1(b, c, d, e, a, 39)
    ROUND2(a, b, c, d, e, 40)
    ROUND2(e, a, b, c, d, 41)
    ROUND2(d, e, a, b, c, 42)
    ROUND2(c, d, e, a, b, 43)
    ROUND2(b, c, d, e, a, 44)
    ROUND2(a, b, c, d, e, 45)
    ROUND2(e, a, b, c, d, 46)
    ROUND2(d, e, a, b, c, 47)
    ROUND2(c, d, e, a, b, 48)
    ROUND2(b, c, d, e, a, 49)
    ROUND2(a, b, c, d, e, 50)
    ROUND2(e, a, b, c, d, 51)
    ROUND2(d, e, a, b, c, 52)
    ROUND2(c, d, e, a, b, 53)
    ROUND2(b, c, d, e, a, 54)
    ROUND2(a, b, c, d, e, 55)
    ROUND2(e, a, b, c, d, 56)
    ROUND2(d, e, a, b, c, 57)
    ROUND2(c, d, e, a, b, 58)
    ROUND2(b, c, d, e, a, 59)
    ROUND3(a, b, c, d, e, 60)
    ROUND3(e, a, b, c, d, 61)
    ROUND3(d, e, a, b, c, 62)
    ROUND3(c, d, e, a, b, 63)
    ROUND3(b, c, d, e, a, 64)
    ROUND3(a, b, c, d, e, 65)
    ROUND3(e, a, b, c, d, 66)
    ROUND3(d, e, a, b, c, 67)
    ROUND3(c, d, e, a, b, 68)
    ROUND3(b, c, d, e, a, 69)
    ROUND3(a, b, c, d, e, 70)
    ROUND3(e, a, b, c, d, 71)
    ROUND3(d, e, a, b, c, 72)
    ROUND3(c, d, e, a, b, 73)
    ROUND3(b, c, d, e, a, 74)
    ROUND3(a, b, c, d, e, 75)
    ROUND3(e, a, b, c, d, 76)
    ROUND3(d, e, a, b, c, 77)
    ROUND3(c, d, e, a, b, 78)
    ROUND3(b, c, d, e, a, 79)

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

void SHA1L_Final (unsigned char digest[SHA_DIGEST_LENGTH], SHA_CTXL *context)
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
