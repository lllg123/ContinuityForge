# PSPLIB 公开 RCPSP 实例

本目录的转换工具读取 [PSPLIB 官方单模式实例](https://www.om-db.wi.tum.de/psplib/getdata.php?mode=sm)；官方 J30 的 480 个实例都有已证明最优值，J60 的部分实例只有上下界。`selection.json` 固定五个案例，覆盖 32/62 个节点和三个参数组，同时包含一个**尚无官方最优性证明**的 J60 实例。官方原始 ZIP 与逐实例 `.sm` 文件未提交；站点允许研究者下载用于算法评价，但未明确授予重分发许可，所以仓库只保存来源、摘要和转换器。引用 PSPLIB 时请标明 Kolisch 与 Sprecher (1996)，原站也列出该论文。

把官方页面的 J30/J60 ZIP 和相应 JSON Summary 下载到某个本地 `CACHE` 目录，分别命名为：

```text
psplib-j30.zip
psplib-j60.zip
psplib-j30-solutions.json
psplib-j60-solutions.json
```

四个直接来源 URL 在 `selection.json` 中。文件的 SHA-256 也固定在那里，防止运行中无声换版。然后在仓库根目录运行：

```text
python benchmark/psplib/prepare.py --cache CACHE --output OUTPUT
moon build cmd/rcpsp --target js --release --deny-warn
node integration/js/rcpsp-cli.mjs OUTPUT/j301_1.sm.json stable-topological 0
```

`prepare.py` 校验下载摘要、官方实例 ID、官方最优/上下界及证明标记后写出规范化 v2 JSON 与 `provenance.json`。转换器还对 J30 与 J60 的全部 480+480 个原文件逐一完成格式解析。每个 `.sm` 中 30/60 个普通任务和虚拟起止节点全部保留；四类可再生资源的容量、每任务四个需求、时长与全部后继边原样映射。所有文件均为单模式、无不可再生或双重约束资源，项目释放时间为零。PSPLIB `PROJECT INFORMATION` 中的 `duedate`/`tardcost` 是附带项目资料，不是本单模式 **最小 Makespan** 基准的硬截止：例如 `j301_1.sm` 的该字段为 38，而官方已证明最优 Makespan 为 43。文件里的 `horizon` 是实例生成的搜索上界，不作为任务截止；转换器不把它加入约束。v2 模型里的任务 `release_time` 全部为 0，`deadline` 与 `target_makespan` 省略。

本次固定选择与官方参照：

| 原始成员 | 节点 | 官方最优 | 官方下界 | 官方上界 |
| --- | ---: | ---: | ---: | ---: |
| `j301_1.sm` | 32 | 43 | 43 | 43 |
| `j309_1.sm` | 32 | 83 | 83 | 83 |
| `j3013_1.sm` | 32 | 58 | 58 | 58 |
| `j601_1.sm` | 62 | 77 | 77 | 77 |
| `j609_1.sm` | 62 | 未证明 | 82 | 87 |

不得把 `j609_1.sm` 的上界 87 当作已证明最优值。转换后的 MoonBit 稳定拓扑结果依次为 49、100、75、80、106，五个结果均由独立验证器检查为可行；这些只是一个基线，不代表本项目最终实验结论。更多算法与 CP-SAT 原始结果见后续实验产物。
