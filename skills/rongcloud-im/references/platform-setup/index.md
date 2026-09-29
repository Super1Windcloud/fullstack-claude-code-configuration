# 融云 IM 平台说明

每个平台文件仅用于**导航**：它指向需要获取的国内官方文档，并记录已核实的平台差异。单个版本的 API、默认值和限制仍以按需获取的官方文档及项目安装版本为准。

IMKit 会话类型覆盖情况位于 SKILL.md。业务能力矩阵见[基础功能指南](https://docs.rongcloud.cn/guides/realtime-chat/intro-chat/im-feature-basic.md)。

确定目标平台后，打开对应文件查看文档地图和差异标记：

| 平台 | 文件 |
| --- | --- |
| Web | `platform-setup/web.md` |
| Android | `platform-setup/android.md` |
| iOS | `platform-setup/ios.md` |
| Flutter | `platform-setup/flutter.md` |

## 获取官方文档（适用于所有平台）

每个平台文件末尾都有**按需获取的文档索引**，列出官方文档路径，而不是阅读清单。平台文件说明某个问题对应哪个文档；获取该路径后才能查看实际事实（功能默认值、限制、API 名称、参数和配置对象）：

平台文件中的命令都应从**技能根目录**（`rongcloud-im/`）运行，例如：

```
bash scripts/fetch-docs.sh <path>       # 例如 /android-imkit/quickstart.md
rg 'Android.*IMKit' references/llms.txt # 发现平台文件未列出的路径
```

`fetch-docs.sh` 将文件写入 `references/cache/` 并管理有效期：默认 7 天后重新下载，网络不可用时回退到旧缓存。使用 `--force` 可立即刷新。

不要选择索引中带 `Global` 标记的 UI 套件；本技能默认只处理国内 IMKit/IMLib。只有用户明确要求海外产品时，才说明它不属于本技能默认路径。

⚠️ 约定（例如 `⚠️ 未验证`）定义在 SKILL.md 中。
