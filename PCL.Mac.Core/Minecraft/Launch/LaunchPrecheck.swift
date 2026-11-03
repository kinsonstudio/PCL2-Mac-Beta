//
//  LaunchPrecheck.swift
//  PCL.Mac
//
//  Created by YiZhiMCQiu on 2025/7/20.
//

import Foundation
import AppKit

public enum JavaCheckError: Error {
    case javaNotFound
    case noUsableJava(minVersion: Int)
    case javaNotSupport
    case invalidMemoryConfiguration
    case rosetta
}

public enum AccountCheckError: Error {
    case missingAccount
    case noMicrosoftAccount
}

public class LaunchPrecheck {
    public static func checkJava(_ instance: MinecraftInstance, _ options: LaunchOptions) -> Result<Void, JavaCheckError> {
        log("[launchPrecheck] 正在进行 Java 检查")
        let manifest = instance.manifest
        let minVersion = MinecraftInstance.getMinJavaVersion(instance.version, manifest: manifest)
        let suitableJava = MinecraftInstance.findSuitableJava(instance.version, manifest: manifest)
        if DataManager.shared.javaVirtualMachines
            .filter({ $0.executableURL.path != "/usr/bin/java" })
            .count == 0 {
            err("[launchPrecheck] 用户未安装 Java")
            return .failure(.javaNotFound)
        }
        
        if instance.config.maxMemory == 0 {
            return .failure(.invalidMemoryConfiguration)
        }
        
        // 当前已选 Java：仅在从未选择或所选文件丢失时才自动挑选；
        // 用户手动选定的 JDK（包括系统 /usr/bin/java）一律尊重，不静默切换；
        // 版本 / 架构不达标仅警告，由用户自行决定是否更换。
        let currentPath = instance.config.javaURL?.path
        let currentJvm = DataManager.shared.javaVirtualMachines.first { $0.executableURL.path == currentPath }
        let fileMissing = (currentPath == nil) || !FileManager.default.fileExists(atPath: currentPath!)
        let needsAutoSelect = fileMissing

        if needsAutoSelect {
            guard let suitableJava else {
                err("[launchPrecheck] 无可用 Java。最低版本: \(minVersion)")
                return .failure(.noUsableJava(minVersion: minVersion))
            }
            instance.config.javaURL = suitableJava.executableURL
            instance.saveConfig()
        } else if let currentJvm, currentJvm.version < minVersion {
            warn("[launchPrecheck] 所选 Java 主版本 \(currentJvm.version) 低于该版本需要的 \(minVersion)，可能无法启动；如需更换请在 Java 设置中手动选择")
        }
        let javaArchitecture = Architecture.getArchOfFile(instance.config.javaURL!)
        
        if Architecture.system == .x64 && javaArchitecture == .arm64 {
            err("[launchPrecheck] Java 架构不兼容")
            return .failure(.javaNotSupport)
        } else if Architecture.system == .arm64 && javaArchitecture == .x64 {
            // 没有满足版本的原生 JDK 时，允许 Rosetta 转译运行，仅警告不阻断启动
            warn("[launchPrecheck] 正在使用 x64 Java（Rosetta 转译），性能可能受限")
        }
        
        return .success(())
    }
    
    public static func checkAccount(_ instance: MinecraftInstance, _ options: LaunchOptions) -> Result<Void, AccountCheckError> {
        guard let account = AccountManager.shared.getAccount() else {
            err("无法启动 Minecraft: 未设置账号")
            return .failure(.missingAccount)
        }
        
        options.account = account
        
        if !AppSettings.shared.hasMicrosoftAccount {
            debug("[launchPrecheck] 未登录过正版账号")
            return .failure(.noMicrosoftAccount)
        }
        
        return .success(())
    }
}
