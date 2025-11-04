//
//  COpenConnect.c
//  OpenConnectSwiftCLI
//
//  C shim to convert OpenConnect's variadic progress callback to va_list
//  This allows Swift code to handle the callback using CVaListPointer
//

#include "include/COpenConnect.h"
#include <stdarg.h>
#include <stddef.h>

// Global pointer to store the Swift callback that uses va_list
static progress_va_callback swift_progress_callback = NULL;

// Register the Swift callback
void register_progress_callback(progress_va_callback callback) {
  swift_progress_callback = callback;
}

// This function matches OpenConnect's expected signature
// (openconnect_progress_vfn) It converts the variadic arguments to va_list and
// forwards to Swift
void progress_shim_callback(void *privdata, int level, const char *fmt, ...) {
  if (swift_progress_callback == NULL) {
    // No callback registered, do nothing
    return;
  }

  va_list args;
  va_start(args, fmt);

  // Call the Swift callback with va_list
  swift_progress_callback(privdata, level, fmt, args);

  va_end(args);
}

// Returns a pointer to progress_shim_callback
// This allows Swift to get a function pointer to our variadic shim function
openconnect_progress_vfn get_progress_shim_callback(void) {
  return &progress_shim_callback;
}
