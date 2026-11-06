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

// MARK: - Sections / State / Entries

private enum GhostModeSection: Int32 {
    case intro = 0
    case actions = 1
    case history = 2
}

private final class GhostModeControllerState: Equatable {
    let settings: GhostModeSettings

    init(settings: GhostModeSettings) {
        self.settings = settings
    }

    static func == (lhs: GhostModeControllerState, rhs: GhostModeControllerState) -> Bool {
        return lhs.settings == rhs.settings
    }

    static func current() -> GhostModeControllerState {
        return GhostModeControllerState(settings: GhostModeSettingsManager.shared.settings)
    }
}

private enum GhostModeEntryId: Hashable {
    case introNotice
    case actionsHeader
    case dontReadMessages
    case dontReadMessagesNotice
    case dontSendTyping
    case dontSendTypingNotice
    case dontSendOnline
    case dontSendOnlineNotice
    case dontSendUploadProgress
    case dontSendUploadProgressNotice
    case historyHeader
    case saveDeletedMessages
    case saveDeletedMessagesNotice
    case saveExpiringMedia
    case saveExpiringMediaNotice
}

private enum GhostModeEntry: ItemListNodeEntry {
    case introNotice
    case actionsHeader
    case dontReadMessages(Bool)
    case dontReadMessagesNotice
    case dontSendTyping(Bool)
    case dontSendTypingNotice
    case dontSendOnline(Bool)
    case dontSendOnlineNotice
    case dontSendUploadProgress(Bool)
    case dontSendUploadProgressNotice
    case historyHeader
    case saveDeletedMessages(Bool)
    case saveDeletedMessagesNotice
    case saveExpiringMedia(Bool)
    case saveExpiringMediaNotice

    var section: ItemListSectionId {
        switch self {
        case .introNotice:
            return GhostModeSection.intro.rawValue
        case .actionsHeader, .dontReadMessages, .dontReadMessagesNotice,
             .dontSendTyping, .dontSendTypingNotice,
             .dontSendOnline, .dontSendOnlineNotice,
             .dontSendUploadProgress, .dontSendUploadProgressNotice:
            return GhostModeSection.actions.rawValue
        case .historyHeader, .saveDeletedMessages, .saveDeletedMessagesNotice,
             .saveExpiringMedia, .saveExpiringMediaNotice:
            return GhostModeSection.history.rawValue
        }
    }

    var stableId: GhostModeEntryId {
        switch self {
        case .introNotice: return .introNotice
        case .actionsHeader: return .actionsHeader
        case .dontReadMessages: return .dontReadMessages
        case .dontReadMessagesNotice: return .dontReadMessagesNotice
        case .dontSendTyping: return .dontSendTyping
        case .dontSendTypingNotice: return .dontSendTypingNotice
        case .dontSendOnline: return .dontSendOnline
        case .dontSendOnlineNotice: return .dontSendOnlineNotice
        case .dontSendUploadProgress: return .dontSendUploadProgress
        case .dontSendUploadProgressNotice: return .dontSendUploadProgressNotice
        case .historyHeader: return .historyHeader
        case .saveDeletedMessages: return .saveDeletedMessages
        case .saveDeletedMessagesNotice: return .saveDeletedMessagesNotice
        case .saveExpiringMedia: return .saveExpiringMedia
        case .saveExpiringMediaNotice: return .saveExpiringMediaNotice
        }
    }

    static func < (lhs: GhostModeEntry, rhs: GhostModeEntry) -> Bool {
        if lhs.section != rhs.section { return lhs.section < rhs.section }
        return false
    }

    func item(presentationData: ItemListPresentationData, arguments: Any) -> ListViewItem {
        let arguments = arguments as! GhostModeArguments
        let lang = presentationData.strings.baseLanguageCode

        switch self {
        case .introNotice:
            return ItemListTextItem(
                presentationData: presentationData,
                text: .plain("GhostMode.Intro".i18n(lang)),
                sectionId: self.section
            )
        case .actionsHeader:
            return ItemListSectionHeaderItem(
                presentationData: presentationData,
                text: "GhostMode.Actions.Header".i18n(lang),
                sectionId: self.section
            )
        case let .dontReadMessages(value):
            return ItemListSwitchItem(
                presentationData: presentationData,
                title: "GhostMode.DontReadMessages".i18n(lang),
                value: value,
                sectionId: self.section,
                style: .blocks,
                updated: { arguments.setDontReadMessages($0) }
            )
        case .dontReadMessagesNotice:
            return ItemListTextItem(
                presentationData: presentationData,
                text: .plain("GhostMode.DontReadMessages.Description".i18n(lang)),
                sectionId: self.section
            )
        case let .dontSendTyping(value):
            return ItemListSwitchItem(
                presentationData: presentationData,
                title: "GhostMode.DontSendTyping".i18n(lang),
                value: value,
                sectionId: self.section,
                style: .blocks,
                updated: { arguments.setDontSendTyping($0) }
            )
        case .dontSendTypingNotice:
            return ItemListTextItem(
                presentationData: presentationData,
                text: .plain("GhostMode.DontSendTyping.Description".i18n(lang)),
                sectionId: self.section
            )
        case let .dontSendOnline(value):
            return ItemListSwitchItem(
                presentationData: presentationData,
                title: "GhostMode.DontSendOnline".i18n(lang),
                value: value,
                sectionId: self.section,
                style: .blocks,
                updated: { arguments.setDontSendOnline($0) }
            )
        case .dontSendOnlineNotice:
            return ItemListTextItem(
                presentationData: presentationData,
                text: .plain("GhostMode.DontSendOnline.Description".i18n(lang)),
                sectionId: self.section
            )
        case let .dontSendUploadProgress(value):
            return ItemListSwitchItem(
                presentationData: presentationData,
                title: "GhostMode.DontSendUploadProgress".i18n(lang),
                value: value,
                sectionId: self.section,
                style: .blocks,
                updated: { arguments.setDontSendUploadProgress($0) }
            )
        case .dontSendUploadProgressNotice:
            return ItemListTextItem(
                presentationData: presentationData,
                text: .plain("GhostMode.DontSendUploadProgress.Description".i18n(lang)),
                sectionId: self.section
            )
        case .historyHeader:
            return ItemListSectionHeaderItem(
                presentationData: presentationData,
                text: "GhostMode.History.Header".i18n(lang),
                sectionId: self.section
            )
        case let .saveDeletedMessages(value):
            return ItemListSwitchItem(
                presentationData: presentationData,
                title: "GhostMode.SaveDeletedMessages".i18n(lang),
                value: value,
                sectionId: self.section,
                style: .blocks,
                updated: { arguments.setSaveDeletedMessages($0) }
            )
        case .saveDeletedMessagesNotice:
            return ItemListTextItem(
                presentationData: presentationData,
                text: .plain("GhostMode.SaveDeletedMessages.Description".i18n(lang)),
                sectionId: self.section
            )
        case let .saveExpiringMedia(value):
            return ItemListSwitchItem(
                presentationData: presentationData,
                title: "GhostMode.SaveExpiringMedia".i18n(lang),
                value: value,
                sectionId: self.section,
                style: .blocks,
                updated: { arguments.setSaveExpiringMedia($0) }
            )
        case .saveExpiringMediaNotice:
            return ItemListTextItem(
                presentationData: presentationData,
                text: .plain("GhostMode.SaveExpiringMedia.Description".i18n(lang)),
                sectionId: self.section
            )
        }
    }
}

private final class GhostModeArguments {
    let setDontReadMessages: (Bool) -> Void
    let setDontSendTyping: (Bool) -> Void
    let setDontSendOnline: (Bool) -> Void
    let setDontSendUploadProgress: (Bool) -> Void
    let setSaveDeletedMessages: (Bool) -> Void
    let setSaveExpiringMedia: (Bool) -> Void

    init(
        setDontReadMessages: @escaping (Bool) -> Void,
        setDontSendTyping: @escaping (Bool) -> Void,
        setDontSendOnline: @escaping (Bool) -> Void,
        setDontSendUploadProgress: @escaping (Bool) -> Void,
        setSaveDeletedMessages: @escaping (Bool) -> Void,
        setSaveExpiringMedia: @escaping (Bool) -> Void
    ) {
        self.setDontReadMessages = setDontReadMessages
        self.setDontSendTyping = setDontSendTyping
        self.setDontSendOnline = setDontSendOnline
        self.setDontSendUploadProgress = setDontSendUploadProgress
        self.setSaveDeletedMessages = setSaveDeletedMessages
        self.setSaveExpiringMedia = setSaveExpiringMedia
    }
}

private func ghostModeControllerEntries(state: GhostModeControllerState) -> [GhostModeEntry] {
    var entries: [GhostModeEntry] = []
    let s = state.settings

    entries.append(.introNotice)

    entries.append(.actionsHeader)
    entries.append(.dontReadMessages(s.dontReadMessages))
    entries.append(.dontReadMessagesNotice)
    entries.append(.dontSendTyping(s.dontSendTyping))
    entries.append(.dontSendTypingNotice)
    entries.append(.dontSendOnline(s.dontSendOnline))
    entries.append(.dontSendOnlineNotice)
    entries.append(.dontSendUploadProgress(s.dontSendUploadProgress))
    entries.append(.dontSendUploadProgressNotice)

    entries.append(.historyHeader)
    entries.append(.saveDeletedMessages(s.saveDeletedMessages))
    entries.append(.saveDeletedMessagesNotice)
    entries.append(.saveExpiringMedia(s.saveExpiringMedia))
    entries.append(.saveExpiringMediaNotice)

    return entries
}

public func ghostModeSettingsController(context: AccountContext) -> ViewController {
    let initialState = GhostModeControllerState.current()
    let statePromise = ValuePromise(initialState, ignoreRepeated: true)
    let stateValue = Atomic(value: initialState)

    let updateState: (() -> Void) = {
        let newState = GhostModeControllerState.current()
        _ = stateValue.swap(newState)
        statePromise.set(newState)
    }

    let accountId = String(context.account.peerId.toInt64())
    GhostModeSettingsManager.shared.switchToAccount(accountId: accountId) {
        updateState()
    }

    let arguments = GhostModeArguments(
        setDontReadMessages: { value in
            GhostModeSettingsManager.shared.setDontReadMessages(value) {
                Queue.mainQueue().async { updateState() }
            }
        },
        setDontSendTyping: { value in
            GhostModeSettingsManager.shared.setDontSendTyping(value) {
                Queue.mainQueue().async { updateState() }
            }
        },
        setDontSendOnline: { value in
            GhostModeSettingsManager.shared.setDontSendOnline(value) {
                Queue.mainQueue().async { updateState() }
            }
        },
        setDontSendUploadProgress: { value in
            GhostModeSettingsManager.shared.setDontSendUploadProgress(value) {
                Queue.mainQueue().async { updateState() }
            }
        },
        setSaveDeletedMessages: { value in
            GhostModeSettingsManager.shared.setSaveDeletedMessages(value) {
                Queue.mainQueue().async { updateState() }
            }
        },
        setSaveExpiringMedia: { value in
            GhostModeSettingsManager.shared.setSaveExpiringMedia(value) {
                Queue.mainQueue().async { updateState() }
            }
        }
    )

    let signal = combineLatest(
        queue: .mainQueue(),
        context.sharedContext.presentationData,
        statePromise.get()
    )
    |> map { presentationData, state -> (ItemListControllerState, (ItemListNodeState, Any)) in
        let lang = presentationData.strings.baseLanguageCode
        let controllerState = ItemListControllerState(
            presentationData: ItemListPresentationData(presentationData),
            title: .text("GhostMode.Title".i18n(lang)),
            leftNavigationButton: nil,
            rightNavigationButton: nil,
            backNavigationButton: ItemListBackButton(title: presentationData.strings.Common_Back),
            animateChanges: false
        )

        let listState = ItemListNodeState(
            presentationData: ItemListPresentationData(presentationData),
            entries: ghostModeControllerEntries(state: state),
            style: .blocks,
            emptyStateItem: nil,
            animateChanges: false
        )

        return (controllerState, (listState, arguments))
    }

    let controller = ItemListController(context: context, state: signal)
    return controller
}
