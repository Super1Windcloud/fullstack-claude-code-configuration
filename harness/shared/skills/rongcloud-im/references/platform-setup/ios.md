# 平台说明：iOS

本文件仅用于导航。请从技能根目录运行 `rg 'ios-imkit|ios-imlib' references/llms.txt`，再用 `bash scripts/fetch-docs.sh <path>` 获取目标文档。⚠️ 约定定义在 SKILL.md 中。

## 获取文档前需要了解的平台信息

- CocoaPods 的国内 IMKit 为 `RongCloudIM/IMKit`，IMLib 为 `RongCloudIM/IMLib`；也可按官方版本要求使用 Swift Package Manager。
- 国内 App Key 默认连接北京数据中心，不要配置海外区域码；只有用户明确提供海外数据中心 App Key 时才配置对应 `RCAreaCode`。

## 文档路径（按需获取）

- 能力目录：按 [功能清单使用规则](../feature-lists.md) 获取 `/ios-imkit/feature-list.md` 或 `/ios-imlib/feature-list.md`，再获取清单指向的功能页
- 核心：`/ios-imkit.md`、`/ios-imkit/import.md`、`/ios-imkit/init.md`、`/ios-imkit/quickstart.md`、`/ios-imkit/quickstart-swift.md`、`/ios-imkit/release-notes.md`
- 个人资料：`/ios-imkit/user/userinfo.md`
- 会话列表：`/ios-imkit/key-functions/conversation-list.md`
- 功能：`/ios-imkit/features/` → `message-mention.md`、`message-receipt.md`、`message-reaction.md`、`stick-to-top.md`、`typing-status.md`
- IMLib（聊天室 / 超级群等）：`/ios-imlib/import.md`、`/ios-imlib/init.md`、`/ios-imlib/quickstart.md`
