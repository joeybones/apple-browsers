//
//  DebugDatabaseBrowserViewModel.swift
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
import SecureStorage
import DataBrokerProtectionCore
import PixelKit

final class DebugDatabaseBrowserViewModel: ObservableObject {
    @Published var selectedTable: DataBrokerDatabaseBrowserData.Table?
    @Published var tables: [DataBrokerDatabaseBrowserData.Table]
    private let database: DataBrokerProtectionRepository?

    internal init(database: DataBrokerProtectionRepository, tables: [DataBrokerDatabaseBrowserData.Table]? = nil) {

        if let tables = tables {
            self.tables = tables
            self.selectedTable = tables.first
            self.database = nil
        } else {
            self.database = database
            self.tables = [DataBrokerDatabaseBrowserData.Table]()
            self.selectedTable = nil
            updateTables()
        }
    }

    private func createTable(using fetchData: [Any], tableName: String) -> DataBrokerDatabaseBrowserData.Table {
        let rows = fetchData.map { convertToGenericRowData($0) }
        let table = DataBrokerDatabaseBrowserData.Table(name: tableName, rows: rows)
        return table
    }

    private func updateTables() {
        guard let database = self.database else { return }

        Task {
            guard let data = try? database.fetchAllBrokerProfileQueryData(),
                  let attempts = try? database.fetchAllAttempts() else {
                assertionFailure("DataManager error during DataBrokerDatavaseBrowserViewModel.updateTables")
                return
            }

            let profileBrokers = data.map { $0.dataBroker }
            let dataBrokers = Array(Set(profileBrokers)).sorted { $0.id ?? 0 < $1.id ?? 0 }

            let profileQuery = Array(Set(data.map { $0.profileQuery }))
            let scanJobs = data.map { $0.scanJobData }
            let optOutJobs = data.flatMap { $0.optOutJobData }
            let extractedProfiles = data.flatMap { $0.extractedProfiles }
            let events = data.flatMap { $0.events }
            let bgTaskEvents = (try? database.fetchBackgroundTaskEvents(since: .distantPast)) ?? []

            let brokersTable = createTable(using: dataBrokers, tableName: "DataBrokers")
            let profileQueriesTable = createTable(using: profileQuery, tableName: "ProfileQuery")
            let scansTable = createTable(using: scanJobs, tableName: "ScanOperation")
            let optOutsTable = createTable(using: optOutJobs, tableName: "OptOutOperation")
            let extractedProfilesTable = createTable(using: extractedProfiles, tableName: "ExtractedProfile")
            let eventsTable = createTable(using: events.sorted(by: { $0.date > $1.date }), tableName: "Events")
            let attemptsTable = createTable(using: attempts.sorted(by: <), tableName: "OptOutAttempts")
            let backgroundTaskEventsTable = createTable(using: bgTaskEvents.sorted(by: { $0.timestamp < $1.timestamp }), tableName: "BackgroundTaskEvents")

            DispatchQueue.main.async {
                self.tables = [brokersTable, profileQueriesTable, scansTable, optOutsTable, extractedProfilesTable, eventsTable, attemptsTable, backgroundTaskEventsTable]
            }
        }
 }

    private func convertToGenericRowData<T>(_ item: T) -> DataBrokerDatabaseBrowserData.Row {
        let mirror = Mirror(reflecting: item)
        var data: [String: CustomStringConvertible] = [:]
        for child in mirror.children {
            var label: String

            if let childLabel = child.label {
                label = childLabel
            } else {
                label = "No label"
            }

            data[label] = "\(unwrapChildValue(child.value) ?? "-")"
        }
        return DataBrokerDatabaseBrowserData.Row(data: data)
    }

    private func unwrapChildValue(_ value: Any) -> Any? {
        let mirror = Mirror(reflecting: value)
        if mirror.displayStyle != .optional {
            return value
        }

        guard let child = mirror.children.first else {
            return nil
        }

        return unwrapChildValue(child.value)
    }
}

struct DataBrokerDatabaseBrowserData {

    struct Row: Identifiable, Hashable {
        var id = UUID()
        var data: [String: CustomStringConvertible]

        static func == (lhs: Row, rhs: Row) -> Bool {
            return lhs.id == rhs.id
        }

        func hash(into hasher: inout Hasher) {
            hasher.combine(id)
        }
    }

    struct Table: Hashable, Identifiable {
        let id = UUID()
        let name: String
        let rows: [DataBrokerDatabaseBrowserData.Row]

        static func == (lhs: Table, rhs: Table) -> Bool {
            return lhs.name == rhs.name
        }

        func hash(into hasher: inout Hasher) {
            hasher.combine(name)
        }
    }

}

extension AttemptInformation: Comparable {
    public static func < (lhs: AttemptInformation, rhs: AttemptInformation) -> Bool {
        if lhs.extractedProfileId != rhs.extractedProfileId {
            return lhs.extractedProfileId < rhs.extractedProfileId
        } else if lhs.dataBroker != rhs.dataBroker {
            return lhs.dataBroker < rhs.dataBroker
        } else {
            return lhs.startDate < rhs.startDate
        }
    }

    public static func == (lhs: AttemptInformation, rhs: AttemptInformation) -> Bool {
        lhs.attemptId == rhs.attemptId
    }
}
