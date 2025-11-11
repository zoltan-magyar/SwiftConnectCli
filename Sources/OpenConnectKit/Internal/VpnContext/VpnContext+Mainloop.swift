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
    stateLock.lock()

    // Create and start the mainloop thread
    mainloopThread = Thread { [weak self] in
      guard let self = self else { return }

      self.stateLock.lock()
      let shouldConnect = self.connectionStatus.isConnecting
      self.stateLock.unlock()

      if shouldConnect {
        // Use updateStatus for consistency
        self.updateStatus(.connected)
      }

      self.runMainloopThread()
    }
    mainloopThread?.name = "com.openconnect.mainloop"
    mainloopThread?.start()

    stateLock.unlock()
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
    stateLock.lock()
    guard connectionStatus.isConnected else {
      stateLock.unlock()
      return
    }
    stateLock.unlock()

    // Send cancel command to stop the mainloop
    sendCommand(VpnContext.OC_CMD_CANCEL)

    // Wait for the mainloop thread to finish (with timeout)
    let deadline = Date().addingTimeInterval(5.0)
    while !connectionStatus.isDisconnected && Date() < deadline {
      Thread.sleep(forTimeInterval: 0.1)
    }

    mainloopThread = nil
  }

  /// The actual mainloop execution that runs on the background thread.
  ///
  /// This method runs `openconnect_mainloop()` in a continuous loop, which is the
  /// correct way to use the OpenConnect library. Each call to `openconnect_mainloop()`
  /// returns when it needs to process commands or reconnect. The loop continues
  /// until an error occurs or a cancel command is received.
  ///
  /// The mainloop handles all VPN traffic and will automatically attempt
  /// to reconnect if the connection drops (up to reconnect_timeout).
  ///
  /// When the mainloop exits:
  /// - Updates connection status to disconnected
  /// - Logs the exit code
  /// - Cleans up thread state
  /// - Notifies the session of disconnection (if not intentional)
  private func runMainloopThread() {
    var wasReconnecting = false

    while true {
      // Call the OpenConnect mainloop with reconnection parameters
      // This call will block until:
      // - A command is received via cmd_fd
      // - The connection drops and reconnection is attempted
      // - An error occurs
      let ret = openconnect_mainloop(
        vpnInfo,
        configuration.reconnectTimeout,
        configuration.reconnectInterval
      )

      // Check if mainloop exited due to an error or cancel command
      if ret != 0 {
        // Non-zero return means the mainloop has stopped
        // This could be due to:
        // - OC_CMD_CANCEL command (user-initiated disconnect)
        // - Connection failure that couldn't be recovered
        // - Other errors
        break
      }

      // If ret == 0, the mainloop exited normally (usually after a successful
      // reconnect or command processing). Continue the loop to keep the
      // connection alive.

      // Check if we were reconnecting - if so, we've successfully reconnected
      if wasReconnecting {
        updateStatus(.connected)
        session?.handleReconnected()
        wasReconnecting = false
      }

      // Mark that we're in reconnection mode for next iteration
      stateLock.lock()
      if connectionStatus.isConnected {
        wasReconnecting = true
        connectionStatus = .reconnecting
        let status = connectionStatus
        stateLock.unlock()
        session?.handleStatusChange(status: status)
      } else {
        stateLock.unlock()
      }
    }

    // Determine disconnect reason
    let error: VpnError?
    stateLock.lock()
    let wasUserInitiated = connectionStatus.isDisconnected
    stateLock.unlock()

    if wasUserInitiated {
      error = nil  // User requested disconnect
    } else if let storedError = lastError {
      // Use the stored error directly
      error = storedError
    } else {
      error = .connectionFailed(reason: "Connection lost")
    }

    updateStatus(.disconnected(error: error))

    // Always notify - let the session decide what to do
    session?.handleDisconnect(reason: error?.localizedDescription)

    lastError = nil
  }
}
