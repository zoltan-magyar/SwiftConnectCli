//
//  StatsCallback.swift
//  OpenConnectKit
//
//  Internal stats callback handler
//

import COpenConnect
import Foundation

// MARK: - C Callback Entry Point

/// Handles traffic statistics notifications from the OpenConnect C library.
///
/// This function is called by OpenConnect when statistics are requested via
/// the `OC_CMD_STATS` command sent through cmd_fd. It extracts the `VpnSession`
/// from the `privdata` pointer, converts the C `oc_stats` structure to a Swift
/// `VpnStats` model, and delegates to the session's stats handler.
///
/// This callback is registered via `openconnect_set_stats_handler()` and will
/// be triggered whenever `requestStats()` is called.
///
/// - Parameters:
///   - privdata: Pointer to the owning `VpnSession`
///   - stats: Pointer to the C `oc_stats` structure containing traffic data
internal func statsCallback(
    privdata: UnsafeMutableRawPointer?,
    stats: UnsafePointer<oc_stats>?
) {
    guard let privdata = privdata else {
        return
    }

    guard let stats = stats else {
        return
    }

    let session = Unmanaged<VpnSession>.fromOpaque(privdata).takeUnretainedValue()

    // Convert C stats to Swift VpnStats
    let vpnStats = VpnStats(
        txPackets: stats.pointee.tx_pkts,
        txBytes: stats.pointee.tx_bytes,
        rxPackets: stats.pointee.rx_pkts,
        rxBytes: stats.pointee.rx_bytes
    )

    session.handleStats(vpnStats)
}
