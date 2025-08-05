//
//  AddressBarButtonsViewController.swift
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

import AppKit
import BrowserServicesKit
import Cocoa
import Combine
import Common
import Lottie
import os.log
import PrivacyDashboard
import PixelKit
import AppKitExtensions
import AIChat

protocol AddressBarButtonsViewControllerDelegate: AnyObject {

    func addressBarButtonsViewControllerCancelButtonClicked(_ addressBarButtonsViewController: AddressBarButtonsViewController)
    func addressBarButtonsViewControllerHideAIChatButtonClicked(_ addressBarButtonsViewController: AddressBarButtonsViewController)
    func addressBarButtonsViewControllerOpenAIChatSettingsButtonClicked(_ addressBarButtonsViewController: AddressBarButtonsViewController)
    func addressBarButtonsViewControllerAIChatButtonClicked(_ addressBarButtonsViewController: AddressBarButtonsViewController)
}

final class AddressBarButtonsViewController: NSViewController {

    private enum Constants {
        static let askAiChatButtonHorizontalPadding: CGFloat = 6
        static let askAiChatButtonAnimationDuration: TimeInterval = 0.2
    }

    weak var delegate: AddressBarButtonsViewControllerDelegate?

    private let accessibilityPreferences: AccessibilityPreferences
    private let tabsPreferences: TabsPreferences
    private let visualStyle: VisualStyleProviding
    private let featureFlagger: FeatureFlagger
    private let privacyConfigurationManager: PrivacyConfigurationManaging
    private let permissionManager: PermissionManagerProtocol

    private var permissionAuthorizationPopover: PermissionAuthorizationPopover?
    private func permissionAuthorizationPopoverCreatingIfNeeded() -> PermissionAuthorizationPopover {
        return permissionAuthorizationPopover ?? {
            let popover = PermissionAuthorizationPopover()
            NotificationCenter.default.addObserver(self, selector: #selector(popoverDidClose), name: NSPopover.didCloseNotification, object: popover)
            self.permissionAuthorizationPopover = popover
            popover.setAccessibilityIdentifier("AddressBarButtonsViewController.permissionAuthorizationPopover")
            return popover
        }()
    }

    private var popupBlockedPopover: PopupBlockedPopover?
    private func popupBlockedPopoverCreatingIfNeeded() -> PopupBlockedPopover {
        return popupBlockedPopover ?? {
            let popover = PopupBlockedPopover()
            popover.delegate = self
            self.popupBlockedPopover = popover
            return popover
        }()
    }

    @IBOutlet weak var zoomButton: AddressBarButton!
    @IBOutlet weak var privacyDashboardButton: MouseOverAnimationButton!
    @IBOutlet weak var separator: NSView!
    @IBOutlet weak var bookmarkButton: AddressBarButton!
    @IBOutlet weak var imageButtonWrapper: NSView!
    @IBOutlet weak var imageButton: NSButton!
    @IBOutlet weak var cancelButton: AddressBarButton!
    @IBOutlet private weak var buttonsContainer: NSStackView!
    @IBOutlet private weak var trailingButtonsContainer: NSStackView!
    @IBOutlet weak var aiChatButton: AddressBarMenuButton!
    @IBOutlet weak var askAIChatButton: AddressBarMenuButton!
    @IBOutlet weak var trailingButtonsBackground: ColorView!

    @IBOutlet weak var animationWrapperView: NSView!
    var trackerAnimationView1: LottieAnimationView!
    var trackerAnimationView2: LottieAnimationView!
    var trackerAnimationView3: LottieAnimationView!
    var shieldAnimationView: LottieAnimationView!
    var shieldDotAnimationView: LottieAnimationView!
    @IBOutlet weak var privacyShieldLeadingConstraint: NSLayoutConstraint!
    @IBOutlet weak var animationWrapperViewLeadingConstraint: NSLayoutConstraint!

    @IBOutlet weak var leadingAIChatDivider: NSImageView!
    @IBOutlet weak var trailingAIChatDivider: NSImageView!
    @IBOutlet weak var trailingStackViewTrailingViewConstraint: NSLayoutConstraint!
    @IBOutlet weak var notificationAnimationView: NavigationBarBadgeAnimationView!
    @IBOutlet weak var bookmarkButtonWidthConstraint: NSLayoutConstraint!
    @IBOutlet weak var bookmarkButtonHeightConstraint: NSLayoutConstraint!
    @IBOutlet weak var cancelButtonWidthConstraint: NSLayoutConstraint!
    @IBOutlet weak var cancelButtonHeightConstraint: NSLayoutConstraint!
    @IBOutlet weak var aiChatButtonWidthConstraint: NSLayoutConstraint!
    @IBOutlet weak var aiChatButtonHeightConstraint: NSLayoutConstraint!
    @IBOutlet weak var askAIChatButtonWidthConstraint: NSLayoutConstraint!
    @IBOutlet weak var askAIChatButtonHeightConstraint: NSLayoutConstraint!
    @IBOutlet weak var privacyShieldButtonWidthConstraint: NSLayoutConstraint!
    @IBOutlet weak var privacyShieldButtonHeightConstraint: NSLayoutConstraint!
    @IBOutlet weak var imageButtonLeadingConstraint: NSLayoutConstraint!
    @IBOutlet weak var zoomButtonHeightConstraint: NSLayoutConstraint!
    @IBOutlet weak var geolocationButtonHeightConstraint: NSLayoutConstraint!
    @IBOutlet weak var microphoneButtonHeightConstraint: NSLayoutConstraint!
    @IBOutlet weak var cameraButtonHeightConstraint: NSLayoutConstraint!
    @IBOutlet weak var popupsButtonHeightConstraint: NSLayoutConstraint!
    @IBOutlet weak var externalSchemeButtonHeightConstraint: NSLayoutConstraint!
    @IBOutlet weak var wifiHotspotButtonHeightConstraint: NSLayoutConstraint!
    @IBOutlet private weak var permissionButtons: NSView!
    @IBOutlet weak var cameraButton: PermissionButton! {
        didSet {
            cameraButton.isHidden = true
            cameraButton.target = self
            cameraButton.action = #selector(cameraButtonAction(_:))
        }
    }
    @IBOutlet weak var microphoneButton: PermissionButton! {
        didSet {
            microphoneButton.isHidden = true
            microphoneButton.target = self
            microphoneButton.action = #selector(microphoneButtonAction(_:))
        }
    }
    @IBOutlet weak var geolocationButton: PermissionButton! {
        didSet {
            geolocationButton.isHidden = true
            geolocationButton.target = self
            geolocationButton.action = #selector(geolocationButtonAction(_:))
        }
    }
    @IBOutlet weak var popupsButton: PermissionButton! {
        didSet {
            popupsButton.isHidden = true
            popupsButton.target = self
            popupsButton.action = #selector(popupsButtonAction(_:))
        }
    }
    @IBOutlet weak var externalSchemeButton: PermissionButton! {
        didSet {
            externalSchemeButton.isHidden = true
            externalSchemeButton.target = self
            externalSchemeButton.action = #selector(externalSchemeButtonAction(_:))
        }
    }
    @IBOutlet weak var wifiHotspotButton: PermissionButton! {
        didSet {
            wifiHotspotButton.isHidden = true
            wifiHotspotButton.target = self
            wifiHotspotButton.action = #selector(wifiHotspotButtonAction(_:))
        }
    }

    @Published private(set) var buttonsWidth: CGFloat = 0
    @Published private(set) var trailingButtonsWidth: CGFloat = 0

    private let onboardingPixelReporter: OnboardingAddressBarReporting

    private var tabCollectionViewModel: TabCollectionViewModel
    private var tabViewModel: TabViewModel? {
        didSet {
            popovers?.closeZoomPopover()
            subscribeToTabZoomLevel()
        }
    }

    private let popovers: NavigationBarPopovers?
    private let bookmarkManager: BookmarkManager

    var controllerMode: AddressBarViewController.Mode? {
        didSet {
            updateButtons()
        }
    }
    var isTextFieldEditorFirstResponder = false {
        didSet {
            updateButtons()
            stopHighlightingPrivacyShield()
        }
    }
    var textFieldValue: AddressBarTextField.Value? {
        didSet {
            updateButtons()
        }
    }
    var isMouseOverNavigationBar = false {
        didSet {
            if isMouseOverNavigationBar != oldValue {
                updateBookmarkButtonVisibility()
            }
        }
    }

    var shouldShowDaxLogInAddressBar: Bool {
        self.tabViewModel?.tab.content == .newtab && visualStyle.addressBarStyleProvider.shouldShowNewSearchIcon
    }

    private var cancellables = Set<AnyCancellable>()
    private var urlCancellable: AnyCancellable?
    private var zoomLevelCancellable: AnyCancellable?
    private var permissionsCancellables = Set<AnyCancellable>()
    private var trackerAnimationTriggerCancellable: AnyCancellable?
    private var privacyEntryPointIconUpdateCancellable: AnyCancellable?

    private lazy var buttonsBadgeAnimator = {
        let animator = NavigationBarBadgeAnimator()
        animator.delegate = self
        return animator
    }()

    private var hasPrivacyInfoPulseQueuedAnimation = false

    required init?(coder: NSCoder) {
        fatalError("AddressBarButtonsViewController: Bad initializer")
    }

    private let aiChatTabOpener: AIChatTabOpening
    private let aiChatMenuConfig: AIChatMenuVisibilityConfigurable
    private let aiChatSidebarPresenter: AIChatSidebarPresenting

    init?(coder: NSCoder,
          tabCollectionViewModel: TabCollectionViewModel,
          bookmarkManager: BookmarkManager,
          privacyConfigurationManager: PrivacyConfigurationManaging,
          permissionManager: PermissionManagerProtocol,
          accessibilityPreferences: AccessibilityPreferences = AccessibilityPreferences.shared,
          tabsPreferences: TabsPreferences = TabsPreferences.shared,
          popovers: NavigationBarPopovers?,
          onboardingPixelReporter: OnboardingAddressBarReporting = OnboardingPixelReporter(),
          aiChatTabOpener: AIChatTabOpening,
          aiChatMenuConfig: AIChatMenuVisibilityConfigurable,
          aiChatSidebarPresenter: AIChatSidebarPresenting,
          visualStyle: VisualStyleProviding = NSApp.delegateTyped.visualStyle,
          featureFlagger: FeatureFlagger = NSApp.delegateTyped.featureFlagger) {
        self.tabCollectionViewModel = tabCollectionViewModel
        self.bookmarkManager = bookmarkManager
        self.accessibilityPreferences = accessibilityPreferences
        self.tabsPreferences = tabsPreferences
        self.popovers = popovers
        self.onboardingPixelReporter = onboardingPixelReporter
        self.aiChatTabOpener = aiChatTabOpener
        self.aiChatMenuConfig = aiChatMenuConfig
        self.aiChatSidebarPresenter = aiChatSidebarPresenter
        self.visualStyle = visualStyle
        self.featureFlagger = featureFlagger
        self.privacyConfigurationManager = privacyConfigurationManager
        self.permissionManager = permissionManager
        super.init(coder: coder)
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        setupAnimationViews()
        setupNotificationAnimationView()
        subscribeToSelectedTabViewModel()
        subscribeToBookmarkList()
        subscribeToEffectiveAppearance()
        subscribeToIsMouseOverAnimationVisible()
        updateBookmarkButtonVisibility()
        subscribeToPrivacyEntryPointIsMouseOver()
        subscribeToButtonsVisibility()
        subscribeToAIChatPreferences()
        subscribeToAIChatSidebarPresenter()
    }

    private func setupButtons() {
        if view.window?.isPopUpWindow == true {
            privacyDashboardButton.position = .free
            cameraButton.position = .free
            geolocationButton.position = .free
            popupsButton.position = .free
            microphoneButton.position = .free
            externalSchemeButton.position = .free
            wifiHotspotButton.position = .free
            bookmarkButton.isHidden = true
        } else {
            bookmarkButton.position = .right
            privacyDashboardButton.position = .left
        }

        privacyDashboardButton.sendAction(on: .leftMouseUp)

        (imageButton.cell as? NSButtonCell)?.highlightsBy = NSCell.StyleMask(rawValue: 0)

        cameraButton.sendAction(on: .leftMouseDown)
        cameraButton.setAccessibilityIdentifier("AddressBarButtonsViewController.cameraButton")
        cameraButton.setAccessibilityTitle(UserText.permissionCamera)
        microphoneButton.sendAction(on: .leftMouseDown)
        microphoneButton.setAccessibilityIdentifier("AddressBarButtonsViewController.microphoneButton")
        microphoneButton.setAccessibilityTitle(UserText.permissionMicrophone)
        geolocationButton.sendAction(on: .leftMouseDown)
        geolocationButton.setAccessibilityIdentifier("AddressBarButtonsViewController.geolocationButton")
        geolocationButton.setAccessibilityTitle(UserText.permissionGeolocation)
        popupsButton.sendAction(on: .leftMouseDown)
        popupsButton.setAccessibilityTitle(UserText.permissionPopups)
        popupsButton.setAccessibilityIdentifier("AddressBarButtonsViewController.popupsButton")
        externalSchemeButton.sendAction(on: .leftMouseDown)
        // externalSchemeButton.accessibilityTitle is set in `updatePermissionButtons`
        externalSchemeButton.setAccessibilityIdentifier("AddressBarButtonsViewController.externalSchemeButton")
        wifiHotspotButton.sendAction(on: .leftMouseDown)

        privacyDashboardButton.setAccessibilityRole(.button)
        privacyDashboardButton.setAccessibilityElement(true)
        privacyDashboardButton.setAccessibilityIdentifier("AddressBarButtonsViewController.privacyDashboardButton")
        privacyDashboardButton.setAccessibilityTitle(UserText.privacyDashboardButton)
        privacyDashboardButton.toolTip = UserText.privacyDashboardTooltip

        bookmarkButton.sendAction(on: .leftMouseDown)
        bookmarkButton.normalTintColor = visualStyle.colorsProvider.iconsColor
        bookmarkButton.setAccessibilityIdentifier("AddressBarButtonsViewController.bookmarkButton")
        // bookmarkButton.accessibilityTitle is set in `updateBookmarkButtonImage`

        configureAIChatButton()
        configureAskAIChatButton()
        configureContextMenuForAIChatButtons()

        setupButtonsCornerRadius()
        setupButtonsSize()
        setupButtonIcons()
        setupButtonPaddings()
    }

    func setupButtonPaddings(isFocused: Bool = false) {
        guard visualStyle.addressBarStyleProvider.shouldAddPaddingToAddressBarButtons else { return }

        imageButtonLeadingConstraint.constant = isFocused ? 2 : 1
        animationWrapperViewLeadingConstraint.constant = 1

        if let superview = privacyDashboardButton.superview {
            privacyDashboardButton.translatesAutoresizingMaskIntoConstraints = false
            privacyShieldLeadingConstraint.constant = isFocused ? 4 : 3
            NSLayoutConstraint.activate([
                privacyDashboardButton.topAnchor.constraint(equalTo: superview.topAnchor, constant: 2),
                privacyDashboardButton.bottomAnchor.constraint(equalTo: superview.bottomAnchor, constant: -2)
            ])
        }

        if let superview = aiChatButton.superview {
            aiChatButton.translatesAutoresizingMaskIntoConstraints = false
            trailingStackViewTrailingViewConstraint.constant = isFocused ? 4 : 3
            NSLayoutConstraint.activate([
                aiChatButton.topAnchor.constraint(equalTo: superview.topAnchor, constant: 2),
                aiChatButton.bottomAnchor.constraint(equalTo: superview.bottomAnchor, constant: -2)
            ])
        }
    }

    override func viewWillAppear() {
        setupButtons()
    }

    override func viewWillDisappear() {
        super.viewWillDisappear()

        // The permission popover leaks when its parent window is closed while it's still visible, so this workaround
        // forces it to deallocate when the window is closing. This workaround can be removed if the true source of
        // the leak is found.
        if let permissionAuthorizationPopover, permissionAuthorizationPopover.isShown {
            permissionAuthorizationPopover.close()
        }

        for case let .some(animationView) in [trackerAnimationView1, trackerAnimationView2, trackerAnimationView3, shieldDotAnimationView, shieldAnimationView] {
            animationView.stop()
        }
    }

    func showBadgeNotification(_ type: NavigationBarBadgeAnimationView.AnimationType) {
        if !isAnyShieldAnimationPlaying {
            buttonsBadgeAnimator.showNotification(withType: type,
                                                  buttonsContainer: buttonsContainer,
                                                  notificationBadgeContainer: notificationAnimationView)
        } else {
            buttonsBadgeAnimator.queuedAnimation = NavigationBarBadgeAnimator.QueueData(selectedTab: tabViewModel?.tab,
                                                                                        animationType: type)
        }
    }

    private func playBadgeAnimationIfNecessary() {
        if let queuedNotification = buttonsBadgeAnimator.queuedAnimation {
            // Add small time gap in between animations if badge animation was queued
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                if self.tabViewModel?.tab == queuedNotification.selectedTab {
                    self.showBadgeNotification(queuedNotification.animationType)
                } else {
                    self.buttonsBadgeAnimator.queuedAnimation = nil
                }
            }
        }
    }

    private func playPrivacyInfoHighlightAnimationIfNecessary() {
        if hasPrivacyInfoPulseQueuedAnimation {
            hasPrivacyInfoPulseQueuedAnimation = false
            // Give a bit of delay to have a better animation effect
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                ViewHighlighter.highlight(view: self.privacyDashboardButton, inParent: self.view)
            }
        }
    }

    var mouseEnterExitTrackingArea: NSTrackingArea?

    override func viewDidLayout() {
        super.viewDidLayout()
        if view.window?.isPopUpWindow == false {
            updateTrackingAreaForHover()
        }
        self.buttonsWidth = buttonsContainer.frame.size.width + 10.0
        self.trailingButtonsWidth = trailingButtonsContainer.frame.size.width + 14.0
    }

    func updateTrackingAreaForHover() {
        if let previous = mouseEnterExitTrackingArea {
            view.removeTrackingArea(previous)
        }
        let trackingArea = NSTrackingArea(rect: view.frame, options: [.mouseEnteredAndExited, .mouseMoved, .activeAlways], owner: view, userInfo: nil)
        view.addTrackingArea(trackingArea)
        mouseEnterExitTrackingArea = trackingArea
    }

    @IBAction func bookmarkButtonAction(_ sender: Any) {
        openBookmarkPopover(setFavorite: false, accessPoint: .button)
    }

    @IBAction func cancelButtonAction(_ sender: Any) {
        delegate?.addressBarButtonsViewControllerCancelButtonClicked(self)
    }

    @IBAction func privacyDashboardButtonAction(_ sender: Any) {
        openPrivacyDashboardPopover()
    }

    @IBAction func aiChatButtonAction(_ sender: Any) {
        guard let tab = tabViewModel?.tab else { return }

        // Close the sidebar if it's currently open and the user preference is set to open AI chat in new tabs
        // This ensures consistent behavior when the sidebar is unexpectedly open but shouldn't be the default action
        if !aiChatMenuConfig.shouldOpenAIChatInSidebar && aiChatSidebarPresenter.isSidebarOpen(for: tab.uuid) {
            aiChatSidebarPresenter.toggleSidebar()

            if aiChatButton == sender as? AddressBarMenuButton {
                return
            }
        }

        let behavior = createAIChatLinkOpenBehavior(for: tab)

        if featureFlagger.isFeatureOn(.aiChatSidebar),
           aiChatMenuConfig.shouldOpenAIChatInSidebar,
           !isTextFieldEditorFirstResponder,
           case .url = tab.content,
           behavior == .currentTab {
            // Toggle (open or close) the sidebar only when feature flag and setting option are enabled and:
            // - address bar text field is not in focus
            // - the current tab is displaying a standard web page (not a special page),
            // - intended link open behavior is to use the current tab
            toggleAIChatSidebar(for: tab)
        } else {
            // Otherwise open Duck.ai in a full tab
            openAIChatTab(for: tab, with: behavior)
        }

        delegate?.addressBarButtonsViewControllerAIChatButtonClicked(self)
        updateAskAIChatButtonVisibility()
    }

    // MARK: - AI Chat Action Helpers

    private func createAIChatLinkOpenBehavior(for tab: Tab) -> LinkOpenBehavior {
        let shouldSelectNewTab: Bool = {
            guard let url = tab.url else { return false }
            return !url.isDuckAIURL && tab.content != .newtab
        }()

        return LinkOpenBehavior(event: NSApp.currentEvent,
                                switchToNewTabWhenOpenedPreference: tabsPreferences.switchToNewTabWhenOpened,
                                shouldSelectNewTab: shouldSelectNewTab)
    }

    private func toggleAIChatSidebar(for tab: Tab) {
        let isSidebarCurrentlyOpen = aiChatSidebarPresenter.isSidebarOpen(for: tab.uuid)

        let pixel: AIChatPixel = isSidebarCurrentlyOpen ? .aiChatSidebarClosed(source: .addressBarButton) : .aiChatSidebarOpened(source: .addressBarButton)
        PixelKit.fire(pixel, frequency: .dailyAndStandard)
        if !isSidebarCurrentlyOpen {
            PixelKit.fire(AIChatPixel.aiChatAddressBarButtonClicked(action: .sidebar), frequency: .dailyAndStandard)
        }

        aiChatSidebarPresenter.toggleSidebar()
    }

    private func openAIChatTab(for tab: Tab, with behavior: LinkOpenBehavior) {
        // If the AI Chat sidebar is open and the intended behavior is to open in the current tab,
        // close the sidebar before opening Duck.ai in the current tab.
        if aiChatSidebarPresenter.isSidebarOpen(for: tab.uuid) && behavior == .currentTab {
            aiChatSidebarPresenter.collapseSidebar(withAnimation: false)
        }

        if let value = textFieldValue, !value.isEmpty {
            PixelKit.fire(AIChatPixel.aiChatAddressBarButtonClicked(action: .tabWithPrompt), frequency: .dailyAndStandard)
            aiChatTabOpener.openAIChatTab(value, with: behavior)
        } else {
            PixelKit.fire(AIChatPixel.aiChatAddressBarButtonClicked(action: .tab), frequency: .dailyAndStandard)
            aiChatTabOpener.openAIChatTab(nil, with: behavior)
        }
    }

    func openPrivacyDashboardPopover(entryPoint: PrivacyDashboardEntryPoint = .dashboard) {
        if let permissionAuthorizationPopover, permissionAuthorizationPopover.isShown {
            permissionAuthorizationPopover.close()
        }
        popupBlockedPopover?.close()

        popovers?.togglePrivacyDashboardPopover(for: tabViewModel, from: privacyDashboardButton, entryPoint: entryPoint)
        onboardingPixelReporter.measurePrivacyDashboardOpened()
        PixelKit.fire(NavigationBarPixel.privacyDashboardOpened, frequency: .daily)
    }

    private func setupButtonsCornerRadius() {
        let cornerRadius = visualStyle.addressBarStyleProvider.addressBarButtonsCornerRadius
        aiChatButton.setCornerRadius(cornerRadius)
        askAIChatButton.setCornerRadius(cornerRadius)
        bookmarkButton.setCornerRadius(cornerRadius)
        cancelButton.setCornerRadius(cornerRadius)
        permissionButtons.setCornerRadius(cornerRadius)
        zoomButton.setCornerRadius(cornerRadius)
        privacyDashboardButton.setCornerRadius(cornerRadius)
        wifiHotspotButton.setCornerRadius(cornerRadius)
    }

    private func setupButtonsSize() {
        bookmarkButtonWidthConstraint.constant = visualStyle.addressBarStyleProvider.addressBarButtonSize
        bookmarkButtonHeightConstraint.constant = visualStyle.addressBarStyleProvider.addressBarButtonSize
        cancelButtonWidthConstraint.constant = visualStyle.addressBarStyleProvider.addressBarButtonSize
        cancelButtonHeightConstraint.constant = visualStyle.addressBarStyleProvider.addressBarButtonSize
        aiChatButtonWidthConstraint.constant = visualStyle.addressBarStyleProvider.addressBarButtonSize
        aiChatButtonHeightConstraint.constant = visualStyle.addressBarStyleProvider.addressBarButtonSize
        askAIChatButtonWidthConstraint.constant = visualStyle.addressBarStyleProvider.addressBarButtonSize
        askAIChatButtonHeightConstraint.constant = visualStyle.addressBarStyleProvider.addressBarButtonSize
        privacyShieldButtonWidthConstraint.constant = visualStyle.addressBarStyleProvider.addressBarButtonSize
        privacyShieldButtonHeightConstraint.constant = visualStyle.addressBarStyleProvider.addressBarButtonSize
        zoomButtonHeightConstraint.constant = visualStyle.addressBarStyleProvider.addressBarButtonSize
        geolocationButtonHeightConstraint.constant = visualStyle.addressBarStyleProvider.addressBarButtonSize
        microphoneButtonHeightConstraint.constant = visualStyle.addressBarStyleProvider.addressBarButtonSize
        cameraButtonHeightConstraint.constant = visualStyle.addressBarStyleProvider.addressBarButtonSize
        popupsButtonHeightConstraint.constant = visualStyle.addressBarStyleProvider.addressBarButtonSize
        externalSchemeButtonHeightConstraint.constant = visualStyle.addressBarStyleProvider.addressBarButtonSize
        wifiHotspotButtonHeightConstraint.constant = visualStyle.addressBarStyleProvider.addressBarButtonSize
    }

    private func setupButtonIcons() {
        geolocationButton.activeImage = visualStyle.iconsProvider.addressBarButtonsIconsProvider.locationSolid
        geolocationButton.disabledImage = visualStyle.iconsProvider.addressBarButtonsIconsProvider.locationIcon
        geolocationButton.defaultImage = visualStyle.iconsProvider.addressBarButtonsIconsProvider.locationIcon
        externalSchemeButton.defaultImage = visualStyle.iconsProvider.addressBarButtonsIconsProvider.externalSchemeIcon
        popupsButton.defaultImage = visualStyle.iconsProvider.addressBarButtonsIconsProvider.popupsIcon
        wifiHotspotButton.defaultImage = visualStyle.iconsProvider.addressBarButtonsIconsProvider.wifiIcon
    }

    private func updateBookmarkButtonVisibility() {
        guard view.window?.isPopUpWindow == false else { return }
        let hasEmptyAddressBar = textFieldValue?.isEmpty ?? true
        var shouldShowBookmarkButton: Bool {
            guard let tabViewModel, tabViewModel.canBeBookmarked else { return false }

            var isUrlBookmarked = false
            if let url = tabViewModel.tab.content.userEditableUrl {
                let urlVariants = url.bookmarkButtonUrlVariants()

                // Check if any of the URL variants is bookmarked
                isUrlBookmarked = urlVariants.contains { variant in
                    return bookmarkManager.isUrlBookmarked(url: variant)
                }
            }

            return cancelButton.isHidden && !hasEmptyAddressBar && (isMouseOverNavigationBar || popovers?.isEditBookmarkPopoverShown == true || isUrlBookmarked)
        }

        bookmarkButton.isShown = shouldShowBookmarkButton
        updateAIChatDividerVisibility()
    }

    private func updateZoomButtonVisibility(animation: Bool = false) {
        let hasURL = tabViewModel?.tab.url != nil
        let isEditingMode = controllerMode?.isEditing ?? false
        let isTextFieldValueText = textFieldValue?.isText ?? false

        enum ZoomState { case zoomedIn, zoomedOut }
        var zoomState: ZoomState?
        if let zoomLevel = tabViewModel?.zoomLevel, zoomLevel != accessibilityPreferences.defaultPageZoom {
            zoomState = (zoomLevel > accessibilityPreferences.defaultPageZoom) ? .zoomedIn : .zoomedOut
        }

        let isPopoverShown = popovers?.isZoomPopoverShown == true
        let shouldShowZoom = hasURL
        && !isEditingMode
        && !isTextFieldValueText
        && !isTextFieldEditorFirstResponder
        && !animation
        && (zoomState != .none || isPopoverShown)

        zoomButton.image = (zoomState == .zoomedOut) ? visualStyle.iconsProvider.moreOptionsMenuIconsProvider.zoomOutIcon : visualStyle.iconsProvider.moreOptionsMenuIconsProvider.zoomInIcon
        zoomButton.backgroundColor = isPopoverShown ? .buttonMouseDown : nil
        zoomButton.mouseOverColor = isPopoverShown ? nil : .buttonMouseOver
        zoomButton.isHidden = !shouldShowZoom
        zoomButton.normalTintColor = visualStyle.colorsProvider.iconsColor
    }

    // Temporarily hide/display AI chat button (does not persist)
    func updateAIChatButtonVisibility(isHidden: Bool) {
        aiChatButton.isHidden = isHidden
        updateAIChatDividerVisibility()
    }

    private func updateAIChatButtonState() {
        guard let tab = tabViewModel?.tab, featureFlagger.isFeatureOn(.aiChatSidebar) else { return }
        let isShowingSidebar = aiChatSidebarPresenter.isSidebarOpen(for: tab.uuid)
        updateAIChatButtonForSidebar(isShowingSidebar)
    }

    private func updateAIChatButtonForSidebar(_ isShowingSidebar: Bool) {
        configureContextMenuForAIChatButtons(isSidebarOpen: isShowingSidebar)
        configureAIChatButtonTooltip(isSidebarOpen: isShowingSidebar)

        if isShowingSidebar {
            aiChatButton.setButtonType(.toggle)
            aiChatButton.state = .on
            aiChatButton.mouseOverColor = nil
        } else {
            aiChatButton.setButtonType(.momentaryPushIn)
            aiChatButton.state = .off
            aiChatButton.mouseOverColor = visualStyle.colorsProvider.buttonMouseOverColor
        }
    }

    private func updateAIChatButtonVisibility() {
        let isPopUpWindow = view.window?.isPopUpWindow ?? false
        let isDuckAIURL = tabViewModel?.tab.url?.isDuckAIURL ?? false

        aiChatButton.isHidden = !aiChatMenuConfig.shouldDisplayAddressBarShortcut || isPopUpWindow || isDuckAIURL
        updateAIChatDividerVisibility()

        // Check if the current tab is in the onboarding state and disable the AI chat button if it is
        guard let tabViewModel else { return }
        let isOnboarding = [.onboarding].contains(tabViewModel.tab.content)
        aiChatButton.isEnabled = !isOnboarding
    }

    private var isAskAIChatButtonExpanded: Bool = false

    private func updateAskAIChatButtonVisibility(isSidebarOpen: Bool? = nil) {
        // Early return if AI Chat sidebar feature is not enabled or not configured to show
        guard shouldShowAskAIChatButton() else {
            askAIChatButton.isHidden = true
            updateAIChatDividerVisibility()
            return
        }

        let isSidebarOpen: Bool = isSidebarOpen ?? {
            guard let tabID = tabViewModel?.tab.uuid else { return false }
            return aiChatSidebarPresenter.isSidebarOpen(for: tabID)
        }()

        updateAIChatButtonVisibilityForTextFieldState()
        updateAIChatDividerVisibility()

        if shouldExpandAskAIChatButton(isSidebarOpen: isSidebarOpen) {
            expandAskAIChatButton()
        } else {
            contractAskAIChatButton()
        }
    }

    // MARK: - Ask AI Chat Button Helper Methods

    private func shouldShowAskAIChatButton() -> Bool {
        return featureFlagger.isFeatureOn(.aiChatSidebar) &&
               aiChatMenuConfig.shouldDisplayAddressBarShortcut &&
               !(tabViewModel?.tab.url?.isDuckAIURL ?? false)
    }

    private func updateAIChatButtonVisibilityForTextFieldState() {
        if isTextFieldEditorFirstResponder {
            aiChatButton.isHidden = true
            askAIChatButton.isHidden = false
        } else {
            // aiChatButton visibility managed in updateAIChatButtonVisibility
            askAIChatButton.isHidden = true
        }
    }

    private func shouldExpandAskAIChatButton(isSidebarOpen: Bool) -> Bool {
        guard isTextFieldEditorFirstResponder,
              let textFieldValue = textFieldValue,
              !textFieldValue.isEmpty,
              textFieldValue.isUserTyped || textFieldValue.isSuggestion else {
            return false
        }
        return true
    }

    private func expandAskAIChatButton() {
        guard !isAskAIChatButtonExpanded else {
            // Ignore any subsequent calls to prevent duplicate animations
            return
        }
        isAskAIChatButtonExpanded = true

        askAIChatButton.isEnabled = true
        askAIChatButton.state = .off
        askAIChatButton.toolTip = nil
        askAIChatButton.backgroundColor = visualStyle.colorsProvider.fillButtonBackgroundColor
        askAIChatButton.mouseOverColor = visualStyle.colorsProvider.fillButtonMouseOverColor

        animateAskAIChatButtonExpansion()
    }

    private func contractAskAIChatButton() {
        askAIChatButton.backgroundColor = .clear
        askAIChatButton.mouseOverColor = visualStyle.colorsProvider.buttonMouseOverColor
        askAIChatButton.toolTip = ShortcutTooltip.askAIChat.value

        askAIChatButton.isEnabled = true
        askAIChatButton.state = .off

        guard isAskAIChatButtonExpanded else {
            // Ignore any subsequent calls if button is already contracted
            return
        }

        isAskAIChatButtonExpanded = false
        animateAskAIChatButtonContraction()
    }

    private func animateAskAIChatButtonExpansion() {
        configureAskAIChatButton()
        let targetWidth = calculateExpandedButtonWidth()

        NSAnimationContext.runAnimationGroup { context in
            context.allowsImplicitAnimation = true
            context.duration = Constants.askAiChatButtonAnimationDuration
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)

            askAIChatButtonWidthConstraint.animator().constant = targetWidth
        }
    }

    private func calculateExpandedButtonWidth() -> CGFloat {
        let fittingSize = askAIChatButton.sizeThatFits(
            CGSize(width: 1000, height: visualStyle.addressBarStyleProvider.addressBarButtonSize)
        )
        return max(fittingSize.width, visualStyle.addressBarStyleProvider.addressBarButtonSize)
    }

    private func animateAskAIChatButtonContraction() {
        NSAnimationContext.runAnimationGroup { context in
            context.allowsImplicitAnimation = true
            context.duration = Constants.askAiChatButtonAnimationDuration
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)

            askAIChatButtonWidthConstraint.animator().constant = visualStyle.addressBarStyleProvider.addressBarButtonSize
        } completionHandler: {
            guard !self.isAskAIChatButtonExpanded else { return }
            self.askAIChatButton.title = ""
        }
    }

    @objc func openAIChatContextMenuAction(_ sender: NSMenuItem) {
        // Open AI Chat action implementation - behavior opposite to default setting

        if aiChatMenuConfig.shouldOpenAIChatInSidebar {
            // Default is sidebar, menu action forces new tab
            let behavior = LinkOpenBehavior(
                event: NSApp.currentEvent,
                switchToNewTabWhenOpenedPreference: tabsPreferences.switchToNewTabWhenOpened,
                canOpenLinkInCurrentTab: false,
                shouldSelectNewTab: true
            )

            if let value = textFieldValue {
                aiChatTabOpener.openAIChatTab(value, with: behavior)
            } else {
                aiChatTabOpener.openAIChatTab(nil, with: behavior)
            }
        } else {
            if let tab = tabViewModel?.tab {
                let isSidebarCurrentlyOpen = aiChatSidebarPresenter.isSidebarOpen(for: tab.uuid)
                let pixel: AIChatPixel = isSidebarCurrentlyOpen ? .aiChatSidebarClosed(source: .contextMenu) : .aiChatSidebarOpened(source: .contextMenu)
                PixelKit.fire(pixel, frequency: .dailyAndStandard)
            }

            // Default is new tab, menu action forces sidebar
            aiChatSidebarPresenter.toggleSidebar()
        }
    }

    @objc func hideAIChatButtonAction(_ sender: NSMenuItem) {
        delegate?.addressBarButtonsViewControllerHideAIChatButtonClicked(self)
    }

    @objc func openAIChatSettingsContextMenuAction(_ sender: NSMenuItem) {
        delegate?.addressBarButtonsViewControllerOpenAIChatSettingsButtonClicked(self)
    }

    private func updateAIChatDividerVisibility() {
        // Prevent crash if Combine subscriptions outlive view lifecycle: https://app.asana.com/1/137249556945/project/1199230911884351/task/1210593147082728
        guard isViewLoaded else { return }

        leadingAIChatDivider.isHidden = aiChatButton.isHidden || bookmarkButton.isHidden

        if featureFlagger.isFeatureOn(.aiChatSidebar) {
            trailingAIChatDivider.isHidden = askAIChatButton.isHidden || cancelButton.isHidden
        } else {
            trailingAIChatDivider.isHidden = aiChatButton.isHidden || cancelButton.isHidden
        }
    }

    private func updateButtonsPosition() {
        cancelButton.position = .right
        askAIChatButton.position = .center

        if featureFlagger.isFeatureOn(.aiChatSidebar) {
            aiChatButton.position = .right
        } else {
            aiChatButton.position = cancelButton.isShown ? .center : .right
        }

        bookmarkButton.position = aiChatButton.isShown ? .center : .right
    }

    func openBookmarkPopover(setFavorite: Bool, accessPoint: GeneralPixel.AccessPoint) {
        guard let popovers else {
            return
        }
        let result = bookmarkForCurrentUrl(setFavorite: setFavorite, accessPoint: accessPoint)
        guard let bookmark = result.bookmark else {
            assertionFailure("Failed to get a bookmark for the popover")
            return
        }

        if popovers.isEditBookmarkPopoverShown {
            updateBookmarkButtonVisibility()
            popovers.closeEditBookmarkPopover()
        } else {
            popovers.showEditBookmarkPopover(with: bookmark, isNew: result.isNew, from: bookmarkButton, withDelegate: self)
        }
    }

    func openPermissionAuthorizationPopover(for query: PermissionAuthorizationQuery) {
        let button: PermissionButton

        lazy var popover: NSPopover = {
            let popover = self.permissionAuthorizationPopoverCreatingIfNeeded()
            popover.behavior = .applicationDefined
            return popover
        }()

        if query.permissions.contains(.camera)
            || (query.permissions.contains(.microphone) && microphoneButton.isHidden && cameraButton.isShown) {
            button = cameraButton
        } else {
            assert(query.permissions.count == 1)
            switch query.permissions.first {
            case .microphone:
                button = microphoneButton
            case .geolocation:
                button = geolocationButton
            case .popups:
                guard !query.wasShownOnce else { return }
                button = popupsButton
                popover = popupBlockedPopoverCreatingIfNeeded()
            case .externalScheme:
                button = externalSchemeButton
                query.shouldShowAlwaysAllowCheckbox = true
                query.shouldShowCancelInsteadOfDeny = true
            case .wifiHotspot:
                button = wifiHotspotButton
                query.shouldShowCancelInsteadOfDeny = true
            default:
                assertionFailure("Unexpected permissions")
                query.handleDecision(grant: false)
                return
            }
        }
        guard button.isVisible else { return }

        button.backgroundColor = .buttonMouseDown
        button.mouseOverColor = .buttonMouseDown
        (popover.contentViewController as? PermissionAuthorizationViewController)?.query = query

        DispatchQueue.main.asyncAfter(deadline: .now() + NSAnimationContext.current.duration) {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .maxY)
            query.wasShownOnce = true
        }
    }

    func closePrivacyDashboard() {
        popovers?.closePrivacyDashboard()
    }

    func openPrivacyDashboard() {
        guard let tabViewModel else { return }
        popovers?.openPrivacyDashboard(for: tabViewModel, from: privacyDashboardButton, entryPoint: .dashboard)
    }

    func openZoomPopover(source: ZoomPopover.Source) {
        guard let popovers,
              let tabViewModel = tabCollectionViewModel.selectedTabViewModel else { return }

        if let zoomPopover = popovers.zoomPopover, zoomPopover.isShown {
            // reschedule close timer for already shown popover
            zoomPopover.rescheduleCloseTimerIfNeeded()
            return
        }

        zoomButton.isShown = true
        popovers.showZoomPopover(for: tabViewModel, from: zoomButton, addressBar: parent?.view, withDelegate: self, source: source)
        updateZoomButtonVisibility()
    }

    func updateButtons() {
        stopAnimationsAfterFocus()

        if featureFlagger.isFeatureOn(.aiChatSidebar) {
            cancelButton.isShown = isTextFieldEditorFirstResponder
        } else {
            cancelButton.isShown = isTextFieldEditorFirstResponder && !textFieldValue.isEmpty
        }

        updateImageButton()
        updatePrivacyDashboardButton()
        updatePermissionButtons()
        updateBookmarkButtonVisibility()
        updateZoomButtonVisibility()
        updateAIChatButtonVisibility()
        updateAskAIChatButtonVisibility()
        updateButtonsPosition()
    }

    @IBAction func zoomButtonAction(_ sender: Any) {
        guard let popovers else { return }
        if popovers.isZoomPopoverShown {
            popovers.closeZoomPopover()
        } else {
            openZoomPopover(source: .toolbar)
        }
    }

    @IBAction func cameraButtonAction(_ sender: NSButton) {
        guard let tabViewModel else {
            assertionFailure("No selectedTabViewModel")
            return
        }
        if case .requested(let query) = tabViewModel.usedPermissions.camera {
            openPermissionAuthorizationPopover(for: query)
            return
        }

        var permissions = Permissions()
        permissions.camera = tabViewModel.usedPermissions.camera
        if microphoneButton.isHidden {
            permissions.microphone = tabViewModel.usedPermissions.microphone
        }

        let url = tabViewModel.tab.content.urlForWebView ?? .empty
        let domain = url.isFileURL ? .localhost : (url.host ?? "")

        PermissionContextMenu(permissionManager: permissionManager, permissions: permissions.map { ($0, $1) }, domain: domain, delegate: self)
            .popUp(positioning: nil, at: NSPoint(x: 0, y: sender.bounds.height), in: sender)
    }

    @IBAction func microphoneButtonAction(_ sender: NSButton) {
        guard let tabViewModel,
              let state = tabViewModel.usedPermissions.microphone
        else {
            Logger.general.error("Selected tab view model is nil or no microphone state")
            return
        }
        if case .requested(let query) = state {
            openPermissionAuthorizationPopover(for: query)
            return
        }

        let url = tabViewModel.tab.content.urlForWebView ?? .empty
        let domain = url.isFileURL ? .localhost : (url.host ?? "")

        PermissionContextMenu(permissionManager: permissionManager, permissions: [(.microphone, state)], domain: domain, delegate: self)
            .popUp(positioning: nil, at: NSPoint(x: 0, y: sender.bounds.height), in: sender)
    }

    @IBAction func geolocationButtonAction(_ sender: NSButton) {
        guard let tabViewModel,
              let state = tabViewModel.usedPermissions.geolocation
        else {
            Logger.general.error("Selected tab view model is nil or no geolocation state")
            return
        }
        if case .requested(let query) = state {
            openPermissionAuthorizationPopover(for: query)
            return
        }

        let url = tabViewModel.tab.content.urlForWebView ?? .empty
        let domain = url.isFileURL ? .localhost : (url.host ?? "")

        PermissionContextMenu(permissionManager: permissionManager, permissions: [(.geolocation, state)], domain: domain, delegate: self)
            .popUp(positioning: nil, at: NSPoint(x: 0, y: sender.bounds.height), in: sender)
    }

    @IBAction func popupsButtonAction(_ sender: NSButton) {
        guard let tabViewModel,
              let state = tabViewModel.usedPermissions.popups
        else {
            Logger.general.error("Selected tab view model is nil or no popups state")
            return
        }

        let permissions: [(PermissionType, PermissionState)]
        let domain: String
        if case .requested(let query) = state {
            domain = query.domain
            permissions = tabViewModel.tab.permissions.authorizationQueries.reduce(into: .init()) {
                guard $1.permissions.contains(.popups) else { return }
                $0.append( (.popups, .requested($1)) )
            }
        } else {
            let url = tabViewModel.tab.content.urlForWebView ?? .empty
            domain = url.isFileURL ? .localhost : (url.host ?? "")
            permissions = [(.popups, state)]
        }
        PermissionContextMenu(permissionManager: permissionManager, permissions: permissions, domain: domain, delegate: self)
            .popUp(positioning: nil, at: NSPoint(x: 0, y: sender.bounds.height), in: sender)
    }

    @IBAction func externalSchemeButtonAction(_ sender: NSButton) {
        guard let tabViewModel,
              let (permissionType, state) = tabViewModel.usedPermissions.first(where: { $0.key.isExternalScheme })
        else {
            Logger.general.error("Selected tab view model is nil or no externalScheme state")
            return
        }

        let permissions: [(PermissionType, PermissionState)]
        if case .requested(let query) = state {
            query.wasShownOnce = false
            openPermissionAuthorizationPopover(for: query)
            return
        }

        permissions = [(permissionType, state)]
        let url = tabViewModel.tab.content.urlForWebView ?? .empty
        let domain = url.isFileURL ? .localhost : (url.host ?? "")

        PermissionContextMenu(permissionManager: permissionManager, permissions: permissions, domain: domain, delegate: self)
            .popUp(positioning: nil, at: NSPoint(x: 0, y: sender.bounds.height), in: sender)
    }

    @IBAction func wifiHotspotButtonAction(_ sender: NSButton) {
        guard let tabViewModel,
              let state = tabViewModel.usedPermissions.wifiHotspot
        else {
            Logger.general.error("Selected tab view model is nil or no wifiHotspot state")
            return
        }

        if case .requested(let query) = state {
            openPermissionAuthorizationPopover(for: query)
            return
        }

        let url = tabViewModel.tab.content.urlForWebView ?? .empty
        let domain = url.isFileURL ? .localhost : (url.host ?? "")

        PermissionContextMenu(permissionManager: permissionManager, permissions: [(.wifiHotspot, state)], domain: domain, delegate: self)
            .popUp(positioning: nil, at: NSPoint(x: 0, y: sender.bounds.height), in: sender)
    }

    private var animationViewCache = [String: LottieAnimationView]()
    private func getAnimationView(for animationName: String) -> LottieAnimationView? {
        if let animationView = animationViewCache[animationName] {
            return animationView
        }

        guard let animationView = LottieAnimationView(named: animationName,
                                                      imageProvider: trackerAnimationImageProvider) else {
            assertionFailure("Missing animation file")
            return nil
        }

        animationViewCache[animationName] = animationView
        return animationView
    }

    private func setupNotificationAnimationView() {
        notificationAnimationView.alphaValue = 0.0
    }

    private func setupAnimationViews() {

        func addAndLayoutAnimationViewIfNeeded(animationView: LottieAnimationView?,
                                               animationName: String,
                                               // Default use of .mainThread to prevent high WindowServer Usage
                                               // Pending Fix with newer Lottie versions
                                               // https://app.asana.com/0/1177771139624306/1207024603216659/f
                                               renderingEngine: Lottie.RenderingEngineOption = .mainThread) -> LottieAnimationView {
            if let animationView = animationView, animationView.identifier?.rawValue == animationName {
                return animationView
            }

            animationView?.removeFromSuperview()

            let newAnimationView: LottieAnimationView
            // For unknown reason, this caused infinite execution of various unit tests.
            if AppVersion.runType.requiresEnvironment {
                newAnimationView = getAnimationView(for: animationName) ?? LottieAnimationView()
            } else {
                newAnimationView = LottieAnimationView()
            }
            newAnimationView.configuration = LottieConfiguration(renderingEngine: renderingEngine)
            animationWrapperView.addAndLayout(newAnimationView)
            newAnimationView.isHidden = true
            return newAnimationView
        }

        let isAquaMode = NSApp.effectiveAppearance.name == .aqua
        let style = visualStyle.addressBarStyleProvider.privacyShieldStyleProvider

        trackerAnimationView1 = addAndLayoutAnimationViewIfNeeded(animationView: trackerAnimationView1,
                                                                  animationName: isAquaMode ? "trackers-1" : "dark-trackers-1",
                                                                  renderingEngine: .mainThread)
        trackerAnimationView2 = addAndLayoutAnimationViewIfNeeded(animationView: trackerAnimationView2,
                                                                  animationName: isAquaMode ? "trackers-2" : "dark-trackers-2",
                                                                  renderingEngine: .mainThread)
        trackerAnimationView3 = addAndLayoutAnimationViewIfNeeded(animationView: trackerAnimationView3,
                                                                  animationName: isAquaMode ? "trackers-3" : "dark-trackers-3",
                                                                  renderingEngine: .mainThread)
        shieldAnimationView = addAndLayoutAnimationViewIfNeeded(animationView: shieldAnimationView,
                                                                animationName: style.animationForShield(forLightMode: isAquaMode))
        shieldDotAnimationView = addAndLayoutAnimationViewIfNeeded(animationView: shieldDotAnimationView,
                                                                   animationName: style.animationForShieldWithDot(forLightMode: isAquaMode))
    }

    private func subscribeToSelectedTabViewModel() {
        tabCollectionViewModel.$selectedTabViewModel.sink { [weak self] tabViewModel in
            guard let self else { return }

            stopAnimations()
            closePrivacyDashboard()

            self.tabViewModel = tabViewModel
            subscribeToUrl()
            subscribeToPermissions()
            subscribeToPrivacyEntryPointIconUpdateTrigger()

            updatePrivacyEntryPointIcon()
            updateAIChatButtonState()
        }.store(in: &cancellables)
    }

    private func subscribeToUrl() {
        guard let tabViewModel else {
            urlCancellable = nil
            return
        }
        urlCancellable = tabViewModel.tab.$content
            .combineLatest(tabViewModel.tab.$error)
            .sink { [weak self] _ in
                guard let self else { return }

                stopAnimations()
                updateBookmarkButtonImage()
                updateButtons()
                configureAIChatButton()
                subscribeToTrackerAnimationTrigger()
            }
    }

    private func subscribeToPermissions() {
        permissionsCancellables.removeAll(keepingCapacity: true)

        tabViewModel?.$usedPermissions.dropFirst().sink { [weak self] _ in
            self?.updatePermissionButtons()
        }.store(in: &permissionsCancellables)
        tabViewModel?.$permissionAuthorizationQuery.dropFirst().sink { [weak self] _ in
            self?.updatePermissionButtons()
        }.store(in: &permissionsCancellables)
    }

    private func subscribeToTrackerAnimationTrigger() {
        trackerAnimationTriggerCancellable = tabViewModel?.trackersAnimationTriggerPublisher
            .first()
            .sink { [weak self] _ in
                self?.animateTrackers()
            }
    }

    private func subscribeToPrivacyEntryPointIconUpdateTrigger() {
        privacyEntryPointIconUpdateCancellable = tabViewModel?.privacyEntryPointIconUpdateTrigger
            .sink { [weak self] _ in
                self?.updatePrivacyEntryPointIcon()
            }
    }

    private func subscribeToBookmarkList() {
        bookmarkManager.listPublisher.receive(on: DispatchQueue.main).sink { [weak self] _ in
            guard let self else { return }
            updateBookmarkButtonImage()
            updateBookmarkButtonVisibility()
        }.store(in: &cancellables)
    }

    // update Separator on Privacy Entry Point and other buttons appearance change
    private func subscribeToButtonsVisibility() {
        privacyDashboardButton.publisher(for: \.isHidden).asVoid()
            .merge(with: permissionButtons.publisher(for: \.frame).asVoid())
            .merge(with: zoomButton.publisher(for: \.isHidden).asVoid())
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in
                self?.updateSeparator()
            }
            .store(in: &cancellables)
    }

    private func subscribeToAIChatPreferences() {
        aiChatMenuConfig.valuesChangedPublisher
            .receive(on: DispatchQueue.main)
            .sink(receiveValue: { [weak self] in
                self?.updateAIChatButtonVisibility()
                self?.configureAIChatButton()
            }).store(in: &cancellables)
    }

    private func subscribeToAIChatSidebarPresenter() {
        aiChatSidebarPresenter.sidebarPresenceWillChangePublisher
            .sink { [weak self] change in
                guard let self, change.tabID == tabViewModel?.tab.uuid else {
                    return
                }
                updateAIChatButtonForSidebar(change.isShown)
                updateAskAIChatButtonVisibility(isSidebarOpen: change.isShown)
            }
            .store(in: &cancellables)
    }

    private func configureAIChatButton() {
        aiChatButton.sendAction(on: [.leftMouseUp, .otherMouseDown])
        aiChatButton.image = visualStyle.iconsProvider.navigationToolbarIconsProvider.aiChatButtonImage
        aiChatButton.mouseOverColor = visualStyle.colorsProvider.buttonMouseOverColor
        aiChatButton.normalTintColor = visualStyle.colorsProvider.iconsColor
        aiChatButton.setAccessibilityIdentifier("AddressBarButtonsViewController.aiChatButton")

        configureAIChatButtonTooltip()
    }

    private func configureAIChatButtonTooltip(isSidebarOpen: Bool? = nil) {
        if let tab = tabViewModel?.tab, featureFlagger.isFeatureOn(.aiChatSidebar) {
            let isSidebarOpen: Bool = isSidebarOpen ?? {
                guard let tabID = tabViewModel?.tab.uuid else { return false }
                return aiChatSidebarPresenter.isSidebarOpen(for: tabID)
            }()

            if isSidebarOpen {
                aiChatButton.toolTip = UserText.aiChatCloseSidebarButton
                aiChatButton.setAccessibilityTitle(UserText.aiChatCloseSidebarButton)
            } else if aiChatMenuConfig.shouldOpenAIChatInSidebar, case .url = tab.content {
                aiChatButton.toolTip = UserText.aiChatOpenSidebarButton
                aiChatButton.setAccessibilityTitle(UserText.aiChatOpenSidebarButton)
            } else {
                aiChatButton.toolTip = isTextFieldEditorFirstResponder ? ShortcutTooltip.askAIChat.value : ShortcutTooltip.newAIChatTab.value
                aiChatButton.setAccessibilityTitle(UserText.aiChatAddressBarTrustedIndicator)
            }
        } else {
            aiChatButton.toolTip = isTextFieldEditorFirstResponder ? ShortcutTooltip.askAIChat.value : ShortcutTooltip.newAIChatTab.value
            aiChatButton.setAccessibilityTitle(UserText.aiChatAddressBarTrustedIndicator)
        }
    }

    private func configureAskAIChatButton() {
        askAIChatButton.image = visualStyle.iconsProvider.navigationToolbarIconsProvider.aiChatButtonImage.withPadding(left: Constants.askAiChatButtonHorizontalPadding)

        askAIChatButton.imageHugsTitle = true
        askAIChatButton.imagePosition = .imageLeading
        askAIChatButton.imageScaling = .scaleNone

        let attributedTitle = NSMutableAttributedString(string: " ")

        // Configure text truncation required for smoother animation
        if let buttonCell = askAIChatButton.cell as? NSButtonCell {
            buttonCell.lineBreakMode = .byClipping
            buttonCell.truncatesLastVisibleLine = false
        }

        askAIChatButton.attributedTitle = {
            // Main text in normal color
            let mainAttributes: [NSAttributedString.Key: Any] = [
                .foregroundColor: visualStyle.colorsProvider.textPrimaryColor,
                .font: NSFont.systemFont(ofSize: NSFont.systemFontSize)
            ]

            // Shortcut text in secondary color
            let shortcutAttributes: [NSAttributedString.Key: Any] = [
                .foregroundColor: visualStyle.colorsProvider.textTertiaryColor,
                .font: NSFont.systemFont(ofSize: NSFont.systemFontSize)
            ]

            attributedTitle.append(NSAttributedString(string: UserText.askAIChatButtonTitle, attributes: mainAttributes))
            attributedTitle.append(NSAttributedString(string: " "))
            attributedTitle.append(NSAttributedString(string: "⇧↵", attributes: shortcutAttributes))

            // Add invisible character to prevent whitespace trimming which causes animation glitches
            // The trailing whitespace gets trimmed by the system, so we use a clear-colored dot instead to add padding
            let invisibleAttributes: [NSAttributedString.Key: Any] = [
                .foregroundColor: NSColor.clear,
                .font: NSFont.systemFont(ofSize: NSFont.systemFontSize)
            ]

            attributedTitle.append(NSAttributedString(string: ".", attributes: invisibleAttributes))

            return attributedTitle
        }()
        askAIChatButton.setAccessibilityIdentifier("AddressBarButtonsViewController.askAIChatButton")
    }

    private func configureContextMenuForAIChatButtons(isSidebarOpen: Bool? = nil) {
        guard featureFlagger.isFeatureOn(.aiChatSidebar) else {

            aiChatButton.menu = NSMenu {
                NSMenuItem(title: UserText.aiChatAddressBarHideButton,
                           action: #selector(hideAIChatButtonAction(_:)),
                           keyEquivalent: "")
            }

            return
        }

        let shouldShowOpenAIChatButton: Bool = {
            guard let tabContent = tabViewModel?.tab.content, case .url = tabContent else {
                return false
            }
            return true
        }()

        let contextMenu = NSMenu {
            if shouldShowOpenAIChatButton {
                let contextMenuTitle: String = {
                    if aiChatMenuConfig.shouldOpenAIChatInSidebar {
                        return UserText.aiChatOpenNewTabButton
                    } else {
                        // Check if sidebar is currently open for this tab
                        guard let tab = tabViewModel?.tab else {
                            return UserText.aiChatOpenSidebarButton
                        }
                        let isShowingSidebar = isSidebarOpen ?? aiChatSidebarPresenter.isSidebarOpen(for: tab.uuid)
                        return isShowingSidebar ? UserText.aiChatCloseSidebarButton : UserText.aiChatOpenSidebarButton
                    }
                }()

                NSMenuItem(title: contextMenuTitle,
                           action: #selector(openAIChatContextMenuAction(_:)),
                           keyEquivalent: "")
            }
            NSMenuItem(title: UserText.aiChatAddressBarHideButton,
                       action: #selector(hideAIChatButtonAction(_:)),
                       keyEquivalent: "")
            NSMenuItem.separator()
            NSMenuItem(title: UserText.aiChatOpenSettingsButton,
                       action: #selector(openAIChatSettingsContextMenuAction(_:)),
                       keyEquivalent: "")
        }

        aiChatButton.menu = contextMenu
        askAIChatButton.menu = contextMenu
    }

    private func updatePermissionButtons() {
        guard let tabViewModel else { return }

        permissionButtons.isShown = !isTextFieldEditorFirstResponder
        && !isAnyTrackerAnimationPlaying
        && (!tabViewModel.isShowingErrorPage || tabViewModel.usedPermissions.wifiHotspot?.isRequested == true)
        defer {
            showOrHidePermissionPopoverIfNeeded()
        }

        geolocationButton.buttonState = tabViewModel.usedPermissions.geolocation

        let (camera, microphone) = PermissionState?.combineCamera(tabViewModel.usedPermissions.camera,
                                                                  withMicrophone: tabViewModel.usedPermissions.microphone)
        cameraButton.buttonState = camera
        microphoneButton.buttonState = microphone

        popupsButton.buttonState = tabViewModel.usedPermissions.popups?.isRequested == true // show only when there're popups blocked
        ? tabViewModel.usedPermissions.popups
        : nil
        externalSchemeButton.buttonState = tabViewModel.usedPermissions.externalScheme
        let title = String(format: UserText.permissionExternalSchemeOpenFormat, tabViewModel.usedPermissions.first(where: { $0.key.isExternalScheme })?.key.localizedDescription ?? "")
        externalSchemeButton.setAccessibilityTitle(title)
        wifiHotspotButton.buttonState = tabViewModel.usedPermissions.wifiHotspot

        geolocationButton.normalTintColor = visualStyle.colorsProvider.iconsColor
        cameraButton.normalTintColor = visualStyle.colorsProvider.iconsColor
        microphoneButton.normalTintColor = visualStyle.colorsProvider.iconsColor
        wifiHotspotButton.normalTintColor = visualStyle.colorsProvider.iconsColor
    }

    private func showOrHidePermissionPopoverIfNeeded() {
        guard let tabViewModel else { return }

        for permission in tabViewModel.usedPermissions.keys {
            guard case .requested(let query) = tabViewModel.usedPermissions[permission] else { continue }
            let permissionAuthorizationPopover = permissionAuthorizationPopoverCreatingIfNeeded()
            guard !permissionAuthorizationPopover.isShown else {
                if permissionAuthorizationPopover.viewController.query === query { return }
                permissionAuthorizationPopover.close()
                return
            }
            openPermissionAuthorizationPopover(for: query)
            return
        }
        if let permissionAuthorizationPopover, permissionAuthorizationPopover.isShown {
            permissionAuthorizationPopover.close()
        }

    }

    private func updateBookmarkButtonImage(isUrlBookmarked: Bool = false) {
        if let url = tabViewModel?.tab.content.userEditableUrl,
           isUrlBookmarked || bookmarkManager.isAnyUrlVariantBookmarked(url: url)
        {
            bookmarkButton.image = visualStyle.iconsProvider.bookmarksIconsProvider.bookmarkFilledIcon
            bookmarkButton.mouseOverTintColor = NSColor.bookmarkFilledTint
            bookmarkButton.toolTip = UserText.editBookmarkTooltip
            bookmarkButton.setAccessibilityValue("Bookmarked")
            bookmarkButton.setAccessibilityTitle(UserText.editBookmarkTooltip)
        } else {
            bookmarkButton.mouseOverTintColor = nil
            bookmarkButton.image = visualStyle.iconsProvider.bookmarksIconsProvider.bookmarkIcon
            bookmarkButton.contentTintColor = visualStyle.colorsProvider.iconsColor
            bookmarkButton.toolTip = ShortcutTooltip.bookmarkThisPage.value
            bookmarkButton.setAccessibilityValue("Unbookmarked")
            bookmarkButton.setAccessibilityTitle(UserText.addBookmarkTooltip)
        }
    }

    private func updateImageButton() {
        guard let tabViewModel else { return }

        imageButton.contentTintColor = visualStyle.colorsProvider.iconsColor
        imageButton.image = nil
        switch controllerMode {
        case .browsing where tabViewModel.isShowingErrorPage:
            imageButton.image = .web
        case .browsing:
            if let favicon = tabViewModel.favicon {
                imageButton.image = favicon
            } else {
                imageButton.image = .web
            }
        case .editing(.url):
            imageButton.image = .web
        case .editing(.text):
            if visualStyle.addressBarStyleProvider.shouldShowNewSearchIcon {
                imageButton.image = visualStyle.addressBarStyleProvider.addressBarLogoImage
            } else {
                imageButton.image = .search
            }
        case .editing(.openTabSuggestion):
            imageButton.image = .openTabSuggestion
        default:
            imageButton.image = nil
        }
    }

    private func updatePrivacyDashboardButton() {
        guard let tabViewModel else { return }

        let url = tabViewModel.tab.content.userEditableUrl
        let isNewTabOrOnboarding = [.newtab, .onboarding].contains(tabViewModel.tab.content)
        let isHypertextUrl = url?.navigationalScheme?.isHypertextScheme == true && url?.isDuckPlayer == false
        let isEditingMode = controllerMode?.isEditing ?? false
        let isTextFieldValueText = textFieldValue?.isText ?? false
        let isLocalUrl = url?.isLocalURL ?? false

        // Privacy entry point button
        let isFlaggedAsMalicious = (tabViewModel.tab.privacyInfo?.malicousSiteThreatKind != .none)
        privacyDashboardButton.isAnimationEnabled = !isFlaggedAsMalicious
        privacyDashboardButton.normalTintColor = isFlaggedAsMalicious ? .fireButtonRedPressed : .privacyEnabled
        privacyDashboardButton.mouseOverTintColor = isFlaggedAsMalicious ? .alertRedHover : privacyDashboardButton.mouseOverTintColor
        privacyDashboardButton.mouseDownTintColor = isFlaggedAsMalicious ? .alertRedPressed : privacyDashboardButton.mouseDownTintColor

        privacyDashboardButton.isShown = !isEditingMode
        && !isTextFieldEditorFirstResponder
        && isHypertextUrl
        && !tabViewModel.isShowingErrorPage
        && !isTextFieldValueText
        && !isLocalUrl

        imageButtonWrapper.isShown = imageButton.image != nil
        && view.window?.isPopUpWindow != true
        && (isHypertextUrl || isTextFieldEditorFirstResponder || isEditingMode || isNewTabOrOnboarding)
        && privacyDashboardButton.isHidden
        && !isAnyTrackerAnimationPlaying
    }

    private func updatePrivacyEntryPointIcon() {
        let privacyShieldStyle = visualStyle.addressBarStyleProvider.privacyShieldStyleProvider
        guard AppVersion.runType.requiresEnvironment else { return }
        privacyDashboardButton.image = nil

        guard let tabViewModel else { return }
        guard !isAnyShieldAnimationPlaying else { return }

        switch tabViewModel.tab.content {
        case .url(let url, _, _), .identityTheftRestoration(let url), .subscription(let url), .aiChat(let url):
            guard let host = url.host else { break }

            let isNotSecure = url.scheme == URL.NavigationalScheme.http.rawValue
            let isCertificateInvalid = tabViewModel.tab.isCertificateInvalid
            let isFlaggedAsMalicious = (tabViewModel.tab.privacyInfo?.malicousSiteThreatKind != .none)
            let configuration = privacyConfigurationManager.privacyConfig
            let isUnprotected = configuration.isUserUnprotected(domain: host)

            let isShieldDotVisible = isNotSecure || isUnprotected || isCertificateInvalid

            if isFlaggedAsMalicious {
                privacyDashboardButton.isAnimationEnabled = false
                privacyDashboardButton.image = .redAlertCircle16
                privacyDashboardButton.normalTintColor = .alertRed
                privacyDashboardButton.mouseOverTintColor = .alertRedHover
                privacyDashboardButton.mouseDownTintColor = .alertRedPressed
            } else {
                privacyDashboardButton.image = isShieldDotVisible ? privacyShieldStyle.iconWithDot : privacyShieldStyle.icon
                privacyDashboardButton.isAnimationEnabled = true

                let animationNames = MouseOverAnimationButton.AnimationNames(
                    aqua: isShieldDotVisible ? privacyShieldStyle.hoverAnimationWithDot(forLightMode: true) : privacyShieldStyle.hoverAnimation(forLightMode: true),
                    dark: isShieldDotVisible ? privacyShieldStyle.hoverAnimationWithDot(forLightMode: false) : privacyShieldStyle.hoverAnimation(forLightMode: false)
                )
                privacyDashboardButton.animationNames = animationNames
            }
        default:
            break
        }
    }

    private func updateSeparator() {
        separator.isShown = privacyDashboardButton.isVisible && (
            (permissionButtons.subviews.contains(where: { $0.isVisible })) || zoomButton.isVisible
        )
    }

    // MARK: Tracker Animation

    let trackerAnimationImageProvider = TrackerAnimationImageProvider()

    private func animateTrackers() {
        guard privacyDashboardButton.isShown, let tabViewModel else { return }

        switch tabViewModel.tab.content {
        case .url(let url, _, _):
            // Don't play the shield animation if mouse is over
            guard !privacyDashboardButton.isAnimationViewVisible else {
                break
            }

            var animationView: LottieAnimationView
            if url.navigationalScheme == .http {
                animationView = shieldDotAnimationView
            } else {
                animationView = shieldAnimationView
            }

            animationView.isHidden = false
            updateZoomButtonVisibility(animation: true)
            animationView.play { [weak self] _ in
                animationView.isHidden = true
                self?.updateZoomButtonVisibility(animation: false)
            }
        default:
            return
        }

        if let trackerInfo = tabViewModel.tab.privacyInfo?.trackerInfo {
            let lastTrackerImages = PrivacyIconViewModel.trackerImages(from: trackerInfo)
            trackerAnimationImageProvider.lastTrackerImages = lastTrackerImages

            let trackerAnimationView: LottieAnimationView?
            switch lastTrackerImages.count {
            case 0: trackerAnimationView = nil
            case 1: trackerAnimationView = trackerAnimationView1
            case 2: trackerAnimationView = trackerAnimationView2
            default: trackerAnimationView = trackerAnimationView3
            }
            trackerAnimationView?.isHidden = false
            trackerAnimationView?.reloadImages()
            self.updateZoomButtonVisibility(animation: true)
            trackerAnimationView?.play { [weak self] _ in
                trackerAnimationView?.isHidden = true
                guard let self else { return }
                updatePrivacyEntryPointIcon()
                updatePermissionButtons()
                // If badge animation is not queueued check if we should animate the privacy shield
                if buttonsBadgeAnimator.queuedAnimation == nil {
                    playPrivacyInfoHighlightAnimationIfNecessary()
                }
                playBadgeAnimationIfNecessary()
                updateZoomButtonVisibility(animation: false)
            }
        }

        updatePrivacyEntryPointIcon()
        updatePermissionButtons()
    }

    private func stopAnimations(trackerAnimations: Bool = true,
                                shieldAnimations: Bool = true,
                                badgeAnimations: Bool = true) {
        func stopAnimation(_ animationView: LottieAnimationView) {
            if animationView.isAnimationPlaying || animationView.isShown {
                animationView.isHidden = true
                animationView.stop()
            }
        }

        if trackerAnimations {
            stopAnimation(trackerAnimationView1)
            stopAnimation(trackerAnimationView2)
            stopAnimation(trackerAnimationView3)
        }
        if shieldAnimations {
            stopAnimation(shieldAnimationView)
            stopAnimation(shieldDotAnimationView)
        }
        if badgeAnimations {
            stopNotificationBadgeAnimations()
        }
    }

    private func stopNotificationBadgeAnimations() {
        notificationAnimationView.removeAnimation()
        buttonsBadgeAnimator.queuedAnimation = nil
    }

    private var isAnyTrackerAnimationPlaying: Bool {
        trackerAnimationView1.isAnimationPlaying ||
        trackerAnimationView2.isAnimationPlaying ||
        trackerAnimationView3.isAnimationPlaying
    }

    private var isAnyShieldAnimationPlaying: Bool {
        shieldAnimationView.isAnimationPlaying ||
        shieldDotAnimationView.isAnimationPlaying
    }

    private func stopAnimationsAfterFocus() {
        if isTextFieldEditorFirstResponder {
            stopAnimations()
        }
    }

    private func bookmarkForCurrentUrl(setFavorite: Bool, accessPoint: GeneralPixel.AccessPoint) -> (bookmark: Bookmark?, isNew: Bool) {
        guard let tabViewModel,
              let url = tabViewModel.tab.content.userEditableUrl else {
            assertionFailure("No URL for bookmarking")
            return (nil, false)
        }

        if let bookmark = bookmarkManager.getBookmark(forVariantUrl: url) {
            if setFavorite {
                bookmark.isFavorite = true
                bookmarkManager.update(bookmark: bookmark)
            }

            return (bookmark, false)
        }

        let lastUsedFolder = UserDefaultsBookmarkFoldersStore().lastBookmarkSingleTabFolderIdUsed.flatMap(bookmarkManager.getBookmarkFolder)
        let bookmark = bookmarkManager.makeBookmark(for: url,
                                                    title: tabViewModel.title,
                                                    isFavorite: setFavorite,
                                                    index: nil,
                                                    parent: lastUsedFolder)
        updateBookmarkButtonImage(isUrlBookmarked: bookmark != nil)

        return (bookmark, true)
    }

    private func subscribeToEffectiveAppearance() {
        NSApp.publisher(for: \.effectiveAppearance)
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.setupAnimationViews()
                self?.updatePrivacyEntryPointIcon()
                self?.updateZoomButtonVisibility()
                self?.configureAskAIChatButton()
            }
            .store(in: &cancellables)
    }

    private func subscribeToTabZoomLevel() {
        zoomLevelCancellable = tabViewModel?.zoomLevelSubject
            .sink { [weak self] _ in
                self?.updateZoomButtonVisibility()
            }
    }

    private func subscribeToIsMouseOverAnimationVisible() {
        privacyDashboardButton.$isAnimationViewVisible
            .dropFirst()
            .sink { [weak self] isAnimationViewVisible in

                if isAnimationViewVisible {
                    self?.stopAnimations(trackerAnimations: false, shieldAnimations: true, badgeAnimations: false)
                } else {
                    self?.updatePrivacyEntryPointIcon()
                }
            }
            .store(in: &cancellables)
    }

    private func subscribeToPrivacyEntryPointIsMouseOver() {
        privacyDashboardButton.publisher(for: \.isMouseOver)
            .first(where: { $0 }) // only interested when mouse is over
            .sink(receiveValue: { [weak self] _ in
                self?.stopHighlightingPrivacyShield()
            })
            .store(in: &cancellables)
    }

}

// MARK: - Contextual Onboarding View Highlight

extension AddressBarButtonsViewController {

    func highlightPrivacyShield() {
        if !isAnyShieldAnimationPlaying && buttonsBadgeAnimator.queuedAnimation == nil {
            ViewHighlighter.highlight(view: privacyDashboardButton, inParent: self.view)
        } else {
            hasPrivacyInfoPulseQueuedAnimation = true
        }
    }

    func stopHighlightingPrivacyShield() {
        hasPrivacyInfoPulseQueuedAnimation = false
        ViewHighlighter.stopHighlighting(view: privacyDashboardButton)
    }

}

// MARK: - NavigationBarBadgeAnimatorDelegate

extension AddressBarButtonsViewController: NavigationBarBadgeAnimatorDelegate {

    func didFinishAnimating() {
        playPrivacyInfoHighlightAnimationIfNecessary()
    }

}

// MARK: - PermissionContextMenuDelegate

extension AddressBarButtonsViewController: PermissionContextMenuDelegate {

    func permissionContextMenu(_ menu: PermissionContextMenu, mutePermissions permissions: [PermissionType]) {
        tabViewModel?.tab.permissions.set(permissions, muted: true)
    }
    func permissionContextMenu(_ menu: PermissionContextMenu, unmutePermissions permissions: [PermissionType]) {
        tabViewModel?.tab.permissions.set(permissions, muted: false)
    }
    func permissionContextMenu(_ menu: PermissionContextMenu, allowPermissionQuery query: PermissionAuthorizationQuery) {
        tabViewModel?.tab.permissions.allow(query)
    }
    func permissionContextMenu(_ menu: PermissionContextMenu, alwaysAllowPermission permission: PermissionType) {
        permissionManager.setPermission(.allow, forDomain: menu.domain, permissionType: permission)
    }
    func permissionContextMenu(_ menu: PermissionContextMenu, alwaysDenyPermission permission: PermissionType) {
        permissionManager.setPermission(.deny, forDomain: menu.domain, permissionType: permission)
    }
    func permissionContextMenu(_ menu: PermissionContextMenu, resetStoredPermission permission: PermissionType) {
        permissionManager.setPermission(.ask, forDomain: menu.domain, permissionType: permission)
    }
    func permissionContextMenuReloadPage(_ menu: PermissionContextMenu) {
        tabViewModel?.reload()
    }

}

// MARK: - NSPopoverDelegate

extension AddressBarButtonsViewController: NSPopoverDelegate {

    func popoverDidClose(_ notification: Notification) {
        guard let popovers, let popover = notification.object as? NSPopover else { return }

        switch popover {
        case popovers.bookmarkPopover:
            if popovers.bookmarkPopover?.isNew == true {
                NotificationCenter.default.post(name: .bookmarkPromptShouldShow, object: nil)
            }
            updateBookmarkButtonVisibility()
        case popovers.zoomPopover:
            updateZoomButtonVisibility()
        case is PermissionAuthorizationPopover,
            is PopupBlockedPopover:
            if let button = popover.positioningView as? PermissionButton {
                button.backgroundColor = .clear
                button.mouseOverColor = .buttonMouseOver
            } else {
                assertionFailure("Unexpected popover positioningView: \(popover.positioningView?.description ?? "<nil>"), expected PermissionButton")
            }
        default:
            break
        }
    }

}

// MARK: - AnimationImageProvider

final class TrackerAnimationImageProvider: AnimationImageProvider {

    var lastTrackerImages = [CGImage]()

    func imageForAsset(asset: ImageAsset) -> CGImage? {
        switch asset.name {
        case "img_0.png": return lastTrackerImages[safe: 0]
        case "img_1.png": return lastTrackerImages[safe: 1]
        case "img_2.png": return lastTrackerImages[safe: 2]
        case "img_3.png": return lastTrackerImages[safe: 3]
        default: return nil
        }
    }

}

// MARK: - URL Helpers

extension URL {
    private static let localPatterns = [
        "^localhost$",
        "^::1$",
        "^.+\\.local$",
        "^localhost\\.localhost$",
        "^127\\.0\\.0\\.1$",
        "^10\\.(25[0-5]|2[0-4][0-9]|1[0-9][0-9]|[1-9][0-9]?|0)\\.(25[0-5]|2[0-4][0-9]|1[0-9][0-9]|[1-9][0-9]?|0)\\.(25[0-5]|2[0-4][0-9]|1[0-9][0-9]|[1-9][0-9]?|0)$",
        "^172\\.(1[6-9]|2[0-9]|3[0-1])\\.(25[0-5]|2[0-4][0-9]|1[0-9][0-9]|[1-9][0-9]?|0)\\.(25[0-5]|2[0-4][0-9]|1[0-9][0-9]|[1-9][0-9]?|0)$",
        "^192\\.168\\.(25[0-5]|2[0-4][0-9]|1[0-9][0-9]|[1-9][0-9]?|0)\\.(25[0-5]|2[0-4][0-9]|1[0-9][0-9]|[1-9][0-9]?|0)$",
        "^169\\.254\\.(25[0-5]|2[0-4][0-9]|1[0-9][0-9]|[1-9][0-9]?|0)\\.(25[0-5]|2[0-4][0-9]|1[0-9][0-9]|[1-9][0-9]?|0)$",
        "^fc[0-9a-fA-F]{2}:.+",
        "^fe80:.+"
    ]

    private static var compiledRegexes: [NSRegularExpression] = {
        var regexes: [NSRegularExpression] = []
        for pattern in localPatterns {
            if let newRegex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) {
                regexes.append(newRegex)
            }
        }
        return regexes
    }()

    var isLocalURL: Bool {
        if let host = self.host {
            for regex in Self.compiledRegexes
            where regex.firstMatch(in: host, options: [], range: host.fullRange) != nil {
                return true
            }
        }
        return false
    }
}
