# Kubb TV iOS 测试版

零第三方依赖的 SwiftUI 测试 App：按 `../kubb-tv-technical-report.md`（协议文档）实现关键词搜索、搜索结果列表、点击进入播放页、用系统播放器（`VideoPlayer`/`AVPlayer`）播放。

## 在 Mac 上运行（需要 Xcode）

环境：macOS + Xcode 15 或更新（真机需 iOS 16.0 或更新，工程部署目标已设为 16.0）。本工程在云端 Linux 上生成，未经 Xcode 编译/签名，首次打开请按以下步骤确认。

1. 解压（若拿到的是压缩包）：双击 `kubb-tv-ios-test.zip`，或把整个 `kubb-tv-ios/` 文件夹拷到 Mac。
2. 打开工程：双击 `KubbTV/KubbTV.xcodeproj`（也可以在 Xcode 里 File → Open 选这个文件）。
3. 选个人签名 Team：左侧点最上面的蓝色工程图标 `KubbTV` → TARGETS 里选 `KubbTV` → Signing & Capabilities：
   - Automatically manage signing 已在工程里预先勾好（`CODE_SIGN_STYLE = Automatic`，Target 的 Provisioning Style 也是 Automatic），不用再改；
   - Development Team 在工程里刻意留空：点 Team 下拉选你的个人团队（没有就点 Add an Account… 登录你的 Apple ID，选带 `(Personal Team)` 字样的那项，免费账号即可真机调试，不需要付费开发者账号）；
   - Bundle ID 预设为 `app.kubbtv.test.ios`（已避开容易被占用的 `com.example.*`）；若仍提示被占用，改成只属于你的唯一值，例如 `com.<你的名字拼音>.kubbtv`，改完再 Run 一次即可。
4. 选运行设备与运行：模拟器选任意 iOS 16+ 机型；真机按下一节分步做。按 ⌘R（或点 ▶︎）编译并安装运行。
5. 使用：顶部搜索框输入关键词（例如某部影片名）→ 点结果进入播放页 → 若拿到播放地址会自动播放；选集按钮可切换 mediaKey 重新取地址。

## 真机调试分步（免费 Personal Team 即可）

> 先说清边界：云端 Linux 没有 Xcode、没有你的 Apple ID，**无法直接产出已签名的 `.ipa`**，本交付也没有伪造任何 `.ipa`。这份源工程就是用来在你的 Mac 上用 Xcode 一键编译、签名并安装到真机的调试工程；Xcode 的 Personal Team 签名只能在你本地完成。

1. **开开发者模式（真机，只需做一次）**：先用数据线把 iPhone 连上 Mac 并解锁；然后在 iPhone 上打开 设置 → 隐私与安全性 → 开发者模式 → 打开开关，按提示重启并确认「打开」。找不到这一项时，先让 Xcode 识别一次设备（下一步）它才会出现。
2. **数据线连接与信任**：用可传数据的数据线连接（部分充电线只能充电）；iPhone 上弹出「要信任此电脑吗？」选「信任」并输入锁屏密码；Mac 上 Finder/Xcode 若问信任同样确认。之后在 Xcode 顶部把这台 iPhone 选为运行设备（Window → Devices and Simulators 里应能看到它且无黄色警告）。
3. **选 Personal Team**：按上一节第 3 步在 Signing & Capabilities 里选你自己的 `(Personal Team)`，Bundle ID 保持 `app.kubbtv.test.ios` 或换成你的唯一值。选错成别人的团队、或 Team 一直为空，都会在 Run 时报签名错误，先回到这一步检查。
4. **选真机按 ⌘R**：Xcode 顶部设备菜单选中你的 iPhone（不要选成模拟器或「Any iOS Device」），按 ⌘R。Xcode 会自动申请免费证书、把 App 装进手机并尝试直接打开。
5. **首次「不受信任的开发者」处理**：若手机上点开 App 提示「不受信任的开发者」或 Xcode 提示开发者 App 未受信任：到 iPhone 设置 → 通用 → VPN与设备管理（旧系统叫「描述文件与设备管理」）→ 在「开发者 App」栏点你的 Apple ID → 点「信任」→ 再回桌面打开 App，或回 Xcode 再按一次 ⌘R。
6. **验证联网与播放**：真机连上 Wi-Fi/蜂窝后搜一个关键词（能出列表说明 `rankv21.kubb.tv` 接口在真机可达）；点一条结果进播放页。若提示「用户签名错误」那是接口签名未接入（见「已知限制」第 1 条），不是真机调试失败；若 App 能装、能开、能搜，真机调试链路本身已打通。

### 真机常见报错速查

| 现象/报错 | 原因 | 解决 |
|---|---|---|
| Failed to register bundle identifier / Bundle ID 已被占用 | 预设 ID 恰好与已有 App 冲突 | Signing 页把 Bundle ID 改成你的唯一值（如 `com.<你的名字>.kubbtv`）再 Run |
| No Development Team selected / Signing requires a development team | Team 还留空 | Signing 页 Team 下拉选 `(Personal Team)`；没有该项先在 Xcode → Settings → Accounts 登录 Apple ID |
| 未受信任的开发者 / Developer App 未验证 | 首次安装的个人证书未在手机上信任 | 设置 → 通用 → VPN与设备管理 → 信任你的 Apple ID（见上第 5 步） |
| App 装上几天后打不开、提示验证失败 | **免费 Personal Team 签名只有约 7 天有效期**（付费账号更长） | 数据线连回这台 Mac，Xcode 里再按一次 ⌘R 重新签名安装即可，数据一般保留；这是免费签名的固有限制，不是工程问题 |
| 找不到「开发者模式」开关 | 设备还没被 Xcode 识别过 | 先连线、信任电脑、在 Xcode 设备列表确认到设备，再回设置里找；仍没有则重启手机 |
| 设备显示 unavailable / OS version 不被支持 | 手机 iOS 高于当前 Xcode 支持，或低于部署目标 16.0 | 升级 Xcode（对应新 iOS），或换 iOS 16+ 的设备；不要为此改工程的部署目标以下的系统 |
| 编译过了但装不上、提示设备被锁定等 | 手机锁屏/未信任/线缆只充电 | 解锁手机、点「信任此电脑」、换原装或可传数据的数据线、保持手机亮屏再 Run |
| App 能开但搜不到/播放页报「用户签名错误」 | 接口 `vv/pub` 签名未接入（与真机无关） | 见「已知限制」第 1 条接入 `RequestSigning`；这不是签名证书问题，不要去改 Signing 页 |

本轮真机就绪核查结论（工程侧已改好）：自动签名开启且 Provisioning Style=Automatic、Development Team 显式留空、无任何 Capability/entitlement 文件（不需要付费账号）、Debug 为可调试配置（`-Onone` + dwarf + `ONLY_ACTIVE_ARCH=YES`，Scheme 的 Run 走 Debug）、部署目标降为 iOS 16.0、架构未做任何只限模拟器的排除（仅显式声明 `iphoneos iphonesimulator`、Release 关闭 ONLY_ACTIVE_ARCH）、Info.plist 已补 ATS（见下）与 Scene 清单。

## 没有 Mac（Windows）：GitHub Actions 打包 + 侧载到 iPhone

> 适用：只有 Windows、没有 Mac。思路是让 GitHub 的 macOS 机器替你编译，拿到未签名 `.ipa` 后，在 Windows 上用你自己的 Apple ID 侧载到 iPhone。这不需要付费开发者账号，但免费签名约 7 天到期，要按最后一节定期刷新。
>
> **安全警告（务必先看）**：侧载时 Apple ID 密码、短信/验证器验证码**只输在苹果官方登录框和侧载工具（SideStore/AltStore）本地界面里，不要发给任何人**（包括不要发到聊天、邮件、网盘表单或让「代装」的人替你输）。不要用他人的 Apple ID，不要买所谓共享证书/企业证书装包：账号可能被锁、证书随时被苹果吊销。为侧载单独建一个备用 Apple ID 更稳妥，且同样只在官方/工具本地登录。

### 第 1 步：在 GitHub 建私有仓库并上传工程

1. 登录 [github.com](https://github.com)，右上角 `+` → New repository：仓库名随意（如 `kubb-tv-ios`），可见性选 **Private（私有）**（工程含接口细节，不要公开），点 Create repository，先别勾任何初始化选项。
2. 把本工程上传成这个仓库的根目录。**关键：仓库根目录必须直接包含 `.github/`、`KubbTV/`、`README.md` 三样**，也就是上传的是 `kubb-tv-ios/` 文件夹**里面的内容**，而不是把 `kubb-tv-ios` 文件夹本身再套一层。仓库根多套一层的话，Actions 找不到工作流、路径也会错。
3. Windows 上推荐用 GitHub Desktop（免费）上传：解压 `kubb-tv-ios-test.zip` → GitHub Desktop 里 File → Add local repository（或先新建文件夹把内容拷进去再添加）→ 写一句提交说明 → Commit → Publish repository，并确认发布窗口里**不要**勾 Keep this code private 以外的公开选项（保持 Private）。没有 GitHub Desktop 时用网页也行：仓库页点 uploading an existing file 后把文件拖进去，但网页端对文件夹/隐藏目录（`.github`）支持差，容易漏掉工作流，优先 GitHub Desktop 或 git 命令行。
4. 上传后在仓库网页确认根目录能看到 `.github` 文件夹（GitHub 网页默认可能不展开它，在文件列表里点进去应能到 `.github/workflows/build-unsigned-ipa.yml`）。看不到就是根目录套错了一层或漏传，回到第 2 步改。

### 第 2 步：在 Actions 里手动跑打包，下载 .ipa

1. 打开仓库的 **Actions** 页（首次进会提示启用 Actions，点启用）。左侧选工作流 **Build unsigned IPA (no Mac)**。
2. 点右侧 **Run workflow** → 分支保持默认 → 再点绿色的 Run workflow。这就是手动触发；每次改代码后重跑一次即可出新包。
3. 等这次运行变成绿勾（约几分钟）。若变红叉：点进去看失败步骤的日志，把**失败步骤的完整日志文本**复制发回来排查（日志里不要粘贴任何账号密码；正常构建日志也不会有）。云端这边没有你的仓库权限，**无法替你在 GitHub 上实际触发验证**，首次跑只能靠你这次结果确认。
4. 成功后在该次运行页面底部 Artifacts 区下载 **KubbTV-unsigned-ipa**，解压得到 `KubbTV-unsigned.ipa`。注意 artifact 默认只保留 7 天，过期重新 Run 一次即可；这个 `.ipa` 是**未签名**的，不能直接点开装，必须走下一步侧载重签。

### 第 3 步：在 Windows 上侧载到 iPhone（SideStore 为主，AltStore 备选）

先在 iPhone 上做好两件准备（两个工具通用）：设置 → 隐私与安全性 → **开发者模式**打开（按提示重启确认）；装好后若提示不受信任，到 设置 → 通用 → VPN与设备管理 里**信任**你的 Apple ID。

**首选 SideStore（装好后刷新不依赖电脑常开）：**

- 前提：一台 Windows 电脑、一条能传数据的数据线、你自己的 Apple ID；iPhone 与电脑先用线连一次完成初装和配对。前置软件与配对文件生成方式以 SideStore 官网（sidestore.io）的 Windows 指引为准（通常经其推荐的桌面端工具完成初次安装与 pairing file 生成），不要从不明网盘下载改版工具。
- 步骤梗概：按官网 Windows 指引把 SideStore 装进 iPhone 并导入配对文件 → 在 iPhone 打开 SideStore，用**你自己的** Apple ID 在工具本地登录 → 把第 2 步的 `KubbTV-unsigned.ipa` 传到 iPhone（数据线/AirDrop 替代方式/文件 App 均可）→ 在 SideStore 里点 `+` 选这个 `.ipa` 安装 → 回桌面先做上面的「信任」，再打开 Kubb TV。
- 刷新：SideStore 可在 iPhone 上自行刷新签名（按其指引保持它要求的本地 VPN/刷新开关开启即可，刷新时手机需联网），不用每次都连电脑，但务必在到期前刷新（见下节）。

**备选 AltStore（SideStore 装不上时用）：**

- 前提：Windows 电脑常备、iPhone 与电脑处于**同一 Wi-Fi**、数据线（初装时）、你自己的 Apple ID；电脑需安装苹果官方版 iTunes 与 iCloud（从苹果官网装，不要用微软商店版，老版本 AltServer 与商店版不兼容），并在电脑上安装运行 AltServer。
- 步骤梗概：在电脑 AltServer 里选 Install AltStore → 选你的 iPhone，在官方登录框输自己的 Apple ID 完成装入 → iPhone 上完成「信任」→ 打开 AltStore 登录同一 Apple ID → 把 `.ipa` 传入手机，在 AltStore 的 My Apps 里点 `+` 选它安装。
- 刷新：AltStore 刷新时电脑必须开着、AltServer 在运行且与 iPhone 同一 Wi-Fi；比 SideStore 更依赖电脑，别等过期了才想起来开电脑。

### 第 4 步：免费签名约 7 天到期如何刷新

- 免费 Personal Team/侧载签名的有效期约 **7 天**：到期后 App 会闪退或提示无法验证，这是免费签名的固有限制，不是 App 坏了，也不需要重新去 GitHub 打包（`.ipa` 文件没过期，过期的是签名）。
- **到期前**任选：SideStore 在 App 内点 Refresh All（保持其刷新条件开启、手机联网）；AltStore 则打开电脑 AltServer、同 Wi-Fi 后在 AltStore 里 Refresh。刷新成功后有效期重新计 7 天，App 数据一般保留。
- 已经过期才想起来：重新用对应工具对同一个 `.ipa` 再装/刷新一次即可恢复，一般不需要删 App（先别卸载，卸载会清数据；直接覆盖刷新/重装优先）。
- 免费账号另有上限（同时侧载 App 数量、App ID 数量等苹果侧限制），装太多其他侧载 App 时可能互相挤占，报错时先删掉不用的侧载 App 再试。

## 依据协议文档用到的接口

| 用途 | 接口 | 参数要点 | 证据级别 |
|---|---|---|---|
| 关键词搜索 | `POST https://rankv21.kubb.tv/v3/list/briefsearch` | 查询串 `cinema=1, orderby=4, page, size=10, desc=1, v=1`；body 表单 `tags=<关键词>` | 【实测】回包 `info[0].{recordcount,maxpage,result[],hasResult}` 已用无签名 curl 复现（中文关键词命中 1 条） |
| 详情 | `GET https://m10.kubb.tv/v3/video/detail` | `cinema=1, device=1, player=CkPlayer, tech=HLS, country=HU, lang=cns, id=<作品key>, region=US, v=1` | 【代码】字段清单；实测无签名返回 `code:1 用户签名错误`，成功回包未取得 |
| 选集/语言 | `GET https://m10.kubb.tv/v3/video/languagesplaylist` | `cinema=1, vid=<作品key>, lsk=1, v=1`（`taxis` 默认值未确认故省略、`cid` 空省略） | 【代码】；实测无签名 `code:1`，文档实测曾得 `code:0,info:[]` 空 |
| 播放源 | `GET https://m10.kubb.tv/v3/video/play` | `cinema=1, id=<mediaKey>, usersign=1, device=1, a=1, region=US, isMasterSupport=0(iOS), v=1` | 【代码】；实测无签名 `code:1`，成功回包原文未取得 |

通用约定：响应包络 `{"ret":200,"data":{"code":0,"msg":"","info":...}}`，只消费 `data.info`；`code=1` 显示服务端 `msg`；HTTP 503 纯文本按「服务不可用」处理。封面 `image/imgPath` 为完整 URL 或 `static.kubb.tv` 相对路径。条目优先用搜索内嵌的 `languagesPlayList.playList[].key` 作为 mediaKey，其次 `lastKey`。

播放地址提取（集中在 `KubbTV/PlaySource.swift`，真机第一份成功回包后重点核对这里）：`video/play` 的 `flvPathList[]` 中不带 `link` 的条目为正片（带 `link` 是广告，本测试版不播广告），`result` 经 `uriSignature` 后为播放地址；`isHls`/`.m3u8` 为 HLS，否则 MP4，均由 AVPlayer 原生播放；`clarity[]`（`path` 字段）作兜底；`needLogin/isLimitedStream` 时不播正片；`startSecond>0` 时自动 seek。

## 已知限制（文档脱敏/未确认，未臆造）

1. **签名未接入（最关键）**：协议文档 §5.1 的 `vv/pub` MD5 签名只给形态，密钥与拼接细节已脱敏，本工程不提供签名复现。因此默认无签名运行：搜索大概率可用（已实测），但 `video/detail`、`video/play`、`video/languagesplaylist` 实测返回「用户签名错误」，**播放页现在多半拿不到真实播放地址**。要打通：实现 `RequestSigning`（见 `KubbTV/KubbConfig.swift` 顶部说明），把 `KubbConfig.signer` 换成你的实现即可，业务代码不用改。占位类 `StaticVVPubSigner` 只负责把现成的 `vv/pub` 拼上，不计算 MD5。不要把公开页面里的密钥硬编码进仓库。
2. **mediaKey 之后的地址可能还要 `uriSignature`**：`result` 的签名改写规则（`PlaySource` 里 `MediaURLProcessor`）同样未确认，默认原样使用 `result`。若条目标记 `needSign`，播放页会给出提示；真机确认规则后只改这一个函数。
3. **播放 CDN 请求头未知**：文档未确认 CDN 需要 Referer/UA/Cookie 等请求头，默认不带（`KubbConfig.mediaHTTPHeaders` 为空）。若真机出现能拿到地址但 AVPlayer 加载失败，先抓包确认是否缺请求头，只改这个字典。
4. **`video/play`、`video/detail` 成功回包字段未经实测**：字段名来自前端代码证据（文档 §6 未确认项 1–3），字幕 `tracks`、清晰度菜单细节、广告字段均未实现（本测试版有意不播前贴/中插/暂停广告，也不做弹幕、登录、进度上报）。若真机回包字段与 `PlaySource.swift` 假设不同，按回包改那一个文件。
5. 地区固定 `region=US`（文档实测地区）、`country=HU/lang=cns` 为详情注册默认值，均集中在 `KubbConfig`，可改。
6. 工程未经 Xcode 编译：源码与工程文件已在 Linux 做静态校验（结构/plist/JSON/字段与文档逐项核对，真机相关设置逐项清单见「真机调试分步」末尾结论），但 Swift 编译、Personal Team 签名、真机安装与播放必须在你的 Mac 上首次运行确认。若 Xcode 报某个 Swift 语法/类型错误，多半是版本差异，按报错行就近修即可。
7. ATS（真机联网/播放）：协议文档的接口与静态资源均为 HTTPS，本身不需要 ATS 例外；但播放地址由接口下发、其 CDN 域名与 http/https 在文档中未确认（`hss100.pipecdn.vip` 只确认到 HLS 地址形态）。`Info.plist` 已做**收窄的**放行：总开关 `NSAllowsArbitraryLoads=false` 保持关闭，只开 `NSAllowsArbitraryLoadsInMedia=true`（仅 AVFoundation 播媒体时放行，含接口临时下发的未知 CDN），并只对 `kubb.tv` 与 `pipecdn.vip` 两个域（含子域）放行第三方 HTTP 加载（防封面/接口回包出现 http 链接被拦截）。普通 `URLSession` 请求对其它域名仍受 ATS 保护；这属于测试版为未知媒体 CDN 留的口子，上架前应按真机抓到的确切 CDN 域名收紧为逐域白名单。

## 工程结构

```
KubbTV/
  KubbTV.xcodeproj          Xcode 工程（无第三方包依赖）
  KubbTV/
    KubbTVApp.swift         入口
    KubbConfig.swift        接口地址/默认参数/签名与播放地址可替换层（先看这个）
    KubbAPIClient.swift     统一请求管线 + 搜索/详情/选集/播放四个接口
    Models.swift            包络与条目/分集/详情模型（容忍字段类型不稳定）
    PlaySource.swift        video/play 回包 → 正片地址提取（未确认字段集中点）
    SearchView.swift        搜索页（加载中/无结果/失败/结果列表与分页）
    PlayerView.swift        播放页（VideoPlayer/AVPlayer + 选集）
```
