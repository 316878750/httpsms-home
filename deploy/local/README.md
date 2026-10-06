# 从干净克隆复现家庭收信系统

本文针对 Windows PowerShell 5.1 或 PowerShell 7、Docker Desktop Linux containers、Android 9+。请使用全新专用数据库。示例 `192.168.1.50`、`192.168.1.0/24`、工具目录需要替换为自己的值。

## 1. 工作原理和运行条件

真实 SIM 收新短信 → Android 接收器 → WorkManager 持久上传任务 → 家庭 HTTPS 收信 API → PostgreSQL → 本机网页。断网时任务保留，恢复后重试；同一用户和上传 ID 去重。

Firebase 用于账号认证，Android 保留 FCM 注册。需要正常连接 Google 服务。手机和电脑使用同一家庭 Wi-Fi，不能把 USB 连接当作局域网连接。电脑开机登录、避免休眠；手机重启后首次解锁。

本机网页只监听回环 `8443`。家庭 `8444` 只提供注册、短信上传与心跳，仍需要用户 API Key。数据库和 Redis 不映射到宿主机。

## 2. 安装工具

安装 Git 和 Docker Desktop，启用所需虚拟化/WSL 条件并使用 Linux containers。按 [Docker Windows 官方说明](https://docs.docker.com/desktop/setup/install/windows-install/) 检查本机要求。不要删除已有 WSL 数据。

Android 编译需要本仓库 Gradle wrapper 9.7.0、JetBrains JDK 25、Android SDK platform 37、build-tools 37.0.0、platform-tools。Gradle daemon 配置指定 JetBrains 25，普通 JDK 21 不能替代它。[JetBrains Runtime](https://github.com/JetBrains/JetBrainsRuntime/releases)、[Android 命令行工具](https://developer.android.com/studio#command-line-tools-only)

将 Android command-line tools 解压到自选 SDK 目录的 `cmdline-tools/latest`，使该目录下直接有 `bin/sdkmanager.bat`。例如在已安装 JDK 的 PowerShell 中：

```powershell
$env:JAVA_HOME = 'D:\sms-tools\jbr-25' # 自己解压后的真实 JDK 根目录
$env:PATH = "$env:JAVA_HOME\bin;$env:PATH"
& 'D:\sms-tools\android-sdk\cmdline-tools\latest\bin\sdkmanager.bat' --sdk_root=D:\sms-tools\android-sdk 'platform-tools' 'platforms;android-37' 'build-tools;37.0.0'
& 'D:\sms-tools\android-sdk\cmdline-tools\latest\bin\sdkmanager.bat' --sdk_root=D:\sms-tools\android-sdk --licenses
```

阅读并接受自己的 SDK 许可。Docker 程序和镜像数据盘要分别设置；大型工具、缓存可放 D 盘，Windows 组件仍可能占 C 盘。无需模拟器，也不要求 Android Studio。

## 3. 克隆并生成配置

```powershell
git clone --branch v1.0.1-home https://github.com/316878750/httpsms-home.git
cd httpsms-home
.\deploy\local\Prepare-Local.ps1 -LanIP 192.168.1.50 -LanCidr 192.168.1.0/24
```

脚本仅接受私有地址及当前防火墙支持的 `/24` 子网，生成 `.local/compose.env`、`api.env` 和内部用户 SQL，并限制 Windows ACL。不会覆盖已有配置，也不会打印密码。它同时写入 Android 家庭地址和限定用户 CA 的信任范围。

确认电脑网卡为 Up，并在路由器中保留该地址。不使用访客隔离或公网端口映射。不要在启动时叠加上游 `docker-compose.yml`，本教程使用独立 `compose.local.yml`。

配置自己的工具位置：

```powershell
.\deploy\local\Configure-Tools.ps1 `
  -JdkHome 'D:\sms-tools\jbr-25' `
  -AndroidSdk 'D:\sms-tools\android-sdk' `
  -CacheRoot 'D:\sms-tools\cache' `
  -DockerDesktopPath 'D:\Docker\Docker Desktop.exe'
```

参数是实际文件位置；若 Docker 安装在默认目录，可省略 DockerDesktopPath。自备 Gradle 9.7.0 时可选 `-GradleHome`；默认使用仓库 wrapper 下载发行包。设置保存在被忽略的 `.local/tools.json`，不会写入公开源码。

## 4. 建立自己的 Firebase 项目

1. 注册 Web 应用，复制 `apiKey`、`authDomain`、`projectId`、`messagingSenderId`、`appId`。
2. 启用 Authentication 的邮件/密码登录；添加 `localhost` 授权域。此用途不需要 Analytics，也不需要电话短信登录提供方。
3. 注册包名 `com.httpsms` 的 Android 应用，下载 `google-services.json`。参考 [Android 配置](https://firebase.google.com/docs/android/setup)。
4. 确认 Firebase Cloud Messaging API（HTTP v1）启用；Android 手机需要 Google Play 服务及网络。
5. 在项目设置的服务账号页面生成自己的后端私钥文件。不要分享它或放进 APK。

把以下文件放到已经受 ACL 保护的 `.local`：

- `firebase-web.json`：从 `deploy/local/firebase-web.example.json` 复制并填写，必须是有效 JSON，不是 JavaScript 的 `const firebaseConfig`。
- `android-google-services.json`：Android 控制台下载的配置。
- `service-account.json`：后端服务账号文件。

```powershell
.\deploy\local\Import-Firebase.ps1 `
  -WebConfig .\.local\firebase-web.json `
  -AndroidConfig .\.local\android-google-services.json `
  -ServiceAccount .\.local\service-account.json
```

脚本检查三端项目一致、Android 包名和发送者 ID，将配置写到本地 env 与 Android 配置文件。Web 和 Android 配置属于客户端参数；服务账号私钥只供后端使用。不要把系统事件用户的密钥放到手机。

## 5. 设置防火墙并启动

管理员 PowerShell 进入同一个仓库，安装仅限家庭网络的规则：

```powershell
.\deploy\local\Protect-DockerLanPort.ps1 -LanIP 192.168.1.50 -LanCidr 192.168.1.0/24
```

这会明确阻止非家庭 IPv4 访问指定家庭地址的 TCP 8444，再允许家庭子网，覆盖 Docker 的宽泛允许规则。已有同名规则时停止，请先检查旧部署，不直接覆盖。

回到普通 PowerShell，确认 Docker Desktop 已启动：

```powershell
.\deploy\local\Start-Local.ps1
```

首次构建会下载依赖和镜像，需要网络与磁盘。脚本等待数据库迁移、创建内部事件用户，构建 Web 并导出 `.local/home-ca.crt`。不要把 `docker compose config` 的完整输出发到公开处，它会展开凭据。

Docker Desktop 常把手机源地址改写为 edge 网关。需支持这一行为时，在管理员 PowerShell 中执行：

```powershell
.\deploy\local\Enable-DockerPeer.ps1
```

脚本先验证防火墙规则与当前地址/子网匹配、各网络类别防火墙启用，再读取当前 Docker edge 网关并重建 proxy。不能手填 `0.0.0.0/0`。重建 Docker 网络后网关可能变化，需重新配置；403 时检查真实来源，不能直接全放行。

需要只检查防火墙而不改配置时，运行 `Enable-DockerPeer.ps1 -CheckOnly`。v1.0.1-home 同时识别 Windows 返回的 `/24` 和 `/255.255.255.0` 表示。

## 6. 信任公开证书、注册网页账号

确认导出证书来自刚创建的本地服务，核对指纹，导入当前 Windows 用户信任库：

```powershell
Get-FileHash .\.local\home-ca.crt -Algorithm SHA256
Import-Certificate -FilePath .\.local\home-ca.crt -CertStoreLocation Cert:\CurrentUser\Root
```

重新打开浏览器，访问 `https://localhost:8443`。选择邮件登录或注册；如在 Firebase 已创建账号，使用同一邮件和密码。进入 Settings 的 API Key 区域，手机需要的是这里自己的用户 Key。

不要使用上游账号，不要给手机内部系统 Key。若只启用邮件/密码，Google/GitHub 登录不适用。

## 7. 构建并安装自己的 APK

```powershell
.\deploy\local\Build-Android.ps1 -Tasks testDebugUnitTest
.\deploy\local\Build-Release.ps1 -VersionCode 2
```

正式包位于 `releases/httpsms-home-release-v2.apk`，全新创建并复用 `.local/signing/httpsms-home.p12`。签名密码和密钥都不打印。默认不依赖 debug keystore。

只在迁移自己之前用 debug 签名安装的版本时，追加 `-OldDebugKeystore '自己的debug.keystore路径'`。这不是迁移任意上游 APK 的通用方法；签名材料不匹配时停止处理，不能直接卸载丢数据。

手机开启开发者选项和 USB 调试，确认电脑授权弹窗。普通 PowerShell 执行：

```powershell
. .\deploy\local\Use-DDriveTools.ps1 -NeedAndroid
adb devices
# 多设备时用 adb -s 自己的序列号；下面仅用于已确认单台设备的情况
adb install -r .\releases\httpsms-home-release-v2.apk
adb push .\.local\home-ca.crt /sdcard/Download/httpsms-home-ca.crt
```

在手机设置中安装 Download 里的 CA 证书。核对同一个公开根证书，不传输 CA 私钥。应用仅为准备脚本指定家庭地址信任用户 CA，不能全局关闭 TLS 校验。

首次打开手机应用，填写家庭地址 `https://192.168.1.50:8444`、网页自己的 API Key 和真实 SIM 号码（带国家区号），完成注册。允许接收短信、通知和必要后台运行，关闭该应用电池优化；开启接收开关。双 SIM 机型按实际使用填写两张 SIM。

如果系统因侧载安装限制授权，先在应用信息页面检查是否有“允许受限设置”，再授权必要权限；不同 Android 版本入口可能不同。不要授予本版本未申请的发送或历史短信读取权限。

## 8. 验收与使用

先用另一台手机发普通测试短信，不要用银行验证码测试。网页会轮询更新，检查该条只出现一次。

分别验证：锁屏且关闭 Wi-Fi 时后端未收到；恢复 Wi-Fi、不打开应用后补传一次；手机重启并首次解锁、不打开应用后收到新短信。测试网络中断时设置恢复提醒或兜底。

电脑恢复设置和重启基线：

```powershell
.\deploy\local\Enable-LoginRecovery.ps1
.\deploy\local\Write-RebootBaseline.ps1
```

保存工作后自行重启电脑、登录 Windows，不手动启动服务。检查 `.local/startup-recovery-status.json` 的 `trigger_source=ScheduledTask`、`success=true`，和 `.local/reboot-baseline.json` 的重启验证结果。检查历史消息仍在；记录中的计数检查不代替逐条去重测试。

```powershell
Get-ScheduledTaskInfo -TaskName 'httpSMS Home Recovery'
Get-Content .\.local\startup-recovery-status.json
Get-Content .\.local\reboot-baseline.json
```

网页不可用时可手动运行 `Resume-Local.ps1` 排障，但手动恢复成功不能算本次自动验收通过。计划任务等待网卡和 Docker，并以当前用户普通权限启动，不要求关闭防火墙。

## 9. 升级、备份与限制

保管并加密备份 `.local/signing` 和自己的 Firebase 凭据，后续构建复用同一签名、递增 VersionCode。升级前备份数据库；配置和证书保留对应 Docker volumes，不删除卷。

默认不读取历史短信，不自动删除旧消息。默认数据库短信为明文，使用设备锁、磁盘加密保护本地数据和备份。禁用 Android 备份不能代替数据库保护。

电脑离线时手机保留上传任务；强行停止应用、清除数据或卸载可能破坏接收或队列。这里仍依赖 Firebase，不是完全离线系统，也不是默认端到端加密。事件队列为至少一次，不能推导所有副作用恰好一次。

正常停止：

```powershell
.\deploy\local\Stop-Local.ps1
```

不要用 `down -v`。地址改变需同步服务、证书和 Android 配置并重建 APK。当前版本保留一些上游菜单和发送页面，发送/外部集成请求会被后端拒绝；不要将它们当成此配置支持的功能。

## 10. 开发验证与排障

Go 修改相关测试：

```powershell
cd api
go test ./pkg/services ./pkg/middlewares ./pkg/telemetry ./pkg/di ./pkg/handlers ./pkg/repositories
```

数据库集成测试仅使用独立空测试库，设置 `LOCAL_QUEUE_TEST_DSN` 再运行 `go test ./pkg/services -run TestLocalQueueDatabase`。未配置时测试会跳过，不应声称已通过数据库验收。不能指向真实收件数据库。

常见问题：旧 IP 存在但网卡已断开；TLS 正常但 Docker 来源导致 403；FCM token 缺失时检查 Google 服务与 Firebase 一致性；JDK/SDK 版本不符；native memory 不足时使用脚本低并发构建。使用 Skill 中的排障说明进一步检查。
