# httpSMS Home：Android 手机 + 家庭电脑短信收件箱

这是 [NdoleStudio/httpsms](https://github.com/NdoleStudio/httpsms) 的家庭收信修改版：自有真实 SIM 接收新短信，Android 通过家庭 Wi-Fi 上传，Windows 电脑保存并在本机浏览器展示。

**首次部署请按 [完整复现教程](deploy/local/README.md) 操作。** 每位用户需要自己的 Firebase 配置、手机和签名密钥；仓库不分发预配置 APK、不提供虚拟号码。

首个固定版本为 `v1.0.0-home`；验证范围见 [复现记录](docs/REPRODUCIBILITY.md)，原理与开发经验见 [开发教程](docs/architecture-and-development.md)。

## 本次修改

- 接收专用 Android APK：不申请发送和历史短信读取权限，禁用备份，去除外部日志与分析组件。
- WorkManager 持久任务、稳定上传 ID、后端去重及 PostgreSQL 事件队列。
- 本机网页 `https://localhost:8443`；手机端口 `8444` 仅绑定家庭 IPv4，要求认证并限制接口。
- 独立 Compose 配置，数据库和 Redis 不开放宿主机端口，外部发送/集成接口受限制。
- 可配置 Windows 工具路径、自有 Firebase 导入、全新正式签名、登录后服务恢复及重启检查。

## 开始前

需要 Windows + Docker Desktop Linux containers、Android 9+（有 Google Play 服务）、真实 SIM、同一家庭 Wi-Fi 和 USB 调试。已验证设备是 Solana Seeker，其他机型仍需要按教程验收。

当前脚本支持家庭 `/24` IPv4 子网。其他子网需要先调整并验证防火墙脚本。不要做路由器公网端口映射。

```powershell
git clone --branch v1.0.0-home https://github.com/316878750/httpsms-home.git
cd httpsms-home
.\deploy\local\Prepare-Local.ps1 -LanIP 192.168.1.50 -LanCidr 192.168.1.0/24
# 接着按完整教程配置工具和自己的 Firebase；上面地址只是示例。
```

<a id="android"></a>
## Android 安装包

按教程使用自己的 `google-services.json` 与签名密钥构建 APK。全新安装不需要旧 debug 密钥；从自己原先的 debug 包升级时才按需指定 `-OldDebugKeystore`。

不要安装上游公共 APK 并期待它连接本修改版：权限、服务地址、证书信任和 Firebase 配置都必须匹配。

## 限制与数据

Firebase Authentication/FCM 等外部依赖仍在，不能完全离线；手机上传正文通过 HTTPS 传输，默认数据库明文保存。没有自动过期清理，不承诺所有验证码或所有机型永不丢消息。

电脑需要开机登录且避免休眠；手机重启后首次解锁。不要清除应用数据、随意卸载或删除数据库卷。旧上游数据库可能含外部集成，使用全新专用数据库。

## Skill

可用 [httpsms-home-skill](https://github.com/316878750/httpsms-home-skill) 指导 Codex 检查环境并执行流程，调用名 `$httpsms-home`。Skill 不携带任何人的私人账号或密钥。

## 来源与许可

基于上游提交 `8f44d83091deac7a8c6491fb3c5fa85f1ed08a53`，沿用 [AGPL-3.0 许可证](LICENSE)，保留上游声明。修改清单见 [SOURCE_NOTICE.md](SOURCE_NOTICE.md)。这是独立修改版，不是上游官方项目；上游原说明保存在 [UPSTREAM_README.md](UPSTREAM_README.md)。
