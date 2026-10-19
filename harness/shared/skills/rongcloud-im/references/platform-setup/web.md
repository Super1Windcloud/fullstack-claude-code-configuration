# 平台说明：Web

本文件仅用于导航。请从技能根目录运行 `rg 'web-im-kit|web-imlib' references/llms.txt`，再用 `bash scripts/fetch-docs.sh <path>` 获取目标文档。⚠️ 约定定义在 SKILL.md 中。

## 获取文档前需要了解的跨文档差异

- 国内 Web IMKit 包为 `@rongcloud/im-kit`；同时依赖版本匹配的 `@rongcloud/engine` 与 `@rongcloud/imlib-next`。
- 默认语言是 `zh_CN`。公开扩展能力包括 Hooks、事件、自定义组件、消息气泡和菜单；实现前以对应文档核对版本要求。
- 使用 Web IMKit 时通过 IMKit 的消息接口发送消息，避免绕过其 UI 状态更新。
- Web IMKit 的 `39003` 表示会话列表尚未同步完成；列表同步完成前不要调用 `openConversation`。官方 `openConversation` 支持打开当前列表外的新会话，因此不要把“会话已存在”当作 Web SDK 硬性条件，但仍必须校验会话类型、`targetId` 和业务权限。
- Web IMKit 没有公开的会话列表首屏完成事件。程序化打开会话前，应用需在调用 `connect()` 前注册 IMLib 监听：`RongIMLib.Events.PULL_OFFLINE_MESSAGE_FINISHED` 表示离线消息拉取完成，`RongIMLib.Events.CONVERSATIONS_SYNCED` 表示单/群聊会话列表同步完成（IMLib ≥ 5.20.0）。两个事件都触发后才调用 `kitApp.openConversation()`；若包含超级群，还需监听 `Events.ULTRA_GROUP_ENABLE` 并等其触发。`CONVERSATION_SELECTED` 只表示会话已被选中，不能作为打开前置条件。`openConversation()` 返回 `39003` 时仍表示 IMKit 内部会话列表未就绪，应保持加载态并稍后重试，不要立即循环重放。
- Web IMKit 会话详情容器内置消息列表和输入框；替换行为时优先使用官方组件覆盖、事件或 Hooks，不要在应用层重复创建同类编辑区。

## 文档路径（按需获取）

- 能力目录：按 [功能清单使用规则](../feature-lists.md) 获取 `/web-im-kit/feature-list.md` 或 `/web-imlib/feature-list.md`，再获取清单指向的功能页
- 核心：`/web-im-kit.md`、`/web-im-kit/quickstart.md`、`/web-im-kit/release-notes.md`
- 用户资料/数据：`/web-im-kit/user/hooks.md`、`/web-im-kit/user/overview.md`、`/web-im-kit/user/update.md`
- UI/扩展：`/web-im-kit/components/overview.md`、`/web-im-kit/components/override-component.md`、`/web-im-kit/chat-ui/message-bubble.md`、`/web-im-kit/chat-ui/editor.md`
- IMLib：`/web-imlib/import.md`、`/web-imlib/init.md`、`/web-imlib/quickstart.md`
