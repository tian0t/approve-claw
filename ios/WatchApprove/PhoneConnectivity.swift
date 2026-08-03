import Foundation
import WatchConnectivity

class PhoneConnectivity: NSObject, WCSessionDelegate {
    static let shared = PhoneConnectivity()
    
    private var session: WCSession? {
        if WCSession.isSupported() {
            return WCSession.default
        }
        return nil
    }
    
    override init() {
        super.init()
        setupSession()
    }
    
    func setupSession() {
        guard let session = session else {
            print("WCSession is not supported on this device.")
            return
        }
        session.delegate = self
        session.activate()
        print("Phone WCSession initialized.")
    }
    
    // MARK: - Send request to Apple Watch
    func syncActiveRequest(_ request: ApprovalRequest?, status: String = "Disconnected", isPaired: Bool = false, ipAddress: String = "") {
        guard let session = session, session.activationState == .activated else {
            print("WCSession not active, cannot sync request.")
            return
        }
        
        var context: [String: Any] = [
            "connection_status": status,
            "is_paired": isPaired,
            "mac_ip": ipAddress
        ]
        
        if let request = request {
            do {
                let data = try JSONEncoder().encode(request)
                context["active_request_data"] = data
                print("Syncing request data to Watch.")
            } catch {
                print("Failed to encode request for Watch sync: \(error)")
            }
        } else {
            context["active_request_data"] = Data() // Empty data signals no request
            print("Clearing request on Watch.")
        }
        
        do {
            try session.updateApplicationContext(context)
        } catch {
            print("Failed to update application context: \(error)")
        }
    }
    
    // MARK: - Receive messages from Apple Watch
    func session(_ session: WCSession, didReceiveMessage message: [String : Any], replyHandler: @escaping ([String : Any]) -> Void) {
        print("Phone received message from Watch: \(message)")
        
        guard let action = message["action"] as? String,
              let requestId = message["requestId"] as? String else {
            replyHandler(["success": false, "error": "Invalid arguments"])
            return
        }
        
        DispatchQueue.main.async {
            if let wsManager = WebSocketManager.shared {
                let success = wsManager.sendDecision(requestId: requestId, action: action)
                replyHandler(["success": success])
            } else {
                replyHandler(["success": false, "error": "WebSocketManager not running"])
            }
        }
    }
    
    // MARK: - WCSessionDelegate conformance
    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        if let error = error {
            print("WCSession activation failed: \(error.localizedDescription)")
        } else {
            print("WCSession activated. State: \(activationState.rawValue)")
            // Resync current active request if one is pending
            if let wsManager = WebSocketManager.shared, let active = wsManager.activeRequest {
                syncActiveRequest(active)
            }
        }
    }
    
    func sessionDidBecomeInactive(_ session: WCSession) {
        print("WCSession became inactive.")
    }
    
    func sessionDidDeactivate(_ session: WCSession) {
        print("WCSession deactivated. Reactivating...")
        // Reactivate session as required by Apple guidelines when switching between watches
        self.session?.activate()
    }
}
