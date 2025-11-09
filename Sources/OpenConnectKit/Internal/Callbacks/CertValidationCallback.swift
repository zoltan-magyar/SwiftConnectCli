//
//  CertValidationCallback.swift
//  OpenConnectKit
//
//  Internal certificate validation callback handler
//

import COpenConnect
import Foundation

/// Handles certificate validation requests from the OpenConnect C library.
///
/// This function is called when the OpenConnect library needs to validate a server certificate.
/// It extracts the `VpnContext` from the `privdata` pointer, translates the C validation reason
/// to a Swift `CertificateInfo` structure, and delegates to the context's validation handler.
///
/// - Parameters:
///   - privdata: Pointer to the `VpnContext` managing the OpenConnect connection
///   - reason: C string pointer describing the validation failure reason
/// - Returns: `0` to accept the certificate, `1` to reject it
internal func validatePeerCertCallback(
  privdata: UnsafeMutableRawPointer?,
  reason: UnsafePointer<CChar>?
) -> CInt {
  guard let privdata = privdata else {
    return 1
  }

  let context = Unmanaged<VpnContext>.fromOpaque(privdata).takeUnretainedValue()

  return context.handleCertificateValidation(reason: reason)
}
