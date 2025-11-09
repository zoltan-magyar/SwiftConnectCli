//
//  ReconnectedCallback.swift
//  OpenConnectKit
//
//  Internal reconnection callback handler
//

import COpenConnect
import Foundation

// MARK: - C Callback Entry Point

/// Handles reconnection notifications from the OpenConnect C library.
///
/// This function is called by OpenConnect when the VPN connection is successfully
/// re-established after a disconnection. It extracts the `VpnSession` from the
/// `privdata` pointer and delegates to its reconnection handler.
///
/// This callback is registered via `openconnect_set_reconnected_handler()` and
/// will only be triggered on reconnections, not on the initial connection.
///
/// - Parameter privdata: Pointer to the owning `VpnSession`
internal func reconnectedCallback(privdata: UnsafeMutableRawPointer?) {
    guard let privdata = privdata else {
        return
    }

    let session = Unmanaged<VpnSession>.fromOpaque(privdata).takeUnretainedValue()
    session.handleReconnected()
}
