//
//  WindowsManager.swift
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

import Cocoa
import BrowserServicesKit

@MainActor
final class WindowsManager {

    class var windows: [NSWindow] {
        NSApplication.shared.windows
    }

    class var mainWindows: [MainWindow] {
        NSApplication.shared.windows.compactMap { $0 as? MainWindow }
    }

    // Shared type to enable managing `PasswordManagementPopover`s in multiple windows
    private static let autofillPopoverPresenter: AutofillPopoverPresenter = DefaultAutofillPopoverPresenter()

    class func closeWindows(except windows: [NSWindow] = []) {
        for controller in Application.appDelegate.windowControllersManager.mainWindowControllers {
            guard let window = controller.window, !windows.contains(window) else { continue }
            controller.close()
        }
    }

    /// finds window to position newly opened (or popup) windows against
    private class func findPositioningSourceWindow(for tab: Tab?) -> NSWindow? {
        if let parentTab = tab?.parentTab,
           let sourceWindowController = Application.appDelegate.windowControllersManager.mainWindowControllers.first(where: {
               $0.mainViewController.tabCollectionViewModel.tabs.contains(parentTab)
           }) {
            // window that initiated the new window opening
            return sourceWindowController.window
        }

        // fallback to last known main window
        return Application.appDelegate.windowControllersManager.lastKeyMainWindowController?.window
    }

    @discardableResult
    class func openNewWindow(with tabCollectionViewModel: TabCollectionViewModel? = nil,
                             aiChatSidebarProvider: AIChatSidebarProviding = Application.appDelegate.aiChatSidebarProvider,
                             fireCoordinator: FireCoordinator = Application.appDelegate.fireCoordinator,
                             burnerMode: BurnerMode = .regular,
                             droppingPoint: NSPoint? = nil,
                             contentSize: NSSize? = nil,
                             showWindow: Bool = true,
                             popUp: Bool = false,
                             lazyLoadTabs: Bool = false,
                             isMiniaturized: Bool = false,
                             isMaximized: Bool = false,
                             isFullscreen: Bool = false) -> NSWindow? {
        let mainWindowController = makeNewWindow(tabCollectionViewModel: tabCollectionViewModel,
                                                 popUp: popUp,
                                                 burnerMode: burnerMode,
                                                 autofillPopoverPresenter: autofillPopoverPresenter,
                                                 fireCoordinator: fireCoordinator,
                                                 aiChatSidebarProvider: aiChatSidebarProvider)

        if let contentSize {
            mainWindowController.window?.setContentSize(contentSize)
        }

        mainWindowController.window?.setIsMiniaturized(isMiniaturized)

        if isMaximized {
            if let screen = NSScreen.main {
                let screenFrame = screen.visibleFrame
                mainWindowController.window?.setFrame(screenFrame, display: true, animate: true)
                mainWindowController.window?.makeKeyAndOrderFront(nil)
            }
        }

        if isFullscreen {
            mainWindowController.window?.toggleFullScreen(self)
        }

        if let droppingPoint {
            mainWindowController.window?.setFrameOrigin(droppingPoint: droppingPoint)
        } else if let sourceWindow = self.findPositioningSourceWindow(for: tabCollectionViewModel?.tabs.first) {
            mainWindowController.window?.setFrameOrigin(cascadedFrom: sourceWindow)
        }

        if showWindow {
            mainWindowController.showWindow(self)
            if !NSApp.isActive {
                NSApp.activate(ignoringOtherApps: true)
            }
        } else {
            mainWindowController.orderWindowBack(self)
        }

        if lazyLoadTabs {
            mainWindowController.mainViewController.tabCollectionViewModel.setUpLazyLoadingIfNeeded()
        }

        return mainWindowController.window
    }

    @discardableResult
    class func openNewWindow(with tab: Tab, droppingPoint: NSPoint? = nil, contentSize: NSSize? = nil, showWindow: Bool = true, popUp: Bool = false) -> NSWindow? {
        let tabCollection = TabCollection()
        tabCollection.append(tab: tab)

        let tabCollectionViewModel: TabCollectionViewModel = {
            if popUp {
                return .init(tabCollection: tabCollection, pinnedTabsManagerProvider: nil, burnerMode: tab.burnerMode)
            }
            return .init(tabCollection: tabCollection, burnerMode: tab.burnerMode)
        }()

        return openNewWindow(with: tabCollectionViewModel,
                             burnerMode: tab.burnerMode,
                             droppingPoint: droppingPoint,
                             contentSize: contentSize,
                             showWindow: showWindow,
                             popUp: popUp)
    }

    @discardableResult
    class func openNewWindow(with initialUrl: URL, source: Tab.TabContent.URLSource, isBurner: Bool, parentTab: Tab? = nil, droppingPoint: NSPoint? = nil, showWindow: Bool = true) -> NSWindow? {
        openNewWindow(with: Tab(content: .contentFromURL(initialUrl, source: source), parentTab: parentTab, shouldLoadInBackground: true, burnerMode: BurnerMode(isBurner: isBurner)), droppingPoint: droppingPoint, showWindow: showWindow)
    }

    @discardableResult
    class func openNewWindow(with tabCollection: TabCollection, isBurner: Bool, droppingPoint: NSPoint? = nil, contentSize: NSSize? = nil, popUp: Bool = false) -> NSWindow? {
        let burnerMode = BurnerMode(isBurner: isBurner)
        let tabCollectionViewModel = TabCollectionViewModel(tabCollection: tabCollection, burnerMode: burnerMode)
        defer {
            tabCollectionViewModel.setUpLazyLoadingIfNeeded()
        }
        return openNewWindow(with: tabCollectionViewModel,
                             burnerMode: burnerMode,
                             droppingPoint: droppingPoint,
                             contentSize: contentSize,
                             popUp: popUp)
    }

    private static let defaultPopUpWidth: CGFloat = 1024
    private static let defaultPopUpHeight: CGFloat = 752

    @discardableResult
    class func openPopUpWindow(with tab: Tab, origin: NSPoint?, contentSize: NSSize?, forcePopup: Bool = false) -> NSWindow? {
        if !forcePopup,
           let mainWindowController = Application.appDelegate.windowControllersManager.lastKeyMainWindowController,
           mainWindowController.window?.styleMask.contains(.fullScreen) == true,
           mainWindowController.window?.isPopUpWindow == false {

            mainWindowController.mainViewController.tabCollectionViewModel.insert(tab, selected: true)
            return mainWindowController.window

        } else {
            let screenFrame = (self.findPositioningSourceWindow(for: tab)?.screen ?? .main)?.visibleFrame ?? NSScreen.fallbackHeadlessScreenFrame

            // limit popUp content size to screen visible frame
            // fallback to default if nil or zero
            var contentSize = contentSize ?? .zero
            contentSize = NSSize(width: min(screenFrame.width, contentSize.width > 0 ? contentSize.width : Self.defaultPopUpWidth),
                                 height: min(screenFrame.height, contentSize.height > 0 ? contentSize.height : Self.defaultPopUpHeight))

            // if origin provided, popup should be fully positioned on screen
            let origin = origin.map { origin in
                NSPoint(x: max(screenFrame.minX, min(screenFrame.maxX - contentSize.width, screenFrame.minX + origin.x)),
                        y: min(screenFrame.maxY, max(screenFrame.minY + contentSize.height, screenFrame.maxY - origin.y)))
            }

            let droppingPoint = origin.map { origin in
                NSPoint(x: origin.x + contentSize.width / 2, y: origin.y)
            }

            return self.openNewWindow(with: tab, droppingPoint: droppingPoint, contentSize: contentSize, popUp: true)
        }
    }

    private class func makeNewWindow(tabCollectionViewModel: TabCollectionViewModel? = nil,
                                     popUp: Bool = false,
                                     burnerMode: BurnerMode,
                                     autofillPopoverPresenter: AutofillPopoverPresenter,
                                     fireCoordinator: FireCoordinator,
                                     aiChatSidebarProvider: AIChatSidebarProviding) -> MainWindowController {
        let mainViewController = MainViewController(
            tabCollectionViewModel: tabCollectionViewModel ?? TabCollectionViewModel(burnerMode: burnerMode),
            autofillPopoverPresenter: autofillPopoverPresenter,
            aiChatSidebarProvider: aiChatSidebarProvider,
            fireCoordinator: fireCoordinator
        )

        let fireWindowSession = if case .burner = burnerMode {
            Application.appDelegate.windowControllersManager.mainWindowControllers.first(where: {
                $0.mainViewController.tabCollectionViewModel.burnerMode == burnerMode
            })?.fireWindowSession ?? FireWindowSession()
        } else { FireWindowSession?.none }
        return MainWindowController(
            mainViewController: mainViewController,
            popUp: popUp,
            fireWindowSession: fireWindowSession,
            fireViewModel: fireCoordinator.fireViewModel
        )
    }

}

fileprivate extension NSStoryboard.SceneIdentifier {
    static let mainViewController = NSStoryboard.SceneIdentifier("mainViewController")
}
