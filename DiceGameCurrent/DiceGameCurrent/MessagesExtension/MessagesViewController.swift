import SwiftUI
import UIKit
import Messages

/// The extension's root.
///
/// Thin on purpose. Everything a player sees is SwiftUI — the same screens
/// the app runs — so this does four things and no more: it keeps a
/// `MessagesStore` in step with Messages' callbacks, it hosts one SwiftUI
/// view, it asks for the expanded presentation when a bubble is tapped,
/// and it inserts the message a finished turn produces.
///
/// Platform floor: iOS 16, Swift 5.7 (see PLATFORM.txt). Nothing here
/// reaches past it.
final class MessagesViewController: MSMessagesAppViewController {

    /// What the SwiftUI side reads and writes. Owned here because its
    /// lifetime is the extension's, not any one view's.
    private let store = MessagesStore()

    private var hosting: UIHostingController<MessagesRootView>?

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()

        // The store cannot send on its own — it has no conversation and no
        // business holding one. It asks, and this answers.
        store.onSend = { [weak self] message in
            self?.insert(message)
        }
        store.onRequestExpanded = { [weak self] in
            self?.requestPresentationStyle(.expanded)
        }
        // Closing the view, not the match. The match is its message and
        // stays in the thread; this just puts the player back to the
        // conversation, which is also how they abandon one — by not
        // replying. See MessagesStore.onClose.
        store.onClose = { [weak self] in
            self?.requestPresentationStyle(.compact)
        }

        let root = MessagesRootView(store: store)
        let controller = UIHostingController(rootView: root)
        controller.view.backgroundColor = .clear

        addChild(controller)
        view.addSubview(controller.view)
        controller.view.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            controller.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            controller.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            controller.view.topAnchor.constraint(equalTo: view.topAnchor),
            controller.view.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
        controller.didMove(toParent: self)
        hosting = controller
    }

    // MARK: - Conversation handling

    override func willBecomeActive(with conversation: MSConversation) {
        super.willBecomeActive(with: conversation)
        store.update(conversation: conversation,
                     selected: conversation.selectedMessage,
                     style: presentationStyle)
    }

    override func didResignActive(with conversation: MSConversation) {
        super.didResignActive(with: conversation)
        // Dropped rather than kept. The extension is torn down and rebuilt
        // freely, and a retained conversation is a stale one — every
        // callback hands the current one back.
        store.clearConversation()
    }

    /// A participant tapped a game bubble in the transcript.
    ///
    /// Compact is a few hundred points tall and no game in the suite fits
    /// it, so a tap means expand. The store already has the message by the
    /// time this runs, because `willBecomeActive` ran first.
    override func didSelect(_ message: MSMessage, conversation: MSConversation) {
        super.didSelect(message, conversation: conversation)
        store.update(conversation: conversation,
                     selected: message,
                     style: presentationStyle)
        requestPresentationStyle(.expanded)
    }

    override func didReceive(_ message: MSMessage, conversation: MSConversation) {
        super.didReceive(message, conversation: conversation)
        store.update(conversation: conversation,
                     selected: conversation.selectedMessage,
                     style: presentationStyle)
    }

    override func didStartSending(_ message: MSMessage, conversation: MSConversation) {
        super.didStartSending(message, conversation: conversation)
        // Back to compact the moment a turn is away: the player is done,
        // and leaving a finished board full-screen reads as if it is still
        // their move.
        requestPresentationStyle(.compact)
    }

    override func didCancelSending(_ message: MSMessage, conversation: MSConversation) {
        super.didCancelSending(message, conversation: conversation)
        store.sendFailed()
    }

    // MARK: - Presentation style

    override func willTransition(to presentationStyle: MSMessagesAppPresentationStyle) {
        super.willTransition(to: presentationStyle)
        // Set on the way in rather than on the way out, so the first frame
        // the player sees in the new style is already the right layout.
        store.style = presentationStyle
    }

    // MARK: - Sending

    private func insert(_ message: MSMessage) {
        guard let conversation = activeConversation else {
            store.sendFailed()
            return
        }
        conversation.insert(message) { [weak self] error in
            // The completion is not promised on the main queue, and this
            // touches an ObservableObject a SwiftUI view is observing.
            DispatchQueue.main.async {
                if error != nil { self?.store.sendFailed() }
            }
        }
    }
}
