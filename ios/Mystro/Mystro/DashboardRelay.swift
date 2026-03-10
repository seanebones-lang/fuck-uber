import Foundation

// MARK: - Notification
extension Notification.Name {
  static let destroDashboardRelayConnectionDidChange = Notification.Name("destroDashboardRelayConnectionDidChange")
}

// MARK: - DashboardRelay
// Sends daemon events to the WebSocket dashboard (ws://localhost:3000 or configured host).
// Reconnects on disconnect; no-op when server unreachable.

final class DashboardRelay {
  static let shared = DashboardRelay()

  private static let keyBaseURL = "destro.dashboard.wsURL"

  private var task: URLSessionWebSocketTask?
  private let queue = DispatchQueue(label: "destro.dashboard.relay")
  private var baseURL: String
  private var reconnectWorkItem: DispatchWorkItem?
  private var _isConnected = false

  /// True when the WebSocket is connected; false when disconnected or not yet connected.
  var isConnected: Bool { queue.sync { _isConnected } }

  private init() {
    let stored = UserDefaults.standard.string(forKey: Self.keyBaseURL)
    let useStored = stored.map { !$0.isEmpty } ?? false
    baseURL = useStored ? (stored ?? "ws://localhost:3000") : "ws://localhost:3000"
  }

  /// Set and persist WebSocket URL (e.g. ws://192.168.1.10:3000 for Mac on LAN). Empty string resets to localhost.
  func setBaseURL(_ url: String) {
    queue.async { [weak self] in
      guard let self = self else { return }
      self.baseURL = url.isEmpty ? "ws://localhost:3000" : url
      UserDefaults.standard.set(url.isEmpty ? nil : url, forKey: Self.keyBaseURL)
      self.disconnect()
    }
  }

  func getBaseURL() -> String {
    queue.sync { baseURL }
  }

  func connect() {
    queue.async { [weak self] in
      self?._connect()
    }
  }

  private func _connect() {
    guard let url = URL(string: baseURL) else { return }
    let session = URLSession(configuration: .default)
    task = session.webSocketTask(with: url)
    task?.resume()
    receiveLoop()
  }

  private func receiveLoop() {
    task?.receive { [weak self] result in
      self?.queue.async {
        self?._handleReceive(result: result)
      }
    }
  }

  private func _handleReceive(result: Result<URLSessionWebSocketTask.Message, Error>) {
    switch result {
    case .success:
      if !_isConnected {
        _isConnected = true
        _postConnectionDidChange()
      }
      receiveLoop()
    case .failure:
      let wasConnected = _isConnected
      _isConnected = false
      task = nil
      if wasConnected { _postConnectionDidChange() }
      scheduleReconnect()
    }
  }

  private func _postConnectionDidChange() {
    let connected = _isConnected
    DispatchQueue.main.async {
      NotificationCenter.default.post(
        name: .destroDashboardRelayConnectionDidChange,
        object: self,
        userInfo: ["connected": connected]
      )
    }
  }

  func disconnect() {
    queue.async { [weak self] in
      guard let self = self else { return }
      let wasConnected = self._isConnected
      self.task?.cancel(with: .goingAway, reason: nil)
      self.task = nil
      self.reconnectWorkItem?.cancel()
      self._isConnected = false
      if wasConnected { self._postConnectionDidChange() }
    }
  }

  func send(_ payload: [String: Any]) {
    queue.async { [weak self] in
      self?._send(payload)
    }
  }

  private func _send(_ payload: [String: Any]) {
    guard let data = try? JSONSerialization.data(withJSONObject: payload),
          let str = String(data: data, encoding: .utf8) else {
      print("[Destro] DashboardRelay send: JSON serialization failed")
      return
    }
    task?.send(.string(str)) { [weak self] error in
      self?.queue.async {
        if error != nil {
          let wasConnected = self?._isConnected ?? false
          self?._isConnected = false
          self?.task = nil
          if wasConnected { self?._postConnectionDidChange() }
          self?.scheduleReconnect()
        } else {
          if let self = self, !self._isConnected {
            self._isConnected = true
            self._postConnectionDidChange()
          }
        }
      }
    }
  }

  private func scheduleReconnect() {
    reconnectWorkItem?.cancel()
    let item = DispatchWorkItem { [weak self] in
      self?._connect()
    }
    reconnectWorkItem = item
    queue.asyncAfter(deadline: .now() + 5, execute: item)
  }
}
