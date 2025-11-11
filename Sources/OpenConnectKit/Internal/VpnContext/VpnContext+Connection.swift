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
  /// Connects to the VPN server.
  ///
  /// This method performs the following steps:
  /// 1. Obtains an authentication cookie from the server
  /// 2. Establishes the CSTP (Control and Provisioning of Wireless Access Points) connection
  /// 3. Sets up DTLS (Datagram Transport Layer Security) for the data channel
  /// 4. TUN device setup (handled automatically by OpenConnect via callback)
  /// 5. Starts the mainloop to handle VPN traffic
  ///
  /// - Throws: `VpnError` if any connection step fails
  func connect() throws {
    stateLock.lock()
    guard connectionStatus.isDisconnected else {
      stateLock.unlock()
      return
    }
    connectionStatus = .connecting(stage: "Initializing connection")
    stateLock.unlock()

    // Notify session of status change
    session?.handleStatusChange(status: .connecting(stage: "Initializing connection"))

    // Step 1: Obtain authentication cookie
    updateStatus(.connecting(stage: "Authenticating..."))
    var ret = openconnect_obtain_cookie(vpnInfo)
    if ret != 0 {
      updateStatus(.disconnected(error: .cookieObtainFailed))
      throw VpnError.cookieObtainFailed
    }

    // Step 2: Establish CSTP connection
    updateStatus(.connecting(stage: "Establishing CSTP connection"))
    ret = openconnect_make_cstp_connection(vpnInfo)
    if ret != 0 {
      updateStatus(.disconnected(error: .cstpConnectionFailed))
      throw VpnError.cstpConnectionFailed
    }

    // Step 3: Setup DTLS for secure data channel
    updateStatus(.connecting(stage: "Setting up DTLS"))
    ret = openconnect_setup_dtls(vpnInfo, 60)
    if ret != 0 {
      updateStatus(.disconnected(error: .dtlsSetupFailed))
      throw VpnError.dtlsSetupFailed
    }

    // Step 4: TUN device setup
    // The TUN device will be set up automatically by OpenConnect via the callback
    // we registered in initialization (setupTunCallback). OpenConnect will call
    // this callback at the appropriate time, after authentication and after
    // receiving network configuration from the server.
    updateStatus(.connecting(stage: "Configuring tunnel"))

    // Step 5: Start the mainloop to handle VPN traffic
    startMainloop()
  }

  /// Disconnects from the VPN server.
  ///
  /// This method performs a graceful shutdown by:
  /// 1. Stopping the mainloop (sends OC_CMD_CANCEL)
  /// 2. Waiting for the mainloop thread to finish
  /// 3. Cleaning up connection state
  ///
  /// The OpenConnect library will automatically:
  /// - Close the CSTP connection
  /// - Shut down DTLS
  /// - Clean up the TUN device
  /// - Log off from the server
  func disconnect() {
    stateLock.lock()
    guard !connectionStatus.isDisconnected else {
      stateLock.unlock()
      return
    }
    stateLock.unlock()

    stopMainloop()

    updateStatus(.disconnected(error: nil))
  }

  /// Updates the connection status in a thread-safe manner and notifies the session.
  ///
  /// - Parameter status: The new connection status
  internal func updateStatus(_ status: ConnectionStatus) {
    stateLock.lock()
    connectionStatus = status
    stateLock.unlock()

    session?.handleStatusChange(status: status)
  }
}
