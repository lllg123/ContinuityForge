# 第三方工具与数据来源核查

| 对象 | 仓库用途 | 来源与许可判断 | 分发决定 |
| --- | --- | --- | --- |
| 本项目 MoonBit、JavaScript 与 Python 自编代码 | 核心库、集成和实验 | 本仓库 [Apache-2.0](../LICENSE) | 随仓库发布 |
| MoonBit 工具链 | 编译、检查和测试 | 从[官方安装页面](https://www.moonbitlang.com/download/)获取；仓库未打包其二进制 | 由用户或 CI 单独安装 |
| OR-Tools 9.15.6755 | 可选独立 CP-SAT 参照 | [官方 PyPI 页面](https://pypi.org/project/ortools/9.15.6755/)标注 Apache-2.0；`benchmark/reference/requirements.txt` 固定直接依赖版本 | 仓库不分发包或源码，实验环境单独安装 |
| PSPLIB J30/J60 单模式实例与官方解信息 | 公开 RCPSP 评价 | [PSPLIB 官方页面](https://www.om-db.wi.tum.de/psplib/getdata.php?mode=sm)提供下载和评价用途；未看到明确的重分发许可条款 | 不提交 ZIP、`.sm`、官方 JSON 全量文件；仅保存固定选择 ID、SHA-256、转换器及本项目计算结果 |

PSPLIB 官方[说明](https://www.om-db.wi.tum.de/psplib/library.php)指出研究者可下载实例评估算法，并列出 Kolisch 与 Sprecher (1996) 的库论文。`selection.json` 记录下载地址与本次摘要，`prepare.py` 在本地校验下载文件和已证明最优/上下界。若官方文件更新导致摘要变化，先审查版本与实例含义，再更新选择清单和实验；不要跳过摘要检查。

Python 的 OR-Tools 间接依赖由 pip 根据固定直接版本解析，本仓库当前没有跨平台完整锁文件；`raw.json` 记录本次执行环境及 OR-Tools 版本随每条 CP-SAT 结果的诊断文本。重新运行的毫秒数和 5 秒限时实例状态可能变化。原始结果与可复现脚本提供审计依据，但不代表生产性能认证。
