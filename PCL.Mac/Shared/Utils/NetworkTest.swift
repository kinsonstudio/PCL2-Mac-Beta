//
//  NetworkTest.swift
//  PCL.Mac
//
//  Created by YiZhiMCQiu on 2025/6/3.
//

import Foundation
import Network

public class NetworkTest {
    public static let shared = NetworkTest()
    private let monitor = NWPathMonitor()
    private let lock = NSLock()
    private var isConnected: Bool = false
    private var hasReceivedPath: Bool = false
    private let firstPathSemaphore = DispatchSemaphore(value: 0)

    private init() {
        monitor.pathUpdateHandler = { [weak self] path in
            guard let self else { return }
            self.lock.lock()
            self.isConnected = (path.status == .satisfied)
            self.hasReceivedPath = true
            self.lock.unlock()
            self.firstPathSemaphore.signal()
        }
        monitor.start(queue: DispatchQueue.global(qos: .userInitiated))
    }

    public func hasNetworkConnection(timeout: TimeInterval = 2.0) -> Bool {
        lock.lock()
        let received = hasReceivedPath
        lock.unlock()

        if !received {
            // 首次调用等待首次路径回调，避免 currentPath 尚未就绪时误判离线
            _ = firstPathSemaphore.wait(timeout: .now() + timeout)
        }

        lock.lock()
        let connected = isConnected
        lock.unlock()
        return connected
    }
}
