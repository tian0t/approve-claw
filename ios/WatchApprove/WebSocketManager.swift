import Foundation
import Combine

enum ConnectionStatus: String {
    case disconnected = "Disconnected"
    case connecting = "Connecting"
    case connected = "Connected"
    case authFailed = "Authentication Failed"
}



class WebSocketManager: NSObject, ObservableObject, URLSessionWebSocketDelegate {
    @Published var connectionStatus: ConnectionStatus = .disconnected {
        didSet { syncToWatch() }
    }
    @Published var activeRequest: ApprovalRequest? = nil {
        didSet { syncToWatch() }
    }
    @Published var history: [HistoricalRequest] = []
    @Published var ipAddress: String = "" {
        didSet { syncToWatch() }
    }
    @Published var port: String = "8080"
    @Published var lastError: String? = nil
    
    func syncToWatch() {
        PhoneConnectivity.shared.syncActiveRequest(activeRequest, status: connectionStatus.rawValue, isPaired: isPaired, ipAddress: ipAddress)
    }
    
    private var webSocketTask: URLSessionWebSocketTask?
    private var urlSession: URLSession!
    private var cancellables = Set<AnyCancellable>()
    private var retryCount = 0
    private var pendingPin: String?
    
    // Shared instance reference for PhoneConnectivity to access
    static var shared: WebSocketManager?
    
    @Published var isPaired: Bool = false {
        didSet { syncToWatch() }
    }
    
    override init() {
        #if targetEnvironment(simulator)
        let savedIp = UserDefaults.standard.string(forKey: "mac_ip_address")
        self.ipAddress = (savedIp == nil || savedIp == "192.168.1.100") ? "127.0.0.1" : savedIp!
        #else
        let savedIp = UserDefaults.standard.string(forKey: "mac_ip_address")
        self.ipAddress = (savedIp == nil || savedIp == "192.168.1.100") ? "192.168.1.4" : savedIp!
        #endif
        super.init()
        self.isPaired = UserDefaults.standard.string(forKey: "auth_token") != nil
        self.urlSession = URLSession(configuration: .default, delegate: self, delegateQueue: .main)
        self.loadHistory()
        WebSocketManager.shared = self
    }
    
    func connect() {
        guard connectionStatus != .connected && connectionStatus != .connecting else { return }
        
        UserDefaults.standard.set(ipAddress, forKey: "mac_ip_address")
        lastError = nil
        
        let urlString = "ws://\(ipAddress):\(port)"
        guard let url = URL(string: urlString) else {
            print("Invalid URL: \(urlString)")
            lastError = "Invalid URL: \(urlString)"
            return
        }
        
        connectionStatus = .connecting
        print("Connecting to WebSocket: \(url)")
        
        let request = URLRequest(url: url, timeoutInterval: 10)
        webSocketTask = urlSession.webSocketTask(with: request)
        webSocketTask?.resume()
        
        // Start receiving messages
        receiveMessage()
        // Auth is sent once the connection actually opens (didOpenWithProtocol),
        // so the auth message is never dropped while the socket is CONNECTING.
    }
    
    func disconnect() {
        pendingPin = nil
        retryCount = 0
        webSocketTask?.cancel(with: .normalClosure, reason: nil)
        connectionStatus = .disconnected
        activeRequest = nil
    }
    
    func pair(pin: String) {
        pendingPin = pin
        if connectionStatus != .connected && connectionStatus != .connecting {
            connect()
        } else if connectionStatus == .connected {
            sendAuth(pin: pin)
        }
    }
    
    func resetPairing() {
        pendingPin = nil
        UserDefaults.standard.removeObject(forKey: "auth_token")
        isPaired = false
        disconnect()
    }
    
    private func sendAuth(token: String? = nil, pin: String? = nil) {
        var payload: [String: String] = ["type": "auth"]
        if let token = token {
            payload["token"] = token
        } else if let pin = pin {
            payload["code"] = pin
        }
        
        sendJson(payload)
    }
    
    @discardableResult
    func sendDecision(requestId: String, action: String) -> Bool {
        guard connectionStatus == .connected, webSocketTask != nil else {
            print("Cannot send decision: WebSocket not connected")
            return false
        }

        let payload = [
            "type": "confirmation_response",
            "id": requestId,
            "action": action
        ]

        sendJson(payload)

        // Add to history locally
        if let request = activeRequest, request.id == requestId {
            let histAction = action == "approve" ? "Approved" : "Rejected"
            addHistory(requestId: requestId, agent: request.agent, command: request.command, action: histAction)

            // Clear request
            DispatchQueue.main.async {
                self.activeRequest = nil
                PhoneConnectivity.shared.syncActiveRequest(nil)
            }
        }
        return true
    }
    
    private func sendJson(_ dict: [String: Any]) {
        do {
            let data = try JSONSerialization.data(withJSONObject: dict, options: [])
            if let jsonString = String(data: data, encoding: .utf8) {
                let message = URLSessionWebSocketTask.Message.string(jsonString)
                webSocketTask?.send(message) { error in
                    if let error = error {
                        print("WebSocket send error: \(error)")
                    }
                }
            }
        } catch {
            print("Failed to serialize WebSocket JSON: \(error)")
        }
    }
    
    private func receiveMessage() {
        webSocketTask?.receive { [weak self] result in
            guard let self = self else { return }
            
            switch result {
            case .failure(let error):
                print("WebSocket receive error: \(error)")
                DispatchQueue.main.async {
                    self.retryCount += 1
                    self.lastError = error.localizedDescription
                    self.connectionStatus = .disconnected
                    self.activeRequest = nil
                    PhoneConnectivity.shared.syncActiveRequest(nil)
                    self.scheduleAutoReconnect()
                }
                
            case .success(let message):
                switch message {
                case .string(let text):
                    self.handleIncomingText(text)
                case .data(let data):
                    if let text = String(data: data, encoding: .utf8) {
                        self.handleIncomingText(text)
                    }
                @unknown default:
                    break
                }
                
                // Continue listening
                self.receiveMessage()
            }
        }
    }
    
    private func handleIncomingText(_ text: String) {
        guard let data = text.data(using: .utf8) else { return }
        
        do {
            if let json = try JSONSerialization.jsonObject(with: data, options: []) as? [String: Any],
               let type = json["type"] as? String {
                
                DispatchQueue.main.async {
                    switch type {
                    case "auth_success":
                        if let token = json["token"] as? String {
                            self.pendingPin = nil
                            UserDefaults.standard.set(token, forKey: "auth_token")
                            self.isPaired = true
                            self.connectionStatus = .connected
                            print("Auth succeeded, token saved.")
                        }
                        
                    case "auth_fail":
                        self.pendingPin = nil
                        self.connectionStatus = .authFailed
                        self.activeRequest = nil
                        PhoneConnectivity.shared.syncActiveRequest(nil)
                        print("Auth failed.")
                        
                    case "confirmation_request":
                        if let requestData = try? JSONSerialization.data(withJSONObject: json["request"] as Any, options: []),
                           let request = try? JSONDecoder().decode(ApprovalRequest.self, from: requestData) {
                            self.activeRequest = request
                            // Sync request to Apple Watch
                            PhoneConnectivity.shared.syncActiveRequest(request)
                            // Post system notification with Quick Actions & Haptics
                            NotificationManager.shared.sendApprovalNotification(for: request)
                            print("Received new confirmation request: \(request.command)")
                        }
                        
                    case "confirmation_completed":
                        if let id = json["id"] as? String {
                            // If the active request matches, clear it
                            if self.activeRequest?.id == id {
                                let action = json["action"] as? String ?? ""
                                let histAction = action == "approve" ? "Approved" : "Rejected"
                                self.addHistory(requestId: id, agent: self.activeRequest?.agent ?? "Agent", command: self.activeRequest?.command ?? "", action: histAction)
                                self.activeRequest = nil
                                PhoneConnectivity.shared.syncActiveRequest(nil)
                            }
                        }
                        
                    case "confirmation_cancelled":
                        if let id = json["id"] as? String {
                            if self.activeRequest?.id == id {
                                self.addHistory(requestId: id, agent: self.activeRequest?.agent ?? "Agent", command: self.activeRequest?.command ?? "", action: "Cancelled")
                                self.activeRequest = nil
                                PhoneConnectivity.shared.syncActiveRequest(nil)
                            }
                        }
                        
                    default:
                        print("Unknown WebSocket message type: \(type)")
                    }
                }
            }
        } catch {
            print("Failed to decode message: \(error)")
        }
    }
    
    private func addHistory(requestId: String, agent: String, command: String, action: String) {
        let entry = HistoricalRequest(requestId: requestId, agent: agent, command: command, action: action, timestamp: Date())
        
        // Prevent duplicates
        if !history.contains(where: { $0.requestId == requestId }) {
            history.insert(entry, at: 0)
            saveHistory()
        }
    }
    
    private func saveHistory() {
        if let data = try? JSONEncoder().encode(history) {
            UserDefaults.standard.set(data, forKey: "request_history")
        }
    }
    
    private func loadHistory() {
        if let data = UserDefaults.standard.data(forKey: "request_history"),
           let decoded = try? JSONDecoder().decode([HistoricalRequest].self, from: data) {
            self.history = decoded
        }
    }
    
    // MARK: - Auto Reconnect
    private var isAutoReconnecting = false

    private func scheduleAutoReconnect() {
        guard !isAutoReconnecting else { return }
        isAutoReconnecting = true

        // Exponential backoff: 3s, 6s, 12s, ... capped at 30s
        let delay = min(pow(2.0, Double(retryCount)) * 3.0, 30.0)
        print("Scheduling reconnection in \(Int(delay))s...")

        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self = self else { return }
            self.isAutoReconnecting = false

            if self.connectionStatus == .disconnected && self.isPaired {
                print("Attempting automatic reconnection...")
                self.connect()
            }
        }
    }

    // MARK: - URLSessionWebSocketDelegate

    func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask, didOpenWithProtocol protocol: String?) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.retryCount = 0
            print("WebSocket opened. Sending auth...")
            if let pin = self.pendingPin {
                self.sendAuth(pin: pin)
            } else if let token = UserDefaults.standard.string(forKey: "auth_token") {
                self.sendAuth(token: token)
            }
        }
    }

    func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask, didCloseWith closeCode: URLSessionWebSocketTask.CloseCode, reason: Data?) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            if self.connectionStatus == .connecting || self.connectionStatus == .connected {
                self.retryCount += 1
                self.connectionStatus = .disconnected
                self.activeRequest = nil
                PhoneConnectivity.shared.syncActiveRequest(nil)
                self.scheduleAutoReconnect()
            }
        }
    }
}
