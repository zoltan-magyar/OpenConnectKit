#ifndef COPENCONNECTLIB_H
#define COPENCONNECTLIB_H

// This system library wrapper provides access to the OpenConnect C library
// via pkg-config, ensuring portability across different installation locations.
//
// Note: This module could potentially be simplified by merging with COpenConnect,
// but the current separation maintains a clear boundary between:
// - COpenConnectLib: System library wrapper (OpenConnect itself)
// - COpenConnect: Custom C shims for variadic callbacks

#include <openconnect.h>

#endif // COPENCONNECTLIB_H
