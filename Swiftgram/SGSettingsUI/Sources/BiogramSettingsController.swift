import Foundation
import UIKit
import Display
import AsyncDisplayKit
import SwiftSignalKit
import TelegramCore
import TelegramPresentationData
import ItemListUI
import AccountContext
import PresentationDataUtils
import Biogram
import SGStrings

// MARK: - Helpers

private final class BiogramActionsAlertController: ViewController {
    private let titleText: String
    private let messageText: String?
    private let actions: [(title: String, destructive: Bool, action: () -> Void)]
   
    init(title: String, message: String?, actions: [(title: String, destructive: Bool, action: () -> Void)]) {
        self.titleText = title
        self.messageText = message
        self.actions = actions
        super.init(navigationBarPresentationData: nil)
        self.statusBar.statusBarStyle = .Ignore
    }
   
    required init(coder aDecoder: NSCoder) { fatalError() }
   
    override func loadDisplayNode() {
        self.displayNode = ASDisplayNode()
        self.displayNode.backgroundColor = UIColor.black.withAlphaComponent(0.4)
       
        let alert = UIAlertController(title: titleText, message: messageText, preferredStyle: .actionSheet)
        for item in actions {
            alert.addAction(UIAlertAction(title: item.title, style: item.destructive ? .destructive : .default, handler: { [weak self] _ in
                item.action()
                self?.close()
            }))
        }
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel, handler: { [weak self] _ in
            self?.close()
        }))
       
        Queue.mainQueue().after(0.05) { [weak self] in
            guard let self = self else { return }
            guard let root = self.view.window?.rootViewController else { return }
            var top: UIViewController = root
            while let presented = top.presentedViewController { top = presented }
            if let pop = alert.popoverPresentationController {
                pop.sourceView = top.view
                pop.sourceRect = CGRect(x: top.view.bounds.midX, y: top.view.bounds.midY, width: 1, height: 1)
                pop.permittedArrowDirections = []
            }
            top.present(alert, animated: true)
        }
    }
   
    private func close() { self.dismiss(animated: false) }
}
