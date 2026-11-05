import Foundation

/// 播放源（协议文档 §2.5 video/play、§4.1）。
/// 【重要未确认】video/play 成功回包原文从未取得（§6 未确认项 1），以下字段来自前端代码证据：
/// info[0] 含 key, mediaKey, mediaTitle, uniqueKey, clarity[], tracks, flvPathList[],
/// startData[], pauseData[], maxFrontAds, barrageData[], barrageStatus, customData,
/// videoServer, isLimitedStream, isUserFilterAd, needLogin, startSecond, previewFormat。
/// 条目转播放地址的规则（§4.1 converHtml5ToMedia2）：
///   src = uriSignature(item.result)；href = link（有 link 即广告）；type = isHls ? HLS : MP4。
/// 本文件就是这条链的集中可替换点：真机拿到第一份成功回包后，若字段名/层级不同，只改这里。
struct PlaySource {
    let mediaKey: String?
    let workKey: String?       // key：作品 key，变化时再拉详情（§3.6）
    let title: String?         // mediaTitle
    let uniqueKey: String?
    let needLogin: Bool
    let isLimitedStream: Bool
    let startSecond: Double    // startSecond>0 时 seek 续播（§3.7）
    /// 正片候选（已剔除带 link 的广告项；前贴 startData 按要求不播广告，故不纳入）。
    let mainMedia: [PlayableMedia]
    let clarityLabels: [String]
}

struct PlayableMedia: Identifiable, Equatable {
    let url: URL
    let isHLS: Bool            // .m3u8 → application/vnd.apple.mpegurl，AVPlayer 原生支持
    let needsSignedURL: Bool   // 条目带 needSign 且当前未配置签名/uriSignature 时为 true（§4.3）
    var id: String { url.absoluteString }
}

enum PlaySourceParser {
    static func parse(_ infoFirst: JSONValue) -> PlaySource {
        let o = infoFirst.objectValue

        // 正片：flvPathList 中不带 link 的条目（带 link = 广告，§4.3 第 2 点）。本测试版不播广告。
        var media: [PlayableMedia] = []
        for item in o["flvPathList"]?.arrayValue ?? [] {
            let io = item.objectValue
            let link = io["link"]?.stringValue ?? ""
            guard link.isEmpty else { continue } // 广告项跳过
            guard let playable = playable(from: io) else { continue }
            media.append(playable)
        }
        // 兜底：无 flvPathList 时尝试 clarity[]（条目带 path/key，§3.8）。
        var clarityLabels: [String] = []
        for item in o["clarity"]?.arrayValue ?? [] {
            let io = item.objectValue
            if let label = io["name"]?.stringValue ?? io["title"]?.stringValue ?? io["sharpness"]?.stringValue {
                clarityLabels.append(label)
            }
            if media.isEmpty, let playable = playable(from: io) { media.append(playable) }
        }

        return PlaySource(
            mediaKey: o["mediaKey"]?.stringValue,
            workKey: o["key"]?.stringValue,
            title: o["mediaTitle"]?.stringValue,
            uniqueKey: o["uniqueKey"]?.stringValue,
            needLogin: o["needLogin"]?.boolValue ?? false,
            isLimitedStream: o["isLimitedStream"]?.boolValue ?? false,
            startSecond: Double(o["startSecond"]?.stringValue ?? "") ?? 0,
            mainMedia: media,
            clarityLabels: clarityLabels
        )
    }

    private static func playable(from item: [String: JSONValue]) -> PlayableMedia? {
        // result 为文档确认的源字段（§4.1）；path 为 clarity 条目字段（§3.8）。
        let raw = item["result"]?.stringValue ?? item["path"]?.stringValue ?? ""
        guard let url = MediaURLProcessor.playableURL(fromResult: raw) else { return nil }
        let isHLS = (item["isHls"]?.boolValue ?? false) || url.pathExtension.lowercased() == "m3u8"
        let needSign = item["needSign"]?.boolValue ?? false
        return PlayableMedia(url: url, isHLS: isHLS, needsSignedURL: needSign && !KubbConfig.signer.isConfigured)
    }
}
