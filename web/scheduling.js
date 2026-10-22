const PRESETS = { incident: "./scenarios/incident.json", ci: "./scenarios/ci.json" }

export function validateScenario(value) {
  if (!value || typeof value !== "object" || value.schemaVersion !== "1.0") {
    throw new Error("Expected a version 1.0 scheduling scenario.")
  }
  if (!Array.isArray(value.tasks) || value.tasks.length === 0 || value.tasks.length > 500) {
    throw new Error("Provide 1–500 tasks.")
  }
  if (!Number.isInteger(value.targetWindow) || value.targetWindow < 0) {
    throw new Error("targetWindow must be a nonnegative integer.")
  }
  if (!Number.isInteger(value.searchBudget) || value.searchBudget < 0 || value.searchBudget > 10000) {
    throw new Error("searchBudget must be an integer from 0 to 10000.")
  }
  const ids = new Set()
  for (const task of value.tasks) {
    if (!task || typeof task.id !== "string" || !task.id.trim() || ids.has(task.id)) {
      throw new Error("Task IDs must be unique nonempty strings.")
    }
    ids.add(task.id)
    if (!Number.isInteger(task.duration) || task.duration <= 0 || task.duration > 1000000) {
      throw new Error("Every task needs a positive integer duration up to 1000000.")
    }
    if (typeof task.resource !== "string" || !task.resource.trim()) {
      throw new Error("Every task needs a resource name.")
    }
    if (!Number.isInteger(task.priority) || !Array.isArray(task.dependsOn) ||
        task.dependsOn.some((id) => typeof id !== "string")) {
      throw new Error("Every task needs an integer priority and string dependsOn list.")
    }
    if (task.assetType !== undefined && !["Service", "Component"].includes(task.assetType)) {
      throw new Error("assetType must be Service or Component.")
    }
  }
  if (value.failedTaskId && !ids.has(value.failedTaskId)) {
    throw new Error("failedTaskId must name an included task.")
  }
  return value
}

export function toEngineRequest(scenario) {
  return {
    assets: scenario.tasks.map((task) => ({
      id: task.id,
      asset_type: task.assetType ?? "Component",
      depends_on: task.dependsOn,
      duration: task.duration,
      resource: task.resource,
      priority: task.priority,
    })),
    failed_asset_id: scenario.failedTaskId ?? "",
    target_window: scenario.targetWindow,
    search_budget: scenario.searchBudget,
  }
}

export function analyzeScenario(scenario, engine) {
  validateScenario(scenario)
  const reply = JSON.parse(engine(JSON.stringify(toEngineRequest(scenario))))
  if (!reply.ok) throw new Error(reply.error || "MoonBit scheduling failed.")
  return reply.result
}

function selectedAlgorithm(result, name) {
  return name === "budgeted-search"
    ? result.optimized
    : result.baselines.find((item) => item.name === name) ?? result.optimized
}

export function graphMarkup(scenario, result, escapeHtml) {
  const tasks = new Map(scenario.tasks.map((task) => [task.id, task]))
  const levels = new Map()
  const columns = new Map()
  for (const id of result.dependency_order) {
    const task = tasks.get(id)
    const level = task.dependsOn.length
      ? 1 + Math.max(...task.dependsOn.map((dependency) => levels.get(dependency)))
      : 0
    levels.set(id, level)
    const column = columns.get(level) ?? []
    column.push(id)
    columns.set(level, column)
  }
  const positions = new Map()
  for (const [level, ids] of columns) {
    ids.forEach((id, index) => positions.set(id, { x: 24 + level * 215, y: 30 + index * 86 }))
  }
  const width = Math.max(460, 60 + columns.size * 215)
  const height = Math.max(150, 75 + 86 * Math.max(...[...columns.values()].map((ids) => ids.length)))
  const critical = new Set(result.critical_path)
  const edges = scenario.tasks.flatMap((task) => task.dependsOn.map((dependency) => {
    const from = positions.get(dependency)
    const to = positions.get(task.id)
    const x1 = from.x + 155
    const x2 = to.x
    const y1 = from.y + 22
    const y2 = to.y + 22
    const tone = critical.has(dependency) && critical.has(task.id) ? "critical" : ""
    return `<path class="graph-edge ${tone}" d="M ${x1} ${y1} C ${x1 + 28} ${y1}, ${x2 - 28} ${y2}, ${x2} ${y2}"/>`
  })).join("")
  const nodes = result.dependency_order.map((id) => {
    const { x, y } = positions.get(id)
    const task = tasks.get(id)
    const tone = critical.has(id) ? "critical" : ""
    return `<g class="graph-node ${tone}"><rect x="${x}" y="${y}" width="155" height="44" rx="10"/>` +
      `<text x="${x + 11}" y="${y + 19}">${escapeHtml(task.label ?? task.id)}</text>` +
      `<text class="graph-subtitle" x="${x + 11}" y="${y + 34}">${escapeHtml(task.resource)} · ${task.duration}</text></g>`
  }).join("")
  return `<svg class="dependency-svg" viewBox="0 0 ${width} ${height}" width="${width}" height="${height}" role="img" aria-label="Task dependency graph">${edges}${nodes}</svg>`
}

export function ganttMarkup(scenario, algorithm, result, escapeHtml) {
  const taskById = new Map(scenario.tasks.map((task) => [task.id, task]))
  const resources = [...new Set(scenario.tasks.map((task) => task.resource))]
  const makespan = Math.max(1, algorithm.makespan)
  const critical = new Set(result.critical_path)
  const ticks = [0, 25, 50, 75, 100]
    .map((pct) => `<span style="left:${pct}%">${Math.round(makespan * pct / 100)}</span>`)
    .join("")
  const rows = resources.map((resource, resourceIndex) => {
    const bars = algorithm.schedule
      .filter((entry) => entry.resource === resource)
      .map((entry) => {
        const task = taskById.get(entry.asset_id)
        const left = (entry.start / makespan) * 100
        const width = ((entry.finish - entry.start) / makespan) * 100
        const title = `${task.label ?? task.id}: ${entry.start}–${entry.finish} ${scenario.timeUnit ?? "units"}`
        return `<span class="gantt-bar resource-${resourceIndex % 4} ${critical.has(entry.asset_id) ? "critical" : ""}"` +
          ` style="left:${left}%;width:${width}%" title="${escapeHtml(title)}">${escapeHtml(task.label ?? task.id)}</span>`
      }).join("")
    return `<div class="gantt-row"><strong>${escapeHtml(resource)}</strong><div class="gantt-track">${bars}</div></div>`
  }).join("")
  return `<div class="gantt-axis"><span></span><div>${ticks}</div></div>${rows}`
}

function csvCell(value) {
  let text = String(value)
  if (/^[=+\-@]/.test(text)) text = "'" + text
  return '"' + text.replaceAll('"', '""') + '"'
}

function download(name, type, content) {
  const url = URL.createObjectURL(new Blob([content], { type }))
  const link = document.createElement("a")
  link.href = url
  link.download = name
  document.body.appendChild(link)
  link.click()
  link.remove()
  URL.revokeObjectURL(url)
}

export function initSchedulingWorkspace({ analyze_workspace, escapeHtml, showToast }) {
  const scenarioSelect = document.querySelector("#schedule-scenario")
  const algorithmSelect = document.querySelector("#schedule-algorithm")
  let scenario = null
  let imported = null
  let result = null

  function clear(error) {
    document.querySelector("#schedule-error").textContent = error
    for (const id of ["schedule-summary", "schedule-graph", "schedule-gantt", "schedule-comparison", "schedule-explanation"]) {
      document.getElementById(id).replaceChildren()
    }
    result = null
  }

  function render() {
    if (!scenario || !result) return
    const algorithm = selectedAlgorithm(result, algorithmSelect.value)
    const unit = scenario.timeUnit ?? "units"
    const edges = scenario.tasks.reduce((sum, task) => sum + task.dependsOn.length, 0)
    const summary = [
      ["Tasks / edges", `${scenario.tasks.length} / ${edges}`],
      ["Makespan", `${algorithm.makespan} ${unit}`],
      ["Execution time", algorithm.elapsed_ms === 0 ? "<1 ms" : `${algorithm.elapsed_ms} ms`],
      ["Target", algorithm.makespan <= scenario.targetWindow ? "Met" : "Missed"],
    ]
    document.querySelector("#schedule-summary").innerHTML = summary
      .map(([label, value]) => `<div class="schedule-stat"><span>${label}</span><strong>${escapeHtml(value)}</strong></div>`)
      .join("")
    document.querySelector("#schedule-graph").innerHTML = graphMarkup(scenario, result, escapeHtml)
    document.querySelector("#schedule-gantt").innerHTML = ganttMarkup(scenario, algorithm, result, escapeHtml)
    const stable = result.baselines[0].makespan
    document.querySelector("#schedule-comparison").innerHTML = [...result.baselines, result.optimized]
      .map((item) => {
        const gain = stable ? Math.round(((stable - item.makespan) / stable) * 1000) / 10 : 0
        return `<tr class="${item.name === algorithm.name ? "selected" : ""}"><td>${escapeHtml(item.name)}</td>` +
          `<td>${item.makespan} ${escapeHtml(unit)}</td><td>${item.elapsed_ms === 0 ? "<1" : item.elapsed_ms} ms</td>` +
          `<td>${gain > 0 ? "+" : ""}${gain}%</td></tr>`
      }).join("")
    const path = result.critical_path.map((id) => scenario.tasks.find((task) => task.id === id)?.label ?? id)
    document.querySelector("#schedule-explanation").innerHTML =
      `<p><strong>Critical path:</strong> ${escapeHtml(path.join(" → ") || "none")} (${result.critical_path_duration} ${escapeHtml(unit)})</p>` +
      `<p><strong>Lower bound:</strong> ${result.lower_bound} ${escapeHtml(unit)}. Dependencies and exclusive resources both constrain this bound.</p>` +
      `<p><strong>Busiest resource:</strong> ${escapeHtml(result.bottleneck_resource ?? "none")} (${result.bottleneck_load} ${escapeHtml(unit)} of work).</p>` +
      `<p class="schedule-note">Synthetic presets are examples. Runtime uses a millisecond clock; &lt;1 ms means below its resolution.</p>`
  }

  function run() {
    try {
      if (!scenario) throw new Error("Choose a preset or import a JSON scenario.")
      result = analyzeScenario(scenario, analyze_workspace)
      document.querySelector("#schedule-error").textContent = ""
      render()
    } catch (error) {
      clear(error.message)
    }
  }

  async function loadPreset(kind) {
    try {
      const response = await fetch(PRESETS[kind])
      if (!response.ok) throw new Error(`Cannot load ${kind} scenario (${response.status}).`)
      scenario = validateScenario(await response.json())
      run()
    } catch (error) {
      scenario = null
      clear(error.message)
    }
  }

  scenarioSelect.addEventListener("change", () => {
    if (scenarioSelect.value === "custom") {
      scenario = imported
      run()
    } else {
      loadPreset(scenarioSelect.value)
    }
  })
  document.querySelector("#schedule-import").addEventListener("change", async (event) => {
    const file = event.target.files?.[0]
    if (!file) return
    try {
      imported = validateScenario(JSON.parse(await file.text()))
      scenario = imported
      scenarioSelect.value = "custom"
      run()
      if (result) showToast("Scenario imported and analyzed")
    } catch (error) {
      clear(error.message)
    }
  })
  algorithmSelect.addEventListener("change", render)
  document.querySelector("#schedule-run").addEventListener("click", run)
  document.querySelector("#schedule-export-json").addEventListener("click", () => {
    if (!result) return showToast("Run a valid scenario first", "error")
    download("continuityforge-schedule.json", "application/json", JSON.stringify({
      schemaVersion: "1.0", scenario, result, selectedAlgorithm: algorithmSelect.value,
    }, null, 2))
  })
  document.querySelector("#schedule-export-csv").addEventListener("click", () => {
    if (!result) return showToast("Run a valid scenario first", "error")
    const algorithm = selectedAlgorithm(result, algorithmSelect.value)
    const header = "task_id,resource,start,finish,duration,algorithm,makespan,elapsed_ms"
    const lines = algorithm.schedule.map((entry) => [
      entry.asset_id, entry.resource, entry.start, entry.finish,
      entry.finish - entry.start, algorithm.name, algorithm.makespan, algorithm.elapsed_ms,
    ].map(csvCell).join(","))
    download("continuityforge-schedule.csv", "text/csv;charset=utf-8", [header, ...lines].join("\n") + "\n")
  })
  loadPreset("incident")
  return { run }
}
