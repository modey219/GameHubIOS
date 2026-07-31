import Foundation

private let envLock = NSLock()

func safeSetenv(_ key: String, _ value: String, _ overwrite: Int32 = 1) {
    envLock.lock()
    setenv(key, value, overwrite)
    envLock.unlock()
}
