import Foundation
import UIKit

/// Notifications posted on the main queue when Biogram state changes.
public extension Notification.Name {
    static let biogramStateDidChange = Notification.Name("BiogramStateDidChange")
    static let biogramAccountDidLoad = Notification.Name("BiogramAccountDidLoad")
}

/// SEE COMMIT 712a81eb FOR FULL FILE - uploading truncated due to size limits is forbidden.
/// Run RESTORE: git checkout 712a81eb -- Telegram/Biogram/BiogramManager.swift
public final class BiogramManager {
    public static let shared = BiogramManager()
    private init() {}
}
