# v2 资源受限排程启发式

`solve_rcpsp(problem, algorithm)` 提供 Stable Topological、Critical Path、Recovery Heuristic。第一种按输入稳定拓扑顺序选择就绪任务；第二种优先选择剩余最长依赖路径；第三种先比较调用方给定的领域无关整数 `priority`，再比较剩余路径长度，输入序号作稳定平局规则。`optimize_rcpsp(problem, budget)` 先比较三种基线，再尝试前置关系允许的相邻任务交换，只接受严格缩短 Makespan 且经独立验证的候选。预算限制邻域候选评估次数，三种基线的评估另计；结果中的 `candidates_evaluated` 包含二者，`accepted_moves` 记录实际改进。

所有排序调用同一个串行日程生成器。每项任务的最早起点是其释放时刻与全部前置任务完成时刻的最大值。资源占用为 `[start, finish)`，并行任务在执行期间同时占用其每项正需求。生成器只检查最早起点和已排任务的完成时刻作为候选起点；对每个候选，检查其开始时刻及已排任务落在区间内的开始事件，验证每项资源容量。因为现有任务的占用只在完成事件下降，可行性的最早起点若晚于最早时刻，必位于一个完成事件。整个排程完成后仍调用 `inspect_rcpsp_schedule` 独立核验时间窗、目标和所有资源约束。

四种算法都是确定性启发式，结果仅报告 `FEASIBLE` 或 `UNKNOWN`，不提供最优性或不可行性证明。结果的 `lower_bound` 由释放时间和最长前置路径计算，忽略资源容量，因此可能很弱。`elapsed_ms` 是运行机器上的墙钟毫秒数，不能与不同机器的性能直接对比。旧 `run_baseline`、`optimize_schedule` 和 Web v1 继续使用容量 1 的旧模型；新求解行为不隐式替换旧结果。
