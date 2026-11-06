import Foundation

/// Snapshot of a message retained after it was deleted from the chat history.
public struct GhostModeDeletedMessage: Codable, Equatable, Identifiable {
    public var id: String
    public var messageId: Int64
    public var peerId: Int64
    public var authorId: Int64?
    public var text: String
    public var date: Int32
    public var mediaSummary: String?
    public var localMediaPath: String?
    public var deletedAt: TimeInterval

    public init(
        id: String = UUID().uuidString,
        messageId: Int64,
        peerId: Int64,
        authorId: Int64?,
        text: String,
        date: Int32,
        mediaSummary: String?,
        localMediaPath: String? = nil,
        deletedAt: TimeInterval = Date().timeIntervalSince1970
    ) {
        self.id = id
        self.messageId = messageId
        self.peerId = peerId
        self.authorId = authorId
        self.text = text
        self.date = date
        self.mediaSummary = mediaSummary
        self.localMediaPath = localMediaPath
        self.deletedAt = deletedAt
    }
}

/// JSON-backed store for deleted messages (per-account file under Application Support/GhostMode).
public final class GhostModeDeletedMessagesStorage {
    public static let shared = GhostModeDeletedMessagesStorage()

    private let queue = DispatchQueue(label: "org.rubygram.ghostmode.deleted", qos: .utility)
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    private var currentAccountId: String = "default"

    private init() {
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    }

    public func setAccountId(_ accountId: String) {
        self.queue.async {
            self.currentAccountId = accountId
        }
    }

    private func directory() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        let dir = base.appendingPathComponent("GhostMode", isDirectory: true)
            .appendingPathComponent("deleted", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private func fileURL(for accountId: String) -> URL {
        return self.directory().appendingPathComponent("\(accountId).json")
    }

    public func insert(_ message: GhostModeDeletedMessage, completion: (() -> Void)? = nil) {
        self.queue.async {
            var items = self.loadSync(accountId: self.currentAccountId)
            if items.contains(where: { $0.messageId == message.messageId && $0.peerId == message.peerId }) {
                DispatchQueue.main.async { completion?() }
                return
            }
            items.insert(message, at: 0)
            if items.count > 2000 {
                items = Array(items.prefix(2000))
            }
            self.saveSync(items, accountId: self.currentAccountId)
            DispatchQueue.main.async { completion?() }
        }
    }

    public func fetchAll(peerId: Int64? = nil, completion: @escaping ([GhostModeDeletedMessage]) -> Void) {
        self.queue.async {
            var items = self.loadSync(accountId: self.currentAccountId)
            if let peerId {
                items = items.filter { $0.peerId == peerId }
            }
            DispatchQueue.main.async { completion(items) }
        }
    }

    public func clear(completion: (() -> Void)? = nil) {
        self.queue.async {
            self.saveSync([], accountId: self.currentAccountId)
            DispatchQueue.main.async { completion?() }
        }
    }

    private func loadSync(accountId: String) -> [GhostModeDeletedMessage] {
        let url = self.fileURL(for: accountId)
        guard let data = try? Data(contentsOf: url),
              let items = try? self.decoder.decode([GhostModeDeletedMessage].self, from: data) else {
            return []
        }
        return items
    }

    private func saveSync(_ items: [GhostModeDeletedMessage], accountId: String) {
        let url = self.fileURL(for: accountId)
        guard let data = try? self.encoder.encode(items) else { return }
        try? data.write(to: url, options: [.atomic])
    }
}

/// Lightweight capture used from TelegramCore via NotificationCenter (no Biogram import needed there).
public enum GhostModeDeletedMessageCapture {
    public static let notificationName = Notification.Name("GhostModeCaptureDeletedMessage")

    public static func post(messageId: Int64, peerId: Int64, authorId: Int64?, text: String, date: Int32, mediaSummary: String?) {
        guard UserDefaults.standard.bool(forKey: "GhostMode.saveDeletedMessages") || UserDefaults.standard.bool(forKey: "GhostMode.saveDeletedMedia") else { return }
        let payload: [String: Any] = [
            "messageId": messageId,
            "peerId": peerId,
            "authorId": authorId as Any,
            "text": text,
            "date": date,
            "mediaSummary": mediaSummary as Any
        ]
        NotificationCenter.default.post(name: notificationName, object: nil, userInfo: payload)
    }
}
