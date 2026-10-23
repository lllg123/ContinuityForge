# 独立 CP-SAT 参照

`benchmark/reference/ortools_rcpsp.py` 使用固定版本 OR-Tools 9.15.6755 的 CP-SAT，从与 MoonBit **相同的 v2 JSON 文件**读入任务、前置边、容量、多个同时需求、释放时间、硬截止及总体目标。每个任务使用固定长度的 interval；`AddCumulative` 对每种资源施加容量；前置边约束后继开始不早于前驱结束；所有结束时间的上界变量作为最小化的 Makespan。零时长且无需求的 PSPLIB 虚拟节点保留。求解器固定单工作线程、随机种子 20261023 和默认 5 秒时间上限。Python 只用于独立参照，核心求解器与验证器仍为 MoonBit。

在仓库根目录创建 Python 环境并安装 `benchmark/reference/requirements.txt` 后：

```text
python benchmark/reference/ortools_rcpsp.py examples/rcpsp/ci.json --time-limit 5 --output benchmark/reference/ci-reference.json
moon build cmd/rcpsp --target js --release --deny-warn
node integration/js/rcpsp-validate.mjs examples/rcpsp/ci.json benchmark/reference/ci-reference.json
```

`OPTIMAL` 是 CP-SAT 在时间限制内证明的最优解，`FEASIBLE` 是未证明最优的可行解，`INFEASIBLE` 是证明无解，`UNKNOWN` 是未找到结论。输出的 `lower_bound` 是求解器有效的整数下界；只有 `OPTIMAL` 或公开基准有完整证明时才计算最优性差距。`benchmark/reference/*-reference.json` 是本次三个自制教学实例的原始运行快照，耗时受机器影响。三个结果均通过 `import_rcpsp_solution` 的独立可行性检查；CI 最优值 11 分钟、恢复 8 分钟、项目 11 天，这些数字只适用于随仓库提交的示例输入。

CP-SAT 目标是最小化 Makespan。启发式预算是候选邻域次数，CP-SAT 预算是墙钟秒数；两者并不等价，比较时应分别报告时间、结果和最优界。第三方 OR-Tools 采用 Apache-2.0 许可，版本和来源见[PyPI 页面](https://pypi.org/project/ortools/9.15.6755/)；本仓库只依赖它进行可选实验。
