//
//  OfflineAvatarLibrary.swift
//  PCL.Mac
//
//  离线账号内置默认头像库：负责索引分配、随机选择与旧账号稳定映射。
//  皮肤图片资源位于 App 层 Assets.xcassets，本类型只做纯逻辑计算。
//

import Foundation

public enum OfflineAvatarLibrary {
    /// 内置默认头像数量（与 Assets.xcassets/Avatars/OfflineAvatar{0..7}.imageset 一一对应）
    public static let count = 8

    /// 新建账号时未手动挑选头像，随机分配一个索引
    public static func randomIndex() -> Int {
        Int.random(in: 0..<count)
    }

    /// 旧存档（未保存头像索引）根据 UUID 稳定映射到一个头像，保证每次启动头像一致
    public static func index(for uuid: UUID) -> Int {
        let bytes = withUnsafeBytes(of: uuid.uuid) { Array($0) }
        let sum = bytes.map(Int.init).reduce(0, +)
        return sum % count
    }

    /// 越界索引归一到合法范围，避免损坏数据导致越界崩溃
    public static func clamped(_ index: Int) -> Int {
        guard index >= 0, index < count else { return 0 }
        return index
    }
}
