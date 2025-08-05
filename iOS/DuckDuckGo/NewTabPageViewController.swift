//
//  NewTabPageViewController.swift
//  DuckDuckGo
//
//  Copyright © 2024 DuckDuckGo. All rights reserved.
//
//  Licensed under the Apache License, Version 2.0 (the "License");
//  you may not use this file except in compliance with the License.
//  You may obtain a copy of the License at
//
//  http://www.apache.org/licenses/LICENSE-2.0
//
//  Unless required by applicable law or agreed to in writing, software
//  distributed under the License is distributed on an "AS IS" BASIS,
//  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
//  See the License for the specific language governing permissions and
//  limitations under the License.
//

import SwiftUI
import DDGSync
import Bookmarks
import BrowserServicesKit
import Core

final class NewTabPageViewController: UIHostingController<AnyView>, NewTabPage {

    var isShowingLogo: Bool {
        favoritesModel.isEmpty
    }

    private lazy var borderView = StyledTopBottomBorderView()

    private let variantManager: VariantManager
    private let newTabDialogFactory: any NewTabDaxDialogProvider
    private let newTabDialogTypeProvider: NewTabDialogSpecProvider

    private let newTabPageViewModel: NewTabPageViewModel
    private let messagesModel: NewTabPageMessagesModel
    private let favoritesModel: FavoritesViewModel
    private let shortcutsModel: ShortcutsModel
    private let shortcutsSettingsModel: NewTabPageShortcutsSettingsModel
    private let sectionsSettingsModel: NewTabPageSectionsSettingsModel
    private let associatedTab: Tab

    private var hostingController: UIHostingController<AnyView>?

    private let messageNavigationDelegate: MessageNavigationDelegate

    private var privacyProPromotionCoordinating: PrivacyProPromotionCoordinating
    private let appSettings: AppSettings
    private let appWidthObserver: AppWidthObserver

    init(tab: Tab,
         isNewTabPageCustomizationEnabled: Bool,
         interactionModel: FavoritesListInteracting,
         homePageMessagesConfiguration: HomePageMessagesConfiguration,
         privacyProDataReporting: PrivacyProDataReporting? = nil,
         variantManager: VariantManager,
         newTabDialogFactory: any NewTabDaxDialogProvider,
         newTabDialogTypeProvider: NewTabDialogSpecProvider,
         privacyProPromotionCoordinating: PrivacyProPromotionCoordinating = DaxDialogs.shared,
         faviconLoader: FavoritesFaviconLoading,
         messageNavigationDelegate: MessageNavigationDelegate,
         appSettings: AppSettings,
         appWidthObserver: AppWidthObserver = .shared) {

        self.associatedTab = tab
        self.variantManager = variantManager
        self.newTabDialogFactory = newTabDialogFactory
        self.newTabDialogTypeProvider = newTabDialogTypeProvider
        self.privacyProPromotionCoordinating = privacyProPromotionCoordinating
        self.messageNavigationDelegate = messageNavigationDelegate
        self.appSettings = appSettings
        self.appWidthObserver = appWidthObserver

        newTabPageViewModel = NewTabPageViewModel()
        shortcutsSettingsModel = NewTabPageShortcutsSettingsModel()
        sectionsSettingsModel = NewTabPageSectionsSettingsModel()
        favoritesModel = FavoritesViewModel(isNewTabPageCustomizationEnabled: isNewTabPageCustomizationEnabled,
                                            favoriteDataSource: FavoritesListInteractingAdapter(favoritesListInteracting: interactionModel),
                                            faviconLoader: faviconLoader)
        shortcutsModel = ShortcutsModel()
        messagesModel = NewTabPageMessagesModel(homePageMessagesConfiguration: homePageMessagesConfiguration,
                                                privacyProDataReporter: privacyProDataReporting,
                                                navigator: DefaultMessageNavigator(delegate: messageNavigationDelegate))

        if isNewTabPageCustomizationEnabled {
            super.init(rootView: AnyView(CustomizableNewTabPageView(viewModel: self.newTabPageViewModel,
                                                        messagesModel: self.messagesModel,
                                                        favoritesViewModel: self.favoritesModel,
                                                        shortcutsModel: self.shortcutsModel,
                                                        shortcutsSettingsModel: self.shortcutsSettingsModel,
                                                        sectionsSettingsModel: self.sectionsSettingsModel)))
        } else {
            super.init(rootView: AnyView(NewTabPageView(viewModel: self.newTabPageViewModel,
                                                              messagesModel: self.messagesModel,
                                                              favoritesViewModel: self.favoritesModel)))
        }

        assignFavoriteModelActions()
        assignShorcutsModelActions()
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        registerForNotifications()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)

        view.backgroundColor = UIColor(designSystemColor: .background)

        // If there's no tab switcher then this will be true, if there is a tabswitcher then only allow the
        // stuff below to happen if it's being dismissed
        guard presentedViewController?.isBeingDismissed ?? true else {
            return
        }

        associatedTab.viewed = true

        presentNextDaxDialog()

        if !favoritesModel.isEmpty {
            borderView.insertSelf(into: view)
            updateBorderView()
        }
    }

    func setFavoritesEditable(_ editable: Bool) {
        newTabPageViewModel.canEditFavorites = editable
        favoritesModel.canEditFavorites = editable
    }

    func hideBorderView() {
        borderView.isHidden = true
    }

    func widthChanged() {
        updateBorderView()
    }

    func updateBorderView() {
        borderView.updateForAddressBarPosition(appSettings.currentAddressBarPosition)
        borderView.isBottomVisible = !appWidthObserver.isLargeWidth
    }

    func registerForNotifications() {
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(onSettingsDidDisappear),
                                               name: .settingsDidDisappear,
                                               object: nil)

        NotificationCenter.default.addObserver(self,
                                               selector: #selector(onAddressBarPositionChanged),
                                               name: AppUserDefaults.Notifications.addressBarPositionChanged,
                                               object: nil)
    }

    @objc func onAddressBarPositionChanged() {
        updateBorderView()
    }

    @objc func onSettingsDidDisappear() {
        if self.favoritesModel.hasMissingIcons {
            self.delegate?.newTabPageDidRequestFaviconsFetcherOnboarding(self)
        }
    }

    // MARK: - Private

    private func assignFavoriteModelActions() {
        favoritesModel.onFaviconMissing = { [weak self] in
            guard let self else { return }

            delegate?.newTabPageDidRequestFaviconsFetcherOnboarding(self)
        }

        favoritesModel.onFavoriteURLSelected = { [weak self] favorite in
            guard let self else { return }

            delegate?.newTabPageDidSelectFavorite(self, favorite: favorite)
        }

        favoritesModel.onFavoriteEdit = { [weak self] favorite in
            guard let self else { return }

            delegate?.newTabPageDidEditFavorite(self, favorite: favorite)
        }

        favoritesModel.onFavoriteDeleted = { [weak self] favorite in
            guard let self else { return }

            borderView.updateForAddressBarPosition(appSettings.currentAddressBarPosition)
            delegate?.newTabPageDidDeleteFavorite(self, favorite: favorite)
        }
    }

    private func assignShorcutsModelActions() {
        shortcutsModel.onShortcutOpened = { [weak self] shortcut in
            guard let self else { return }

            switch shortcut {
            case .aiChat:
                shortcutsDelegate?.newTabPageDidRequestAIChat(self)
            case .bookmarks:
                shortcutsDelegate?.newTabPageDidRequestBookmarks(self)
            case .downloads:
                shortcutsDelegate?.newTabPageDidRequestDownloads(self)
            case .passwords:
                shortcutsDelegate?.newTabPageDidRequestPasswords(self)
            case .settings:
                shortcutsDelegate?.newTabPageDidRequestSettings(self)
            }
        }
    }

    // MARK: - NewTabPage

    var isDragging: Bool { newTabPageViewModel.isDragging }

    weak var chromeDelegate: BrowserChromeDelegate?
    weak var delegate: NewTabPageControllerDelegate?
    weak var shortcutsDelegate: NewTabPageControllerShortcutsDelegate?

    func launchNewSearch() {
        // If we are displaying a Privacy Pro promotion on a new tab, do not activate search
        guard !privacyProPromotionCoordinating.isShowingPrivacyProPromotion else { return }
        chromeDelegate?.omniBar.beginEditing()
    }

    func openedAsNewTab(allowingKeyboard: Bool) {
        if allowingKeyboard && KeyboardSettings().onNewTab {

            // The omnibar is inside a collection view so this needs a chance to do its thing
            // which might also be async. Not great.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                self.launchNewSearch()
            }
        }
    }

    func dismiss() {
        delegate = nil
        chromeDelegate = nil
        removeFromParent()
        view.removeFromSuperview()
    }

    func showNextDaxDialog() {
        presentNextDaxDialog()
    }

    func onboardingCompleted() {
        presentNextDaxDialog()
        // Show Keyboard when showing the first Dax tip
        chromeDelegate?.omniBar.beginEditing()
    }

    // MARK: - Onboarding

    private func presentNextDaxDialog() {
        showNextDaxDialogNew(dialogProvider: newTabDialogTypeProvider, factory: newTabDialogFactory)
    }

    // MARK: -

    @available(*, unavailable)
    @MainActor required dynamic init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

extension NewTabPageViewController: HomeScreenTransitionSource {
    var snapshotView: UIView {
        view
    }

    var rootContainerView: UIView {
        view
    }
}

extension NewTabPageViewController {

    func showNextDaxDialogNew(dialogProvider: NewTabDialogSpecProvider, factory: any NewTabDaxDialogProvider) {
        dismissHostingController(didFinishNTPOnboarding: false)

        guard let spec = dialogProvider.nextHomeScreenMessageNew() else { return }

        let onDismiss: (_ activateSearch: Bool) -> Void = { [weak self] activateSearch in
            guard let self else { return }

            let nextSpec = dialogProvider.nextHomeScreenMessageNew()
            guard nextSpec != .privacyProPromotion else {
                chromeDelegate?.omniBar.endEditing()
                showNextDaxDialog()
                return
            }

            dialogProvider.dismiss()
            self.dismissHostingController(didFinishNTPOnboarding: true)
            if activateSearch {
                // Make the address bar first responder after closing the new tab page final dialog.
                self.launchNewSearch()
            }
        }

        let onManualDismiss: () -> Void = { [weak self] in
            self?.dismissHostingController(didFinishNTPOnboarding: true)
            // Show keyboard when manually dismiss the Dax tips.
            self?.chromeDelegate?.omniBar.beginEditing()
        }

        let daxDialogView = AnyView(factory.createDaxDialog(for: spec, onCompletion: onDismiss, onManualDismiss: onManualDismiss))
        let hostingController = UIHostingController(rootView: daxDialogView)
        self.hostingController = hostingController

        hostingController.view.backgroundColor = .clear
        addChild(hostingController)
        view.addSubview(hostingController.view)
        hostingController.view.translatesAutoresizingMaskIntoConstraints = false

        NSLayoutConstraint.activate([
            hostingController.view.topAnchor.constraint(equalTo: view.topAnchor),
            hostingController.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            hostingController.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            hostingController.view.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])

        hostingController.didMove(toParent: self)

        newTabPageViewModel.startOnboarding()
    }

    private func dismissHostingController(didFinishNTPOnboarding: Bool) {
        hostingController?.willMove(toParent: nil)
        hostingController?.view.removeFromSuperview()
        hostingController?.removeFromParent()
        if didFinishNTPOnboarding {
            self.newTabPageViewModel.finishOnboarding()
        }
    }
}
