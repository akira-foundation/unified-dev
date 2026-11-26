import Foundation

enum SettingsColumns {
    static let read = "SELECT value FROM settings WHERE key = ?"

    static let write = "INSERT INTO settings (key, value) VALUES (?, ?) ON CONFLICT(key) DO UPDATE SET value = excluded.value"

    static let clear = "DELETE FROM settings WHERE key = ?"
}
