//
//  PreferencesGeneralView.swift
//
//  Copyright © 2022 DuckDuckGo. All rights reserved.
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
import Combine
import FeatureFlags
import MaliciousSiteProtection
import PixelKit
import PreferencesUI_macOS
import SwiftUI
import SwiftUIExtensions

extension Preferences {

    struct GeneralView: View {
        @ObservedObject var startupModel: StartupPreferences
        @ObservedObject var downloadsModel: DownloadsPreferences
        @ObservedObject var searchModel: SearchPreferences
        @ObservedObject var tabsModel: TabsPreferences
        @ObservedObject var dataClearingModel: DataClearingPreferences
        @ObservedObject var maliciousSiteDetectionModel: MaliciousSiteProtectionPreferences
        @State private var showingCustomHomePageSheet = false
        @State private var isAddedToDock = false
        var dockCustomizer: DockCustomizer
        let featureFlagger = NSApp.delegateTyped.featureFlagger
        let pinnedTabsManagerProvider: PinnedTabsManagerProviding = Application.appDelegate.pinnedTabsManagerProvider

        @State private var showWarningAlert = false
        @State private var pendingSelection: PinnedTabsMode?

        private func firePinnedTabsPixel(_ newMode: PinnedTabsMode) {
            if newMode == .shared {
                PixelKit.fire(PinnedTabsPixel.userSwitchedToSharedPinnedTabs, frequency: .dailyAndStandard)
            } else {
                PixelKit.fire(PinnedTabsPixel.userSwitchedToPerWindowPinnedTabs, frequency: .dailyAndStandard)
            }
        }

        private func setPinnedTabsMode(_ newMode: PinnedTabsMode) {
            guard tabsModel.pinnedTabsMode != newMode else { return }
            tabsModel.pinnedTabsMode = newMode
            firePinnedTabsPixel(newMode)
        }

        var body: some View {
            PreferencePane(UserText.general) {

                // SECTION: Shortcuts
#if !APPSTORE
                PreferencePaneSection(UserText.shortcuts, spacing: 4) {
                    PreferencePaneSubSection {
                        HStack {
                            if isAddedToDock || dockCustomizer.isAddedToDock {
                                HStack {
                                    Image(.checkCircle).foregroundColor(Color(.successGreen))
                                    Text(UserText.isAddedToDock)
                                }
                                .transition(.opacity)
                                .padding(.trailing, 8)
                            } else {
                                HStack {
                                    Image(.warning).foregroundColor(Color(.linkBlue))
                                    Text(UserText.isNotAddedToDock)
                                }
                                .padding(.trailing, 8)
                                Button(action: {
                                    withAnimation {
                                        PixelKit.fire(GeneralPixel.userAddedToDockFromSettings,
                                                      includeAppVersionParameter: false)
                                        dockCustomizer.addToDock()
                                        isAddedToDock = true
                                    }
                                }) {
                                    Text(UserText.addToDock)
                                        .fixedSize(horizontal: true, vertical: false)
                                        .multilineTextAlignment(.center)
                                }
                            }
                        }
                    }
                }
#endif
                // SECTION: On Startup
                PreferencePaneSection(UserText.onStartup) {

                    PreferencePaneSubSection {
                        Picker(selection: $startupModel.restorePreviousSession, content: {
                            if featureFlagger.isFeatureOn(.openFireWindowByDefault) {
                                VStack(alignment: .leading, spacing: 4) {
                                    HStack(spacing: 0) {
                                        Text(UserText.openANew)
                                        Picker("", selection: $startupModel.startupWindowType) {
                                            ForEach(StartupWindowType.allCases, id: \.self) { windowType in
                                                Text(windowType.displayName).tag(windowType)
                                                    .accessibilityIdentifier({
                                                        switch windowType {
                                                        case .window:
                                                            "PreferencesGeneralView.stateRestorePicker.openANewWindow.regular"
                                                        case .fireWindow:
                                                            "PreferencesGeneralView.stateRestorePicker.openANewWindow.fireWindow"
                                                        }
                                                    }())
                                            }
                                        }
                                        .pickerStyle(.menu)
                                        .fixedSize()
                                        .disabled(startupModel.restorePreviousSession)
                                    }
                                }
                                .tag(false)
                                .padding(.bottom, 4)
                            } else {
                                Text(UserText.showHomePage).tag(false)
                                    .padding(.bottom, 4)
                                    .accessibilityIdentifier("PreferencesGeneralView.stateRestorePicker.openANewWindow")
                            }
                            Text(UserText.reopenAllWindowsFromLastSession).tag(true)
                                .accessibilityIdentifier("PreferencesGeneralView.stateRestorePicker.reopenAllWindowsFromLastSession")
                        }, label: {})
                        .pickerStyle(.radioGroup)
                        .offset(x: PreferencesUI_macOS.Const.pickerHorizontalOffset)
                        .accessibilityIdentifier("PreferencesGeneralView.stateRestorePicker")

                        if (dataClearingModel.isAutoClearEnabled || dataClearingModel.shouldOpenFireWindowByDefault) && startupModel.restorePreviousSession {
                            VStack(alignment: .leading, spacing: 1) {
                                TextMenuItemCaption(UserText.disableAutoClearToEnableSessionRestore)
                                TextButton(UserText.showDataClearingSettings) {
                                    startupModel.show(url: .settingsPane(.dataClearing))
                                }
                            }
                            .padding(.leading, 19)
                        }
                    }
                }

                // SECTION: Tabs
                PreferencePaneSection(UserText.tabs) {
                    PreferencePaneSubSection {
                        ToggleMenuItem(UserText.preferNewTabsToWindows, isOn: $tabsModel.preferNewTabsToWindows)
                        ToggleMenuItem(UserText.switchToNewTabWhenOpened, isOn: $tabsModel.switchToNewTabWhenOpened)
                            .accessibilityIdentifier("PreferencesGeneralView.switchToNewTabWhenOpened")
                    }

                    PreferencePaneSubSection {
                        HStack {
                            Picker(UserText.newTabPositionTitle, selection: $tabsModel.newTabPosition) {
                                ForEach(NewTabPosition.allCases, id: \.self) { position in
                                    Text(UserText.newTabPositionMode(for: position)).tag(position)
                                }
                            }
                        }
                        HStack {
                            Picker(UserText.pinnedTabs, selection: Binding(
                                get: { tabsModel.pinnedTabsMode },
                                set: { newValue in
                                    if newValue == .shared {
                                        // Attempting to switch to the shared mode that requires warning in case
                                        // the app is going to combine existing pinned tabs
                                        if pinnedTabsManagerProvider.areDifferentPinnedTabsPresent {
                                            pendingSelection = newValue
                                            showWarningAlert = true
                                        } else {
                                            setPinnedTabsMode(newValue)
                                        }
                                    } else {
                                        setPinnedTabsMode(newValue)
                                    }
                                }
                            )) {
                                ForEach(PinnedTabsMode.allCases, id: \.self) { mode in
                                    Text(UserText.pinnedTabsMode(for: mode)).tag(mode)
                                }
                            }.accessibilityIdentifier("PreferencesGeneralView.pinnedTabsModePicker")
                        }
                        .alert(isPresented: $showWarningAlert) {
                            Alert(
                                title: Text(UserText.pinnedTabsWarningTitle),
                                message: Text(UserText.pinnedTabsWarningMessage),
                                primaryButton: .default(Text(UserText.ok)) {
                                    // Apply the change only if confirmed
                                    if let selection = pendingSelection {
                                        tabsModel.pinnedTabsMode = selection

                                        firePinnedTabsPixel(selection)
                                    }
                                },
                                secondaryButton: .cancel {
                                    pendingSelection = nil
                                }
                            )
                        }
                    }
                }

                // SECTION: Home Page
                PreferencePaneSection(UserText.homePage) {

                    PreferencePaneSubSection {

                        TextMenuItemCaption(UserText.homePageDescription)

                        Picker(selection: $startupModel.launchToCustomHomePage, label: EmptyView()) {
                            Text(UserText.newTab).tag(false)
                            VStack(alignment: .leading, spacing: 0) {
                                HStack(spacing: 15) {
                                    Text(UserText.specificPage)
                                    Button(UserText.setPage) {
                                        showingCustomHomePageSheet.toggle()
                                    }.disabled(!startupModel.launchToCustomHomePage)
                                }
                                TextMenuItemCaption(startupModel.friendlyURL)
                                    .padding(.top, 0)
                                    .visibility(!startupModel.launchToCustomHomePage ? .gone : .visible)

                            }.tag(true)
                        }
                        .pickerStyle(.radioGroup)
                        .offset(x: PreferencesUI_macOS.Const.pickerHorizontalOffset)
                    }

                    PreferencePaneSubSection {
                        HStack {
                            Picker(UserText.mainMenuHomeButton, selection: $startupModel.homeButtonPosition) {
                                ForEach(HomeButtonPosition.allCases, id: \.self) { position in
                                    Text(UserText.homeButtonMode(for: position)).tag(position)
                                }
                            }
                            .onChange(of: startupModel.homeButtonPosition) { _ in
                                startupModel.updateHomeButton()
                            }
                        }
                    }

                }.sheet(isPresented: $showingCustomHomePageSheet) {
                    CustomHomePageSheet(startupModel: startupModel, isSheetPresented: $showingCustomHomePageSheet)
                }

                // SECTION: Search Settings
                PreferencePaneSection(UserText.privateSearch) {
                    ToggleMenuItem(UserText.showAutocompleteSuggestions, isOn: $searchModel.showAutocompleteSuggestions).accessibilityIdentifier("PreferencesGeneralView.showAutocompleteSuggestions")
                }

                // SECTION: Downloads
                PreferencePaneSection(UserText.downloads) {
                    PreferencePaneSubSection {
                        ToggleMenuItem(UserText.downloadsOpenPopupOnCompletion, isOn: $downloadsModel.shouldOpenPopupOnCompletion)
                            .accessibilityIdentifier("PreferencesGeneralView.openPopupOnDownloadCompletion")
                    }.padding(.bottom, 5)

                    // MARK: Location
                    PreferencePaneSubSection {
                        Text(UserText.downloadsLocation).bold()

                        HStack {
                            NSPathControlView(url: downloadsModel.selectedDownloadLocation)
                            Button(UserText.downloadsChangeDirectory) {
                                downloadsModel.presentDownloadDirectoryPanel()
                            }
                        }
                        .disabled(downloadsModel.alwaysRequestDownloadLocation)

                        ToggleMenuItem(UserText.downloadsAlwaysAsk, isOn: $downloadsModel.alwaysRequestDownloadLocation)
                            .accessibilityIdentifier("PreferencesGeneralView.alwaysAskWhereToSaveFiles")
                    }
                }
            }
        }
    }
}

struct CustomHomePageSheet: View {

    @ObservedObject var startupModel: StartupPreferences
    @State var url: String = ""
    @State var isValidURL: Bool = true
    @Binding var isSheetPresented: Bool

    var body: some View {
        VStack(alignment: .center) {
            TextMenuTitle(UserText.setHomePage)
                .padding(.vertical, 10)

            Group {
                HStack {
                    Text(UserText.addressLabel)
                        .padding(.trailing, 10)
                    TextField("", text: $url)
                        .frame(width: 250)
                        .onChange(of: url) { newValue in
                            validateURL(newValue)
                        }
                }
                .padding(8)
            }
            .roundedBorder()
            .padding(EdgeInsets(top: 10, leading: 15, bottom: 10, trailing: 15))

            Divider()

            HStack(alignment: .center) {
                Spacer()
                Button(UserText.cancel) {
                    isSheetPresented.toggle()
                }
                Button(UserText.save) {
                    saveChanges()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!isValidURL)
            }.padding(EdgeInsets(top: 10, leading: 0, bottom: 10, trailing: 15))

        }
        .padding(.vertical, 10)
        .onAppear(perform: {
            url = startupModel.customHomePageURL
        })
    }

    private func saveChanges() {
        startupModel.customHomePageURL = url
        isSheetPresented.toggle()
    }

    private func validateURL(_ url: String) {
        isValidURL = startupModel.isValidURL(url)
    }
}
