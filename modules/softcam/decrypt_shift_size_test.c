#include "decrypt_shift_size.h"

#include <assert.h>
#include <stddef.h>

int main(void)
{
    const size_t five_seconds = decrypt_shift_size_bytes(50);
    const size_t eight_seconds = decrypt_shift_size_bytes(8000);
    const size_t capped = decrypt_shift_size_bytes(60000);

    assert(five_seconds >= 6250000U);
    assert(eight_seconds >= 10000000U);
    assert(eight_seconds < 16U * 1024U * 1024U);
    assert(capped % 188U == 0U);
    assert(capped <= 16U * 1024U * 1024U);
    assert(decrypt_shift_size_bytes(0) == 0U);

    return 0;
}
