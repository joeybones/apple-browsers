//
//  DataBrokerProtectionManager.swift
//
//  Copyright © 2023 DuckDuckGo. All rights reserved.
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

import Foundation
import BrowserServicesKit
import DataBrokerProtection_macOS
import DataBrokerProtectionCore
import PixelKit
import LoginItems
import Common
import Freemium
import NetworkProtectionIPC
import Subscription

public final class DataBrokerProtectionManager {

    static let shared = DataBrokerProtectionManager()

    private let pixelHandler: EventMapping<DataBrokerProtectionMacOSPixels> = DataBrokerProtectionMacOSPixelsHandler()
    private let authenticationManager: DataBrokerProtectionAuthenticationManaging
    private let fakeBrokerFlag: DataBrokerDebugFlag = DataBrokerDebugFlagFakeBroker()
    private let vpnBypassService: VPNBypassFeatureProvider

    private lazy var freemiumDBPFirstProfileSavedNotifier: FreemiumDBPFirstProfileSavedNotifier = {
        let freemiumDBPUserStateManager = DefaultFreemiumDBPUserStateManager(userDefaults: .dbp)
        let freemiumDBPFirstProfileSavedNotifier = FreemiumDBPFirstProfileSavedNotifier(freemiumDBPUserStateManager: freemiumDBPUserStateManager,
                                                                                        authenticationStateProvider: Application.appDelegate.subscriptionAuthV1toV2Bridge)
        return freemiumDBPFirstProfileSavedNotifier
    }()

    private lazy var sharedPixelsHandler: EventMapping<DataBrokerProtectionSharedPixels>? = {
        guard let pixelKit = PixelKit.shared else {
            assertionFailure("PixelKit not set up")
            return nil
        }
        let sharedPixelsHandler = DataBrokerProtectionSharedPixelsHandler(pixelKit: pixelKit, platform: .macOS)
        return sharedPixelsHandler
    }()

    private lazy var vault: (any DataBrokerProtectionSecureVault)? = {
        guard let sharedPixelsHandler else { return nil }

        let databaseURL = DefaultDataBrokerProtectionDatabaseProvider.databaseFilePath(directoryName: DatabaseConstants.directoryName, fileName: DatabaseConstants.fileName, appGroupIdentifier: Bundle.main.appGroupName)
        let vaultFactory = createDataBrokerProtectionSecureVaultFactory(appGroupName: Bundle.main.appGroupName, databaseFileURL: databaseURL)
        let privacyConfigManager = Application.appDelegate.privacyFeatures.contentBlocking.privacyConfigurationManager
        let reporter = DataBrokerProtectionSecureVaultErrorReporter(pixelHandler: sharedPixelsHandler, privacyConfigManager: privacyConfigManager)

        let vault: DefaultDataBrokerProtectionSecureVault<DefaultDataBrokerProtectionDatabaseProvider>
        do {
            vault = try vaultFactory.makeVault(reporter: reporter)
        } catch let error {
            pixelHandler.fire(.mainAppSetUpFailedSecureVaultInitFailed(error: error))
            return nil
        }

        return vault
    }()

    lazy var dataManager: DataBrokerProtectionDataManager? = {
        guard let vault, let sharedPixelsHandler, let brokerUpdater else { return nil }

        let fakeBroker = DataBrokerDebugFlagFakeBroker()
        let database = DataBrokerProtectionDatabase(fakeBrokerFlag: fakeBroker,
                                                    pixelHandler: sharedPixelsHandler,
                                                    vault: vault,
                                                    localBrokerService: brokerUpdater)
        let dataManager = DataBrokerProtectionDataManager(database: database,
                                                          profileSavedNotifier: freemiumDBPFirstProfileSavedNotifier)

        dataManager.delegate = self
        return dataManager
    }()

    lazy var brokerUpdater: BrokerJSONServiceProvider? = {
        guard let vault, let sharedPixelsHandler else { return nil }

        let featureFlagger = DBPFeatureFlagger(featureFlagger: Application.appDelegate.featureFlagger)
        let localBrokerService = LocalBrokerJSONService(vault: vault, pixelHandler: sharedPixelsHandler)
        let brokerUpdater = RemoteBrokerJSONService(featureFlagger: featureFlagger,
                                                    settings: DataBrokerProtectionSettings(defaults: .dbp),
                                                    vault: vault,
                                                    authenticationManager: authenticationManager,
                                                    pixelHandler: sharedPixelsHandler,
                                                    localBrokerProvider: localBrokerService)
        return brokerUpdater
    }()

    private lazy var ipcClient: DataBrokerProtectionIPCClient = {
        let loginItemStatusChecker = LoginItem.dbpBackgroundAgent
        return DataBrokerProtectionIPCClient(machServiceName: Bundle.main.dbpBackgroundAgentBundleId,
                                             pixelHandler: pixelHandler,
                                             loginItemStatusChecker: loginItemStatusChecker)
    }()

    lazy var loginItemInterface: DataBrokerProtectionLoginItemInterface = {
        return DefaultDataBrokerProtectionLoginItemInterface(ipcClient: ipcClient, pixelHandler: pixelHandler)
    }()

    private init() {
        self.authenticationManager = DataBrokerAuthenticationManagerBuilder.buildAuthenticationManager(
            subscriptionManager: Application.appDelegate.subscriptionAuthV1toV2Bridge)
        self.vpnBypassService = VPNBypassService()
    }

    public func isUserAuthenticated() -> Bool {
        authenticationManager.isUserAuthenticated
    }

    // MARK: - Debugging Features

    public func showAgentIPAddress() {
        ipcClient.openBrowser(domain: "https://www.whatismyip.com")
    }
}

extension DataBrokerProtectionManager: DataBrokerProtectionDataManagerDelegate {

    public func dataBrokerProtectionDataManagerDidUpdateData() {
        loginItemInterface.profileSaved()
    }

    public func dataBrokerProtectionDataManagerDidDeleteData() {
        DataBrokerProtectionSettings(defaults: .dbp).resetBrokerDeliveryData()
        loginItemInterface.dataDeleted()
    }

    public func dataBrokerProtectionDataManagerWillOpenSendFeedbackForm() {
        NotificationCenter.default.post(name: .OpenUnifiedFeedbackForm, object: nil, userInfo: UnifiedFeedbackSource.userInfo(source: .pir))
    }

    public func dataBrokerProtectionDataManagerWillApplyVPNBypassSetting(_ bypass: Bool) async {
        vpnBypassService.applyVPNBypass(bypass)
        try? await Task.sleep(interval: 0.1)
        try? await VPNControllerXPCClient.shared.command(.restartAdapter)
    }

    public func isAuthenticatedUser() -> Bool {
        isUserAuthenticated()
    }

    /// Returns whether the current user is eligible for a free trial of Data Broker Protection
    /// - Returns: `true` if the user is eligible for a free trial, `false` otherwise
    public func isUserEligibleForFreeTrial() -> Bool {
        authenticationManager.isUserEligibleForFreeTrial
    }
}
