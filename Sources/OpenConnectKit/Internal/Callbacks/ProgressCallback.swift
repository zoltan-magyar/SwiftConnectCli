//
//  ProgressCallback.swift
//  OpenConnectKit
//
//  Internal progress callback handler
//

import COpenConnect
import Foundation

// MARK: - C Callback Entry Point

/// Handles progress/log messages from the OpenConnect C library.
///
/// This function is called from the C shim (`progress_shim_callback`) after it formats
/// the variadic arguments into a string. The function extracts the `VpnContext` from
/// the `privdata` pointer and delegates to its progress handler.
///
/// - Parameters:
///   - privdata: Pointer to the `VpnContext` managing the OpenConnect connection
///   - level: The C log level (0=error, 1=info, 2=debug, 3=trace)
///   - formatted_message: The formatted message string
@_cdecl("progressCallback")
internal func progressCallback(
  privdata: UnsafeMutableRawPointer?, level: CInt, formatted_message: UnsafePointer<CChar>?
) {
  guard let privdata = privdata else {
    return
  }

  guard let formatted_message = formatted_message else {
    return
  }

  let context = Unmanaged<VpnContext>.fromOpaque(privdata).takeUnretainedValue()
  let message = String(cString: formatted_message)

  context.handleProgress(level: level, message: message)
}
