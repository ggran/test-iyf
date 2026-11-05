import SwiftUI

@MainActor
final class SearchViewModel: ObservableObject {
    enum State: Equatable {
        case idle
        case loading
        case empty(keyword: String)
        case failed(String)
        case loaded
    }

    @Published var keyword: String = ""
    @Published private(set) var state: State = .idle
    @Published private(set) var items: [VideoItem] = []
    @Published private(set) var recordCount: Int = 0
    @Published private(set) var isLoadingMore: Bool = false

    private var page: Int = 1
    private var maxPage: Int = 1
    private var currentKeyword: String = ""
    private let api: KubbAPIClient

    init(api: KubbAPIClient = .shared) { self.api = api }

    func search() async {
        let kw = keyword.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !kw.isEmpty else { state = .idle; items = []; return }
        currentKeyword = kw
        page = 1
        state = .loading
        do {
            let result = try await api.search(keyword: kw, page: 1)
            items = result.items
            recordCount = result.recordCount
            maxPage = result.maxPage
            state = result.items.isEmpty ? .empty(keyword: kw) : .loaded
        } catch {
            items = []
            state = .failed(Self.message(for: error))
        }
    }

    func loadMoreIfNeeded(current item: VideoItem) async {
        guard state == .loaded, !isLoadingMore, page < maxPage, item.id == items.last?.id else { return }
        isLoadingMore = true
        defer { isLoadingMore = false }
        do {
            let next = page + 1
            let result = try await api.search(keyword: currentKeyword, page: next)
            page = next
            maxPage = result.maxPage
            items.append(contentsOf: result.items)
        } catch {
            // 分页失败不清空已加载结果；用户可继续浏览或重新搜索。
        }
    }

    static func message(for error: Error) -> String {
        (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
    }
}

/// 通用空/错误占位（自绘以兼容 iOS 16，不依赖仅 iOS 17 才有的系统占位视图）。
struct PlaceholderView<Actions: View>: View {
    let systemImage: String
    let title: String
    let message: String
    @ViewBuilder var actions: () -> Actions

    init(systemImage: String, title: String, message: String, @ViewBuilder actions: @escaping () -> Actions) {
        self.systemImage = systemImage
        self.title = title
        self.message = message
        self.actions = actions
    }

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: systemImage).font(.largeTitle).foregroundStyle(.secondary)
            Text(title).font(.headline)
            Text(message).font(.subheadline).foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            actions()
        }
        .padding()
    }
}

extension PlaceholderView where Actions == EmptyView {
    init(systemImage: String, title: String, message: String) {
        self.init(systemImage: systemImage, title: title, message: message) { EmptyView() }
    }
}

struct SearchView: View {
    @StateObject private var model = SearchViewModel()

    var body: some View {
        NavigationStack {
            Group {
                switch model.state {
                case .idle:
                    PlaceholderView(systemImage: "magnifyingglass", title: "搜索影视",
                                    message: "输入关键词后调用协议文档的 briefsearch 接口搜索。")
                case .loading:
                    ProgressView("搜索中…")
                case .empty(let kw):
                    PlaceholderView(systemImage: "tray", title: "无结果",
                                    message: "「\(kw)」没有命中（recordcount=0）。换个关键词试试。")
                case .failed(let message):
                    PlaceholderView(systemImage: "exclamationmark.triangle", title: "搜索失败", message: message) {
                        Button("重试") { Task { await model.search() } }
                    }
                case .loaded:
                    resultList
                }
            }
            .navigationTitle("Kubb TV 测试版")
            .searchable(text: $model.keyword, prompt: "输入关键词")
            .onSubmit(of: .search) { Task { await model.search() } }
        }
    }

    private var resultList: some View {
        List {
            Section {
                ForEach(model.items) { item in
                    NavigationLink {
                        PlayerView(item: item)
                    } label: {
                        VideoRow(item: item)
                    }
                    .task { await model.loadMoreIfNeeded(current: item) }
                }
            } header: {
                Text("共 \(model.recordCount) 条")
            }
            if model.isLoadingMore {
                HStack { Spacer(); ProgressView(); Spacer() }
            }
        }
        .listStyle(.plain)
    }
}

struct VideoRow: View {
    let item: VideoItem

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            AsyncImage(url: item.coverURL) { phase in
                switch phase {
                case .success(let image): image.resizable().scaledToFill()
                case .failure: Image(systemName: "photo").frame(maxWidth: .infinity, maxHeight: .infinity)
                default: ProgressView()
                }
            }
            .frame(width: 64, height: 90)
            .clipped()
            .cornerRadius(6)

            VStack(alignment: .leading, spacing: 4) {
                Text(item.title).font(.headline).lineLimit(2)
                if let meta = metaLine { Text(meta).font(.subheadline).foregroundStyle(.secondary).lineLimit(1) }
                if let starring = item.starring, !starring.isEmpty {
                    Text("主演：\(starring)").font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
                if item.isSerial {
                    Text("连载\(item.serialCount.map { " · 共 \($0) 集" } ?? "")\(item.lastName.map { " · 最新 \($0)" } ?? "")")
                        .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
                if let vip = item.vipResource, !vip.isEmpty {
                    Text(vip).font(.caption2).padding(.horizontal, 6).padding(.vertical, 2)
                        .background(Color.orange.opacity(0.2)).cornerRadius(4)
                }
            }
        }
        .padding(.vertical, 4)
    }

    private var metaLine: String? {
        let parts = [item.typeName, item.year, item.regional, item.lang,
                     item.ratingText.map { "评分 \($0)" }].compactMap { $0 }.filter { !$0.isEmpty }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
}
