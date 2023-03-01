import Foundation

@objc(NativeStorage)
final class NativeStorage: CDVPlugin {

    private static let defaultSuiteName = "NativeStorage"

    private var appGroupUserDefaults: UserDefaults? = nil
    private var suiteName: String? = nil {
        didSet {
            appGroupUserDefaults = UserDefaults(suiteName: suiteName)
        }
    }

    override func pluginInitialize() {
        super.pluginInitialize()

        /// Maintaining default `NativeStorage` suite name as a default groups user defaults
        self.suiteName = Self.defaultSuiteName

        /// Check if migration is needed.
        /// If `targetUserDefaults` already contains any key with "rapid-" prefix,
        /// It means that the migration has been done in the past.
        let targetUserDefaults = getUserDefault()
        let migrator = LocalStorageMigrator(userDefaults: targetUserDefaults)

        if !migrator.hasMigrated {
            do {
                try migrator.run()
            } catch {
                print("\(migrator.logTag) \(error.localizedDescription)")
                commandDelegate.evalJs("console.log([\(NSStringFromClass(Self.self))] \(error.localizedDescription)")
            }
        }

        print("User default values: \n\(targetUserDefaults.dictionaryRepresentation())")
    }

    @objc
    func initWithSuiteName(_ command: CDVInvokedUrlCommand) {
        self.commandDelegate.run(inBackground: { [unowned self] in
            let pluginResult: CDVPluginResult
            if let suiteName = command.arguments[0] as? String {
                self.suiteName = suiteName
                pluginResult = CDVPluginResult(status: .ok)
            } else {
                pluginResult = CDVPluginResult(status: .error, messageAs: "Reference or SuiteName was null")
            }

            self.commandDelegate.send(pluginResult, callbackId: command.callbackId)
        })
    }

    private func getUserDefault() -> UserDefaults {
        if let appGroupUserDefaults = appGroupUserDefaults {
            return appGroupUserDefaults
        } else {
            return .standard
        }
    }

    @objc
    func remove(_ command: CDVInvokedUrlCommand) {
        self.commandDelegate.run(inBackground: { [unowned self] in
            let pluginResult: CDVPluginResult
            if let reference = command.arguments[0] as? String {
                let defaults = self.getUserDefault()
                defaults.removeObject(forKey: reference)
                if defaults.synchronize() {
                    pluginResult = CDVPluginResult(status: .ok)
                } else {
                    pluginResult = CDVPluginResult(status: .error, messageAs: "Remove has failed")
                }
            } else {
                pluginResult = CDVPluginResult(status: .error, messageAs: "Reference was null")
            }
            self.commandDelegate.send(pluginResult, callbackId: command.callbackId)
        })
    }

    @objc
    func clear(_ command: CDVInvokedUrlCommand) {
        self.commandDelegate.run(inBackground: { [unowned self] in
            let pluginResult: CDVPluginResult
            self.getUserDefault().removePersistentDomain(forName: Bundle.main.bundleIdentifier!)

            if self.getUserDefault().synchronize() {
                pluginResult = CDVPluginResult(status: .ok)
            } else {
                pluginResult = CDVPluginResult(status: .error, messageAs: "Clear has failed")
            }
            self.commandDelegate.send(pluginResult, callbackId: command.callbackId)
        })
    }

    @objc
    func putBoolean(_ command: CDVInvokedUrlCommand) {
        self.commandDelegate.run(inBackground: { [unowned self] in
            let pluginResult: CDVPluginResult
            if let reference = command.arguments[0] as? String,
               let aBoolean = command.arguments[1] as? ObjCBool {
                let defaults = self.getUserDefault()
                defaults.set(aBoolean.boolValue, forKey: reference)
                if defaults.synchronize() {
                    pluginResult = CDVPluginResult(status: .ok, messageAs: aBoolean.boolValue)
                } else {
                    pluginResult = CDVPluginResult(status: .error, messageAs: "Write has failed")
                }
            } else {
                pluginResult = CDVPluginResult(status: .error, messageAs: "Reference was null")
            }
            self.commandDelegate.send(pluginResult, callbackId: command.callbackId)
        })
    }

    @objc
    func getBoolean(_ command: CDVInvokedUrlCommand) {
        self.commandDelegate.run(inBackground: { [unowned self] in
            let pluginResult: CDVPluginResult
            if let reference = command.arguments[0] as? String {
                let aBoolean = self.getUserDefault().bool(forKey: reference)
                pluginResult = CDVPluginResult(status: .ok, messageAs: aBoolean)
            } else {
                pluginResult = CDVPluginResult(status: .error, messageAs: "Reference was null")
            }
            self.commandDelegate.send(pluginResult, callbackId: command.callbackId)
        })
    }

    @objc
    func putInt(_ command: CDVInvokedUrlCommand) {
        self.commandDelegate.run(inBackground: { [unowned self] in
            let pluginResult: CDVPluginResult
            if let reference = command.arguments[0] as? String,
               let anInt = command.arguments[1] as? Int {
                let defaults = self.getUserDefault()
                defaults.set(anInt, forKey: reference)
                if defaults.synchronize() {
                    pluginResult = CDVPluginResult(status: .ok, messageAs: anInt)
                } else {
                    pluginResult = CDVPluginResult(status: .error, messageAs: "Write has failed")
                }
            } else {
                pluginResult = CDVPluginResult(status: .error, messageAs: "Reference was null")
            }
            self.commandDelegate.send(pluginResult, callbackId: command.callbackId)
        })
    }

    @objc
    func getInt(_ command: CDVInvokedUrlCommand) {
        self.commandDelegate.run(inBackground: { [unowned self] in
            let pluginResult: CDVPluginResult
            if let reference = command.arguments[0] as? String {
                let anInt = self.getUserDefault().integer(forKey: reference)
                pluginResult = CDVPluginResult(status: .ok, messageAs: anInt)
            } else {
                pluginResult = CDVPluginResult(status: .error, messageAs: "Reference was null")
            }
            self.commandDelegate.send(pluginResult, callbackId: command.callbackId)
        })
    }

    @objc
    func putDouble(_ command: CDVInvokedUrlCommand) {
        self.commandDelegate.run(inBackground: { [unowned self] in
            let pluginResult: CDVPluginResult
            if let reference = command.arguments[0] as? String,
               let aDouble = command.arguments[1] as? Double {
                let defaults = self.getUserDefault()
                defaults.set(aDouble, forKey: reference)
                if defaults.synchronize() {
                    pluginResult = CDVPluginResult(status: .ok, messageAs: aDouble)
                } else {
                    pluginResult = CDVPluginResult(status: .error, messageAs: "Write has failed")
                }
            } else {
                pluginResult = CDVPluginResult(status: .error, messageAs: "Reference was null")
            }
            self.commandDelegate.send(pluginResult, callbackId: command.callbackId)
        })
    }

    @objc
    func getDouble(_ command: CDVInvokedUrlCommand) {
        self.commandDelegate.run(inBackground: { [unowned self] in
            let pluginResult: CDVPluginResult
            if let reference = command.arguments[0] as? String {
                let aDouble = self.getUserDefault().double(forKey: reference)
                pluginResult = CDVPluginResult(status: .ok, messageAs: aDouble)
            } else {
                pluginResult = CDVPluginResult(status: .error, messageAs: "Reference was null")
            }
            self.commandDelegate.send(pluginResult, callbackId: command.callbackId)
        })
    }

    @objc
    func putString(_ command: CDVInvokedUrlCommand) {
        self.commandDelegate.run(inBackground: { [unowned self] in
            let pluginResult: CDVPluginResult
            if let reference = command.arguments[0] as? String,
               let aString = command.arguments[1] as? String {
                let defaults = self.getUserDefault()
                defaults.set(aString, forKey: reference)
                if defaults.synchronize() {
                    pluginResult = CDVPluginResult(status: .ok, messageAs: aString)
                } else {
                    pluginResult = CDVPluginResult(status: .error, messageAs: "Write has failed")
                }
            } else {
                pluginResult = CDVPluginResult(status: .error, messageAs: "Reference was null")
            }
            self.commandDelegate.send(pluginResult, callbackId: command.callbackId)
        })
    }

    @objc
    func getString(_ command: CDVInvokedUrlCommand) {
        self.commandDelegate.run(inBackground: { [unowned self] in
            let pluginResult: CDVPluginResult
            if let reference = command.arguments[0] as? String {
                let aString = self.getUserDefault().string(forKey: reference)
                pluginResult = CDVPluginResult(status: .ok, messageAs: aString)
            } else {
                pluginResult = CDVPluginResult(status: .error, messageAs: "Reference was null")
            }
            self.commandDelegate.send(pluginResult, callbackId: command.callbackId)
        })
    }

    @objc
    func setItem(_ command: CDVInvokedUrlCommand) {
        self.commandDelegate.run(inBackground: { [unowned self] in
            let pluginResult: CDVPluginResult
            if let reference = command.arguments[0] as? String,
               let aString = command.arguments[1] as? String {
                let defaults = self.getUserDefault()
                defaults.set(aString, forKey: reference)
                if defaults.synchronize() {
                    pluginResult = CDVPluginResult(status: .ok, messageAs: aString)
                } else {
                    pluginResult = CDVPluginResult(status: .error, messageAs: 1)
                }
            } else {
                pluginResult = CDVPluginResult(status: .error, messageAs: 3)
            }
            self.commandDelegate.send(pluginResult, callbackId: command.callbackId)
        })
    }

    @objc
    func getItem(_ command: CDVInvokedUrlCommand) {
        self.commandDelegate.run(inBackground: { [unowned self] in
            let pluginResult: CDVPluginResult
            if let reference = command.arguments[0] as? String {
                if let aString = self.getUserDefault().string(forKey: reference) {
                    pluginResult = CDVPluginResult(status: .ok, messageAs: aString)
                } else {
                    // Reference not found
                    pluginResult = CDVPluginResult(status: .error, messageAs: 2)
                }
            } else {
                // Reference was null
                pluginResult = CDVPluginResult(status: .error, messageAs: 3)
            }
            self.commandDelegate.send(pluginResult, callbackId: command.callbackId)
        })
    }

    @objc
    func keys(_ command: CDVInvokedUrlCommand) {
        self.commandDelegate.run(inBackground: { [unowned self] in
            let keys = Array(self.getUserDefault().dictionaryRepresentation().keys)
            let pluginResult = CDVPluginResult(status: .ok, messageAs: keys)
            self.commandDelegate.send(pluginResult, callbackId: command.callbackId)
        })
    }

}
