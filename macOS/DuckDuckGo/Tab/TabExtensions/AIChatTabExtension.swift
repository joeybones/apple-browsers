//
//  AIChatTabExtension.swift
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

import Navigation
import Foundation
import Combine
import WebKit
import AIChat

protocol AIChatUserScriptProvider {
    var aiChatUserScript: AIChatUserScript? { get }
}
extension UserScripts: AIChatUserScriptProvider {}

final class AIChatTabExtension {

    private var cancellables = Set<AnyCancellable>()
    private let isLoadedInSidebar: Bool
    private weak var webView: WKWebView?

    private(set) weak var aiChatUserScript: AIChatUserScript?

    init(scriptsPublisher: some Publisher<some AIChatUserScriptProvider, Never>,
         webViewPublisher: some Publisher<WKWebView, Never>,
         isLoadedInSidebar: Bool) {
        self.isLoadedInSidebar = isLoadedInSidebar

        webViewPublisher.sink { [weak self] webView in
            self?.webView = webView
            self?.aiChatUserScript?.webView = webView
        }.store(in: &cancellables)

        scriptsPublisher.sink { [weak self] scripts in
            Task { @MainActor in
                self?.aiChatUserScript = scripts.aiChatUserScript
                self?.aiChatUserScript?.webView = self?.webView

                // Pass the handoff payload in case it was provided before the user script was loaded
                if let payload = self?.temporaryAIChatNativeHandoffData {
                    self?.aiChatUserScript?.handler.messageHandling.setData(payload, forMessageType: .nativeHandoffData)
                    self?.temporaryAIChatNativeHandoffData = nil
                }

                if let data = self?.temporaryAIChatRestorationData {
                    self?.aiChatUserScript?.handler.messageHandling.setData(data, forMessageType: .chatRestorationData)
                    self?.temporaryAIChatRestorationData = nil
                }

                if let prompt = self?.temporaryAIChatNativePrompt {
                    self?.aiChatUserScript?.handler.submitAIChatNativePrompt(prompt)
                    self?.temporaryAIChatNativePrompt = nil
                }

                if let pageContext = self?.temporaryPageContext {
                    /// See the comment in `self.submitPageContext` for the explanation of why we're calling user script twice.
                    self?.aiChatUserScript?.handler.messageHandling.setData(pageContext, forMessageType: .pageContext)
                    self?.aiChatUserScript?.handler.submitPageContext(pageContext)
                    self?.temporaryPageContext = nil
                }
            }
        }.store(in: &cancellables)
    }

    private var temporaryAIChatNativeHandoffData: AIChatPayload?
    func setAIChatNativeHandoffData(payload: AIChatPayload) {
        guard let aiChatUserScript else {
            // User script not yet loaded, store the payload and set when ready
            temporaryAIChatNativeHandoffData = payload
            return
        }

        aiChatUserScript.handler.messageHandling.setData(payload, forMessageType: .nativeHandoffData)
    }

    private var temporaryAIChatRestorationData: AIChatRestorationData?
    func setAIChatRestorationData(data: AIChatRestorationData) {
        guard let aiChatUserScript else {
            // User script not yet loaded, store the payload and set when ready
            temporaryAIChatRestorationData = data
            return
        }

        aiChatUserScript.handler.messageHandling.setData(data, forMessageType: .chatRestorationData)
    }

    private var temporaryAIChatNativePrompt: AIChatNativePrompt?
    func submitAIChatNativePrompt(_ prompt: AIChatNativePrompt) {
        guard let aiChatUserScript else {
            // User script not yet loaded, store the payload and set when ready
            temporaryAIChatNativePrompt = prompt
            return
        }

        aiChatUserScript.handler.submitAIChatNativePrompt(prompt)
    }

    private var temporaryPageContext: AIChatPageContextData?
    func submitPageContext(_ pageContext: AIChatPageContextData) {
        // Page Context functionality is only for the sidebar.
        guard isLoadedInSidebar else {
            return
        }

        guard let aiChatUserScript else {
            // User script not yet loaded, store the payload and set when ready
            temporaryPageContext = pageContext
            return
        }

        ///
        /// We're both making the data available for `getPageContext` (by storing it in the page context handler)
        /// and calling `submitPageContext`, because when sidebar is just presented, it's not ready to receive
        /// `submitPageContext` and will call `getPageContext` at a later time (when fully initialized).
        /// After that it will exclusively use `submitPageContext`.
        ///
        /// This can be optimized later to only call one function, depending on whether `getPageContext`
        /// was received by this user script.
        ///
        aiChatUserScript.handler.messageHandling.setData(pageContext, forMessageType: .pageContext)
        aiChatUserScript.handler.submitPageContext(pageContext)
    }
}

extension AIChatTabExtension: NavigationResponder {

    func decidePolicy(for navigationAction: NavigationAction, preferences: inout NavigationPreferences) async -> NavigationActionPolicy? {
        guard isLoadedInSidebar,
              !navigationAction.navigationType.isSameDocumentNavigation,
              navigationAction.isUserInitiated,
              let parentWindowController = Application.appDelegate.windowControllersManager.lastKeyMainWindowController
        else {
            return .next
        }

        let tabCollectionViewModel = parentWindowController.mainViewController.tabCollectionViewModel
        tabCollectionViewModel.insertOrAppendNewTab(.url(navigationAction.url, source: .link))
        return .cancel
    }
}

protocol AIChatProtocol: AnyObject, NavigationResponder {
    var aiChatUserScript: AIChatUserScript? { get }
    func setAIChatNativeHandoffData(payload: AIChatPayload)
    func setAIChatRestorationData(data: AIChatRestorationData)
    func submitAIChatNativePrompt(_ prompt: AIChatNativePrompt)
    func submitPageContext(_ pageContext: AIChatPageContextData)
}

extension AIChatTabExtension: AIChatProtocol, TabExtension {
    func getPublicProtocol() -> AIChatProtocol { self }
}

extension TabExtensions {
    var aiChat: AIChatProtocol? { resolve(AIChatTabExtension.self) }
}
