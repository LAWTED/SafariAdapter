# SafariAdapter 安装说明

## 1. 安装

1. 双击 `SafariAdapter-0.2.8.dmg`。
2. 把左边的 `SafariAdapter` 拖到右边的 `Applications` 文件夹。
3. 打开 Finder → 应用程序，双击 `SafariAdapter`。

安装包已经使用 Apple Developer ID 签名并通过 Apple 公证。macOS 可能会显示普通的“从互联网下载”确认，选择“打开”即可。

## 2. 给权限

第一次按快捷键时，macOS 可能会分别询问两项权限：

- 辅助功能：打开“系统设置 → 隐私与安全性 → 辅助功能”，开启 SafariAdapter。
- 自动化：打开“系统设置 → 隐私与安全性 → 自动化”，展开 SafariAdapter，开启 Safari。

权限改完后，从菜单栏退出 SafariAdapter，再从“应用程序”重新打开一次。

## 3. 开始用

1. 打开 Safari。
2. 按 `⌘L`，中央会出现当前网址。
3. 输入网址或搜索内容，按 `Return` 在当前标签页打开。
4. 按 `⌘Return` 会新建标签页、切换过去并打开。
5. 输入至少两个字符可以搜索已打开的标签页和 SafariAdapter 本机记录的历史页面；已打开标签页会优先显示。
6. 按 `⌘⇧C` 复制当前网址，按 `⌘⌥⇧C` 复制 Markdown 链接。
7. 需要切换侧边栏时，点击菜单栏图标选择 `Toggle Safari Sidebar`。

还可以输入 `g`、`gh`、`yt`、`x` 或 `maps` 加空格和关键词，快速选择对应搜索网站。

点击菜单栏图标，可以随时暂停或清空 SafariAdapter 的本地历史；不会影响 Safari 自己的历史记录。

## 看不到窗口？

这是正常的。SafariAdapter 只显示在 macOS 菜单栏，不显示主窗口，也不占 Dock。点击菜单栏图标可以测试命令栏、切换材质或退出。

## 快捷键没反应？

依次检查：

1. Safari 是否在最前面。
2. 菜单栏是否有 SafariAdapter 图标。
3. “辅助功能”和“自动化 → Safari”是否都已开启。
4. 退出并重新打开 SafariAdapter。
5. 仍无反应时，删除系统设置中的旧 SafariAdapter 权限项，再重新添加 `/Applications/SafariAdapter.app`。
