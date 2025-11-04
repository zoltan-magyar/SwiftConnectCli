//
//  Progress.swift
//  SwiftConnectCli
//
//  Created by Zoltán Magyar on 2025. 10. 27..
//

import COpenConnect
import Foundation

func progressCallback(
    privdata: UnsafeMutableRawPointer?, level: CInt, fmt: UnsafePointer<CChar>?,
    args: CVaListPointer?
) {
    guard let fmt = fmt else { return }
    guard let args = args else { return }

    // Format the message using vsnprintf
    // Create a buffer for the formatted string
    let bufferSize = 4096
    var buffer = [CChar](repeating: 0, count: bufferSize)

    // Format the string with the variadic arguments
    let written = vsnprintf(&buffer, bufferSize, fmt, args)

    // Check if the message was truncated
    let message: String
    if written >= bufferSize {
        // Message was truncated, add indicator
        buffer[bufferSize - 4] = 46  // '.'
        buffer[bufferSize - 3] = 46  // '.'
        buffer[bufferSize - 2] = 46  // '.'
        buffer[bufferSize - 1] = 0  // null terminator
        message = String(cString: buffer)
    } else if written >= 0 {
        // Success - convert to Swift String
        message = String(cString: buffer)
    } else {
        // Error occurred
        message = "[Error formatting message]"
    }

    // Print with appropriate prefix based on log level
    // OpenConnect log levels: PRG_ERR=0, PRG_INFO=1, PRG_DEBUG=2, PRG_TRACE=3
    let prefix: String
    switch level {
    case 0:
        prefix = "ERROR: "
    case 1:
        prefix = "INFO: "
    case 2:
        prefix = "DEBUG: "
    case 3:
        prefix = "TRACE: "
    default:
        prefix = "LOG[\(level)]: "
    }

    print("\(prefix)\(message)")
}

func registerCallback() {
    register_progress_callback(progressCallback)
}
