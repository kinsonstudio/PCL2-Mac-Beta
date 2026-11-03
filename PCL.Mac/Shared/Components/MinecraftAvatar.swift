//
//  MinecraftAvatar.swift
//  PCL.Mac
//
//  Created by YiZhiMCQiu on 2025/6/30.
//

import SwiftUI
import AppKit
import CoreGraphics

/// 读取内置离线头像皮肤（64×64）原始图像数据，供皮肤裁剪组件使用。
/// 离线账号完全走本地资源，不发起网络请求，保证添加后第一时间显示。
func offlineAvatarSkinData(_ index: Int) -> Data? {
    let name = "OfflineAvatar\(OfflineAvatarLibrary.clamped(index))"
    guard let image = NSImage(named: name),
          let tiff = image.tiffRepresentation,
          let rep = NSBitmapImageRep(data: tiff),
          let png = rep.representation(using: NSBitmapImageRep.FileType.png, properties: [:]) else { return nil }
    return png
}

struct MinecraftAvatar: View {
    @State private var skinData: Data?

    private let account: AnyAccount
    private let src: String
    private let size: CGFloat

    init(account: AnyAccount, src: String, size: CGFloat = 58) {
        self.account = account
        self.src = src
        self.size = size
        switch account {
        case .offline(let offline):
            // 离线账号：初始化时即从内置皮肤库读取，同步赋值，不等待网络
            self._skinData = State(initialValue: offlineAvatarSkinData(offline.avatarIndex))
        default:
            if let cached = SkinCacheStorage.shared.skinCache[account.uuid] {
                self._skinData = State(initialValue: cached)
            }
        }
    }

    var body: some View {
        ZStack {
            if let data = skinData {
                SkinLayerView(imageData: data, startX: 8, startY: 16, width: 8 * 5.4 / 58 * size, height: 8 * 5.4 / 58 * size)
                    .shadow(color: Color.black.opacity(0.2), radius: 1)
                SkinLayerView(imageData: data, startX: 40, startY: 16, width: 7.99 * 6.1 / 58 * size, height: 7.99 * 6.1 / 58 * size)
            }
        }
        .frame(width: size, height: size)
        .clipped()
        .padding(6)
        .task {
            // 离线账号已使用本地皮肤，无需联网；仅微软 / 外置账号在无缓存时加载网络皮肤
            guard skinData == nil else { return }
            if case .offline = account { return }
            do {
                self.skinData = try await SkinCacheStorage.shared.loadSkin(account: account)
            } catch {
                err("无法加载头像: \(error.localizedDescription)")
            }
        }
    }
}

/// 新建离线账号表单里使用的内置头像预览方块（仅渲染正面 8×8 头像）
struct OfflineAvatarPreview: View {
    let index: Int
    var size: CGFloat = 40

    var body: some View {
        Group {
            if let data = offlineAvatarSkinData(index) {
                SkinLayerView(imageData: data, startX: 8, startY: 16, width: size, height: size)
            } else {
                Color.clear
            }
        }
        .frame(width: size, height: size)
        .clipped()
    }
}

struct SkinLayerView: View {
    let imageData: Data
    let startX: CGFloat
    let startY: CGFloat
    let width: CGFloat
    let height: CGFloat
    @State private var image: NSImage?

    var body: some View {
        Group {
            if let image = image {
                Image(nsImage: image)
                    .interpolation(.none)
                    .resizable()
                    .frame(width: width, height: height)
            } else {
                Color.clear
            }
        }
        .onAppear {
            if var image = CIImage(data: imageData) {
                let yOffset: CGFloat = image.extent.height == 32 ? 0 : 32
                image = image.cropped(to: CGRect(x: startX, y: startY + yOffset, width: 8, height: 8))
                let context = CIContext(options: nil)
                let extent = image.extent
                guard let cgImage = context.createCGImage(image, from: extent) else { return }
                self.image = NSImage(cgImage: cgImage, size: image.extent.size)
            } else {
                err("无法获取头像")
            }
        }
    }
}
