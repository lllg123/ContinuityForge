# 公开需求证据与验证边界

以下均为截至 2026-10-22 可核实的**公开技术资料**，用来证明问题类型真实存在。由资料推导出 ContinuityForge 的设计需求属于本项目的工程判断；资料作者没有提出或认可本项目。仓库尚无可核实的外部用户访谈、试点部署或真实生产数据。

| 问题与公开来源 | 当前方法的边界及项目推论 | 对应功能、验证方式与已有结果 |
| --- | --- | --- |
| CI 流水线并发与排队：[GitHub Actions 并发控制文档](https://docs.github.com/en/actions/how-tos/write-workflows/choose-when-workflows-run/control-workflow-concurrency)说明同一并发组可限制运行中的作业，并有待处理队列规则。 | 并发组规则处理执行互斥，但该文档并未提供本项目输入下的完整 DAG 最短工期求解器。**推论**：在运行前比较不同任务顺序与 Runner 分配计划有价值。 | `adapters/pipeline` 把阶段、前置关系和独占 Runner 映射到通用问题；`examples/ci_pipeline` 和 Web CI Demo 显示逐项排程。合成基准 `small-20` 中预算搜索平均工期 98，稳定拓扑 106；不能外推到 GitHub Actions 实际排队。 |
| 有向任务的资源容量：[Kubernetes 资源管理文档](https://kubernetes.io/docs/concepts/configuration/manage-resources-containers/)说明调度会检查资源请求与节点容量。 | Kubernetes 处理的是 Pod 放置及具体平台约束；本项目只抽象单任务单独占资源与前置依赖。**推论**：仅拓扑排序不足以计算资源冲突下的完成窗口。 | `scheduling.validate_schedule` 同时检查前置完成与同资源区间不重叠；`examples/recovery_window` 的任务时长合计 70 分钟，因不同资源可并行，算得窗口 45 分钟。此例是合成模型演示，不是 Kubernetes 集群实验。 |
| 微服务故障传播：[Google SRE《Addressing Cascading Failures》](https://sre.google/sre-book/addressing-cascading-failures/)描述局部故障和过载可能扩大为级联故障。 | 该资料讨论实际服务负载与反馈；本项目仅在静态依赖图上传播受影响资产，**不模拟**负载反馈或故障概率。**推论**：事前列出受影响路径与恢复任务有助于演练和人工审查。 | `impact.mbt` 给出确定性影响路径；`adapters/recovery` 将受影响资产和恢复任务接到同一调度核心；`examples/minimal` 可复现。结果只验证静态模型的计算闭环。 |
| 资源约束下的恢复目标：[AWS Resilience Hub 术语文档](https://docs.aws.amazon.com/resilience-hub/latest/userguide/concepts-terms.html)把 RTO 定义为中断到恢复的最大可接受延迟，并区分 RPO。 | RTO 是业务目标，不能由一条拓扑顺序自动证明可达到。**推论**：需要输出逐项起止、资源占用、工期与目标差异，供人工审查。 | `adapters/recovery.analyze_recovery` 返回实际排程、目标分钟数与 `target_met`；`docs/recovery-scheduling.md` 展示 45 分钟窗口及下界。若启发式工期超标，只能说明**这次计划**未达标，不能断定所有计划都不可能。 |

## 证据强度

上述官方资料证明了并发约束、资源容量、级联故障和恢复目标这些**问题背景**；它们不证明 ContinuityForge 的算法优于现有平台，也不证明产品需求已被真实客户验证。项目自己的证据分为三个层次：独立约束测试证明候选排程合法；小实例精确枚举证明特定结果的最优性；固定种子合成基准给出有限范围的比较。量化结果和无收益机制见[实验报告](benchmark-report.md)。

下一步用户验证应邀请实际 CI 管理员和灾备演练负责人，先脱敏收集 10–20 条实际任务图、时长、资源、目标与人工计划，确认模型能表达其约束，再用事前约定的工期、可行率、解释可用性和人工审查时间指标比较。取得许可后记录数据来源、日期、角色、匿名化方式与结果；在此之前不得宣称生产部署或用户认可。
