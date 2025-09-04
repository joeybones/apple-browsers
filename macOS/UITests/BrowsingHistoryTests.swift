//
//  BrowsingHistoryTests.swift
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

class BrowsingHistoryTests: UITestCase {

    private var historyMenuBarItem: XCUIElement!
    private var clearAllHistoryMenuItem: XCUIElement!
    private var clearAllHistoryAlertClearButton: XCUIElement!
    private var fakeFireButton: XCUIElement!
    private var addressBarTextField: XCUIElement!
    private let lengthForRandomPageTitle = 8

    override func setUpWithError() throws {
        try super.setUpWithError()
        continueAfterFailure = false
        app = XCUIApplication.setUp()
        historyMenuBarItem = app.menuBarItems["History"]
        clearAllHistoryMenuItem = app.menuItems["HistoryMenu.clearAllHistory"]
        clearAllHistoryAlertClearButton = app.buttons["ClearAllHistoryAndDataAlert.clearButton"]
        fakeFireButton = app.buttons["FireViewController.fakeFireButton"]
        addressBarTextField = app.addressBar
        app.enforceSingleWindow()

        XCTAssertTrue(
            historyMenuBarItem.waitForExistence(timeout: UITests.Timeouts.elementExistence),
            "History menu bar item didn't appear in a reasonable timeframe."
        )
        historyMenuBarItem.click()

        XCTAssertTrue(
            clearAllHistoryMenuItem.waitForExistence(timeout: UITests.Timeouts.elementExistence),
            "Clear all history item didn't appear in a reasonable timeframe."
        )
        clearAllHistoryMenuItem.click()

        XCTAssertTrue(
            clearAllHistoryAlertClearButton.waitForExistence(timeout: UITests.Timeouts.elementExistence),
            "Clear all history item didn't appear in a reasonable timeframe."
        )
        clearAllHistoryAlertClearButton.click() // Manually remove the history
        XCTAssertTrue( // Let any ongoing fire animation or data processes complete
            fakeFireButton.waitForNonExistence(timeout: UITests.Timeouts.fireAnimation),
            "Fire animation didn't finish and cease existing in a reasonable timeframe."
        )
    }

    func test_recentlyVisited_showsLastVisitedSite() throws {
        let historyPageTitleExpectedToBeFirstInRecentlyVisited = UITests.randomPageTitle(length: lengthForRandomPageTitle)
        let url = UITests.simpleServedPage(titled: historyPageTitleExpectedToBeFirstInRecentlyVisited)
        let firstSiteInRecentlyVisitedSection = app.menuItems["HistoryMenu.recentlyVisitedMenuItem.0"]
        XCTAssertTrue(
            addressBarTextField.waitForExistence(timeout: UITests.Timeouts.elementExistence),
            "The address bar text field didn't become available in a reasonable timeframe."
        )

        addressBarTextField.typeURL(url)
        XCTAssertTrue(
            app.windows.webViews[historyPageTitleExpectedToBeFirstInRecentlyVisited]
                .waitForExistence(timeout: UITests.Timeouts.elementExistence),
            "Visited site didn't load with the expected title in a reasonable timeframe."
        )
        XCTAssertTrue(
            historyMenuBarItem.waitForExistence(timeout: UITests.Timeouts.elementExistence),
            "History menu bar item didn't appear in a reasonable timeframe."
        )
        historyMenuBarItem.click() // The visited sites identifiers will not be available until after the History menu has been accessed.
        XCTAssertTrue(
            firstSiteInRecentlyVisitedSection.waitForExistence(timeout: UITests.Timeouts.elementExistence),
            "The first site in the recently visited section didn't appear in a reasonable timeframe."
        )

        XCTAssertEqual(historyPageTitleExpectedToBeFirstInRecentlyVisited, firstSiteInRecentlyVisitedSection.title)
    }

    func test_history_showsVisitedSiteAfterClosingAndReopeningWindow() throws {
        let historyPageTitleExpectedToBeFirstInTodayHistory = UITests.randomPageTitle(length: lengthForRandomPageTitle)
        let url = UITests.simpleServedPage(titled: historyPageTitleExpectedToBeFirstInTodayHistory)
        let siteInRecentlyVisitedSection = app.menuItems[historyPageTitleExpectedToBeFirstInTodayHistory]
        XCTAssertTrue(
            addressBarTextField.waitForExistence(timeout: UITests.Timeouts.elementExistence),
            "The address bar text field didn't become available in a reasonable timeframe."
        )

        addressBarTextField.typeURL(url)
        XCTAssertTrue(
            app.windows.webViews[historyPageTitleExpectedToBeFirstInTodayHistory].waitForExistence(timeout: UITests.Timeouts.elementExistence),
            "Visited site didn't load with the expected title in a reasonable timeframe."
        )
        app.enforceSingleWindow()
        XCTAssertTrue(
            historyMenuBarItem.waitForExistence(timeout: UITests.Timeouts.elementExistence),
            "History menu bar item didn't appear in a reasonable timeframe."
        )
        historyMenuBarItem.click() // The visited sites identifiers will not be available until after the History menu has been accessed.
        XCTAssertTrue(
            siteInRecentlyVisitedSection.waitForExistence(timeout: UITests.Timeouts.elementExistence),
            "The first site in the recently visited section didn't appear in a reasonable timeframe."
        )
    }

    func test_reopenLastClosedWindowMenuItem_canReopenTabsOfLastClosedWindow() throws {
        let titleOfFirstTabWhichShouldRestore = UITests.randomPageTitle(length: lengthForRandomPageTitle)
        let titleOfSecondTabWhichShouldRestore = UITests.randomPageTitle(length: lengthForRandomPageTitle)
        let urlForFirstTab = UITests.simpleServedPage(titled: titleOfFirstTabWhichShouldRestore)
        let urlForSecondTab = UITests.simpleServedPage(titled: titleOfSecondTabWhichShouldRestore)
        XCTAssertTrue(
            addressBarTextField.waitForExistence(timeout: UITests.Timeouts.elementExistence),
            "The address bar text field didn't become available in a reasonable timeframe."
        )
        addressBarTextField.typeURL(urlForFirstTab)
        XCTAssertTrue(
            app.windows.webViews[titleOfFirstTabWhichShouldRestore].waitForExistence(timeout: UITests.Timeouts.elementExistence),
            "Visited site didn't load with the expected title in a reasonable timeframe."
        )
        app.openNewTab()

        addressBarTextField.typeURL(urlForSecondTab)
        XCTAssertTrue(
            app.windows.webViews[titleOfSecondTabWhichShouldRestore].waitForExistence(timeout: UITests.Timeouts.elementExistence),
            "Visited site didn't load with the expected title in a reasonable timeframe."
        )
        app.enforceSingleWindow()
        XCTAssertTrue(
            historyMenuBarItem.waitForExistence(timeout: UITests.Timeouts.elementExistence),
            "History menu bar item didn't appear in a reasonable timeframe."
        )
        historyMenuBarItem.click() // The visited sites identifiers will not be available until after the History menu has been accessed.
        let reopenLastClosedWindowMenuItem = app.menuItems["HistoryMenu.reopenLastClosedWindow"]
        XCTAssertTrue(
            reopenLastClosedWindowMenuItem.waitForExistence(timeout: UITests.Timeouts.elementExistence),
            "The \"Reopen Last Closed Window\" menu item didn't appear in a reasonable timeframe."
        )
        reopenLastClosedWindowMenuItem.click()

        XCTAssertTrue(
            app.windows.webViews[titleOfFirstTabWhichShouldRestore].waitForExistence(timeout: UITests.Timeouts.elementExistence),
            "Restored visited tab 1 wasn't available with the expected title in a reasonable timeframe."
        )
        app.closeCurrentTab()
        XCTAssertTrue(
            app.windows.webViews[titleOfSecondTabWhichShouldRestore].waitForExistence(timeout: UITests.Timeouts.elementExistence),
            "Restored visited tab 2 wasn't available with the expected title in a reasonable timeframe."
        )
    }
}
