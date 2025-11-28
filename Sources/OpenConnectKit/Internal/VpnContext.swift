//
//  VpnContext.swift
//  OpenConnectKit
//
//  Internal wrapper around OpenConnect C API
//

import COpenConnect
import Foundation

#if os(Windows)
  import WinSDK
#endif

// Internal context managing OpenConnect C API
internal class VpnContext {
  // MARK: - Properties

  internal var connectionStatus: ConnectionStatus = .disconnected(error: nil)
  internal let stateLock = NSLock()
  internal var status: ConnectionStatus {
    stateLock.lock()
    defer { stateLock.unlock() }
    return connectionStatus
  }

  internal var vpnInfo: OpaquePointer!
  internal unowned let session: VpnSession

  // Command pipe for controlling mainloop (OC_CMD_*)
  #if os(Windows)
    internal var cmdFd: SOCKET!
  #else
    internal var cmdFd: Int32!
  #endif

  internal var mainloopThread: Thread?
  internal var setupError: VpnError?

  // MARK: - Command Types

  internal enum Command: UInt8 {
    case cancel = 0x78  // 'x'
    case pause = 0x70  // 'p'
    case detach = 0x64  // 'd'
    case stats = 0x73  // 's'
  }

  // MARK: - Initialization

  /// Creates a VPN context.
  ///
  /// This initializes the OpenConnect library, parses the server URL, sets up
  /// the command pipe for mainloop control, and registers callback handlers.
  ///
  /// - Parameter session: The VpnSession that owns this context
  /// - Throws: `VpnError` if initialization fails
  init(session: VpnSession) throws {
    self.session = session

    // Create OpenConnect vpninfo structure with callbacks
    // Pass VpnContext (self) as privdata since it manages the OpenConnect resources
    guard
      let vpnInfo = openconnect_vpninfo_new(
        "AnyConnect Compatible OpenConnectKit Client",
        validatePeerCertCallback,
        nil,
        processAuthFormCallback,
        get_progress_shim_callback(),
        Unmanaged.passUnretained(self).toOpaque()
      )
    else {
      throw VpnError.notInitialized
    }

    self.vpnInfo = vpnInfo

    // Configure log level
    openconnect_set_loglevel(vpnInfo, session.configuration.logLevel.openConnectLevel)

    // Parse and validate server URL
    let ret = openconnect_parse_url(vpnInfo, session.configuration.serverURL.absoluteString)
    if ret != 0 {
      throw VpnError.invalidConfiguration(reason: "Failed to parse server URL")
    }

    // Set up command pipe for controlling the mainloop
    let cmdFdResult = openconnect_setup_cmd_pipe(vpnInfo)
    #if os(Windows)
      if cmdFdResult == INVALID_SOCKET {
        throw VpnError.cmdPipeSetupFailed
      }
    #else
      if cmdFdResult < 0 {
        throw VpnError.cmdPipeSetupFailed
      }
    #endif
    self.cmdFd = cmdFdResult

    // Register callback handlers
    openconnect_set_reconnected_handler(vpnInfo, reconnectedCallback)
    openconnect_set_stats_handler(vpnInfo, statsCallback)
    openconnect_set_setup_tun_handler(vpnInfo, setupTunCallback)
  }

  deinit {
    disconnect()
    openconnect_vpninfo_free(vpnInfo)
  }

  // MARK: - Public Computed Properties

  internal var isCmdPipeReady: Bool {
    #if os(Windows)
      return cmdFd != INVALID_SOCKET
    #else
      return cmdFd >= 0
    #endif
  }

  internal var assignedInterfaceName: String? {
    guard let ifnamePtr = openconnect_get_ifname(vpnInfo) else {
      return nil
    }

    return String(cString: ifnamePtr)
  }
}
