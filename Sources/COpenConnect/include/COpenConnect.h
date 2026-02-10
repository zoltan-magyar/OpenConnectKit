//
//  COpenConnect.h
//  OpenConnectSwiftCLI
//
//  C shim to convert OpenConnect's variadic progress callback to a formatted string
//  This allows Swift code to handle the callback without dealing with va_list
//

#ifndef COpenConnect_h
#define COpenConnect_h

// OpenConnect library types and functions (provided by COpenConnectLib module)
#include <openconnect.h>
#include <stdarg.h>

// Type definition for the Swift callback that receives a formatted string
typedef void (*progress_formatted_callback)(void *privdata, int level, const char *formatted_message);

// This function matches OpenConnect's expected signature (openconnect_progress_vfn)
// and can be passed to openconnect_vpninfo_new
// It formats the variadic message and forwards the formatted string to Swift
void progress_shim_callback(void *privdata, int level, const char *fmt, ...);

// Returns a pointer to progress_shim_callback that Swift can use
// Swift can't directly reference C functions with variadics, so we provide this getter
openconnect_progress_vfn get_progress_shim_callback(void);

// Certificate validation callback (defined in Swift with @_cdecl)
// int validatePeerCertCallback(void *privdata, const char *reason);

// Authentication form callback (defined in Swift with @_cdecl)
//int processAuthFormCallback(void *privdata, struct oc_auth_form *form);

// Getter functions to avoid Swift thunk generation issues
// openconnect_validate_peer_cert_vfn get_cert_validation_callback(void);
//openconnect_process_auth_form_vfn get_auth_form_callback(void);

#endif /* COpenConnect_h */
