//
//  VpnSession+Async.swift
//  OpenConnectKit
//
//  Async/Await support for VpnSession
//

import Foundation

// MARK: - Async VPN Session Wrapper

/// Async/await wrapper for VpnSession.
///
/// This type provides a safe async interface to VpnSession that's explicitly
/// separate from the callback-based API, preventing accidental conflicts.
///
/// ## Usage
///
/// ```swift
/// let session = VpnSession(configuration: config)
/// let asyncSession = session.async
///
/// Task {
///     for await status in asyncSession.statusUpdates {
///         print("Status: \(status)")
///     }
/// }
/// ```
///
/// **Important**: Don't mix callback and async APIs. Choose one style:
/// - Use `session.onStatusChanged = { }` for callbacks
/// - Use `session.async.statusUpdates` for async/await
@MainActor
public final class AsyncVpnSession: Sendable {
  private let session: VpnSession

  internal init(session: VpnSession) {
    self.session = session
  }

  // MARK: - Async Streams

  /// Stream of connection status updates.
  ///
  /// ```swift
  /// for await status in asyncSession.statusUpdates {
  ///     switch status {
  ///     case .connected:
  ///         print("Connected!")
  ///     case .disconnected(let error):
  ///         print("Disconnected: \(error?.localizedDescription ?? "user initiated")")
  ///     default:
  ///         break
  ///     }
  /// }
  /// ```
  public var statusUpdates: AsyncStream<ConnectionStatus> {
    AsyncStream { continuation in
      session.onStatusChanged = { status in
        continuation.yield(status)
      }
      continuation.onTermination = { @Sendable [weak session] _ in
        session?.onStatusChanged = nil
      }
    }
  }

  /// Stream of log messages with their levels.
  ///
  /// ```swift
  /// for await (message, level) in asyncSession.logMessages {
  ///     print("[\(level)] \(message)")
  /// }
  /// ```
  public var logMessages: AsyncStream<(message: String, level: LogLevel)> {
    AsyncStream { continuation in
      session.onLog = { message, level in
        continuation.yield((message, level))
      }
      continuation.onTermination = { @Sendable [weak session] _ in
        session?.onLog = nil
      }
    }
  }

  /// Stream of traffic statistics.
  ///
  /// Statistics are yielded when `requestStats()` is called on the underlying session.
  ///
  /// ```swift
  /// for await stats in asyncSession.statisticsUpdates {
  ///     print("TX: \(stats.formattedTxBytes), RX: \(stats.formattedRxBytes)")
  /// }
  /// ```
  public var statisticsUpdates: AsyncStream<VpnStats> {
    AsyncStream { continuation in
      session.onStats = { stats in
        continuation.yield(stats)
      }
      continuation.onTermination = { @Sendable [weak session] _ in
        session?.onStats = nil
      }
    }
  }

  // MARK: - Connection Control

  /// Connects to the VPN server.
  ///
  /// - Throws: `VpnError` if connection fails
  public func connect() throws {
    try session.connect()
  }

  /// Disconnects from the VPN server.
  public func disconnect() {
    session.disconnect()
  }

  /// Requests traffic statistics from the VPN connection.
  ///
  /// Statistics will be delivered via `statisticsUpdates` stream.
  ///
  /// - Returns: `true` if the request was sent successfully
  @discardableResult
  public func requestStats() -> Bool {
    session.requestStats()
  }

  // MARK: - Properties

  /// The current connection status.
  public var connectionStatus: ConnectionStatus {
    session.connectionStatus
  }

  /// The name of the network interface assigned to the VPN tunnel.
  ///
  /// This property returns the interface name (e.g., "tun0", "utun0") after
  /// the TUN device has been successfully set up. Returns `nil` before connection
  /// or if the TUN device hasn't been configured yet.
  ///
  /// **Important**: The interface name becomes available only when the connection
  /// status changes to `.connected`. Wait for the `statusUpdates` stream to emit
  /// `.connected` before accessing this property.
  ///
  /// ## Example Usage
  ///
  /// ```swift
  /// for await status in asyncSession.statusUpdates {
  ///     if case .connected = status {
  ///         if let ifname = asyncSession.interfaceName {
  ///             print("Interface: \(ifname)")
  ///         }
  ///     }
  /// }
  /// ```
  public var interfaceName: String? {
    session.interfaceName
  }

  /// The configuration for this VPN session.
  public var configuration: VpnConfiguration {
    session.configuration
  }

  // MARK: - Authentication Handlers

  /// Handler for certificate validation requests.
  ///
  /// Return `true` to accept the certificate, `false` to reject it.
  public var onCertificateValidation: ((CertificateInfo) -> Bool)? {
    get { session.onCertificateValidation }
    set { session.onCertificateValidation = newValue }
  }

  /// Handler for authentication form requests.
  ///
  /// Modify and return the form with filled-in field values.
  public var onAuthenticationRequired: ((AuthenticationForm) -> AuthenticationForm)? {
    get { session.onAuthenticationRequired }
    set { session.onAuthenticationRequired = newValue }
  }
}

// MARK: - VpnSession Extension

extension VpnSession {
  /// Returns an async/await interface for this VPN session.
  ///
  /// Use this property to access async streams instead of callbacks.
  /// This provides a type-safe way to use async/await without conflicting
  /// with the callback-based API.
  ///
  /// ## Example
  ///
  /// ```swift
  /// let session = VpnSession(configuration: config)
  ///
  /// // Async/await style
  /// Task {
  ///     for await status in session.async.statusUpdates {
  ///         print("Status: \(status)")
  ///     }
  /// }
  /// ```
  ///
  /// **Important**: Choose either callbacks OR async/await, not both:
  /// - Callbacks: `session.onStatusChanged = { }`
  /// - Async/await: `session.async.statusUpdates`
  @MainActor
  public var async: AsyncVpnSession {
    AsyncVpnSession(session: self)
  }
}
