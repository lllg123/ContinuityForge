# 三个完整的 RCPSP v2 场景

这三个输入是仓库内完整给出的**人工教学数据**，并非生产 CI、故障记录或真实项目。任务时长、资源量和时间窗均为示范假设，可由 [`rcpsp-problem-v2.schema.json`](../../docs/schema/rcpsp-problem-v2.schema.json) 检查结构，再由 MoonBit `import_rcpsp_problem` 检查语义。每个文件中的 `solve_options` 给出算法、邻域预算及对照求解器时间限制。先在仓库根目录构建，然后运行：

```text
moon build cmd/rcpsp --target js --release --deny-warn
node examples/rcpsp/check.mjs
node integration/js/rcpsp-cli.mjs examples/rcpsp/ci.json
node integration/js/rcpsp-cli.mjs examples/rcpsp/recovery.json
node integration/js/rcpsp-cli.mjs examples/rcpsp/project.json
```

`check.mjs` 对每个成功方案调用独立验证器；将同一方案按失败输入重新检查时必须被拒绝。输出预期为三个 `FEASIBLE` 结果：CI 11 分钟、恢复 8 分钟、通用项目 11 天。成功输入的 CP-SAT 5 秒对照均给出 `OPTIMAL`，结果分别同为 11、8、11；原始结果见 `benchmark/reference/*-reference.json`。

## A. CI/CD 资源调度

[`ci.json`](ci.json) 包含 checkout、两项编译、测试、打包、签名及完整前置边。Runner 容量 2、内存容量 4、签名器容量 1；`compile-a` 和 `compile-b` 同时需要 Runner 与内存。`compile-b` 最早在第 2 分钟启动，签名硬截止第 12 分钟。虽然两个 Runner 可并行运行编译，内存需求 2+3 超出容量 4，因此最优 Makespan 为 11。只把内存容量提高到 5 且不动依赖时，CP-SAT 和 MoonBit 均得到 10，展示了资源瓶颈对窗口的影响。`package` 也必须等 `compile-b` 与 `test-a` 都完成，证明资源与前置约束同时作用。

[`ci-deadline-fail.json`](ci-deadline-fail.json) 只把签名硬截止提前到第 10 分钟并移除总体目标；MoonBit 返回 `UNKNOWN`，CP-SAT 返回 `INFEASIBLE`。原 11 分钟的可行排程导入这个输入时，验证器给出 `task misses hard deadline`。

## B. 系统故障恢复

[`recovery.json`](recovery.json) 包含隔离、数据库恢复、缓存恢复、API 验证、冒烟测试。数据库小组容量 1、计算容量 2、网络容量 1；数据库与缓存可共用两份计算资源并行恢复，计划在第 8 分钟完成。`target_makespan=8` 和最后任务 `deadline=8` 是**此教学案例的计划窗口**，不能代替经业务批准、从真实故障起点定义的 RTO；数据丢失窗口 RPO 不在 RCPSP 时间模型中，不能从此排程推导。

[`recovery-capacity-fail.json`](recovery-capacity-fail.json) 只把计算容量减到 1，保留 8 分钟目标和截止。MoonBit 返回 `UNKNOWN`，CP-SAT 证明 `INFEASIBLE`；如同时移除目标和硬截止，最短完成时间变为 10。原 8 分钟排程在新容量下被验证器以 `renewable resource capacity exceeded` 拒绝。

## C. 通用项目调度

[`project.json`](project.json) 是完整可复现的合成任务集：设计、采购、原型、文档、验证、发布。工程师容量 2，实验室容量 1，采购最早在第 1 天启动，发布硬截止第 12 天。原型同时占用两名工程师与实验室；验证需等原型和采购。最优完成时间为第 11 天，CP-SAT 给出证明。该合成案例独立于 CI 和故障恢复的领域词汇；公开 PSPLIB 案例另见[基准目录](../../benchmark/psplib/README.md)。

[`project-deadline-fail.json`](project-deadline-fail.json) 只把发布硬截止提前至第 10 天。MoonBit 返回 `UNKNOWN`，CP-SAT 返回 `INFEASIBLE`；原第 11 天方案被验证器以 `task misses hard deadline` 拒绝。

验证 CP-SAT 的失败状态可运行（将文件名换成上面另两个失败输入）：

```text
python benchmark/reference/ortools_rcpsp.py examples/rcpsp/ci-deadline-fail.json
```

启发式 `UNKNOWN` 只表示没找到可行排程；无解结论来自 CP-SAT 的 `INFEASIBLE` 证明。此处均为单模式、固定时长、非抢占式、可再生资源的计划模拟，未建模任务时长不确定性、真实人员日历或生产系统控制。
