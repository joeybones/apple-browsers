//
//  UpdatesDebugMenu.swift
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

import AppKit
import AIChat

final class UpdatesDebugMenu: NSMenu {
    init() {
        super.init(title: "")

        buildItems {
            NSMenuItem(title: "Expire current update", action: #selector(expireCurrentUpdate))
                .targetting(self)
            NSMenuItem(title: "Reset last update check", action: #selector(resetLastUpdateCheck))
                .targetting(self)
        }
    }

    required init(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Menu State Update

    @UserDefaultsWrapper(key: .updateValidityStartDate, defaultValue: nil)
    var updateValidityStartDate: Date?

    @objc func expireCurrentUpdate() {
        updateValidityStartDate = .distantPast
    }

    @UserDefaultsWrapper(key: .pendingUpdateSince, defaultValue: .distantPast)
    private var pendingUpdateSince: Date

    @objc func resetLastUpdateCheck() {
        pendingUpdateSince = .distantPast
    }

}
