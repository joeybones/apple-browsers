//
//  OmniBarEditingStateViewController.swift
//  DuckDuckGo
//
//  Copyright © 2025 DuckDuckGo. All rights reserved.
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

import UIKit
import DesignResourcesKit
import Combine
import BrowserServicesKit
import Bookmarks
import Persistence
import History
import Core
import Suggestions
import SwiftUI
import AIChat

protocol OmniBarEditingStateViewControllerDelegate: AnyObject {
    func onQueryUpdated(_ query: String)
    func onQuerySubmitted(_ query: String)
    func onPromptSubmitted(_ query: String, tools: [AIChatRAGTool]?)
    func onSelectFavorite(_ favorite: BookmarkEntity)
    func onSelectSuggestion(_ suggestion: Suggestion)
    func onVoiceSearchRequested(from mode: TextEntryMode)
}

/// Main coordinator for the OmniBar editing state, managing multiple specialized components
final class OmniBarEditingStateViewController: UIViewController, OmniBarEditingStateTransitioning {

    // MARK: - Properties

    var actionBarView: UIView? { navigationActionBarManager?.view }

    var suggestionTrayDependencies: SuggestionTrayDependencies?

    weak var delegate: OmniBarEditingStateViewControllerDelegate?
    var automaticallySelectsTextOnAppear = false

    // MARK: - Core Components
    
    private let switchBarHandler: SwitchBarHandling
    private var cancellables = Set<AnyCancellable>()

    lazy var isTopBarPosition = AppDependencyProvider.shared.appSettings.currentAddressBarPosition == .top
    lazy var switchBarVC = SwitchBarViewController(switchBarHandler: switchBarHandler)
    
    // MARK: - Manager Components
    
    private var swipeContainerManager: SwipeContainerManager?
    private var navigationActionBarManager: NavigationActionBarManager?
    private var suggestionTrayManager: SuggestionTrayManager?
    private let daxLogoManager = DaxLogoManager()

    // MARK: - Initialization
    
    internal init(switchBarHandler: any SwitchBarHandling) {
        self.switchBarHandler = switchBarHandler
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()

        setupView()
        installComponents()
        setupSubscriptions()

        suggestionTrayManager?.showInitialSuggestions()

        updateDaxVisibility()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)

        switchBarVC.focusTextField()
        if automaticallySelectsTextOnAppear {
            DispatchQueue.main.async {
                self.switchBarVC.textEntryViewController.selectAllText()
            }
        }
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)

        DailyPixel.fireDailyAndCount(pixel: .aiChatInternalSwitchBarDisplayed)
    }

    // MARK: - Public Methods
    
    @objc func dismissAnimated(_ completion: (() -> Void)? = nil) {
        if self.presentingViewController != nil {
            self.dismiss(animated: true, completion: completion)
        }
    }

    // MARK: - Private Methods
    
    private func setupView() {
        view.backgroundColor = UIColor(designSystemColor: .background)
    }
    
    private func installComponents() {
        installSwitchBarVC()
        installSwipeContainer()
        installSuggestionsTray()
        installDaxLogoView()
        installNavigationActionBar()

        view.bringSubviewToFront(switchBarVC.view)
    }

    private func installSwitchBarVC() {
        addChild(switchBarVC)
        view.addSubview(switchBarVC.view)
        switchBarVC.view.translatesAutoresizingMaskIntoConstraints = false
        switchBarVC.view.setContentHuggingPriority(.defaultHigh, for: .vertical)

        NSLayoutConstraint.activate([
            switchBarVC.view.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 8),
            switchBarVC.view.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor),
            switchBarVC.view.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor)
        ])

        switchBarVC.didMove(toParent: self)
        switchBarVC.backButton.addTarget(self, action: #selector(dismissButtonTapped), for: .touchUpInside)
    }

    private func installSwipeContainer() {
        let manager = SwipeContainerManager(switchBarHandler: switchBarHandler)
        manager.installInViewController(self, belowView: switchBarVC.view)
        manager.delegate = self
        swipeContainerManager = manager
    }

    private func installSuggestionsTray() {
        guard let dependencies = suggestionTrayDependencies,
              let swipeContainerViewController = swipeContainerManager?.swipeContainerViewController,
              let searchContainer = swipeContainerViewController.searchPageContainer else { return }

        let manager = SuggestionTrayManager(switchBarHandler: switchBarHandler, dependencies: dependencies)
        manager.delegate = self
        manager.installInContainerView(searchContainer, parentViewController: swipeContainerViewController)
        suggestionTrayManager = manager
    }

    private func installDaxLogoView() {
        daxLogoManager.installInViewController(self, belowView: switchBarVC.view)
    }
    
    private func installNavigationActionBar() {
        let manager = NavigationActionBarManager(switchBarHandler: switchBarHandler)
        manager.delegate = self
        manager.installInViewController(self)
        navigationActionBarManager = manager
    }

    private func setupSubscriptions() {
        switchBarHandler.currentTextPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] currentText in
                self?.delegate?.onQueryUpdated(currentText)
                self?.suggestionTrayManager?.handleQueryUpdate(currentText)
                self?.updateDaxVisibility()
            }
            .store(in: &cancellables)

        switchBarHandler.textSubmissionPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] submission in
                guard let self = self else { return }
                defer { self.switchBarHandler.clearText() }

                let text = submission.text

                if self.switchBarHandler.isCurrentTextValidURL {
                    self.delegate?.onQuerySubmitted(text)
                    return
                }

                switch submission.mode {
                case .search:
                    self.delegate?.onQuerySubmitted(text)

                case .aiChat:
                    // If we (re)add the web rag button, then we need to add it to the array of tools Duck.ai should use
                    //  for this submission.
                    self.delegate?.onPromptSubmitted(text, tools: nil)
                }
            }
            .store(in: &cancellables)

        switchBarHandler.microphoneButtonTappedPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in
                self?.handleMicrophoneButtonTapped()
            }
            .store(in: &cancellables)
    }

    // MARK: - Action Handlers

    @objc private func dismissButtonTapped(_ sender: UIButton) {
        switchBarVC.unfocusTextField()
        dismissAnimated()
    }

    private func handleMicrophoneButtonTapped() {
        delegate?.onVoiceSearchRequested(from: switchBarHandler.currentToggleState)
    }

    private func updateDaxVisibility() {

        let shouldDisplaySuggestionTray = suggestionTrayManager?.shouldDisplaySuggestionTray == true
        let shouldDisplayFavoritesOverlay = suggestionTrayManager?.shouldDisplayFavoritesOverlay == true

        let isHomeDaxVisible = !shouldDisplaySuggestionTray && !shouldDisplayFavoritesOverlay
        let isAIDaxVisible = !shouldDisplaySuggestionTray

        daxLogoManager.updateVisibility(isHomeDaxVisible: isHomeDaxVisible, isAIDaxVisible: isAIDaxVisible)
    }
}

// MARK: - SwipeContainerManagerDelegate

extension OmniBarEditingStateViewController: SwipeContainerViewControllerDelegate {
    
    func swipeContainerViewController(_ controller: SwipeContainerViewController, didSwipeToMode mode: TextEntryMode) {
        switchBarHandler.setToggleState(mode)
    }
    
    func swipeContainerViewController(_ controller: SwipeContainerViewController, didUpdateScrollProgress progress: CGFloat) {
        // Forward the scroll progress to the switch bar to animate the toggle
        switchBarVC.updateScrollProgress(progress)

        daxLogoManager.updateSwipeProgress(progress)
    }
}

// MARK: - SuggestionTrayManagerDelegate

extension OmniBarEditingStateViewController: SuggestionTrayManagerDelegate {
    
    func suggestionTrayManager(_ manager: SuggestionTrayManager, didSelectSuggestion suggestion: Suggestion) {
        delegate?.onSelectSuggestion(suggestion)
    }
    
    func suggestionTrayManager(_ manager: SuggestionTrayManager, didSelectFavorite favorite: BookmarkEntity) {
        delegate?.onSelectFavorite(favorite)
    }
    
    func suggestionTrayManager(_ manager: SuggestionTrayManager, shouldUpdateTextTo text: String) {
        switchBarHandler.updateCurrentText(text)
    }
    
}

// MARK: - NavigationActionBarManagerDelegate

extension OmniBarEditingStateViewController: NavigationActionBarManagerDelegate {
    
    func navigationActionBarManagerDidTapMicrophone(_ manager: NavigationActionBarManager) {
        handleMicrophoneButtonTapped()
    }
    
    func navigationActionBarManagerDidTapNewLine(_ manager: NavigationActionBarManager) {
        let currentText = switchBarHandler.currentText
        let newText = currentText + "\n"
        switchBarHandler.updateCurrentText(newText)
    }
    
    func navigationActionBarManagerDidTapSearch(_ manager: NavigationActionBarManager) {
        let currentText = switchBarHandler.currentText
        if !currentText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            switchBarHandler.submitText(currentText)
        }
    }
}
