# RCPSP v2 数学模型与算法边界

设任务集合为 $J$，可再生资源集合为 $K$。任务 $i$ 固定整数工期 $d_i$、最早开工 $r_i$、可选硬完工截止 $D_i$，对资源 $k$ 的恒定需求为 $q_{ik}$，容量为正整数 $C_k$。变量 $s_i$ 是整数开工时间，$f_i=s_i+d_i$。任务非抢占，整个执行区间 $[s_i,f_i)$ 同时占用所有正需求资源。零工期只允许无需求的虚拟里程碑。全部时间均非负、使用同一由输入指定的单位，并受 MoonBit 32 位 `Int` 的安全加法范围约束。

可行排程必须满足：

$$
s_i\ge r_i,\qquad f_i\le D_i\quad(\text{有截止时}),\qquad
s_j\ge f_i\quad(i\to j).
$$

$$
\sum_{i:\,s_i\le t<f_i}q_{ik}\le C_k
\quad\text{对每个资源 }k\text{ 和每个整数时刻 }t。
$$

令 $M=\max_i f_i$。若输入有 `target_makespan=T`，还须 $M\le T$；优化目标统一为最小化 $M$。任务依赖是有向无环图，但拓扑顺序本身没有 $s_i$、$q_{ik}$、$C_k$ 或 $D_i$，不能判定资源受限恢复窗口。旧容量 1、单资源模型通过 `upgrade_exclusive_problem` 显式映射到此子集。

MoonBit 的稳定拓扑、关键路径和恢复优先级规则先形成前置可行的任务序列。统一日程生成器再从 $\max(r_i,\max_{p\in pred(i)}f_p)$ 起，检查该时刻及已排任务的完成事件，找到所有资源**同时**可用的最早候选起点。容量占用只在任务完成事件下降，因此更晚的最早可行起点必位于某个完成事件。生成完整候选后，独立验证器重新检查任务集合、前置、时间窗、容量和总体目标。预算局部搜索只交换不破坏前置关系的相邻任务，只接受严格缩短工期且通过验证的候选。四种算法均是启发式，不声称最优性。

公开 API 的 `rcpsp_lower_bound` 计算忽略资源的、含释放时间的最长前置路径：按拓扑序计算 $e_i=d_i+\max(r_i,\max_{p\in pred(i)}e_p)$，返回 $\max_i e_i$。这是有效下界，但资源越紧时往往越弱。结果分析的 `gap_to_bound_percent` 是相对于该下界的界限差距；只有官方证明或 CP-SAT `OPTIMAL` 才可报告精确最优性差距。CP-SAT 的每任务 interval、资源 cumulative 和 makespan 目标与上式一致，独立读取同一规范化 JSON，并输出 `OPTIMAL`、`FEASIBLE`、`INFEASIBLE` 或 `UNKNOWN`。MoonBit 启发式的 `UNKNOWN` 仅表示给定搜索内未找到解。

当前不支持多执行模式、抢占、不可再生资源、随时间变化容量、人员日历、概率时长或任务收益最大化。任务 `priority` 只影响排序，不改变可行性或目标函数。计划窗口也不是实际故障的 RTO/RPO 证明。整数输入验证和独立候选校验详见[验证器说明](rcpsp-v2-validation.md)，数据及最优界解释详见[实验报告](rcpsp-experiment-report.md)。
