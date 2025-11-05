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
/// It extracts the `VpnSession` from the `privdata` pointer, translates the C validation reason
/// to a Swift `CertificateInfo` structure, and delegates to the session's validation handler.
///
/// - Parameters:
///   - privdata: Pointer to the owning `VpnSession`
///   - reason: C string pointer describing the validation failure reason
/// - Returns: `0` to accept the certificate, `1` to reject it
internal func validatePeerCertCallback(
    privdata: UnsafeMutableRawPointer?,
    reason: UnsafePointer<CChar>?
) -> CInt {
    guard let privdata = privdata else {
        return 1
    }

    let session = Unmanaged<VpnSession>.fromOpaque(privdata).takeUnretainedValue()

    guard let context = session.context else {
        return 1
    }

    return context.handleCertificateValidation(reason: reason)
}
