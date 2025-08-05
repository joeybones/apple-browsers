//
//  TabTests.swift
//
//  Copyright © 2020 DuckDuckGo. All rights reserved.
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
import Navigation
import XCTest
import BrowserServicesKit

@testable import DuckDuckGo_Privacy_Browser

// swiftlint:disable opening_brace
@available(macOS 12.0, *)
final class TabTests: XCTestCase {

    struct URLs {
        let url = URL(string: "http://testhost.com/")!
        let url1 = URL(string: "https://localhost/1")!
        let url2 = URL(string: "http://something-else.biz/2")!
        let url3 = URL(string: "https://local-domain/3")!
    }
    let urls = URLs()

    var tab: Tab!
    var contentBlockingMock: ContentBlockingMock!
    var privacyFeaturesMock: AnyPrivacyFeatures!
    var privacyConfiguration: MockPrivacyConfiguration {
        contentBlockingMock.privacyConfigurationManager.privacyConfig as! MockPrivacyConfiguration
    }

    var schemeHandler: TestSchemeHandler!
    private var cancellables: Set<AnyCancellable>!

    override func setUp() {
        contentBlockingMock = ContentBlockingMock()
        privacyFeaturesMock = AppPrivacyFeatures(contentBlocking: contentBlockingMock, httpsUpgradeStore: HTTPSUpgradeStoreMock())
        // disable waiting for CBR compilation on navigation
        privacyConfiguration.isFeatureKeyEnabled = { _, _ in
            return false
        }

        schemeHandler = TestSchemeHandler()
        cancellables = []
    }

    override func tearDown() {
        tab = nil
        TestTabExtensionsBuilder.shared = .default
        contentBlockingMock = nil
        privacyFeaturesMock = nil
        schemeHandler = nil
        cancellables = nil
    }

    // MARK: - Tab Content

    @MainActor func testWhenSettingURLThenTabTypeChangesToStandard() {
        tab = Tab(content: .settings(pane: .autofill), webViewConfiguration: schemeHandler.webViewConfiguration())
        XCTAssertEqual(tab.content, .settings(pane: .autofill))

        tab.url = URL.duckDuckGo
        XCTAssertEqual(tab.content, .url(.duckDuckGo, source: .link))
    }

    // MARK: - Equality

    @MainActor func testWhenTabsAreIdenticalThenTheyAreEqual() {
        tab = Tab(content: .none, webViewConfiguration: schemeHandler.webViewConfiguration())
        let tab2 = tab

        XCTAssert(tab == tab2)
    }

    @MainActor func testWhenTabsArentIdenticalThenTheyArentEqual() {
        tab = Tab(content: .none, webViewConfiguration: schemeHandler.webViewConfiguration())
        tab.url = URL.duckDuckGo
        let tab2 = Tab(content: .none, webViewConfiguration: schemeHandler.webViewConfiguration())
        tab2.url = URL.duckDuckGo

        XCTAssert(tab != tab2)
    }

    // MARK: - "Crash Tab" functionality

    @MainActor func testWhenUserIsNotInternalThenTabCannotBeCrashed() {
        let internalUserDecider = MockInternalUserDecider()
        internalUserDecider.isInternalUser = false

        let featureFlagger = FeatureFlaggerMock(internalUserDecider: internalUserDecider)

        let tab = Tab(content: .newtab, featureFlagger: featureFlagger)
        XCTAssertFalse(tab.canKillWebContentProcess)
    }

    @MainActor func testWhenTabCrashDebugToolsFeatureFlagIsDisabledThenTabCannotBeCrashed() {
        let internalUserDecider = MockInternalUserDecider()
        internalUserDecider.isInternalUser = true

        let featureFlagger = FeatureFlaggerMock(internalUserDecider: internalUserDecider)

        let tab = Tab(content: .newtab, featureFlagger: featureFlagger)
        XCTAssertFalse(tab.canKillWebContentProcess)
    }

    @MainActor func testWhenTabCrashDebugToolsFeatureFlagIsEnabledThenTabCanBeCrashed() {
        let internalUserDecider = MockInternalUserDecider()
        internalUserDecider.isInternalUser = true

        let featureFlagger = FeatureFlaggerMock(internalUserDecider: internalUserDecider, enabledFeatureFlags: [.tabCrashDebugging])

        let tab = Tab(content: .newtab, featureFlagger: featureFlagger)
        XCTAssertTrue(tab.canKillWebContentProcess)
    }

    // MARK: - Dialogs

    @MainActor func testWhenAlertDialogIsShowingChangingURLClearsDialog() {
        tab = Tab(content: .none, webViewConfiguration: schemeHandler.webViewConfiguration())
        tab.url = .duckDuckGo
        let webViewMock = WebViewMock()
        let frameInfo = WKFrameInfoMock(webView: webViewMock, securityOrigin: WKSecurityOriginMock.new(url: .duckDuckGo), request: URLRequest(url: .duckDuckGo), isMainFrame: true)
        tab.webView(webViewMock, runJavaScriptAlertPanelWithMessage: "Alert", initiatedByFrame: frameInfo) { }
        XCTAssertNotNil(tab.userInteractionDialog)
        tab.url = .duckDuckGoMorePrivacyInfo
        XCTAssertNil(tab.userInteractionDialog)
    }

    @MainActor func testWhenDownloadDialogIsShowingChangingURLDoesNOTClearDialog() {
        // GIVEN
        tab = Tab(content: .none, webViewConfiguration: schemeHandler.webViewConfiguration(), extensionsBuilder: TestTabExtensionsBuilder(load: [DownloadsTabExtension.self]))
        tab.url = .duckDuckGo
        DownloadsPreferences(persistor: DownloadsPreferencesUserDefaultsPersistor()).alwaysRequestDownloadLocation = true
        tab.webView(WebViewMock(), saveDataToFile: Data(), suggestedFilename: "anything", mimeType: "application/pdf", originatingURL: .duckDuckGo)
        var expectedDialog: Tab.UserDialog?
        let expectation = expectation(description: "savePanelDialog published")
        tab.downloads?.savePanelDialogPublisher.sink(receiveValue: { userDialog in
            if let userDialog {
                expectation.fulfill()
                expectedDialog = userDialog
            }
        }).store(in: &cancellables)

        waitForExpectations(timeout: 1)
        // WHEN
        tab.url = .duckDuckGoMorePrivacyInfo

        // THEN
        XCTAssertNotNil(expectedDialog)
    }

    // MARK: - Back/Forward navigation

    @MainActor
    func testCanGoBack() throws {
        tab = Tab(content: .none, webViewConfiguration: schemeHandler.webViewConfiguration(), privacyFeatures: privacyFeaturesMock)

        var eCantGoBack = expectation(description: "canGoBack: false")
        var eCanGoBack: XCTestExpectation!
        let c = tab.$canGoBack.sink { canGoBack in
            if canGoBack {
                eCanGoBack.fulfill()
            } else {
                eCantGoBack.fulfill()
            }
        }
        var eCantGoForward = expectation(description: "canGoForward: false")
        var eCanGoForward: XCTestExpectation!
        let c2 = tab.$canGoForward.sink { canGoForward in
            if canGoForward {
                eCanGoForward.fulfill()
            } else {
                eCantGoForward.fulfill()
            }
        }
        var eDidFinishLoading = expectation(description: "isLoading: false")
        let c3 = tab.webView.publisher(for: \.isLoading).sink { isLoading in
            if !isLoading {
                eDidFinishLoading.fulfill()
            }
        }

        // initial: false
        waitForExpectations(timeout: 0)

        schemeHandler.middleware = [{ _ in
            .ok(.html(""))
        }]

        // after first navigation: false
        eDidFinishLoading = expectation(description: "didFinish 1")
        tab.setContent(.url(urls.url, source: .link))
        waitForExpectations(timeout: 5)

        // after second navigation: true
        eCanGoBack = expectation(description: "canGoBack: true")
        eDidFinishLoading = expectation(description: "gb_didFinish 2")
        tab.setContent(.url(urls.url1, source: .link))
        waitForExpectations(timeout: 5)

        // after go back: false
        eCantGoBack = expectation(description: "canGoBack: false 2")
        eCanGoForward = expectation(description: "canGoForward: true")
        eDidFinishLoading = expectation(description: "didFinish 3")
        tab.goBack()
        waitForExpectations(timeout: 5)

        // after go forward: true
        eCanGoBack = expectation(description: "canGoBack: true")
        eCantGoForward = expectation(description: "canGoForward: false")
        eDidFinishLoading = expectation(description: "didFinish 4")
        tab.goForward()
        waitForExpectations(timeout: 5)

        withExtendedLifetime((c, c2, c3)) {}
    }

    @MainActor
    func testWhenGoingBackInvalidatingBackItem_BackForwardButtonsDoNotBlink() throws {
        var didFinishExpectations = [String: XCTestExpectation]()
        var eDidRedirect: XCTestExpectation!
        let extensionsBuilder = TestTabExtensionsBuilder(load: []) { [urls, unowned self] builder in { _, _ in
            builder.add {
                TestsClosureNavigationResponderTabExtension(.init { [unowned self] navigationAction, _ in
                    if navigationAction.url == urls.url2, let mainFrameTarget = navigationAction.mainFrameTarget {
                        return .redirect(mainFrameTarget) { navigator in
                            eDidRedirect.fulfill()
                            didFinishExpectations[urls.url3.absoluteString] = self.expectation(description: "didFinish \(urls.url3.absoluteString)")
                            navigator.load(URLRequest(url: urls.url3))
                        }
                    }
                    return .next
                } navigationDidFinish: { navigation in
                    didFinishExpectations[navigation.url.absoluteString]?.fulfill()
                })
            }
        }}

        tab = Tab(content: .none, webViewConfiguration: schemeHandler.webViewConfiguration(), privacyFeatures: privacyFeaturesMock, extensionsBuilder: extensionsBuilder)

        schemeHandler.middleware = [{ [urls] request in
            guard request.url!.path == urls.url1.path else { return nil }

            return .ok(.html("""
                <html><body><script language='JavaScript'>
                    window.parent.location.replace("\(urls.url2.absoluteString)");
                </script></body></html>
            """))
        }, { _ in
            return .ok(.html(""))
        }]

        // initial page: http://testhost.com/
        didFinishExpectations[urls.url.absoluteString] = expectation(description: "didFinish \(urls.url.absoluteString)")
        tab.setContent(.url(urls.url, source: .link))
        waitForExpectations(timeout: 5)

        // load urls.url1 which will be js-redirected to urls.url2
        // it should be .redirected with .goBack() to urls.url3
        didFinishExpectations[urls.url1.absoluteString] = expectation(description: "didFinish \(urls.url1.absoluteString)")

        // back/forward buttons state shouldn‘t change during the redirect
        let eCantGoBack = expectation(description: "initial canGoBack: false")
        // canGoBack should be set once during navigation to urls.url1 and not changed
        let eCanGoBack = expectation(description: "canGoBack -> true")
        let c1 = tab.$canGoBack.sink { canGoBack in
            if canGoBack {
                eCanGoBack.fulfill()
            } else {
                eCantGoBack.fulfill()
            }
        }
        let eCanGoForward = expectation(description: "initial canGoForward")
        let c2 = tab.$canGoForward.sink { canGoForward in
            XCTAssertFalse(canGoForward)
            eCanGoForward.fulfill()
        }

        eDidRedirect = expectation(description: "did redirect")

        // navigate to https://localhost/1
        tab.setContent(.url(urls.url1, source: .link))
        waitForExpectations(timeout: 5)
        // "didFinish \(urls.url3.absoluteString)" expectation is set in redirect handler above
        waitForExpectations(timeout: 5)

        XCTAssertTrue(tab.canGoBack)
        XCTAssertFalse(tab.canGoForward)
        XCTAssertEqual(tab.webView.url, urls.url3)
        XCTAssertEqual(tab.webView.backForwardList.currentItem?.url, urls.url3)
        XCTAssertEqual(tab.backHistoryItems.map(\.url), [urls.url])
        XCTAssertEqual(tab.forwardHistoryItems, [])

        withExtendedLifetime((c1, c2)) {}
    }

    @MainActor
    func testWhenGoingBackInvalidatingBackItemWithExistingBackItem_BackForwardButtonsDoNotBlink() throws {
        var eDidFinish: XCTestExpectation!
        var eDidRedirect: XCTestExpectation!
        let extensionsBuilder = TestTabExtensionsBuilder(load: []) { [urls] builder in { _, _ in
            builder.add {
                TestsClosureNavigationResponderTabExtension(.init { navigationAction, _ in
                    if navigationAction.url == urls.url2, let mainFrameTarget = navigationAction.mainFrameTarget {
                        return .redirect(mainFrameTarget) { navigator in
                            eDidRedirect.fulfill()
                            navigator.load(URLRequest(url: urls.url3))
                        }
                    }
                    return .next
                } navigationDidFinish: { _ in
                    eDidFinish?.fulfill()
                })
            }
        }}

        tab = Tab(content: .none, webViewConfiguration: schemeHandler.webViewConfiguration(), privacyFeatures: privacyFeaturesMock, extensionsBuilder: extensionsBuilder)

        schemeHandler.middleware = [{ [urls] request in
            guard request.url!.path == urls.url1.path else { return nil }

            return .ok(.html("""
                <html><body><script language='JavaScript'>
                    window.parent.location.replace("\(urls.url2.absoluteString)");
                </script></body></html>
            """))
        }, { _ in
            return .ok(.html(""))
        }]

        // initial page
        eDidFinish = expectation(description: "didFinish 1")
        tab.setContent(.url(urls.url, source: .link))
        waitForExpectations(timeout: 5)

        // page 2 to make canGoBack == true
        eDidFinish = expectation(description: "didFinish 1")
        tab.setContent(.url(urls.url3, source: .link))
        waitForExpectations(timeout: 5)

        // load urls.url1 which will be js-redirected to urls.url2
        // it should be .redirected with .goBack() to urls.url3
        eDidFinish = expectation(description: "didFinish 2")

        // back/forward buttons state shouldn‘t change during the redirect
        let c1 = tab.$canGoBack.sink { canGoBack in
            XCTAssertTrue(canGoBack)
        }
        let c2 = tab.$canGoForward.sink { canGoForward in
            XCTAssertFalse(canGoForward)
        }

        eDidRedirect = expectation(description: "did redirect")

        tab.setContent(.url(urls.url1, source: .link))
        waitForExpectations(timeout: 5)
        eDidFinish = nil

        XCTAssertTrue(tab.canGoBack)
        XCTAssertFalse(tab.canGoForward)
        XCTAssertEqual(tab.webView.url, urls.url3)
        XCTAssertEqual(tab.backHistoryItems.map(\.url), [urls.url, urls.url3])
        XCTAssertEqual(tab.forwardHistoryItems, [])

        withExtendedLifetime((c1, c2)) {}
    }

    @MainActor
    func testIfTabIsBurner_ThenFaviconManagerIsInMemory() throws {
        let builder = TestTabExtensionsBuilder.shared
        builder.shouldCaptureBuildCalls = true
        defer {
            builder.shouldCaptureBuildCalls = false
            builder.buildCalls = []
        }
        builder.buildCalls = []

        _ = Tab(content: .newtab)
        let faviconManagement = try XCTUnwrap(builder.buildCalls[safe: 0]?.1.faviconManagement)
        XCTAssertTrue(faviconManagement === NSApp.delegateTyped.faviconManager)

        _ = Tab(content: .newtab, burnerMode: BurnerMode(isBurner: true))
        let burnerFaviconManagement = try XCTUnwrap(builder.buildCalls[safe: 1]?.1.faviconManagement)
        XCTAssertTrue(burnerFaviconManagement !== NSApp.delegateTyped.faviconManager)
    }

    // MARK: - Control Center Media Session enabled

    @MainActor func testWhenRegularWindow_mediaSessionEnabled() {
        tab = Tab(content: .url(.empty, source: .ui), webViewConfiguration: schemeHandler.webViewConfiguration(), burnerMode: .regular)

        XCTAssertTrue(tab.webView.configuration.preferences[.mediaSessionEnabled])
    }

    @MainActor func testWhenFireWindow_mediaSessionDisabled() {
        tab = Tab(content: .url(.empty, source: .ui), webViewConfiguration: schemeHandler.webViewConfiguration(), burnerMode: BurnerMode(isBurner: true))

        XCTAssertFalse(tab.webView.configuration.preferences[.mediaSessionEnabled])
    }

}

private extension Tab {

    var url: URL? {
        get {
            content.userEditableUrl
        }
        set {
            setContent(newValue.map { TabContent.url($0, source: .link) } ?? .newtab)
        }
    }
}
