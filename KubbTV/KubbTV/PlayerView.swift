import SwiftUI
import AVKit
import AVFoundation

/// 播放页：搜索结果点击进入（§3.6 详情装配 + §3.7 播放启动 + §3.9 选集）。
/// 流程：mediaKey → video/play 拿真实播放地址 → AVPlayer 播放；
/// 同时拉 video/detail 与 video/languagesplaylist 补详情与选集（失败不阻塞，单独提示）。
struct PlayerView: View {
    let item: VideoItem

    @State private var player: AVPlayer?
    @State private var detail: VideoDetail?
    @State private var episodes: [Episode]
    @State private var currentMediaKey: String?
    @State private var statusText: String = "正在获取播放地址…"
    @State private var errorText: String?
    @State private var detailErrorText: String?
    @State private var isLoading = true
    @State private var playerItemObservation: NSKeyValueObservation?

    init(item: VideoItem) {
        self.item = item
        _episodes = State(initialValue: item.episodes)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                playerArea
                titleBlock
                if let errorText {
                    Label(errorText, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.red).font(.subheadline)
                }
                if let detailErrorText {
                    Label("详情/选集：\(detailErrorText)", systemImage: "info.circle")
                        .foregroundStyle(.secondary).font(.caption)
                }
                if !episodes.isEmpty { episodePicker }
                if let summary = detail?.summary ?? item.summary, !summary.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("简介").font(.headline)
                        Text(summary).font(.body).foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding()
        }
        .navigationTitle(item.title)
        .navigationBarTitleDisplayMode(.inline)
        .task { await loadAll() }
        .onDisappear {
            player?.pause()
            playerItemObservation?.invalidate()
        }
    }

    // MARK: 播放器区域
    private var playerArea: some View {
        ZStack {
            Color.black
            if let player {
                VideoPlayer(player: player)
            } else if isLoading {
                VStack(spacing: 8) {
                    ProgressView().tint(.white)
                    Text(statusText).foregroundStyle(.white).font(.caption)
                }
            } else {
                VStack(spacing: 8) {
                    Image(systemName: "play.slash").foregroundStyle(.white).font(.largeTitle)
                    Text(statusText).foregroundStyle(.white).font(.caption)
                        .multilineTextAlignment(.center).padding(.horizontal)
                }
            }
        }
        .aspectRatio(16 / 9, contentMode: .fit)
        .cornerRadius(8)
    }

    private var titleBlock: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(detail?.title ?? item.title).font(.title3).bold()
            let parts = [detail?.year ?? item.year, detail?.regional ?? item.regional,
                         detail?.language ?? item.lang, detail?.scoreText ?? item.ratingText]
                .compactMap { $0 }.filter { !$0.isEmpty }
            if !parts.isEmpty {
                Text(parts.joined(separator: " · ")).font(.subheadline).foregroundStyle(.secondary)
            }
            if let stars = detail?.stars, !stars.isEmpty {
                Text("主演：\(stars)").font(.caption).foregroundStyle(.secondary)
            }
            if let directors = detail?.directors, !directors.isEmpty {
                Text("导演：\(directors)").font(.caption).foregroundStyle(.secondary)
            }
            Text(statusText).font(.caption).foregroundStyle(.secondary)
        }
    }

    private var episodePicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("选集 / 清晰度入口").font(.headline)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 96))], spacing: 8) {
                ForEach(episodes) { episode in
                    Button {
                        Task { await play(mediaKey: episode.key) }
                    } label: {
                        VStack(spacing: 2) {
                            Text(episode.name).lineLimit(1)
                            if episode.isVIP {
                                Text("VIP").font(.caption2).foregroundStyle(.orange)
                            }
                        }
                        .frame(maxWidth: .infinity).padding(.vertical, 8)
                        .background(currentMediaKey == episode.key ? Color.accentColor.opacity(0.25) : Color.gray.opacity(0.15))
                        .cornerRadius(6)
                    }
                    .buttonStyle(.plain)
                    .disabled(episode.key.isEmpty)
                }
            }
        }
    }

    // MARK: 加载链
    private func loadAll() async {
        // 详情与选集与播放并行；任一失败只提示，不臆造数据（§3.6）。
        async let detailTask: Void = loadDetail()
        async let playlistTask: Void = loadPlaylist()
        await play(mediaKey: item.initialMediaKey)
        await detailTask
        await playlistTask
    }

    private func loadDetail() async {
        do { detail = try await KubbAPIClient.shared.detail(workKey: item.key) }
        catch { detailErrorText = SearchViewModel.message(for: error) }
    }

    private func loadPlaylist() async {
        do {
            let fetched = try await KubbAPIClient.shared.languagesPlaylist(workKey: item.key)
            if !fetched.isEmpty { episodes = fetched }
        } catch {
            // 与详情共用一行提示，避免覆盖。
            if detailErrorText == nil { detailErrorText = SearchViewModel.message(for: error) }
        }
    }

    /// §3.7：renderPlayer → getMedia → invokePlayVideo。拿到正片地址后用系统播放器播。
    private func play(mediaKey: String?) async {
        guard let mediaKey, !mediaKey.isEmpty else {
            isLoading = false
            statusText = "搜索结果没有可用的 mediaKey（lastKey / 内嵌分集均为空）"
            errorText = "无法确定要播放的 mediaKey，未臆造地址。"
            return
        }
        isLoading = true
        errorText = nil
        currentMediaKey = mediaKey
        statusText = "正在获取播放地址（video/play）…"
        do {
            let source = try await KubbAPIClient.shared.playSource(mediaKey: mediaKey)
            if source.needLogin {
                isLoading = false
                statusText = "该内容需要登录（needLogin），未登录状态下不播正片（§3.7）。"
                return
            }
            if source.isLimitedStream {
                isLoading = false
                statusText = "直播限流（isLimitedStream），正片不播（§3.7）。"
                return
            }
            guard let media = source.mainMedia.first else {
                isLoading = false
                statusText = "video/play 已返回，但未解析到正片地址。"
                errorText = "flvPathList/clarity 中没有不带 link 的正片条目，或 result 为空。成功回包字段未经实测确认（协议文档 §6 未确认项 1），请按 README 在 Xcode 真机抓第一份回包后核对 PlaySource.swift。"
                return
            }
            configurePlayer(with: media, startSecond: source.startSecond)
            statusText = media.needsSignedURL
                ? "已解析到地址，但条目标记 needSign 且签名未配置，播放可能失败（需 uriSignature，§4.1）。"
                : (source.startSecond > 0 ? "已为您跳到上次播放的时间" : "正在播放")
            isLoading = false
        } catch {
            isLoading = false
            statusText = "播放地址获取失败"
            errorText = SearchViewModel.message(for: error)
                + (KubbConfig.signer.isConfigured ? "" : "\n当前未配置 vv/pub 签名（协议文档已脱敏）。无签名调用 video/play 实测返回「用户签名错误」；接入签名的方法见 README 与 KubbConfig.swift。")
        }
    }

    private func configurePlayer(with media: PlayableMedia, startSecond: Double) {
        player?.pause()
        playerItemObservation?.invalidate()
        // m3u8（HLS）与 MP4 均由 AVPlayer 原生处理（§4.1 的 type 区分）；特殊请求头集中在 KubbConfig.mediaHTTPHeaders。
        let asset: AVURLAsset
        if KubbConfig.mediaHTTPHeaders.isEmpty {
            asset = AVURLAsset(url: media.url)
        } else {
            asset = AVURLAsset(url: media.url, options: [AVURLAssetHTTPHeaderFieldsKey: KubbConfig.mediaHTTPHeaders])
        }
        let item = AVPlayerItem(asset: asset)
        let newPlayer = AVPlayer(playerItem: item)
        playerItemObservation = item.observe(\.status, options: [.new]) { observed, _ in
            if observed.status == .failed {
                Task { @MainActor in
                    self.statusText = "播放器加载失败"
                    self.errorText = observed.error?.localizedDescription ?? "AVPlayerItem 状态 failed（可能是地址需签名、需请求头或网络问题）"
                }
            }
        }
        player = newPlayer
        if startSecond > 0 {
            newPlayer.seek(to: CMTime(seconds: startSecond, preferredTimescale: 600))
        }
        newPlayer.play()
    }
}
