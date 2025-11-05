//
//  VpnConfiguration.swift
//  OpenConnectKit
//
//  Configuration for VPN sessions
//

import Foundation

/// Configuration for establishing a VPN connection.
///
/// Use this structure to specify all settings for a VPN session, including
/// server details, protocol, credentials, and security preferences.
///
/// ## Example
///
/// ```swift
/// let config = VpnConfiguration(
///     serverURL: URL(string: "https://vpn.example.com")!,
///     vpnProtocol: .anyConnect,
///     logLevel: .info,
///     username: "user@example.com"
/// )
/// ```
public struct VpnConfiguration: Sendable {
    // MARK: - Properties

    /// The VPN server URL (e.g., `https://vpn.example.com`).
    public var serverURL: URL

    /// The VPN protocol to use.
    public var vpnProtocol: VpnProtocol

    /// Log level for VPN messages.
    public var logLevel: LogLevel

    /// Whether to allow connections with invalid or self-signed certificates.
    ///
    /// Default is `false` (reject invalid certificates).
    /// Set to `true` only for testing or when you trust the server.
    public var allowInsecureCertificates: Bool

    /// Optional username for authentication.
    public var username: String?

    /// Optional password for authentication.
    ///
    /// - Note: The password will be cleared from memory after use.
    public var password: String?

    // MARK: - Initialization

    /// Creates a VPN configuration.
    ///
    /// - Parameters:
    ///   - serverURL: The VPN server URL
    ///   - vpnProtocol: The VPN protocol (default: `.anyConnect`)
    ///   - logLevel: The log level (default: `.info`)
    ///   - allowInsecureCertificates: Whether to allow invalid certificates (default: `false`)
    ///   - username: Optional username
    ///   - password: Optional password
    public init(
        serverURL: URL,
        vpnProtocol: VpnProtocol = .anyConnect,
        logLevel: LogLevel = .info,
        allowInsecureCertificates: Bool = false,
        username: String? = nil,
        password: String? = nil
    ) {
        self.serverURL = serverURL
        self.vpnProtocol = vpnProtocol
        self.logLevel = logLevel
        self.allowInsecureCertificates = allowInsecureCertificates
        self.username = username
        self.password = password
    }
}

// MARK: - VpnProtocol

/// Supported VPN protocols.
public enum VpnProtocol: String, Sendable, CaseIterable {
    /// Cisco AnyConnect
    case anyConnect = "anyconnect"

    /// Palo Alto Networks GlobalProtect
    case globalProtect = "gp"

    /// Pulse Secure
    case pulse = "pulse"

    /// Juniper Network Connect
    case nc = "nc"

    /// Array Networks SSL VPN
    case array = "array"
}
