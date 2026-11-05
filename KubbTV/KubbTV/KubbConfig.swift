import Foundation

/// 集中配置层：所有接口地址、参数默认值、可替换的签名/播放地址处理都在这里。
/// 依据 docs/kubb-tv-technical-report.md（下称「协议文档」），不要臆造接口。
///
/// 已知关键缺口（协议文档脱敏/未确认，见 README「已知限制」）：
/// 1. 统一请求管线的 `vv/pub` MD5 签名（协议文档 §5.1）只描述了形态，
///    公钥/私钥与确切拼接顺序均脱敏，未给出可复用的签名成品。
///    因此默认使用 `UnconfiguredRequestSigner`（不加签名）。
///    实测（2026-11-05，Linux curl、无签名、未登录）：
///    `list/briefsearch` 可返回 code:0 数据；`video/detail`、`video/play`、
///    `video/languagesplaylist` 返回 code:1「用户签名错误」。
/// 2. `video/play` 成功回包原文从未被协议文档取得（§6 未确认项 1），
///    `clarity[]/flvPathList[]` 的真实条目字段以代码证据为准，见 PlaySource.swift。
enum KubbConfig {
    // MARK: 子域（协议文档 §1.2，均按 kubb.tv 实例化）
    static let searchBaseURL = URL(string: "https://rankv21.kubb.tv")! // RANK / APIV3RANK
    static let mainBaseURL = URL(string: "https://m10.kubb.tv")!       // API_ENDPOINT / APIV3_ENDPOINT
    static let staticBaseURL = URL(string: "https://static.kubb.tv")! // resourceHost，封面/海报

    // MARK: 通用参数（协议文档 §2.3 / §2.5 / §1.5）
    static let cinema = "1"
    static let apiVersion = "1"          // appendApiVersion 补的 v=1；已自带 v 的接口不重复加
    static let region = "US"             // 实测样本地区；详情/播放的 region 来自本地配置，缺省见文档
    static let language = "cns"          // 详情注册默认 lang
    static let country = "HU"            // 详情注册默认 country
    static let searchPageSize = 10       // 搜索页默认 size（§2.3）
    static let playlistTaxis: String? = nil // languagesplaylist 的 taxis 默认值文档未给确切值，未确认前不臆造

    // MARK: 播放器媒体请求头（可替换点）
    /// 协议文档未确认播放 CDN 需要任何特殊请求头（无 Referer/UA/Cookie 的确切结论）。
    /// 默认空：AVPlayer 直接播接口下发地址。若在 Xcode 真机抓包确认 CDN 需要请求头，
    /// 只改这里（键值会通过 AVURLAssetHTTPHeaderFieldsKey 传给 AVPlayer）。
    static let mediaHTTPHeaders: [String: String] = [:]

    // MARK: 签名（可替换点）
    /// 默认未配置签名。要接入真实签名，实现 `RequestSigning` 并替换这一行即可，
    /// 业务代码（搜索/详情/播放调用）无需改动。
    /// 注意：不要把从公开页面抓到的密钥硬编码进仓库（协议文档 §5.2）。
    static let signer: RequestSigning = UnconfiguredRequestSigner()
    // 接入示例（vv/pub 由你自己的签名实现提供时）：
    // static let signer: RequestSigning = StaticVVPubSigner(vv: "<签名值>", pub: "<公钥标识>")
}

/// 请求签名协议层（协议文档 §1.5 第 3 步、§5.1）。
/// GET 对最终查询串签名并追加 vv/pub；POST 对表单 body 串签名并追加 vv/pub。
/// 签名对参数顺序与大小写敏感，因此全项目统一用有序参数数组拼串。
protocol RequestSigning {
    /// 返回追加签名后的 (查询参数, body 参数)。未配置签名时原样返回。
    func signed(queryItems: [(String, String)], bodyItems: [(String, String)], isPOST: Bool) -> (query: [(String, String)], body: [(String, String)])
    /// 是否已配置签名。播放页据此提示「播放地址可能还需 uriSignature 处理」。
    var isConfigured: Bool { get }
}

/// 默认实现：不加签名。无签名时部分只读接口仍可调（见 KubbConfig 注释中的实测）。
struct UnconfiguredRequestSigner: RequestSigning {
    var isConfigured: Bool { false }
    func signed(queryItems: [(String, String)], bodyItems: [(String, String)], isPOST: Bool) -> (query: [(String, String)], body: [(String, String)]) {
        (queryItems, bodyItems)
    }
}

/// 占位实现：当你已有办法得到 vv/pub（例如自有服务端代签）时，用它把两个参数接上。
/// 本工程不实现 MD5 计算：协议文档对算法只给形态、密钥脱敏，臆造拼接顺序只会得到「用户签名错误」。
struct StaticVVPubSigner: RequestSigning {
    let vv: String
    let pub: String
    var isConfigured: Bool { !vv.isEmpty && !pub.isEmpty }
    func signed(queryItems: [(String, String)], bodyItems: [(String, String)], isPOST: Bool) -> (query: [(String, String)], body: [(String, String)]) {
        guard isConfigured else { return (queryItems, bodyItems) }
        if isPOST {
            return (queryItems, bodyItems + [("vv", vv), ("pub", pub)])
        }
        return (queryItems + [("vv", vv), ("pub", pub)], bodyItems)
    }
}

/// 播放地址处理（协议文档 §4.1：`src = uriSignature(item.result)`）。
/// uriSignature 的确切规则同样未确认，默认原样返回 result；
/// 若真机确认 result 还需签名/改写，只替换这一个函数。
enum MediaURLProcessor {
    static func playableURL(fromResult result: String) -> URL? {
        let trimmed = result.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if let url = URL(string: trimmed), url.scheme != nil { return url }
        // 兜底：相对路径按静态资源域拼（封面同源逻辑）；媒体 CDN 域名由接口下发，不套用正片域名断言（§4.9）。
        return URL(string: trimmed, relativeTo: KubbConfig.staticBaseURL)
    }
}
