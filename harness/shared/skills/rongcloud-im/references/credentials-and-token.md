# 融云 IM 凭据与 Token 指南

处理 App Key、App Secret、Token、Postman 测试、占位凭据或客户端/服务端安全边界前阅读本文件。

## 目录

- 必需凭据
- App Key 处理
- Token 处理
- 占位符策略
- Postman 测试路径
- 安全边界

## 必需凭据

融云 IM 运行时集成需要：

- App Key：客户端 SDK 使用的应用标识。
- Token：连接融云 IM 服务的用户身份凭据。
- App Secret：用于签名或调用特权服务端 API 的服务端密钥，绝不能暴露在客户端代码中。

App Key 和 Token 是可运行初始化及连接代码的必需项。缺少凭据不会阻止架构讨论、代码审查、项目检查、文档查询，或明确标注为占位符的不可运行脚手架。

### 登录 UI 属于应用层（不是 SDK）

如果原型、截图或功能清单出现登录表单（手机号、国家码、密码、2FA/OTP、二维码登录、“保持登录”），将这些界面归类为应用层，并视为超出 `rongcloud-im` 范围。IMLib 只接收服务端签发的 **Token**，不提供登录或注册界面、密码/2FA/OTP 流程、二维码登录配对或会话持久化 UI。

推荐拆分：应用负责自己的认证服务；认证成功后，应用服务端从融云服务端 API 获取绑定用户 ID 的 Token；客户端再通过目标平台 IMLib 的连接 API 使用该 Token。连接方法必须从当前国内官方文档和已安装版本确认，不要复用其他版本的类名，也不要为了匹配竞品截图而虚构 SDK 登录 API。

## App Key 处理

用户未提供 App Key 时，引导其获取：

```markdown
请提供融云 App Key。如果还没有：

1. 登录[融云开发者后台](https://console.rongcloud.cn/agile/apps/list)
2. 创建新应用或选择已有应用
3. 在应用详情页复制 App Key

安全提示：App Secret 只用于服务端签名，绝不能暴露在客户端代码中。
```

用户要求可运行的初始化或连接代码但没有 App Key 时，先索要 App Key，不要把占位初始化代码说成可运行代码。若明确需要不可运行脚手架，使用 `YOUR_APP_KEY` 等占位符，并在最终待办中指出需要替换的文件。

## Token 处理

Token 必须通过服务端 API 流程获取。不要生成在前端/移动端使用 App Secret 签名，或直接调用特权 Token API 的代码。

从 `./references/llms.txt` 找到服务端 Token 文档路径，运行 `bash scripts/fetch-docs.sh <path>`，读取 `./references/cache/` 下的缓存 Markdown，并以官方文档为准处理签名、参数、示例和安全要求。

如果应用已有服务端 Token 端点，将客户端接入该端点或已有服务端变量。用户未提供 Token 但要求客户端集成时，使用 `YOUR_TEST_TOKEN` 或 `chatToken` 等明确注入变量，并在待办中说明需要接入真实 Token。

## 占位符策略

| 情况 | 处理 |
| --- | --- |
| 用户询问建议、方案或架构 | 无需凭据即可继续，并列出凭据前置条件 |
| 用户要求代码且接受占位符 | 生成明确不可运行的脚手架，并列出待办 |
| 用户要求可运行初始化/连接代码但缺 App Key | 先索要 App Key，不生成可运行初始化代码 |
| 缺 Token 但已有 App Key | 接入服务端 Token；否则使用带标记的占位符 |
| 用户要求客户端使用 App Secret 签名 | 拒绝该实现，提供安全的服务端或 Postman 替代方案 |

## Postman 测试路径

如果尚无应用服务端且用户想快速验证 Demo，说明生产 Token 必须来自应用服务端，并建议使用官方 Postman Collection：https://docs.rongcloud.cn/platform-chat-api/api-explorer/explore-api-with-postman。不要提交真实 Token、App Secret 或签名请求材料。

## 安全边界

绝不生成将 App Secret 放入客户端、在浏览器或移动应用中执行服务端签名、记录敏感凭据或把测试 Token 当作生产认证设计的代码。可接受的模式是：客户端在应用认证后从服务端获得 Token；安全注入 App Key；Demo 使用带说明的占位符；服务端从环境变量或密钥存储读取 App Secret。
