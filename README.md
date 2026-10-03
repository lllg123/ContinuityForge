# ContinuityForge

ContinuityForge 是一个面向组织内部的系统韧性与业务连续性平台。它帮助团队登记关键业务和技术依赖，完成业务影响分析（BIA），模拟故障影响，生成恢复顺序，记录演练过程，并导出可追溯报告。

项目地址：<https://github.com/lllg123/ContinuityForge>

## 当前阶段

当前仓库已建立 MoonBit 模块、JavaScript 目标验证入口、依赖图校验、业务影响分析（BIA）模型和故障影响传播模拟。服务端和 Web 界面会在后续独立提交中逐步加入。

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
├── server/     # API、权限、持久化和输入校验
├── web/        # Web 界面
├── docs/       # 架构、运行和操作文档
├── examples/   # 脱敏的演示数据
└── integration/ # 跨语言构建与集成验证
```

目录会在对应功能提交中创建，当前阶段只保留仓库级文档。

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

## 许可证

本项目以 Apache License 2.0 发布，详见 [LICENSE](LICENSE)。
