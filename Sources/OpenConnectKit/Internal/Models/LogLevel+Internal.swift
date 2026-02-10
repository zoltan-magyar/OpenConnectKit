//
//  LogLevel+Internal.swift
//  OpenConnectKit
//
//  Internal C interop extensions for LogLevel
//

import Foundation

extension LogLevel {
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
