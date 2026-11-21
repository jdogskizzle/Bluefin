//
//  BluefinCarPlaySceneDelegate.swift
//  Bluefin
//
//  Created by Jacob Marcuson on 11/14/26.
//

#if canImport(CarPlay)
import CarPlay
import Combine

/// Drives Bluefin's CarPlay screen. Registered by class name in `Info.plist`'s
/// `UIApplicationSceneManifest` (`CPTemplateApplicationSceneSessionRoleApplication`); UIKit
/// instantiates this directly — no storyboard or extension target involved, since it lives in the
/// main `Bluefin` app target alongside everything else.
final class BluefinCarPlaySceneDelegate: UIResponder, CPTemplateApplicationSceneDelegate {
    private var interfaceController: CPInterfaceController?
    private var libraryChangeObserver: AnyCancellable?

    // Audio apps must use these window-less variants; the `to:`/`from: CPWindow` overloads are only
    // called for navigation apps, so implementing those left CarPlay with no root template.
    func templateApplicationScene(
        _ templateApplicationScene: CPTemplateApplicationScene,
        didConnect interfaceController: CPInterfaceController
    ) {
        self.interfaceController = interfaceController
        interfaceController.setRootTemplate(
            CPListTemplate(title: "Bluefin", sections: []), animated: false, completion: nil)
        Task { await showRoot() }
        observeLibraryChanges()
    }

    func templateApplicationScene(
        _ templateApplicationScene: CPTemplateApplicationScene,
        didDisconnectInterfaceController interfaceController: CPInterfaceController
    ) {
        libraryChangeObserver = nil
        self.interfaceController = nil
    }

    private func showRoot() async {
        guard let interfaceController else { return }
        let root = await CarPlayContent.buildRootTemplate(interfaceController: interfaceController)
        interfaceController.setRootTemplate(root, animated: false, completion: nil)
    }

    /// Keeps the root list honest if the phone app re-syncs (or a playlist is edited) while CarPlay
    /// is still connected. A deeper pushed template (an open song list) isn't live-updated in this
    /// first pass — reopening it from the root picks up the change.
    private func observeLibraryChanges() {
        libraryChangeObserver = LibraryCacheChangeCenter.didChange
            .filter { $0 == "playlists" || $0.hasPrefix("albums:") }
            .sink { [weak self] _ in
                Task { await self?.showRoot() }
            }
    }
}
#endif
