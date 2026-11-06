import Foundation

public extension Notification.Name {
    static let ghostModeSettingsDidChange = Notification.Name("GhostModeSettingsDidChange")
    static let ghostModeAccountDidLoad = Notification.Name("GhostModeAccountDidLoad")
}

/// Singleton manager that exposes current Ghost Mode settings for the active Telegram account.
/// Settings are local-only and stored separately for every account.
public final class GhostModeSettingsManager {
    public static let shared = GhostModeSettingsManager()

    private let storage: GhostModeStorage

    private var currentAccountId: String = "default"
    private var switchGeneration: UInt64 = 0
    private var loadedAccountId: String?

    private var cachedSettings: GhostModeSettings = .defaultValue

    private init(storageBase: URL? = nil) {
        self.storage = GhostModeStorage(baseDirectory: storageBase)
        self.registerDeletedMessageCaptureObserver()
    }

    private func registerDeletedMessageCaptureObserver() {
        NotificationCenter.default.addObserver(
            forName: Notification.Name("GhostModeCaptureDeletedMessage"),
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard UserDefaults.standard.bool(forKey: "GhostMode.saveDeletedMessages") || UserDefaults.standard.bool(forKey: "GhostMode.saveDeletedMedia") else { return }
            guard let info = notification.userInfo else { return }
            let messageId = (info["messageId"] as? Int64) ?? 0
            let peerId = (info["peerId"] as? Int64) ?? 0
            let authorId = info["authorId"] as? Int64
            let text = (info["text"] as? String) ?? ""
            let date = (info["date"] as? Int32) ?? 0
            let mediaSummary = info["mediaSummary"] as? String
            let localMediaPath = info["localMediaPath"] as? String
            let mediaType = info["mediaType"] as? String
            let mimeType = info["mimeType"] as? String
            let fileName = info["fileName"] as? String
            let fileSize = info["fileSize"] as? Int64
            let duration = info["duration"] as? Double
            let width = info["width"] as? Int32
            let height = info["height"] as? Int32
            let namespace = info["namespace"] as? Int32
            let flags = info["flags"] as? UInt32
            let stableId = info["stableId"] as? UInt32
            if let accountId = self?.currentAccountId {
                GhostModeDeletedMessagesStorage.shared.setAccountId(accountId)
            }
            GhostModeDeletedMessagesStorage.shared.insert(
                GhostModeDeletedMessage(
                    messageId: messageId,
                    peerId: peerId,
                    authorId: authorId,
                    text: text,
                    date: date,
                    mediaSummary: mediaSummary,
                    localMediaPath: localMediaPath,
                    mediaType: mediaType,
                    mimeType: mimeType,
                    fileName: fileName,
                    fileSize: fileSize,
                    duration: duration,
                    width: width,
                    height: height,
                    namespace: namespace,
                    flags: flags,
                    stableId: stableId
                )
            )
        }
    }

    // MARK: - Account

    public var isLoaded: Bool {
        return self.loadedAccountId != nil && self.loadedAccountId == self.currentAccountId
    }

    public var activeAccountId: String {
        return self.currentAccountId
    }

    /// Current settings for the active account. Safe to read from any thread after load.
    public var settings: GhostModeSettings {
        return self.cachedSettings
    }

    /// Switch local Ghost Mode state to a Telegram account.
    /// Completion is called on the main queue after JSON is loaded.
    public func switchToAccount(accountId: String, completion: (() -> Void)? = nil) {
        if !Thread.isMainThread {
            DispatchQueue.main.async { [weak self] in
                self?.switchToAccount(accountId: accountId, completion: completion)
            }
            return
        }

        if accountId == self.loadedAccountId {
            completion?()
            return
        }

        self.currentAccountId = accountId
        self.switchGeneration &+= 1
        let generation = self.switchGeneration

        self.storage.setCurrentAccountId(accountId)

        self.storage.load(for: accountId) { [weak self] settings in
            guard let self else { return }

            DispatchQueue.main.async { [weak self] in
                guard let self else { return }

                guard generation == self.switchGeneration,
                      accountId == self.currentAccountId else {
                    return
                }

                self.cachedSettings = settings
                self.loadedAccountId = accountId
                Self.syncRuntimeFlags(settings)
                GhostModeDeletedMessagesStorage.shared.setAccountId(accountId)

                NotificationCenter.default.post(name: .ghostModeAccountDidLoad, object: self)
                NotificationCenter.default.post(name: .ghostModeSettingsDidChange, object: self)

                completion?()
            }
        }
    }

    /// Call as early as possible when AccountContext is ready (app launch / account switch).
    /// Safe to call repeatedly.
    public func ensureAccountLoaded(accountId: String, completion: (() -> Void)? = nil) {
        self.switchToAccount(accountId: accountId, completion: completion)
    }

    // MARK: - Mutations

    public func updateSettings(_ transform: (inout GhostModeSettings) -> Void, completion: (() -> Void)? = nil) {
        assert(Thread.isMainThread)

        var next = self.cachedSettings
        transform(&next)

        guard next != self.cachedSettings else {
            completion?()
            return
        }

        self.cachedSettings = next
        Self.syncRuntimeFlags(next)
        NotificationCenter.default.post(name: .ghostModeSettingsDidChange, object: self)

        self.storage.save(next) {
            DispatchQueue.main.async {
                completion?()
            }
        }
    }

    public func setDontReadMessages(_ value: Bool, completion: (() -> Void)? = nil) {
        self.updateSettings({ $0.dontReadMessages = value }, completion: completion)
    }

    public func setDontSendOnline(_ value: Bool, completion: (() -> Void)? = nil) {
        self.updateSettings({ $0.dontSendOnline = value }, completion: completion)
    }

    public func setDontSendTyping(_ value: Bool, completion: (() -> Void)? = nil) {
        self.updateSettings({ $0.dontSendTyping = value }, completion: completion)
    }

    public func setDontSendUploadProgress(_ value: Bool, completion: (() -> Void)? = nil) {
        self.updateSettings({ $0.dontSendUploadProgress = value }, completion: completion)
    }

    public func setSaveDeletedMessages(_ value: Bool, completion: (() -> Void)? = nil) {
        self.updateSettings({ $0.saveDeletedMessages = value }, completion: completion)
    }

    public func setSaveDeletedMedia(_ value: Bool, completion: (() -> Void)? = nil) {
        self.updateSettings({ $0.saveDeletedMedia = value }, completion: completion)
    }

    public func setSaveExpiringMedia(_ value: Bool, completion: (() -> Void)? = nil) {
        self.updateSettings({ $0.saveExpiringMedia = value }, completion: completion)
    }

    /// Mirrors settings into UserDefaults so TelegramCore can read flags without importing Biogram.
    private static func syncRuntimeFlags(_ settings: GhostModeSettings) {
        let defaults = UserDefaults.standard
        defaults.set(settings.dontReadMessages, forKey: "GhostMode.dontReadMessages")
        defaults.set(settings.dontSendOnline, forKey: "GhostMode.dontSendOnline")
        defaults.set(settings.dontSendTyping, forKey: "GhostMode.dontSendTyping")
        defaults.set(settings.dontSendUploadProgress, forKey: "GhostMode.dontSendUploadProgress")
        defaults.set(settings.saveDeletedMessages, forKey: "GhostMode.saveDeletedMessages")
        defaults.set(settings.saveDeletedMedia, forKey: "GhostMode.saveDeletedMedia")
        defaults.set(settings.saveExpiringMedia, forKey: "GhostMode.saveExpiringMedia")
    }
}
