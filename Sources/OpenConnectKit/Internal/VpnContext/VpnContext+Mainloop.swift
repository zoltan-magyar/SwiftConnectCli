//
//  VpnContext+Mainloop.swift
//  OpenConnectKit
//
//  Mainloop management extension for VpnContext
//

import COpenConnect
import Foundation

// MARK: - Mainloop Management

extension VpnContext {
  /// Runs the OpenConnect mainloop on a background thread.
  ///
  /// The mainloop handles:
  /// - Packet routing through the TUN device
  /// - Automatic reconnection on connection loss
  /// - Monitoring cmd_fd for control commands
  /// - DTLS keepalive and DPD (Dead Peer Detection)
  ///
  /// This method starts the mainloop in a background thread and returns immediately.
  /// The mainloop will continue running until:
  /// - A command is sent via cmd_fd (e.g., OC_CMD_CANCEL)
  /// - The remote server disconnects
  /// - An unrecoverable error occurs
  internal func startMainloop() {
    mainloopLock.lock()
    defer { mainloopLock.unlock() }

    // Don't start if already running
    guard !isMainloopRunning else {
      return
    }

    isMainloopRunning = true

    // Create and start the mainloop thread
    mainloopThread = Thread { [weak self] in
      guard let self = self else { return }
      self.runMainloopThread()
    }
    mainloopThread?.name = "com.openconnect.mainloop"
    mainloopThread?.start()
  }

  /// Stops the mainloop by sending a cancel command.
  ///
  /// This method sends the OC_CMD_CANCEL byte to the cmd_fd, which signals
  /// the mainloop to exit gracefully. It then waits for the mainloop thread
  /// to complete.
  ///
  /// The method will wait up to 5 seconds for the mainloop to stop. If the
  /// mainloop doesn't stop within that time, it will continue anyway and
  /// clean up the thread reference.
  internal func stopMainloop() {
    mainloopLock.lock()
    let wasRunning = isMainloopRunning
    mainloopLock.unlock()

    guard wasRunning else {
      return
    }

    // Send cancel command to stop the mainloop
    sendCommand(VpnContext.OC_CMD_CANCEL)

    // Wait for the mainloop thread to finish (with timeout)
    let deadline = Date().addingTimeInterval(5.0)
    while isMainloopRunning && Date() < deadline {
      Thread.sleep(forTimeInterval: 0.1)
    }

    mainloopThread = nil
  }

  /// The actual mainloop execution that runs on the background thread.
  ///
  /// This method calls `openconnect_mainloop()` which blocks until the connection
  /// ends. The mainloop handles all VPN traffic and will automatically attempt
  /// to reconnect if the connection drops.
  ///
  /// When the mainloop exits:
  /// - Sets `isMainloopRunning` to false
  /// - Logs the exit code
  /// - Cleans up thread state
  private func runMainloopThread() {
    guard let vpnInfo = self.vpnInfo else {
      mainloopLock.lock()
      isMainloopRunning = false
      mainloopLock.unlock()
      return
    }

    // Call the OpenConnect mainloop with reconnection parameters
    _ = openconnect_mainloop(
      vpnInfo,
      configuration.reconnectTimeout,
      configuration.reconnectInterval
    )

    // Mainloop has exited
    mainloopLock.lock()
    isMainloopRunning = false
    mainloopLock.unlock()

    // Only notify if this wasn't an intentional disconnect
    if !intentionalDisconnect {
      // Notify session of disconnection with error if available
      let disconnectReason = lastError
      session?.handleDisconnect(reason: disconnectReason)
    }

    // Clear the error and reset flag
    lastError = nil
    intentionalDisconnect = false
  }
}
