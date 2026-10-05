# ContinuityForge

ContinuityForge 是一个面向组织内部的系统韧性与业务连续性平台。它帮助团队登记关键业务和技术依赖，完成业务影响分析（BIA），模拟故障影响，生成恢复顺序，记录演练过程，并导出可追溯报告。

项目地址：<https://github.com/lllg123/ContinuityForge>

## 当前阶段

当前仓库已建立 MoonBit 模块、JavaScript 目标验证入口、经过统一 API façade 校验的依赖图、业务影响分析（BIA）、故障影响传播、约束下恢复排序、恢复预案、演练审计时间线、项目与审计记录存储、本地用户权限，以及包含故障影响、恢复排序、演练时间线可视化和证据 JSON 导出的 Web 工作区。服务端接口和更完整的 Web 流程会在后续独立提交中逐步加入。

## 产品边界

- 记录业务服务、技术组件和依赖关系。
- 维护 RTO、RPO、影响等级等业务影响分析指标。
- 对故障场景做确定性的影响分析，并生成恢复顺序。
- 管理恢复预案、人工审批点和演练时间线。
- 导出包含输入、计算结果和演练证据的报告。

平台只负责分析、规划和演练记录。它不会直接操作生产系统、自动切换灾备，也不保存生产凭据。

## 目录约定

后续实现遵循以下边界：

```text
ContinuityForge/
├── core.mbt    # MoonBit 核心包入口与集成探针
├── model.mbt   # 服务、组件和依赖领域模型
├── dependency.mbt # 拓扑排序与循环依赖校验
├── bia.mbt     # RTO、RPO、最大中断时间与影响等级
├── impact.mbt  # 故障影响传播与稳定路径
├── recovery.mbt # 依赖约束、影响等级和资源窗口下的恢复排序
├── playbook.mbt # 恢复步骤、前置条件与人工审批状态机
├── drill.mbt    # 演练状态与有序审计时间线
├── api.mbt      # 统一暴露经过校验的领域操作
├── storage.mbt  # 项目与审计记录的持久化快照
├── auth.mbt     # 本地用户、角色与权限校验
├── web/
│   ├── index.html # 库存、BIA、故障、恢复与演练工作区页面
│   ├── styles.css # 工作区视觉样式
│   └── app.js     # 本地交互、模拟计算、证据导出与浏览器存储
├── server/     # API、权限、持久化和输入校验
├── docs/
│   └── operations.md # 安装、运行、操作和发布检查
├── examples/
│   └── minimal/      # 可运行的领域闭环示例与脱敏输入
└── integration/ # 跨语言构建与集成验证
```

当前 web、docs 和 examples 已提供最小可复核闭环，server 仍保留为后续服务端实现边界。

## 开发原则

1. 每次提交对应一个可复核的功能增量。
2. 核心计算保持无副作用、可重复，并优先用测试固定行为。
3. 真实生产操作由宿主系统负责，平台只生成计划和记录结果。
4. 配置、示例和提交历史中不得出现密码、令牌或其他敏感凭据。

每次功能提交都应保持范围清晰，并在提交信息中说明对应的验收结果。

## 快速开始

### 安装环境

安装 MoonBit 0.10.7 或更新版本、Node.js 20 或更新版本；如需预览 Web 工作区，再安装 Python 3。确认核心工具链：

```text
moon version --all
node --version
```

预览 Web 前再确认：

```text
python --version
```

MoonBit 可从[官方安装页面](https://www.moonbitlang.com/download/)获取。克隆仓库后进入项目目录：

```text
git clone https://github.com/lllg123/ContinuityForge.git
cd ContinuityForge
```

### 运行领域最小示例

`cmd/js_probe` 只验证 MoonBit 到 JavaScript 的集成边界；面向使用者的领域闭环示例位于 `examples/minimal`。运行：

```text
moon run examples/minimal
```

示例会完成服务与组件登记、依赖校验、BIA、故障影响传播、恢复排序、人工审批和演练时间线，并打印每一步的确定性结果。对应的脱敏输入快照见 [examples/minimal/sample-data.json](examples/minimal/sample-data.json)。

### 运行 Web 工作区

```text
python -m http.server 8765 --directory web
```

打开 `http://127.0.0.1:8765/`，依次使用 Inventory、Business impact、Incident impact、Recovery plans 和 Drill log；最后点击 **Export evidence** 下载证据 JSON。完整操作说明见 [docs/operations.md](docs/operations.md)。

## 本地验证

需要安装 MoonBit 工具链和 Node.js。仓库根目录可运行：

```text
moon fmt
moon check --deny-warn
moon build --target js --deny-warn
node integration/js/smoke.mjs
```

最后一条命令会启动 MoonBit 的 JavaScript 目标探针，并检查核心包返回的稳定标记。

web/ 是独立的静态工作区，可交给任意静态服务器预览；库存、BIA 和演练事件会保存到当前浏览器，Export evidence 会下载当前工作区的证据 JSON。

## 发布检查

发布前运行以下检查，确保 MoonBit 核心、JavaScript 集成和静态工作区都可复核：

GitHub Actions 中的 `ContinuityForge CI` 会在 `main` 的推送和 Pull Request 上自动运行同一组门禁。

```text
moon fmt
moon check --target all --deny-warn
moon test --target all
moon build --target all --deny-warn
moon run examples/minimal
node integration/js/smoke.mjs
node --check web/app.js
git diff --check
```

## 许可证

本项目以 Apache License 2.0 发布，详见 [LICENSE](LICENSE)。
