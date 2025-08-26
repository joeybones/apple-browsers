//
//  SubscriptionPagesUseSubscriptionFeature.swift
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

import Foundation
import BrowserServicesKit
import Common
import WebKit
import UserScript
import Subscription
import PixelKit
import os.log
import Freemium
import DataBrokerProtection_macOS
import DataBrokerProtectionCore
import Networking

/// Use Subscription sub-feature
final class SubscriptionPagesUseSubscriptionFeature: Subfeature {

    private enum OriginDomains {
        static let duckduckgo = "duckduckgo.com"
    }

    weak var broker: UserScriptMessageBroker?

    let featureName = "useSubscription"
    lazy var messageOriginPolicy: MessageOriginPolicy = .only(rules: [
        HostnameMatchingRule.makeExactRule(for: subscriptionManager.url(for: .baseURL)) ?? .exact(hostname: OriginDomains.duckduckgo)
    ])

    let subscriptionManager: SubscriptionManager
    var accountManager: AccountManager { subscriptionManager.accountManager }
    var subscriptionPlatform: SubscriptionEnvironment.PurchasePlatform { subscriptionManager.currentEnvironment.purchasePlatform }

    let stripePurchaseFlow: StripePurchaseFlow
    let subscriptionErrorReporter = DefaultSubscriptionErrorReporter()
    let subscriptionSuccessPixelHandler: SubscriptionAttributionPixelHandler
    let uiHandler: SubscriptionUIHandling

    let subscriptionFeatureAvailability: SubscriptionFeatureAvailability

    private var freemiumDBPUserStateManager: FreemiumDBPUserStateManager
    private let notificationCenter: NotificationCenter

    /// The `DataBrokerProtectionFreemiumPixelHandler` instance used to fire pixels
    private let dataBrokerProtectionFreemiumPixelHandler: EventMapping<DataBrokerProtectionFreemiumPixels>

    private let featureFlagger: FeatureFlagger

    public init(subscriptionManager: SubscriptionManager,
                subscriptionSuccessPixelHandler: SubscriptionAttributionPixelHandler = PrivacyProSubscriptionAttributionPixelHandler(),
                stripePurchaseFlow: StripePurchaseFlow,
                uiHandler: SubscriptionUIHandling,
                subscriptionFeatureAvailability: SubscriptionFeatureAvailability = DefaultSubscriptionFeatureAvailability(),
                freemiumDBPUserStateManager: FreemiumDBPUserStateManager = DefaultFreemiumDBPUserStateManager(userDefaults: .dbp),
                notificationCenter: NotificationCenter = .default,
                dataBrokerProtectionFreemiumPixelHandler: EventMapping<DataBrokerProtectionFreemiumPixels> = DataBrokerProtectionFreemiumPixelHandler(),
                featureFlagger: FeatureFlagger = NSApp.delegateTyped.featureFlagger) {
        self.subscriptionManager = subscriptionManager
        self.stripePurchaseFlow = stripePurchaseFlow
        self.subscriptionSuccessPixelHandler = subscriptionSuccessPixelHandler
        self.uiHandler = uiHandler
        self.subscriptionFeatureAvailability = subscriptionFeatureAvailability
        self.freemiumDBPUserStateManager = freemiumDBPUserStateManager
        self.notificationCenter = notificationCenter
        self.dataBrokerProtectionFreemiumPixelHandler = dataBrokerProtectionFreemiumPixelHandler
        self.featureFlagger = featureFlagger
    }

    func with(broker: UserScriptMessageBroker) {
        self.broker = broker
    }

    struct Handlers {
        static let getSubscription = "getSubscription"
        static let setSubscription = "setSubscription"
        static let backToSettings = "backToSettings"
        static let getSubscriptionOptions = "getSubscriptionOptions"
        static let subscriptionSelected = "subscriptionSelected"
        static let activateSubscription = "activateSubscription"
        static let featureSelected = "featureSelected"
        static let completeStripePayment = "completeStripePayment"
        // Pixels related events
        static let subscriptionsMonthlyPriceClicked = "subscriptionsMonthlyPriceClicked"
        static let subscriptionsYearlyPriceClicked = "subscriptionsYearlyPriceClicked"
        static let subscriptionsUnknownPriceClicked = "subscriptionsUnknownPriceClicked"
        static let subscriptionsAddEmailSuccess = "subscriptionsAddEmailSuccess"
        static let subscriptionsWelcomeAddEmailClicked = "subscriptionsWelcomeAddEmailClicked"
        static let subscriptionsWelcomeFaqClicked = "subscriptionsWelcomeFaqClicked"
        static let getAccessToken = "getAccessToken"
    }

    func handler(forMethodNamed methodName: String) -> Subfeature.Handler? {
        Logger.subscription.debug("WebView handler: \(methodName)")

        switch methodName {
        case Handlers.getSubscription: return getSubscription
        case Handlers.setSubscription: return setSubscription
        case Handlers.backToSettings: return backToSettings
        case Handlers.getSubscriptionOptions: return getSubscriptionOptions
        case Handlers.subscriptionSelected: return subscriptionSelected
        case Handlers.activateSubscription: return activateSubscription
        case Handlers.featureSelected: return featureSelected
        case Handlers.completeStripePayment: return completeStripePayment
            // Pixel related events
        case Handlers.subscriptionsMonthlyPriceClicked: return subscriptionsMonthlyPriceClicked
        case Handlers.subscriptionsYearlyPriceClicked: return subscriptionsYearlyPriceClicked
        case Handlers.subscriptionsUnknownPriceClicked: return subscriptionsUnknownPriceClicked
        case Handlers.subscriptionsAddEmailSuccess: return subscriptionsAddEmailSuccess
        case Handlers.subscriptionsWelcomeAddEmailClicked: return subscriptionsWelcomeAddEmailClicked
        case Handlers.subscriptionsWelcomeFaqClicked: return subscriptionsWelcomeFaqClicked
        case Handlers.getAccessToken: return getAccessToken
        default:
            Logger.subscription.error("Unknown web message: \(methodName, privacy: .public)")
            return nil
        }
    }

    struct Subscription: Encodable {
        let token: String
    }

    /// Values that the Frontend can use to determine the current state.
    struct SubscriptionValues: Codable {
        enum CodingKeys: String, CodingKey {
            case token
        }
        let token: String
    }

    func getSubscription(params: Any, original: WKScriptMessage) async throws -> Encodable? {
        let authToken = accountManager.authToken ?? ""
        return Subscription(token: authToken)
    }

    func setSubscription(params: Any, original: WKScriptMessage) async throws -> Encodable? {

        PixelKit.fire(PrivacyProPixel.privacyProRestorePurchaseEmailSuccess, frequency: .legacyDailyAndCount)

        guard let subscriptionValues: SubscriptionValues = DecodableHelper.decode(from: params) else {
            assertionFailure("SubscriptionPagesUserScript: expected JSON representation of SubscriptionValues")
            return nil
        }

        let authToken = subscriptionValues.token
        if case let .success(accessToken) = await accountManager.exchangeAuthTokenToAccessToken(authToken),
           case let .success(accountDetails) = await accountManager.fetchAccountDetails(with: accessToken) {
            accountManager.storeAuthToken(token: authToken)
            accountManager.storeAccount(token: accessToken, email: accountDetails.email, externalID: accountDetails.externalID)
        }

        return nil
    }

    func backToSettings(params: Any, original: WKScriptMessage) async throws -> Encodable? {
        if let accessToken = accountManager.accessToken,
           case let .success(accountDetails) = await accountManager.fetchAccountDetails(with: accessToken) {
            accountManager.storeAccount(token: accessToken, email: accountDetails.email, externalID: accountDetails.externalID)
        }

        DispatchQueue.main.async { [weak self] in
            self?.notificationCenter.post(name: .subscriptionPageCloseAndOpenPreferences, object: self)
        }

        return nil
    }

    func getSubscriptionOptions(params: Any, original: WKScriptMessage) async throws -> Encodable? {
        var subscriptionOptions = SubscriptionOptions.empty

        switch subscriptionPlatform {
        case .appStore:
            guard #available(macOS 12.0, *) else { break }

            if featureFlagger.isFeatureOn(.privacyProFreeTrial),
               let freeTrialOptions = await freeTrialSubscriptionOptions() {
                subscriptionOptions = freeTrialOptions
            } else if let appStoreSubscriptionOptions = await subscriptionManager.storePurchaseManager().subscriptionOptions() {
                subscriptionOptions = appStoreSubscriptionOptions
            }
        case .stripe:
            switch await stripePurchaseFlow.subscriptionOptions() {
            case .success(let stripeSubscriptionOptions):
                subscriptionOptions = stripeSubscriptionOptions
            case .failure:
                break
            }
        }

        guard subscriptionFeatureAvailability.isSubscriptionPurchaseAllowed else { return subscriptionOptions.withoutPurchaseOptions() }

        return subscriptionOptions
    }

    func subscriptionSelected(params: Any, original: WKScriptMessage) async throws -> Encodable? {
        PixelKit.fire(PrivacyProPixel.privacyProPurchaseAttempt, frequency: .legacyDailyAndCount)
        struct SubscriptionSelection: Decodable {
            let id: String
        }

        let message = original

        await setPixelOrigin(from: message)

        if subscriptionManager.currentEnvironment.purchasePlatform == .appStore {
            if #available(macOS 12.0, *) {
                guard let subscriptionSelection: SubscriptionSelection = DecodableHelper.decode(from: params) else {
                    assertionFailure("SubscriptionPagesUserScript: expected JSON representation of SubscriptionSelection")
                    subscriptionErrorReporter.report(subscriptionActivationError: .otherPurchaseError)
                    await uiHandler.dismissProgressViewController()
                    return nil
                }

                Logger.subscription.info("[Purchase] Starting purchase for: \(subscriptionSelection.id, privacy: .public)")

                await uiHandler.presentProgressViewController(withTitle: UserText.purchasingSubscriptionTitle)

                // Check for active subscriptions
                if await subscriptionManager.storePurchaseManager().hasActiveSubscription() {
                    PixelKit.fire(PrivacyProPixel.privacyProRestoreAfterPurchaseAttempt)
                    Logger.subscription.info("[Purchase] Found active subscription during purchase")
                    subscriptionErrorReporter.report(subscriptionActivationError: .activeSubscriptionAlreadyPresent)
                    await showSubscriptionFoundAlert(originalMessage: message)
                    await pushPurchaseUpdate(originalMessage: message, purchaseUpdate: PurchaseUpdate(type: "canceled"))
                    return nil
                }

                let emailAccessToken = try? EmailManager().getToken()
                let purchaseTransactionJWS: String
                let appStoreRestoreFlow = DefaultAppStoreRestoreFlow(accountManager: subscriptionManager.accountManager,
                                                                     storePurchaseManager: subscriptionManager.storePurchaseManager(),
                                                                     subscriptionEndpointService: subscriptionManager.subscriptionEndpointService,
                                                                     authEndpointService: subscriptionManager.authEndpointService)
                let appStorePurchaseFlow = DefaultAppStorePurchaseFlow(subscriptionEndpointService: subscriptionManager.subscriptionEndpointService,
                                                                       storePurchaseManager: subscriptionManager.storePurchaseManager(),
                                                                       accountManager: subscriptionManager.accountManager,
                                                                       appStoreRestoreFlow: appStoreRestoreFlow,
                                                                       authEndpointService: subscriptionManager.authEndpointService)

                Logger.subscription.info("[Purchase] Purchasing")
                switch await appStorePurchaseFlow.purchaseSubscription(with: subscriptionSelection.id, emailAccessToken: emailAccessToken) {
                case .success(let transactionJWS):
                    purchaseTransactionJWS = transactionJWS
                case .failure(let error):
                    switch error {
                    case .noProductsFound:
                        subscriptionErrorReporter.report(subscriptionActivationError: .failedToGetSubscriptionOptions)
                    case .activeSubscriptionAlreadyPresent:
                        subscriptionErrorReporter.report(subscriptionActivationError: .activeSubscriptionAlreadyPresent)
                    case .authenticatingWithTransactionFailed:
                        subscriptionErrorReporter.report(subscriptionActivationError: .otherPurchaseError)
                    case .accountCreationFailed(let creationError):
                        subscriptionErrorReporter.report(subscriptionActivationError: .accountCreationFailed(creationError))
                    case .purchaseFailed(let purchaseError):
                        subscriptionErrorReporter.report(subscriptionActivationError: .purchaseFailed(purchaseError))
                    case .cancelledByUser:
                        subscriptionErrorReporter.report(subscriptionActivationError: .cancelledByUser)
                    case .missingEntitlements:
                        subscriptionErrorReporter.report(subscriptionActivationError: .missingEntitlements)
                    case .internalError:
                        assertionFailure("Internal error")
                    }

                    if error != .cancelledByUser {
                        await showSomethingWentWrongAlert()
                    } else {
                        await uiHandler.dismissProgressViewController()
                    }
                    await pushPurchaseUpdate(originalMessage: message, purchaseUpdate: PurchaseUpdate(type: "canceled"))
                    return nil
                }

                await uiHandler.updateProgressViewController(title: UserText.completingPurchaseTitle)

                Logger.subscription.info("[Purchase] Completing purchase")
                let completePurchaseResult = await appStorePurchaseFlow.completeSubscriptionPurchase(with: purchaseTransactionJWS)
                switch completePurchaseResult {
                case .success(let purchaseUpdate):
                    Logger.subscription.info("[Purchase] Purchase complete")
                    PixelKit.fire(PrivacyProPixel.privacyProPurchaseSuccess, frequency: .legacyDailyAndCount)
                    sendFreemiumSubscriptionPixelIfFreemiumActivated()
                    saveSubscriptionUpgradeTimestampIfFreemiumActivated()
                    PixelKit.fire(PrivacyProPixel.privacyProSubscriptionActivated, frequency: .uniqueByName)
                    subscriptionSuccessPixelHandler.fireSuccessfulSubscriptionAttributionPixel()
                    sendSubscriptionUpgradeFromFreemiumNotificationIfFreemiumActivated()
                    await pushPurchaseUpdate(originalMessage: message, purchaseUpdate: purchaseUpdate)
                case .failure(let error):
                    switch error {
                    case .noProductsFound:
                        subscriptionErrorReporter.report(subscriptionActivationError: .failedToGetSubscriptionOptions)
                    case .activeSubscriptionAlreadyPresent:
                        subscriptionErrorReporter.report(subscriptionActivationError: .activeSubscriptionAlreadyPresent)
                    case .authenticatingWithTransactionFailed:
                        subscriptionErrorReporter.report(subscriptionActivationError: .otherPurchaseError)
                    case .accountCreationFailed(let creationError):
                        subscriptionErrorReporter.report(subscriptionActivationError: .accountCreationFailed(creationError))
                    case .purchaseFailed(let purchaseError):
                        subscriptionErrorReporter.report(subscriptionActivationError: .purchaseFailed(purchaseError))
                    case .cancelledByUser:
                        subscriptionErrorReporter.report(subscriptionActivationError: .cancelledByUser)
                    case .missingEntitlements:
                        subscriptionErrorReporter.report(subscriptionActivationError: .missingEntitlements)
                        DispatchQueue.main.async { [weak self] in
                            self?.notificationCenter.post(name: .subscriptionPageCloseAndOpenPreferences, object: self)
                        }
                        await uiHandler.dismissProgressViewController()
                        return nil
                    case .internalError:
                        assertionFailure("Internal error")
                    }

                    await pushPurchaseUpdate(originalMessage: message, purchaseUpdate: PurchaseUpdate(type: "completed"))
                }
            }
        } else if subscriptionPlatform == .stripe {
            let emailAccessToken = try? EmailManager().getToken()
            let result = await stripePurchaseFlow.prepareSubscriptionPurchase(emailAccessToken: emailAccessToken)
            switch result {
            case .success(let success):
                await pushPurchaseUpdate(originalMessage: message, purchaseUpdate: success)
            case .failure(let error):
                await showSomethingWentWrongAlert()
                switch error {
                case .noProductsFound:
                    subscriptionErrorReporter.report(subscriptionActivationError: .failedToGetSubscriptionOptions)
                case .accountCreationFailed(let creationError):
                    subscriptionErrorReporter.report(subscriptionActivationError: .accountCreationFailed(creationError))
                }
                await pushPurchaseUpdate(originalMessage: message, purchaseUpdate: PurchaseUpdate(type: "canceled"))
            }
        }

        await uiHandler.dismissProgressViewController()
        return nil
    }

    // MARK: functions used in SubscriptionAccessActionHandlers

    func activateSubscription(params: Any, original: WKScriptMessage) async throws -> Encodable? {
        PixelKit.fire(PrivacyProPixel.privacyProRestorePurchaseOfferPageEntry)
        Task { @MainActor in
            uiHandler.presentSubscriptionAccessViewController(handler: self, message: original)
        }
        return nil
    }

    func featureSelected(params: Any, original: WKScriptMessage) async throws -> Encodable? {
        struct FeatureSelection: Codable {
            let productFeature: Entitlement.ProductName
        }

        guard let featureSelection: FeatureSelection = DecodableHelper.decode(from: params) else {
            assertionFailure("SubscriptionPagesUserScript: expected JSON representation of FeatureSelection")
            return nil
        }

        switch featureSelection.productFeature {
        case .networkProtection:
            PixelKit.fire(PrivacyProPixel.privacyProWelcomeVPN, frequency: .uniqueByName)
            notificationCenter.post(name: .ToggleNetworkProtectionInMainWindow, object: self, userInfo: nil)
        case .dataBrokerProtection:
            PixelKit.fire(PrivacyProPixel.privacyProWelcomePersonalInformationRemoval, frequency: .uniqueByName)
            notificationCenter.post(name: .openPersonalInformationRemoval, object: self, userInfo: nil)
            await uiHandler.showTab(with: .dataBrokerProtection)
        case .identityTheftRestoration, .identityTheftRestorationGlobal:
            PixelKit.fire(PrivacyProPixel.privacyProWelcomeIdentityRestoration, frequency: .uniqueByName)
            let url = subscriptionManager.url(for: .identityTheftRestoration)
            await uiHandler.showTab(with: .identityTheftRestoration(url))
        case .paidAIChat:
            break
        case .unknown:
            break
        }

        return nil
    }

    func completeStripePayment(params: Any, original: WKScriptMessage) async throws -> Encodable? {
        await uiHandler.presentProgressViewController(withTitle: UserText.completingPurchaseTitle)
        await stripePurchaseFlow.completeSubscriptionPurchase()
        await uiHandler.dismissProgressViewController()

        PixelKit.fire(PrivacyProPixel.privacyProPurchaseStripeSuccess, frequency: .legacyDailyAndCount)
        sendFreemiumSubscriptionPixelIfFreemiumActivated()
        saveSubscriptionUpgradeTimestampIfFreemiumActivated()
        subscriptionSuccessPixelHandler.fireSuccessfulSubscriptionAttributionPixel()
        sendSubscriptionUpgradeFromFreemiumNotificationIfFreemiumActivated()
        return [String: String]() // cannot be nil, the web app expect something back before redirecting the user to the final page
    }

    // MARK: Pixel related actions

    func subscriptionsMonthlyPriceClicked(params: Any, original: WKScriptMessage) async -> Encodable? {
        PixelKit.fire(PrivacyProPixel.privacyProOfferMonthlyPriceClick)
        return nil
    }

    func subscriptionsYearlyPriceClicked(params: Any, original: WKScriptMessage) async -> Encodable? {
        PixelKit.fire(PrivacyProPixel.privacyProOfferYearlyPriceClick)
        return nil
    }

    func subscriptionsUnknownPriceClicked(params: Any, original: WKScriptMessage) async -> Encodable? {
        // Not used
        return nil
    }

    func subscriptionsAddEmailSuccess(params: Any, original: WKScriptMessage) async -> Encodable? {
        PixelKit.fire(PrivacyProPixel.privacyProAddEmailSuccess, frequency: .uniqueByName)
        return nil
    }

    func subscriptionsWelcomeAddEmailClicked(params: Any, original: WKScriptMessage) async -> Encodable? {
        PixelKit.fire(PrivacyProPixel.privacyProWelcomeAddDevice, frequency: .uniqueByName)
        return nil
    }

    func subscriptionsWelcomeFaqClicked(params: Any, original: WKScriptMessage) async -> Encodable? {
        PixelKit.fire(PrivacyProPixel.privacyProWelcomeFAQClick, frequency: .uniqueByName)
        return nil
    }

    func getAccessToken(params: Any, original: WKScriptMessage) async throws -> Encodable? {
        if let accessToken = accountManager.accessToken {
            return ["token": accessToken]
        } else {
            return [String: String]()
        }
    }

    // MARK: Push actions

    enum SubscribeActionName: String {
        case onPurchaseUpdate
    }

    @MainActor
    func pushPurchaseUpdate(originalMessage: WKScriptMessage, purchaseUpdate: PurchaseUpdate) {
        pushAction(method: .onPurchaseUpdate, webView: originalMessage.webView!, params: purchaseUpdate)
    }

    func pushAction(method: SubscribeActionName, webView: WKWebView, params: Encodable) {
        guard let broker else {
            assertionFailure("Cannot continue without broker instance")
            return
        }

        broker.push(method: method.rawValue, params: params, for: self, into: webView)
    }

    @MainActor
    private func originFrom(originalMessage: WKScriptMessage) -> String? {
        let url = originalMessage.webView?.url
        return url?.getParameter(named: AttributionParameter.origin)
    }

    // MARK: - UI interactions

    func showSomethingWentWrongAlert() async {
        switch await uiHandler.dismissProgressViewAndShow(alertType: .somethingWentWrong, text: nil) {
        case .alertFirstButtonReturn:
            let url = subscriptionManager.url(for: .purchase)
            await uiHandler.showTab(with: .subscription(url))
            PixelKit.fire(PrivacyProPixel.privacyProOfferScreenImpression)
        default: return
        }
    }

    func showSubscriptionFoundAlert(originalMessage: WKScriptMessage) async {

        switch await uiHandler.dismissProgressViewAndShow(alertType: .subscriptionFound, text: nil) {
        case .alertFirstButtonReturn:
            if #available(macOS 12.0, *) {
                let appStoreRestoreFlow = DefaultAppStoreRestoreFlow(accountManager: subscriptionManager.accountManager,
                                                                     storePurchaseManager: subscriptionManager.storePurchaseManager(),
                                                                     subscriptionEndpointService: subscriptionManager.subscriptionEndpointService,
                                                                     authEndpointService: subscriptionManager.authEndpointService)
                let result = await appStoreRestoreFlow.restoreAccountFromPastPurchase()
                switch result {
                case .success: PixelKit.fire(PrivacyProPixel.privacyProRestorePurchaseStoreSuccess, frequency: .legacyDailyAndCount)
                case .failure: break
                }
                Task { @MainActor in
                    originalMessage.webView?.reload()
                }
            }
        default: return
        }
    }

    // MARK: - Attribution
    /// Sets the appropriate origin for the subscription success tracking pixel.
    ///
    /// - Note: This method is asynchronous when extracting the origin from the webview URL.
    private func setPixelOrigin(from message: WKScriptMessage) async {
        // Extract the origin from the webview URL to use for attribution pixel.
        subscriptionSuccessPixelHandler.origin = await originFrom(originalMessage: message)
    }
}

/// For handling subscription access actions when presented as modal VC on purchase page via "I Have a Subscription" link
extension SubscriptionPagesUseSubscriptionFeature: SubscriptionAccessActionHandling {

    func subscriptionAccessActionRestorePurchases(message: WKScriptMessage) {
        if #available(macOS 12.0, *) {
            Task { @MainActor in
                let appStoreRestoreFlow = DefaultAppStoreRestoreFlow(accountManager: subscriptionManager.accountManager,
                                                                     storePurchaseManager: subscriptionManager.storePurchaseManager(),
                                                                     subscriptionEndpointService: subscriptionManager.subscriptionEndpointService,
                                                                     authEndpointService: subscriptionManager.authEndpointService)
                let subscriptionAppStoreRestorer = DefaultSubscriptionAppStoreRestorer(subscriptionManager: self.subscriptionManager,
                                                                                       appStoreRestoreFlow: appStoreRestoreFlow,
                                                                                       uiHandler: self.uiHandler)
                await subscriptionAppStoreRestorer.restoreAppStoreSubscription()
                message.webView?.reload()
            }
        }
    }

    func subscriptionAccessActionOpenURLHandler(url: URL) {
        Task {
            await self.uiHandler.showTab(with: .subscription(url))
        }
    }
}

private extension SubscriptionPagesUseSubscriptionFeature {

    /**
     Sends a subscription upgrade notification if the freemium state is activated.

     This function checks if the freemium state has been activated by verifying the
     `didActivate` property in `freemiumDBPUserStateManager`. If the freemium activation
     is detected, it posts a `subscriptionUpgradeFromFreemium` notification via
     `notificationCenter`.

     - Important: The notification will only be posted if `didActivate` is `true`.
     */
    func sendSubscriptionUpgradeFromFreemiumNotificationIfFreemiumActivated() {
        if freemiumDBPUserStateManager.didActivate {
            notificationCenter.post(name: .subscriptionUpgradeFromFreemium, object: nil)
        }
    }

    /// Sends a freemium subscription pixel event if the freemium feature has been activated.
    ///
    /// This function checks whether the user has activated the freemium feature by querying the `freemiumDBPUserStateManager`.
    /// If the feature is activated (`didActivate` returns `true`), it fires a unique subscription-related pixel event using `PixelKit`.
    func sendFreemiumSubscriptionPixelIfFreemiumActivated() {
        if freemiumDBPUserStateManager.didActivate {
            dataBrokerProtectionFreemiumPixelHandler.fire(DataBrokerProtectionFreemiumPixels.subscription)
        }
    }

    /// Saves the current timestamp for a subscription upgrade if the freemium feature has been activated.
    ///
    /// This function checks whether the user has activated the freemium feature and if the subscription upgrade timestamp
    /// has not already been set. If the user has activated the freemium feature and no upgrade timestamp exists, it assigns
    /// the current date and time to `freemiumDBPUserStateManager.upgradeToSubscriptionTimestamp`.
    func saveSubscriptionUpgradeTimestampIfFreemiumActivated() {
        if freemiumDBPUserStateManager.didActivate && freemiumDBPUserStateManager.upgradeToSubscriptionTimestamp == nil {
            freemiumDBPUserStateManager.upgradeToSubscriptionTimestamp = Date()
        }
    }

    /// Retrieves free trial subscription options for App Store.
    ///
    /// - Returns: A `SubscriptionOptions` object containing the relevant subscription options, or nil if unavailable.
    ///   If free trial options are unavailable, falls back to standard subscription options.
    ///   This fallback could occur if the Free Trial offer in AppStoreConnect had an end date in the past.
    @available(macOS 12.0, *)
    func freeTrialSubscriptionOptions() async -> SubscriptionOptions? {
        guard let options = await subscriptionManager.storePurchaseManager().freeTrialSubscriptionOptions() else {
            return await subscriptionManager.storePurchaseManager().subscriptionOptions()
        }
        return options
    }
}
