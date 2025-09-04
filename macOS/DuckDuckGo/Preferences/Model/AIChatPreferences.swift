//
//  AIChatPreferences.swift
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

import AIChat
import AppKit
import BrowserServicesKit
import Combine
import Foundation
import PixelKit

final class AIChatPreferences: ObservableObject {
    static let shared = AIChatPreferences()
    private var storage: AIChatPreferencesStorage
    private var cancellables = Set<AnyCancellable>()
    private let learnMoreURL = URL(string: "https://duckduckgo.com/duckduckgo-help-pages/duckai/approach-to-ai")!
    private let searchAssistSettingsURL = URL(string: "https://duckduckgo.com/settings#aifeatures")!
    private let aiChatMenuConfiguration: AIChatMenuVisibilityConfigurable
    private var windowControllersManager: WindowControllersManager
    private let featureFlagger: FeatureFlagger

    init(storage: AIChatPreferencesStorage = DefaultAIChatPreferencesStorage(),
         aiChatMenuConfiguration: AIChatMenuVisibilityConfigurable = Application.appDelegate.aiChatMenuConfiguration,
         windowControllersManager: WindowControllersManager = Application.appDelegate.windowControllersManager,
         featureFlagger: FeatureFlagger = Application.appDelegate.featureFlagger) {
        self.storage = storage
        self.aiChatMenuConfiguration = aiChatMenuConfiguration
        self.windowControllersManager = windowControllersManager
        self.featureFlagger = featureFlagger

        isAIFeaturesEnabled = storage.isAIFeaturesEnabled
        showShortcutOnNewTabPage = storage.showShortcutOnNewTabPage
        showShortcutInApplicationMenu = storage.showShortcutInApplicationMenu
        showShortcutInAddressBar = storage.showShortcutInAddressBar
        openAIChatInSidebar = storage.openAIChatInSidebar
        isPageContextEnabled = storage.isPageContextEnabled

        subscribeToShowInApplicationMenuSettingsChanges()
    }

    func subscribeToShowInApplicationMenuSettingsChanges() {
        storage.isAIFeaturesEnabledPublisher
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .assign(to: \.isAIFeaturesEnabled, onWeaklyHeld: self)
            .store(in: &cancellables)

        storage.showShortcutOnNewTabPagePublisher
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .assign(to: \.showShortcutOnNewTabPage, onWeaklyHeld: self)
            .store(in: &cancellables)

        storage.showShortcutInApplicationMenuPublisher
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .assign(to: \.showShortcutInApplicationMenu, onWeaklyHeld: self)
            .store(in: &cancellables)

        storage.showShortcutInAddressBarPublisher
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .assign(to: \.showShortcutInAddressBar, onWeaklyHeld: self)
            .store(in: &cancellables)

        storage.openAIChatInSidebarPublisher
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .assign(to: \.openAIChatInSidebar, onWeaklyHeld: self)
            .store(in: &cancellables)
    }

    // Options visibility

    var shouldShowAIFeatures: Bool {
        aiChatMenuConfiguration.shouldDisplayAnyAIChatFeature
    }

    var shouldShowAIFeaturesToggle: Bool {
        featureFlagger.isFeatureOn(.aiChatGlobalSwitch)
    }

    var shouldShowOpenAIChatInSidebarToggle: Bool {
        featureFlagger.isFeatureOn(.aiChatSidebar)
    }

    var shouldShowPageContextToggle: Bool {
        featureFlagger.isFeatureOn(.aiChatPageContext)
    }

    var shouldShowNewTabPageToggle: Bool {
        featureFlagger.isFeatureOn(.newTabPageOmnibar)
    }

    // Properties for managing the current state of AI Chat preference options

    @Published var isAIFeaturesEnabled: Bool {
        didSet { storage.isAIFeaturesEnabled = isAIFeaturesEnabled }
    }

    @Published var showShortcutOnNewTabPage: Bool {
        didSet { storage.showShortcutOnNewTabPage = showShortcutOnNewTabPage }
    }

    @Published var showShortcutInApplicationMenu: Bool {
        didSet { storage.showShortcutInApplicationMenu = showShortcutInApplicationMenu }
    }

    @Published var showShortcutInAddressBar: Bool {
        didSet { storage.showShortcutInAddressBar = showShortcutInAddressBar }
    }

    @Published var openAIChatInSidebar: Bool {
        didSet { storage.openAIChatInSidebar = openAIChatInSidebar }
    }

    @Published var isPageContextEnabled: Bool {
        didSet { storage.isPageContextEnabled = isPageContextEnabled }
    }

    @MainActor func openLearnMoreLink() {
        windowControllersManager.show(url: learnMoreURL, source: .ui, newTab: true)
    }

    @MainActor func openAIChatLink() {
        NSApp.delegateTyped.aiChatTabOpener.openAIChatTab()
    }

    @MainActor func openSearchAssistSettings() {
        windowControllersManager.show(url: searchAssistSettingsURL, source: .ui, newTab: true)
    }
}
