import Foundation
import SQLite3

struct LocalStorageMigrator {
    private let logTag = "\nLocal Storage Migration"
    
    private let fileManager = FileManager.default

    // TODO: Review this
    private let userDefaults: UserDefaults

    // TODO: Review this
    init(userDefaults: UserDefaults) {
        self.userDefaults = userDefaults
    }

    // TODO: Call migrator inside the plugin
    func run() throws {
        // Path to the database file
        let dbPath = try databaseFilePath()
        
        // Check if the local storage database exists
        let dbFileExists = fileManager.fileExists(atPath: dbPath.relativePath)
        
        if dbFileExists {
            // Perform migration if the database file exists
            try performMigration(dbPath: dbPath)
        } else {
            assertionFailure("\(logTag) Failed to find the database file")
            throw LocalStorageMigrationError.databaseFileNotFound
        }
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
        dbPath.appendPathComponent("WebsiteData/Default")
        
        // There are a couple of intermediate folders names encrypted from salt
        // which we can't decrypt. Since this is the only folder under "Default",
        // we look for the first folder under this path and use the folder name
        // for further database path construction.
        guard let targetFolderName = try fileManager
            .contentsOfDirectory(atPath: dbPath.relativePath)
            .first(where: { content in
                dbPath.appendingPathComponent(content).isDirectory
            })
        else {
            assertionFailure("\(logTag) Failed to find the cordova salted intermediate directory")
            throw LocalStorageMigrationError.intermediateDirectoryNotFound
        }
        
        dbPath
            .appendPathComponent(
                "\(targetFolderName)/\(targetFolderName)/LocalStorage/localstorage.sqlite3"
            )
        print("\(logTag) Database file path \(dbPath)")
        
        return dbPath
    }
    
    private func performMigration(dbPath: URL) throws {
        print("\(logTag) Opening database")
        var database: OpaquePointer?
        var stmt: OpaquePointer?
        
        // Open the database
        let openResult = sqlite3_open_v2(
            dbPath.relativePath,
            &database,
            SQLITE_OPEN_READONLY,
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
                    // TODO: Maybe do a shared method to have same logic for native storage plugin
                    // for checking has this prefix
                    guard key.hasPrefix("rapid-") else { continue }
                    
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
            }
            
            print("\(logTag) Closing database")
            sqlite3_close(database)
        } else {
            assertionFailure("\(logTag) Failed to open database")
            throw LocalStorageMigrationError.databaseOpenFailed
        }
    }
    
    private func saveToNativeStorage(key: String, value: String) {
        print("\(logTag) Saving \(value) for key: \(key) into user defaults")

        // TODO: Improve typing of the value
        /// Aaron provided list of keys with expected types of the value
        /// Maybe we can have mapping of those keys and the expected type
        /// Use that as the logic of given a key, try to typecast the value to target type
        /// or something like that.
        userDefaults.set(value, forKey: key)
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
    
    var errorDescription: String? {
        switch self {
        case .databaseFileNotFound:
            return "Could not find local storage database file"
        
        case .intermediateDirectoryNotFound:
            return "Could not find intermediate directory to the local storage database"
        
        case .databaseOpenFailed:
            return "Failed to open local storage database"
        }
    }
}
