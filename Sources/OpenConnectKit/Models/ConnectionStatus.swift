//
//  ConnectionStatus.swift
//  OpenConnectKit
//
//  Connection status types for VPN sessions
//

import Foundation

/// Represents the current status of a VPN connection.
///
/// This enum provides a type-safe way to track the connection lifecycle,
/// including any errors that caused disconnection and progress messages
/// during connection establishment.
///
/// ## Example Usage
///
/// ```swift
/// switch session.connectionStatus {
/// case .disconnected(let error):
///     if let error = error {
///         print("Disconnected due to error: \(error)")
///     } else {
///         print("Disconnected normally")
///     }
/// case .connecting(let stage):
///     print("Connecting: \(stage)")
/// case .connected:
///     print("Connected successfully")
/// case .reconnecting:
///     print("Attempting to reconnect...")
/// }
/// ```
public enum ConnectionStatus: Equatable {
  /// The VPN is disconnected.
  ///
  /// The associated `VpnError` indicates why the disconnection occurred:
  /// - `nil` - User initiated disconnect or normal disconnection
  /// - Non-nil - Connection failed or was interrupted due to an error
  ///
  /// - Parameter error: Optional error that caused the disconnection
  case disconnected(error: VpnError?)

  /// The VPN is in the process of connecting.
  ///
  /// The associated string provides details about the current connection stage,
  /// such as:
  /// - "Authenticating..."
  /// - "Establishing CSTP connection"
  /// - "Setting up DTLS"
  /// - "Configuring tunnel"
  ///
  /// This allows for flexible progress reporting without requiring a fixed
  /// set of connection stages.
  ///
  /// - Parameter stage: Human-readable description of the current connection stage
  case connecting(stage: String)

  /// The VPN is fully connected and the mainloop is running.
  ///
  /// In this state, traffic is being routed through the VPN tunnel and
  /// the connection is actively maintained.
  case connected

  /// The VPN is attempting to reconnect after a connection loss.
  ///
  /// This state indicates that the connection was lost (e.g., due to network
  /// interruption) and OpenConnect is automatically attempting to re-establish
  /// the connection. This is different from the initial connection process.
  case reconnecting

  // MARK: - Convenience Properties

  /// Whether the VPN is currently connected.
  ///
  /// Returns `true` only when the status is `.connected`.
  public var isConnected: Bool {
    if case .connected = self {
      return true
    }
    return false
  }

  /// Whether the VPN is currently disconnected.
  ///
  /// Returns `true` when the status is `.disconnected`, regardless of
  /// whether an error caused the disconnection.
  public var isDisconnected: Bool {
    if case .disconnected = self {
      return true
    }
    return false
  }

  /// Whether the VPN is currently in a connecting state.
  ///
  /// Returns `true` for both `.connecting` and `.reconnecting` states.
  public var isConnecting: Bool {
    switch self {
    case .connecting, .reconnecting:
      return true
    default:
      return false
    }
  }

  /// The error associated with a disconnected state, if any.
  ///
  /// Returns the error if the status is `.disconnected(error:)` and an error is present.
  /// Returns `nil` for all other states or if the disconnection was intentional.
  public var error: VpnError? {
    if case .disconnected(let error) = self {
      return error
    }
    return nil
  }

  /// A human-readable description of the current status.
  ///
  /// Useful for logging or displaying status to users.
  public var description: String {
    switch self {
    case .disconnected(let error):
      if let error = error {
        return "Disconnected: \(error.localizedDescription)"
      } else {
        return "Disconnected"
      }
    case .connecting(let stage):
      return "Connecting: \(stage)"
    case .connected:
      return "Connected"
    case .reconnecting:
      return "Reconnecting..."
    }
  }
}

// MARK: - Equatable Conformance

extension ConnectionStatus {
  public static func == (lhs: ConnectionStatus, rhs: ConnectionStatus) -> Bool {
    switch (lhs, rhs) {
    case (.disconnected(let lhsError), .disconnected(let rhsError)):
      // Compare errors by their localized description since VpnError doesn't conform to Equatable
      return lhsError?.localizedDescription == rhsError?.localizedDescription
    case (.connecting(let lhsStage), .connecting(let rhsStage)):
      return lhsStage == rhsStage
    case (.connected, .connected):
      return true
    case (.reconnecting, .reconnecting):
      return true
    default:
      return false
    }
  }
}
