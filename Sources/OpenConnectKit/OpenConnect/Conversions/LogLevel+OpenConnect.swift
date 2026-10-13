//
//  LogLevel+OpenConnect.swift
//  OpenConnectKit
//
//  Conversion between LogLevel and openconnect's PRG_* levels
//

import COpenConnect
import Foundation
import os

extension LogLevel {
  // Convert from openconnect's PRG_* level; unknown levels map to info
  internal init(openConnectLevel: CInt) {
    switch openConnectLevel {
    case PRG_ERR: self = .error
    case PRG_INFO: self = .info
    case PRG_DEBUG: self = .debug
    case PRG_TRACE: self = .trace
    default: self = .info
    }
  }

  // Convert to openconnect's PRG_* level. Also defines the order of `Comparable`.
  internal var openConnectLevel: CInt {
    switch self {
    case .error: PRG_ERR
    case .info: PRG_INFO
    case .debug: PRG_DEBUG
    case .trace: PRG_TRACE
    }
  }

  // The matching level in the system log
  internal var osLogType: OSLogType {
    switch self {
    case .error: .error
    case .info: .info
    case .debug, .trace: .debug
    }
  }
}
