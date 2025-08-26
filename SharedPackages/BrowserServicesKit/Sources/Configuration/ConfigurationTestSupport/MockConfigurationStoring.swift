//
//  MockConfigurationStoring.swift
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

#if !RELEASE
import Foundation

final class MockConfigurationStoring: ConfigurationStoring {
    func loadData(for configuration: Configuration) -> Data? {
        return nil
    }

    func loadEtag(for configuration: Configuration) -> String? {
        return nil
    }

    func loadEmbeddedEtag(for configuration: Configuration) -> String? {
        return nil
    }

    func saveData(_ data: Data, for configuration: Configuration) throws {
    }

    func saveEtag(_ etag: String, for configuration: Configuration) throws {
    }

    func fileUrl(for configuration: Configuration) -> URL {
        return URL(string: "file:///path/to/file")!
    }

}
#endif
