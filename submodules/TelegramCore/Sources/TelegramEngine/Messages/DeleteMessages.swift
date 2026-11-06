import Foundation
import Postbox
import SwiftSignalKit
import TelegramApi

func addMessageMediaResourceIdsToRemove(media: Media, resourceIds: inout [MediaResourceId]) {
    if let image = media as? TelegramMediaImage {
        for representation in image.representations {
            resourceIds.append(representation.resource.id)
        }
    } else if let file = media as? TelegramMediaFile {
        for representation in file.previewRepresentations {
            resourceIds.append(representation.resource.id)
        }
        resourceIds.append(file.resource.id)
    }
}

func addMessageMediaResourceIdsToRemove(message: Message, resourceIds: inout [MediaResourceId]) {
    for media in message.effectiveMedia {
        addMessageMediaResourceIdsToRemove(media: media, resourceIds: &resourceIds)
    }
}

public func _internal_deleteMessages(transaction: Transaction, mediaBox: MediaBox, ids: [MessageId], deleteMedia: Bool = true, manualAddMessageThreadStatsDifference: ((MessageThreadKey, Int, Int) -> Void)? = nil) {
    // Ghost Mode: snapshot before Postbox removal (covers interactive + server deletes).
    if UserDefaults.standard.bool(forKey: "GhostMode.saveDeletedMessages") {
        for id in ids {
            if let message = transaction.getMessage(id) {
                var mediaSummary: String? = nil
                if !message.media.isEmpty {
                    mediaSummary = String(describing: type(of: message.media[0]))
                }
                NotificationCenter.default.post(
                    name: Notification.Name("GhostModeCaptureDeletedMessage"),
                    object: nil,
                    userInfo: [
                        "messageId": Int64(message.id.id),
                        "peerId": message.id.peerId.toInt64(),
                        "authorId": message.author?.id.toInt64() as Any,
                        "text": message.text,
                        "date": message.timestamp,
                        "mediaSummary": mediaSummary as Any,
                        "flags": message.flags.rawValue,
                        "namespace": message.id.namespace
                    ]
                )
            }
        }
    }
    var resourceIds: [MediaResourceId] = []
    if deleteMedia {
        for id in ids {
            if id.peerId.namespace == Namespaces.Peer.SecretChat {
                if let message = transaction.getMessage(id) {
                    addMessageMediaResourceIdsToRemove(message: message, resourceIds: &resourceIds)
                }
            }
        }
    }
    if !resourceIds.isEmpty {
        let _ = mediaBox.removeCachedResources(Array(Set(resourceIds)), force: true).start()
    }
    for id in ids {
        if id.peerId.namespace == Namespaces.Peer.CloudChannel && id.namespace == Namespaces.Message.Cloud {
            if let message = transaction.getMessage(id) {
                if let threadId = message.threadId {
                    let messageThreadKey = MessageThreadKey(peerId: message.id.peerId, threadId: threadId)
                    if id.peerId.namespace == Namespaces.Peer.CloudChannel {
                        if let manualAddMessageThreadStatsDifference = manualAddMessageThreadStatsDifference {
                            manualAddMessageThreadStatsDifference(messageThreadKey, 0, 1)
                        } else {
                            updateMessageThreadStats(transaction: transaction, threadKey: messageThreadKey, removedCount: 1, addedMessagePeers: [])
                        }
                    }
                }
            }
        }
    }
    transaction.deleteMessages(ids, forEachMedia: { _ in
    })
}

func _internal_deleteAllMessagesWithAuthor(transaction: Transaction, mediaBox: MediaBox, peerId: PeerId, authorId: PeerId, namespace: MessageId.Namespace) {
    var resourceIds: [MediaResourceId] = []
    transaction.removeAllMessagesWithAuthor(peerId, authorId: authorId, namespace: namespace, forEachMedia: { media in
        addMessageMediaResourceIdsToRemove(media: media, resourceIds: &resourceIds)
    })
    if !resourceIds.isEmpty {
        let _ = mediaBox.removeCachedResources(Array(Set(resourceIds))).start()
    }
}

func _internal_deleteAllMessagesWithForwardAuthor(transaction: Transaction, mediaBox: MediaBox, peerId: PeerId, forwardAuthorId: PeerId, namespace: MessageId.Namespace) {
    var resourceIds: [MediaResourceId] = []
    transaction.removeAllMessagesWithForwardAuthor(peerId, forwardAuthorId: forwardAuthorId, namespace: namespace, forEachMedia: { media in
        addMessageMediaResourceIdsToRemove(media: media, resourceIds: &resourceIds)
    })
    if !resourceIds.isEmpty {
        let _ = mediaBox.removeCachedResources(Array(Set(resourceIds)), force: true).start()
    }
}
