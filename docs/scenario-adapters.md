# 故障恢复与 CI 流水线适配器

两个适配器都把场景数据映射到 `lllg123/continuity_forge/scheduling` 的 `SchedulingProblem`，调用同一个 `optimize_schedule`、三种基线和独立 `validate_schedule`。它们没有各自实现调度算法。代码分别位于 `adapters/recovery/` 与 `adapters/pipeline/`；通用核心不导入这两个包，也不依赖任何企业领域类型。

## 故障恢复

`analyze_recovery` 接受故障资产、完整资产与依赖图、恢复任务、资源与目标窗口、搜索预算。它先调用原有 MoonBit 故障传播，保留受影响资产及路径；随后把 `ServiceId`/`ComponentId` 转为带前缀的稳定任务 ID，把 `TimeSpan` 安全换算成分钟，把 Low/Medium/High/Critical 映射为 0/1/2/3。依赖边的两个端点都必须有对应恢复任务；与恢复排程无关的资产可只留在影响图中。

返回 `RecoveryAnalysis`：故障影响、实际通用问题、优化报告、目标分钟数、目标是否达到和简短说明。即使启发式排程没有满足目标，也返回实际排程和 `target_met=false`；不能把“本次未达标”自动解读成全局不可行。原有 `plan_recovery` 与 `examples/recovery_window` 保持兼容；本提交不改变旧 API 的排序语义。

## CI 流水线

`analyze_pipeline` 接受阶段 ID、整数时长、Runner、优先级和前置阶段，以及 Runner 列表、可选目标和预算。阶段可以代表编译、静态检查或测试，单位由调用者统一约定。返回同一问题上的三种基线与优化结果、负载最高的 Runner 及其总时长、目标是否达到。最大 Runner 负载是瓶颈下界，不等于全部前置约束下的最优工期。

`adapters/recovery/adapter_test.mbt` 与 `adapters/pipeline/adapter_test.mbt` 使用明确的合成输入，分别检查故障路径、旧 API 兼容、Runner 并行、排程可行性、目标和资源错误。它们证明代码复用了同一 MoonBit 调度包；这些测试不是实际企业部署或公开 CI 数据。可运行的独立 CI 流水线示例、真实需求证据、批量 benchmark 与 Web 集成仍属于后续阶段。
