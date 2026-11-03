//
//  MinecraftLauncher.swift
//  PCL.Mac
//
//  Created by YiZhiMCQiu on 2025/5/20.
//

import Foundation
import Cocoa

public class MinecraftLauncher {
    private let instance: MinecraftInstance
    private let id = UUID()
    public let logURL: URL
    
    public init?(_ instance: MinecraftInstance) {
        self.instance = instance
        self.logURL = SharedConstants.shared.applicationSupportURL.appending(path: "GameLogs").appending(path: id.uuidString + ".log")
        try? FileManager.default.createDirectory(at: logURL.parent(), withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: logURL.path, contents: Data())
    }
    
    public func launch(_ options: LaunchOptions, _ callback: @MainActor @escaping (Int32) -> Void = { _ in }) {
        // 启动前确保游戏默认简体中文
        ensureChineseLanguage()

        let process = Process()
        process.executableURL = options.javaPath
        process.environment = ProcessInfo.processInfo.environment
        process.arguments = []
        process.arguments!.append(contentsOf: buildJvmArguments(options))
        process.arguments!.append(instance.manifest.mainClass)
        process.arguments!.append(contentsOf: buildGameArguments(options))
        let command = process.executableURL!.path + " " + process.arguments!.joined(separator: " ")
            .replacingOccurrences(of: #"--accessToken\s+\S+"#, with: "--accessToken 🎉", options: .regularExpression)
        debug(command)
        MinecraftCrashHandler.lastLaunchCommand = command
        process.currentDirectoryURL = instance.runningDirectory

        if instance.config.qualityOfService.rawValue == 0 {
            instance.config.qualityOfService = .default
        }
        process.qualityOfService = instance.config.qualityOfService

        instance.process = process
        LaunchState.shared.set(.waitingWindow, "游戏已启动，正在等待窗口拉起……")
        do {
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = pipe

            let logHandle = try FileHandle(forWritingTo: logURL)
            pipe.fileHandleForReading.readabilityHandler = { handle in
                for line in String(data: handle.availableData, encoding: .utf8)!.split(separator: "\n") {
                    raw(line.replacing("\t", with: "    "))
                    try? logHandle.write(contentsOf: (line + "\n").data(using: .utf8)!)
                    logHandle.seekToEndOfFile()
                }
            }

            try process.run()

            Task { // 轮询判断窗口是否出现
                while process.isRunning {
                    let options = CGWindowListOption(arrayLiteral: .excludeDesktopElements, .optionOnScreenOnly)
                    guard let windowInfoList = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else {
                        try await Task.sleep(for: .seconds(1))
                        continue
                    }

                    for info in windowInfoList {
                        if let windowPID = info["kCGWindowOwnerPID"] as? Int32,
                           windowPID == process.processIdentifier {
                            log("窗口已出现")
                            LaunchState.shared.set(.windowShown, "游戏窗口已出现")
                            return
                        }
                    }
                    try await Task.sleep(for: .seconds(1))
                }
            }

            process.waitUntilExit()
            log("\(instance.name) 进程已退出, 退出代码 \(process.terminationStatus)")
            LaunchState.shared.set(.finished, "游戏已退出")
            if process.terminationStatus == 0 {
                debug("检测到退出代码为 0，已删除日志")
                try? FileManager.default.removeItem(at: self.logURL)
            }
            DispatchQueue.main.async {
                callback(process.terminationStatus)
            }
            instance.process = nil
        } catch {
            err(error.localizedDescription)
            LaunchState.shared.reset()
        }
    }

    /// 启动前把 options.txt 的语言固定为简体中文；文件缺失则创建最小配置。
    private func ensureChineseLanguage() {
        let optionsURL = instance.runningDirectory.appending(path: "options.txt")
        let targetLang = "zh_cn"

        if FileManager.default.fileExists(atPath: optionsURL.path) {
            guard var content = try? String(contentsOf: optionsURL, encoding: .utf8) else { return }
            var hasLang = false
            var lines = content.components(separatedBy: .newlines)
            for i in 0..<lines.count {
                if lines[i].hasPrefix("lang:") {
                    lines[i] = "lang:\(targetLang)"
                    hasLang = true
                    break
                }
            }
            if !hasLang {
                lines.append("lang:\(targetLang)")
            }
            content = lines.joined(separator: "\n")
            try? content.data(using: .utf8)?.write(to: optionsURL, options: .atomic)
        } else {
            try? FileManager.default.createDirectory(at: instance.runningDirectory, withIntermediateDirectories: true)
            try? "lang:\(targetLang)\n".data(using: .utf8)?.write(to: optionsURL, options: .atomic)
        }
    }
    
    public func buildJvmArguments(_ options: LaunchOptions) -> [String] {
        let values: [String: String] = [
            "natives_directory": instance.runningDirectory.appending(path: "natives").path,
            "launcher_name": "PCL.Mac",
            "launcher_version": SharedConstants.shared.version,
            "classpath": buildClasspath(),
            "classpath_separator": ":",
            "library_directory": instance.minecraftDirectory.librariesURL.path,
            "version_name": instance.name,
            "authlib_injector_path": SharedConstants.shared.authlibInjectorURL.path
        ]

        var args: [String] = [
            "-Xmx\(instance.config.maxMemory)m",
            "-Djna.tmpdir=${natives_directory}"
        ]

        // 参照 HMCL (DefaultLauncher.generateCommandLine) 的默认优化 JVM 参数
        let javaMajor = instance.manifest.javaVersion ?? 21

        // G1GC 调优：降低游戏运行中的 GC 停顿，缓解卡顿
        args.append(contentsOf: [
            "-XX:+UnlockExperimentalVMOptions",
            "-XX:+UnlockDiagnosticVMOptions",
            "-XX:+UseG1GC",
            "-XX:G1MixedGCCountTarget=5",
            "-XX:G1NewSizePercent=20",
            "-XX:G1ReservePercent=20",
            "-XX:MaxGCPauseMillis=50",
            "-XX:G1HeapRegionSize=32m",
            "-XX:-OmitStackTraceInFastThrow",
            "-XX:+DisableExplicitGC"
        ])

        // 物理内存大于 4GB 时，启用 HMCL 同款 JIT 代码缓存调优，减少编译卡顿
        if ProcessInfo.processInfo.physicalMemory > UInt64(4 * 1024 * 1024 * 1024) {
            args.append(contentsOf: [
                "-XX:-DontCompileHugeMethods",
                "-XX:MaxNodeLimit=240000",
                "-XX:NodeLimitFudgeFactor=8000",
                "-XX:TieredCompileTaskTimeout=10000",
                "-XX:ReservedCodeCacheSize=400M",
                "-XX:NmethodSweepActivity=1"
            ])
            if javaMajor >= 9 {
                args.append(contentsOf: [
                    "-XX:NonNMethodCodeHeapSize=12M",
                    "-XX:ProfiledCodeHeapSize=194M"
                ])
            }
        }

        // Java 24/25 放宽 sun.misc.Unsafe 访问，避免告警导致的降级与停顿
        if javaMajor == 24 || javaMajor == 25 {
            args.append("--sun-misc-unsafe-memory-access=allow")
        }

        // log4j2 RCE 防护（HMCL 同款）
        args.append(contentsOf: [
            "-Djava.rmi.server.useCodebaseOnly=true",
            "-Dcom.sun.jndi.rmi.object.trustURLCodebase=false",
            "-Dcom.sun.jndi.cosnaming.object.trustURLCodebase=false",
            "-Dlog4j2.formatMsgNoLookups=true"
        ])

        // 客户端 jar 路径与 Mac Dock 标题
        let clientJar = instance.runningDirectory.appending(path: "\(instance.name).jar")
        args.append("-Dminecraft.client.jar=\(clientJar.path)")
        #if os(macOS)
        args.append("-Xdock:name=Minecraft \(instance.version!.displayName)")
        #endif

        args.insert(contentsOf: options.yggdrasilArguments, at: 0)
        args.append(contentsOf: instance.manifest.getArguments().getAllowedJVMArguments())

        return Util.replaceTemplateStrings(args, with: values)
    }
    
    private func buildClasspath() -> String {
        // 去重
        ClientManifest.deduplicateLibraries(instance.manifest)
        
        var urls: [URL] = []
        for library in instance.manifest.getNeededLibraries() {
            if let artifact = library.artifact {
                urls.append(instance.minecraftDirectory.librariesURL.appending(path: artifact.path))
            }
        }
        urls.append(instance.runningDirectory.appending(path: "\(instance.name).jar"))

        return urls.map { $0.path }.joined(separator: ":")
    }
    
    private func buildGameArguments(_ options: LaunchOptions) -> [String] {
        let values: [String: String] = [
            "auth_player_name": options.playerName,
            "version_name": instance.version!.displayName,
            "game_directory": instance.runningDirectory.path,
            "assets_root": instance.minecraftDirectory.assetsURL.path,
            "assets_index_name": instance.manifest.assetIndex?.id ?? "",
            "auth_uuid": options.uuid.uuidString.replacingOccurrences(of: "-", with: "").lowercased(),
            "auth_access_token": options.accessToken,
            "user_type": "msa",
            "version_type": "PCL.Mac \(SharedConstants.shared.version)",
            "user_properties": "\"{}\"",
            // 离线账号没有这些字段，补空串避免命令行残留未替换的模板占位符
            "clientid": "",
            "auth_xuid": ""
        ]
        
        var args: [String] = []
        if options.isDemo {
            args.append("--demo")
        }
        
        return Util.replaceTemplateStrings(instance.manifest.getArguments().getAllowedGameArguments(), with: values).union(args)
    }
    
    public static func downloadAuthlibInjector() async throws {
        if FileManager.default.fileExists(atPath: SharedConstants.shared.authlibInjectorURL.path) { return }
        let json = try await Requests.get("https://bmclapi2.bangbang93.com/mirrors/authlib-injector/artifact/latest.json").getJSONOrThrow()
        guard let downloadURL = json["download_url"].url else {
            throw MyLocalizedError(reason: "无效的 authlib-injector 下载 URL")
        }
        try await SingleFileDownloader.download(url: downloadURL, destination: SharedConstants.shared.authlibInjectorURL)
        log("authlib-injector 下载完成")
    }
}

public enum LaunchPhase: Equatable {
    /// 空闲，可点击启动
    case idle
    /// 正在预检与资源完整性检查
    case preparing
    /// 游戏进程已拉起，正在等待游戏窗口出现
    case waitingWindow
    /// 游戏窗口已出现
    case windowShown
    /// 游戏进程已退出
    case finished
}

public class LaunchState: ObservableObject {
    public static let shared = LaunchState()

    @Published public var phase: LaunchPhase = .idle
    @Published public var statusText: String = ""

    /// 是否处于不可重复点击的启动流程中
    public var isBusy: Bool {
        phase == .preparing || phase == .waitingWindow
    }

    public func reset() {
        DispatchQueue.main.async {
            self.phase = .idle
            self.statusText = ""
        }
    }

    public func set(_ phase: LaunchPhase, _ statusText: String = "") {
        DispatchQueue.main.async {
            self.phase = phase
            self.statusText = statusText
        }
    }
}
