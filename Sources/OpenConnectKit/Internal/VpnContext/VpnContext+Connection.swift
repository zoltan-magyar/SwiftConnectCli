//
//  VpnContext+Connection.swift
//  OpenConnectKit
//
//  Connection management extension for VpnContext
//

import COpenConnect
import Foundation

// MARK: - Connection Management

extension VpnContext {
  // Connects to VPN: auth cookie → CSTP → DTLS → TUN setup (via callback) → mainloop
  func connect() throws {
    stateLock.lock()
    guard case .disconnected = connectionStatus else {
      stateLock.unlock()
      return
    }
    connectionStatus = .connecting(stage: "Initializing connection")
    stateLock.unlock()

    session.handleStatusChange(status: .connecting(stage: "Initializing connection"))

    updateStatus(.connecting(stage: "Authenticating..."))
    var ret = openconnect_obtain_cookie(vpnInfo)
    if ret != 0 {
      updateStatus(.disconnected(error: .cookieObtainFailed))
      throw VpnError.cookieObtainFailed
    }

    updateStatus(.connecting(stage: "Establishing CSTP connection"))
    ret = openconnect_make_cstp_connection(vpnInfo)
    if ret != 0 {
      updateStatus(.disconnected(error: .cstpConnectionFailed))
      throw VpnError.cstpConnectionFailed
    }

    updateStatus(.connecting(stage: "Setting up DTLS"))
    ret = openconnect_setup_dtls(vpnInfo, 60)
    if ret != 0 {
      updateStatus(.disconnected(error: .dtlsSetupFailed))
      throw VpnError.dtlsSetupFailed
    }

    startMainloop()
  }

  // Disconnect: stop mainloop → cleanup
  func disconnect() {
    stateLock.lock()
    if case .disconnected = connectionStatus {
      stateLock.unlock()
      return
    }
    stateLock.unlock()

    stopMainloop()

    updateStatus(.disconnected(error: nil))
  }

  // Thread-safe status update
  internal func updateStatus(_ status: ConnectionStatus) {
    stateLock.lock()
    connectionStatus = status
    stateLock.unlock()

    session.handleStatusChange(status: status)
  }
}
