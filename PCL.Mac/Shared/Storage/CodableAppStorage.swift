//
//  CodableAppStorage.swift
//  PCL.Mac
//
//  Created by YiZhiMCQiu on 2025/6/3.
//

import Foundation

/// 非泛型的进程内引用缓存（泛型类型内不允许声明静态存储属性）
private final class StorageReferenceCache {
    static let shared = StorageReferenceCache()
    var cache: [String: Any] = [:]
    let lock = NSLock()
}

@propertyWrapper
public struct CodableAppStorage<T: Codable> {
    private let key: String
    private let store: UserDefaults
    private let defaultValue: T

    public var wrappedValue: T {
        get {
            let cache = StorageReferenceCache.shared
            cache.lock.lock()
            defer { cache.lock.unlock() }

            if let cached = cache.cache[key] as? T {
                return cached
            }

            let decoded: T
            if let data = store.data(forKey: key),
               let value = try? JSONDecoder().decode(T.self, from: data) {
                decoded = value
            } else {
                decoded = defaultValue
            }

            cache.cache[key] = decoded
            return decoded
        }
        set {
            let cache = StorageReferenceCache.shared
            cache.lock.lock()
            cache.cache[key] = newValue
            cache.lock.unlock()

            if let data = try? JSONEncoder().encode(newValue) {
                store.set(data, forKey: key)
            }
            DispatchQueue.main.async {
                DataManager.shared.objectWillChange.send()
            }
        }
    }

    public init(wrappedValue: T, _ key: String, store: UserDefaults = .standard) {
        self.key = key
        self.store = store
        self.defaultValue = wrappedValue
        // 初始写入（仅当没有值时）
        if store.data(forKey: key) == nil,
           let data = try? JSONEncoder().encode(wrappedValue) {
            store.set(data, forKey: key)
        }
    }
}
