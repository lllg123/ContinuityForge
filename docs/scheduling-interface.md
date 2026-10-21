# 通用任务与排程接口（当前阶段）

`lllg123/continuity_forge/scheduling` 是独立 MoonBit 包，不导入企业服务、BIA、RTO、RPO 或演练类型。它接受任务、前置关系和独占资源，能运行三种确定性基线，并校验任何算法给出的候选排程。现有 `plan_recovery` 仍使用旧领域算法；新基线不声称最优或具有已验证的改进率。

## 问题定义

每个 `Task` 有唯一 `id`、正整数 `duration`、`priority` 和一个 `resource_id`。`Dependency(task_id, prerequisite_id)` 表示前者须等待后者完成。`Constraints` 给出可用资源及可选的 `target_makespan`。时间从 0 开始，所有时长和目标必须使用**同一个由调用者约定的单位**；恢复场景可用分钟，CI 流水线可用秒。当前资源容量均为 1，任务不能中断；不同资源可以并行。`priority` 作为场景无关的输入保留，当前可行性检查不以它改变约束。

对任务 `i`，开始和结束时间分别为 `sᵢ`、`fᵢ`，时长为 `dᵢ`。合法排程满足 `sᵢ ≥ 0`、`fᵢ = sᵢ + dᵢ`；每条依赖 `j → i` 满足 `sᵢ ≥ fⱼ`；共享资源的任意两任务执行区间 `[s,f)` 不相交。`makespan = max(fᵢ)`，空任务集为 0。可选目标要求 `makespan ≤ target_makespan`。后续算法的首要目标是最小化 makespan；基线仅构造并校验候选值，不求最优值。

## 调用边界

- `SchedulingProblem::new` 与 `validate_problem` 拒绝空 ID、非正时长、重复任务/资源/边、缺失任务或资源、自依赖和依赖环。公开记录含可变数组，因此 `validate_schedule` 每次都会重新检查问题。
- `validate_schedule` 要求每项任务恰好出现一次，并检查资源、时长、前置、资源冲突与目标窗口。它独立于候选方案的生成方法，可作为后续各基线与优化算法的统一正确性门槛。
- `evaluate_schedule` 在校验通过后返回 `AnalysisResult`（排程、实际 makespan、算法来源及约束说明）。`algorithm` 仅是来源标签，不会触发对应算法。
- `run_baseline(problem, baseline)` 根据明确的 `Baseline` 枚举生成排程，并调用上述独立校验。未设置 `target_makespan` 时可比较全部合法结果；设置目标后，超过目标的基线返回约束错误，不返回一个“合格”结果。

## 三种基线

三者使用相同的 `SchedulingProblem`、资源空档搜索和 `validate_schedule`。空档搜索从最晚前置完成时间开始，在该资源上找到能容纳整项任务的最早区间；较晚选中的任务仍可填入较早空档。

| 基线 | 就绪任务的选择规则 |
| --- | --- |
| `StableTopological` | 以输入顺序初始化就绪队列，按依赖边输入顺序加入新就绪任务，FIFO 取出 |
| `RecoveryHeuristic` | 最高下游优先级、最长下游剩余路径（不含自身）、自身优先级、较短时长、任务 ID 字典序 |
| `CriticalPath` | 最长剩余依赖路径（含自身）优先；平局按任务输入顺序 |

`RecoveryHeuristic` 复刻旧 `recovery.mbt` 的选择规则，但以通用整数 `Task.priority` 代替 `ImpactLevel`。故障恢复调用者可把 Low/Medium/High/Critical 映射为 0/1/2/3；映射本身尚未封装为领域适配器。三种方法均为列表排程启发式，不能保证最小 makespan。当前数组索引与资源空档扫描在高依赖密度下可能较慢；基准测试和优化实现仍需单独完成。

`scheduling/interfaces_test.mbt` 用同一接口验证恢复任务（数据库与计算团队，45 单位）和 CI 流水线任务（两个 runner，13 单位）。`scheduling/baselines_test.mbt` 在相同输入上运行全部三种基线，并固定优先级传播、关键路径选择、目标拒绝、空任务及整数溢出行为。这些是确定性测试数据，不是生产部署或性能实验。

有预算的改进搜索已在 `optimize_schedule` 实现；假设、搜索流程及单个合成反例见 [optimized-scheduling.md](optimized-scheduling.md)。小规模最优性参照与正确性边界见 [exact-reference.md](exact-reference.md)。故障恢复与 CI 流水线适配边界见 [scenario-adapters.md](scenario-adapters.md)。系统性基准实验和 Web 调用仍属后续提交。
