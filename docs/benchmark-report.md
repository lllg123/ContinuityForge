# 调度实验报告

本报告对应 `benchmark/runner/main.mbt`、[逐次结果](../benchmark/results.csv)、[汇总结果](../benchmark/summary.csv)、[消融逐次结果](../benchmark/ablation.csv)及[消融汇总](../benchmark/ablation-summary.csv)。输入全为**合成数据**，没有生产 CI 或故障恢复记录。目标是可复核地比较同一约束模型下的可行性、工期、调用耗时和机制贡献，而不是证明普遍最优。

## 复现

安装 README 所列 MoonBit 工具链，在仓库根目录运行：

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

原始基准为 6 种规模 × 3 个固定种子 × 4 种算法，共 72 条记录。种子为 `20261021`、`20262030`、`20263039`，局部搜索预算为 10 次合法相邻交换候选评估。`benchmark/README.md` 给出任务数、Runner 数、边抽样概率、热点比例和时长分布。所有算法使用同一输入；`validate_schedule` 独立检查每个结果。上面的重定向命令可能使用不同 shell 编码写文件，但 CSV/JSON 字段与确定性工期应相同。计时会波动，不能按字节比较。

## 算法对比

下表从 `benchmark/summary.csv` 读取平均工期；越小越好。每个单元由三个固定种子各一次观测平均得出，数值不是生产业务分钟数。

| 案例 | 稳定拓扑 | 恢复启发式 | 关键路径 | 预算搜索 | 搜索相对稳定拓扑的平均改善率 |
| --- | ---: | ---: | ---: | ---: | ---: |
| micro，6 项 | 41.00 | 38.67 | 38.67 | 38.67 | 4.86% |
| small-12 | 79.67 | 80.00 | 80.00 | 79.67 | 0% |
| small-20 | 106.00 | 101.67 | 100.00 | 98.00 | 6.56% |
| medium-50 | 272.67 | 272.67 | 272.67 | 272.67 | 0% |
| medium-100 | 278.67 | 286.00 | 281.00 | 278.67 | 0% |
| large-200 | 2268.33 | 2265.67 | 2265.33 | 2265.33 | 0.13% |

72/72 个原始结果均通过可行性检查。预算搜索保留三种基线中的最优候选，因此在这组输入上不会比它们更差；这不等于有统计可靠的改进。`small-20` 的平均改善率 6.56% 是**逐个种子改善率的均值**，不能直接用表格中两个平均工期相除代替。`medium-100` 中单独的恢复启发式和关键路径基线反而比稳定拓扑更慢，说明优先规则存在适用条件。

仅 `micro` 的 3 个实例完整取得精确参照：预算搜索的最优性差距均为 0；稳定拓扑在第 3 个种子为 17.07%，其余两个为 0。12–200 项没有最优性证明，空的 `optimality_gap_pct` 不能解释为 0。执行时间列是本地毫秒级 `@env.now()` 观测，0 表示低于分辨率；`large-200` 搜索平均约 60.33 ms、稳定拓扑约 3.67 ms。这些时间不构成跨机器性能承诺。原始基准快照的环境见 `benchmark/README.md`。

## 单因素消融

`optimize_schedule_with_features` 每次只关闭一个机制：自适应种子的关键路径排序、资源总负载平局规则、或相邻交换局部搜索。三种原有基线始终保留为同一回退候选，因此测试的是**额外机制相对于基线组合的边际贡献**，不是从系统中删除关键路径基线。详细结果可由 `ablation-csv` 命令重算；`delta_from_full = 变体工期 − 完整算法工期`，正值表示关闭机制后变差。

| 输入组 | 观测次数/变体 | 关闭关键路径 | 关闭资源负载 | 关闭局部搜索 | 可行性 |
| --- | ---: | ---: | ---: | ---: | ---: |
| 六组合成随机案例合计 | 18 | 工期差均为 0 | 工期差均为 0 | 工期差均为 0 | 72/72 |
| 定向 `local-order-trap` | 1 | 差 0 | 差 0 | 19 − 12 = +7 | 4/4 |

定向案例中，共享资源上的 `a` 耗时 10，后续 `c` 耗时 1；`b` 耗时 1，后续 `d` 耗时 8。先安排 `b` 再安排 `a` 可让 `d` 与 `a` 并行，工期为 12；没有局部交换的三种基线和自适应种子均给出 19。精确枚举已在 `scheduling/exact_reference_test.mbt` 证明此案例最优工期为 12。这个正例说明局部搜索在**资源顺序使下游任务被延迟**时可产生贡献，但单个定向实例不支持总体收益声明。

关键路径与资源负载感知在当前消融集合中没有可观察的边际工期收益。它们目前只作为低成本的候选种子排序规则保留；不能据此宣传这两项带来可靠改进。若后续更大、更真实的数据仍无收益，应简化这两项规则。现有三次重复是不同固定种子的确定性实例，不是对真实工作负载的统计抽样。

## 解释与局限

工期是 `max(finish)`，不是任务时长求和；最长依赖路径和每个独占资源的总负载仅提供下界。热点资源比例高时，资源负载可能主导工期，其他排序规则很难改善 `large-200`。预算 10 限制搜索时间，也可能错过更好的任务顺序。模型只允许每项任务绑定一个容量为 1 的资源，不表示多资源占用、抢占、动态到达、故障概率或实际 Runner 调度策略。实例生成、时间测量、精确参照边界及算法细节见[算法设计](algorithm-design.md)。
