# ProxyPanel · 应用代理观察台

Windows 上的 Clash Verge Rev 应用分流观察工具。v1.0.0 保留已验证的五应用卡片、后台连接检测、自动刷新和本机分流配置，先提供可用的便携首版。

**[下载首版](https://github.com/jtl520/ProxyPanel/releases/latest)** · [版本记录](CHANGELOG.md) · [验证说明](VALIDATION.md)

## 功能

- 查看 Codex、VMware NAT、Chrome、百度网盘、夸克网盘的活动连接。
- 区分 DIRECT、代理、阻断、未知；无连接不等于直连。
- 显示当前配置与实际连接，配置切换后旧连接可能继续沿用原路线。
- 默认自动刷新：每次读取完成后等待 3 秒；后台读取不阻塞窗口。
- 卡片支持窄窗口滚动，配置操作完成后自动刷新，操作期间防止重复点击。
- 本机配置：Chrome、两个网盘及所选安装目录中的辅助程序 DIRECT；其余被 Clash 接管的流量走 GLOBAL。
- 配置前创建 Windows 当前用户加密备份，支持撤销。

## 首次使用

1. 使用 Windows 10/11 64 位、Windows PowerShell 5.1（系统自带）。下载 Releases 中的 `windows-portable.zip` 并**完整解压**到可写目录。
2. 安装并启动 Clash Verge Rev，导入自己的订阅，确认节点能够使用。然后从托盘**完全退出 Clash Verge**。
3. 双击 `Configure.vbs`，或打开 `ProxyPanel.exe` 点击“配置本机分流”。按提示选择两个网盘的安装目录；未安装可以取消对应选择。
4. 启动 Clash，启用其所需服务，确认 **规则模式、TUN 开启**，在 GLOBAL 中选择自己的节点。
5. 打开 `ProxyPanel.exe`，使用相关应用后查看连接状态。普通监控不需要管理员权限，Clash 的 TUN 服务授权由 Clash 自己管理。

已有自定义全局脚本时工具会停止，不覆盖用户脚本。本版检测标准安装目录下的 Clash Verge Rev 配置，不兼容所有叫“Clash”的客户端或便携目录布局。

## 撤销与再次启用

从托盘完全退出 Clash，点击“撤销本工具配置”或运行 `Restore.vbs`，再启动 Clash。撤销会还原配置前的 `Script.js`、`config.yaml`、`verge.yaml`；如果配置后这三个文件已有其他变动，工具会拒绝覆盖，需要人工核对。

撤销后可再次运行“配置本机分流”。不要删除程序目录中的 `migration-backup.dpapi`；它是本机恢复凭据，不能拿到另一台电脑或另一账户恢复。

公开首版使用已有的新电脑配置流程，配置/撤销需要退出并重启 Clash。作者自用版本依赖个人历史备份的在线“恢复最初配置/撤销网盘调整”不随公开包分发。普通状态读取不修改代理，不会强制断开旧连接。

## 边界

- 本版固定监控五个应用，**尚不支持添加任意应用**；不附带 Clash、代理节点、订阅或浏览器代理扩展。
- DIRECT 表示不使用 Clash 代理节点，仍消耗本地网络流量；浏览器自己的代理扩展需要独立管理。
- VMware 的监控对象是 `vmnat.exe`；桥接网络不保证经过主机 TUN。
- 根据 Clash 进程信息及 Windows TCP 端口归属匹配；短连接、UDP、间接代理和采样时间差会影响覆盖范围。不是完整抓包，也不保证每条连接都能归属。
- 应用目录变化后需要重新配置；独立安装在其他目录的更新程序不一定被覆盖。
- 软件没有代码签名证书，无后台自启服务，不保存浏览记录。运行策略 Bypass 仅限本次进程，不修改系统持久策略。

## 从源码构建

在 **Windows PowerShell 5.1** 中运行：

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Build.ps1
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Test-Matching.ps1
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Test-Migration.ps1
```

生成 `dist/ProxyPanel-v1.0.0-windows-portable.zip` 和 SHA-256 校验文件；不需要安装 .NET SDK、npm 或 Python。启动器源码位于 `Launcher.cs`，界面位于 `Dashboard.ps1`。

## 发布与隐私

仓库和发行包不包含订阅、密钥、节点配置、个人加密备份或机器连接日志。构建使用明确的文件白名单。提交问题前请移除个人路径、域名、订阅和密钥。

配置机制参考 [Clash Verge Rev 官方扩展脚本文档](https://www.clashverge.dev/guide/script.html)。
