import Foundation
import WatchConnectivity
import WatchKit

class WatchConnectivityManager: NSObject, ObservableObject, WCSessionDelegate {
    static let shared = WatchConnectivityManager()
    
    @Published var activeRequest: ApprovalRequest? = nil
    @Published var connectionStatus: String = "Disconnected"
    @Published var isPaired: Bool = false
    @Published var macIP: String = ""
    
    private var session: WCSession {
        return WCSession.default
    }
    
    override init() {
        super.init()
        setupSession()
    }
    
    func setupSession() {
        if WCSession.isSupported() {
            session.delegate = self
            session.activate()
            print("Watch WCSession initialized.")
        }
    }
    
    func sendDecision(requestId: String, action: String) {
        guard session.activationState == .activated else {
            print("WCSession not active on Watch.")
            return
        }
        
        let message = [
            "action": action,
            "requestId": requestId
        ]
        
        print("Sending decision from Watch: \(message)")
        
        session.sendMessage(message, replyHandler: { [weak self] reply in
            print("Received reply from phone: \(reply)")
            if let success = reply["success"] as? Bool, success {
                DispatchQueue.main.async {
                    self?.activeRequest = nil
                }
            }
        }, errorHandler: { error in
            print("Failed to send decision to phone: \(error.localizedDescription)")
        })
    }
    
    // MARK: - WCSessionDelegate
    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        if let error = error {
            print("Watch WCSession activation failed: \(error.localizedDescription)")
        } else {
            print("Watch WCSession activated. State: \(activationState.rawValue)")
            
            // Check initial application context if available
            DispatchQueue.main.async {
                self.processContext(session.receivedApplicationContext)
            }
        }
    }
    
    func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String : Any]) {
        print("Watch received application context: \(applicationContext)")
        DispatchQueue.main.async {
            self.processContext(applicationContext)
        }
    }
    
    private func processContext(_ context: [String: Any]) {
        if let status = context["connection_status"] as? String {
            self.connectionStatus = status
        }
        if let paired = context["is_paired"] as? Bool {
            self.isPaired = paired
        }
        if let ip = context["mac_ip"] as? String, !ip.isEmpty {
            self.macIP = ip
        }
        
        guard let data = context["active_request_data"] as? Data else { return }
        
        if data.isEmpty {
            self.activeRequest = nil
            print("Watch cleared active request.")
        } else {
            do {
                let request = try JSONDecoder().decode(ApprovalRequest.self, from: data)
                
                // If it's a new request, trigger haptics & system notification
                if self.activeRequest?.id != request.id {
                    NotificationManager.shared.sendApprovalNotification(for: request)
                    print("New request on Watch! Triggered notification and haptic feedback.")
                }
                
                self.activeRequest = request
                print("Watch set active request: \(request.command)")
            } catch {
                print("Failed to decode synced request on Watch: \(error)")
            }
        }
    }
}
