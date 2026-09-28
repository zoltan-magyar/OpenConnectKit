//
//  LogLevel+Internal.swift
//  OpenConnectKit
//
//  Internal C interop extensions for LogLevel
//

import Foundation

extension LogLevel {
  // Convert from OpenConnect C log level (0-3); unknown levels map to info
  internal init(openConnectLevel: CInt) {
    switch openConnectLevel {
    case 0: self = .error
    case 1: self = .info
    case 2: self = .debug
    case 3: self = .trace
    default: self = .info
    }
  }

  // Convert to OpenConnect C log level (0-3)
  internal var openConnectLevel: Int32 {
    switch self {
    case .error: return 0
    case .info: return 1
    case .debug: return 2
    case .trace: return 3
    }
  }
}
