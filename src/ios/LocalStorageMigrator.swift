import Foundation
import SQLite3

/**

 Please read below **important** discussion.

 Up to the point before the migration, Local Storage that has been used by the main web app has been interfacing using primitive string type values only.

 Therefore, all values inside the local storage database should only be treated as and migrated as strings as well.
 However, this plugin angular interface only expose only `getItem` and `setItem` which tries to get and set as JSON object type.
 Internally, it's doing `JSON.stringify` for `setItem` and `JSON.parse` for `getItem`.

 This is causing the raw string stored to be treated incorrectly, e.g. `JSON.parse("username")` would throw an error, whereas `JSON.parse("\"username\"")` would return a string `username`.

 To fix this issue, we opted to migrate the values into JSON parsable values.
 Mimicking `setItem`, we're going to stringify the string value we got so it's properly parsed by `getItem`.
 */
struct LocalStorageMigrator {
    private let logTag = "\nLocal Storage Migration"
    private let migrationKeyPrefix = "rapid-"

    private let fileManager = FileManager.default

    private let userDefaults: UserDefaults

    init(userDefaults: UserDefaults) {
        self.userDefaults = userDefaults
    }

    func run() throws {
        // Path to the database file
        let dbPath = try databaseFilePath()

        // Check if the local storage database exists
        let dbFileExists = fileManager.fileExists(atPath: dbPath.relativePath)

        if dbFileExists {
            // Perform migration if the database file exists
            try performMigration(dbPath: dbPath)
        } else {
            print("\(logTag) Failed to find the database file")
            throw LocalStorageMigrationError.databaseFileNotFound
        }
    }

    var hasMigrated: Bool {
        userDefaults
            .dictionaryRepresentation()
            .keys
            .contains { $0.hasPrefix(migrationKeyPrefix) }
    }
}

// MARK: - Helper Functions

extension LocalStorageMigrator {

    private func databaseFilePath() throws -> URL  {
        // Path to the library folder
        let libraryDir = NSSearchPathForDirectoriesInDomains(
            .libraryDirectory, .userDomainMask, true
        ).first!
        let libraryPath = URL(fileURLWithPath: libraryDir)

        // Append "WebKit" to the path
        var dbPath: URL = libraryPath.appendingPathComponent("WebKit")

        // Append bundle id if building for simulator
        #if targetEnvironment(simulator)
        dbPath.appendPathComponent("\(Bundle.main.bundleIdentifier!)")
        #endif

        // Append "WebsiteData/Default" to the path
        dbPath.appendPathComponent("WebsiteData")

        if #available(iOS 16.0, *) {
            // iOS 16+
            try appendPathForiOS16(baseURL: &dbPath)
        } else {
            // iOS 14 & 15
            appendPathForiOS1415(baseURL: &dbPath)
        }

        return dbPath
    }

    private func appendPathForiOS16(baseURL: inout URL) throws {
        baseURL.appendPathComponent("Default")

        // There are a couple of intermediate folders names encrypted from salt
        // which we can't decrypt. Since this is the only folder under "Default",
        // we look for the first folder under this path and use the folder name
        // for further database path construction.
        guard let targetFolderName = try fileManager
            .contentsOfDirectory(atPath: baseURL.relativePath)
            .first(where: { content in
                /// Find directory where the content of `origin` file matches original
                /// custom base URL, `ionic://app`.
                let inspectingURL = baseURL.appendingPathComponent(content)
                let originURL = inspectingURL.appendingPathComponent("\(content)/origin")
                guard let origin = try? String(contentsOf: originURL, encoding: .utf8) else {
                    return false
                }

                /// origin = "\u{05}\0\0\0\u{01}ionic\u{03}\0\0\0\u{01}app\0\u{05}\0\0\0\u{01}ionic\u{03}\0\0\0\u{01}app\0"
                /// Seems like the origin has been separated with some control codes.
                /// We want to detect original scheme -> 'ionic'
                /// and original hostname -> 'app'
                return origin.contains("ionic") 
                && origin.contains("app")
                && inspectingURL.isDirectory
            })
        else {
            print("\(logTag) Failed to find the cordova salted intermediate directory")
            throw LocalStorageMigrationError.intermediateDirectoryNotFound
        }

        baseURL
            .appendPathComponent(
                "\(targetFolderName)/\(targetFolderName)/LocalStorage/localstorage.sqlite3"
            )
        print("\(logTag) Database file path iOS16 \(baseURL)")
    }

    private func appendPathForiOS1415(baseURL: inout URL) {
        baseURL.appendPathComponent("LocalStorage/ionic_app_0.localstorage")

        print("\(logTag) Database file path iOS14 or iOS15 \(baseURL)")
    }

    private func performMigration(dbPath: URL) throws {
        print("\(logTag) Opening database")
        var database: OpaquePointer?
        var stmt: OpaquePointer?

        // Open the database
        let openResult = sqlite3_open_v2(
            dbPath.relativePath,
            &database,
            SQLITE_OPEN_READWRITE,
            nil
        )

        if openResult == SQLITE_OK {
            let query = "SELECT key,value FROM ItemTable"

            let queryResult = sqlite3_prepare_v2(
                database,
                (query as NSString).utf8String,
                -1,
                &stmt,
                nil
            )

            // Query the databasse
            if queryResult == SQLITE_OK {
                while(sqlite3_step(stmt) == SQLITE_ROW) {
                    // Get the key
                    let key = String(cString: sqlite3_column_text(stmt, 0))

                    // Skip the keys without "rapid-" prefix, WE DON'T CARE ABOUT THEM!!!
                    guard key.hasPrefix(migrationKeyPrefix) else { continue }

                    // Get value as String
                    if let valueBlob = sqlite3_column_blob(stmt, 1) {
                        let valueBlobLength = sqlite3_column_bytes(stmt, 1)
                        let valueData = Data(bytes: valueBlob, count: Int(valueBlobLength))

                        if let valueString = String(data: valueData, encoding: .utf16LittleEndian) {
                            saveToNativeStorage(key: key, value: valueString)
                        } else {
                            print("\(logTag) Failed to convert data blob into string for key \(key), skipping....")
                        }
                    } else {
                        print("\(logTag) Failed to get the value for key \(key)")
                    }
                }
                sqlite3_finalize(stmt);

                // Database clean up
                print("\(logTag) Cleaning up the local storage database")

                let deleteQuery = "DELETE FROM ItemTable WHERE key LIKE '\(migrationKeyPrefix)%'"

                let deleteQueryResult = sqlite3_prepare_v2(
                    database,
                    (deleteQuery as NSString).utf8String,
                    -1,
                    &stmt,
                    nil
                )

                if deleteQueryResult == SQLITE_OK && sqlite3_step(stmt) == SQLITE_DONE {
                    print("\(logTag) Local storage database cleaned up")
                }
                sqlite3_finalize(stmt);
            }

            print("\(logTag) Closing database")
            sqlite3_close(database)
        } else {
            print("\(logTag) Failed to open database")
            throw LocalStorageMigrationError.databaseOpenFailed
        }
    }

    private func saveToNativeStorage(key: String, value: String) {
        print("\(logTag) Saving \(value) for key: \(key) into user defaults")

        let convertedValue: Any?

        do {
            // There is a list of keys we care about and there are 1-1 mappings between
            // the keys and value types - please refer to LocalStorageDataConverter for details
            convertedValue = try LocalStorageDataConverter(key: key, rawString: value).convert()
        } catch {
            convertedValue = nil
            print("\(logTag) Failed to convert \(value) for key: \(key)")
        }

        userDefaults.set(convertedValue, forKey: key)
    }
}

private extension URL {
    var isDirectory: Bool {
       (try? resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true
    }
}

enum LocalStorageMigrationError: LocalizedError {
    case databaseFileNotFound
    case intermediateDirectoryNotFound
    case databaseOpenFailed
    case dataConversionFailed

    var errorDescription: String? {
        switch self {
        case .databaseFileNotFound:
            return "Could not find local storage database file"

        case .intermediateDirectoryNotFound:
            return "Could not find intermediate directory to the local storage database"

        case .databaseOpenFailed:
            return "Failed to open local storage database"

        case .dataConversionFailed:
            return "Failed to convert migration data"
        }
    }
}

private struct LocalStorageDataConverter {
    private enum OutputType {
        case string, bool, double, object, undefined
    }

    private let rawString: String
    private let outputType: OutputType

    init(key: String, rawString: String) {
        self.rawString = rawString

        switch key {
        case _ where key.contains("rapid-username"): outputType = .string
        case _ where key.contains("rapid-user-changed"): outputType = .bool
        case _ where key.contains("rapid-automatic-download"): outputType = .bool
        case _ where key.contains("rapid-app-paused-timestamp"): outputType = .double
        case _ where key.contains("rapid-last-activity-timestamp"): outputType = .double
        case _ where key.contains("rapid-app-storage"): outputType = .object
        case _ where key.contains("rapid-notification-prompt-request"): outputType = .bool
        case _ where key.contains("rapid-notification-prompt-response"): outputType = .bool
        case _ where key.contains("rapid-rma-cognito-device-key"): outputType = .string
        default: outputType = .undefined
        }
    }

    func convert() throws -> Any {
        switch outputType {
        case .object: fallthrough
        case .bool: fallthrough
        case .double: fallthrough
        case .string:
            /// Treat everything as a string that's needed to be stringified
            /// Read the documentation of the object for more info
            let stringifiedData = try JSONSerialization.data(withJSONObject: rawString, options: .fragmentsAllowed)
            guard let stringifiedString = String(data: stringifiedData, encoding: .utf8) else {
                throw LocalStorageMigrationError.dataConversionFailed
            }
            return stringifiedString

        case .undefined:
            throw LocalStorageMigrationError.dataConversionFailed
        }
    }
}

private extension String {
    var boolValue: Bool {
        (self as NSString).boolValue
    }

    var doubleValue: Double {
        (self as NSString).doubleValue
    }
}
