//
//  COpenConnect.c
//  OpenConnectSwiftCLI
//
//  C shim to convert OpenConnect's variadic progress callback to a formatted
//  string This allows Swift code to handle the callback without dealing with
//  va_list
//
//  This implementation is stateless - it formats the message in C and calls
//  into Swift which uses privdata to access the VpnContext.
//

#include "include/COpenConnect.h"
#include <stdarg.h>
#include <stddef.h>
#include <stdio.h>
#include <stdlib.h>

extern void progressCallback(void *privdata, int level,
                             const char *formatted_message);

void progress_shim_callback(void *privdata, int level, const char *fmt, ...) {
  if (fmt == NULL) {
    return;
  }

  // Format the message using vsnprintf
  va_list args;
  va_start(args, fmt);

  // First, determine the size needed
  va_list args_copy;
  va_copy(args_copy, args);
  int size = vsnprintf(NULL, 0, fmt, args_copy);
  va_end(args_copy);

  if (size < 0) {
    va_end(args);
    return;
  }

  // Allocate buffer (size + 1 for null terminator)
  char *buffer = (char *)malloc(size + 1);
  if (buffer == NULL) {
    va_end(args);
    return;
  }

  // Format the string
  vsnprintf(buffer, size + 1, fmt, args);
  va_end(args);

  // Call the Swift dispatcher with the formatted message
  progressCallback(privdata, level, buffer);

  // Free the buffer
  free(buffer);
}

// Returns a pointer to progress_shim_callback
// This allows Swift to get a function pointer to our variadic shim function
openconnect_progress_vfn get_progress_shim_callback(void) {
  return &progress_shim_callback;
}
