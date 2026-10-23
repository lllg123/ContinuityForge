# RCPSP v2 交换格式与 API

问题 JSON 由 [`rcpsp-problem-v2.schema.json`](schema/rcpsp-problem-v2.schema.json) 描述，解由 [`rcpsp-solution-v2.schema.json`](schema/rcpsp-solution-v2.schema.json) 描述。`schema_version` 分别为 `continuityforge.rcpsp.v2` 和 `continuityforge.rcpsp.solution.v2`。`time_unit` 由调用方给定，同一问题内的时长、释放时间、截止时间与目标必须使用同一整数单位。未设置的 `deadline`、`target_makespan`、`makespan`、`lower_bound` 和 `diagnostic` **省略字段**，而不是写入 `null`。任务的 `demands` 数组同时保留所有正需求，空数组代表无需可再生资源。可选 `solve_options` 明确算法名、MoonBit 邻域搜索次数 `search_budget` 和独立求解器墙钟限制 `time_limit_ms`；缺省导入请求时分别采用预算搜索、30 次、5000 毫秒。求解参数不改变物理约束。

MoonBit 包 `scheduling` 提供 `import_rcpsp_problem`、`export_rcpsp_problem`、`import_rcpsp_request`、`export_rcpsp_request`、`solve_rcpsp_request`、`solve_rcpsp`、`optimize_rcpsp`、`analyze_rcpsp_result`、`inspect_rcpsp_problem`、`inspect_rcpsp_schedule`、`import_rcpsp_solution` 和 `export_rcpsp_solution`。导入问题时调用结构验证器，导入外部可行解时调用独立排程验证器并核对 Makespan。`analyze_rcpsp_result` 重新核验排程，计算带释放时间的前置路径下界、界限差距、平均资源利用率与最高利用率资源。MoonBit 启发式输出的 `lower_bound` 是这一有效但可能很弱的下界，`makespan` 是已找到可行解的上界。`OPTIMAL` 状态可以通过可行性导入，但最优性本身须由可信求解器或公开基准的证明支持；MoonBit 验证器不证明它。

旧 `SchedulingProblem` 与 Web v1 继续使用原先的单资源容量 1 语义；`upgrade_exclusive_problem` 将其显式转换。v2 不会暗中改变旧 API 的输出。

在仓库根目录运行：

```text
moon build cmd/rcpsp --target js --release --deny-warn
node integration/js/rcpsp-cli.mjs examples/rcpsp/ci.json
node integration/js/rcpsp-cli.mjs examples/rcpsp/recovery.json critical-path 0
node integration/js/rcpsp-validate.mjs examples/rcpsp/ci.json benchmark/reference/ci-reference.json
```

可选算法名为 `stable-topological`、`critical-path`、`recovery-heuristic`、`budgeted-local-search`。默认 `from-input` 使用文件内 `solve_options`；显式算法和最后的预算参数可以覆盖这一选择。命令行输出单个 JSON 对象，输入或排程错误时返回 `error` 或 `ok:false` 并设置非零退出码。`FEASIBLE` 表示验证器已确认约束满足；`UNKNOWN` 表示启发式未找到可行解，不能据此断言无解。
