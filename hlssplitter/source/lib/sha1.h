#ifndef _SHA1_H_
#define _SHA1_H_

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
        @file     sha.h
        @brief

    Rev Date      Author      Comments
  ----------------------------------------------------------------------------
      1 20080925  amccurdy    Initial CMS checkin
*/

#define SHA_DIGEST_LENGTH 20

typedef struct
{
	unsigned int state[5];
	unsigned int bytesHandled;	/* Note: results will differ from reference sha1 if hashing >= 2^32 bytes */
	unsigned char buffer[64];
}
SHA_CTXL;

extern void SHA1L_Init (SHA_CTXL *context);
extern void SHA1L_Update (SHA_CTXL *context, const unsigned char *input, unsigned long input_bytes);
extern void SHA1L_Final (unsigned char digest[SHA_DIGEST_LENGTH], SHA_CTXL *context);

#define SHA1L(buffer, size, outhash) ({ \
                                        SHA_CTXL ctx; \
                                        SHA1L_Init(&ctx); \
                                        SHA1L_Update(&ctx, buffer, size); \
                                        SHA1L_Final(outhash, &ctx); \
                                      })

#endif
