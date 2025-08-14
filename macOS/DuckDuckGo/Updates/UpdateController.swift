//
//  UpdateController.swift
//
//  Copyright © 2021 DuckDuckGo. All rights reserved.
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
import Common
import Combine
import Sparkle
import BrowserServicesKit
import SwiftUIExtensions
import PixelKit
import SwiftUI
import os.log

#if SPARKLE

protocol UpdateControllerProtocol: AnyObject {

    var latestUpdate: Update? { get }
    var latestUpdatePublisher: Published<Update?>.Publisher { get }

    var hasPendingUpdate: Bool { get }
    var hasPendingUpdatePublisher: Published<Bool>.Publisher { get }

    var needsNotificationDot: Bool { get set }
    var notificationDotPublisher: AnyPublisher<Bool, Never> { get }

    var updateProgress: UpdateCycleProgress { get }
    var updateProgressPublisher: Published<UpdateCycleProgress>.Publisher { get }

    var lastUpdateCheckDate: Date? { get }

    func checkForUpdateRespectingRollout()
    func checkForUpdateSkippingRollout()
    func runUpdateFromMenuItem()
    func runUpdate()

    var areAutomaticUpdatesEnabled: Bool { get set }

    var isAtRestartCheckpoint: Bool { get }
    var shouldForceUpdateCheck: Bool { get }
}

final class UpdateController: NSObject, UpdateControllerProtocol {

    enum Constants {
        static let internalChannelName = "internal-channel"
    }

    lazy var notificationPresenter = UpdateNotificationPresenter()
    let willRelaunchAppPublisher: AnyPublisher<Void, Never>

    // Struct used to cache data until the updater finishes checking for updates
    struct UpdateCheckResult {
        let item: SUAppcastItem
        let isInstalled: Bool
        let needsLatestReleaseNote: Bool

        init(item: SUAppcastItem, isInstalled: Bool, needsLatestReleaseNote: Bool = false) {
            self.item = item
            self.isInstalled = isInstalled
            self.needsLatestReleaseNote = needsLatestReleaseNote
        }
    }
    private var cachedUpdateResult: UpdateCheckResult?

    @Published private(set) var updateProgress = UpdateCycleProgress.default {
        didSet {
            if let cachedUpdateResult {
                latestUpdate = Update(appcastItem: cachedUpdateResult.item, isInstalled: cachedUpdateResult.isInstalled, needsLatestReleaseNote: cachedUpdateResult.needsLatestReleaseNote)
                hasPendingUpdate = latestUpdate?.isInstalled == false && updateProgress.isDone && userDriver?.isResumable == true
                needsNotificationDot = hasPendingUpdate
            }
            showUpdateNotificationIfNeeded()
        }
    }

    var updateProgressPublisher: Published<UpdateCycleProgress>.Publisher { $updateProgress }

    @Published private(set) var latestUpdate: Update?

    var latestUpdatePublisher: Published<Update?>.Publisher { $latestUpdate }

    @Published private(set) var hasPendingUpdate = false
    var hasPendingUpdatePublisher: Published<Bool>.Publisher { $hasPendingUpdate }

    @UserDefaultsWrapper(key: .updateValidityStartDate, defaultValue: nil)
    var updateValidityStartDate: Date?

    var lastUpdateCheckDate: Date? { updater?.lastUpdateCheckDate }
    var lastUpdateNotificationShownDate: Date = .distantPast

    private var shouldShowUpdateNotification: Bool {
        Date().timeIntervalSince(lastUpdateNotificationShownDate) > .days(7)
    }

    @UserDefaultsWrapper(key: .automaticUpdates, defaultValue: true)
    var areAutomaticUpdatesEnabled: Bool {
        willSet {
            if newValue != areAutomaticUpdatesEnabled {
                userDriver?.cancelAndDismissCurrentUpdate()
                updater = nil
            }
        }
        didSet {
            if oldValue != areAutomaticUpdatesEnabled {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
                    _ = try? self?.configureUpdater()
                    self?.checkForUpdateSkippingRollout()
                }
            }
        }
    }

    var isAtRestartCheckpoint: Bool {
        guard let userDriver else {
            return false
        }

        switch userDriver.updateProgress {
        case .readyToInstallAndRelaunch:
            return true
        case .updateCycleDone(let reason) where reason == .pausedAtRestartCheckpoint:
            return true
        default:
            return false
        }
    }

    @UserDefaultsWrapper(key: .pendingUpdateShown, defaultValue: false)
    var needsNotificationDot: Bool {
        didSet {
            notificationDotSubject.send(needsNotificationDot)
        }
    }

    private let notificationDotSubject = CurrentValueSubject<Bool, Never>(false)
    lazy var notificationDotPublisher = notificationDotSubject.eraseToAnyPublisher()

    private(set) var updater: SPUUpdater?
    private(set) var userDriver: UpdateUserDriver?
    private let willRelaunchAppSubject = PassthroughSubject<Void, Never>()
    private var internalUserDecider: InternalUserDecider
    private var updateProcessCancellable: AnyCancellable!

    private var shouldCheckNewApplicationVersion = true

    private let updateCheckState: UpdateCheckState

    // MARK: - Feature Flags support

    private let featureFlagger: FeatureFlagger

    var useLegacyAutoRestartLogic: Bool {
        !featureFlagger.isFeatureOn(.updatesWontAutomaticallyRestartApp)
    }
    private var canBuildsExpire: Bool {
        featureFlagger.isFeatureOn(.updatesWontAutomaticallyRestartApp)
    }

    // MARK: - Public

    init(internalUserDecider: InternalUserDecider,
         featureFlagger: FeatureFlagger = NSApp.delegateTyped.featureFlagger,
         updateCheckState: UpdateCheckState = UpdateCheckState()) {

        willRelaunchAppPublisher = willRelaunchAppSubject.eraseToAnyPublisher()
        self.featureFlagger = featureFlagger
        self.internalUserDecider = internalUserDecider
        self.updateCheckState = updateCheckState
        super.init()

        _ = try? configureUpdater()

#if DEBUG
        if NSApp.delegateTyped.featureFlagger.isFeatureOn(.autoUpdateInDEBUG) {
            checkForUpdateRespectingRollout()
        }
#else
        checkForUpdateRespectingRollout()
#endif

        subscribeToResignKeyNotifications()
    }

    private var cancellables = Set<AnyCancellable>()

    private func subscribeToResignKeyNotifications() {
        NotificationCenter.default.publisher(for: NSWindow.didResignKeyNotification)
            .sink { [weak self] _ in
                self?.checkForUpdateRespectingRollout()
            }
            // Store subscription to keep it alive
            .store(in: &cancellables)
    }

    func checkNewApplicationVersionIfNeeded(updateProgress: UpdateCycleProgress) {
        /// Displays the "Browser Updated/Downgraded" notification only after the first complete update cycle
        if updateProgress.isDone, shouldCheckNewApplicationVersion {
            /// Proceed only if no newer update is available for the user
            if case .updateCycleDone(.finishedWithNoUpdateFound) = updateProgress {
               checkNewApplicationVersion()
            }
            shouldCheckNewApplicationVersion = false
        }
    }

    private func checkNewApplicationVersion() {
        let updateStatus = ApplicationUpdateDetector.isApplicationUpdated()
        switch updateStatus {
        case .noChange: break
        case .updated:
            notificationPresenter.showUpdateNotification(icon: NSImage.successCheckmark, text: UserText.browserUpdatedNotification, buttonText: UserText.viewDetails)
        case .downgraded:
            notificationPresenter.showUpdateNotification(icon: NSImage.successCheckmark, text: UserText.browserDowngradedNotification, buttonText: UserText.viewDetails)
        }
    }

    // Check for updates while adhering to the rollout schedule
    // This is the default behavior
    func checkForUpdateRespectingRollout() {
        Task { @UpdateCheckActor in
            await performUpdateCheck()
        }
    }

    @UpdateCheckActor
    private func performUpdateCheck() async {
        // Check if we can start a new check (Sparkle availability + rate limiting)
        guard await updateCheckState.canStartNewCheck(updater: updater) else {
            Logger.updates.debug("Update check skipped - not allowed by Sparkle or rate limited")
            return
        }

        if case .updaterError = userDriver?.updateProgress {
            userDriver?.cancelAndDismissCurrentUpdate()
        }

        // Create the actual update task
        Task { @MainActor in
            // Handle expired builds first (critical path)
            guard !discardCurrentUpdateIfExpiredAndCheckAgain(skipRollout: false) else {
                return
            }

            guard let updater, !updater.sessionInProgress else { return }

            Logger.updates.log("Checking for updates respecting rollout")
            updater.checkForUpdatesInBackground()
        }
    }

    private var isBuildExpired: Bool {
        canBuildsExpire && shouldForceUpdateCheck
    }

    @discardableResult
    private func discardCurrentUpdateIfExpiredAndCheckAgain(skipRollout: Bool) -> Bool {
        guard isBuildExpired else {
            return false
        }

        userDriver?.cancelAndDismissCurrentUpdate()
        updater = nil

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            guard let self,
                  let updater = try? configureUpdater(needsUpdateCheck: true) else {
                return
            }
            self.updater = updater

            if skipRollout {
                updater.checkForUpdates()
            } else {
                updater.checkForUpdatesInBackground()
            }
        }

        return true
    }

    // Check for updates immediately, bypassing the rollout schedule
    // This is used for user-initiated update checks only
    func checkForUpdateSkippingRollout() {
        Task { @UpdateCheckActor in
            await performUpdateCheckSkippingRollout()
        }
    }

    @UpdateCheckActor
    private func performUpdateCheckSkippingRollout() async {
        // User-initiated checks skip rate limiting but still respect Sparkle availability
        guard await updateCheckState.canStartNewCheck(updater: updater, minimumInterval: 0) else {
            Logger.updates.debug("User-initiated update check skipped - not allowed by Sparkle")
            return
        }

        Logger.updates.debug("User-initiated update check starting")

        if case .updaterError = userDriver?.updateProgress {
            userDriver?.cancelAndDismissCurrentUpdate()
        }

        // Create the actual update task
        Task { @MainActor in
            // Handle expired builds first (critical path)
            guard !discardCurrentUpdateIfExpiredAndCheckAgain(skipRollout: true) else {
                return
            }

            guard let updater, !updater.sessionInProgress else { return }

            Logger.updates.log("Checking for updates skipping rollout")
            updater.checkForUpdates()
        }
    }

    // MARK: - Private

    // Determines if a forced update check is necessary
    //
    // Due to frequent releases (weekly public, daily internal), the downloaded update
    // may become obsolete if the user doesn't relaunch the app for an extended period.
    var shouldForceUpdateCheck: Bool {
        guard let updateValidityStartDate else {
            return true
        }

        let threshold = internalUserDecider.isInternalUser ? TimeInterval.hours(1) : TimeInterval.days(1)
        return Date().timeIntervalSince(updateValidityStartDate) > threshold
    }

    // Resets the updater state, configures it with dependencies/settings
    //
    // - Parameters:
    //   - needsUpdateCheck: A flag indicating whether to perform a new appcast check.
    //     Set to `true` if the pending update might be obsolete.
    //     Defaults to `false`
    private func configureUpdater(needsUpdateCheck: Bool = false) throws -> SPUUpdater? {
        // Workaround to reset the updater state
        cachedUpdateResult = nil
        latestUpdate = nil

        userDriver = UpdateUserDriver(internalUserDecider: internalUserDecider,
                                      areAutomaticUpdatesEnabled: areAutomaticUpdatesEnabled)
        guard let userDriver else { return nil }

        let updater = SPUUpdater(hostBundle: Bundle.main, applicationBundle: Bundle.main, userDriver: userDriver, delegate: self)

#if DEBUG
        if NSApp.delegateTyped.featureFlagger.isFeatureOn(.autoUpdateInDEBUG) {
            updater.updateCheckInterval = 10_800
        } else {
            updater.updateCheckInterval = 0
        }
        updater.automaticallyChecksForUpdates = false
        updater.automaticallyDownloadsUpdates = false
#else
        // Some older version uses SUAutomaticallyUpdate to control app restart behavior
        // We disable it to prevent interference with our custom updater UI
        if updater.automaticallyDownloadsUpdates == true {
            updater.automaticallyDownloadsUpdates = false
        }
#endif

        updateProcessCancellable = userDriver.updateProgressPublisher
            .assign(to: \.updateProgress, onWeaklyHeld: self)

        try updater.start()
        self.updater = updater

        return updater
    }

    private func showUpdateNotificationIfNeeded() {
        guard let latestUpdate, hasPendingUpdate, shouldShowUpdateNotification else { return }

        let action = areAutomaticUpdatesEnabled ? UserText.autoUpdateAction : UserText.manualUpdateAction

        switch latestUpdate.type {
        case .critical:
            notificationPresenter.showUpdateNotification(
                icon: NSImage.criticalUpdateNotificationInfo,
                text: "\(UserText.criticalUpdateNotification) \(action)",
                presentMultiline: true
            )
        case .regular:
            notificationPresenter.showUpdateNotification(
                icon: NSImage.updateNotificationInfo,
                text: "\(UserText.updateAvailableNotification) \(action)",
                presentMultiline: true
            )
        }

        lastUpdateNotificationShownDate = Date()
    }

    @objc func openUpdatesPage() {
        notificationPresenter.openUpdatesPage()
    }

    @objc func runUpdateFromMenuItem() {
        // Duplicating the code a bit to make the feature flag separation clearer
        // remove this comment once the feature flag is removed.
        guard useLegacyAutoRestartLogic else {
            openUpdatesPage()

            if shouldForceUpdateCheck {
                checkForUpdateRespectingRollout()
                return
            }

            runUpdate()
            return
        }

        if shouldForceUpdateCheck {
            openUpdatesPage()
        }

        runUpdate()
    }

    @objc func runUpdate() {
        guard let userDriver else { return }

        PixelKit.fire(DebugEvent(GeneralPixel.updaterDidRunUpdate))

        guard useLegacyAutoRestartLogic else {
            userDriver.resume()
            return
        }

        guard shouldForceUpdateCheck else {
            userDriver.resume()
            return
        }

        userDriver.cancelAndDismissCurrentUpdate()
        updater = nil

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            _ = try? self?.configureUpdater(needsUpdateCheck: true)
            self?.checkForUpdateSkippingRollout()
        }
    }

}

extension UpdateController: SPUUpdaterDelegate {

    func allowedChannels(for updater: SPUUpdater) -> Set<String> {
        if internalUserDecider.isInternalUser {
            return Set([Constants.internalChannelName])
        } else {
            return Set()
        }
    }

    func updaterWillRelaunchApplication(_ updater: SPUUpdater) {
        willRelaunchAppSubject.send()
    }

    func updater(_ updater: SPUUpdater, didAbortWithError error: Error) {
        Logger.updates.error("Updater did abort with error: \(error.localizedDescription, privacy: .public) (\(error.pixelParameters, privacy: .public))")
        let errorCode = (error as NSError).code
        guard ![Int(Sparkle.SUError.noUpdateError.rawValue),
                Int(Sparkle.SUError.installationCanceledError.rawValue),
                Int(Sparkle.SUError.runningTranslocated.rawValue),
                Int(Sparkle.SUError.downloadError.rawValue)].contains(errorCode) else {
            return
        }

        PixelKit.fire(DebugEvent(
            GeneralPixel.updaterAborted(reason: sparkleUpdaterErrorReason(from: error.localizedDescription)),
            error: error
        ))
    }

    internal func sparkleUpdaterErrorReason(from errorDescription: String) -> String {
        // Hardcodes known Sparkle failures to ensure that no file paths are ever included.
        // Any unrecognized strings will be sent with "unknown", and will need to be debugged further as it means there
        // is a Sparkle error that isn't being accounted for in this list.
        let knownErrorPrefixes = [
            "Package installer failed to launch.",
            "Guided package installer failed to launch",
            "Guided package installer returned non-zero exit status",
            "Failed to perform installation because the paths to install at and from are not valid",
            "Failed to recursively update new application's modification time before moving into temporary directory",
            "Failed to perform installation because a path could not be constructed for the old installation",
            "Failed to move the new app",
            "Failed to perform installation because the last path component of the old installation URL could not be constructed.",
            "The update is improperly signed and could not be validated.",
            "Found regular application update",
            "An error occurred while running the updater.",
            "An error occurred while encoding the installer parameters.",
            "An error occurred while starting the installer.",
            "An error occurred while connecting to the installer.",
            "An error occurred while launching the installer.",
            "An error occurred while extracting the archive",
            "An error occurred while downloading the update",
            "An error occurred in retrieving update information",
            "An error occurred while parsing the update feed"
        ]

        for prefix in knownErrorPrefixes where errorDescription.hasPrefix(prefix) {
            return prefix
        }

        return "unknown"
    }

    func updater(_ updater: SPUUpdater, didFindValidUpdate item: SUAppcastItem) {
        Logger.updates.log("Updater did find valid update: \(item.displayVersionString, privacy: .public)(\(item.versionString, privacy: .public))")
        PixelKit.fire(DebugEvent(GeneralPixel.updaterDidFindUpdate))
        cachedUpdateResult = UpdateCheckResult(item: item, isInstalled: false)
        updateValidityStartDate = Date()
    }

    func updaterDidNotFindUpdate(_ updater: SPUUpdater, error: any Error) {
        let nsError = error as NSError
        guard let item = nsError.userInfo[SPULatestAppcastItemFoundKey] as? SUAppcastItem else { return }

        Logger.updates.log("Updater did not find valid update: \(item.displayVersionString, privacy: .public)(\(item.versionString, privacy: .public))")

        // Edge case: User upgrades to latest version within their rollout group
        // But fetched release notes are outdated due to rollout group reset
        let needsLatestReleaseNote = {
            guard let reason = nsError.userInfo[SPUNoUpdateFoundReasonKey] as? Int else { return false }
            return reason == Int(Sparkle.SPUNoUpdateFoundReason.onNewerThanLatestVersion.rawValue)
        }()
        cachedUpdateResult = UpdateCheckResult(item: item, isInstalled: true, needsLatestReleaseNote: needsLatestReleaseNote)
    }

    func updater(_ updater: SPUUpdater, didDownloadUpdate item: SUAppcastItem) {
        Logger.updates.log("Updater did download update: \(item.displayVersionString, privacy: .public)(\(item.versionString, privacy: .public))")
        PixelKit.fire(DebugEvent(GeneralPixel.updaterDidDownloadUpdate))

        if !useLegacyAutoRestartLogic,
           let userDriver {

            userDriver.updateLastUpdateDownloadedDate()
        }
    }

    func updater(_ updater: SPUUpdater, didExtractUpdate item: SUAppcastItem) {
        Logger.updates.log("Updater did extract update: \(item.displayVersionString, privacy: .public)(\(item.versionString, privacy: .public))")
    }

    func updater(_ updater: SPUUpdater, willInstallUpdate item: SUAppcastItem) {
        Logger.updates.log("Updater will install update: \(item.displayVersionString, privacy: .public)(\(item.versionString, privacy: .public))")
    }

    func updater(_ updater: SPUUpdater, willInstallUpdateOnQuit item: SUAppcastItem, immediateInstallationBlock immediateInstallHandler: @escaping () -> Void) -> Bool {
        Logger.updates.log("Updater will install update on quit: \(item.displayVersionString, privacy: .public)(\(item.versionString, privacy: .public))")
        userDriver?.configureResumeBlock(immediateInstallHandler)
        return true
    }

    func updater(_ updater: SPUUpdater, didFinishUpdateCycleFor updateCheck: SPUUpdateCheck, error: (any Error)?) {
        if error == nil {
            Logger.updates.log("Updater did finish update cycle with no error")
            updateProgress = .updateCycleDone(.finishedWithNoError)
            Task { @UpdateCheckActor in await updateCheckState.recordCheckTime() }
        } else if let errorCode = (error as? NSError)?.code, errorCode == Int(Sparkle.SUError.noUpdateError.rawValue) {
            Logger.updates.log("Updater did finish update cycle with no update found")
            updateProgress = .updateCycleDone(.finishedWithNoUpdateFound)
            Task { @UpdateCheckActor in await updateCheckState.recordCheckTime() }
        } else if let error {
            Logger.updates.log("Updater did finish update cycle with error: \(error.localizedDescription, privacy: .public) (\(error.pixelParameters, privacy: .public))")
        }
    }

    func log() {
        Logger.updates.log("areAutomaticUpdatesEnabled: \(self.areAutomaticUpdatesEnabled, privacy: .public)")
        Logger.updates.log("updateProgress: \(self.updateProgress, privacy: .public)")
        if let cachedUpdateResult {
            Logger.updates.log("cachedUpdateResult: \(cachedUpdateResult.item.displayVersionString, privacy: .public)(\(cachedUpdateResult.item.versionString, privacy: .public))")
        }
        if let state = userDriver?.sparkleUpdateState {
            Logger.updates.log("Sparkle update state: (userInitiated: \(state.userInitiated, privacy: .public), stage: \(state.stage.rawValue, privacy: .public))")
        } else {
            Logger.updates.log("Sparkle update state: Unknown")
        }
        if let userDriver {
            Logger.updates.log("isResumable: \(userDriver.isResumable, privacy: .public)")
        }
    }
}

#endif
