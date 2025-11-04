//
//  ProcessAuthForm.swift
//  SwiftConnectCli
//
//  Created by Zoltán Magyar on 2025. 10. 27..
//

import COpenConnect
import Foundation

func processAuthFormCallback(
    privdata: UnsafeMutableRawPointer?, form: UnsafeMutablePointer<oc_auth_form>?
) -> CInt {
    guard let privdata = privdata else {
        print("Privdata is nil")
        return 1
    }
    let vpnContext = Unmanaged<VpnContext>.fromOpaque(privdata).takeUnretainedValue()
    guard let form = form else {
        print("Form is nil")
        return 0
    }

    print("Form:", "\(form)")
    vpnContext.print_auth()

    return 0
}
