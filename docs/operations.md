# ContinuityForge 运行与操作说明

本文档说明如何在全新环境运行核心示例和本地 Web 工作区。ContinuityForge 只生成分析结果、恢复计划和演练记录；恢复动作仍需由人工在目标系统中执行。

## 环境要求

- MoonBit 工具链 0.10.7 或更新版本。
- Node.js 20 或更新版本，用于 JavaScript 集成探针。
- Python 3，用于静态 Web 预览。
- Git，用于获取仓库和复核提交历史。

检查工具链：

```text
moon version --all
node --version
```

## 首次启动与领域示例

在仓库根目录执行：

```text
moon check --target all --deny-warn
moon run examples/minimal
```

最小示例会依次登记服务和组件、校验依赖、创建 BIA、模拟数据库故障、生成恢复顺序、推进带审批点的恢复预案，并完成一次演练。`examples/minimal/sample-data.json` 是同一场景的脱敏输入快照，可作为 Web 录入或集成测试的参考数据。

## Web 工作区

启动静态预览服务器：

```text
python -m http.server 8765 --directory web
```

然后打开 `http://127.0.0.1:8765/`，按以下顺序操作：

1. 在 **Inventory** 中确认服务、组件、负责人和依赖关系。
2. 在 **Business impact** 中填写影响分数、RTO、RPO 和最大可容忍中断时间。
3. 在 **Incident impact** 中选择 `postgres-primary`，检查两级依赖传播结果。
4. 在 **Recovery plans** 中检查依赖感知的恢复顺序和资源窗口。
5. 在 **Drill log** 中记录后续事件，确认审批和完成时间线。
6. 点击 **Export evidence** 下载当前工作区的 JSON 证据包。

浏览器工作区的数据保存在当前浏览器的 localStorage 中。演练和资产数据属于本地演示数据，不应替换为生产凭据或真实遥测。

## 发布前检查

```text
moon fmt --check
moon check --target all --deny-warn
moon info
moon test --target all
moon build --target all --deny-warn
moon run examples/minimal
node integration/js/smoke.mjs
node --check web/app.js
git diff --check
```

GitHub Actions 的 `ContinuityForge CI` 会在 `main` 推送和 Pull Request 上自动执行同一组门禁。

## 故障排查

- **依赖校验失败**：确认每条边的两端都在 Inventory 中，且没有自依赖或循环依赖。
- **BIA 无法保存**：确认 RTO 和 RPO 不超过最大可容忍中断时间，时间值为非负分钟数。
- **恢复顺序不符合预期**：先检查依赖边，再检查恢复资源是否在可用资源列表中，以及总时长是否超过目标窗口。
- **演练无法推进**：按前置条件开始步骤；需要审批的步骤必须先记录审批事件。
- **报告下载失败**：确认浏览器允许当前页面下载，并检查页面控制台是否有错误。

## 明确不支持的范围

当前版本不连接真实监控、云平台或故障切换接口，不执行生产恢复动作，不提供多租户服务，也不保存密码、令牌、生产地址或真实用户遥测。
