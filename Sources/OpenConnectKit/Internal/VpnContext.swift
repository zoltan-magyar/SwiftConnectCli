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

/// Internal context managing the OpenConnect VPN connection.
///
/// This class handles all C interop with the OpenConnect library and is owned by `VpnSession`.
/// It translates between Swift types and C types, managing the lifecycle of the underlying
/// OpenConnect `vpninfo` structure.
///
/// The class is organized into extensions by functionality:
/// - `VpnContext+Connection.swift` - Connection and disconnection logic
/// - `VpnContext+TunDevice.swift` - TUN device setup and management
/// - `VpnContext+Mainloop.swift` - Mainloop thread management
/// - `VpnContext+Commands.swift` - Command sending via cmd_fd
/// - `VpnContext+Callbacks.swift` - Callback handling from OpenConnect
internal class VpnContext {
  // MARK: - Properties

  /// OpenConnect vpninfo pointer.
  internal var vpnInfo: OpaquePointer?

  /// Reference to the owning VpnSession.
  internal weak var session: VpnSession?

  /// Configuration for this context.
  internal let configuration: VpnConfiguration

  /// Whether the VPN is currently connected.
  internal var isConnected: Bool = false

  /// Command file descriptor for controlling the mainloop.
  ///
  /// This pipe is used to send commands to the OpenConnect mainloop, such as:
  /// - `OC_CMD_CANCEL` - Close connections, log off, and shut down
  /// - `OC_CMD_PAUSE` - Pause the connection temporarily
  /// - `OC_CMD_DETACH` - Detach from the connection
  /// - `OC_CMD_STATS` - Request traffic statistics
  ///
  /// The pipe is created by `openconnect_setup_cmd_pipe()` and is owned by the
  /// vpninfo structure. It will be automatically closed when `openconnect_vpninfo_free()`
  /// is called.
  ///
  /// Platform-specific types:
  /// - **Windows**: `SOCKET` (from WinSDK)
  /// - **Unix/Linux/macOS**: `Int32` file descriptor
  #if os(Windows)
    internal var cmdFd: SOCKET?
  #else
    internal var cmdFd: Int32?
  #endif

  /// Thread running the OpenConnect mainloop.
  ///
  /// The mainloop runs in a background thread to avoid blocking the main thread.
  /// It continuously processes VPN traffic, handles reconnections, and monitors
  /// the cmd_fd for control commands.
  internal var mainloopThread: Thread?

  /// Flag indicating whether the mainloop is currently running.
  ///
  /// This is used to track the mainloop state and prevent multiple simultaneous
  /// mainloop executions.
  internal var isMainloopRunning: Bool = false

  /// Lock for synchronizing access to mainloop state.
  internal let mainloopLock = NSLock()

  // MARK: - Command Constants

  /// Command byte to cancel the connection and log off.
  internal static let OC_CMD_CANCEL: UInt8 = 0x78  // 'x'

  /// Command byte to pause the connection.
  internal static let OC_CMD_PAUSE: UInt8 = 0x70  // 'p'

  /// Command byte to detach from the connection.
  internal static let OC_CMD_DETACH: UInt8 = 0x64  // 'd'

  /// Command byte to request statistics.
  internal static let OC_CMD_STATS: UInt8 = 0x73  // 's'

  // MARK: - Initialization

  /// Creates a VPN context.
  ///
  /// This initializes the OpenConnect library, parses the server URL, sets up
  /// the command pipe for mainloop control, and registers callback handlers.
  ///
  /// - Parameters:
  ///   - session: The VpnSession that owns this context
  ///   - configuration: The VPN configuration
  /// - Throws: `VpnError` if initialization fails
  init(session: VpnSession, configuration: VpnConfiguration) throws {
    self.session = session
    self.configuration = configuration

    // Create OpenConnect vpninfo structure with callbacks
    self.vpnInfo = openconnect_vpninfo_new(
      "AnyConnect Compatible OpenConnectKit Client",
      validatePeerCertCallback,
      nil,
      processAuthFormCallback,
      get_progress_shim_callback(),
      Unmanaged.passUnretained(session).toOpaque()
    )

    guard let vpnInfo = self.vpnInfo else {
      throw VpnError.notInitialized
    }

    // Configure log level
    openconnect_set_loglevel(vpnInfo, configuration.logLevel.openConnectLevel)

    // Parse and validate server URL
    let ret = openconnect_parse_url(vpnInfo, configuration.serverURL.absoluteString)
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
  }

  deinit {
    disconnect()

    if let vpnInfo = self.vpnInfo {
      openconnect_vpninfo_free(vpnInfo)
      self.vpnInfo = nil
    }

    // Note: cmdFd is owned by vpninfo and will be closed by openconnect_vpninfo_free()
    cmdFd = nil
  }

  // MARK: - Public Computed Properties

  /// Checks if the command pipe has been successfully set up.
  ///
  /// - Returns: `true` if the command pipe is ready to send commands, `false` otherwise
  internal var isCmdPipeReady: Bool {
    guard let cmdFd = cmdFd else {
      return false
    }

    #if os(Windows)
      return cmdFd != INVALID_SOCKET
    #else
      return cmdFd >= 0
    #endif
  }

  /// Gets the name of the TUN/TAP interface that was assigned.
  ///
  /// This is only available after the TUN device has been set up successfully.
  ///
  /// - Returns: The interface name (e.g., "tun0", "utun0"), or `nil` if not yet set up
  internal var assignedInterfaceName: String? {
    guard let vpnInfo = self.vpnInfo else {
      return nil
    }

    guard let ifnamePtr = openconnect_get_ifname(vpnInfo) else {
      return nil
    }

    return String(cString: ifnamePtr)
  }

  /// Indicates whether the mainloop is currently running.
  ///
  /// The mainloop runs on a background thread and handles VPN traffic routing.
  /// This property is thread-safe.
  ///
  /// - Returns: `true` if the mainloop is running, `false` otherwise
  internal var mainloopRunning: Bool {
    mainloopLock.lock()
    defer { mainloopLock.unlock() }
    return isMainloopRunning
  }
}
