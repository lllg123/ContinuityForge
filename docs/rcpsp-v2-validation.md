# RCPSP v2 模型与独立可行性验证

`scheduling/rcpsp_model.mbt` 新增独立于业务场景的 `RcpspProblem`。资源以 `RenewableResource(id, capacity)` 表示；任务固定时长、优先级、最早开始、可选硬截止与一组 `ResourceDemand(resource_id, amount)`。需求列表的缺项代表该资源需求为 0；每个正需求在任务完整执行区间内同时占用相应资源。原 `Task`、`Resource`、`SchedulingProblem` 与旧 Web v1 数据保持原语义，`upgrade_exclusive_problem` 明确映射容量 1、需求 1、最早开始 0、无单任务截止。

`inspect_rcpsp_problem` 检查字段、正容量和需求、需求不超过容量、唯一标识、前置 DAG、整数时间范围及可变公共记录。`inspect_rcpsp_schedule` **不调用求解器**，检查任务完整性、固定时长、前置关系、最早开始、硬截止、总体目标及所有可再生资源的瞬时占用。它在每个任务开始时刻扫描全部活动区间 `[start, finish)`；结束与开始同刻时，前者已释放资源。若某项任务需要 CPU 和内存，两个容量条件在同一执行区间分别检查，不拆分任务。当前扫描实现以正确性为先，最坏时间随任务数和资源数平方增长，未来基准若显示瓶颈可换事件排序扫描。

返回的 `ConstraintViolation` 含错误类别、可选任务 ID、资源 ID、起止时间和说明；`validate_rcpsp_problem`/`validate_rcpsp_schedule` 则把首个错误转换为现有 `SchedulingError`，方便旧调用方集成。时间类型为 MoonBit `Int`，任务的 `release_time + duration` 必须可表示，累计资源量在加法前与剩余容量比较。零时长任务只允许空需求，供 PSPLIB 虚拟起止节点使用。验证器检查候选排程是否合规，**不证明该问题存在解或给出最优性**。

运行 `moon test scheduling` 可复核容量 4 下 2+1 并行、2+3 冲突、多资源独立超量、半开端点、释放/截止/总体目标、缺失任务、溢出、旧模型映射与零时长虚拟节点。v2 求解器尚未在本阶段实现；在它完成前，不能宣称新约束已端到端支持。
