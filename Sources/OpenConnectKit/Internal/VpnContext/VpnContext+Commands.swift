//
//  VpnContext+Commands.swift
//  OpenConnectKit
//
//  Command sending extension for VpnContext
//

import COpenConnect
import Foundation

#if os(Windows)
  import WinSDK
#endif

// MARK: - Command Sending

extension VpnContext {
  // Send command byte to mainloop via cmd_fd
  @discardableResult
  internal func sendCommand(_ command: Command) -> Bool {
    var commandByte = command.rawValue

    #if os(Windows)
      // Windows: Use send() for socket
      let result = send(cmdFd, &commandByte, 1, 0)
      return result == 1
    #else
      // Unix/Linux/macOS: Use write() for file descriptor
      let result = write(cmdFd, &commandByte, 1)
      return result == 1
    #endif
  }

  // Request stats via OC_CMD_STATS
  @discardableResult
  internal func requestStats() -> Bool {
    return sendCommand(.stats)
  }
}
