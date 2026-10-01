# ContinuityForge 开发计划

## 项目定位

ContinuityForge 是系统韧性与业务连续性平台。首个可交付版本面向单个组织，帮助团队登记关键业务与技术依赖，完成业务影响分析（BIA），模拟故障影响，生成恢复顺序，记录演练过程，并导出可追溯报告。

平台只做分析、规划与演练记录，不直接操作生产系统或自动切换灾备。所有故障场景和恢复动作都必须明确标为“模拟”或“待人工执行”。

## 技术路线与边界

- **MoonBit 核心**：领域模型、依赖图、影响传播、优先级计算、恢复排序和报告数据生成。核心算法保持确定性，并以单元测试验证。
- **服务端**：Node.js/TypeScript 提供 API、输入校验、身份与权限控制及 SQLite 持久化。第 2 次提交先验证 MoonBit 与服务端的集成路径；若工具链约束不同，以验证结果调整接口，不改变核心业务边界。
- **Web 端**：React/TypeScript 实现资产登记、BIA、场景模拟、恢复预案、演练和报告页面。
- **MVP 约束**：单组织、单实例部署；不接入真实监控、云平台或故障切换接口；不收集生产凭据。

## 交付与验收标准

1. 用户可建立业务服务、技术组件及其依赖，并得到循环依赖等错误的明确提示。
2. 用户可为业务服务填写影响等级、RTO、RPO 和最大可容忍中断时间；不合法指标不能保存。
3. 给定故障组件，平台可展示受影响服务、传播路径、优先级和计算依据；相同输入得到相同结果。
4. 平台可生成遵守依赖顺序的恢复预案，并标注人工审批与资源约束。
5. 用户可创建、推进和完成演练，保留时间线、结果和证据引用。
6. 平台可导出包含输入快照、计算结果、预案和演练记录的报告。
7. 核心测试、API 集成测试和关键页面端到端流程通过；README 给出从全新环境启动和复现演示的步骤。

## 分步实施与提交计划

以下为 **15 次独立、可复核的提交**。每次提交前运行适用的格式化、构建与测试命令；不要为了凑次数拆分同一功能的半成品。提交标题仅作建议，可根据实际实现微调。

| 次序 | 建议提交标题 | 交付内容 | 单次验收点 |
| --- | --- | --- | --- |
| 1 | `docs: define ContinuityForge MVP and repository conventions` | 建立仓库、README、许可证、忽略规则与本计划；固定范围和目录约定。 | 仓库结构、范围与启动前提可读；无密钥进入版本库。 |
| 2 | `build: scaffold MoonBit core and validate JS integration` | 建立 MoonBit 模块、TypeScript 工作区与最小跨语言调用样例。 | 全新克隆后可构建，服务端测试能调用一个 MoonBit 导出函数。 |
| 3 | `feat(core): model services components and dependencies` | 定义业务服务、技术组件、依赖边和稳定标识；实现字段校验。 | 有效与无效模型的测试通过，错误包含字段信息。 |
| 4 | `feat(core): validate dependency graph and detect cycles` | 实现拓扑排序、缺失节点检查、循环检测和可解释错误。 | 多层依赖排序稳定，循环与悬空依赖被拒绝。 |
| 5 | `feat(core): add business impact assessment` | 建立 BIA 指标、时间单位和影响分级规则。 | RTO、RPO、最大可容忍中断时间的约束测试通过。 |
| 6 | `feat(core): simulate incident impact propagation` | 输入故障节点，计算受影响业务、传播路径及去重后的影响范围。 | 菱形依赖不重复计数；相同输入的结果顺序固定。 |
| 7 | `feat(core): prioritize recovery under constraints` | 结合业务影响、依赖关系、恢复时间与资源约束生成恢复顺序。 | 前置组件先恢复；资源冲突和无法满足的目标有明确说明。 |
| 8 | `feat(core): model recovery playbooks and approvals` | 为恢复步骤定义负责人、人工确认点、前置条件与状态。 | 未满足前置条件或审批时，步骤不能推进。 |
| 9 | `feat(core): track drills and produce audit timeline` | 建立演练状态机、事件记录和可重放时间线。 | 非法状态转换被拒绝，记录顺序与来源可追溯。 |
| 10 | `feat(api): expose validated domain operations` | 建立业务、组件、BIA、场景、预案和演练的 API 契约与校验。 | API 集成测试覆盖成功、非法输入和领域错误映射。 |
| 11 | `feat(storage): persist projects and audit records` | 增加 SQLite 迁移、仓储实现和事务边界。 | 重启后数据仍在；失败事务不留下部分写入。 |
| 12 | `feat(auth): add local users and role based access` | 建立本地登录与管理员、规划者、只读角色；敏感操作写审计。 | 未登录及越权请求被拒绝，普通密码不以明文保存。 |
| 13 | `feat(web): build inventory and BIA workspace` | 实现业务/组件/依赖编辑及 BIA 表单与校验反馈。 | 可从空数据录入并保存一套可分析的业务依赖。 |
| 14 | `feat(web): visualize incidents recovery and drills` | 实现场景影响、恢复顺序、演练时间线的页面与交互。 | 从故障场景到预案、演练的完整流程可在浏览器操作。 |
| 15 | `feat(report): export evidence and finish release checks` | 报告导出、示例数据、端到端流程、CI、部署与操作文档。 | 全新环境按 README 启动；核心/API/端到端检查通过，可导出完整报告。 |

## 提交与协作约定

- 在 `ContinuityForge` 内初始化独立 Git 仓库；后续提交均在该仓库完成。
- 提交作者使用用户指定的 GitHub 用户名和邮箱，设置为**仓库级** Git 配置，避免影响其他项目。GitHub 密码不写入命令、源码、配置、测试数据、提交信息或远程地址。
- 每次提交只包含对应阶段已完成且通过检查的内容。完成第 15 次提交后复核提交数量、作者信息、工作区状态和可运行演示。
- 如需推送到 GitHub，先确认远程仓库地址及当前登录状态；远程发布不属于本计划文件的创建步骤。

## 首轮开发顺序

先完成第 1–2 次提交以锁定工具链，再实现第 3–9 次 MoonBit 核心提交；核心行为稳定后接入 API、持久化和权限，最后完成 Web 流程与发布检查。
