//
//  VpnContext+TunDevice.swift
//  OpenConnectKit
//
//  TUN device management extension for VpnContext
//

import COpenConnect
import Foundation

// MARK: - TUN Device Management

extension VpnContext {
  /// Sets up the TUN device for routing VPN traffic.
  ///
  /// This method configures the network tunnel interface that will be used to route
  /// packets through the VPN. It calls `openconnect_setup_tun_device()` which:
  /// 1. Creates a TUN/TAP device (or uses an existing one)
  /// 2. Runs the vpnc-script to configure routes and DNS
  /// 3. Prepares the device for packet routing
  ///
  /// - Returns: `0` on success, non-zero on failure
  /// - Throws: `VpnError.vpncScriptFailed` if the vpnc-script cannot be found or executed
  internal func setupTunDevice() throws -> Int32 {
    guard let vpnInfo = self.vpnInfo else {
      return -1
    }

    // Find or validate vpnc-script path
    // Note: openconnect_setup_tun_device requires a valid script path, not NULL
    let vpncScriptPath = try findVpncScript()
    let vpncScriptPtr = vpncScriptPath.withCString { strdup($0) }

    let interfaceNamePtr = configuration.interfaceName?.withCString { strdup($0) }

    defer {
      // Free any duplicated strings
      if let ptr = vpncScriptPtr {
        free(ptr)
      }
      if let ptr = interfaceNamePtr {
        free(ptr)
      }
    }

    // Call OpenConnect to setup the TUN device
    // Parameters: vpninfo, vpnc_script (required), interface_name (optional)
    let ret = openconnect_setup_tun_device(vpnInfo, vpncScriptPtr, interfaceNamePtr)

    return ret
  }

  /// Finds the vpnc-script in common installation locations.
  ///
  /// This method searches for the vpnc-script in platform-specific default locations:
  /// - **macOS (Homebrew)**: `/opt/homebrew/etc/vpnc-scripts/vpnc-script`, `/usr/local/etc/vpnc-scripts/vpnc-script`
  /// - **Linux**: `/etc/vpnc/vpnc-script`, `/usr/share/vpnc-scripts/vpnc-script`
  ///
  /// TODO: Enhance this to support more installation methods and platforms:
  /// - Check environment variables (e.g., VPNC_SCRIPT)
  /// - Support custom script locations per distro
  /// - Windows TAP adapter script location
  /// - Flatpak/Snap isolated installations
  ///
  /// - Returns: The path to a valid vpnc-script
  /// - Throws: `VpnError.vpncScriptFailed` if no valid script is found
  private func findVpncScript() throws -> String {
    // If explicitly configured, use that path
    if let configuredPath = configuration.vpncScript {
      if FileManager.default.isExecutableFile(atPath: configuredPath) {
        return configuredPath
      } else {
        throw VpnError.vpncScriptFailed
      }
    }

    // Search common locations
    let commonPaths = [
      // macOS Homebrew (Apple Silicon)
      "/opt/homebrew/etc/vpnc-scripts/vpnc-script",
      // macOS Homebrew (Intel)
      "/usr/local/etc/vpnc-scripts/vpnc-script",
      // Linux (Arch, Fedora, etc.)
      "/usr/share/vpnc-scripts/vpnc-script",
      // Linux (Debian, Ubuntu, etc.)
      "/etc/vpnc/vpnc-script",
      // Alternative Linux location
      "/usr/local/share/vpnc-scripts/vpnc-script",
    ]

    for path in commonPaths {
      if FileManager.default.isExecutableFile(atPath: path) {
        return path
      }
    }

    // No valid script found
    throw VpnError.vpncScriptFailed
  }
}
