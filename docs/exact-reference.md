# 小规模精确参照与正确性门槛

`exact_reference(problem, node_budget)` 对最多 8 个任务枚举全部满足前置关系的活动列表，用与三种基线相同的最早可行资源空档规则解码。活动列表的串行排程涵盖最优主动排程；其依据见 Hartmann 的[RCPSP 启发式分类与分析](https://www.hsba.de/fileadmin/user_upload/bereiche/_dokumente/6-forschung/profs-publikationen/Hartmann_1999_Heuristic_Algorithms_for_solving_the_resource-constrained_project_scheduling_problem.pdf)。在本项目的单任务单独占资源、整数时长、非抢占模型下，搜索完整结束时返回的最小 makespan 可作为该模型的最优值。

`node_budget` 计数递归搜索节点，包含部分顺序；预算耗尽时 `proven_optimal=false`，`best` 可能只有当前最好候选，也可能是 `None`。超过 8 个任务或非正预算会被拒绝。可选目标窗口在精确搜索时暂时移除，以便仍能给出无窗口约束的最优 makespan；若它超过原目标，则可证明目标不可能满足。只在 `proven_optimal=true` 时允许调用 `optimality_gap_percent`；调用者须保证候选和参照来自同一问题。空问题的最优值为 0，差距定义为 0%。

## 已验证案例

`scheduling/exact_reference_test.mbt` 完整搜索了四任务局部顺序陷阱：最优 makespan 为 **12**，三个基线均为 **19**，其相对最优性差距为 `(19−12)/12×100% ≈ 58.33%`；第 5 个提交的局部搜索找到 12，差距为 0%。这只证明该合成小案例，不代表总体平均改进率。

`scheduling/correctness_test.mbt` 进一步核对链式任务、不同资源并行、同资源串行、目标不可达、可变输入重新校验及重复排程项。缺失资源、重复任务、环、无效时长、整数溢出和空任务也由调度包其他测试覆盖。所有基线与改进算法的候选都经 `evaluate_schedule` 的独立可行性校验。

此枚举的最坏搜索量随任务数阶乘增长，8 任务上限是刻意设置的实验边界；中大规模最优解、外部求解器交叉验证和系统性性能实验尚未完成。
