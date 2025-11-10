//
//  SecureInput.swift
//  SwiftConnectCli
//
//  Cross-platform secure input utility for reading passwords without echo
//

import Foundation

#if os(Windows)
  import WinSDK
#elseif canImport(Darwin)
  import Darwin
#elseif canImport(Glibc)
  import Glibc
#endif

// Utility for securely reading sensitive input from the terminal.
// Provides cross-platform support for reading passwords without echo.
enum SecureInput {

  // Reads a line of input from the terminal with echo disabled.
  // Returns the input string, or nil if reading failed or input was empty.
  static func read(prompt: String) -> String? {
    #if os(Windows)
      return readSecureWindows(prompt: prompt)
    #else
      return readSecureUnix(prompt: prompt)
    #endif
  }

  #if os(Windows)
    // Windows-specific implementation using Console API.
    private static func readSecureWindows(prompt: String) -> String? {
      // Display the prompt
      print(prompt, terminator: "")
      fflush(stdout)

      // Get the console input handle
      let handle = GetStdHandle(STD_INPUT_HANDLE)
      guard handle != INVALID_HANDLE_VALUE else {
        print("\nError: Could not get console handle")
        return nil
      }

      // Get current console mode
      var originalMode: DWORD = 0
      guard GetConsoleMode(handle, &originalMode) != 0 else {
        print("\nError: Could not get console mode")
        return nil
      }

      // Disable echo input
      let newMode = originalMode & ~DWORD(ENABLE_ECHO_INPUT)
      guard SetConsoleMode(handle, newMode) != 0 else {
        print("\nError: Could not disable echo")
        return nil
      }

      // Ensure console mode is restored even if reading fails
      defer {
        SetConsoleMode(handle, originalMode)
        // Print newline since user's Enter wasn't echoed
        print()
      }

      // Read the input
      guard let input = readLine() else {
        return nil
      }

      // Return nil if input is empty
      return input.isEmpty ? nil : input
    }
  #else
    // Unix-like systems implementation using termios.
    private static func readSecureUnix(prompt: String) -> String? {
      // Display the prompt
      print(prompt, terminator: "")
      fflush(stdout)

      // Get current terminal attributes
      var originalTermios = termios()
      guard tcgetattr(STDIN_FILENO, &originalTermios) == 0 else {
        print("\nError: Could not get terminal attributes")
        return nil
      }

      // Create modified attributes with echo disabled
      var newTermios = originalTermios
      #if os(Linux)
        newTermios.c_lflag &= ~UInt32(ECHO)
      #else
        newTermios.c_lflag &= ~UInt(ECHO)
      #endif

      // Apply the new attributes
      guard tcsetattr(STDIN_FILENO, TCSANOW, &newTermios) == 0 else {
        print("\nError: Could not disable echo")
        return nil
      }

      // Ensure terminal attributes are restored even if reading fails
      defer {
        tcsetattr(STDIN_FILENO, TCSANOW, &originalTermios)
        // Print newline since user's Enter wasn't echoed
        print()
      }

      // Read the input
      guard let input = readLine() else {
        return nil
      }

      // Return nil if input is empty
      return input.isEmpty ? nil : input
    }
  #endif

  // Reads a password with a default prompt.
  static func readPassword() -> String? {
    return read(prompt: "Password: ")
  }

  // Reads a password with confirmation.
  // Returns the password if both entries match, nil otherwise.
  static func readPasswordWithConfirmation(
    prompt: String = "Password: ",
    confirmPrompt: String = "Confirm password: "
  ) -> String? {
    guard let password = read(prompt: prompt) else {
      return nil
    }

    guard let confirmation = read(prompt: confirmPrompt) else {
      return nil
    }

    guard password == confirmation else {
      print("Passwords do not match")
      return nil
    }

    return password
  }
}
