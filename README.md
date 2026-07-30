# SafariAdapter

给 Safari 加上一条接近 Arc 的原生命令栏：按 `⌘L` 在页面中央查看或输入地址，按 `⌘S` 切换 Safari 侧边栏。

## 下载

不懂代码也没关系，直接打开 [最新版下载页](https://github.com/LAWTED/SafariAdapter/releases/latest)，下载 `SafariAdapter-0.2.8.dmg`。

## 三步安装

1. 打开下载的 DMG，把 `SafariAdapter` 拖进 `Applications`。
2. 在“应用程序”里双击 `SafariAdapter`。
3. 按系统提示允许“辅助功能”和“自动化 → Safari”。然后打开 Safari，按 `⌘L`。

更细的图文式说明见 [INSTALL.md](INSTALL.md)。SafariAdapter 是菜单栏应用，不会显示普通窗口，也不会出现在 Dock；看到菜单栏里的图标就代表它正在运行。

## 快捷键

| 快捷键 | 作用 |
| --- | --- |
| `⌘L` | 打开/关闭中央地址栏，并显示当前网址 |
| `Return` | 在当前标签页打开输入的网址或搜索内容 |
| `⌘Return` | 新建标签页、切换过去并打开输入内容 |
| `Escape` | 关闭地址栏 |
| `⌘S` | 切换 Safari 原生侧边栏 |
| `⌘1`…`⌘9` | 切换 Safari 标签页 |

只有 Safari 位于最前面时，这些快捷键才会被 SafariAdapter 接管。

## 输入规则

- 完整网址会直接打开。
- 类似 `github.com` 的域名会自动补上 `https://`。
- 普通文字会使用 Google 搜索。

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

SafariAdapter 不上传浏览记录，也不包含网络服务或分析 SDK。

## License

MIT
