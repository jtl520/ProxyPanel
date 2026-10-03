# ProxyPanel · 应用分流管理器

Windows + Clash Verge Rev 的应用分流工具。[下载 v1.1.0 通用版](https://github.com/jtl520/ProxyPanel/releases/tag/v1.1.0)。旧版 [v1.0.0](https://github.com/jtl520/ProxyPanel/releases/tag/v1.0.0) 保留，可按需下载。

## 通用版功能

- 添加任意 `.exe`，或从正在运行的进程中选择。
- 每个应用选择 **不使用代理 / 使用代理 / 由 Clash 决定**。
- 按完整程序路径、安装目录（含辅助进程）、进程名匹配；默认完整路径。
- 编辑、移除、禁用、搜索应用；默认每轮读取后间隔 3 秒自动刷新。
- 显示真实直连/代理连接数量，点击数量查看判定依据。
- 导入/导出应用列表，失效路径单独提示并可重新定位。
- 自动检测标准 Clash Verge Rev 配置目录，也可手动选择。
- 只管理本工具的脚本段，不覆盖原订阅和用户脚本；加密备份、冲突检测和撤销。
- 便携使用，或免管理员安装到当前用户目录，创建桌面和开始菜单快捷方式。

## 使用

1. 安装 Clash Verge Rev，导入自己的订阅并验证节点可用。工具不附带 Clash 或代理订阅。
2. 完整解压构建生成的 `ProxyPanel-v1.1.0-windows-portable.zip`，打开 `ProxyPanel.exe`。也可双击 `Install.vbs` 安装到 `%LOCALAPPDATA%\Programs\ProxyPanel`。
3. 点击“添加应用”，选择程序文件和匹配范围。网盘如需包含下载器、播放器等同目录辅助程序，可选择目录匹配；不要选择多个无关应用共用的目录。
4. 在列表中选择直连、代理或跟随规则。修改此处先保存为草稿，不会立即改变网络。
5. **从托盘完全退出 Clash Verge**，点击“应用设置”，然后重新启动 Clash。保持规则模式；需要接管普通应用流量时，在 Clash 内启用 TUN。工具不改变 TUN 状态。
6. 查看“设置已生效”以及实际连接。已有连接不会被强制断开；未知归属、短连接及 UDP 不保证完整覆盖。

撤销：退出 Clash → 点击“撤销本工具规则” → 重启 Clash。仅移除本工具管理段；其他流量继续遵循原有订阅/脚本，不再强制全部走 GLOBAL。全部应用改为“由 Clash 决定”、全部停用或移除后，也可直接点击“应用设置”，会自动移除本工具此前添加的规则；已有规则时仍需先退出 Clash Verge。

“GLOBAL”代表使用 Clash 的 GLOBAL 组；如果该组本身选择了 DIRECT，也会直连。“跟随规则”表示本工具不为该应用添加覆盖规则，不会撤销其他工具设置的规则。

## 换电脑与升级

在旧电脑导出应用列表，新电脑安装后导入，再在“设置”中检测 Clash。路径不同的应用会显示“路径失效”，点击“编辑”重新选择程序。按进程名匹配不依赖固定目录，但会匹配所有同名进程。

应用列表位于 `%LOCALAPPDATA%\ProxyPanel\settings.json`；管理状态和备份存储在同一目录，使用当前 Windows 用户加密。导出文件仅包含应用名称、路径、匹配方式和路线，不含订阅、接口密钥、节点或配置备份。加密备份不支持跨电脑/账户恢复。

从 1.0.0 升级：如使用过 1.0 的配置工具，先使用**原 1.0 程序目录中的 Restore.vbs 及其备份**撤销旧规则，再在新版重建应用列表。新版本不会擅自删除旧版本、订阅或其他工具的规则。

安装器只复制程序文件，不覆盖应用列表或加密备份。卸载前先撤销本工具的规则，再删除安装目录和快捷方式；需要保留迁移能力时保留数据目录。

## 支持范围

Windows 10/11 64 位，系统自带的 Windows PowerShell 5.1、.NET Framework 4.x，Clash Verge Rev。非标准配置目录可手动指定，但不支持其他 Clash 客户端的专有持久化结构或远程控制接口。

原全局脚本需提供 `function main(...)`。工具会调用并保留它的返回结果，再添加应用设置。脚本管理段被外部修改时，会停止应用/撤销，避免覆盖。不要同时在多个工具中编辑同一段规则。

程序没有代码签名，不增加开机自启或后台服务；启动参数中的 ExecutionPolicy Bypass 只作用于该次进程。

## 构建与验证

在 Windows PowerShell 5.1 中运行：

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Test-General.ps1
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Test-Matching.ps1
powershell.exe -NoProfile -ExecutionPolicy Bypass -STA -File .\Test-UI.ps1
powershell.exe -NoProfile -ExecutionPolicy Bypass -STA -File .\Test-UI.ps1 -Layout
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Test-Mihomo.ps1
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Build.ps1
```

不需要 .NET SDK、npm 或 Python。Node.js 仅用于可选的生成脚本测试，不是程序运行依赖。产物位于 `dist/`，附 SHA-256 校验文件。打包使用文件白名单，不包含用户数据。

- `Core.ps1`：应用配置、验证、规则生成、备份和撤销。
- `Monitor.ps1` / `ProxyPanel.ps1`：Mihomo 只读接口及连接归属。
- `Dashboard.ps1`：WPF 界面。
- `Install.ps1`：当前用户安装。
- [验证范围](VALIDATION.md) · [版本记录](CHANGELOG.md)

本机选项回归测试还提供 `Test-UIOptions.ps1 -ManifestPath <manifest.json>` 和 `Test-OptionLifecycle.ps1 -ManifestPath <manifest.json>`。前者在独立列表中操作真实 WPF 控件并生成选项配置，后者在隔离 Clash 目录验证应用/撤销和生成脚本（需要 Node.js）。清单包含 `root`（当前用户 TEMP 下的专用测试目录）与 `apps` 数组，每项提供 `name` 和已安装 `.exe` 的绝对 `path`；先运行界面测试，再运行生命周期测试。这两个入口不修改实际 Clash 配置。真实联网验证记录不随公开源码上传。

官方协议依据：[Clash Verge Rev 扩展脚本](https://www.clashverge.dev/guide/script.html)、[Mihomo 路由规则](https://wiki.metacubex.one/config/rules/)。
