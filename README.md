# SafariAdapter

给 Safari 加上一条接近 Arc 的原生命令栏：按 `⌘L` 在页面中央查看或输入地址、搜索已打开的标签页和本地历史，按 `⌘S` 切换 Safari 侧边栏。

## 下载

不懂代码也没关系，直接打开 [最新版下载页](https://github.com/LAWTED/SafariAdapter/releases/latest)，下载 `SafariAdapter-0.3.0.dmg`。

## 三步安装

1. 打开下载的 DMG，把 `SafariAdapter` 拖进 `Applications`。
2. 在“应用程序”里双击 `SafariAdapter`。
3. 按系统提示允许“辅助功能”和“自动化 → Safari”。然后打开 Safari，按 `⌘L`。

更细的图文式说明见 [INSTALL.md](INSTALL.md)。SafariAdapter 是纯后台辅助程序，不显示普通窗口、不出现在 Dock，也不会占用菜单栏；切到 Safari 后按 `⌘L` 就能确认它正在运行。

## 快捷键

| 快捷键 | 作用 |
| --- | --- |
| `⌘L` | 打开/关闭中央地址栏，并显示当前网址 |
| `⌘S` | 打开/关闭 Safari 原生侧边栏 |
| `Return` | 在当前标签页打开输入的网址或搜索内容 |
| `⌘Return` | 新建标签页、切换过去并打开输入内容 |
| `Escape` | 关闭地址栏 |
| `⌘1`…`⌘9` | 切换 Safari 标签页 |
| `⌘⇧C` | 复制当前网址 |
| `⌘⌥⇧C` | 复制当前页面的 Markdown 链接 |

只有 Safari 位于最前面时，这些快捷键才会被 SafariAdapter 接管。

`⌘S` 只在 Safari 位于最前面时由 SafariAdapter 接管，用来切换 Safari 原生侧边栏；不会打开“存储页面”对话框。

## 输入规则

- 输入至少两个字符后，会依次匹配当前 Safari 窗口中已经打开的标签页和 SafariAdapter 的本地历史；使用上下键选择，按 `Return` 打开。
- 已打开的标签页永远排在历史记录前面，同一个网址不会重复出现。
- 完整网址会直接打开。
- 类似 `github.com` 的域名会自动补上 `https://`。
- 普通文字会使用 Google 搜索。

## 搜索别名

| 输入 | 搜索位置 |
| --- | --- |
| `g liquid glass` | Google |
| `gh safari adapter` | GitHub |
| `yt swift tutorial` | YouTube |
| `x openai` | X |
| `maps coffee` | Google Maps |

识别到别名时，输入框右侧会显示目标网站；按 `Return` 在当前标签页搜索，按 `⌘Return` 在新标签页搜索。

## 系统要求

- macOS 15 或更高版本。
- Apple Silicon 和 Intel Mac 均可运行。
- macOS 26 使用原生 Liquid Glass；旧系统自动使用兼容材质。

## 安全与公证

公开安装包使用 `Developer ID Application: Mingze Wu (V8DZ785G5L)` 签名，并通过 Apple Notary Service 公证和 stapling。发布页同时提供 SHA-256 校验文件，源码和构建脚本全部公开。

## 从源码构建

需要安装 Xcode Command Line Tools：

```bash
./build.sh
open dist/SafariAdapter.app
```

生成 DMG、ZIP 和 SHA-256 校验文件：

```bash
./package.sh
```

## 权限用途

- “辅助功能”：定位 Safari 窗口，以及按下 Safari 自己的侧边栏按钮。
- “自动化 → Safari”：读取当前网址、切换标签页和打开网址。

如果没有授予“自动化 → Safari”，命令栏会打不开当前网址；这时 SafariAdapter 会直接提示你，并可以一键跳转到对应的系统设置面板。

SafariAdapter 不上传浏览记录，也不包含网络服务或分析 SDK。

## 本地历史

SafariAdapter 只记录安装本版本后、在 Safari 前台稳定停留过的网页。记录保存在本机的 Application Support 文件夹，不读取 Safari 的私有历史数据库，也不需要“完全磁盘访问”。

SafariAdapter 不显示菜单栏图标。如果需要暂停本地历史，在“终端”运行 `defaults write com.ha7ch.SafariAdapter localHistoryEnabled -bool false`，再重新打开 SafariAdapter；把最后的 `false` 改成 `true` 可以恢复记录。清理记录时，在 Finder 中选择“前往 → 前往文件夹”，打开 `~/Library/Application Support/SafariAdapter/`，把 `history.json` 移到废纸篓。这些操作都不会影响 Safari 自己的历史记录。

## License

MIT
