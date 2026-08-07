#include <assert.h>

#include "newcamd_reconnect.h"

int main(void)
{
    assert(newcamd_should_reconnect_immediately(0));
    assert(!newcamd_should_reconnect_immediately(-1));
    return 0;
}
