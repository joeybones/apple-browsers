//
//  NewTabPageTabExtension.swift
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

import Combine
import Foundation
import Navigation
import NewTabPage
import WebKit

protocol NewTabPageUserScriptProvider {
    var newTabPageUserScript: NewTabPageUserScript? { get }
}
extension UserScripts: NewTabPageUserScriptProvider {}

final class NewTabPageTabExtension {
    private var cancellables = Set<AnyCancellable>()
    private weak var newTabPageUserScript: NewTabPageUserScript?
    private var content: Tab.TabContent?
    private let pixelSender: NewTabPageShownPixelSender
    private let loadMetrics = NewTabPageLoadMetrics()
    private var sendPixelOnFinish = false
    private weak var webView: WKWebView? {
        didSet {
            newTabPageUserScript?.webView = webView
        }
    }

    init(
        scriptsPublisher: some Publisher<some NewTabPageUserScriptProvider, Never>,
        webViewPublisher: some Publisher<WKWebView, Never>,
        pixelSender: NewTabPageShownPixelSender
    ) {
        self.pixelSender = pixelSender

        scriptsPublisher.sink { [weak self] scripts in
            Task { @MainActor in
                self?.newTabPageUserScript = scripts.newTabPageUserScript
                self?.newTabPageUserScript?.webView = self?.webView
            }
        }.store(in: &cancellables)

        webViewPublisher.sink { [weak self] webView in
            self?.webView = webView
        }.store(in: &cancellables)

    }

    func onNewTabPageWillPresent() {
        loadMetrics.onNTPWillPresent()
    }

    func onNewTabPageDidPresent() {
        guard webView?.superview != nil else {
            assertionFailure("Webview not yet added to the view hierarchy")
            return
        }

        pixelSender.firePixel()
        if webView?.isLoading == true {
            sendPixelOnFinish = true
        } else {
            loadMetrics.onNTPDidPresent()
        }
    }

}

extension NewTabPageTabExtension: NavigationResponder {

    func navigationDidFinish(_ navigation: Navigation) {
        if sendPixelOnFinish {
            sendPixelOnFinish = false
            guard webView?.superview != nil else {
                return
            }
            loadMetrics.onNTPDidPresent()
        }
    }

}

protocol NewTabPageTabExtensionProtocol: AnyObject, NavigationResponder {

    func onNewTabPageWillPresent()
    func onNewTabPageDidPresent()

}

extension NewTabPageTabExtension: NewTabPageTabExtensionProtocol, TabExtension {
    func getPublicProtocol() -> NewTabPageTabExtensionProtocol { self }
}

extension TabExtensions {
    var newTabPage: NewTabPageTabExtensionProtocol? {
        resolve(NewTabPageTabExtension.self)
    }
}
