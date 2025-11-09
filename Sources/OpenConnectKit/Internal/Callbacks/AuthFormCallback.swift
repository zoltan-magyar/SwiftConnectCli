//
//  AuthFormCallback.swift
//  OpenConnectKit
//
//  Internal authentication form callback handler
//

import COpenConnect
import Foundation

/// Handles authentication form requests from the OpenConnect C library.
///
/// This function is called when the OpenConnect library needs authentication information
/// from the user. It extracts the `VpnSession` from the `privdata` pointer, translates
/// the C `oc_auth_form` structure to a Swift `AuthenticationForm`, delegates to the
/// session's authentication handler, and applies the filled values back to the C structure.
///
/// - Parameters:
///   - privdata: Pointer to the owning `VpnSession`
///   - form: Pointer to the C `oc_auth_form` structure to be filled
/// - Returns: `0` for success, `1` for failure
internal func processAuthFormCallback(
  privdata: UnsafeMutableRawPointer?,
  form: UnsafeMutablePointer<oc_auth_form>?
) -> CInt {
  guard let privdata = privdata else {
    return 1
  }

  guard let form = form else {
    return 1
  }

  let context = Unmanaged<VpnContext>.fromOpaque(privdata).takeUnretainedValue()

  return context.handleAuthenticationForm(form: form)
}
