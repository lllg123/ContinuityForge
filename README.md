# ContinuityForge

ContinuityForge 的核心是 **MoonBit 单模式资源受限项目调度（RCPSP）库**：对有依赖、固定工期、多个同时占用的可再生资源、最早开工与硬截止的任务，生成、验证并分析可行排程。系统韧性、业务连续性和 CI/CD 是同一调度核心的应用场景；现有 Web 工作区还提供资产登记、业务影响分析（BIA）、故障影响传播、恢复预案、演练审计与证据导出。

项目地址：<https://github.com/lllg123/ContinuityForge>

## 当前阶段

`scheduling/` 已提供独立于业务场景的 RCPSP v2 模型、结构化违规报告、独立可行性验证器、三种确定性基线和预算局部搜索。v2 输入/输出有版本化 JSON Schema；同一输入可交给固定版本 OR-Tools CP-SAT 独立对照，再把解送回 MoonBit 验证。仓库提交了三个可运行教学场景、PSPLIB J30/J60 的无损转换工具、固定公开实例选择、120 行原始实验结果及图表。旧恢复 API、单资源容量 1 的排程 API 和 Web v1 保持兼容。参见[实施进度](docs/IMPLEMENTATION_PROGRESS.md)与[已知限制](docs/rcpsp-mathematical-model.md)。

## 产品边界

- 记录业务服务、技术组件和依赖关系。
- 维护 RTO、RPO、影响等级等业务影响分析指标。
- 对故障场景做确定性的影响分析，并生成恢复顺序。
- 管理恢复预案、人工审批点和演练时间线。
- 导出包含输入、计算结果和演练证据的报告。

平台只负责分析、规划和演练记录。它不会直接操作生产系统、自动切换灾备，也不保存生产凭据。

## 调度约束范围

| 约束或能力 | v2 状态 |
| --- | --- |
| 单模式、固定整数工期、非抢占任务与 DAG 依赖 | 支持；零时长仅供无需求虚拟里程碑 |
| 多类可再生资源、正整数容量与任务同时占用 | 支持；区间为 `[start, finish)` |
| 最早开工、可选硬截止、可选总体目标 Makespan | 支持；整数溢出与非法输入拒绝 |
| 独立排程验证、结构化违规、`FEASIBLE`/`UNKNOWN` | 支持；无解/最优证明由独立求解器或官方基准提供 |
| 多执行模式、抢占、不可再生资源、动态容量、人员日历和随机工期 | 当前不支持 |

[完整数学模型与算法边界](docs/rcpsp-mathematical-model.md)说明求解器超出拓扑排序的职责、下界的含义和适用条件。

## 目录约定

主要目录：

```text
ContinuityForge/
├── core.mbt    # MoonBit 核心包入口与集成探针
├── model.mbt   # 服务、组件和依赖领域模型
├── dependency.mbt # 拓扑排序与循环依赖校验
├── bia.mbt     # RTO、RPO、最大中断时间与影响等级
├── impact.mbt  # 故障影响传播与稳定路径
├── recovery.mbt # 依赖约束、影响等级和资源窗口下的恢复排序
├── scheduling/ # 旧单资源 API 与 v2 多资源 RCPSP 库、独立验证器
├── adapters/   # 故障恢复与 CI 流水线到通用调度问题的映射
├── benchmark/  # 合成实验、PSPLIB 转换、CP-SAT 参照与原始实验产物
├── cmd/rcpsp/ # v2 JSON 到 MoonBit JavaScript 的命令边界
├── playbook.mbt # 恢复步骤、前置条件与人工审批状态机
├── drill.mbt    # 演练状态与有序审计时间线
├── api.mbt      # 统一暴露经过校验的领域操作
├── storage.mbt  # 项目与审计记录的持久化快照
├── auth.mbt     # 本地用户、角色与权限校验
├── web/
│   ├── index.html # 库存、BIA、故障、恢复与演练工作区页面
│   ├── styles.css # 工作区视觉样式
│   ├── app.js     # 本地交互、MoonBit 引擎调用、证据导出与浏览器存储
│   ├── engine/    # 浏览器用 MoonBit JSON 边界
│   └── engine.mjs # 编译并发布的 MoonBit ESM
├── server/     # API、权限、持久化和输入校验
├── docs/
│   ├── operations.md # 安装、运行、操作和发布检查
│   └── recovery-scheduling.md # 恢复窗口算法、下界与案例
├── examples/
│   ├── minimal/      # 可运行的领域闭环示例与脱敏输入
│   ├── recovery_window/ # 资源独占、并行和恢复窗口案例
│   ├── ci_pipeline/ # 旧版三个 Runner 排程
│   └── rcpsp/ # v2 CI、故障恢复、项目及各自失败案例
└── integration/ # 跨语言构建与集成验证
```

旧模型及 Web v1 的原有使用方式见 [docs/scheduling-interface.md](docs/scheduling-interface.md)、[docs/scenario-adapters.md](docs/scenario-adapters.md)。v2 模型见[数学定义](docs/rcpsp-mathematical-model.md)，版本化导入导出与迁移见[交换格式](docs/rcpsp-exchange.md)。现有故障恢复与 CI 适配器继续复用旧通用调度核心；v2 场景通过同一个新 `RcpspProblem` 接口运行。

## 开发原则

1. 每次提交对应一个可复核的功能增量。
2. 核心计算保持无副作用、可重复，并优先用测试固定行为。
3. 真实生产操作由宿主系统负责，平台只生成计划和记录结果。
4. 配置、示例和提交历史中不得出现密码、令牌或其他敏感凭据。

每次功能提交都应保持范围清晰，并在提交信息中说明对应的验收结果。

## 快速开始

### 安装环境

安装 MoonBit 工具链（CI 固定编译器 0.10.14+7d59c7ec9）、Node.js 22 或更新版本；独立 CP-SAT 对照还需要 Python 3.9 或更新版本及 `benchmark/reference/requirements.txt` 中固定的 OR-Tools 版本。预览 Web 工作区可用 Python 3 的静态服务器。确认核心工具链：

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

### 运行资源受限调度最小示例

此 v2 示例只依赖 MoonBit 和 Node.js；构建后，默认按 JSON 中的 `solve_options` 运行：

```text
moon build cmd/rcpsp --target js --release --deny-warn
node integration/js/rcpsp-cli.mjs examples/rcpsp/ci.json
node examples/rcpsp/check.mjs
```

CI 输入包含两个 Runner、容量 4 的内存以及同时需要 Runner/内存的两项编译。程序给出 `FEASIBLE`、11 分钟 Makespan、逐任务起止和有效下界；场景检查还确认把内存容量升到 5 会将工期缩到 10，并让独立验证器拒绝违反硬截止的旧排程。再运行 `examples/rcpsp/recovery.json` 与 `examples/rcpsp/project.json` 可得到 8 分钟与 11 天的可行计划。全部输入、失败例、验证与 RTO/RPO 边界见[三场景说明](examples/rcpsp/README.md)。

如需独立最优性参照，安装 Python 依赖后运行：

```text
python -m pip install -r benchmark/reference/requirements.txt
python benchmark/reference/ortools_rcpsp.py examples/rcpsp/ci.json
```

该 CI 教学输入的 CP-SAT 状态为 `OPTIMAL`、Makespan 11；MoonBit 验证器只证明排程可行，最优性证明来自 CP-SAT。[公开 PSPLIB 下载/转换步骤](benchmark/psplib/README.md)、[五算法实验复现](benchmark/rcpsp/README.md)和[原始结果](benchmark/rcpsp/results/raw.csv)可用于独立核对。

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

打开 `http://127.0.0.1:8765/`，依次使用 Inventory、Business impact、Incident impact、Recovery plans、Scheduling lab 和 Drill log；最后点击 **Export evidence** 下载证据 JSON。故障传播、依赖校验及恢复排程由随仓库发布的 MoonBit JavaScript 引擎计算；输入非法时页面显示引擎错误。Scheduling lab 支持两个预置场景、版本化 JSON 导入、依赖图、甘特图、算法对比和 JSON/CSV 导出，操作方式见 [docs/scheduling-workspace.md](docs/scheduling-workspace.md)。完整工作区说明见 [docs/operations.md](docs/operations.md)。

### 验证资源受限恢复窗口

运行 `moon run examples/recovery_window`，查看依赖完成时间、独占资源排队和不同团队并行产生的逐项起止时间。示例中任务时长合计 70 分钟，实际排程窗口为 45 分钟；最长依赖路径下界为 30 分钟，单资源负载下界为 35 分钟。计算公式、拒绝条件和算法边界见 [docs/recovery-scheduling.md](docs/recovery-scheduling.md)。Web 工作区现在也调用 MoonBit 排程核心，恢复时长仍来自 BIA 的演示估算输入。

### 验证 CI 流水线调度

运行 `moon run examples/ci_pipeline`。这是明确标注的合成案例：七个编译、检查、测试和打包阶段分配到三个独占 Runner；阶段间有前置依赖，互不阻塞的阶段可以并行。程序打印各阶段输入、三种基线与优化结果的完工时间、逐项起止时间、负载最高的 Runner、下界及 40 分钟目标是否达到。案例由 [流水线适配器](docs/scenario-adapters.md)调用与故障恢复相同的通用调度核心，时长不代表真实生产流水线。

### 复现旧容量 1 的合成算法对比

旧容量 1 模型仍可运行：`moon test benchmark/runner` 验证固定种子实例和指标边界；再按 [benchmark/README.md](benchmark/README.md) 的命令生成逐次 CSV/JSON、汇总 CSV、消融数据与两张 SVG 图表。覆盖 12–20、50–100、200 个任务的 Small、Medium、Large 案例，并额外用 6 个任务的实例验证已证明最优解的差距。数据均为合成输入，执行时间是本机测量值。v2 的 PSPLIB 公开数据实验见[新实验报告](docs/rcpsp-experiment-report.md)。

实验结果和无收益机制见 [基准与消融报告](docs/benchmark-report.md)。[算法设计](docs/algorithm-design.md)说明数学模型、恢复窗口和局部搜索的实际职责；[公开需求证据](docs/requirements-evidence.md)区分问题背景与尚缺的真实用户验证。[架构设计](docs/architecture.md)与 [English overview](docs/overview.en.md)概述跨场景调用和兼容边界。

## 本地验证

需要安装 MoonBit 工具链和 Node.js。仓库根目录可运行：

```text
moon fmt
moon check --deny-warn
moon build --target js --deny-warn
node integration/js/smoke.mjs
moon build cmd/rcpsp --target js --release --deny-warn
node examples/rcpsp/check.mjs
```

`integration/js/smoke.mjs` 检查原有 JavaScript 目标探针；`examples/rcpsp/check.mjs` 复核三个 v2 场景的可行排程和失败输入。

web/ 是独立的静态工作区，可交给任意静态服务器预览；库存、BIA 和演练事件会保存到当前浏览器，Export evidence 会下载当前工作区的证据 JSON。

## 发布检查

发布前运行以下检查，确保 MoonBit 核心、JavaScript 集成和静态工作区都可复核。Python 对照命令需先安装上文固定的 OR-Tools 依赖：

GitHub Actions 中的 `ContinuityForge CI` 会在 `main` 的推送和 Pull Request 上自动运行同一组门禁。

```text
moon fmt
moon check --target all --deny-warn
moon test --target all
moon build --target all --deny-warn
moon run examples/minimal
moon run examples/recovery_window
moon run examples/ci_pipeline
moon build cmd/rcpsp --target js --release --deny-warn
node examples/rcpsp/check.mjs
node --check benchmark/rcpsp/run.mjs
python benchmark/reference/check_scenarios.py
node integration/js/smoke.mjs
node --check web/app.js
git diff --check
```

## 许可证

本项目以 Apache License 2.0 发布，详见 [LICENSE](LICENSE)。可选的 OR-Tools 9.15.6755 对照工具自身亦为 Apache-2.0，版本固定在 `benchmark/reference/requirements.txt`；PSPLIB 官方允许下载用于算法评价，但未明确授权重分发原始数据，所以仓库不提交其 ZIP、`.sm` 文件或完整镜像，只提交转换器、来源与摘要。数据、算法和证据边界见[第三方与数据核查](docs/third-party-and-data.md)、[PSPLIB 说明](benchmark/psplib/README.md)及[CP-SAT 对照说明](docs/ortools-reference.md)。
