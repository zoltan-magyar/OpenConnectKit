//
//  VPNSession.swift
//  OpenConnectKit
//
//  Main public API for VPN sessions
//

import Foundation
import os

/// openconnect's messages in the system log (Console.app, `log stream`).
private let openconnectLog = Logger(subsystem: "OpenConnectKit", category: "openconnect")

/// Manages VPN connections using the OpenConnect protocol.
///
/// `VPNSession` provides a SwiftUI-friendly, observable API for establishing
/// and managing OpenConnect VPN connections. All C interop is handled internally,
/// exposing a clean, type-safe interface.
///
/// ## SwiftUI Usage
///
/// ```swift
/// @State private var prompts: VPNPrompts
/// @State private var session: VPNSession
///
/// init() {
///     let prompts = VPNPrompts()
///     _prompts = State(initialValue: prompts)
///     _session = State(initialValue: VPNSession(delegate: prompts))
/// }
///
/// var body: some View {
///     VStack {
///         Text("Status: \(session.status)")
///         Button("Connect") {
///             Task {
///                 try await session.connect(using: config)
///             }
///         }
///     }
///     .sheet(item: $prompts.pendingAuthentication) { prompt in
///         LoginForm(prompt.form) { prompts.submit($0) }
///     }
/// }
/// ```
///
/// See `VPNPrompts` for the certificate prompt, and `VPNSessionDelegate` to answer prompts
/// some other way.
@Observable
@MainActor
public final class VPNSession {
  // MARK: - Observable State

  /// The current connection status of the VPN session. While connected, it carries the
  /// connection's details, such as the tunnel's interface name.
  public private(set) var status: ConnectionStatus = .disconnected

  /// Why the last connection attempt or connection failed, or `nil` if it ended normally or was
  /// cancelled. Cleared when `connect` is called.
  public private(set) var lastError: VPNError?

  /// The most recent traffic statistics of the current or last connection, or `nil` before the
  /// first statistics of a connection arrive.
  public private(set) var stats: VPNStats?

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

  /// Answers the authentication and certificate prompts. The session keeps it alive.
  public let delegate: any VPNSessionDelegate

  // MARK: - Internal Properties

  /// The connection in progress, from `connect` until it has ended.
  @ObservationIgnored
  private var context: VPNContext?

  /// Resumes `connect` once the connection is established or has failed.
  @ObservationIgnored
  private var connectContinuation: CheckedContinuation<Result<Void, VPNError>, Never>?

  /// Resume the `disconnect()` calls that are waiting for the connection to end.
  @ObservationIgnored
  private var disconnectContinuations: [CheckedContinuation<Void, Never>] = []

  /// Applies the context's lifecycle, in order, to the observable state.
  @ObservationIgnored
  private var lifecycleTask: Task<Void, Never>?

  /// Requests stats periodically while connected.
  @ObservationIgnored
  private var statsTask: Task<Void, Never>?

  /// Cancels the delegate call that's waiting for an answer, if there is one.
  @ObservationIgnored
  private var cancelPendingPrompt: (() -> Void)?

  private let logBroadcaster = LogBroadcaster()

  // MARK: - Initialization

  /// Creates a new VPN session with a delegate for interactive events.
  ///
  /// The session keeps a strong reference to the delegate, so a delegate created right here,
  /// like `VPNSession(delegate: VPNPrompts())`, stays alive. For SwiftUI, pass a `VPNPrompts`
  /// you keep a reference to, so your views can show its prompts.
  ///
  /// - Parameter delegate: The delegate to handle authentication and certificate validation
  public init(delegate: any VPNSessionDelegate) {
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
  /// `.connecting` as soon as this method is called. If the connection fails, the error is
  /// thrown and also kept in `lastError`.
  ///
  /// Cancelling the calling task cancels the connection attempt, as does `disconnect()`. A prompt
  /// that is waiting for the user is cancelled too (see `VPNSessionDelegate`).
  ///
  /// - Parameter configuration: The VPN configuration for this connection
  /// - Throws: `VPNError.cancelled` if it was cancelled, `VPNError.alreadyActive` if the
  ///   session isn't disconnected, otherwise the `VPNError` the failing step reported
  public func connect(using configuration: VPNConfiguration) async throws(VPNError) {
    guard case .disconnected = status else {
      throw .alreadyActive
    }

    // Set before the first suspension, so a second call can't get past the guard above.
    status = .connecting(.authenticating)
    lastError = nil
    stats = nil

    let context: VPNContext
    do {
      context = try VPNContext(
        configuration: configuration, callbacks: makeCallbacks())
    } catch {
      lastError = error
      status = .disconnected
      throw error
    }
    self.context = context

    let lifecycle = context.lifecycle
    lifecycleTask = Task(name: "OpenConnectKit.lifecycle") { [weak self] in
      for await event in lifecycle {
        self?.handle(event)
      }
    }

    // A non-throwing continuation with a Result, because a throwing continuation can only carry
    // `any Error`; `get()` then rethrows it as `VPNError`.
    let result = await withTaskCancellationHandler {
      await withCheckedContinuation { continuation in
        connectContinuation = continuation
        context.start()
      }
    } onCancel: { [weak self] in
      context.cancel()
      // The prompt task belongs to the session, so cancelling it happens on the main actor.
      Task { @MainActor in
        self?.cancelPendingPrompt?()
      }
    }
    try result.get()
  }

  /// Disconnects from the VPN server, and returns once the connection has been shut down.
  ///
  /// The status changes to `.disconnecting` right away, and to `.disconnected` when the
  /// connection has ended. While connecting, this cancels the attempt, and `connect` throws
  /// `VPNError.cancelled`. If a disconnect is already in progress, this waits for it too.
  ///
  /// A prompt that is waiting for the user is cancelled too (see `VPNSessionDelegate`). Without
  /// a connection, this returns immediately.
  public func disconnect() async {
    switch status {
    case .disconnected:
      return
    case .disconnecting:
      break
    case .connecting, .connected, .reconnecting:
      status = .disconnecting
      // Cancel the context first: when the prompt's answer comes back, the cancellation must
      // already be recorded, so the failure that follows reads as `.cancelled`.
      context?.cancel()
      cancelPendingPrompt?()
    }
    await withCheckedContinuation { continuation in
      disconnectContinuations.append(continuation)
    }
  }

  // MARK: - Lifecycle

  /// Applies a lifecycle event from the connection thread to the observable state.
  ///
  /// Besides `connect` and `disconnect`, lifecycle events are the only thing that changes
  /// `status`.
  private func handle(_ event: VPNContext.Lifecycle) {
    switch event {
    case .stage(let stage):
      // After disconnect(), the status stays .disconnecting until the connection has ended.
      if case .connecting = status {
        status = .connecting(stage)
      }

    case .established(let info):
      // If disconnect() was called meanwhile, wait for .finished.
      guard case .connecting = status else { return }
      status = .connected(info)
      startStatsPolling()
      connectContinuation?.resume(returning: .success(()))
      connectContinuation = nil

    case .reconnected:
      if case .reconnecting(let info) = status {
        status = .connected(info)
      }

    case .finished(let error):
      finish(error)
    }
  }

  /// Cleans up after the connection has ended, and resumes `connect` and `disconnect()` calls
  /// that are still waiting.
  private func finish(_ error: VPNError?) {
    statsTask?.cancel()
    statsTask = nil
    lifecycleTask = nil
    context = nil
    // A cancellation isn't an error from the user's point of view; connect() still throws it.
    lastError = error == .cancelled ? nil : error
    status = .disconnected

    connectContinuation?.resume(returning: .failure(error ?? .cancelled))
    connectContinuation = nil
    for continuation in disconnectContinuations {
      continuation.resume()
    }
    disconnectContinuations.removeAll()
  }

  // MARK: - Context Callbacks

  /// The callbacks the context calls on its connection thread.
  private func makeCallbacks() -> VPNContext.Callbacks {
    let logBroadcaster = logBroadcaster

    return VPNContext.Callbacks(
      // Auth form → the delegate, on the main actor, while the connection thread waits for the
      // answer (semaphore bridge). If the session is gone, cancel.
      authenticate: { [weak self] form in
        blockForMainActor {
          guard let self else { return nil }
          return await self.prompt(orIfCancelled: nil) { delegate in
            await delegate.vpnSession(self, requiresAuthentication: form)
          }
        }
      },
      // Cert validation → the delegate, the same way. If the session is gone, reject.
      validateCertificate: { [weak self] certInfo in
        blockForMainActor {
          guard let self else { return false }
          return await self.prompt(orIfCancelled: false) { delegate in
            await delegate.vpnSession(self, shouldAcceptCertificate: certInfo)
          }
        }
      },
      // Log messages → every `logs` stream, straight from the connection thread, and the system
      // log. The message keeps the system log's default privacy, so it's redacted outside a
      // debugging session: at trace level it includes the login's HTTP traffic, credentials
      // and all.
      log: { level, message in
        openconnectLog.log(level: level.osLogType, "\(message)")
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

  // MARK: - Prompts

  /// Asks the delegate, in a task that `disconnect()` and task cancellation can cancel.
  ///
  /// After a cancellation the delegate's answer is ignored and `fallback` is returned: the
  /// connection is ending either way, and a delegate that doesn't handle cancellation may still
  /// answer later.
  private func prompt<Answer: Sendable>(
    orIfCancelled fallback: Answer,
    _ ask: @MainActor @escaping (any VPNSessionDelegate) async -> Answer
  ) async -> Answer {
    // The connection may have been cancelled just before openconnect asked; don't show a prompt
    // for a connection that is already ending.
    guard let context, !context.isCancelled else { return fallback }

    let delegate = delegate
    let task = Task(name: "OpenConnectKit.prompt") { await ask(delegate) }
    cancelPendingPrompt = { task.cancel() }
    defer { cancelPendingPrompt = nil }

    let answer = await task.value
    return task.isCancelled ? fallback : answer
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
