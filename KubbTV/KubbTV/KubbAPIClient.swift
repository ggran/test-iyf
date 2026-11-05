import Foundation

enum KubbAPIError: LocalizedError {
    case invalidURL
    case httpStatus(Int, String)     // 如 HTTP 503 + 纯文本「服务不可用。」（§2.8）
    case business(code: Int, msg: String) // 包络 data.code != 0，如 code:1「用户签名错误」（§2.1）
    case emptyInfo                    // code:0 但 info 为空（languagesplaylist 实测可为空）
    case decoding(String)

    var errorDescription: String? {
        switch self {
        case .invalidURL: return "接口地址拼装失败"
        case .httpStatus(let status, let body): return "HTTP \(status)：\(body.isEmpty ? "服务不可用" : body)"
        case .business(let code, let msg): return msg.isEmpty ? "业务错误 code=\(code)" : msg
        case .emptyInfo: return "接口返回为空（info 为空）"
        case .decoding(let detail): return "响应解析失败：\(detail)"
        }
    }
}

struct SearchPage {
    let recordCount: Int
    let maxPage: Int
    let hasResult: Bool
    let items: [VideoItem]
}

/// 统一请求管线（协议文档 §1.5）：有序参数拼串 → 签名层 → GET/POST 表单 → 包络解包取 data.info。
/// 本工程零第三方依赖，只用 URLSession。未登录：不平铺 token 字段、不带账号 Cookie 语义。
final class KubbAPIClient {
    static let shared = KubbAPIClient()
    private let session: URLSession
    private let signer: RequestSigning

    init(session: URLSession? = nil, signer: RequestSigning = KubbConfig.signer) {
        if let session { self.session = session }
        else {
            let config = URLSessionConfiguration.default
            config.httpShouldSetCookies = true // 对应 withCredentials 的 Cookie 携带形态
            config.timeoutIntervalForRequest = 30
            self.session = URLSession(configuration: config)
        }
        self.signer = signer
    }

    // MARK: - 关键词搜索（§2.3 / §3.2）
    /// POST https://rankv21.kubb.tv/v3/list/briefsearch（别名 solr-search）
    /// 查询串：cinema=1, orderby=4(Relativity), page, size, desc=1, v=1
    /// body：表单 tags=<关键词> 一项，再经签名层。
    /// 回包：info[0] = {recordcount, maxpage, result[], firstCID, tagResult, isStar, hasResult}
    func search(keyword: String, page: Int = 1) async throws -> SearchPage {
        let query: [(String, String)] = [
            ("cinema", KubbConfig.cinema),
            ("orderby", "4"),
            ("page", String(page)),
            ("size", String(KubbConfig.searchPageSize)),
            ("desc", "1"),
            ("v", KubbConfig.apiVersion),
        ]
        let body: [(String, String)] = [("tags", keyword)]
        let info = try await request(base: KubbConfig.searchBaseURL, path: "/v3/list/briefsearch",
                                     method: "POST", queryItems: query, bodyItems: body)
        guard let first = info.arrayValue.first else { throw KubbAPIError.emptyInfo }
        let o = first.objectValue
        let items = o["result"]?.arrayValue.compactMap(VideoItemParser.parse) ?? []
        return SearchPage(
            recordCount: Int(o["recordcount"]?.stringValue ?? "") ?? items.count,
            maxPage: Int(o["maxpage"]?.stringValue ?? "") ?? page,
            hasResult: o["hasResult"]?.boolValue ?? !items.isEmpty,
            items: items
        )
    }

    // MARK: - 详情（§2.5 / §3.6）
    /// GET https://m10.kubb.tv/v3/video/detail（别名 video-detail）
    /// 注册默认：ispath:false(省略), cinema=1, device:"desktop", player:"CkPlayer", tech:"HLS",
    /// country:"HU", lang:"cns", v:1；调用覆盖：id=<作品key>, device=1, region=<本地地区>
    func detail(workKey: String) async throws -> VideoDetail {
        let query: [(String, String)] = [
            ("cinema", KubbConfig.cinema),
            ("device", "1"),
            ("player", "CkPlayer"),
            ("tech", "HLS"),
            ("country", KubbConfig.country),
            ("lang", KubbConfig.language),
            ("id", workKey),
            ("region", KubbConfig.region),
            ("v", KubbConfig.apiVersion),
        ]
        let info = try await request(base: KubbConfig.mainBaseURL, path: "/v3/video/detail",
                                     method: "GET", queryItems: query, bodyItems: [])
        guard let first = info.arrayValue.first, !first.objectValue.isEmpty else { throw KubbAPIError.emptyInfo }
        let o = first.objectValue
        return VideoDetail(
            title: o["title"]?.stringValue,
            coverURL: VideoItemParser.coverURL(from: o),
            summary: o["contxt"]?.stringValue,
            stars: o["stars"]?.stringValue,
            directors: o["directors"]?.stringValue,
            scoreText: o["score"]?.stringValue,
            year: o["post_Year"]?.stringValue,
            regional: o["regional"]?.stringValue,
            language: o["language"]?.stringValue,
            isSerial: o["isSerial"]?.boolValue ?? false,
            serialCount: o["serialCount"]?.stringValue,
            lastName: o["lastName"]?.stringValue
        )
    }

    // MARK: - 选集/语言列表（§2.5 / §3.6）
    /// GET https://m10.kubb.tv/v3/video/languagesplaylist（别名 languagesplaylist）
    /// 参数：cinema=1, vid=<作品key>, lsk=1, taxis=<排序，文档未给默认值时省略>, cid=<空则省略>
    /// 期望：info[0] = {pageSize, playListType, playList:[{id,key,title,created,bought,isVIP,isNew,isLive,isFix}]}
    /// 实测无签名返回 code:1；签名正确时也曾返回 code:0,info:[]（空），两种情况都在 UI 如实呈现。
    func languagesPlaylist(workKey: String, cid: String? = nil) async throws -> [Episode] {
        var query: [(String, String)] = [
            ("cinema", KubbConfig.cinema),
            ("vid", workKey),
            ("lsk", "1"),
        ]
        if let taxis = KubbConfig.playlistTaxis { query.append(("taxis", taxis)) }
        if let cid, !cid.isEmpty { query.append(("cid", cid)) }
        query.append(("v", KubbConfig.apiVersion))
        let info = try await request(base: KubbConfig.mainBaseURL, path: "/v3/video/languagesplaylist",
                                     method: "GET", queryItems: query, bodyItems: [])
        guard let first = info.arrayValue.first else { throw KubbAPIError.emptyInfo }
        return first["playList"]?.arrayValue.compactMap(EpisodeParser.parse) ?? []
    }

    // MARK: - 播放源（§2.5 / §3.7）
    /// GET https://m10.kubb.tv/v3/video/play（别名 video-media）
    /// 注册默认 cinema=1,id:"",a:1；调用：id=<mediaKey>, usersign=1, device=1, a=1,
    /// region, isMasterSupport（桌面 Chrome=1，iOS/Mac Safari=0，本 App 取 0），v=1；
    /// lang/sharpness/line 仅本地有配置时才带（KubbConfig 当前未设，故不出现）。
    func playSource(mediaKey: String) async throws -> PlaySource {
        let query: [(String, String)] = [
            ("cinema", KubbConfig.cinema),
            ("id", mediaKey),
            ("usersign", "1"),
            ("device", "1"),
            ("a", "1"),
            ("region", KubbConfig.region),
            ("isMasterSupport", "0"),
            ("v", KubbConfig.apiVersion),
        ]
        let info = try await request(base: KubbConfig.mainBaseURL, path: "/v3/video/play",
                                     method: "GET", queryItems: query, bodyItems: [])
        guard let first = info.arrayValue.first, !first.objectValue.isEmpty else { throw KubbAPIError.emptyInfo }
        return PlaySourceParser.parse(first)
    }

    // MARK: - 管线
    private func request(base: URL, path: String, method: String,
                         queryItems: [(String, String)], bodyItems: [(String, String)]) async throws -> JSONValue {
        let signed = signer.signed(queryItems: queryItems, bodyItems: bodyItems, isPOST: method == "POST")
        guard var components = URLComponents(url: base.appendingPathComponent(String(path.dropFirst())), resolvingAgainstBaseURL: false) else {
            throw KubbAPIError.invalidURL
        }
        components.percentEncodedQuery = Self.formEncode(signed.query)
        guard let url = components.url else { throw KubbAPIError.invalidURL }

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        // curl 样本与浏览器均带 UA；这里用 App 标识，不冒充浏览器签名材料。
        request.setValue("KubbTVTest/1.0 (iOS)", forHTTPHeaderField: "User-Agent")
        if method == "POST" {
            request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
            request.httpBody = Data(Self.formEncode(signed.body).utf8)
        }

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw KubbAPIError.decoding("无 HTTP 响应") }
        guard http.statusCode == 200 else {
            // §2.8：HTTP 503 + 18 字节纯文本「服务不可用。」
            throw KubbAPIError.httpStatus(http.statusCode, String(data: data, encoding: .utf8) ?? "")
        }
        let envelope: Envelope
        do { envelope = try JSONDecoder().decode(Envelope.self, from: data) }
        catch { throw KubbAPIError.decoding(error.localizedDescription) }
        guard let payload = envelope.data else { throw KubbAPIError.decoding("缺少 data 包络") }
        guard payload.code == 0 else {
            throw KubbAPIError.business(code: payload.code, msg: payload.msg ?? envelope.msg ?? "")
        }
        guard let info = payload.info else { throw KubbAPIError.emptyInfo }
        return info
    }

    /// 表单/查询串编码：key=value 直接拼接（§1.5）。值做百分号编码，空格用 %20（对应搜索页 + → %20 处理）。
    static func formEncode(_ items: [(String, String)]) -> String {
        items.map { "\(escape($0.0))=\(escape($0.1))" }.joined(separator: "&")
    }
    private static func escape(_ value: String) -> String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        return value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
    }
}
