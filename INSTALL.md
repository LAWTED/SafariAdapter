# SafariAdapter 安装说明

## 1. 安装

1. 双击 `SafariAdapter-0.3.0.dmg`。
2. 把左边的 `SafariAdapter` 拖到右边的 `Applications` 文件夹。
3. 打开 Finder → 应用程序，双击 `SafariAdapter`。

安装包已经使用 Apple Developer ID 签名并通过 Apple 公证。macOS 可能会显示普通的“从互联网下载”确认，选择“打开”即可。

## 2. 给权限

第一次按快捷键时，macOS 可能会分别询问两项权限：

- 辅助功能：打开“系统设置 → 隐私与安全性 → 辅助功能”，开启 SafariAdapter。
- 自动化：打开“系统设置 → 隐私与安全性 → 自动化”，展开 SafariAdapter，开启 Safari。

权限改完后，在“活动监视器”中结束 SafariAdapter，再从“应用程序”重新打开一次。

## 3. 开始用

1. 打开 Safari。
2. 按 `⌘L`，中央会出现当前网址。
3. 按 `⌘S` 打开或关闭 Safari 原生侧边栏。
4. 输入网址或搜索内容，按 `Return` 在当前标签页打开。
5. 按 `⌘Return` 会新建标签页、切换过去并打开。
6. 输入至少两个字符可以搜索已打开的标签页和 SafariAdapter 本机记录的历史页面；已打开标签页会优先显示。
7. 按 `⌘⇧C` 复制当前网址，按 `⌘⌥⇧C` 复制 Markdown 链接。

还可以输入 `g`、`gh`、`yt`、`x` 或 `maps` 加空格和关键词，快速选择对应搜索网站。

SafariAdapter 的本地历史只保存在这台 Mac。暂停和清理方法见 [README 的“本地历史”部分](README.md#本地历史)，不会影响 Safari 自己的历史记录。

## 看不到窗口？

这是正常的。SafariAdapter 是纯后台辅助程序，不显示主窗口、不占 Dock，也不在菜单栏显示图标。打开 Safari 后按 `⌘L` 即可使用。

## 快捷键没反应？

依次检查：

1. Safari 是否在最前面。
2. 在“活动监视器”中能否找到 SafariAdapter。
3. “辅助功能”和“自动化 → Safari”是否都已开启。
4. 在“活动监视器”中结束 SafariAdapter，再从“应用程序”重新打开。
5. 仍无反应时，删除系统设置中的旧 SafariAdapter 权限项，再重新添加 `/Applications/SafariAdapter.app`。
