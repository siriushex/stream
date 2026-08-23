#ifndef _NEWCAMD_OPENSSL_PROBE_H_
#define _NEWCAMD_OPENSSL_PROBE_H_ 1

#include <openssl/crypto.h>
#include <openssl/des.h>

static inline int newcamd_openssl_probe(void)
{
    DES_cblock block = {0};
    (void)block;

#if OPENSSL_VERSION_NUMBER < 0x10100000L
    return SSLeay() == 0;
#else
    return OpenSSL_version_num() == 0;
#endif
}

#endif /* _NEWCAMD_OPENSSL_PROBE_H_ */
