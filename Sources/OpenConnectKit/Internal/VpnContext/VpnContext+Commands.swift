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
    /// Sends a command byte to the mainloop via cmd_fd.
    ///
    /// This method writes a single byte command to the command pipe, which
    /// the mainloop monitors. Commands are processed asynchronously.
    ///
    /// Available commands:
    /// - `OC_CMD_CANCEL` (0x78) - Close connections, log off, and shut down
    /// - `OC_CMD_PAUSE` (0x70) - Pause the connection temporarily
    /// - `OC_CMD_DETACH` (0x64) - Detach from the connection
    /// - `OC_CMD_STATS` (0x73) - Request traffic statistics
    ///
    /// The method uses platform-specific I/O operations:
    /// - **Windows**: Uses `send()` for socket operations
    /// - **Unix/Linux/macOS**: Uses `write()` for file descriptor operations
    ///
    /// - Parameter command: The command byte to send
    /// - Returns: `true` if the command was sent successfully, `false` otherwise
    @discardableResult
    internal func sendCommand(_ command: UInt8) -> Bool {
        guard let cmdFd = cmdFd else {
            return false
        }

        var commandByte = command

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

    /// Requests traffic statistics from the mainloop.
    ///
    /// This method sends the `OC_CMD_STATS` command to the mainloop, which
    /// will trigger the stats callback (configured during initialization).
    /// The statistics include:
    /// - Bytes transmitted (sent)
    /// - Bytes received
    /// - Packets transmitted
    /// - Packets received
    ///
    /// Statistics are cumulative since the connection was established and
    /// persist across reconnections during the same session.
    ///
    /// - Returns: `true` if the command was sent successfully, `false` otherwise
    @discardableResult
    internal func requestStats() -> Bool {
        return sendCommand(VpnContext.OC_CMD_STATS)
    }
}
