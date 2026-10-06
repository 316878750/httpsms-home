# 公开源码复现验证记录

验证日期：2026-10-06。目标：Windows 11、PowerShell 5.1/7、Docker Desktop Linux containers、JetBrains JDK 25、Android SDK 37、Gradle 9.7.0。

验证使用独立工作区、合成 Firebase 配置、自己生成的临时签名身份、独立 Docker 项目与数据卷，不复用真实短信、手机配置或后端凭据。Docker/Gradle 依赖缓存可以复用；这不是全新操作系统安装测试。

| 验证项 | 结果与范围 |
|---|---|
| 独立源码文件清单 | 排除原 `.local`、Google 配置、env、密钥、APK、崩溃日志及原 CI 发布配置 |
| 干净 Git 克隆 | 不携带 `.local` 或 `google-services.json`；重新生成配置、导入合成项目及保存新工具路径通过 |
| Windows 脚本 | PowerShell 5.1 和 PowerShell 7 语法检查通过 |
| Firebase 配置导入 | 三端项目一致性、包名与 sender ID 检查通过；凭据不打印 |
| Android | 上传策略单元测试通过；正式 release 构建通过 |
| 全新 APK 签名 | 不使用旧 debug 密钥，V3 签名验证通过；未安装到真实手机 |
| 最终 Manifest | 无 READ_SMS/SEND_SMS，正式应用非 debuggable |
| Gradle wrapper | 官方 9.7.0 下载及固定 SHA-256 校验通过 |
| Docker 首次启动 | API/Web 构建、数据库迁移、内部用户初始化、五类服务启动通过 |
| HTTPS 与认证 | CA 与主机名校验下网页 200；未认证 API 401；内部 health/events 403；发送接口 403 |
| 合成收信与去重 | 相同 X-Receive-ID 重传返回相同消息 ID，数据库只保存一条 |
| 容器恢复 | 独立 API 容器重启后合成消息保留 |
| Go 单元测试 | services、middlewares、telemetry、di、handlers、repositories 六个包通过 |
| PostgreSQL 集成测试 | 独立空数据库中的持久队列、失败重试、事务与去重测试通过 |
| 隐私扫描 | 公开文件检查已知真实部署凭据和私人标识；构建输出及本地配置不入 Git |

Go 的本机 HTTP 测试最初受执行沙箱限制，允许回环访问后通过。独立测试数据库为连接测试临时绑定回环端口；发布的默认 Compose 数据库仍没有主机端口。

原开发版本此前已在 Seeker 上验证正常收信、锁屏断网补传、手机重启后首次解锁收信，以及 Windows 真实重启登录后恢复。公开版本新增的工具配置、Firebase 导入和新签名流程已按上表验证，但没有重新更换真实手机配置或实际重启正在使用的电脑。

每位用户仍必须按教程完成自己的 Firebase 登录、手机证书/权限和真实短信验收。合成配置可用于构建与 API 测试，不能替代真实 Firebase 账号登录或手机 FCM 注册。此记录不承诺所有机型、网络和验证码来源都已验证。
