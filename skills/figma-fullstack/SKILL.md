---
name: figma-fullstack
description: "Full-stack Figma to code implementation & asset export. Translates Figma designs into Android Jetpack Compose or modern Web (React/Tailwind/Vue) UI. Handles design token extraction, responsive layout adaptation without fixed canvases, 9-patch handling, multi-density drawable/SVG asset exporting, and multi-device Compose preview matrices. Triggers whenever a Figma URL appears or the user requests implementing a Figma design or exporting design assets."
disable-model-invocation: false
---

# Figma Full-Stack Implementation & Asset Export (Figma → Code)

Use this skill whenever a Figma design URL is provided (`https://www.figma.com/design/:fileKey/:fileName?node-id=:nodeId`) or the user requests implementing a screen, component, or exporting assets from Figma.

---

## 1. 核心流程与工具编排 (Tool Workflow)

### 1.1 工具调用规范
1. **参数提取**：从 Figma 链接提取 `fileKey` 与 `nodeId`（将 URL 中的 `-` 转换为 `:`，例如 `node-id=123-456` → `123:456`）。
2. **提取设计上下文**：优先调用 `get_design_context` 获取结构语义、布局参数与截图：
   - Android Compose 目标：传入 `clientLanguages: "kotlin"`, `clientFrameworks: "compose"`；
   - Web / Frontend 目标：传入 `clientLanguages: "typescript"`, `clientFrameworks: "react,tailwind"`；
   - 包含 `skillNames: "figma-fullstack,resource:figma-design-to-code"` 便于链路追踪。
3. **视觉校验源**：`get_design_context` 返回的代码是近似结构参考，**截图（Screenshot）才是终极视觉标准**。切勿盲目机械转译绝对定位（`position: absolute`）或固定像素宽高。
4. **切图资源下载**：若涉及图标、插画或位图，调用 `download_figma_images` 批量导出至项目资源目录。

---

## 2. 目标栈 A：Android Jetpack Compose 规范契约

当目标工程为 Android 或涉及 `.kt` / Compose UI 时，**必须严格遵守以下自适应门禁**：

### 2.1 布局与自适应防御（严禁整页固定画布）
- **设计稿尺寸仅为基准**：画板的宽高（如 375x812、1080x1920）是相对关系基准，**严禁将容器宽度或高度用固定 `dp` 锁死**（例如禁止 `Modifier.size(375.dp, 812.dp)`）。
- **父约束优先**：容器优先使用 `fillMaxWidth()`、`fillMaxHeight()`、`weight()`、`aspectRatio()`、自适应网格或滚动容器。
- **严禁整体缩放**：绝对禁止通过 `Modifier.scale()` 或固定居中画布去“等比缩放”适配不同屏幕，必须让组件随父容器重新排版与分配空隙。
- **固定尺寸例外**：仅对最小触控目标（≥ 48dp）、图标原始比例、头像、可读性下限或视觉锚点允许声明固定宽高。

### 2.2 设计系统与 Token 映射
- **颜色与字体**：将 Figma CSS 变量/Token 映射至项目 design system（如 `compose-ui`、`MaterialTheme.colorScheme`），禁止在业务组件内散落硬编码 HEX 颜色。
- **文案与国际化**：所有 UI 可见文本必须抽取到对应模块或 `libRes` 的 `strings.xml` 中，默认同步补齐支持的语言 locale，禁止直接硬编码自然语言字符串。
- **透明度控制**：直接使用 Figma 节点的原始图层透明度；除非 Figma 明确标注或同尺寸截图对比要求，切勿臆想增加额外的 `Modifier.alpha`。

### 2.3 资产与 NinePatch 规范
- **位图密度**：PNG 资源默认导出最高目标密度（优先 `drawable-xxhdpi` 或 `drawable-xhdpi`），禁止插值放大低清素材。
- **NinePatch 资源**：切片拉伸背景导出为 `.9.png`；在 Compose 中使用 `NinePatchDrawable` / `Canvas` 绘制，禁止在 `painterResource` 中直接加载 `.9.png`；在 Preview 中回退至普通 PNG 占位。

### 2.4 系统边距与 Insets (Edge-to-Edge)
- Activity 适配 Android 15+ 强制 edge-to-edge；
- 统一使用 `safeDrawing`、`systemBars` 或 `ime` Insets，确保同一内容边界只有一个 Insets owner，避免多层重复叠加 padding。

### 2.5 必守 Preview 验证矩阵
每个独立 Compose 页面文件必须提供直接标注在无参 `@Composable` 上的 `@Preview`，并覆盖以下形态：
1. **Phone** (竖屏 `412 x 915dp`)；
2. **Tablet** (横屏 `1280 x 800dp`)；
3. **Fold 折叠屏四档矩阵**：
   - 折叠态竖屏：`412 x 915dp`
   - 折叠态横屏：`915 x 412dp`
   - 展开态竖屏：`673 x 841dp`
   - 展开态横屏：`841 x 673dp`
所有档位复用同一份 `UiState`，Preview 仅作为布局约束测试，不可借此注入生产数据。

---

## 3. 目标栈 B：Web / 前端 (React / Vue / Tailwind) 规范契约

当目标工程为 Web、Desktop (Tauri 前端) 时：
- **语义化结构**：优先采用 `header`、`main`、`nav`、`section`、`footer` 等语义化 HTML 标签。
- **Flexbox / Grid 响应式流动**：将 Figma Auto-Layout 精准转换为 Flexbox（`flex-row`, `flex-col`, `gap-*`, `justify-*`, `items-*`），复杂的瀑布或卡片使用 Grid。
- **Tailwind 体系对齐**：使用项目现存的 Tailwind 预设颜色与间距尺度，避免非标方括号属性（如 `w-[342px]`），优先使用标准断点（`sm:`, `md:`, `lg:`）。
- **矢量 SVG 优先**：图标一律交付精简的内联 SVG 或 React 组件（如 Lucide / SVG sprite），保障高分屏绝对锐利度。

---

## 4. 目标栈 C：切图资源导出规范 (Asset Exporting)

若需求为纯切图提取与资源沉淀：
1. **保留元数据**：记录 `fileKey`、Page、节点 ID、节点原名、原尺寸及 `exportSettings`；
2. **命名规范**：遵循目标平台命名（Android 必须小写蛇形 `[module]_[feature]_[type]_[name].png`，Web 使用 kebab-case）；
3. **输出 Manifest**：将节点 ID 与导出的物理文件路径、md5 对应关系记录于 `manifest.json`；
4. **防覆盖校验**：导入工程前检查同名资源，未经确认不得盲目覆盖既有素材。
