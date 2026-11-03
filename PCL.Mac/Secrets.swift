//
//  Secrets.swift
//  PCL.Mac
//
//  Created by YiZhiMCQiu on 2025/7/13.
//

import Foundation

public let ARTIFACT_PAT: String = ""
// 临时借用 Prism Launcher 已注册的公开 Azure AD（v2）应用用于设备码登录，仅供本机自用；
// 后续应替换为 PCL.Mac 自己注册的 Entra 应用 client id。
public let CLIENT_ID: String = "c36a9fb6-4f2a-41ff-90bd-ae7cc92031eb"
public let THEME_KEY: String = ""

public class Secrets {
    public static func getClientID() -> String {
        if !CLIENT_ID.starts(with: "{{") {
            return CLIENT_ID
        }
        
        return ProcessInfo.processInfo.environment["CLIENT_ID"] ?? "" // 本地调试使用
    }
}
