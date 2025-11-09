//
//  LogLevel.swift
//  OpenConnectKit
//
//  Log level enumeration for VPN session messages
//

import Foundation

/// Log level for VPN session messages.
///
/// Controls the verbosity of logging output from the VPN session.
/// Higher levels include messages from lower levels (e.g., `.debug` includes `.info` and `.error`).
public enum LogLevel: String, Sendable {
  /// Error messages only - critical issues that prevent operation.
  case error

  /// Informational messages - normal operation events.
  case info

  /// Debug messages - detailed information for troubleshooting.
  case debug

  /// Verbose trace messages - extremely detailed execution flow.
  case trace

  /// Converts to OpenConnect's internal log level representation.
  internal var openConnectLevel: Int32 {
    switch self {
    case .error: return 0
    case .info: return 1
    case .debug: return 2
    case .trace: return 3
    }
  }
}
