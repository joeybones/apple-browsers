//
//  SubscriptionUserScript.swift
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

import Common
import UserScript
import WebKit
import Combine

///
/// This protocol describes the interface for `SubscriptionUserScript` message handler
///
protocol SubscriptionUserScriptHandling {
    typealias DataModel = SubscriptionUserScript.DataModel

    /// Returns a handshake message reporting capabilities of the app.
    func handshake(params: Any, message: UserScriptMessage) async throws -> DataModel.HandshakeResponse

    /// Returns the details of Privacy Pro subscription.
    func subscriptionDetails(params: Any, message: UserScriptMessage) async throws -> DataModel.SubscriptionDetails

    // Returns the AuthToken of the subscription.
    func getAuthAccessToken(params: Any, message: any UserScriptMessage) async throws -> DataModel.GetAuthAccessTokenResponse

    // Returns the feature configuration for the Subscription.
    func getFeatureConfig(params: Any, message: any UserScriptMessage) async throws -> DataModel.GetFeatureConfigurationResponse

    // Notification message, Subscription Settings should be open
    func backToSettings(params: Any, message: any UserScriptMessage) async throws -> Encodable?

    // Notification message, Subscription activation flow should be open
    func openSubscriptionActivation(params: Any, message: any UserScriptMessage) async throws -> Encodable?

    // Notification message, Subscription purchase flow should be open
    func openSubscriptionPurchase(params: Any, message: any UserScriptMessage) async throws -> Encodable?

    func setBroker(_ broker: UserScriptMessagePushing)
    func setWebView(_ webView: WKWebView?)
    func setUserScript(_ userScript: SubscriptionUserScript)
}

///
/// Navigation delegate for handling platform-specific navigation
///
public protocol SubscriptionUserScriptNavigationDelegate: AnyObject {
    @MainActor func navigateToSettings()
    @MainActor func navigateToSubscriptionActivation()
    @MainActor func navigateToSubscriptionPurchase(origin: String?, featurePage: String?)
}

protocol UserScriptMessagePushing: AnyObject {
    func push(method: String, params: Encodable?, for delegate: Subfeature, into webView: WKWebView)
}

extension UserScriptMessageBroker: UserScriptMessagePushing {}

final class SubscriptionUserScriptHandler: SubscriptionUserScriptHandling {
    typealias DataModel = SubscriptionUserScript.DataModel

    let platform: DataModel.Platform
    let subscriptionManager: any SubscriptionAuthV1toV2Bridge
    private var paidAIChatFlagStatusProvider: () -> Bool
    weak var navigationDelegate: SubscriptionUserScriptNavigationDelegate?
    weak private var webView: WKWebView?
    weak private var broker: UserScriptMessagePushing?
    private weak var userScript: SubscriptionUserScript?
    private var cancellables = Set<AnyCancellable>()

    init(platform: DataModel.Platform,
         subscriptionManager: any SubscriptionAuthV1toV2Bridge,
         paidAIChatFlagStatusProvider: @escaping () -> Bool,
         navigationDelegate: SubscriptionUserScriptNavigationDelegate?) {
        self.platform = platform
        self.subscriptionManager = subscriptionManager
        self.paidAIChatFlagStatusProvider = paidAIChatFlagStatusProvider
        self.navigationDelegate = navigationDelegate

        setupSubscriptionEventObservers()
    }

    func setBroker(_ broker: UserScriptMessagePushing) {
        self.broker = broker
    }

    func setWebView(_ webView: WKWebView?) {
        self.webView = webView
    }

    func setUserScript(_ userScript: SubscriptionUserScript) {
        self.userScript = userScript
    }

    func handshake(params: Any, message: any UserScriptMessage) async throws -> DataModel.HandshakeResponse {
        return .init(availableMessages: [.subscriptionDetails, .getAuthAccessToken, .getFeatureConfig, .backToSettings, .openSubscriptionActivation, .openSubscriptionPurchase, .authUpdate], platform: platform)
    }

    func subscriptionDetails(params: Any, message: any UserScriptMessage) async throws -> DataModel.SubscriptionDetails {
        guard let subscription = try? await subscriptionManager.getSubscription(cachePolicy: .cacheFirst) else {
            return .notSubscribed
        }
        return .init(subscription)
    }

    func getAuthAccessToken(params: Any, message: any UserScriptMessage) async throws -> DataModel.GetAuthAccessTokenResponse {
        guard let accessToken = try? await subscriptionManager.getAccessToken() else { return .init(accessToken: "") }
        return .init(accessToken: accessToken)
    }

    @MainActor
    func getFeatureConfig(params: Any, message: any UserScriptMessage) async throws -> DataModel.GetFeatureConfigurationResponse {
        return .init(usePaidDuckAi: paidAIChatFlagStatusProvider())
    }

    @MainActor
    func backToSettings(params: Any, message: any UserScriptMessage) async throws -> Encodable? {
        navigationDelegate?.navigateToSettings()
        return nil
    }

    @MainActor
    func openSubscriptionActivation(params: Any, message: any UserScriptMessage) async throws -> Encodable? {
        navigationDelegate?.navigateToSubscriptionActivation()
        return nil
    }

    @MainActor
    func openSubscriptionPurchase(params: Any, message: any UserScriptMessage) async throws -> Encodable? {
        struct PurchaseParams: Decodable {
            let origin: String?
        }

        let purchaseParams: PurchaseParams? = {
            if let paramsDict = params as? [String: Any] {
                if let jsonData = try? JSONSerialization.data(withJSONObject: paramsDict, options: []) {
                    return try? JSONDecoder().decode(PurchaseParams.self, from: jsonData)
                }
            }
            return nil
        }()

        navigationDelegate?.navigateToSubscriptionPurchase(origin: purchaseParams?.origin, featurePage: "duckai")
        return nil
    }

    private func handleSubscriptionChanged() {
        guard let webView, let userScript else { return }
        broker?.push(method: SubscriptionUserScript.MessageName.authUpdate.rawValue, params: nil, for: userScript, into: webView)
    }

    private func setupSubscriptionEventObservers() {
        NotificationCenter.default.publisher(for: .subscriptionDidChange)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.handleSubscriptionChanged()
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: .accountDidSignIn)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.handleSubscriptionChanged()
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: .accountDidSignOut)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.handleSubscriptionChanged()
            }
            .store(in: &cancellables)
    }

}

///
/// This user script is responsible for providing Privacy Pro subscription data to the calling website.
///
public final class SubscriptionUserScript: NSObject, Subfeature {

    private let defaultOriginDomain = "duckduckgo.com"

    public enum MessageName: String, CaseIterable, Codable {
        case handshake
        case subscriptionDetails
        case getAuthAccessToken
        case getFeatureConfig
        case backToSettings
        case openSubscriptionActivation
        case openSubscriptionPurchase
        case authUpdate
    }

    public let featureName: String = "subscriptions"
    public var messageOriginPolicy: MessageOriginPolicy {
        var rules: [HostnameMatchingRule] = [.exact(hostname: defaultOriginDomain)]
        if let debugHost {
            rules.append(.exact(hostname: debugHost))
        }
        return .only(rules: rules)
    }
    weak public var broker: UserScriptMessageBroker?
    public weak var webView: WKWebView? {
        didSet {
            handler.setWebView(webView)
        }
    }

    public func with(broker: UserScriptMessageBroker) {
        self.broker = broker
        handler.setBroker(broker)
        handler.setUserScript(self)
    }

    public func handler(forMethodNamed methodName: String) -> Subfeature.Handler? {
        switch MessageName(rawValue: methodName) {
        case .handshake:
            return handler.handshake
        case .subscriptionDetails:
            return handler.subscriptionDetails
        case .getAuthAccessToken:
            return handler.getAuthAccessToken
        case .getFeatureConfig:
            return handler.getFeatureConfig
        case .backToSettings:
            return handler.backToSettings
        case .openSubscriptionActivation:
            return handler.openSubscriptionActivation
        case .openSubscriptionPurchase:
            return handler.openSubscriptionPurchase
        default:
            return nil
        }
    }

    private let debugHost: String?

    public convenience init(platform: DataModel.Platform,
                            subscriptionManager: any SubscriptionAuthV1toV2Bridge,
                            paidAIChatFlagStatusProvider: @escaping () -> Bool,
                            navigationDelegate: SubscriptionUserScriptNavigationDelegate?,
                            debugHost: String?) {
        self.init(handler: SubscriptionUserScriptHandler(platform: platform,
                                                         subscriptionManager: subscriptionManager,
                                                         paidAIChatFlagStatusProvider: paidAIChatFlagStatusProvider,
                                                         navigationDelegate: navigationDelegate),
                  debugHost: debugHost)
    }

    init(handler: SubscriptionUserScriptHandling, debugHost: String?) {
        self.handler = handler
        self.debugHost = debugHost
        super.init()
    }

    let handler: SubscriptionUserScriptHandling

}

extension SubscriptionUserScript {
    public enum DataModel {

        /// Describes the platform to be reported to the user script.
        /// This needs to be public as it's provided by the client app.
        public enum Platform: String, Codable {
            case ios, macos
        }

        /// This struct is returned in response to the `handshake` message
        struct HandshakeResponse: Codable, Equatable {
            let availableMessages: [SubscriptionUserScript.MessageName]
            let platform: Platform
        }

        /// This struct is returned in response to the `subscriptionDetails` message
        struct SubscriptionDetails: Codable, Equatable {
            let isSubscribed: Bool
            let billingPeriod: String?
            let startedAt: Int?
            let expiresOrRenewsAt: Int?
            let paymentPlatform: String?
            let status: String?

            static let notSubscribed: Self = .init(isSubscribed: false, billingPeriod: nil, startedAt: nil, expiresOrRenewsAt: nil, paymentPlatform: nil, status: nil)

            init(_ subscription: PrivacyProSubscription) {
                isSubscribed = true
                billingPeriod = subscription.billingPeriod.rawValue
                startedAt = Int(subscription.startedAt.timeIntervalSince1970 * 1000)
                expiresOrRenewsAt = Int(subscription.expiresOrRenewsAt.timeIntervalSince1970 * 1000)
                paymentPlatform = subscription.platform.rawValue
                status = subscription.status.rawValue
            }

            init(isSubscribed: Bool, billingPeriod: String?, startedAt: Int?, expiresOrRenewsAt: Int?, paymentPlatform: String?, status: String?) {
                self.isSubscribed = isSubscribed
                self.billingPeriod = billingPeriod
                self.startedAt = startedAt
                self.expiresOrRenewsAt = expiresOrRenewsAt
                self.paymentPlatform = paymentPlatform
                self.status = status
            }
        }

        struct GetFeatureConfigurationResponse: Encodable {
            let usePaidDuckAi: Bool
        }

        struct GetAuthAccessTokenResponse: Encodable {
            let accessToken: String
        }
    }
}
