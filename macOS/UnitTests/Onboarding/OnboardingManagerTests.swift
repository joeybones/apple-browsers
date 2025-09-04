//
//  OnboardingManagerTests.swift
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

import XCTest
@testable import DuckDuckGo_Privacy_Browser
import SwiftUI
import Persistence

class OnboardingManagerTests: XCTestCase {

    var manager: OnboardingActionsManaging!
    var navigationDelegate: CapturingOnboardingNavigation!
    var dockCustomization: CapturingDockCustomizer!
    var defaultBrowserProvider: CapturingDefaultBrowserProvider!
    var appearancePreferences: AppearancePreferences!
    var startupPreferences: StartupPreferences!
    var appearancePersistor: MockAppearancePreferencesPersistor!
    var fireButtonPreferencesPersistor: MockFireButtonPreferencesPersistor!
    var dataClearingPreferences: DataClearingPreferences!
    var startupPersistor: StartupPreferencesUserDefaultsPersistor!
    var importProvider: CapturingDataImportProvider!

    @MainActor override func setUp() {
        navigationDelegate = CapturingOnboardingNavigation()
        dockCustomization = CapturingDockCustomizer()
        defaultBrowserProvider = CapturingDefaultBrowserProvider()
        appearancePersistor = MockAppearancePreferencesPersistor()
        appearancePreferences = AppearancePreferences(persistor: appearancePersistor, privacyConfigurationManager: MockPrivacyConfigurationManager(), featureFlagger: MockFeatureFlagger())
        startupPersistor = StartupPreferencesUserDefaultsPersistor(keyValueStore: MockKeyValueStore())
        fireButtonPreferencesPersistor = MockFireButtonPreferencesPersistor()
        dataClearingPreferences = DataClearingPreferences(
            persistor: fireButtonPreferencesPersistor,
            fireproofDomains: MockFireproofDomains(domains: []),
            faviconManager: FaviconManagerMock(),
            windowControllersManager: WindowControllersManagerMock(),
            featureFlagger: MockFeatureFlagger()
        )
        startupPreferences = StartupPreferences(persistor: startupPersistor, appearancePreferences: appearancePreferences)
        importProvider = CapturingDataImportProvider()
        manager = OnboardingActionsManager(navigationDelegate: navigationDelegate, dockCustomization: dockCustomization, defaultBrowserProvider: defaultBrowserProvider, appearancePreferences: appearancePreferences, startupPreferences: startupPreferences, dataImportProvider: importProvider)
    }

    override func tearDown() {
        manager = nil
        navigationDelegate = nil
        dockCustomization = nil
        defaultBrowserProvider = nil
        appearancePreferences = nil
        startupPreferences = nil
        appearancePersistor = nil
        dataClearingPreferences = nil
        fireButtonPreferencesPersistor = nil
        importProvider = nil
    }

    func testReturnsExpectedOnboardingConfig() {
        // Given
        var systemSettings: SystemSettings
#if APPSTORE
        systemSettings = SystemSettings(rows: ["import"])
#else
        systemSettings = SystemSettings(rows: ["dock", "import"])
#endif
        let stepDefinitions = StepDefinitions(systemSettings: systemSettings)
        let expectedConfig = OnboardingConfiguration(
            stepDefinitions: stepDefinitions,
            exclude: [],
            order: "v3",
            env: "development",
            locale: "en",
            platform: .init(name: "macos")
        )

        // Then
        XCTAssertEqual(manager.configuration, expectedConfig)
    }

    func testOnOnboardingStarted_UserInteractionIsPrevented() {
        // Given
        navigationDelegate.preventUserInteraction = false

        // When
        manager.onboardingStarted()

        // Then
        XCTAssertTrue(navigationDelegate.updatePreventUserInteractionCalled)
        XCTAssertTrue(navigationDelegate.preventUserInteraction ?? false)
    }

    func testGoToAddressBar_NavigatesToSearch() {
        // Given
        let isOnboardingFinished = UserDefaultsWrapper(key: .onboardingFinished, defaultValue: true)
        isOnboardingFinished.wrappedValue = false

        // When
        manager.goToAddressBar()

        // Then
        XCTAssertTrue(navigationDelegate.replaceTabCalled)
        XCTAssertEqual(navigationDelegate.tab?.url, URL.duckDuckGo)
        XCTAssertTrue(navigationDelegate.updatePreventUserInteractionCalled)
        XCTAssertFalse(navigationDelegate.preventUserInteraction ?? true)
        XCTAssertTrue(isOnboardingFinished.wrappedValue)
    }

    func testGoToAddressBar_NavigatesToSearch_AndFocusOnBar() {
        // Given
        let isOnboardingFinished = UserDefaultsWrapper(key: .onboardingFinished, defaultValue: true)
        isOnboardingFinished.wrappedValue = false

        // When
        manager.goToAddressBar()

        // Then
        XCTAssertTrue(navigationDelegate.replaceTabCalled)
        XCTAssertEqual(navigationDelegate.tab?.url, URL.duckDuckGo)
        XCTAssertTrue(navigationDelegate.updatePreventUserInteractionCalled)
        XCTAssertFalse(navigationDelegate.preventUserInteraction ?? true)
        XCTAssertTrue(isOnboardingFinished.wrappedValue)

        // When
        navigationDelegate.fireNavigationDidEnd()

        // Then
        XCTAssertTrue(navigationDelegate.focusOnAddressBarCalled)
    }

    func test_WhenFireNavigationDidEndTwice_FocusOnBarIsCalledOnlyOnce() {
        // Given
        let isOnboardingFinished = UserDefaultsWrapper(key: .onboardingFinished, defaultValue: true)
        isOnboardingFinished.wrappedValue = false
        manager.goToAddressBar()
        navigationDelegate.fireNavigationDidEnd()
        XCTAssertTrue(navigationDelegate.focusOnAddressBarCalled)
        navigationDelegate.focusOnAddressBarCalled = false

        // When
        navigationDelegate.fireNavigationDidEnd()

        // Then
        XCTAssertFalse(navigationDelegate.focusOnAddressBarCalled)
    }

    func testGoToAddressBar_NavigatesToSettings() {
        // When
        manager.goToSettings()

        // Then
        XCTAssertTrue(navigationDelegate.replaceTabCalled)
        XCTAssertEqual(navigationDelegate.tab?.url, URL.settings)
    }

    @MainActor
    func testOnImportData_DataImportViewShown() async {
        // Given
        importProvider.didImport = true

        // When
        let didImport = await manager.importData()

        // Then
        XCTAssertTrue(importProvider.showImportWindowCalled)
        XCTAssertTrue(didImport)
    }

    func testOnAddToDock_IsAddedToDock() {
        // When
        manager.addToDock()

        // Then
        XCTAssertTrue(dockCustomization.isAddedToDock)
    }

    func testOnSetAsDefault_DefaultPromptShown() {
        // When
        manager.setAsDefault()

        // Then
        XCTAssertTrue(defaultBrowserProvider.presentDefaultBrowserPromptCalled)
    }

    func testOnSetBookmarksBar_andBarNotShown_ThenBarIsShown() {
        // When
        manager.setBookmarkBar(enabled: true)

        // Then
        XCTAssertTrue(appearancePersistor.showBookmarksBar)
    }

    func testOnSetBookmarksBar_andBarIsShown_ThenBarIsShown() {
        // Given
        appearancePreferences.showBookmarksBar = true

        // When
        manager.setBookmarkBar(enabled: false)

        // Then
        XCTAssertFalse(appearancePersistor.showBookmarksBar)
    }

    func testOnSetSessionRestore_andSessionRestoreOff_sessionRestorationSetOn() {
        // When
        manager.setSessionRestore(enabled: true)

        // Then
        XCTAssertTrue(startupPersistor.restorePreviousSession)
    }

    func testOnSetSessionRestore_andSessionRestoreOn_sessionRestorationSetOff() {
        // Given
        startupPreferences.restorePreviousSession = true

        // When
        manager.setSessionRestore(enabled: false)

        // Then
        XCTAssertFalse(startupPersistor.restorePreviousSession)
    }

    func testOnSetHomeButtonPosition_ifHidden_showHomeButton() {
        // When
        manager.setHomeButtonPosition(enabled: true)

        // Then
        XCTAssertEqual(self.appearancePersistor.homeButtonPosition, .left)
    }

    func testOnSetHomeButtonPosition_ifShown_hideHomeButton() {
        // Given
        startupPreferences.homeButtonPosition = .left

        // When
        manager.setHomeButtonPosition(enabled: false)

        // Then
        XCTAssertEqual(self.appearancePersistor.homeButtonPosition, .hidden)
    }

}

private final class MockKeyValueStore: ThrowingKeyValueStoring {
    func object(forKey defaultName: String) throws -> Any? {
        return nil
    }

    func set(_ value: Any?, forKey defaultName: String) throws {
    }

    func removeObject(forKey defaultName: String) throws {
    }
}
