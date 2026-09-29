# 平台说明：Flutter

本文件仅用于导航。请从技能根目录运行 `rg 'flutter-imkit|flutter-imlib' references/llms.txt`，再用 `bash scripts/fetch-docs.sh <path>` 获取目标文档。⚠️ 约定定义在 SKILL.md 中。

## 获取文档前需要了解的平台信息

- 国内 Flutter IMKit 包为 `rongcloud_im_kit`；IMLib 包为 `rongcloud_im_wrapper_plugin`。
- Flutter IMKit 使用 Config 和 Builder 两层 UI 定制，并提供会话置顶 `features/stick-to-top.md`。
- 官方 Flutter IMKit 当前明确不支持超级群；超级群使用 Flutter IMLib。

## 文档路径（按需获取）

- 能力目录：按 [功能清单使用规则](../feature-lists.md) 获取 `/flutter-imkit/feature-list.md` 或 `/flutter-imlib/feature-list.md`，再获取清单指向的功能页
- 核心：`/flutter-imkit.md`、`/flutter-imkit/import.md`、`/flutter-imkit/quickstart.md`
- 关键功能：`/flutter-imkit/key-functions/conversation-list.md`、`/flutter-imkit/key-functions/conversation.md`
- 个人资料：`/flutter-imkit/user/userinfo.md`、`/flutter-imkit/user/group-info.md`
- 功能：`/flutter-imkit/features/` → `message-mention.md`、`message-forward.md`、`message-reference.md`、`stick-to-top.md`、`unread.md`、`draft.md`、`voice-message.md`、`file-message.md`、`image-gif-message.md`、`sight-message.md`
- 定制：`/flutter-imkit/customization.md`、`customization/config/`（`conversation-page.md`、`chat-page.md`、`input.md`、`bubble.md`）、`customization/builder/`（`conversation-page.md`、`chat-page.md`、`message-bubble.md`）
- IMLib（聊天室 / 超级群等）：`/flutter-imlib/import.md`、`/flutter-imlib/init.md`、`/flutter-imlib/quickstart.md`
