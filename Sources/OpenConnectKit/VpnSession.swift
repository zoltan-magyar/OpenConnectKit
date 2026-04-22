//
//  VpnSession.swift
//  OpenConnectKit
//
//  Main public API for VPN sessions
//

import Foundation

/// Manages VPN connections using the OpenConnect protocol.
///
/// `VpnSession` provides a SwiftUI-friendly, observable API for establishing
/// and managing OpenConnect VPN connections. All C interop is handled internally,
/// exposing a clean, type-safe interface.
///
/// ## SwiftUI Usage
///
/// ```swift
/// @State private var session: VpnSession
///
/// init(handler: MyVpnHandler) {
///     self.session = VpnSession(delegate: handler)
/// }
///
/// var body: some View {
///     VStack {
///         Text("Status: \(session.status)")
///         Button("Connect") {
///             Task {
///                 try await session.connect(configuration: config)
///             }
///         }
///     }
/// }
/// ```
@Observable
@MainActor
public final class VpnSession {
  // MARK: - Observable State

  /// The current connection status of the VPN session.
  public private(set) var status: ConnectionStatus = .disconnected(error: nil)

  /// The most recent traffic statistics, or `nil` if not yet available.
  public private(set) var stats: VpnStats?

  /// The name of the network interface assigned to the VPN tunnel.
  ///
  /// Available only when status is `.connected`.
  public private(set) var interfaceName: String?

  // MARK: - Log Stream

  /// An async stream of log entries from the VPN session.
  ///
  /// Consume in a `.task` modifier:
  /// ```swift
  /// .task {
  ///     for await entry in session.logs {
  ///         // handle log entry
  ///     }
  /// }
  /// ```
  @ObservationIgnored
  public let logs: AsyncStream<LogEntry>

  // MARK: - Delegate

  /// The delegate for handling authentication and certificate validation.
  public weak var delegate: VpnSessionDelegate?

  // MARK: - Internal Properties

  /// Internal context managing the OpenConnect connection.
  private var context: VpnContext?

  /// Continuation for the log async stream.
  @ObservationIgnored
  private let logContinuation: AsyncStream<LogEntry>.Continuation

  /// Timer for periodic stats requests while connected.
  @ObservationIgnored
  private var statsTimer: DispatchSourceTimer?

  // MARK: - Initialization

  /// Creates a new VPN session with a delegate for interactive events.
  ///
  /// - Parameter delegate: The delegate to handle authentication and certificate validation
  public init(delegate: VpnSessionDelegate) {
    let (stream, continuation) = AsyncStream<LogEntry>.makeStream()
    self.logs = stream
    self.logContinuation = continuation
    self.delegate = delegate
  }

  deinit {
    statsTimer?.cancel()
    logContinuation.finish()
  }

  // MARK: - Public Methods

  /// Connects to the VPN server.
  ///
  /// This method performs the following steps:
  /// 1. Obtains an authentication cookie (may trigger delegate authentication)
  /// 2. Establishes the CSTP connection
  /// 3. Sets up DTLS for the data channel
  /// 4. Configures the TUN device
  /// 5. Starts the mainloop on a dedicated thread
  ///
  /// The `status` property is updated throughout the connection process.
  ///
  /// - Parameter configuration: The VPN configuration for this connection
  /// - Throws: `VpnError` if connection fails at any step
  public func connect(configuration: VpnConfiguration) async throws {
    guard case .disconnected = status else {
      throw VpnError.alreadyConnected
    }

    let context = try VpnContext(configuration: configuration)
    self.context = context

    // Wire up closure callbacks
    wireCallbacks(for: context)

    // Run the blocking connect sequence off MainActor
    do {
      try await Task.detached {
        try context.connect()
      }.value
    } catch {
      self.context = nil
      throw error
    }

    // Connection succeeded — start periodic stats polling
    startStatsTimer()
  }

  /// Disconnects from the VPN server.
  ///
  /// This method gracefully shuts down the VPN connection and cleans up
  /// resources. The `status` property will transition to `.disconnected`.
  ///
  /// This method is safe to call multiple times.
  public func disconnect() {
    if case .disconnected = status { return }
    if case .disconnecting = status { return }
    context?.disconnect()
  }

  // MARK: - Internal Callback Wiring

  /// Wires all closure callbacks from VpnContext to VpnSession's observable state.
  private func wireCallbacks(for context: VpnContext) {
    // Status changes → update observable property
    context.onStatus = { [weak self] status in
      Task { @MainActor in
        guard let self else { return }
        self.status = status

        // Update interface name when connected
        if case .connected = status {
          self.interfaceName = context.assignedInterfaceName
        }

        // Clear stats and interface name on disconnect
        if case .disconnected = status {
          self.interfaceName = nil
          self.stopStatsTimer()
        }
      }
    }

    // Stats → update observable property
    context.onStats = { [weak self] stats in
      Task { @MainActor in
        self?.stats = stats
      }
    }

    // Log messages → emit to async stream
    context.onLog = { [weak self] level, message in
      let entry = LogEntry(level: level, message: message)
      self?.logContinuation.yield(entry)
    }

    // Auth form → bridge to async delegate via semaphore
    context.onAuth = { [weak self] form in
      blockForMainActor {
        if let self, let delegate = self.delegate {
          return await delegate.vpnSession(self, requiresAuthentication: form)
        }
        return form
      }
    }

    // Cert validation → bridge to async delegate via semaphore
    context.onCert = { [weak self] certInfo in
      blockForMainActor {
        if let self, let delegate = self.delegate {
          return await delegate.vpnSession(self, shouldAcceptCertificate: certInfo)
        }
        return context.configuration.allowInsecureCertificates
      }
    }

    // Mainloop finished → clean up context reference
    context.onMainloopFinished = { [weak self] in
      Task { @MainActor in
        self?.context = nil
      }
    }
  }

  // MARK: - Stats Timer

  /// Starts periodic stats polling every 5 seconds while connected.
  private func startStatsTimer() {
    stopStatsTimer()

    let timer = DispatchSource.makeTimerSource(queue: DispatchQueue(label: "OpenConnectKit.statsPoller"))
    timer.schedule(deadline: .now() + .seconds(5), repeating: .seconds(5))
    timer.setEventHandler { [weak self] in
      Task { @MainActor in
        self?.context?.requestStats()
      }
    }
    timer.resume()
    statsTimer = timer
  }

  /// Stops the periodic stats timer.
  private func stopStatsTimer() {
    statsTimer?.cancel()
    statsTimer = nil
  }
}

/// Blocks the calling thread until an async MainActor operation completes.
///
/// Used to bridge synchronous C callbacks to async delegate methods.
/// The C library requires a synchronous return value, but the delegate
/// method is async (e.g., awaiting user input in a sheet).
///
/// - Parameter work: The async work to perform on MainActor
/// - Returns: The result of the work
private func blockForMainActor<T>(
  _ work: @MainActor @escaping () async -> T
) -> T {
  let semaphore = DispatchSemaphore(value: 0)
  nonisolated(unsafe) var result: T?
  Task { @MainActor in
    result = await work()
    semaphore.signal()
  }
  semaphore.wait()
  return result!
}
