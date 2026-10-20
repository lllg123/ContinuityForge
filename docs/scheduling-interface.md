# 通用任务与排程接口（当前阶段）

`lllg123/continuity_forge/scheduling` 是独立 MoonBit 包，不导入企业服务、BIA、RTO、RPO 或演练类型。它接受任务、前置关系和独占资源，并校验外部算法给出的候选排程。现有 `plan_recovery` 仍使用旧领域算法；本接口尚不生成排程，也不声称优化能力。

## 问题定义

每个 `Task` 有唯一 `id`、正整数 `duration`、`priority` 和一个 `resource_id`。`Dependency(task_id, prerequisite_id)` 表示前者须等待后者完成。`Constraints` 给出可用资源及可选的 `target_makespan`。时间从 0 开始，所有时长和目标必须使用**同一个由调用者约定的单位**；恢复场景可用分钟，CI 流水线可用秒。当前资源容量均为 1，任务不能中断；不同资源可以并行。`priority` 作为场景无关的输入保留，当前可行性检查不以它改变约束。

对任务 `i`，开始和结束时间分别为 `sᵢ`、`fᵢ`，时长为 `dᵢ`。合法排程满足 `sᵢ ≥ 0`、`fᵢ = sᵢ + dᵢ`；每条依赖 `j → i` 满足 `sᵢ ≥ fⱼ`；共享资源的任意两任务执行区间 `[s,f)` 不相交。`makespan = max(fᵢ)`，空任务集为 0。可选目标要求 `makespan ≤ target_makespan`。后续算法的首要目标是最小化 makespan；目前的接口只**计算并校验**候选值，不求最优值。

## 调用边界

- `SchedulingProblem::new` 与 `validate_problem` 拒绝空 ID、非正时长、重复任务/资源/边、缺失任务或资源、自依赖和依赖环。公开记录含可变数组，因此 `validate_schedule` 每次都会重新检查问题。
- `validate_schedule` 要求每项任务恰好出现一次，并检查资源、时长、前置、资源冲突与目标窗口。它独立于候选方案的生成方法，可作为后续各基线与优化算法的统一正确性门槛。
- `evaluate_schedule` 在校验通过后返回 `AnalysisResult`（排程、实际 makespan、算法来源及约束说明）。`algorithm` 仅是来源标签，不会触发对应算法。

`scheduling/interfaces_test.mbt` 用同一组接口验证恢复任务（数据库与计算团队，45 单位）和 CI 流水线任务（两个 runner，13 单位）。这些是确定性测试数据，不是生产部署或性能实验。候选排程由测试显式给出；三种基线、改进算法、精确解参照、领域适配器和 Web 调用将在后续提交实现。
