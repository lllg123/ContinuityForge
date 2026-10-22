# 架构设计与调用路径

```text
浏览器静态页面 ──JSON──▶ web/engine.mbt ──▶ 原领域包 / scheduling
CLI 领域示例 ───────────────────────────────▶ 原领域包
恢复/CI 示例 ──▶ adapters/recovery|pipeline ──▶ scheduling
固定种子基准 ──▶ benchmark/runner ─────────▶ scheduling
```

原领域包位于仓库根目录，承载服务库存、依赖、BIA、影响传播、恢复预案、演练、审计、存储和权限。`scheduling/` 只认识任务、前置关系、资源、目标窗口和候选排程；它不导入企业类型。两个适配器负责把领域输入转换成统一问题，再将工期、目标达成情况和解释返回场景。这样可以用同一约束校验器检查恢复和 CI 两类计划。

Web 工作区在浏览器本地保存库存与演练输入，使用已提交的 `web/engine.mjs` 调用 MoonBit；`web/engine` 是 JSON 边界，`integration/js` 检查编译产物与浏览器入口的契约。`web/scenarios/schema.v1.json` 约束调度实验室的导入数据。静态页面没有服务端持久化和生产执行权限；`server/` 当前仍是后续服务端边界。

原有 `plan_recovery` 保持兼容。新的 `analyze_recovery` 和 `analyze_pipeline` 是显式适配入口，不会悄悄修改旧输入含义。浏览器的旧库存/BIA 数据也不自动转换为调度 JSON；详见[算法设计与迁移](algorithm-design.md)和[工作区操作](scheduling-workspace.md)。实验数据与可复现命令见[基准报告](benchmark-report.md)。
