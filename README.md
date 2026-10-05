# ContinuityForge

ContinuityForge 是一个面向组织内部的系统韧性与业务连续性平台。它帮助团队登记关键业务和技术依赖，完成业务影响分析（BIA），模拟故障影响，生成恢复顺序，记录演练过程，并导出可追溯报告。

项目地址：<https://github.com/lllg123/ContinuityForge>

## 当前阶段

当前仓库已建立 MoonBit 模块、JavaScript 目标验证入口、经过统一 API façade 校验的依赖图、业务影响分析（BIA）、故障影响传播、约束下恢复排序、恢复预案、演练审计时间线、项目与审计记录存储、本地用户权限，以及包含故障影响、恢复排序和演练时间线可视化的 Web 工作区。服务端接口和更完整的 Web 流程会在后续独立提交中逐步加入。

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
│   └── app.js     # 本地交互、模拟计算与浏览器存储
├── server/     # API、权限、持久化和输入校验
├── docs/       # 架构、运行和操作文档
├── examples/   # 脱敏的演示数据
└── integration/ # 跨语言构建与集成验证
```

目录会在对应功能提交中创建；当前 web 已提供静态工作区，server、docs 和 examples 仍按功能提交逐步加入。

## 开发原则

1. 每次提交对应一个可复核的功能增量。
2. 核心计算保持无副作用、可重复，并优先用测试固定行为。
3. 真实生产操作由宿主系统负责，平台只生成计划和记录结果。
4. 配置、示例和提交历史中不得出现密码、令牌或其他敏感凭据。

每次功能提交都应保持范围清晰，并在提交信息中说明对应的验收结果。

## 本地验证

需要安装 MoonBit 工具链和 Node.js。仓库根目录可运行：

```text
moon fmt
moon check --deny-warn
moon build --target js --deny-warn
node integration/js/smoke.mjs
```

最后一条命令会启动 MoonBit 的 JavaScript 目标探针，并检查核心包返回的稳定标记。

web/ 是独立的静态工作区，可交给任意静态服务器预览；库存、BIA 和演练事件会保存到当前浏览器。

## 许可证

本项目以 Apache License 2.0 发布，详见 [LICENSE](LICENSE)。
