//
//  PrivilegeChecker.swift
//  SwiftConnectCli
//
//  Cross-platform privilege checking utility
//

import Foundation

#if os(Windows)
  import WinSDK
#elseif canImport(Darwin)
  import Darwin
#elseif canImport(Glibc)
  import Glibc
#endif

// Utility for checking if the current process has elevated privileges.
// Provides cross-platform support for detecting elevated privileges.
enum PrivilegeChecker {

  // Error thrown when elevated privileges are required but not present.
  struct InsufficientPrivilegesError: Error, CustomStringConvertible {
    let description: String

    init() {
      #if os(Windows)
        self.description = "This application requires Administrator privileges"
      #else
        self.description = "This application requires elevated privileges (root)"
      #endif
    }
  }

  // Checks if the current process has elevated privileges.
  // Returns true if the process has elevated privileges, false otherwise.
  static func hasElevatedPrivileges() -> Bool {
    #if os(Windows)
      return hasWindowsAdminPrivileges()
    #else
      return geteuid() == 0
    #endif
  }

  // Requires elevated privileges, throwing an error if not present.
  // Throws InsufficientPrivilegesError if privileges are insufficient.
  static func requireElevatedPrivileges() throws {
    guard hasElevatedPrivileges() else {
      print("\n❌ Error: This application requires elevated privileges\n")
      printElevationInstructions()
      throw InsufficientPrivilegesError()
    }
  }

  // Prints platform-specific instructions for running with elevated privileges.
  static func printElevationInstructions() {
    #if os(Windows)
      printWindowsInstructions()
    #else
      printUnixInstructions()
    #endif
  }

  #if os(Windows)
    // Checks if the current process has Administrator privileges on Windows.
    // Uses the Windows Security API to check the process token.
    private static func hasWindowsAdminPrivileges() -> Bool {
      var isAdmin = false

      // Get process token
      var token: HANDLE? = nil
      guard OpenProcessToken(GetCurrentProcess(), TOKEN_QUERY, &token) != 0,
        let processToken = token
      else {
        return false
      }
      defer { CloseHandle(processToken) }

      // Get token elevation information
      var elevation = TOKEN_ELEVATION()
      var returnLength: DWORD = 0

      let success = GetTokenInformation(
        processToken,
        TokenElevation,
        &elevation,
        DWORD(MemoryLayout<TOKEN_ELEVATION>.size),
        &returnLength
      )

      if success != 0 {
        isAdmin = elevation.TokenIsElevated != 0
      }

      return isAdmin
    }

    // Prints Windows-specific elevation instructions.
    private static func printWindowsInstructions() {
      print("To run with Administrator privileges:\n")
      print("Option 1: Right-click the executable and select 'Run as administrator'\n")
      print("Option 2: Open Command Prompt as Administrator and run the command\n")
      print("OpenConnect needs elevated privileges to:")
      print("  • Create TUN/TAP network devices")
      print("  • Modify routing tables")
      print("  • Configure DNS settings")
      print()
    }
  #else
    // Prints Unix-style elevation instructions.
    private static func printUnixInstructions() {
      let commandLine = CommandLine.arguments.joined(separator: " ")

      print("To run with elevated privileges:\n")
      print("  sudo \(commandLine)\n")
      print("OpenConnect needs elevated privileges to:")
      print("  • Create TUN/TAP network devices")
      print("  • Modify routing tables")
      print("  • Configure DNS settings")
      print()

      // Additional helpful information
      if getuid() != 0 {
        print("Note: You are currently running as user '\(getUsername())'")
        print("      You will be prompted for your password when using sudo")
        print()
      }
    }

    // Gets the current username.
    private static func getUsername() -> String {
      if let username = getenv("USER") {
        return String(cString: username)
      } else if let username = getenv("LOGNAME") {
        return String(cString: username)
      } else {
        return "uid \(getuid())"
      }
    }
  #endif

  // Checks if running with elevated privileges and prints a warning if not.
  // Returns true if elevated, false otherwise (after printing warning).
  static func checkAndWarnIfNotElevated() -> Bool {
    if hasElevatedPrivileges() {
      return true
    }

    print("\n⚠️  Warning: Not running with elevated privileges\n")
    printElevationInstructions()
    print("Some operations may fail without elevated privileges.")
    print()

    return false
  }
}
