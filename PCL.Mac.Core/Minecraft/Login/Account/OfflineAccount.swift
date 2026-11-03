//
//  OfflineAccount.swift
//  PCL.Mac
//
//  Created by YiZhiMCQiu on 2025/6/29.
//

import Foundation

public class OfflineAccount: Account {
    public let id: UUID
    public var uuid: UUID
    public var name: String

    /// 内置默认头像索引（0 ..< OfflineAvatarLibrary.count）
    public var avatarIndex: Int

    public init(_ name: String, _ uuid: UUID? = nil, avatarIndex: Int? = nil) {
        self.id = .init()
        self.name = name
        self.uuid = uuid ?? UUID.nameUUIDFromBytes(Array("OfflinePlayer:\(name)".utf8))
        if let avatarIndex {
            self.avatarIndex = OfflineAvatarLibrary.clamped(avatarIndex)
        } else {
            self.avatarIndex = OfflineAvatarLibrary.index(for: self.uuid)
        }
    }

    public func putAccessToken(options: LaunchOptions) {
        options.accessToken = UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()
    }

    // MARK: - Codable（兼容旧存档：缺少 avatarIndex 字段时按 UUID 稳定推导）

    enum CodingKeys: CodingKey {
        case id, uuid, name, avatarIndex
    }

    public required init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        uuid = try container.decode(UUID.self, forKey: .uuid)
        name = try container.decode(String.self, forKey: .name)
        if let saved = try container.decodeIfPresent(Int.self, forKey: .avatarIndex) {
            avatarIndex = OfflineAvatarLibrary.clamped(saved)
        } else {
            avatarIndex = OfflineAvatarLibrary.index(for: uuid)
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(uuid, forKey: .uuid)
        try container.encode(name, forKey: .name)
        try container.encode(avatarIndex, forKey: .avatarIndex)
    }
}
