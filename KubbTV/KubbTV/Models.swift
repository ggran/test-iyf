import Foundation

/// 轻量 JSON 值：协议文档 §2.7 显示同一字段类型不稳定
/// （如 rating 既有字符串 "6.0" 又有数字 -1，year 有数字也有字符串），
/// 因此不用严格 Codable 结构体硬套，统一先解成 JSONValue 再映射。
enum JSONValue: Decodable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case object([String: JSONValue])
    case array([JSONValue])
    case null

    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { self = .null; return }
        if let b = try? c.decode(Bool.self) { self = .bool(b); return }
        if let n = try? c.decode(Double.self) { self = .number(n); return }
        if let s = try? c.decode(String.self) { self = .string(s); return }
        if let a = try? c.decode([JSONValue].self) { self = .array(a); return }
        if let o = try? c.decode([String: JSONValue].self) { self = .object(o); return }
        self = .null
    }

    var stringValue: String? {
        switch self {
        case .string(let s): return s
        case .number(let n): return n.truncatingRemainder(dividingBy: 1) == 0 ? String(Int(n)) : String(n)
        case .bool(let b): return b ? "true" : "false"
        default: return nil
        }
    }
    var boolValue: Bool {
        switch self {
        case .bool(let b): return b
        case .number(let n): return n != 0
        case .string(let s): return s == "true" || s == "1"
        default: return false
        }
    }
    var arrayValue: [JSONValue] {
        if case .array(let a) = self { return a }
        return []
    }
    var objectValue: [String: JSONValue] {
        if case .object(let o) = self { return o }
        return [:]
    }
    subscript(key: String) -> JSONValue? {
        if case .object(let o) = self { return o[key] }
        return nil
    }
}

/// 响应包络（协议文档 §2.1）：{"ret":200,"data":{"code":0,"msg":"","info":...},"msg":""}
struct Envelope: Decodable {
    let ret: Int?
    let data: EnvelopeData?
    let msg: String?
    struct EnvelopeData: Decodable {
        let code: Int
        let msg: String?
        let info: JSONValue?
    }
}

/// 列表/搜索条目（协议文档 §2.7 通用字段）。
struct VideoItem: Identifiable, Equatable {
    let key: String            // key：作品 key
    let lastKey: String?       // lastKey：最近一集 mediaKey（部分接口才有）
    let title: String
    let coverURL: URL?         // image / imgPath（static.kubb.tv）
    let categoryText: String?  // cid（中文类目或类目串，依接口而异）
    let typeName: String?      // atypeName：电影/电视剧等
    let lang: String?          // lang / language
    let year: String?
    let regional: String?
    let ratingText: String?    // rating / score / pingFen 多套并存，展示用
    let hot: String?
    let directed: String?      // directed / director
    let starring: String?
    let summary: String?       // contxt（搜索样本里该字段偶有异常值，仅作简介兜底展示）
    let isSerial: Bool
    let serialCount: String?
    let lastName: String?
    let vipResource: String?
    let episodes: [Episode]    // 搜索结果内嵌 languagesPlayList.playList[]

    var id: String { key.isEmpty ? title : key }

    /// 进入播放页时优先用的 mediaKey：内嵌分集第一项 > lastKey > 作品 key 本身。
    var initialMediaKey: String? {
        if let first = episodes.first?.key, !first.isEmpty { return first }
        if let lastKey, !lastKey.isEmpty { return lastKey }
        return key.isEmpty ? nil : key
    }
}

/// 分集/清晰度入口（搜索内嵌 languagesPlayList.playList[] 与
/// video/languagesplaylist 的 playList[] 同构，协议文档 §2.5 / §2.7）。
struct Episode: Identifiable, Equatable {
    let mediaKey: String  // key：作为新 mediaKey 重走 video/play（§3.9）
    let episodeID: String? // id
    let name: String      // name / title
    let isVIP: Bool
    let isBought: Bool
    let isNew: Bool
    let isLive: Bool
    var id: String { mediaKey.isEmpty ? name : mediaKey }
    var key: String { mediaKey }
}

/// 详情（协议文档 §2.5 video/detail 前端转换器消费的字段子集）。
struct VideoDetail {
    let title: String?
    let coverURL: URL?
    let summary: String?      // contxt
    let stars: String?        // stars
    let directors: String?    // directors
    let scoreText: String?    // score
    let year: String?         // post_Year
    let regional: String?
    let language: String?
    let isSerial: Bool
    let serialCount: String?
    let lastName: String?
}

/// 从 VideoItem 进入播放页时，先用搜索结果内嵌分集，languagesplaylist 成功后再替换。
enum VideoItemParser {
    static func parse(_ value: JSONValue) -> VideoItem? {
        let o = value.objectValue
        guard !o.isEmpty else { return nil }
        let episodes = o["languagesPlayList"]?["playList"]?.arrayValue.compactMap(EpisodeParser.parse) ?? []
        return VideoItem(
            key: o["key"]?.stringValue ?? "",
            lastKey: o["lastKey"]?.stringValue,
            title: o["title"]?.stringValue ?? "未命名",
            coverURL: coverURL(from: o),
            categoryText: o["cid"]?.stringValue,
            typeName: o["atypeName"]?.stringValue,
            lang: o["lang"]?.stringValue ?? o["language"]?.stringValue,
            year: o["year"]?.stringValue ?? o["post_Year"]?.stringValue,
            regional: o["regional"]?.stringValue,
            ratingText: o["rating"]?.stringValue ?? o["score"]?.stringValue ?? o["pingFen"]?.stringValue,
            hot: o["hot"]?.stringValue,
            directed: o["directed"]?.stringValue ?? o["director"]?.stringValue,
            starring: o["starring"]?.stringValue,
            summary: o["contxt"]?.stringValue,
            isSerial: o["isSerial"]?.boolValue ?? false,
            serialCount: o["serialCount"]?.stringValue,
            lastName: o["lastName"]?.stringValue,
            vipResource: o["vipResource"]?.stringValue,
            episodes: episodes
        )
    }

    /// 封面：image/imgPath 可能是完整 URL，也可能是 static 域相对路径（§1.2 / §2.7）。
    static func coverURL(from object: [String: JSONValue]) -> URL? {
        let raw = object["image"]?.stringValue ?? object["imgPath"]?.stringValue ?? object["img"]?.stringValue
        guard let raw, !raw.isEmpty else { return nil }
        if let url = URL(string: raw), url.scheme != nil { return url }
        return URL(string: raw, relativeTo: KubbConfig.staticBaseURL)
    }
}

enum EpisodeParser {
    static func parse(_ value: JSONValue) -> Episode? {
        let o = value.objectValue
        guard !o.isEmpty else { return nil }
        return Episode(
            mediaKey: o["key"]?.stringValue ?? "",
            episodeID: o["id"]?.stringValue,
            name: o["name"]?.stringValue ?? o["title"]?.stringValue ?? "正片",
            isVIP: o["isVIP"]?.boolValue ?? o["isVip"]?.boolValue ?? false,
            isBought: o["isBought"]?.boolValue ?? false,
            isNew: o["isNew"]?.boolValue ?? false,
            isLive: o["isLive"]?.boolValue ?? false
        )
    }
}
