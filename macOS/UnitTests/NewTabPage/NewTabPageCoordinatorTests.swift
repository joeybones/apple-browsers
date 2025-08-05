//
//  NewTabPageCoordinatorTests.swift
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
import Common
import NewTabPage
import PersistenceTestingUtils
import PixelKit
import PrivacyStats
import XCTest
import BrowserServicesKit
@testable import DuckDuckGo_Privacy_Browser

final class MockPrivacyStats: PrivacyStatsCollecting {

    let statsUpdatePublisher: AnyPublisher<Void, Never> = Empty<Void, Never>().eraseToAnyPublisher()

    func recordBlockedTracker(_ name: String) async {}
    func fetchPrivacyStats() async -> [String: Int64] { [:] }
    func fetchPrivacyStatsTotalCount() async -> Int64 { 0 }
    func clearPrivacyStats() async {}
    func handleAppTermination() async {}
}

final class NewTabPageCoordinatorTests: XCTestCase {
    var coordinator: NewTabPageCoordinator!
    var appearancePreferences: AppearancePreferences!
    var customizationModel: NewTabPageCustomizationModel!
    var notificationCenter: NotificationCenter!
    var keyValueStore: MockKeyValueFileStore!
    var firePixelCalls: [PixelKitEvent] = []
    var featureFlagger: FeatureFlagger!
    var windowControllersManager: WindowControllersManagerProtocol!
    var tabsPreferences: TabsPreferences!

    @MainActor
    override func setUp() async throws {
        try await super.setUp()

        notificationCenter = NotificationCenter()
        keyValueStore = try MockKeyValueFileStore()
        firePixelCalls.removeAll()
        featureFlagger = MockFeatureFlagger()

        let appearancePreferencesPersistor = AppearancePreferencesPersistorMock()
        appearancePreferences = AppearancePreferences(
            persistor: appearancePreferencesPersistor,
            privacyConfigurationManager: MockPrivacyConfigurationManager(),
            featureFlagger: featureFlagger
        )

        customizationModel = NewTabPageCustomizationModel(
            appearancePreferences: appearancePreferences,
            userBackgroundImagesManager: nil,
            sendPixel: { _ in },
            openFilePanel: { nil },
            showAddImageFailedAlert: {},
            visualStyle: VisualStyle.legacy
        )

        windowControllersManager = WindowControllersManagerMock()

        tabsPreferences = TabsPreferences(persistor: MockTabsPreferencesPersistor())

        featureFlagger = FeatureFlaggerMock()

        coordinator = NewTabPageCoordinator(
            appearancePreferences: appearancePreferences,
            customizationModel: customizationModel,
            bookmarkManager: MockBookmarkManager(),
            faviconManager: FaviconManagerMock(),
            activeRemoteMessageModel: ActiveRemoteMessageModel(
                remoteMessagingStore: MockRemoteMessagingStore(),
                remoteMessagingAvailabilityProvider: MockRemoteMessagingAvailabilityProvider(),
                openURLHandler: { _ in },
                navigateToFeedbackHandler: { }
            ),
            historyCoordinator: HistoryCoordinatingMock(),
            contentBlocking: ContentBlockingMock(),
            fireproofDomains: MockFireproofDomains(domains: []),
            privacyStats: MockPrivacyStats(),
            freemiumDBPPromotionViewCoordinator: FreemiumDBPPromotionViewCoordinator(
                freemiumDBPUserStateManager: MockFreemiumDBPUserStateManager(),
                freemiumDBPFeature: MockFreemiumDBPFeature(),
                freemiumDBPPresenter: MockFreemiumDBPPresenter(),
                notificationCenter: notificationCenter,
                dataBrokerProtectionFreemiumPixelHandler: MockDataBrokerProtectionFreemiumPixelHandler()
            ),
            tld: Application.appDelegate.tld,
            fireCoordinator: FireCoordinator(tld: Application.appDelegate.tld),
            keyValueStore: keyValueStore,
            notificationCenter: notificationCenter,
            visualizeFireAnimationDecider: MockVisualizeFireAnimationDecider(),
            featureFlagger: featureFlagger,
            windowControllersManager: windowControllersManager,
            tabsPreferences: tabsPreferences,
            newTabPageAIChatShortcutSettingProvider: MockNewTabPageAIChatShortcutSettingProvider(),
            fireDailyPixel: { self.firePixelCalls.append($0) }
        )
    }

    override func tearDown() {
        appearancePreferences = nil
        coordinator = nil
        customizationModel = nil
        featureFlagger = nil
        firePixelCalls = []
        keyValueStore = nil
        notificationCenter = nil
        tabsPreferences = nil
        windowControllersManager = nil
    }

    func testWhenNewTabPageAppearsThenPixelIsSent() {
        notificationCenter.post(name: .newTabPageWebViewDidAppear, object: nil)
        XCTAssertEqual(firePixelCalls.count, 1)
    }
}
