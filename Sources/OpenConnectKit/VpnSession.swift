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
/// ## Example Usage
///
/// ```swift
/// let config = VpnConfiguration(
///     serverURL: URL(string: "https://vpn.example.com")!
/// )
///
/// let session = VpnSession(configuration: config)
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
public class VpnSession {
    // MARK: - Public Properties

    /// The configuration for this VPN session.
    public let configuration: VpnConfiguration

    /// Whether the VPN is currently connected.
    public private(set) var isConnected: Bool = false

    /// The name of the network interface assigned to the VPN tunnel.
    ///
    /// This property returns the interface name (e.g., "tun0", "utun0") after
    /// the TUN device has been successfully set up. Returns `nil` before connection
    /// or if the TUN device hasn't been configured yet.
    public var interfaceName: String? {
        return context?.assignedInterfaceName
    }

    /// Whether the OpenConnect mainloop is currently running.
    ///
    /// The mainloop handles VPN traffic routing and runs on a background thread.
    /// This will be `true` after successful connection and `false` when disconnected
    /// or if the connection hasn't been established yet.
    public var isMainloopRunning: Bool {
        return context?.mainloopRunning ?? false
    }

    // MARK: - Callback Handlers

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

    /// Called when the VPN connection is automatically reconnected.
    ///
    /// This callback is triggered when OpenConnect successfully reconnects
    /// after a connection loss (e.g., network interruption, server restart).
    /// It will not be called on the initial connection, only on reconnections.
    ///
    /// If not set, reconnection events are silently ignored.
    public var onReconnected: (() -> Void)?

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
        guard !isConnected else {
            return
        }

        if context == nil {
            context = try VpnContext(session: self, configuration: configuration)
        }

        try context?.connect()

        isConnected = true
    }

    /// Disconnects from the VPN server.
    public func disconnect() {
        guard isConnected else {
            return
        }

        context?.disconnect()
        context = nil
        isConnected = false
    }

    /// Requests traffic statistics from the VPN connection.
    ///
    /// This method sends a command to the mainloop to gather and report
    /// current traffic statistics. The statistics will be delivered via
    /// the `onStats` callback (configured in Step 6).
    ///
    /// Statistics include:
    /// - Bytes sent/received
    /// - Packets sent/received
    ///
    /// - Returns: `true` if the request was sent successfully, `false` otherwise
    @discardableResult
    public func requestStats() -> Bool {
        guard isConnected else {
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
    /// - Returns: The filled form
    internal func handleAuthenticationForm(_ form: AuthenticationForm) -> AuthenticationForm {
        if let handler = onAuthenticationRequired {
            return handler(form)
        } else {
            // Attempt to use credentials from configuration
            var filledForm = form

            for (index, field) in filledForm.fields.enumerated() {
                switch field.type {
                case .text:
                    if field.label.lowercased().contains("user"),
                        let username = configuration.username
                    {
                        filledForm.fields[index].value = username
                    }
                case .password:
                    if let password = configuration.password {
                        filledForm.fields[index].value = password
                    }
                default:
                    break
                }
            }

            return filledForm
        }
    }

    /// Handles reconnection notification from OpenConnect.
    ///
    /// This is called by the internal context when OpenConnect successfully
    /// reconnects after a connection loss.
    internal func handleReconnected() {
        onReconnected?()
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
}
