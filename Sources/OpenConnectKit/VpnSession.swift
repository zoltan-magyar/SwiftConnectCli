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
}
