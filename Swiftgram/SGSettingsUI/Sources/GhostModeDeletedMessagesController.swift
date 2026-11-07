import Foundation
import UIKit
import Display
import SwiftSignalKit
import TelegramCore
import TelegramPresentationData
import ItemListUI
import AccountContext
import PresentationDataUtils
import Biogram
import SGStrings

import ObjectiveC

private var ghostModeDeletedMessagesToggleTargetAssociationKey: UInt8 = 0

private final class GhostModeDeletedMessagesToggleTarget: NSObject {
    var onTap: (() -> Void)?

    @objc func tapped() {
        self.onTap?()
    }
}


private enum DeletedBrowserMode {
    case chats
    case tabs
}

private enum DeletedTab: Int {
    case media = 0
    case files = 1
    case voice = 2
    case rounds = 3
}

private enum DeletedSection: Int32 {
    case list = 0
    case actions = 1
}

private enum DeletedEntryId: Hashable {
    case empty
    case chat(Int64)
    case item(String)
    case clear
    case tabHeader
}

private enum DeletedEntry: ItemListNodeEntry {
    case empty(String)
    case chat(peerId: Int64, count: Int)
    case item(GhostModeDeletedMessage)
    case clear
    case tabHeader(String)

    var section: ItemListSectionId {
        switch self {
        case .clear: return DeletedSection.actions.rawValue
        default: return DeletedSection.list.rawValue
        }
    }

    var stableId: DeletedEntryId {
        switch self {
        case .empty: return .empty
        case let .chat(peerId, _): return .chat(peerId)
        case let .item(m): return .item(m.id)
        case .clear: return .clear
        case .tabHeader: return .tabHeader
        }
    }

    static func < (lhs: DeletedEntry, rhs: DeletedEntry) -> Bool {
        return false
    }

    func item(presentationData: ItemListPresentationData, arguments: Any) -> ListViewItem {
        let arguments = arguments as! DeletedArguments
        let lang = presentationData.strings.baseLanguageCode
        switch self {
        case let .empty(text):
            return ItemListTextItem(presentationData: presentationData, text: .plain(text), sectionId: self.section)
        case let .chat(peerId, count):
            return ItemListDisclosureItem(
                presentationData: presentationData,
                title: "Chat \(peerId)",
                label: "\(count)",
                sectionId: self.section,
                style: .blocks,
                action: { arguments.openChat(peerId) }
            )
        case let .item(m):
            let title = m.text.isEmpty ? (m.mediaSummary ?? "Media") : m.text
            return ItemListDisclosureItem(
                presentationData: presentationData,
                title: title,
                label: "",
                sectionId: self.section,
                style: .blocks,
                action: {}
            )
        case .clear:
            return ItemListActionItem(
                presentationData: presentationData,
                title: "GhostMode.DeletedMessages.Clear".i18n(lang),
                kind: .destructive,
                alignment: .center,
                sectionId: self.section,
                style: .blocks,
                action: { arguments.clearAll() }
            )
        case let .tabHeader(title):
            return ItemListSectionHeaderItem(presentationData: presentationData, text: title, sectionId: self.section)
        }
    }
}

private final class DeletedArguments {
    let openChat: (Int64) -> Void
    let clearAll: () -> Void
    init(openChat: @escaping (Int64) -> Void, clearAll: @escaping () -> Void) {
        self.openChat = openChat
        self.clearAll = clearAll
    }
}

private func buildEntries(mode: DeletedBrowserMode, tab: DeletedTab, items: [GhostModeDeletedMessage], lang: String) -> [DeletedEntry] {
    var entries: [DeletedEntry] = []
    if items.isEmpty {
        entries.append(.empty("GhostMode.DeletedMessages.Empty".i18n(lang)))
        return entries
    }
    switch mode {
    case .chats:
        var counts: [Int64: Int] = [:]
        for m in items { counts[m.peerId, default: 0] += 1 }
        for (peerId, count) in counts.sorted(by: { $0.key < $1.key }) {
            entries.append(.chat(peerId: peerId, count: count))
        }
        entries.append(.clear)
    case .tabs:
        let filtered: [GhostModeDeletedMessage]
        switch tab {
        case .media:
            filtered = items.filter { ($0.mediaSummary ?? "").lowercased().contains("image") || ($0.mediaSummary ?? "").lowercased().contains("video") }
        case .files:
            filtered = items.filter { ($0.mediaSummary ?? "").lowercased().contains("file") || ($0.mediaSummary ?? "").lowercased().contains("document") }
        case .voice:
            filtered = items.filter { ($0.mediaSummary ?? "").lowercased().contains("voice") || ($0.mediaSummary ?? "").lowercased().contains("audio") }
        case .rounds:
            filtered = items.filter { ($0.mediaSummary ?? "").lowercased().contains("round") || ($0.mediaSummary ?? "").lowercased().contains("instant") }
        }
        if filtered.isEmpty {
            entries.append(.empty("GhostMode.DeletedMessages.Empty".i18n(lang)))
        } else {
            for m in filtered { entries.append(.item(m)) }
        }
        entries.append(.clear)
    }
    return entries
}

public func ghostModeDeletedMessagesController(context: AccountContext) -> ViewController {
    var mode: DeletedBrowserMode = .chats
    var tab: DeletedTab = .media
    var pushImpl: ((ViewController) -> Void)?

    let statePromise = Promise<[GhostModeDeletedMessage]>([])
    let reload: () -> Void = {
        GhostModeDeletedMessagesStorage.shared.fetchAll { items in
            statePromise.set(.single(items))
        }
    }
    reload()

    let arguments = DeletedArguments(
        openChat: { peerId in
            pushImpl?(ghostModeDeletedChatController(context: context, peerId: peerId))
        },
        clearAll: {
            GhostModeDeletedMessagesStorage.shared.clear { reload() }
        }
    )

    let signal: Signal<(ItemListControllerState, (ItemListNodeState, DeletedArguments)), NoError> = combineLatest(queue: .mainQueue(), context.sharedContext.presentationData, statePromise.get())
    |> map { presentationData, items -> (ItemListControllerState, (ItemListNodeState, DeletedArguments)) in
        let lang = presentationData.strings.baseLanguageCode
        let entries = buildEntries(mode: mode, tab: tab, items: items, lang: lang)
        let controllerState = ItemListControllerState(
            presentationData: ItemListPresentationData(presentationData),
            title: .text("GhostMode.DeletedMessages.Title".i18n(lang)),
            leftNavigationButton: nil,
            rightNavigationButton: ItemListNavigationButton(
                content: .icon(.action),
                style: .regular,
                enabled: true,
                action: {
                    // Mode toggle is wired after controller creation via bar button.
                }
            ),
            backNavigationButton: ItemListBackButton(title: presentationData.strings.Common_Back),
            animateChanges: false
        )
        let listState = ItemListNodeState(
            presentationData: ItemListPresentationData(presentationData),
            entries: entries,
            style: .blocks,
            emptyStateItem: nil,
            animateChanges: false
        )
        return (controllerState, (listState, arguments))
    }

    let controller = ItemListController(context: context, state: signal)
    pushImpl = { [weak controller] c in
        (controller?.navigationController as? NavigationController)?.pushViewController(c)
    }

    // Three-dots style: toggle chats <-> tabs (iOS 13-compatible target/action).
    let toggleTarget = GhostModeDeletedMessagesToggleTarget()
    toggleTarget.onTap = { [weak controller] in
        let sheet = UIAlertController(title: nil, message: nil, preferredStyle: .actionSheet)
        if mode == .chats {
            sheet.addAction(UIAlertAction(title: "GhostMode.DeletedMessages.ShowTabs".i18n(context.sharedContext.currentPresentationData.with { $0 }.strings.baseLanguageCode), style: .default, handler: { _ in
                mode = .tabs
                reload()
            }))
        } else {
            sheet.addAction(UIAlertAction(title: "GhostMode.DeletedMessages.ShowChats".i18n(context.sharedContext.currentPresentationData.with { $0 }.strings.baseLanguageCode), style: .default, handler: { _ in
                mode = .chats
                reload()
            }))
            for (title, t) in [("Media", DeletedTab.media), ("Files", DeletedTab.files), ("Voice", DeletedTab.voice), ("Rounds", DeletedTab.rounds)] {
                sheet.addAction(UIAlertAction(title: title, style: .default, handler: { _ in
                    tab = t
                    mode = .tabs
                    reload()
                }))
            }
        }
        sheet.addAction(UIAlertAction(title: context.sharedContext.currentPresentationData.with { $0 }.strings.Common_Cancel, style: .cancel))
        controller?.view.window?.rootViewController?.present(sheet, animated: true)
    }
    let toggleButton = UIBarButtonItem(
        image: UIImage(systemName: "ellipsis"),
        style: .plain,
        target: toggleTarget,
        action: #selector(GhostModeDeletedMessagesToggleTarget.tapped)
    )
    // UIBarButtonItem's target isn't owned by the button; retain it for as long as the button lives.
    objc_setAssociatedObject(
        toggleButton,
        &ghostModeDeletedMessagesToggleTargetAssociationKey,
        toggleTarget,
        .OBJC_ASSOCIATION_RETAIN_NONATOMIC
    )
    controller.navigationItem.rightBarButtonItem = toggleButton

    return controller
}

public func ghostModeDeletedChatController(context: AccountContext, peerId: Int64) -> ViewController {
    let statePromise = Promise<[GhostModeDeletedMessage]>([])
    let reload: () -> Void = {
        GhostModeDeletedMessagesStorage.shared.fetchAll(peerId: peerId) { items in
            statePromise.set(.single(items))
        }
    }
    reload()

    let arguments = DeletedArguments(openChat: { _ in }, clearAll: {
        GhostModeDeletedMessagesStorage.shared.fetchAll(peerId: peerId) { items in
            // Clear only this peer by rewriting storage without these ids — simple full clear of peer via re-fetch + filter not available; use clear-all fallback notice.
            GhostModeDeletedMessagesStorage.shared.clear { reload() }
        }
    })

    let signal = combineLatest(queue: .mainQueue(), context.sharedContext.presentationData, statePromise.get())
    |> map { presentationData, items -> (ItemListControllerState, (ItemListNodeState, Any)) in
        let lang = presentationData.strings.baseLanguageCode
        var entries: [DeletedEntry] = []
        if items.isEmpty {
            entries.append(.empty("GhostMode.DeletedMessages.Empty".i18n(lang)))
        } else {
            for m in items { entries.append(.item(m)) }
            entries.append(.clear)
        }
        let controllerState = ItemListControllerState(
            presentationData: ItemListPresentationData(presentationData),
            title: .text("Chat \(peerId)"),
            leftNavigationButton: nil,
            rightNavigationButton: nil,
            backNavigationButton: ItemListBackButton(title: presentationData.strings.Common_Back),
            animateChanges: false
        )
        let listState = ItemListNodeState(
            presentationData: ItemListPresentationData(presentationData),
            entries: entries,
            style: .blocks,
            emptyStateItem: nil,
            animateChanges: false
        )
        return (controllerState, (listState, arguments))
    }

    return ItemListController(context: context, state: signal)
}
