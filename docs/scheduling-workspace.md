# 调度工作区

在静态 Web 页面的 **Scheduling lab** 中切换 **Incident Recovery Demo** 与 **CI/CD Scheduling Demo**。两套数据均为明确标注的合成案例，分别位于 `web/scenarios/incident.json` 和 `web/scenarios/ci.json`；不代表真实企业运行记录。

也可以导入符合 [v1 JSON Schema](../web/scenarios/schema.v1.json) 的本地 `.json` 文件。每个任务指定 ID、时长、独占资源、整数优先级和前置任务 ID；`targetWindow` 与任务时长使用同一 `timeUnit`。导入后点击 **Run analysis**。浏览器先检查基本字段，再把输入交给 MoonBit 领域模型校验依赖图，接着由同一个通用调度核心运行三种基线和预算搜索。未知依赖、循环、无效时长或资源会显示错误，不会保留旧图表冒充新结果。

依赖图的任务顺序来自 MoonBit 的依赖分析，红色节点和边标示最长依赖路径。甘特图使用所选算法的逐项起止时间，颜色区分资源，红色轮廓标示关键路径任务。算法表展示相同输入下的 Makespan、算法调用耗时及相对稳定拓扑基线的工期变化。**Execution time** 来自浏览器的毫秒计时接口；`<1 ms` 表示小于计时分辨率。资源负载、关键路径时长和总体下界用于解释结果；下界不保证预算搜索达到全局最优。

**Export JSON** 下载当前场景、全部算法结果和所选算法名称；**Export CSV** 下载所选算法逐项任务排程与 Makespan、耗时。两种导出都使用当前 MoonBit 计算结果。数据仅在当前浏览器中处理和下载，不上传到服务端。`web/package.json` 将 `.js` 文件声明为 ES Module；`web/engine.mjs` 是 MoonBit 的可复现发布产物。
