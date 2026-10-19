# IMKit 源码仓库

本文列出各平台的 IMKit 源码仓库。进入 [SDK 集成决策框架](./sdk-integration-decision-framework.md) 第 4 层“源码修改评估”时使用。

## Web

**仓库**：暂未开源

## Android

**仓库**：`https://github.com/rongcloud/android-ui-sdk-set`

## iOS

**仓库**：`https://github.com/rongcloud/ios-ui-sdk-set.git`

## Flutter

**仓库**：`https://github.com/rongcloud/flutter-im-kit.git`

## 使用方式

### 何时使用

当决策框架进入第 4 层时，根据目标平台找到对应仓库，克隆到本地或团队仓库，完成并测试定制，然后记录修改文件及原因，以便未来升级迁移。

### 获取源码

可以将源码克隆到项目根目录或团队指定的依赖目录。可选的 `chat-ui-source` 目录仅用于多平台项目集中管理源码，不是集成要求。

```bash
# 从项目根目录运行
cd /path/to/your/project

# 设置源仓库（此处以 Android 官方仓库为例）
# 使用团队 Fork 时，将下面的 URL 替换为 Fork 地址
imkit_repository_url="https://github.com/rongcloud/android-ui-sdk-set"
git clone "${imkit_repository_url}" imkit-android

# 进入仓库目录
cd imkit-android

# 查看分支和版本
git branch -a
git tag

# 创建定制分支
git checkout -b custom/imkit-android-your-feature
```

如需集中存放多个平台源码，可将目标目录设为 `imkit-source/<repository>`。源码目录名不会决定集成是否成功；克隆后仍需按目标平台配置 Gradle 模块、Swift Package Manager/CocoaPods，或 Flutter `path`/`git` 依赖。

### 重要说明

1. **仅在最后手段使用源码修改**：只有原生能力、扩展和 IMLib API 都无法满足需求时才考虑。
2. **获得用户明确批准**：修改前说明影响和风险并得到同意。
3. **记录全部变更**：使用 Git 分支管理，并在提交信息中详细说明原因。
4. **规划版本升级**：升级 SDK 时重新评估并迁移修改。

## 相关文档

- [SDK 集成决策框架](./sdk-integration-decision-framework.md)
- [集成工作流](./integration-workflow.md)
