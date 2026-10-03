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

  /// The most recent traffic statistics of the current or last connection, or `nil` before the
  /// first statistics of a connection arrive.
  public private(set) var stats: VpnStats?

  /// The name of the network interface assigned to the VPN tunnel.
  ///
  /// Available only when status is `.connected`.
  public private(set) var interfaceName: String?

  // MARK: - Log Stream

  /// Log entries from the VPN session, from the moment you start reading.
  ///
  /// Each access returns a new, independent stream, so several readers can follow the logs at
  /// once, and a SwiftUI `.task` that restarts simply gets a fresh stream. Entries that arrive
  /// while nobody is reading aren't kept. A reader that falls far behind loses the oldest
  /// entries first.
  ///
  /// Consume in a `.task` modifier:
  /// ```swift
  /// .task {
  ///     for await entry in session.logs {
  ///         // handle log entry
  ///     }
  /// }
  /// ```
  public var logs: AsyncStream<LogEntry> {
    logBroadcaster.makeStream()
  }

  // MARK: - Delegate

  /// The delegate for handling authentication and certificate validation.
  @ObservationIgnored
  public weak var delegate: VpnSessionDelegate?

  // MARK: - Internal Properties

  /// The connection in progress, from `connect` until it has ended.
  @ObservationIgnored
  private var context: VpnContext?

  /// Resumes `connect` once the connection is established or has failed.
  @ObservationIgnored
  private var connectContinuation: CheckedContinuation<Void, any Error>?

  /// Applies the context's lifecycle, in order, to the observable state.
  @ObservationIgnored
  private var lifecycleTask: Task<Void, Never>?

  /// Requests stats periodically while connected.
  @ObservationIgnored
  private var statsTask: Task<Void, Never>?

  private let logBroadcaster = LogBroadcaster()

  // MARK: - Initialization

  /// Creates a new VPN session with a delegate for interactive events.
  ///
  /// - Parameter delegate: The delegate to handle authentication and certificate validation
  public init(delegate: VpnSessionDelegate) {
    self.delegate = delegate
  }

  isolated deinit {
    // Without this the connection thread would keep the tunnel up, with nothing left to stop it.
    context?.cancel()
    lifecycleTask?.cancel()
    statsTask?.cancel()
    logBroadcaster.finish()
  }

  // MARK: - Public Methods

  /// Connects to the VPN server.
  ///
  /// This method performs the following steps:
  /// 1. Obtains an authentication cookie (may trigger delegate authentication)
  /// 2. Establishes the CSTP connection
  /// 3. Sets up DTLS for the data channel (falling back to TLS if that fails)
  /// 4. Configures the TUN device
  /// 5. Starts the mainloop
  ///
  /// It returns once the tunnel is up. The `status` property is updated throughout, and it is
  /// `.connecting` as soon as this method is called.
  ///
  /// Cancelling the calling task cancels the connection attempt, as does `disconnect()`. An auth
  /// form or certificate prompt that is waiting for the user still has to be answered first.
  ///
  /// - Parameter configuration: The VPN configuration for this connection
  /// - Throws: `VpnError` if connection fails at any step, `VpnError.cancelled` if it was
  ///   cancelled, `VpnError.alreadyConnected` if the session isn't disconnected
  public func connect(configuration: VpnConfiguration) async throws {
    guard case .disconnected = status else {
      throw VpnError.alreadyConnected
    }

    // Set before the first suspension, so a second call can't get past the guard above.
    status = .connecting(stage: "Initializing connection")
    stats = nil

    let context: VpnContext
    do {
      context = try VpnContext(
        configuration: configuration, callbacks: makeCallbacks(configuration))
    } catch {
      status = .disconnected(error: error)
      throw error
    }
    self.context = context

    let lifecycle = context.lifecycle
    lifecycleTask = Task(name: "OpenConnectKit.lifecycle") { [weak self] in
      for await event in lifecycle {
        self?.handle(event)
      }
    }

    try await withTaskCancellationHandler {
      try await withCheckedThrowingContinuation { continuation in
        connectContinuation = continuation
        context.start()
      }
    } onCancel: {
      context.cancel()
    }
  }

  /// Disconnects from the VPN server.
  ///
  /// The status changes to `.disconnecting` right away, and to `.disconnected` once the
  /// connection has been shut down. While connecting, this cancels the attempt, and `connect`
  /// throws `VpnError.cancelled`.
  ///
  /// This method is safe to call multiple times.
  public func disconnect() {
    switch status {
    case .disconnected, .disconnecting:
      return
    case .connecting, .connected, .reconnecting:
      status = .disconnecting
      context?.cancel()
    }
  }

  // MARK: - Lifecycle

  /// Applies a lifecycle event from the connection thread to the observable state.
  ///
  /// Besides `connect` and `disconnect`, lifecycle events are the only thing that changes
  /// `status`.
  private func handle(_ event: VpnContext.Lifecycle) {
    switch event {
    case .stage(let stage):
      // After disconnect(), the status stays .disconnecting until the connection has ended.
      if case .connecting = status {
        status = .connecting(stage: stage)
      }

    case .established(let interfaceName):
      // If disconnect() was called meanwhile, wait for .finished.
      guard case .connecting = status else { return }
      status = .connected
      self.interfaceName = interfaceName
      startStatsPolling()
      connectContinuation?.resume()
      connectContinuation = nil

    case .reconnected:
      if case .reconnecting = status {
        status = .connected
      }

    case .finished(let error):
      finish(error)
    }
  }

  /// Cleans up after the connection has ended, and resumes `connect` if it's still waiting.
  private func finish(_ error: VpnError?) {
    statsTask?.cancel()
    statsTask = nil
    lifecycleTask = nil
    context = nil
    interfaceName = nil
    // A cancellation isn't an error from the user's point of view; connect() still throws it.
    if case .cancelled? = error {
      status = .disconnected(error: nil)
    } else {
      status = .disconnected(error: error)
    }
    connectContinuation?.resume(throwing: error ?? VpnError.cancelled)
    connectContinuation = nil
  }

  // MARK: - Context Callbacks

  /// The callbacks the context calls on its connection thread.
  private func makeCallbacks(_ configuration: VpnConfiguration) -> VpnContext.Callbacks {
    let allowInsecureCertificates = configuration.allowInsecureCertificates
    let logBroadcaster = logBroadcaster

    return VpnContext.Callbacks(
      // Auth form → bridge to async delegate via semaphore
      authenticate: { [weak self] form in
        blockForMainActor {
          guard let self, let delegate = self.delegate else { return nil }
          return await delegate.vpnSession(self, requiresAuthentication: form)
        }
      },
      // Cert validation → bridge to async delegate via semaphore
      validateCertificate: { [weak self] certInfo in
        blockForMainActor {
          guard let self, let delegate = self.delegate else { return allowInsecureCertificates }
          return await delegate.vpnSession(self, shouldAcceptCertificate: certInfo)
        }
      },
      // Log messages → every `logs` stream, straight from the connection thread
      log: { level, message in
        logBroadcaster.yield(LogEntry(level: level, message: message))
      },
      // Stats → observable property. Unlike the lifecycle, stats don't go through the ordered
      // stream: each reply hops to the main actor on its own, so it isn't ordered with the
      // lifecycle events. A reply requested just before the connection ended can therefore
      // arrive after `.finished` has been handled, or after the next `connect` has already
      // reset `stats`. Replies are only applied while connected, so a late one is dropped
      // instead of showing up as the numbers of a connection that is gone.
      stats: { [weak self] stats in
        Task { @MainActor in
          guard let self, case .connected = self.status else { return }
          self.stats = stats
        }
      }
    )
  }

  // MARK: - Stats Polling

  /// Requests stats every 5 seconds until the connection ends. Replies arrive through the
  /// `stats` callback.
  private func startStatsPolling() {
    statsTask?.cancel()
    statsTask = Task(name: "OpenConnectKit.stats") { [weak self] in
      while true {
        do {
          try await Task.sleep(for: .seconds(5))
        } catch {
          return  // cancelled
        }
        self?.context?.requestStats()
      }
    }
  }
}

/// Blocks the calling thread until an async MainActor operation completes.
///
/// Used to bridge synchronous C callbacks to async delegate methods.
/// The C library requires a synchronous return value, but the delegate
/// method is async (e.g., awaiting user input in a sheet).
///
/// A continuation wouldn't do: it suspends a task, while openconnect needs the thread it called
/// in on to wait. That thread is the context's own connection thread, never one of Swift's
/// cooperative pool, so blocking it is fine.
///
/// - Parameter work: The async work to perform on MainActor
/// - Returns: The result of the work
private func blockForMainActor<T: Sendable>(
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
