import Foundation

struct PasteLightThresholdStore {
    private static let userDefaultsKey = "julia_confidence_threshold"
    private static let fileName = "paste-light-threshold.json"

    static func loadThreshold(defaultValue: Double = 1.0) -> Double {
        if let fileValue = loadFromFile() {
            return fileValue
        }
        if UserDefaults.standard.object(forKey: userDefaultsKey) != nil {
            return UserDefaults.standard.double(forKey: userDefaultsKey)
        }
        return defaultValue
    }

    static func saveUserThreshold(_ value: Double) {
        UserDefaults.standard.set(value, forKey: userDefaultsKey)
    }

    static func fileURL() -> URL? {
        let appName = AppName.displayName
        guard let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent(appName, isDirectory: true) else {
            return nil
        }
        return base.appendingPathComponent(fileName)
    }

    private static func loadFromFile() -> Double? {
        guard let url = fileURL(),
              let data = try? Data(contentsOf: url),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let threshold = json["threshold"] as? Double else {
            return nil
        }
        return threshold
    }
}
