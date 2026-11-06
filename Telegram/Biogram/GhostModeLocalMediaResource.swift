import Foundation
import Postbox
import TelegramCore

/// A file-backed resource for media copied by Ghost Mode before a Telegram message is removed.
///
/// The resource intentionally stores only a filesystem path. It does not own or delete the
/// original file: Ghost Mode keeps that copy under Application Support/GhostMode/media so
/// the deleted-message snapshot can recreate a normal Telegram media model later.
///
/// TelegramMediaResource inherits both MediaResource and PostboxCoding. In this checkout the
/// resource identity must be a Postbox MediaResourceId and equality is expressed through
/// isEqual(to:), rather than Swift's Equatable protocol. This implementation follows that
/// contract directly and does not introduce a second identity or a separate hash requirement.
public final class GhostModeLocalMediaResource: TelegramMediaResource {
    /// Absolute path to the durable Ghost Mode copy, not a temporary MediaBox cache path.
    public let path: String

    /// Use the path as the stable cache identity. A snapshot can therefore reconstruct this
    /// resource repeatedly and resolve the same completed MediaBox cache entry.
    public var id: MediaResourceId {
        return MediaResourceId("ghostmode-local:\(self.path)")
    }

    /// Report the source file size when it exists. Returning nil is valid for an unavailable
    /// file and lets Telegram's existing media model continue to use its optional size field.
    public var size: Int64? {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: self.path),
              let value = attributes[.size] as? NSNumber else {
            return nil
        }
        return value.int64Value
    }

    /// This resource is already a complete local file; it is not a remotely streamable item.
    public var streamable: Bool {
        return false
    }

    /// No special header is required by this file-backed resource.
    public var headerSize: Int32 {
        return 0
    }

    /// Creates a runtime resource from the path persisted in a Ghost Mode snapshot.
    public init(path: String) {
        self.path = path
    }

    /// Restores the path when Postbox decodes a serialized media object.
    public required init(decoder: PostboxDecoder) {
        self.path = decoder.decodeStringForKey("p", orElse: "")
    }

    /// Persists only the path. Media bytes remain in the durable Ghost Mode file and MediaBox
    /// is seeded from that file when the chat-history entry is reconstructed.
    public func encode(_ encoder: PostboxEncoder) {
        encoder.encodeString(self.path, forKey: "p")
    }

    /// Resources are equal when they refer to the same durable local copy.
    public func isEqual(to other: MediaResource) -> Bool {
        guard let other = other as? GhostModeLocalMediaResource else {
            return false
        }
        return self.path == other.path
    }
}
