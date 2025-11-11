//
//  VpnSession.swift
//  OpenConnectKit
//
//  Main public API for VPN sessions
//

import Foundation

/// Manages VPN connections using the OpenConnect protocol.
///
/// `VpnSession` provides a Swift-native API for establishing and managing
/// OpenConnect VPN connections. All C interop is handled internally, exposing
/// a clean, type-safe interface.
///
/// **Thread Safety**: All methods are thread-safe. Callbacks may be invoked on
/// background threads - use `DispatchQueue.main.async` when updating UI.
///
/// ## Example Usage
///
/// ```swift
/// let config = VpnConfiguration(
///     serverURL: URL(string: "https://vpn.example.com")!
/// )
///
/// let session = VpnSession(configuration: config)
///
/// session.onStatusChanged = { status in
///     switch status {
///     case .disconnected(let error):
///         print("Disconnected: \(error?.localizedDescription ?? "user initiated")")
///     case .connecting(let stage):
///         print("Connecting: \(stage)")
///     case .connected:
///         print("Connected!")
///     case .reconnecting:
///         print("Reconnecting...")
///     }
/// }
///
/// session.onLog = { message, level in
///     print("[\(level)] \(message)")
/// }
///
/// session.onCertificateValidation = { certInfo in
///     return true  // Accept certificate
/// }
///
/// try session.connect()
/// ```
public class VpnSession: @unchecked Sendable {
  // MARK: - Public Properties

  /// The configuration for this VPN session.
  public let configuration: VpnConfiguration

  /// The current connection status of the VPN session.
  ///
  /// This property provides detailed information about the connection state,
  /// including any errors that caused disconnection and progress messages
  /// during connection establishment.
  ///
  /// Use the `onStatusChanged` callback to receive real-time updates when
  /// the status changes.
  public var connectionStatus: ConnectionStatus {
    return context?.status ?? .disconnected(error: nil)
  }

  /// The name of the network interface assigned to the VPN tunnel.
  ///
  /// This property returns the interface name (e.g., "tun0", "utun0") after
  /// the TUN device has been successfully set up. Returns `nil` before connection
  /// or if the TUN device hasn't been configured yet.
  ///
  /// **Important**: The interface name becomes available only when the connection
  /// status changes to `.connected`. During the `connect()` call, the TUN device
  /// setup happens asynchronously in a background thread. To access the interface
  /// name reliably, wait for the `onStatusChanged` callback to report `.connected`
  /// status.
  ///
  /// ## Example Usage
  ///
  /// ```swift
  /// session.onStatusChanged = { status in
  ///     if case .connected = status {
  ///         if let ifname = session.interfaceName {
  ///             print("Interface: \(ifname)")
  ///         }
  ///     }
  /// }
  /// ```
  public var interfaceName: String? {
    return context?.assignedInterfaceName
  }

  // MARK: - Callback Handlers

  /// Called when the connection status changes.
  ///
  /// This callback provides real-time updates about the connection lifecycle,
  /// including:
  /// - Connection progress during establishment (e.g., "Authenticating...", "Setting up DTLS")
  /// - Successful connection
  /// - Disconnection (with optional error information)
  /// - Reconnection attempts
  ///
  /// ## Example Usage
  ///
  /// ```swift
  /// session.onStatusChanged = { status in
  ///     switch status {
  ///     case .disconnected(let error):
  ///         if let error = error {
  ///             print("Disconnected with error: \(error)")
  ///         } else {
  ///             print("Disconnected normally")
  ///         }
  ///     case .connecting(let stage):
  ///         print("Progress: \(stage)")
  ///     case .connected:
  ///         print("Successfully connected!")
  ///     case .reconnecting:
  ///         print("Connection lost, reconnecting...")
  ///     }
  /// }
  /// ```
  ///
  /// If not set, status changes are silently ignored.
  ///
  /// - Parameter status: The new connection status
  public var onStatusChanged: ((ConnectionStatus) -> Void)?

  /// Called when the server certificate needs validation.
  ///
  /// Return `true` to accept the certificate, `false` to reject it.
  /// If not set, uses `configuration.allowInsecureCertificates`.
  ///
  /// - Parameter certInfo: Information about the certificate to validate
  /// - Returns: `true` to accept, `false` to reject
  public var onCertificateValidation: ((CertificateInfo) -> Bool)?

  /// Called when an authentication form needs to be filled.
  ///
  /// Modify and return the form with filled-in field values.
  /// If not set, attempts to use credentials from `configuration`.
  ///
  /// - Parameter form: The authentication form to fill
  /// - Returns: The form with filled field values
  public var onAuthenticationRequired: ((AuthenticationForm) -> AuthenticationForm)?

  /// Called for log messages from the VPN session.
  ///
  /// If not set, log messages are silently ignored.
  ///
  /// - Parameters:
  ///   - message: The log message
  ///   - level: The log level
  public var onLog: ((String, LogLevel) -> Void)?

  /// Called when traffic statistics are received.
  ///
  /// This callback is triggered when statistics are requested via `requestStats()`
  /// and the mainloop reports the current traffic data. Statistics include:
  /// - Bytes and packets transmitted (sent)
  /// - Bytes and packets received
  ///
  /// Statistics are cumulative since the connection was established.
  ///
  /// If not set, statistics are silently ignored.
  ///
  /// - Parameter stats: Current VPN traffic statistics
  public var onStats: ((VpnStats) -> Void)?

  // MARK: - Internal Properties

  /// Internal context managing the OpenConnect connection.
  internal private(set) var context: VpnContext?

  // MARK: - Initialization

  /// Creates a new VPN session with the given configuration.
  ///
  /// - Parameter configuration: The VPN configuration
  public init(configuration: VpnConfiguration) {
    self.configuration = configuration
  }

  deinit {
    disconnect()
  }

  // MARK: - Public Methods

  /// Connects to the VPN server.
  ///
  /// This method performs the following steps:
  /// 1. Parses the server URL
  /// 2. Obtains an authentication cookie (may trigger `onAuthenticationRequired`)
  /// 3. Establishes the CSTP connection
  /// 4. Sets up DTLS for the data channel
  ///
  /// - Throws: `VpnError` if connection fails at any step
  public func connect() throws {
    guard case .disconnected = connectionStatus else {
      throw VpnError.alreadyConnected
      return
    }

    if context == nil {
      context = try VpnContext(session: self)
    }

    try context?.connect()
  }

  /// Disconnects from the VPN server.
  public func disconnect() {
    // Only proceed if NOT already disconnected
    if case .disconnected = connectionStatus {
      return
    }

    context?.disconnect()
    context = nil
  }

  /// Requests traffic statistics from the VPN connection.
  ///
  /// This method sends a command to the mainloop to gather and report
  /// current traffic statistics. The statistics will be delivered via
  /// the `onStats` callback.
  ///
  /// Statistics include:
  /// - Bytes sent/received
  /// - Packets sent/received
  ///
  /// - Returns: `true` if the request was sent successfully, `false` otherwise
  @discardableResult
  public func requestStats() -> Bool {
    guard case .connected = connectionStatus else {
      return false
    }

    return context?.requestStats() ?? false
  }

  // MARK: - Internal Methods

  /// Handles progress logging from OpenConnect.
  ///
  /// - Parameters:
  ///   - level: The log level
  ///   - message: The log message
  internal func handleProgress(level: LogLevel, message: String) {
    onLog?(message, level)
  }

  /// Handles certificate validation requests from OpenConnect.
  ///
  /// - Parameter certInfo: Information about the certificate
  /// - Returns: `true` to accept, `false` to reject
  internal func handleCertificateValidation(certInfo: CertificateInfo) -> Bool {
    if let handler = onCertificateValidation {
      return handler(certInfo)
    } else {
      return configuration.allowInsecureCertificates
    }
  }

  /// Handles authentication form requests from OpenConnect.
  ///
  /// - Parameter form: The authentication form to fill
  /// - Returns: The filled form, or the original form if no handler is set
  internal func handleAuthenticationForm(_ form: AuthenticationForm) -> AuthenticationForm {
    guard let handler = onAuthenticationRequired else {
      // No handler provided - return the form unchanged
      // The caller is responsible for setting onAuthenticationRequired
      return form
    }

    return handler(form)
  }

  /// Handles statistics notification from OpenConnect.
  ///
  /// This is called by the internal context when statistics are received
  /// from the mainloop.
  ///
  /// - Parameter stats: The VPN traffic statistics
  internal func handleStats(_ stats: VpnStats) {
    onStats?(stats)
  }

  /// Handles connection status changes from OpenConnect.
  ///
  /// This is called by the internal context whenever the connection status changes.
  ///
  /// - Parameter status: The new connection status
  internal func handleStatusChange(status: ConnectionStatus) {
    onStatusChanged?(status)
  }
}
