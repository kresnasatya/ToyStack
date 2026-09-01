import AppKit

final class AccessibilityThread: NSObject, @unchecked Sendable {
    func speak(_ text: String) {
        print("ANNOUNCE:", text)
        NSAccessibility.post(
            element: NSApp!,
            notification: NSAccessibility.Notification.announcementRequested,
            userInfo: [
                NSAccessibility.NotificationUserInfoKey.announcement: text,
                NSAccessibility.NotificationUserInfoKey.priority: NSAccessibilityPriorityLevel.high.rawValue
            ]
        )
    }
}
