import Foundation
import UserNotifications
#if os(iOS)
import UIKit
#elseif os(watchOS)
import WatchKit
#endif

class NotificationManager: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationManager()
    
    static let categoryIdentifier = "CLAW_APPROVAL_CATEGORY"
    static let approveActionIdentifier = "APPROVE_ACTION"
    static let rejectActionIdentifier = "REJECT_ACTION"
    
    override init() {
        super.init()
        UNUserNotificationCenter.current().delegate = self
        setupCategories()
    }
    
    func requestAuthorization() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge, .criticalAlert]) { granted, error in
            if granted {
                print("Notification permission granted.")
            } else if let error = error {
                print("Notification permission error: \(error.localizedDescription)")
            }
        }
    }
    
    private func setupCategories() {
        let approveAction = UNNotificationAction(
            identifier: Self.approveActionIdentifier,
            title: "✅ Approve",
            options: [.foreground]
        )
        
        let rejectAction = UNNotificationAction(
            identifier: Self.rejectActionIdentifier,
            title: "❌ Reject",
            options: [.destructive]
        )
        
        let category = UNNotificationCategory(
            identifier: Self.categoryIdentifier,
            actions: [approveAction, rejectAction],
            intentIdentifiers: [],
            options: [.customDismissAction]
        )
        
        UNUserNotificationCenter.current().setNotificationCategories([category])
    }
    
    func sendApprovalNotification(for request: ApprovalRequest) {
        // Trigger haptics
        #if os(iOS)
        DispatchQueue.main.async {
            let generator = UINotificationFeedbackGenerator()
            generator.notificationOccurred(.warning)
        }
        #elseif os(watchOS)
        WKInterfaceDevice.current().play(.notification)
        #endif
        
        let content = UNMutableNotificationContent()
        content.title = "🛡️ \(request.agent) Approval Required"
        content.subtitle = "Risk: \(request.risk.uppercased())"
        content.body = request.command
        content.sound = UNNotificationSound.default
        content.categoryIdentifier = Self.categoryIdentifier
        content.userInfo = [
          "requestId": request.id,
          "agent": request.agent,
          "command": request.command
        ]
        
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 0.1, repeats: false)
        let req = UNNotificationRequest(identifier: request.id, content: content, trigger: trigger)
        
        UNUserNotificationCenter.current().add(req) { error in
            if let error = error {
                print("Error posting notification: \(error.localizedDescription)")
            } else {
                print("Posted approval notification for request: \(request.id)")
            }
        }
    }
    
    // MARK: - UNUserNotificationCenterDelegate
    
    // Display banner notifications even when app is in foreground
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound, .badge, .list])
    }
    
    // Handle Quick Actions (Approve / Reject) directly from Notification Banner
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let userInfo = response.notification.request.content.userInfo
        guard let requestId = userInfo["requestId"] as? String else {
            completionHandler()
            return
        }
        
        let actionIdentifier = response.actionIdentifier
        let action: String?
        
        if actionIdentifier == Self.approveActionIdentifier {
            action = "approve"
        } else if actionIdentifier == Self.rejectActionIdentifier {
            action = "reject"
        } else {
            action = nil
        }
        
        if let action = action {
            print("Notification Quick Action triggered: \(action) for request: \(requestId)")
            
            #if os(iOS)
            WebSocketManager.shared?.sendDecision(requestId: requestId, action: action)
            #elseif os(watchOS)
            WatchConnectivityManager.shared.sendDecision(requestId: requestId, action: action)
            #endif
        }
        
        completionHandler()
    }
}
