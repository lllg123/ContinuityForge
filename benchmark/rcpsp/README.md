# v2 RCPSP 系统实验

实验脚本 `run.mjs` 对同一份规范化 JSON 分别运行 MoonBit 的 Stable Topological、Critical Path、Recovery Heuristic、Budgeted Local Search，以及固定版本 OR-Tools CP-SAT。每个标为 `FEASIBLE` 或 `OPTIMAL` 的候选都经 `validate_json` 调用 MoonBit 独立可行性验证器；失败会写入原始行并导致脚本以非零状态结束。三个人工教学场景始终纳入，指定 `--public-dir` 后再加入 `selection.json` 固定的五个 PSPLIB 案例，不筛掉表现差的实例。

先按 [PSPLIB 下载与转换说明](../psplib/README.md)准备官方数据，再在仓库根目录运行：

```text
moon build cmd/rcpsp --target js --release --deny-warn
python -m pip install -r benchmark/reference/requirements.txt
python benchmark/psplib/prepare.py --cache CACHE --output PUBLIC_OUTPUT
node benchmark/rcpsp/run.mjs --public-dir PUBLIC_OUTPUT --python python --repeats 3 --time-limit 5 --budget 30
```

若使用虚拟环境，把 `--python` 后的命令换成其 Python 可执行文件。默认产物在 `benchmark/rcpsp/results/`：

- `raw.json`：每一次求解的完整解、状态、验证结论与环境元数据。
- `raw.csv`：同样的标量指标，便于筛选、重算。
- `summary.csv`：按实例和算法汇总可行率、平均工期、平均耗时、资源利用率与有证明时的差距。
- `ablation.csv`：相同输入上的预算搜索 0 次与 30 次邻域评估对照。
- `makespan.svg`、`runtime.svg`：工期与耗时图。工期图逐案例独立缩放，数值标签保留原案例单位，不能跨分钟、天和 PSPLIB 时间单位比较长度。

`optimality_gap_pct = (候选工期 − 已证明最优值) / 已证明最优值 × 100%`，仅在官方证明或 CP-SAT `OPTIMAL` 时填写。`bound_gap_pct` 以官方有效下界和 CP-SAT 有效下界的较大值作分母，是界限差距，**不是**最优性差距。`reference_feasible_gap_pct` 与 CP-SAT 当前可行工期比较，不能当作最优性差距。`official_upper_bound_gap_pct` 与官方已知可行上界比较，该上界不一定最优。资源利用率是全部任务的 `duration × 需求量` 总和除以 `Makespan × 全部资源容量总和`，未使用资源仍计入分母。

本次固定 3 次重复；MoonBit 算法与实例均确定性，重复用于观察时间测量与结果稳定性。CP-SAT 固定单线程与随机种子，但 5 秒墙钟上限仍可能造成不同机器或负载下的状态变化。MoonBit 的 `elapsed_ms` 包含求解与候选验证，不含 JSON 文件 I/O；CP-SAT 的 `elapsed_ms` 为其内部 wall time，不含 Python 启动与外部 MoonBit 验证，耗时只用于同机粗略比较。MoonBit 毫秒计时可能为 0，不能理解为无执行开销。邻域预算 30 次与 CP-SAT 的 5 秒并非相同计算预算。三种排序无随机性，不做虚假的随机种子平均。

详细结果、改进受限和未证明实例见[实验报告](../../docs/rcpsp-experiment-report.md)。
