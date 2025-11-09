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
  /// 4. Configures the TUN device for routing VPN traffic
  /// 5. Starts the mainloop to handle VPN traffic
  ///
  /// - Throws: `VpnError` if any connection step fails
  func connect() throws {
    guard let vpnInfo = self.vpnInfo else {
      throw VpnError.notInitialized
    }

    guard !isConnected else {
      return
    }

    // Step 1: Obtain authentication cookie
    var ret = openconnect_obtain_cookie(vpnInfo)
    if ret != 0 {
      throw VpnError.cookieObtainFailed
    }

    // Step 2: Establish CSTP connection
    ret = openconnect_make_cstp_connection(vpnInfo)
    if ret != 0 {
      throw VpnError.cstpConnectionFailed
    }

    // Step 3: Setup DTLS for secure data channel
    ret = openconnect_setup_dtls(vpnInfo, 60)
    if ret != 0 {
      throw VpnError.dtlsSetupFailed
    }

    // Step 4: Setup TUN device for routing VPN traffic
    ret = try setupTunDevice()
    if ret != 0 {
      throw VpnError.tunSetupFailed
    }

    // Step 5: Start the mainloop to handle VPN traffic
    startMainloop()

    isConnected = true
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
    guard isConnected else {
      return
    }

    // Stop the mainloop if it's running
    stopMainloop()

    isConnected = false
  }
}
