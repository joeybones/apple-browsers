//
//  SettingsState.swift
//  DuckDuckGo
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

import BrowserServicesKit
import Subscription

struct SettingsState {
    
    enum SubscriptionStatus {
        case active, inactive, unknown
    }
    
    struct AddressBar {
        var enabled: Bool
        var position: AddressBarPosition
    }
    
    struct TextZoom {
        var enabled: Bool
        var level: TextZoomLevel
    }

    struct Subscription: Codable {
        var canPurchase: Bool
        var isSignedIn: Bool
        var hasSubscription: Bool
        var hasActiveSubscription: Bool
        var isRestoring: Bool
        var shouldDisplayRestoreSubscriptionError: Bool
        var subscriptionFeatures: [Entitlement.ProductName]
        var entitlements: [Entitlement.ProductName]
        var platform: PrivacyProSubscription.Platform
        var isShowingStripeView: Bool
        var isActiveTrialOffer: Bool
        /// Whether the user is eligible for a free trial subscription offer
        var isEligibleForTrialOffer: Bool
    }

    struct SyncSettings {
        var enabled: Bool
        var title: String
    }
    
    // Appearance properties
    var appThemeStyle: ThemeStyle
    var appIcon: AppIcon
    var fireButtonAnimation: FireButtonAnimationType
    var textZoom: TextZoom
    var addressBar: AddressBar
    var showsFullURL: Bool
    var isExperimentalAIChatEnabled: Bool

    // Privacy properties
    var sendDoNotSell: Bool
    var autoconsentEnabled: Bool
    var autoclearDataEnabled: Bool
    var applicationLock: Bool

    // Customization properties
    var autocomplete: Bool
    var recentlyVisitedSites: Bool
    var longPressPreviews: Bool
    var allowUniversalLinks: Bool

    // Logins properties
    var activeWebsiteAccount: SecureVaultModels.WebsiteAccount?
    var activeWebsiteCreditCard: SecureVaultModels.CreditCard?
    var autofillSource: AutofillSettingsSource?
    var showCreditCardManagement: Bool

    // About properties
    var version: String
    var crashCollectionOptInStatus: CrashCollectionOptInStatus

    // Features
    var debugModeEnabled: Bool
    var voiceSearchEnabled: Bool
    var speechRecognitionAvailable: Bool // Returns if the device has speech recognition available
    var loginsEnabled: Bool
    
    // Network Protection properties
    var networkProtectionConnected: Bool

    // Subscriptions Properties
    var subscription: Subscription
    
    // Sync Properties
    var sync: SyncSettings
    var syncSource: String?

    // Duck Player Mode
    var duckPlayerEnabled: Bool
    var duckPlayerMode: DuckPlayerMode?
    var duckPlayerOpenInNewTab: Bool
    var duckPlayerOpenInNewTabEnabled: Bool
    
    // Duck Player Native UI    
    var duckPlayerAutoplay: Bool
    var duckPlayerNativeUISERPEnabled: Bool
    var duckPlayerNativeYoutubeMode: NativeDuckPlayerYoutubeMode

    static var defaults: SettingsState {
        return SettingsState(
            appThemeStyle: .systemDefault,
            appIcon: AppIconManager.shared.appIcon,
            fireButtonAnimation: .fireRising,
            textZoom: TextZoom(enabled: false, level: .percent100),
            addressBar: AddressBar(enabled: false, position: .top),
            showsFullURL: false,
            isExperimentalAIChatEnabled: false,
            sendDoNotSell: true,
            autoconsentEnabled: false,
            autoclearDataEnabled: false,
            applicationLock: false,
            autocomplete: true,
            recentlyVisitedSites: true,
            longPressPreviews: true,
            allowUniversalLinks: true,
            activeWebsiteAccount: nil,
            activeWebsiteCreditCard: nil,
            autofillSource: nil,
            showCreditCardManagement: false,
            version: "0.0.0.0",
            crashCollectionOptInStatus: .undetermined,
            debugModeEnabled: false,
            voiceSearchEnabled: false,
            speechRecognitionAvailable: false,
            loginsEnabled: false,
            networkProtectionConnected: false,
            subscription: Subscription(canPurchase: false,
                                       isSignedIn: false,
                                       hasSubscription: false,
                                       hasActiveSubscription: false,
                                       isRestoring: false,
                                       shouldDisplayRestoreSubscriptionError: false,
                                       subscriptionFeatures: [],
                                       entitlements: [],
                                       platform: .unknown,
                                       isShowingStripeView: false,
                                       isActiveTrialOffer: false,
                                       isEligibleForTrialOffer: false),
            sync: SyncSettings(enabled: false, title: ""),
            syncSource: nil,
            duckPlayerEnabled: false,
            duckPlayerMode: .alwaysAsk,
            duckPlayerOpenInNewTab: true,
            duckPlayerOpenInNewTabEnabled: false,
            duckPlayerAutoplay: true,
            duckPlayerNativeUISERPEnabled: true,
            duckPlayerNativeYoutubeMode: .ask
        )
    }
}
