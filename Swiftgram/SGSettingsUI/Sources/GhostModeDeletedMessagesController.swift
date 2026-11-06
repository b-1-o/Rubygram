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

private enum DeletedMessagesSection: Int32 {
    case list = 0
    case actions = 1
}

private enum DeletedMessagesEntryId: Hashable {
    case empty
    case message(String)
    case clear
}

private enum DeletedMessagesEntry: ItemListNodeEntry {
    case empty
    case message(index: Int, item: GhostModeDeletedMessage)
    case clear

    var section: ItemListSectionId {
        switch self {
        case .empty, .message:
            return DeletedMessagesSection.list.rawValue
        case .clear:
            return DeletedMessagesSection.actions.rawValue
        }
    }

    var stableId: DeletedMessagesEntryId {
        switch self {
        case .empty:
            return .empty
        case let .message(_, item):
            return .message(item.id)
        case .clear:
            return .clear
        }
    }

    static func < (lhs: DeletedMessagesEntry, rhs: DeletedMessagesEntry) -> Bool {
        switch (lhs, rhs) {
        case (.empty, _):
            return true
        case (_, .empty):
            return false
        case let (.message(li, _), .message(ri, _)):
            return li < ri
        case (.message, .clear):
            return true
        case (.clear, .message):
            return false
        case (.clear, .clear):
            return false
        }
    }

    func item(presentationData: ItemListPresentationData, arguments: Any) -> ListViewItem {
        let arguments = arguments as! DeletedMessagesArguments
        switch self {
        case .empty:
            return ItemListTextItem(
                presentationData: presentationData,
                text: .plain("GhostMode.DeletedMessages.Empty".i18n(presentationData.strings.baseLanguageCode)),
                sectionId: self.section
            )
        case let .message(_, item):
            let title = item.text.isEmpty ? (item.mediaSummary ?? "Media") : item.text
            let date = Date(timeIntervalSince1970: TimeInterval(item.date))
            let formatter = DateFormatter()
            formatter.dateStyle = .short
            formatter.timeStyle = .short
            let subtitle = "peer \(item.peerId) · \(formatter.string(from: date))"
            return ItemListDisclosureItem(
                presentationData: presentationData,
                title: title,
                label: subtitle,
                sectionId: self.section,
                style: .blocks,
                action: {}
            )
        case .clear:
            return ItemListActionItem(
                presentationData: presentationData,
                title: "GhostMode.DeletedMessages.Clear".i18n(presentationData.strings.baseLanguageCode),
                kind: .destructive,
                alignment: .center,
                sectionId: self.section,
                style: .blocks,
                action: {
                    arguments.clearAll()
                }
            )
        }
    }
}

private final class DeletedMessagesArguments {
    let clearAll: () -> Void
    init(clearAll: @escaping () -> Void) {
        self.clearAll = clearAll
    }
}

private func deletedMessagesControllerEntries(items: [GhostModeDeletedMessage]) -> [DeletedMessagesEntry] {
    var entries: [DeletedMessagesEntry] = []
    if items.isEmpty {
        entries.append(.empty)
    } else {
        for (index, item) in items.enumerated() {
            entries.append(.message(index: index, item: item))
        }
        entries.append(.clear)
    }
    return entries
}

public func ghostModeDeletedMessagesController(context: AccountContext) -> ViewController {
    var updateImpl: (() -> Void)?

    let statePromise = Promise<[GhostModeDeletedMessage]>([])
    let reload: () -> Void = {
        GhostModeDeletedMessagesStorage.shared.fetchAll { items in
            statePromise.set(.single(items))
        }
    }
    reload()

    let arguments = DeletedMessagesArguments(clearAll: {
        GhostModeDeletedMessagesStorage.shared.clear {
            reload()
        }
    })

    let signal = combineLatest(
        queue: .mainQueue(),
        context.sharedContext.presentationData,
        statePromise.get()
    )
    |> map { presentationData, items -> (ItemListControllerState, (ItemListNodeState, Any)) in
        let lang = presentationData.strings.baseLanguageCode
        let entries = deletedMessagesControllerEntries(items: items)
        let controllerState = ItemListControllerState(
            presentationData: ItemListPresentationData(presentationData),
            title: .text("GhostMode.DeletedMessages.Title".i18n(lang)),
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

    let controller = ItemListController(context: context, state: signal)
    updateImpl = reload
    return controller
}
