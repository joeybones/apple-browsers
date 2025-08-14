//
//  SubscriptionManagerV2.swift
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
import Combine
import Common
import os.log
import Networking

public enum SubscriptionManagerError: Error, Equatable, LocalizedError {
    /// The app has no `TokenContainer`
    case noTokenAvailable
    /// There was a failure wile retrieving, updating or creating the `TokenContainer`
    case errorRetrievingTokenContainer(error: Error?)

    case confirmationHasInvalidSubscription
    case noProductsFound

    public static func == (lhs: SubscriptionManagerError, rhs: SubscriptionManagerError) -> Bool {
        switch (lhs, rhs) {
        case (.noTokenAvailable, .noTokenAvailable):
            return true
        case (.errorRetrievingTokenContainer(let lhsError), .errorRetrievingTokenContainer(let rhsError)):
            return lhsError?.localizedDescription == rhsError?.localizedDescription
        case (.confirmationHasInvalidSubscription, .confirmationHasInvalidSubscription),
            (.noProductsFound, .noProductsFound):
            return true
        default:
            return false
        }
    }

    public var errorDescription: String? {
        switch self {
        case .noTokenAvailable:
            "No token available"
        case .errorRetrievingTokenContainer(error: let error):
            "Error retrieving token container: \(String(describing: error))"
        case .confirmationHasInvalidSubscription:
            "Confirmation has an invalid subscription"
        case .noProductsFound:
            "No products found"
        }
    }
}

public enum SubscriptionPixelType: Equatable {
    case invalidRefreshToken
    case migrationSucceeded
    case migrationFailed(Error)
    case subscriptionIsActive
    case getTokensError(AuthTokensCachePolicy, Error)
    case invalidRefreshTokenSignedOut
    case invalidRefreshTokenRecovered

    public static func == (lhs: SubscriptionPixelType, rhs: SubscriptionPixelType) -> Bool {
        switch (lhs, rhs) {
        case (.invalidRefreshToken, .invalidRefreshToken),
            (.migrationSucceeded, .migrationSucceeded),
            (.subscriptionIsActive, .subscriptionIsActive),
            (.invalidRefreshTokenSignedOut, .invalidRefreshTokenSignedOut),
            (.invalidRefreshTokenRecovered, .invalidRefreshTokenRecovered),
            (.migrationFailed, .migrationFailed),
            (.getTokensError, .getTokensError):
            return true
        default:
            return false
        }
    }
}

/// Pixels handler
public protocol SubscriptionPixelHandling {
    func handle(pixel: SubscriptionPixelType)
    func handle(pixel: KeychainManager.Pixel)
}

public protocol SubscriptionManagerV2: SubscriptionTokenProvider, SubscriptionAuthenticationStateProvider, SubscriptionAuthV1toV2Bridge {

    // Environment
    static func loadEnvironmentFrom(userDefaults: UserDefaults) -> SubscriptionEnvironment?
    static func save(subscriptionEnvironment: SubscriptionEnvironment, userDefaults: UserDefaults)
    var currentEnvironment: SubscriptionEnvironment { get }

    /// Tries to get an authentication token and the subscription
    func loadInitialData() async

    /// Retrieve the purchased subscription
    /// - Parameter cachePolicy: The cache policy, `remoteFirst` or `cacheFirst`
    /// - Returns: A `PrivacyProSubscription` if available, throws `SubscriptionEndpointServiceError.noData` if the subscription is not available or any other errors if the process failed at any point.
    @discardableResult func getSubscription(cachePolicy: SubscriptionCachePolicy) async throws -> PrivacyProSubscription

    /// - Returns: true is a subscription (expired or not) is present, false otherwise.
    func isSubscriptionPresent() -> Bool

    /// Tries to activate a subscription using a platform signature
    /// - Parameter lastTransactionJWSRepresentation: A platform signature coming from the AppStore
    /// - Returns: A subscription if found
    /// - Throws: An error if the access token is not available or something goes wrong in the api requests
    func getSubscriptionFrom(lastTransactionJWSRepresentation: String) async throws -> PrivacyProSubscription?

    /// If the user can purchase a subscription or not
    var canPurchase: Bool { get }

    /// Publisher that emits a boolean value indicating whether the user can purchase.
    var canPurchasePublisher: AnyPublisher<Bool, Never> { get }
    func getProducts() async throws -> [GetProductsItem]

    @available(macOS 12.0, iOS 15.0, *) func storePurchaseManager() -> StorePurchaseManagerV2

    /// Subscription feature related URL that matches current environment
    func url(for type: SubscriptionURL) -> URL

    /// Purchase page URL when launched as a result of intercepted `/pro` navigation.
    /// It is created based on current `SubscriptionURL.purchase` and inherits designated URL components from the source page that triggered redirect.
    func urlForPurchaseFromRedirect(redirectURLComponents: URLComponents, tld: TLD) -> URL

    func getCustomerPortalURL() async throws -> URL

    /// The user email
    var userEmail: String? { get }

    /// Sign out the user, clear and invalidate the access token and clear the subscription cache
    func signOut(notifyUI: Bool) async

    /// Removes the subscription cache, this will trigger a remote fetch the next time `getSubscription(...)` is called
    func clearSubscriptionCache()

    /// Confirm a purchase with a platform signature
    func confirmPurchase(signature: String, additionalParams: [String: String]?) async throws -> PrivacyProSubscription

    /// Closure called when an expired refresh token is detected and the Subscription login is invalid. An attempt to automatically recover it can be performed or the app can ask the user to do it manually
    typealias TokenRecoveryHandler = () async throws -> Void

    // MARK: - Features

    /// Get the current subscription features
    /// A feature is based on an entitlement and can be enabled or disabled
    /// A user cant have an entitlement without the feature, if a user is missing an entitlement the feature is disabled
    func currentSubscriptionFeatures(forceRefresh: Bool) async throws -> [SubscriptionEntitlement]

    // MARK: - Token Management

    /// Get a token container accordingly to the policy
    /// - Parameter policy: The policy that will be used to get the token, it effects the tokens source and validity
    /// - Returns: The TokenContainer
    /// - Throws: A `SubscriptionManagerError`.
    ///     `noTokenAvailable` if the TokenContainer is not present.
    ///     `errorRetrievingTokenContainer(error:...)` in case of any error retrieving, refreshing or creating the TokenContainer, this can be caused by networking issues or keychain errors etc.
    @discardableResult
    func getTokenContainer(policy: AuthTokensCachePolicy) async throws -> TokenContainer

    /// Exchange access token v1 for a access token v2
    /// - Parameter tokenV1: The Auth v1 access token
    /// - Returns: An auth v2 TokenContainer
    func exchange(tokenV1: String) async throws -> TokenContainer

    /// Adopt a token provided by the FE during a Subscription purchase
    func adopt(accessToken: String, refreshToken: String) async throws

    /// Adopt a token provided by an external entity, typically the main app when this is used by the VPN
    func adopt(tokenContainer: TokenContainer) async throws

    /// Remove the stored token container and the legacy token
    func removeLocalAccount()
}

/// Single entry point for everything related to Subscription. This manager is disposable, every time something related to the environment changes this need to be recreated.
public final class DefaultSubscriptionManagerV2: SubscriptionManagerV2 {

    var oAuthClient: any OAuthClient
    private let _storePurchaseManager: StorePurchaseManagerV2?
    private let subscriptionEndpointService: SubscriptionEndpointServiceV2
    private let pixelHandler: SubscriptionPixelHandling
    public var tokenRecoveryHandler: TokenRecoveryHandler?
    public let currentEnvironment: SubscriptionEnvironment
    private let isInternalUserEnabled: () -> Bool
    private let legacyAccountStorage: AccountKeychainStorage?
    private let userDefaults: UserDefaults
    private let canPurchaseSubject = PassthroughSubject<Bool, Never>()
    private var cancellables = Set<AnyCancellable>()

    public init(storePurchaseManager: StorePurchaseManagerV2? = nil,
                oAuthClient: any OAuthClient,
                userDefaults: UserDefaults,
                subscriptionEndpointService: SubscriptionEndpointServiceV2,
                subscriptionEnvironment: SubscriptionEnvironment,
                pixelHandler: SubscriptionPixelHandling,
                tokenRecoveryHandler: TokenRecoveryHandler? = nil,
                initForPurchase: Bool = true,
                legacyAccountStorage: AccountKeychainStorage? = nil,
                isInternalUserEnabled: @escaping () -> Bool = { false }) {
        self._storePurchaseManager = storePurchaseManager
        self.oAuthClient = oAuthClient
        self.userDefaults = userDefaults
        self.subscriptionEndpointService = subscriptionEndpointService
        self.currentEnvironment = subscriptionEnvironment
        self.pixelHandler = pixelHandler
        self.tokenRecoveryHandler = tokenRecoveryHandler
        self.isInternalUserEnabled = isInternalUserEnabled
        self.legacyAccountStorage = legacyAccountStorage
        if initForPurchase {
            switch currentEnvironment.purchasePlatform {
            case .appStore:
                if #available(macOS 12.0, iOS 15.0, *) {
                    setupForAppStore()
                } else {
                    assertionFailure("Trying to setup AppStore where not supported")
                }
            case .stripe:
                break
            }
        }
    }

    public var canPurchase: Bool {
        guard let storePurchaseManager = _storePurchaseManager else { return false }
        return storePurchaseManager.areProductsAvailable
    }

    /// Publisher that emits a boolean value indicating whether the user can purchase.
    /// The value is updated whenever the `areProductsAvailablePublisher` of the underlying StorePurchaseManager emits a new value.
    public var canPurchasePublisher: AnyPublisher<Bool, Never> { canPurchaseSubject.eraseToAnyPublisher() }

    @available(macOS 12.0, iOS 15.0, *)
    public func storePurchaseManager() -> StorePurchaseManagerV2 {
        return _storePurchaseManager!
    }

    // MARK: Load and Save SubscriptionEnvironment

    static private let subscriptionEnvironmentStorageKey = "com.duckduckgo.subscription.environment"
    static public func loadEnvironmentFrom(userDefaults: UserDefaults) -> SubscriptionEnvironment? {
        if let savedData = userDefaults.object(forKey: Self.subscriptionEnvironmentStorageKey) as? Data {
            let decoder = JSONDecoder()
            if let loadedData = try? decoder.decode(SubscriptionEnvironment.self, from: savedData) {
                return loadedData
            }
        }
        return nil
    }

    static public func save(subscriptionEnvironment: SubscriptionEnvironment, userDefaults: UserDefaults) {
        let encoder = JSONEncoder()
        if let encodedData = try? encoder.encode(subscriptionEnvironment) {
            userDefaults.set(encodedData, forKey: Self.subscriptionEnvironmentStorageKey)
        }
    }

    // MARK: - Environment

    @available(macOS 12.0, iOS 15.0, *) private func setupForAppStore() {
        storePurchaseManager().areProductsAvailablePublisher
            .sink { [weak self] value in
                self?.canPurchaseSubject.send(value)
            }
            .store(in: &cancellables)

        Task {
            await storePurchaseManager().updateAvailableProducts()
        }
    }

    // MARK: - Subscription

    public func loadInitialData() async {
        Logger.subscription.log("Loading initial data...")
        do {
            _ = try? await getTokenContainer(policy: .localValid)
            let subscription = try await getSubscription(cachePolicy: .remoteFirst)
            Logger.subscription.log("Subscription is \(subscription.isActive ? "active" : "not active", privacy: .public)")
        } catch SubscriptionEndpointServiceError.noData {
            Logger.subscription.log("No Subscription available")
            clearSubscriptionCache()
        } catch {
            Logger.subscription.error("Failed to load initial subscription data: \(error, privacy: .public)")
        }
    }

    @discardableResult
    public func getSubscription(cachePolicy: SubscriptionCachePolicy) async throws -> PrivacyProSubscription {

        // NOTE: This is ugly, the subscription cache will be moved from the endpoint service to here and handled properly https://app.asana.com/0/0/1209015691872191

        guard isUserAuthenticated else {
            throw SubscriptionEndpointServiceError.noData
        }

        var subscription: PrivacyProSubscription

        switch cachePolicy {

        case .remoteFirst, .cacheFirst:
            if cachePolicy == .cacheFirst {
                // We skip ahead and try to get the cached subscription, useful with slow/no connections where we don't want to wait for a get token timeout
                do {
                    subscription = try await subscriptionEndpointService.getSubscription(accessToken: nil, cachePolicy: cachePolicy)
                    break
                } catch {}
            }

            var tokenContainer: TokenContainer
            do {
                tokenContainer = try await getTokenContainer(policy: .localValid)
            } catch SubscriptionManagerError.noTokenAvailable {
                throw SubscriptionEndpointServiceError.noData
            } catch {
                // Failed to get a valid token, fall back on cache
                subscription = try await subscriptionEndpointService.getSubscription(accessToken: nil, cachePolicy: .cacheFirst)
                break
            }
            subscription = try await subscriptionEndpointService.getSubscription(accessToken: tokenContainer.accessToken, cachePolicy: cachePolicy)
        }

        if subscription.isActive {
            pixelHandler.handle(pixel: .subscriptionIsActive)
        }

        return subscription
    }

    public func isSubscriptionPresent() -> Bool {
        subscriptionEndpointService.getCachedSubscription() != nil
    }

    public func getSubscriptionFrom(lastTransactionJWSRepresentation: String) async throws -> PrivacyProSubscription? {
        do {
            let tokenContainer = try await oAuthClient.activate(withPlatformSignature: lastTransactionJWSRepresentation)
            return try await subscriptionEndpointService.getSubscription(accessToken: tokenContainer.accessToken, cachePolicy: .remoteFirst)
        } catch SubscriptionEndpointServiceError.noData {
            return nil
        } catch {
            throw error
        }
    }

    public func getProducts() async throws -> [GetProductsItem] {
        try await subscriptionEndpointService.getProducts()
    }

    public func clearSubscriptionCache() {
        subscriptionEndpointService.clearSubscription()
    }

    // MARK: - URLs

    public func url(for type: SubscriptionURL) -> URL {
        if let customBaseSubscriptionURL = currentEnvironment.customBaseSubscriptionURL,
           isInternalUserEnabled() {
            return type.subscriptionURL(withCustomBaseURL: customBaseSubscriptionURL, environment: currentEnvironment.serviceEnvironment)
        }

        return type.subscriptionURL(environment: currentEnvironment.serviceEnvironment)
    }

    public func urlForPurchaseFromRedirect(redirectURLComponents: URLComponents, tld: TLD) -> URL {
        let defaultPurchaseURL = url(for: .purchase)

        if var purchaseURLComponents = URLComponents(url: defaultPurchaseURL, resolvingAgainstBaseURL: true) {

            purchaseURLComponents.addingSubdomain(from: redirectURLComponents, tld: tld)
            purchaseURLComponents.addingPort(from: redirectURLComponents)
            purchaseURLComponents.addingFragment(from: redirectURLComponents)
            purchaseURLComponents.addingQueryItems(from: redirectURLComponents)

            return purchaseURLComponents.url ?? defaultPurchaseURL
        }

        return defaultPurchaseURL
    }

    public func getCustomerPortalURL() async throws -> URL {
        guard isUserAuthenticated else {
            throw SubscriptionEndpointServiceError.noData
        }

        let tokenContainer = try await getTokenContainer(policy: .localValid)
        // Get Stripe Customer Portal URL and update the model
        let serviceResponse = try await subscriptionEndpointService.getCustomerPortalURL(accessToken: tokenContainer.accessToken, externalID: tokenContainer.decodedAccessToken.externalID)
        guard let url = URL(string: serviceResponse.customerPortalUrl) else {
            throw SubscriptionEndpointServiceError.noData
        }
        return url
    }

    // MARK: - User
    public var isUserAuthenticated: Bool {
        do {
            let tokenContainer = try oAuthClient.currentTokenContainer()
            return tokenContainer != nil
        } catch {
            return cachedIsUserAuthenticated
        }
    }

    public var userEmail: String? {
        return (try? oAuthClient.currentTokenContainer())?.decodedAccessToken.email
    }

    var cachedUserEntitlements: [SubscriptionEntitlement] {
        get {
            userDefaults.userEntitlements
        }
        set {
            let currentCachedUserEntitlements = self.userDefaults.userEntitlements
            self.userDefaults.userEntitlements = newValue

            // Send notification when entitlements change
            if !SubscriptionEntitlement.areEntitlementsEqual(currentCachedUserEntitlements, newValue) {
                Logger.subscription.debug("Entitlements changed - New \(String(describing: newValue)) Old \(String(describing: currentCachedUserEntitlements))")
                let payload = EntitlementsDidChangePayload(entitlements: newValue)
                NotificationCenter.default.post(name: .entitlementsDidChange, object: self, userInfo: payload.notificationUserInfo)
            }
        }
    }

    var cachedIsUserAuthenticated: Bool {
        get {
            userDefaults.isUserAuthenticated
        }
        set {
            let currentCachedIsAuthenticated = self.userDefaults.isUserAuthenticated
            self.userDefaults.isUserAuthenticated = newValue

            // Send notification when the login changes
            switch (currentCachedIsAuthenticated, newValue) {
            case (false, true):
                Logger.subscription.debug("Login detected")
                NotificationCenter.default.post(name: .accountDidSignIn, object: self, userInfo: nil)
            case (true, false):
                Logger.subscription.debug("Logout detected")
                NotificationCenter.default.post(name: .accountDidSignOut, object: self, userInfo: nil)
            default:
                Logger.subscription.debug("Login state unchanged - Current: \(currentCachedIsAuthenticated), new: \(newValue)")
            }

            if newValue == false {
                self.cachedUserEntitlements = []
            }
        }
    }

    @discardableResult public func getTokenContainer(policy: AuthTokensCachePolicy) async throws -> TokenContainer {
        Logger.subscription.debug("Get tokens \(policy.description, privacy: .public)")

        do {
            let resultTokenContainer = try await oAuthClient.getTokens(policy: policy)
            let newEntitlements = resultTokenContainer.decodedAccessToken.subscriptionEntitlements

            cachedUserEntitlements = newEntitlements
            cachedIsUserAuthenticated = true
            return resultTokenContainer
        } catch OAuthClientError.missingTokenContainer {
            // Expected when no tokens are available
            cachedUserEntitlements = []
            throw SubscriptionManagerError.noTokenAvailable
        } catch {
            pixelHandler.handle(pixel: .getTokensError(policy, error))

            switch error {

            case OAuthClientError.unknownAccount:

                Logger.subscription.error("Refresh failed, the account is unknown. Logging out...")
                await signOut(notifyUI: true)
                throw SubscriptionManagerError.noTokenAvailable

            case OAuthClientError.invalidTokenRequest:

                pixelHandler.handle(pixel: .invalidRefreshToken)
                Logger.subscription.error("Refresh failed, invalid token request")
                do {
                    let recoveredTokenContainer = try await attemptTokenRecovery()
                    pixelHandler.handle(pixel: .invalidRefreshTokenRecovered)
                    return recoveredTokenContainer
                } catch {
                    await signOut(notifyUI: false)
                    pixelHandler.handle(pixel: .invalidRefreshTokenSignedOut)
                    throw SubscriptionManagerError.noTokenAvailable
                }

            default:
                throw SubscriptionManagerError.errorRetrievingTokenContainer(error: error)
            }
        }
    }

    func attemptTokenRecovery() async throws -> TokenContainer {

        Logger.subscription.log("Attempting token recovery...")

        guard let tokenRecoveryHandler else {
            Logger.subscription.log("Recovery not possible, no handler configured.")
            throw SubscriptionManagerError.noTokenAvailable
        }

        try await tokenRecoveryHandler()

        guard let currentTokenContainer = try? oAuthClient.currentTokenContainer(),
              !currentTokenContainer.decodedRefreshToken.isExpired() else {
            Logger.subscription.log("Recovery failed: the refresh token is missing or still expired after the recovery attempt.")
            throw SubscriptionManagerError.noTokenAvailable
        }
        return currentTokenContainer
    }

    public func exchange(tokenV1: String) async throws -> TokenContainer {
        let tokenContainer = try await oAuthClient.exchange(accessTokenV1: tokenV1)
            cachedIsUserAuthenticated = true
            cachedUserEntitlements = tokenContainer.decodedAccessToken.subscriptionEntitlements
        return tokenContainer
    }

    public func adopt(accessToken: String, refreshToken: String) async throws {
        Logger.subscription.log("Adopting and decoding token container")
        let tokenContainer = try await oAuthClient.decode(accessToken: accessToken, refreshToken: refreshToken)
        try await adopt(tokenContainer: tokenContainer)
    }

    public func adopt(tokenContainer: TokenContainer) async throws {
        Logger.subscription.log("Adopting token container")
        oAuthClient.adopt(tokenContainer: tokenContainer)
        // It’s important to force refresh the token to immediately branch from the one received.
        // See discussion https://app.asana.com/0/1199230911884351/1208785842165508/f
        let refreshedTokenContainer = try await oAuthClient.getTokens(policy: .localForceRefresh)
            cachedIsUserAuthenticated = true
            cachedUserEntitlements = refreshedTokenContainer.decodedAccessToken.subscriptionEntitlements
        }

    public func removeLocalAccount() {
        Logger.subscription.log("Removing local account")
            cachedIsUserAuthenticated = false
        oAuthClient.removeLocalAccount()
    }

    public func signOut(notifyUI: Bool) async {
        Logger.subscription.log("SignOut: Removing all traces of the subscription and account. Notify UI: \(notifyUI ? "true" : "false")")
        try? await oAuthClient.logout()
        clearSubscriptionCache()
        if notifyUI {
                cachedIsUserAuthenticated = false
        } else {
            // skipping cached setter for avoiding notification
                userDefaults.isUserAuthenticated = false
                userDefaults.userEntitlements = []
            }
        Logger.subscription.log("Removing V1 Account")
        try? legacyAccountStorage?.clearAuthenticationState()
    }

    public func confirmPurchase(signature: String, additionalParams: [String: String]?) async throws -> PrivacyProSubscription {
        Logger.subscription.log("Confirming Purchase...")
        let accessToken = try await getTokenContainer(policy: .localValid).accessToken
        let confirmation = try await subscriptionEndpointService.confirmPurchase(accessToken: accessToken,
                                                                                 signature: signature,
                                                                                 additionalParams: additionalParams)
        try await subscriptionEndpointService.ingestSubscription(confirmation.subscription)
        Logger.subscription.log("Purchase confirmed!")
        return confirmation.subscription
    }

    // MARK: - Features

    /// Returns the features available for the current subscription, a feature is enabled only if the user has the corresponding entitlement
    /// - Parameter forceRefresh: ignore subscription and token cache and re-download everything
    /// - Returns: An Array of SubscriptionFeature where each feature is enabled or disabled based on the user entitlements
    public func currentSubscriptionFeatures(forceRefresh: Bool) async throws -> [SubscriptionEntitlement] {
        guard isUserAuthenticated else { return [] }

        let availableFeatures: [SubscriptionEntitlement]

        if forceRefresh {
            let currentSubscription = try await getSubscription(cachePolicy: .remoteFirst)
            availableFeatures = currentSubscription.features ?? []
        } else {
            let currentSubscription = try? await getSubscription(cachePolicy: .cacheFirst)
            availableFeatures = currentSubscription?.features ?? []
        }

        return availableFeatures
    }
}

extension DefaultSubscriptionManagerV2: SubscriptionTokenProvider {
    public func getAccessToken() async throws -> String {
        try await getTokenContainer(policy: .localValid).accessToken
    }
}

extension SubscriptionEntitlement {

    var entitlement: Entitlement {
        switch self {
        case .networkProtection:
            return Entitlement(product: .networkProtection)
        case .dataBrokerProtection:
            return Entitlement(product: .dataBrokerProtection)
        case .identityTheftRestoration:
            return Entitlement(product: .identityTheftRestoration)
        case .identityTheftRestorationGlobal:
            return Entitlement(product: .identityTheftRestorationGlobal)
        case .paidAIChat:
            return Entitlement(product: .paidAIChat)
        case .unknown:
            return Entitlement(product: .unknown)
        }
    }
}

fileprivate extension UserDefaults {

    private static let isUserAuthenticatedKey = "com.duckduckgo.subscription.isUserAuthenticated"
    var isUserAuthenticated: Bool {
        get {
            return bool(forKey: Self.isUserAuthenticatedKey)
        }
        set {
            set(newValue, forKey: Self.isUserAuthenticatedKey)
        }
    }

    private static let userEntitlementsKey = "com.duckduckgo.subscription.userEntitlements"
    var userEntitlements: [SubscriptionEntitlement] {
        get {
            guard let data = self.data(forKey: Self.userEntitlementsKey) else {
                return []
            }
            guard let entitlements = try? JSONDecoder().decode([SubscriptionEntitlement].self, from: data) else {
                assertionFailure("Error decoding user entitlements")
                Logger.subscription.fault("Error decoding user entitlements")
                return []
            }
            return entitlements
        }
        set {
            guard let data = try? JSONEncoder().encode(newValue)  else {
                assertionFailure("Error encoding user entitlements")
                Logger.subscription.fault("Error encoding user entitlements")
                return
            }
            self.set(data, forKey: Self.userEntitlementsKey)
        }
    }
}
