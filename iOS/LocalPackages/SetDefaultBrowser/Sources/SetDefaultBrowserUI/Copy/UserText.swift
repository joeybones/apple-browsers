//
//  UserText.swift
//  DuckDuckGo
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

import Foundation

enum UserText {

    enum ActiveUserModal {
        static let title = NSLocalizedString("setDefaultBrowser.modal.title", bundle: Bundle.module, value: "Let DuckDuckGo protect more of what you do online", comment: "Set Default Browser Modal Sheet Title.")
        static let message = NSLocalizedString("setDefaultBrowser.modal.message", bundle: Bundle.module, value: "Make us your default browser so all site links open in DuckDuckGo.", comment: "Set Default Browser Modal Sheet Message.")
        static let setDefaultBrowserCTA = NSLocalizedString("setDefaultBrowser.cta.primary.title", bundle: Bundle.module, value: "Set As Default Browser", comment: "The tile of the CTA to set the browser as default.")
        static let doNotAskAgainCTA = NSLocalizedString("setDefaultBrowser.cta.secondary.title", bundle: Bundle.module, value: "Don’t Ask Again", comment: "The title of the CTA to permanently dismiss the modal sheet.")
    }

    enum InactiveUserModal {
        static let title = NSLocalizedString("setDefaultBrowser.modal.inactive-user.title", bundle: Bundle.module, value: "DuckDuckGo has protections other browsers don’t.", comment: "Title of the a page inviting the inactive user to use the DuckDuckGo browser as default browser")
        static let moreProtections = NSLocalizedString("setDefaultBrowser.modal.inactive-user.more-protections.title", bundle: .module, value: "[Plus even more protections...](ddgQuickLink://duckduckgo.com/duckduckgo-help-pages/threat-protection/scam-blocker)", comment: "Title of the button explaining of other browser protections that link to a web page. (do not remove the link)")
        static let setDefaultBrowserCTA = NSLocalizedString("setDefaultBrowser.inactive-user.cta.primary.title", bundle: Bundle.module, value: "Open Links with DuckDuckGo", comment: "The tile of the button the user can use to set the browser as default.")
        static let continueBrowsingCTA = NSLocalizedString("setDefaultBrowser.inactive-user.cta.secondary.title", bundle: Bundle.module, value: "Maybe Later", comment: "The title of the button to dismiss the prompt.")
    }
}
