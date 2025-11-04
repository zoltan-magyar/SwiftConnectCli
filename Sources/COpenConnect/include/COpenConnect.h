//
//  COpenConnect.h
//  OpenConnectSwiftCLI
//
//  C shim to convert OpenConnect's variadic progress callback to va_list
//  This allows Swift code to handle the callback using CVaListPointer
//

#ifndef COpenConnect_h
#define COpenConnect_h

// OpenConnect library types and functions (provided by COpenConnectLib module)
#include <openconnect.h>
#include <stdarg.h>

// Type definition for the va_list version of the progress callback
// that Swift can implement
typedef void (*progress_va_callback)(void *privdata, int level, const char *fmt, va_list args);

// Register the Swift callback that uses va_list
void register_progress_callback(progress_va_callback callback);

// This function matches OpenConnect's expected signature (openconnect_progress_vfn)
// and can be passed to openconnect_vpninfo_new
void progress_shim_callback(void *privdata, int level, const char *fmt, ...);

// Returns a pointer to progress_shim_callback that Swift can use
// Swift can't directly reference C functions with variadics, so we provide this getter
openconnect_progress_vfn get_progress_shim_callback(void);

#endif /* COpenConnect_h */
