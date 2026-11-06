import Foundation

/// Simple local storage for Ghost Mode settings using Codable + file persistence.
/// Each Telegram account has its own JSON file under Application Support/GhostMode/accounts/.
public final class GhostModeStorage {
    private let queue = DispatchQueue(label: "org.biogram.ghostmode.storage", qos: .utility)
    private let accountsFolder: URL
    private var currentAccountId: String = "default"

    private var payload: GhostModeSettings = .defaultValue

    public init(baseDirectory: URL? = nil) {
        let base = baseDirectory
            ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())

        let folder = base.appendingPathComponent("GhostMode", isDirectory: true)
        let accounts = folder.appendingPathComponent("accounts", isDirectory: true)
        try? FileManager.default.createDirectory(at: accounts, withIntermediateDirectories: true, attributes: nil)
        self.accountsFolder = accounts
    }

    public func setCurrentAccountId(_ id: String) {
        self.queue.async {
            self.currentAccountId = self.safeAccountId(id)
        }
    }

    public func load(for accountId: String, completion: @escaping (GhostModeSettings) -> Void) {
        let normalizedId = self.safeAccountId(accountId)
        self.queue.async {
            self.currentAccountId = normalizedId

            let url = self.fileURL(for: normalizedId)
            if let data = try? Data(contentsOf: url),
               let decoded = try? JSONDecoder().decode(GhostModeSettings.self, from: data) {
                self.payload = decoded
            } else {
                self.payload = .defaultValue
                self.saveSync()
            }

            completion(self.payload)
        }
    }

    public func save(_ settings: GhostModeSettings, completion: (() -> Void)? = nil) {
        self.queue.async {
            self.payload = settings
            self.saveSync()
            completion?()
        }
    }

    private func fileURL(for accountId: String) -> URL {
        return self.accountsFolder.appendingPathComponent("\(self.safeAccountId(accountId)).json")
    }

    private func safeAccountId(_ id: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        let result = id.unicodeScalars.map { allowed.contains($0) ? Character($0) : "_" }
        let value = String(result)
        return value.isEmpty ? "default" : value
    }

    private func saveSync() {
        let url = self.fileURL(for: self.currentAccountId)
        guard let data = try? JSONEncoder().encode(self.payload) else {
            return
        }
        try? data.write(to: url, options: [.atomic])
    }
}
