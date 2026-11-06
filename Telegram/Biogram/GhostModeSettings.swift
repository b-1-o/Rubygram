import Foundation

/// Per-account Ghost Mode preferences.
/// All fields default to `false` so existing behaviour is unchanged until the user enables them.
public struct GhostModeSettings: Codable, Equatable {
    public var dontReadMessages: Bool
    public var dontSendOnline: Bool
    public var dontSendTyping: Bool
    public var dontSendUploadProgress: Bool
    public var saveDeletedMessages: Bool
    public var saveExpiringMedia: Bool

    public init(
        dontReadMessages: Bool = false,
        dontSendOnline: Bool = false,
        dontSendTyping: Bool = false,
        dontSendUploadProgress: Bool = false,
        saveDeletedMessages: Bool = false,
        saveExpiringMedia: Bool = false
    ) {
        self.dontReadMessages = dontReadMessages
        self.dontSendOnline = dontSendOnline
        self.dontSendTyping = dontSendTyping
        self.dontSendUploadProgress = dontSendUploadProgress
        self.saveDeletedMessages = saveDeletedMessages
        self.saveExpiringMedia = saveExpiringMedia
    }

    public static var defaultValue: GhostModeSettings {
        return GhostModeSettings()
    }
}
