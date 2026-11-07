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


// MARK: - Ghost Mode media preservation

private func ghostModeFileExtension(
    _ file: TelegramMediaFile
) -> String {

    let candidate = (
        (file.fileName ?? "") as NSString
    ).pathExtension.lowercased()

    if !candidate.isEmpty,
       candidate.range(
           of: "^[a-z0-9]{1,8}$",
           options: .regularExpression
       ) != nil {
        return candidate
    }

    switch file.mimeType.lowercased() {
    case "image/jpeg":
        return "jpg"
    case "image/png":
        return "png"
    case "image/webp":
        return "webp"
    case "image/gif":
        return "gif"
    case "video/mp4":
        return "mp4"
    case "video/quicktime":
        return "mov"
    case "audio/ogg", "application/ogg":
        return "ogg"
    case "audio/mpeg":
        return "mp3"
    case "audio/mp4", "audio/x-m4a":
        return "m4a"
    case "audio/aac":
        return "aac"
    default:
        return "bin"
    }
}


private func ghostModeCopyResource(
    mediaBox: MediaBox,
    resource: MediaResource,
    peerId: Int64,
    messageId: Int32,
    ext: String
) -> String? {

    guard let sourcePath = mediaBox.completedResourcePath(resource) else {
        return nil
    }

    let fileManager = FileManager.default

    guard fileManager.fileExists(atPath: sourcePath) else {
        return nil
    }

    guard let applicationSupport = fileManager.urls(
        for: .applicationSupportDirectory,
        in: .userDomainMask
    ).first else {
        return nil
    }

    let directory = applicationSupport
        .appendingPathComponent("GhostMode/media", isDirectory: true)
        .appendingPathComponent(String(peerId), isDirectory: true)

    let safeExtension = ext.lowercased()

    guard safeExtension.range(
        of: "^[a-z0-9]{1,8}$",
        options: .regularExpression
    ) != nil else {
        return nil
    }

    let target = directory.appendingPathComponent(
        "\(messageId).\(safeExtension)"
    )

    if fileManager.fileExists(atPath: target.path) {
        return target.path
    }

    do {
        try fileManager.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )

        try fileManager.copyItem(
            at: URL(fileURLWithPath: sourcePath),
            to: target
        )

        return target.path

    } catch {
        return nil
    }
}


// Capture a message before its expiring media is replaced or removed. The settings manager
// persists this notification using the same snapshot format as ordinary message deletion.
func ghostModeCaptureMessageSnapshot(message: Message, mediaBox: MediaBox, saveText: Bool, saveMedia: Bool) {
    guard saveText || saveMedia else { return }
    let hasSupportedMedia = message.media.contains { $0 is TelegramMediaImage || $0 is TelegramMediaFile }
    if !saveText && !hasSupportedMedia { return }

    var mediaSummary: String?
    if let firstMedia = message.media.first {
        mediaSummary = String(describing: type(of: firstMedia))
    }

    var localMediaPath: String?
    var capturedMediaType: String?
    var capturedMimeType: String?
    var capturedFileName: String?
    var capturedFileSize: Int64?
    var capturedDuration: Double?
    var capturedWidth: Int32?
    var capturedHeight: Int32?

    if saveMedia {
        let peerId = message.id.peerId.toInt64()
        let messageId = message.id.id

        // The snapshot format stores one resource per message; album support is separate.
        if let file = message.media.first(where: { $0 is TelegramMediaFile }) as? TelegramMediaFile {
            capturedMimeType = file.mimeType
            capturedFileName = file.fileName
            capturedFileSize = file.size

            var isVoice = false
            var isRoundVideo = false
            var isAnimated = false
            var hasVideoAttribute = false

            for attribute in file.attributes {
                switch attribute {
                case let .Audio(attributeIsVoice, attributeDuration, _, _, _):
                    capturedDuration = Double(attributeDuration)
                    if attributeIsVoice {
                        isVoice = true
                    }
                case let .Video(attributeDuration, dimensions, flags, _, _, _):
                    hasVideoAttribute = true
                    capturedDuration = attributeDuration
                    capturedWidth = dimensions.width
                    capturedHeight = dimensions.height
                    if flags.contains(.instantRoundVideo) {
                        isRoundVideo = true
                    }
                case let .ImageSize(dimensions):
                    capturedWidth = dimensions.width
                    capturedHeight = dimensions.height
                case .Animated:
                    isAnimated = true
                default:
                    break
                }
            }

            let normalizedMimeType = file.mimeType.lowercased()
            if isRoundVideo {
                capturedMediaType = "round"
            } else if isVoice {
                capturedMediaType = "voice"
            } else if isAnimated || normalizedMimeType == "image/gif" {
                capturedMediaType = "gif"
            } else if hasVideoAttribute || normalizedMimeType.hasPrefix("video/") {
                capturedMediaType = "video"
            } else if normalizedMimeType.hasPrefix("image/") {
                capturedMediaType = "image"
            } else {
                capturedMediaType = "file"
            }

            localMediaPath = ghostModeCopyResource(
                mediaBox: mediaBox,
                resource: file.resource,
                peerId: peerId,
                messageId: messageId,
                ext: ghostModeFileExtension(file)
            )
        } else if let image = message.media.first(where: { $0 is TelegramMediaImage }) as? TelegramMediaImage {
            capturedMediaType = "image"
            capturedMimeType = "image/jpeg"

            // Prefer the largest cached representation, but fall back to a smaller
            // completed representation when the full-size resource is not available.
            let representations = image.representations.sorted { lhs, rhs in
                let lhsArea = Int64(lhs.dimensions.width) * Int64(lhs.dimensions.height)
                let rhsArea = Int64(rhs.dimensions.width) * Int64(rhs.dimensions.height)
                return lhsArea > rhsArea
            }

            if let largestRepresentation = representations.first {
                capturedWidth = largestRepresentation.dimensions.width
                capturedHeight = largestRepresentation.dimensions.height
                capturedFileSize = largestRepresentation.resource.size
            }

            for representation in representations {
                if let copiedPath = ghostModeCopyResource(
                    mediaBox: mediaBox,
                    resource: representation.resource,
                    peerId: peerId,
                    messageId: messageId,
                    ext: "jpg"
                ) {
                    localMediaPath = copiedPath
                    capturedWidth = representation.dimensions.width
                    capturedHeight = representation.dimensions.height
                    capturedFileSize = representation.resource.size
                    break
                }
            }
        }

        if capturedFileSize == nil,
           let localMediaPath = localMediaPath,
           let fileAttributes = try? FileManager.default.attributesOfItem(atPath: localMediaPath),
           let size = fileAttributes[.size] as? NSNumber {
            capturedFileSize = size.int64Value
        }
    }

    // Keep media metadata even when its resource is not cached, so the deleted
    // messages UI can show a meaningful placeholder instead of dropping the event.

    var userInfo: [String: Any] = [
        "messageId": Int64(message.id.id),
        "peerId": message.id.peerId.toInt64(),
        "authorId": message.author?.id.toInt64() as Any,
        "text": saveText ? message.text : "",
        "date": message.timestamp,
        "mediaSummary": mediaSummary as Any,
        "flags": message.flags.rawValue,
        "namespace": message.id.namespace,
        "stableId": message.stableId
    ]
    if let localMediaPath { userInfo["localMediaPath"] = localMediaPath }
    if let capturedMediaType { userInfo["mediaType"] = capturedMediaType }
    if let capturedMimeType { userInfo["mimeType"] = capturedMimeType }
    if let capturedFileName { userInfo["fileName"] = capturedFileName }
    if let capturedFileSize { userInfo["fileSize"] = capturedFileSize }
    if let capturedDuration { userInfo["duration"] = capturedDuration }
    if let capturedWidth { userInfo["width"] = capturedWidth }
    if let capturedHeight { userInfo["height"] = capturedHeight }

    NotificationCenter.default.post(
        name: Notification.Name("GhostModeCaptureDeletedMessage"),
        object: nil,
        userInfo: userInfo
    )
}


public func _internal_deleteMessages(transaction: Transaction, mediaBox: MediaBox, ids: [MessageId], deleteMedia: Bool = true, manualAddMessageThreadStatsDifference: ((MessageThreadKey, Int, Int) -> Void)? = nil, captureGhostMode: Bool = true, accountPeerId: PeerId? = nil) {
    // Capture before media resource cleanup and message removal.
    if captureGhostMode {
        let saveDeletedMessages = UserDefaults.standard.bool(forKey: "GhostMode.saveDeletedMessages")
        let saveDeletedMedia = UserDefaults.standard.bool(forKey: "GhostMode.saveDeletedMedia")
        if saveDeletedMessages || saveDeletedMedia {
            for id in ids {
                if let message = transaction.getMessage(id) {
                    // Never keep snapshots of messages authored by the active account.
                    if let accountPeerId = accountPeerId, message.author?.id == accountPeerId {
                        continue
                    }
                    ghostModeCaptureMessageSnapshot(
                        message: message,
                        mediaBox: mediaBox,
                        saveText: saveDeletedMessages,
                        saveMedia: saveDeletedMedia
                    )
                }
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

func _internal_deleteAllReactionsWithAuthor(account: Account, peerId: PeerId, authorId: PeerId, aroundMessageId: MessageId?) -> Signal<Never, NoError> {
    return account.postbox.transaction { transaction -> (Peer?, Peer?) in
        let peer = transaction.getPeer(peerId)
        let author = transaction.getPeer(authorId)

        if peer.flatMap(apiInputPeer) != nil && author.flatMap(apiInputPeer) != nil {
            let anchor: HistoryViewInputAnchor
            if let aroundMessageId, aroundMessageId.peerId == peerId {
                anchor = .message(aroundMessageId)
            } else {
                anchor = .upperBound
            }
            let historyView = transaction.getMessagesHistoryViewState(input: .single(peerId: peerId, threadId: nil), ignoreMessagesInTimestampRange: nil, ignoreMessageIds: Set(), count: 50, clipHoles: true, anchor: anchor, namespaces: .just(Set([Namespaces.Message.Cloud])))
            for entry in historyView.entries {
                transaction.updateMessage(entry.message.id, update: { currentMessage in
                    var attributes = currentMessage.attributes
                    var updated = false

                    for i in 0 ..< attributes.count {
                        guard let attribute = attributes[i] as? ReactionsMessageAttribute else {
                            continue
                        }

                        let removedRecentPeers = attribute.recentPeers.filter { $0.peerId == authorId }
                        var updatedTopPeers = attribute.topPeers
                        var removedStarsTopPeerCount: Int32 = 0
                        for j in (0 ..< updatedTopPeers.count).reversed() {
                            if updatedTopPeers[j].peerId == authorId {
                                removedStarsTopPeerCount += updatedTopPeers[j].count
                                updatedTopPeers.remove(at: j)
                            }
                        }

                        if removedRecentPeers.isEmpty && removedStarsTopPeerCount == 0 {
                            continue
                        }

                        var updatedReactions = attribute.reactions
                        for removedRecentPeer in removedRecentPeers {
                            if let index = updatedReactions.firstIndex(where: { $0.value == removedRecentPeer.value }) {
                                if removedRecentPeer.value != .stars || removedStarsTopPeerCount == 0 {
                                    updatedReactions[index].count -= 1
                                }
                                if removedRecentPeer.isMy {
                                    updatedReactions[index].chosenOrder = nil
                                }
                            }
                        }
                        if removedStarsTopPeerCount != 0, let index = updatedReactions.firstIndex(where: { $0.value == .stars }) {
                            updatedReactions[index].count -= removedStarsTopPeerCount
                        }
                        for j in (0 ..< updatedReactions.count).reversed() {
                            if updatedReactions[j].count <= 0 {
                                updatedReactions.remove(at: j)
                            }
                        }

                        let updatedRecentPeers = attribute.recentPeers.filter { $0.peerId != authorId }
                        let updatedAttribute = ReactionsMessageAttribute(canViewList: attribute.canViewList, isTags: attribute.isTags, reactions: updatedReactions, recentPeers: updatedRecentPeers, topPeers: updatedTopPeers)
                        if updatedAttribute != attribute {
                            attributes[i] = updatedAttribute
                            updated = true
                        }
                    }

                    if !updated {
                        return .skip
                    }

                    var storeForwardInfo: StoreMessageForwardInfo?
                    if let forwardInfo = currentMessage.forwardInfo {
                        storeForwardInfo = StoreMessageForwardInfo(authorId: forwardInfo.author?.id, sourceId: forwardInfo.source?.id, sourceMessageId: forwardInfo.sourceMessageId, date: forwardInfo.date, authorSignature: forwardInfo.authorSignature, psaType: forwardInfo.psaType, flags: forwardInfo.flags)
                    }

                    var tags = currentMessage.tags
                    if attributes.contains(where: { ($0 as? ReactionsMessageAttribute)?.hasUnseen == true }) {
                        tags.insert(.unseenReaction)
                    } else {
                        tags.remove(.unseenReaction)
                    }

                    return .update(StoreMessage(id: currentMessage.id, customStableId: nil, globallyUniqueId: currentMessage.globallyUniqueId, groupingKey: currentMessage.groupingKey, threadId: currentMessage.threadId, timestamp: currentMessage.timestamp, flags: StoreMessageFlags(currentMessage.flags), tags: tags, globalTags: currentMessage.globalTags, localTags: currentMessage.localTags, forwardInfo: storeForwardInfo, authorId: currentMessage.author?.id, text: currentMessage.text, attributes: attributes, media: currentMessage.media))
                })
            }
        }

        return (peer, author)
    }
    |> mapToSignal { peer, author in
        guard let inputPeer = peer.flatMap(apiInputPeer), let inputAuthor = author.flatMap(apiInputPeer) else {
            return .complete()
        }
        return account.network.request(Api.functions.messages.deleteParticipantReactions(peer: inputPeer, participant: inputAuthor))
        |> ignoreValues
        |> `catch` { _ -> Signal<Never, NoError> in
            return .complete()
        }
    }
}

func _internal_deleteReaction(account: Account, messageId: MessageId, authorId: PeerId) -> Signal<Never, NoError> {
    return account.postbox.transaction { transaction -> (Peer?, Peer?) in
        let peer = transaction.getPeer(messageId.peerId)
        let author = transaction.getPeer(authorId)

        if peer.flatMap(apiInputPeer) != nil && author.flatMap(apiInputPeer) != nil {
            transaction.updateMessage(messageId, update: { currentMessage in
                var attributes = currentMessage.attributes
                var updated = false

                for i in 0 ..< attributes.count {
                    guard let attribute = attributes[i] as? ReactionsMessageAttribute else {
                        continue
                    }

                    let removedRecentPeers = attribute.recentPeers.filter { $0.peerId == authorId }
                    var updatedTopPeers = attribute.topPeers
                    var removedStarsTopPeerCount: Int32 = 0
                    for j in (0 ..< updatedTopPeers.count).reversed() {
                        if updatedTopPeers[j].peerId == authorId {
                            removedStarsTopPeerCount += updatedTopPeers[j].count
                            updatedTopPeers.remove(at: j)
                        }
                    }

                    if removedRecentPeers.isEmpty && removedStarsTopPeerCount == 0 {
                        continue
                    }

                    var updatedReactions = attribute.reactions
                    for removedRecentPeer in removedRecentPeers {
                        if let index = updatedReactions.firstIndex(where: { $0.value == removedRecentPeer.value }) {
                            if removedRecentPeer.value != .stars || removedStarsTopPeerCount == 0 {
                                updatedReactions[index].count -= 1
                            }
                            if removedRecentPeer.isMy {
                                updatedReactions[index].chosenOrder = nil
                            }
                        }
                    }
                    if removedStarsTopPeerCount != 0, let index = updatedReactions.firstIndex(where: { $0.value == .stars }) {
                        updatedReactions[index].count -= removedStarsTopPeerCount
                    }
                    for j in (0 ..< updatedReactions.count).reversed() {
                        if updatedReactions[j].count <= 0 {
                            updatedReactions.remove(at: j)
                        }
                    }

                    let updatedRecentPeers = attribute.recentPeers.filter { $0.peerId != authorId }
                    let updatedAttribute = ReactionsMessageAttribute(canViewList: attribute.canViewList, isTags: attribute.isTags, reactions: updatedReactions, recentPeers: updatedRecentPeers, topPeers: updatedTopPeers)
                    if updatedAttribute != attribute {
                        attributes[i] = updatedAttribute
                        updated = true
                    }
                }

                if !updated {
                    return .skip
                }

                var storeForwardInfo: StoreMessageForwardInfo?
                if let forwardInfo = currentMessage.forwardInfo {
                    storeForwardInfo = StoreMessageForwardInfo(authorId: forwardInfo.author?.id, sourceId: forwardInfo.source?.id, sourceMessageId: forwardInfo.sourceMessageId, date: forwardInfo.date, authorSignature: forwardInfo.authorSignature, psaType: forwardInfo.psaType, flags: forwardInfo.flags)
                }

                var tags = currentMessage.tags
                if attributes.contains(where: { ($0 as? ReactionsMessageAttribute)?.hasUnseen == true }) {
                    tags.insert(.unseenReaction)
                } else {
                    tags.remove(.unseenReaction)
                }

                return .update(StoreMessage(id: currentMessage.id, customStableId: nil, globallyUniqueId: currentMessage.globallyUniqueId, groupingKey: currentMessage.groupingKey, threadId: currentMessage.threadId, timestamp: currentMessage.timestamp, flags: StoreMessageFlags(currentMessage.flags), tags: tags, globalTags: currentMessage.globalTags, localTags: currentMessage.localTags, forwardInfo: storeForwardInfo, authorId: currentMessage.author?.id, text: currentMessage.text, attributes: attributes, media: currentMessage.media))
            })
        }

        return (peer, author)
    }
    |> mapToSignal { peer, author in
        guard let inputPeer = peer.flatMap(apiInputPeer), let inputAuthor = author.flatMap(apiInputPeer) else {
            return .complete()
        }
        return account.network.request(Api.functions.messages.deleteParticipantReaction(peer: inputPeer, msgId: messageId.id, participant: inputAuthor))
        |> map(Optional.init)
        |> `catch` { _ -> Signal<Api.Updates?, NoError> in
            return .single(nil)
        }
        |> mapToSignal { updates -> Signal<Never, NoError> in
            if let updates {
                account.stateManager.addUpdates(updates)
            }
            return .complete()
        }
    }
}

func _internal_clearHistory(transaction: Transaction, mediaBox: MediaBox, peerId: PeerId, threadId: Int64?, namespaces: MessageIdNamespaces) {
    if peerId.namespace == Namespaces.Peer.SecretChat {
        var resourceIds: [MediaResourceId] = []
        transaction.withAllMessages(peerId: peerId, { message in
            addMessageMediaResourceIdsToRemove(message: message, resourceIds: &resourceIds)
            return true
        })
        if !resourceIds.isEmpty {
            let _ = mediaBox.removeCachedResources(Array(Set(resourceIds)), force: true).start()
        }
    }
    transaction.clearHistory(peerId, threadId: threadId, minTimestamp: nil, maxTimestamp: nil, namespaces: namespaces, forEachMedia: { _ in
    })
}

func _internal_clearHistoryInRange(transaction: Transaction, mediaBox: MediaBox, peerId: PeerId, threadId: Int64?, minTimestamp: Int32, maxTimestamp: Int32, namespaces: MessageIdNamespaces) {
    if peerId.namespace == Namespaces.Peer.SecretChat {
        var resourceIds: [MediaResourceId] = []
        transaction.withAllMessages(peerId: peerId, { message in
            if message.timestamp >= minTimestamp && message.timestamp <= maxTimestamp {
                addMessageMediaResourceIdsToRemove(message: message, resourceIds: &resourceIds)
            }
            return true
        })
        if !resourceIds.isEmpty {
            let _ = mediaBox.removeCachedResources(Array(Set(resourceIds)), force: true).start()
        }
    }
    transaction.clearHistory(peerId, threadId: threadId, minTimestamp: minTimestamp, maxTimestamp: maxTimestamp, namespaces: namespaces, forEachMedia: { _ in
    })
}

public enum ClearCallHistoryError {
    case generic
}

func _internal_clearCallHistory(account: Account, forEveryone: Bool) -> Signal<Never, ClearCallHistoryError> {
    return account.postbox.transaction { transaction -> Signal<Void, NoError> in
        var flags: Int32 = 0
        if forEveryone {
            flags |= 1 << 0
        }
        
        let signal = account.network.request(Api.functions.messages.deletePhoneCallHistory(flags: flags))
        |> map { result -> Api.messages.AffectedFoundMessages? in
            return result
        }
        |> `catch` { _ -> Signal<Api.messages.AffectedFoundMessages?, Bool> in
            return .fail(false)
        }
        |> mapToSignal { result -> Signal<Void, Bool> in
            if let result = result {
                switch result {
                case let .affectedFoundMessages(affectedFoundMessagesData):
                    let (pts, ptsCount, offset) = (affectedFoundMessagesData.pts, affectedFoundMessagesData.ptsCount, affectedFoundMessagesData.offset)
                    account.stateManager.addUpdateGroups([.updatePts(pts: pts, ptsCount: ptsCount)])
                    if offset == 0 {
                        return .fail(true)
                    } else {
                        return .complete()
                    }
                }
            } else {
                return .fail(true)
            }
        }
        return (signal
        |> restart)
        |> `catch` { success -> Signal<Void, NoError> in
            if success {
                return account.postbox.transaction { transaction -> Void in
                    transaction.removeAllMessagesWithGlobalTag(tag: GlobalMessageTags.Calls)
                }
            } else {
                return .complete()
            }
        }
    }
    |> switchToLatest
    |> ignoreValues
    |> castError(ClearCallHistoryError.self)
}

public enum SetChatMessageAutoremoveTimeoutError {
    case generic
}

func _internal_setChatMessageAutoremoveTimeoutInteractively(account: Account, peerId: PeerId, timeout: Int32?) -> Signal<Never, SetChatMessageAutoremoveTimeoutError> {
    return account.postbox.transaction { transaction -> Api.InputPeer? in
        return transaction.getPeer(peerId).flatMap(apiInputPeer)
    }
    |> castError(SetChatMessageAutoremoveTimeoutError.self)
    |> mapToSignal { inputPeer -> Signal<Never, SetChatMessageAutoremoveTimeoutError> in
        guard let inputPeer = inputPeer else {
            return .fail(.generic)
        }
        return account.network.request(Api.functions.messages.setHistoryTTL(peer: inputPeer, period: timeout ?? 0))
        |> map(Optional.init)
        |> `catch` { _ -> Signal<Api.Updates?, NoError> in
            return .single(nil)
        }
        |> castError(SetChatMessageAutoremoveTimeoutError.self)
        |> mapToSignal { result -> Signal<Never, SetChatMessageAutoremoveTimeoutError> in
            if let result = result {
                account.stateManager.addUpdates(result)
                
                return account.postbox.transaction { transaction -> Void in
                    transaction.updatePeerCachedData(peerIds: [peerId], update: { _, current in
                        let updatedTimeout: CachedPeerAutoremoveTimeout
                        if let timeout = timeout {
                            updatedTimeout = .known(CachedPeerAutoremoveTimeout.Value(peerValue: timeout))
                        } else {
                            updatedTimeout = .known(nil)
                        }
                        
                        if peerId.namespace == Namespaces.Peer.CloudUser {
                            let current = (current as? CachedUserData) ?? CachedUserData()
                            return current.withUpdatedAutoremoveTimeout(updatedTimeout)
                        } else if peerId.namespace == Namespaces.Peer.CloudChannel {
                            let current = (current as? CachedChannelData) ?? CachedChannelData()
                            return current.withUpdatedAutoremoveTimeout(updatedTimeout)
                        } else if peerId.namespace == Namespaces.Peer.CloudGroup {
                            let current = (current as? CachedGroupData) ?? CachedGroupData()
                            return current.withUpdatedAutoremoveTimeout(updatedTimeout)
                        } else {
                            return current
                        }
                    })
                }
                |> castError(SetChatMessageAutoremoveTimeoutError.self)
                |> ignoreValues
            } else {
                return .fail(.generic)
            }
        }
        |> `catch` { _ -> Signal<Never, SetChatMessageAutoremoveTimeoutError> in
            return .complete()
        }
    }
}
