//
//  JavaSearch.swift
//  PCL.Mac
//
//  Created by YiZhiMCQiu on 2025/5/18.
//
// 不改了，能跑就不要动
//          by YiZhiMCQiu at 2025/6/6 in fix & optimizations (1)
// 还是改改罢，JRE 搜索炸了
//          by YiZhiMCQiu at 2025/6/28 in main

import Foundation

public class JavaSearch {
    public static func searchAndSet() throws {
        let before = Date().timeIntervalSince1970
        DataManager.shared.javaVirtualMachines = try search()
        DataManager.shared.lastTimeUsed = Int((Date().timeIntervalSince1970 - before) * 1000)
        log("搜索 Java 耗时 \(DataManager.shared.lastTimeUsed)ms")
        
        loadCustomJVMs()
    }
    
    private static func loadCustomJVMs() {
        for url in AppSettings.shared.userAddedJvmPaths {
            DataManager.shared.javaVirtualMachines.append(JavaVirtualMachine.of(url, true))
        }
        log("加载了 \(AppSettings.shared.userAddedJvmPaths.count) 个由用户添加的 Java")
    }
    
    public static func search() throws -> [JavaVirtualMachine] {
        var executableURLs: [URL] = [
            URL(fileURLWithPath: "/usr/bin/java")
        ]

        let javaDirectoryParents = [
            "/Library/Java/JavaVirtualMachines",
            "~/Library/Java/JavaVirtualMachines",
            "/opt/homebrew/opt/java/libexec",
            "/opt/homebrew/Cellar",
            "~/.sdkman/candidates/java"
        ]
            .map { URL(fileURLWithUserPath: $0).path }
            .filter { FileManager.default.fileExists(atPath: $0) }

        for javaDirectoryParent in javaDirectoryParents {
            let parentURL = URL(fileURLWithPath: javaDirectoryParent)
            guard let javaDirectories = try? FileManager.default.contentsOfDirectory(atPath: javaDirectoryParent) else { continue }

            for javaDirectory in javaDirectories {
                // /opt/homebrew/Cellar 下是 openjdk@21/1.21.0 这种两层结构，需要再往下找 Contents/Home
                let candidates: [URL] = [
                    parentURL.appending(path: javaDirectory).appending(path: "Contents").appending(path: "Home"),
                    parentURL.appending(path: javaDirectory)
                ]
                for javaHomeURL in candidates {
                    let binJava = javaHomeURL.appending(path: "bin").appending(path: "java")
                    if FileManager.default.fileExists(atPath: binJava.path) {
                        executableURLs.append(binJava)
                    }
                    let jreJava = javaHomeURL.appending(path: "jre").appending(path: "bin").appending(path: "java")
                    if FileManager.default.fileExists(atPath: jreJava.path) {
                        executableURLs.append(jreJava)
                    }
                }

                // Cellar 两层：openjdk@21/1.21.0/Contents/Home
                let nested = parentURL.appending(path: javaDirectory)
                if let nestedDirs = try? FileManager.default.contentsOfDirectory(atPath: nested.path) {
                    for nestedDir in nestedDirs {
                        let javaHomeURL = nested.appending(path: nestedDir).appending(path: "Contents").appending(path: "Home")
                        let binJava = javaHomeURL.appending(path: "bin").appending(path: "java")
                        if FileManager.default.fileExists(atPath: binJava.path) {
                            executableURLs.append(binJava)
                        }
                    }
                }
            }
        }

        // 去重，避免同一 java 路径被重复收录
        let uniqueURLs = Array(Set(executableURLs.filter { FileManager.default.fileExists(atPath: $0.path) }))

        let result = uniqueURLs
            .map { JavaVirtualMachine.of($0) }
            .filter { !$0.isError }

        log("扫描到 \(result.count) 个可用 Java")
        return result
    }
    
    private static func isValidJvmDirectory(_ path: URL) -> Bool {
        var isDirectory: ObjCBool = false
        return FileManager.default.fileExists(atPath: toJvmDirectory(path).appending(path: "java").path(), isDirectory: &isDirectory) && !isDirectory.boolValue
    }
    
    private static func toJvmDirectory(_ path: URL) -> URL {
        return path.appending(path: "Contents").appending(path: "Home").appending(path: "bin")
    }
}
