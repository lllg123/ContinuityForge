# 可复现调度基准

`benchmark/runner` 是独立的 MoonBit 可执行包，直接调用 `scheduling/` 的三种基线与预算搜索。输入全部由代码生成，**是合成数据，不代表真实 CI 或企业故障记录**。每个任务只使用一个容量为 1 的 Runner；依赖只指向更早编号的任务，因此生成的是 DAG。

## 实验设计

| 案例 | 任务 | Runner | 依赖抽样概率 | 热点 Runner 概率 | 时长分布 |
| --- | ---: | ---: | ---: | ---: | --- |
| micro（精确参照） | 6 | 3 | 20% | 50% | 离散均匀 5–10 |
| small-12 | 12 | 3 | 15% | 70% | 离散均匀 5–10 |
| small-20 | 20 | 5 | 8% | 0% | 离散均匀 1–30 |
| medium-50 | 50 | 5 | 4% | 60% | 离散均匀 5–10 |
| medium-100 | 100 | 8 | 2% | 0% | 离散均匀 1–30 |
| large-200 | 200 | 10 | 1% | 70% | 离散均匀 1–30 |

所有案例使用确定性的线性同余生成器，基础种子为 `20261021`，三次重复的种子依次增加 `1009`。每条候选前置边独立按表中概率抽取，实际边数见结果中的 `edges`。若命中热点比例，则任务分配到 `runner-0`；否则在全部 Runner 中等概率抽取。预算搜索最多评估 10 个候选。更改案例表或算法后应重新生成结果。

## 运行和产物

在仓库根目录运行（PowerShell、bash 均可）：

```text
moon test benchmark/runner
moon run benchmark/runner -- csv > benchmark/results.csv
moon run benchmark/runner -- json > benchmark/results.json
moon run benchmark/runner -- summary > benchmark/summary.csv
moon run benchmark/runner -- svg > benchmark/makespan.svg
moon run benchmark/runner -- time-svg > benchmark/runtime.svg
moon run benchmark/runner -- ablation-csv > benchmark/ablation.csv
moon run benchmark/runner -- ablation-summary > benchmark/ablation-summary.csv
```

`results.csv` 和 `results.json` 各有 72 行：6 个案例 × 3 次重复 × 4 种算法。每次调用重新执行同一批确定性输入，因此两个文件的任务、依赖和工期相同；计时可能受运行时负载影响。`summary.csv` 汇总可行率、平均工期、平均执行时间、平均改善率和可证明最优参照次数。两张 SVG 分别展示平均工期和执行时间随任务规模变化的比较。

每个算法用 `@env.now()` 在调用前后计时，单位为毫秒；输入生成、精确参照、独立排程校验及输出不计入该时间。小于 1 毫秒的调用可能记录为 `0`，**不代表零成本**。`feasible` 由 `validate_schedule` 独立检查；可行率是同一案例和算法下可行次数除以 3。改善率为 `(稳定拓扑工期 − 当前工期) / 稳定拓扑工期 × 100%`，负值表示比该基线慢。`optimality_gap_pct` 仅在精确枚举完整结束且证明最优时填写；当前精确参照最多接受 8 个任务，10–200 任务的空值不能解释为 0% 差距。运行时间图用于同一机器上的粗粒度扩展性比较，跨机器或不同运行时不应直接比较。

本次提交的结果在 Windows NT 10.0.26200、Node.js 22.14.0、MoonBit `moon` 0.1.20260920 / `moonc` 0.10.14+7d59c7ec9 上以默认 JavaScript debug 目标生成。CSV、JSON 与图表是一次测量快照；重跑可验证确定性的工期和可行性，但毫秒数不应要求逐字一致。该基准没有宣称对 10–200 个任务求得全局最优，也没有测量真实生产负载。

`ablation.csv` 与 `ablation-summary.csv` 在相同 18 个固定种子实例外，另包含一个单独标记的 `local-order-trap` 定向实例。每个输入分别运行完整算法以及独立关闭关键路径种子优先、资源负载感知、局部搜索的三个变体；三种基线始终保留。消融不含计时；`delta_from_full` 是变体工期减完整算法工期。解释、无收益机制和适用条件见[实验报告](../docs/benchmark-report.md)。
