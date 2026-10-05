const STORAGE_KEY = "continuityforge-web-v1"

const DEFAULT_STATE = {
  assets: [
    {
      id: "checkout-api",
      name: "checkout-api",
      type: "Service",
      owner: "Commerce platform",
      criticality: "High",
      dependsOn: ["postgres-primary"],
    },
    {
      id: "postgres-primary",
      name: "postgres-primary",
      type: "Component",
      owner: "Data platform",
      criticality: "Critical",
      dependsOn: [],
    },
    {
      id: "payment-gateway",
      name: "payment-gateway",
      type: "Service",
      owner: "Payments",
      criticality: "High",
      dependsOn: ["checkout-api"],
    },
  ],
  bia: [
    {
      serviceId: "checkout-api",
      score: 82,
      rto: 30,
      rpo: 15,
      downtime: 120,
    },
    {
      serviceId: "payment-gateway",
      score: 76,
      rto: 60,
      rpo: 30,
      downtime: 240,
    },
  ],
  drill: {
    status: "In progress",
    events: [
      {
        time: "09:00",
        actor: "Continuity operator",
        action: "Drill started",
        detail: "checkout-recovery",
        kind: "start",
      },
      {
        time: "09:04",
        actor: "Database team",
        action: "Step started",
        detail: "restore-db",
        kind: "step",
      },
      {
        time: "09:07",
        actor: "Resilience approver",
        action: "Approval recorded",
        detail: "restore-db approved",
        kind: "approval",
      },
      {
        time: "09:18",
        actor: "Database team",
        action: "Step completed",
        detail: "restore-db",
        kind: "complete",
      },
      {
        time: "09:22",
        actor: "Platform team",
        action: "Step started",
        detail: "restore-api",
        kind: "step",
      },
    ],
  },
}

const copyDefaultState = () => ({
  assets: DEFAULT_STATE.assets.map((asset) => ({
    ...asset,
    dependsOn: [...asset.dependsOn],
  })),
  bia: DEFAULT_STATE.bia.map((record) => ({ ...record })),
  drill: {
    status: DEFAULT_STATE.drill.status,
    events: DEFAULT_STATE.drill.events.map((event) => ({ ...event })),
  },
})

let state = loadState()
let toastTimer

function loadState() {
  try {
    const stored = window.localStorage.getItem(STORAGE_KEY)
    if (!stored) return copyDefaultState()
    const parsed = JSON.parse(stored)
    if (!Array.isArray(parsed.assets) || !Array.isArray(parsed.bia)) {
      return copyDefaultState()
    }
    const fallback = copyDefaultState()
    return {
      ...fallback,
      ...parsed,
      drill: {
        ...fallback.drill,
        ...(parsed.drill ?? {}),
        events: Array.isArray(parsed.drill?.events)
          ? parsed.drill.events
          : fallback.drill.events,
      },
    }
  } catch {
    return copyDefaultState()
  }
}

function persistState() {
  try {
    window.localStorage.setItem(STORAGE_KEY, JSON.stringify(state))
  } catch {
    // The workspace remains usable when browser storage is unavailable.
  }
  document.querySelector("#last-saved").textContent = "Saved locally · just now"
}

function escapeHtml(value) {
  return String(value)
    .replaceAll("&", "&amp;")
    .replaceAll("<", "&lt;")
    .replaceAll(">", "&gt;")
    .replaceAll('"', "&quot;")
    .replaceAll("'", "&#039;")
}

function slugify(value) {
  const base = value
    .trim()
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, "-")
    .replace(/^-+|-+$/g, "")
  return base || "asset-" + Date.now()
}

function criticalityClass(value) {
  return String(value).toLowerCase()
}

function impactLevel(score) {
  if (score >= 80) return "Critical"
  if (score >= 60) return "High"
  if (score >= 30) return "Medium"
  return "Low"
}

function formatMinutes(value) {
  const minutes = Number(value)
  if (minutes >= 1440 && minutes % 1440 === 0) return minutes / 1440 + "d"
  if (minutes >= 60 && minutes % 60 === 0) return minutes / 60 + "h"
  return minutes + "m"
}

function assetById(id) {
  return state.assets.find((asset) => asset.id === id)
}

function impactRank(value) {
  return { Critical: 4, High: 3, Medium: 2, Low: 1 }[value] ?? 0
}

function dependentImpact(failedId) {
  const impacts = []
  const queue = [{ id: failedId, path: [failedId] }]
  const visited = new Set([failedId])
  while (queue.length) {
    const current = queue.shift()
    state.assets.forEach((asset) => {
      if (!visited.has(asset.id) && (asset.dependsOn ?? []).includes(current.id)) {
        visited.add(asset.id)
        const path = current.path.concat(asset.id)
        impacts.push({ asset, path, depth: path.length - 1 })
        queue.push({ id: asset.id, path })
      }
    })
  }
  return impacts
}

function assetImpactLevel(asset) {
  return asset.criticality || "Medium"
}

function renderIncident() {
  const select = document.querySelector("#incident-asset")
  const current = select.value
  select.innerHTML = state.assets
    .map(
      (asset) =>
        '<option value="' +
        escapeHtml(asset.id) +
        '">' +
        escapeHtml(asset.name) +
        " · " +
        escapeHtml(asset.criticality) +
        "</option>",
    )
    .join("")
  if (assetById(current)) select.value = current
  if (!select.value && select.options.length) select.selectedIndex = 0

  const failed = assetById(select.value)
  const impacts = failed ? dependentImpact(failed.id) : []
  const maxDepth = impacts.reduce((max, item) => Math.max(max, item.depth), 0)
  const highest = impacts.reduce(
    (currentLevel, item) =>
      impactRank(assetImpactLevel(item.asset)) > impactRank(currentLevel)
        ? assetImpactLevel(item.asset)
        : currentLevel,
    "",
  )

  document.querySelector("#impact-affected-count").textContent = impacts.length
  document.querySelector("#impact-depth").textContent = maxDepth + " hops"
  document.querySelector("#impact-highest").textContent = highest || "—"
  document.querySelector("#nav-incident-count").textContent = impacts.length

  document.querySelector("#impact-table").innerHTML = impacts
    .map((item) => {
      const level = assetImpactLevel(item.asset)
      const path = item.path.map((id) => assetById(id)?.name ?? id).join(" → ")
      return (
        "<tr>" +
        '<td><div class="asset-cell"><span class="asset-icon component">↳</span>' +
        "<span><strong>" +
        escapeHtml(item.asset.name) +
        "</strong><small>" +
        escapeHtml(item.asset.id) +
        "</small></span></div></td>" +
        '<td><span class="criticality-pill ' +
        criticalityClass(level) +
        '"><span class="status-dot ' +
        (level === "Critical" ? "red" : level === "High" ? "amber" : "blue") +
        '"></span>' +
        escapeHtml(level) +
        "</span></td>" +
        '<td class="path-cell">' +
        escapeHtml(path) +
        "</td><td>" +
        escapeHtml(item.asset.owner) +
        "</td></tr>"
      )
    })
    .join("")
  document.querySelector("#impact-empty").classList.toggle("hidden", impacts.length > 0)

  const chain = failed
    ? [
        '<div class="chain-node failed"><span class="chain-node-dot"></span><span><strong>' +
          escapeHtml(failed.name) +
          '</strong><small>Failed asset · ' +
          escapeHtml(failed.owner) +
          "</small></span></div>",
      ]
        .concat(
          impacts.map(
            (item) =>
              '<div class="chain-arrow">↓ <span>' +
              item.depth +
              " hop" +
              (item.depth === 1 ? "" : "s") +
              '</span></div><div class="chain-node exposed"><span class="chain-node-dot"></span><span><strong>' +
              escapeHtml(item.asset.name) +
              '</strong><small>Downstream exposure · ' +
              escapeHtml(item.asset.owner) +
              "</small></span></div>",
          ),
        )
        .join("")
    : ""
  document.querySelector("#impact-chain").innerHTML = chain
  document.querySelector("#incident-explanation").textContent = failed
    ? "Failure of " +
      failed.name +
      " reaches " +
      impacts.length +
      " downstream " +
      (impacts.length === 1 ? "asset" : "assets") +
      " through " +
      maxDepth +
      " dependency " +
      (maxDepth === 1 ? "hop" : "hops") +
      "."
    : "Select a failed asset to see how the graph responds."
}

function biaFor(assetId) {
  return state.bia.find((record) => record.serviceId === assetId)
}

function recoveryQueue() {
  const pending = [...state.assets]
  const ordered = []
  let hasCycle = false
  while (pending.length) {
    let ready = pending.filter((asset) =>
      (asset.dependsOn ?? []).every(
        (dependency) =>
          ordered.some((item) => item.id === dependency) || !assetById(dependency),
      ),
    )
    if (!ready.length) {
      hasCycle = true
      ready = [...pending]
    }
    ready.sort((left, right) => {
      const scoreDiff = (biaFor(right.id)?.score ?? 0) - (biaFor(left.id)?.score ?? 0)
      if (scoreDiff) return scoreDiff
      const criticalityDiff =
        impactRank(right.criticality) - impactRank(left.criticality)
      return criticalityDiff || left.id.localeCompare(right.id)
    })
    const next = ready[0]
    pending.splice(pending.indexOf(next), 1)
    ordered.push(next)
  }
  return { assets: ordered, hasCycle }
}

function recoveryEstimate(asset) {
  return Math.max(15, Math.round((biaFor(asset.id)?.rto ?? 30) / 2))
}

function renderRecovery() {
  const queue = recoveryQueue()
  const total = queue.assets.reduce((sum, asset) => sum + recoveryEstimate(asset), 0)
  document.querySelector("#nav-recovery-count").textContent = queue.assets.length
  document.querySelector("#recovery-total").textContent = total + " min total"
  document.querySelector("#recovery-window").textContent = total + "m"
  const utilization = Math.round((total / 180) * 100)
  document.querySelector("#recovery-progress").style.width = Math.min(100, utilization) + "%"
  document.querySelector("#recovery-utilization").textContent = utilization + "%"
  document.querySelector("#recovery-table").innerHTML = queue.assets
    .map((asset, index) => {
      const level = assetImpactLevel(asset)
      const status = queue.hasCycle ? "Review dependency" : index === 0 ? "Next" : "Queued"
      const statusClass = queue.hasCycle ? "review" : index === 0 ? "ready" : "queued"
      return (
        "<tr>" +
        '<td><span class="order-number">' +
        String(index + 1).padStart(2, "0") +
        "</span></td>" +
        '<td><div class="asset-cell"><span class="asset-icon ' +
        (asset.type === "Component" ? "component" : "") +
        '">✦</span><span><strong>' +
        escapeHtml(asset.name) +
        "</strong><small>" +
        escapeHtml(asset.type) +
        "</small></span></div></td>" +
        '<td><span class="priority-label ' +
        criticalityClass(level) +
        '"><span class="status-dot ' +
        (level === "Critical" ? "red" : level === "High" ? "amber" : "blue") +
        '"></span>' +
        escapeHtml(level) +
        "</span></td><td>" +
        recoveryEstimate(asset) +
        "m</td><td>" +
        escapeHtml(asset.owner) +
        '</td><td><span class="status-pill ' +
        statusClass +
        '">' +
        escapeHtml(status) +
        "</span></td></tr>"
      )
    })
    .join("")
}

const DRILL_NEXT_EVENTS = [
  {
    time: "09:31",
    actor: "Platform team",
    action: "Step completed",
    detail: "restore-api",
    kind: "complete",
  },
  {
    time: "09:35",
    actor: "Continuity operator",
    action: "Drill finished",
    detail: "All planned steps succeeded",
    kind: "finish",
  },
]

function renderDrill() {
  const events = state.drill?.events ?? []
  const totalEvents = DEFAULT_STATE.drill.events.length + DRILL_NEXT_EVENTS.length
  const coverage = Math.round((events.length / totalEvents) * 100)
  const completedSteps = events.filter((event) => event.kind === "complete").length
  const approvals = events.filter((event) => event.kind === "approval").length
  const lastActor = events.length ? events[events.length - 1].actor : "—"
  document.querySelector("#nav-drill-count").textContent = events.length
  document.querySelector("#drill-progress-score").textContent = events.length
  document.querySelector("#drill-progress-label").textContent = coverage + "%"
  document.querySelector("#drill-progress").style.width = coverage + "%"
  document.querySelector("#drill-step-count").textContent = completedSteps + "/3"
  document.querySelector("#drill-approval-count").textContent = approvals
  document.querySelector("#drill-last-actor").textContent = lastActor
  document.querySelector("#drill-status").innerHTML =
    '<span class="status-dot ' +
    (state.drill?.status === "Completed" ? "green" : "amber") +
    '"></span>' +
    escapeHtml(state.drill?.status ?? "In progress")
  document.querySelector("#drill-timeline").innerHTML = events
    .map(
      (event) =>
        '<div class="timeline-item ' +
        escapeHtml(event.kind) +
        '"><span class="timeline-marker">' +
        (event.kind === "approval" ? "✓" : event.kind === "complete" ? "●" : "·") +
        '</span><div class="timeline-content"><time>' +
        escapeHtml(event.time) +
        '</time><strong>' +
        escapeHtml(event.action) +
        '</strong><p>' +
        escapeHtml(event.detail) +
        " · " +
        escapeHtml(event.actor) +
        "</p></div></div>",
    )
    .join("")
  document.querySelector("#drill-empty").classList.toggle("hidden", events.length > 0)
  const button = document.querySelector("#record-drill-event")
  const complete = events.length >= totalEvents
  button.disabled = complete
  button.innerHTML = complete ? "✓ Drill complete" : "<span>＋</span> Record next event"
}

function buildEvidenceReport() {
  const serviceCount = state.assets.filter((asset) => asset.type === "Service").length
  const assessedServices = state.bia.filter(
    (record) => assetById(record.serviceId)?.type === "Service",
  ).length
  const recovery = recoveryQueue()
  const drillEvents = state.drill?.events ?? []
  const releaseChecks = [
    {
      id: "inventory",
      label: "Inventory captured",
      passed: state.assets.length > 0,
    },
    {
      id: "bia",
      label: "BIA coverage complete",
      passed: serviceCount > 0 && assessedServices === serviceCount,
    },
    {
      id: "dependencies",
      label: "Dependency edges are mapped",
      passed: state.assets.every((asset) => Array.isArray(asset.dependsOn)),
    },
    {
      id: "drill",
      label: "Drill evidence captured",
      passed: drillEvents.length > 0,
    },
  ]
  return {
    schemaVersion: "1.0",
    product: "ContinuityForge",
    generatedAt: new Date().toISOString(),
    summary: {
      assetCount: state.assets.length,
      serviceCount,
      biaCoverage: serviceCount ? Math.round((assessedServices / serviceCount) * 100) : 0,
      dependencyCount: state.assets.reduce(
        (total, asset) => total + (asset.dependsOn?.length ?? 0),
        0,
      ),
      recoveryTotalMinutes: recovery.assets.reduce(
        (total, asset) => total + recoveryEstimate(asset),
        0,
      ),
      drillEventCount: drillEvents.length,
    },
    inventory: state.assets.map((asset) => ({ ...asset })),
    businessImpact: state.bia.map((record) => ({ ...record })),
    incidentImpact: state.assets.map((asset) => {
      const impacts = dependentImpact(asset.id)
      return {
        failedAsset: asset.id,
        affectedAssets: impacts.map((item) => item.asset.id),
        longestPath: impacts.reduce((max, item) => Math.max(max, item.depth), 0),
        highestExposure:
          impacts.reduce(
            (level, item) =>
              impactRank(assetImpactLevel(item.asset)) > impactRank(level)
                ? assetImpactLevel(item.asset)
                : level,
            "",
          ) || null,
      }
    }),
    recoveryPlan: {
      hasDependencyCycle: recovery.hasCycle,
      orderedAssets: recovery.assets.map((asset, index) => ({
        order: index + 1,
        assetId: asset.id,
        estimateMinutes: recoveryEstimate(asset),
        owner: asset.owner,
        priority: assetImpactLevel(asset),
      })),
    },
    drill: {
      status: state.drill?.status ?? "In progress",
      timeline: drillEvents.map((event) => ({ ...event })),
    },
    releaseChecks: {
      ready: releaseChecks.every((check) => check.passed),
      checks: releaseChecks,
    },
  }
}

function exportEvidenceReport() {
  if (typeof Blob === "undefined" || typeof URL?.createObjectURL !== "function") {
    showToast("Evidence export is unavailable in this browser.", "error")
    return
  }
  const report = buildEvidenceReport()
  const blob = new Blob([JSON.stringify(report, null, 2)], {
    type: "application/json",
  })
  const link = document.createElement("a")
  const date = new Date().toISOString().slice(0, 10)
  const objectUrl = URL.createObjectURL(blob)
  link.href = objectUrl
  link.download = "continuityforge-evidence-" + date + ".json"
  document.body.appendChild(link)
  link.click()
  link.remove()
  URL.revokeObjectURL(objectUrl)
  showToast("Evidence report downloaded")
}

function renderMetrics() {
  const critical = state.assets.filter(
    (asset) => asset.criticality === "Critical",
  ).length
  const dependencies = state.assets.reduce(
    (total, asset) => total + (asset.dependsOn?.length ?? 0),
    0,
  )
  const coverage = state.assets.length
    ? Math.round((state.bia.length / state.assets.length) * 100)
    : 0
  const ownerCount = state.assets.filter((asset) => asset.owner.trim()).length
  const ownerRatio = state.assets.length
    ? Math.round((ownerCount / state.assets.length) * 100)
    : 0
  const signalScore = Math.min(100, Math.round(coverage * 0.7 + ownerRatio * 0.3))

  document.querySelector("#metric-assets").textContent = state.assets.length
  document.querySelector("#metric-critical").textContent = critical
  document.querySelector("#metric-dependencies").textContent = dependencies
  document.querySelector("#metric-coverage").textContent = coverage + "%"
  document.querySelector("#nav-asset-count").textContent = state.assets.length
  document.querySelector("#nav-bia-count").textContent = state.bia.length
  document.querySelector("#nav-recovery-count").textContent = state.assets.length
  document.querySelector("#nav-drill-count").textContent = state.drill?.events?.length ?? 0
  document.querySelector("#owner-count").textContent =
    ownerCount + "/" + state.assets.length
  document.querySelector("#bia-count").textContent =
    state.bia.length + "/" + state.assets.length
  document.querySelector("#dependency-count").textContent = dependencies
  document.querySelector("#signal-score").textContent = signalScore
  document.querySelector("#signal-progress").style.width = signalScore + "%"
  document.querySelector("#signal-label").textContent =
    signalScore >= 85 ? "Ready" : signalScore >= 65 ? "Building" : "Starting"
}

function renderInventory() {
  const query = document.querySelector("#inventory-search").value.trim().toLowerCase()
  const visible = state.assets.filter((asset) =>
    [asset.name, asset.id, asset.type, asset.owner, asset.criticality]
      .join(" ")
      .toLowerCase()
      .includes(query),
  )
  const table = document.querySelector("#inventory-table")
  table.innerHTML = visible
    .map((asset) => {
      const dependencies = asset.dependsOn?.length
        ? asset.dependsOn
            .map((id) => "<span>" + escapeHtml(id) + "</span>")
            .join("")
        : '<span class="muted-cell">None</span>'
      const icon = asset.type === "Component" ? "◇" : "✦"
      const typeLabel =
        asset.type === "Component" ? "Component" : "Service"
      const dot =
        criticalityClass(asset.criticality) === "critical"
          ? "red"
          : criticalityClass(asset.criticality) === "high"
            ? "amber"
            : criticalityClass(asset.criticality) === "low"
              ? "green"
              : "blue"
      return (
        "<tr>" +
        '<td><div class="asset-cell">' +
        '<span class="asset-icon ' +
        (asset.type === "Component" ? "component" : "") +
        '">' +
        icon +
        "</span>" +
        "<span><strong>" +
        escapeHtml(asset.name) +
        "</strong><small>" +
        escapeHtml(asset.id) +
        "</small></span></div></td>" +
        '<td><span class="type-pill">' +
        typeLabel +
        "</span></td>" +
        "<td>" +
        escapeHtml(asset.owner) +
        "</td>" +
        '<td><span class="criticality-pill ' +
        criticalityClass(asset.criticality) +
        '"><span class="status-dot ' +
        dot +
        '"></span>' +
        escapeHtml(asset.criticality) +
        "</span></td>" +
        '<td><div class="dependency-list">' +
        dependencies +
        "</div></td>" +
        '<td><button class="row-menu" type="button" data-remove-asset="' +
        escapeHtml(asset.id) +
        '" aria-label="删除 ' +
        escapeHtml(asset.name) +
        '">⋯</button></td></tr>'
      )
    })
    .join("")
  document.querySelector("#inventory-empty").classList.toggle("hidden", visible.length > 0)
}

function renderBia() {
  const rows = state.bia
    .map((record) => {
      const service = assetById(record.serviceId)
      if (!service) return ""
      const level = impactLevel(record.score)
      const dot =
        level === "Critical"
          ? "red"
          : level === "High"
            ? "amber"
            : level === "Low"
              ? "green"
              : "blue"
      return (
        "<tr>" +
        '<td><div class="asset-cell"><span class="asset-icon">✦</span>' +
        "<span><strong>" +
        escapeHtml(service.name) +
        "</strong><small>" +
        escapeHtml(service.owner) +
        "</small></span></div></td>" +
        '<td><strong class="score-value">' +
        record.score +
        "</strong></td>" +
        '<td><span class="criticality-pill ' +
        criticalityClass(level) +
        '"><span class="status-dot ' +
        dot +
        '"></span>' +
        level +
        "</span></td>" +
        "<td>" +
        formatMinutes(record.rto) +
        "</td><td>" +
        formatMinutes(record.rpo) +
        "</td><td>" +
        formatMinutes(record.downtime) +
        "</td></tr>"
      )
    })
    .join("")
  document.querySelector("#bia-table").innerHTML = rows
  document.querySelector("#bia-empty").classList.toggle("hidden", state.bia.length > 0)

  const select = document.querySelector("#bia-service")
  const current = select.value
  select.innerHTML = state.assets
    .filter((asset) => asset.type === "Service")
    .map(
      (asset) =>
        '<option value="' +
        escapeHtml(asset.id) +
        '">' +
        escapeHtml(asset.name) +
        "</option>",
    )
    .join("")
  if (assetById(current)?.type === "Service") select.value = current
  if (!select.value && select.options.length) select.selectedIndex = 0
  loadBiaForm()
}

function loadBiaForm() {
  const serviceId = document.querySelector("#bia-service").value
  const record = state.bia.find((item) => item.serviceId === serviceId)
  document.querySelector("#bia-score").value = record?.score ?? 70
  document.querySelector("#bia-rto").value = record?.rto ?? 60
  document.querySelector("#bia-rpo").value = record?.rpo ?? 30
  document.querySelector("#bia-downtime").value = record?.downtime ?? 240
}

function renderAll() {
  renderMetrics()
  renderInventory()
  renderBia()
  renderIncident()
  renderRecovery()
  renderDrill()
}

function showToast(message, tone = "success") {
  const toast = document.querySelector("#toast")
  toast.textContent = message
  toast.dataset.tone = tone
  toast.classList.add("visible")
  window.clearTimeout(toastTimer)
  toastTimer = window.setTimeout(() => toast.classList.remove("visible"), 2800)
}

function switchView(view) {
  document.querySelectorAll("[data-view-target]").forEach((button) => {
    button.classList.toggle("active", button.dataset.viewTarget === view)
  })
  document.querySelectorAll(".workspace-view").forEach((section) => {
    section.classList.toggle("active", section.dataset.view === view)
  })
  const metadata = {
    inventory: {
      breadcrumb: "Inventory",
      kicker: "SYSTEM INVENTORY",
      title: "Know what keeps the business running.",
      description:
        "Keep services, components, ownership, and dependencies ready for the next continuity decision.",
      action: "<span>＋</span> Add asset",
    },
    bia: {
      breadcrumb: "Business impact",
      kicker: "BUSINESS IMPACT ANALYSIS",
      title: "Make recovery targets explicit.",
      description: "Translate service criticality into recovery targets your team can act on.",
      action: "<span>＋</span> Assess service",
    },
    incident: {
      breadcrumb: "Incident impact",
      kicker: "INCIDENT IMPACT",
      title: "See where a failure travels.",
      description: "Trace downstream exposure before the incident reaches the next team.",
      action: "<span>⌁</span> Simulate impact",
    },
    recovery: {
      breadcrumb: "Recovery plans",
      kicker: "RECOVERY PLANNING",
      title: "Put the next recovery action first.",
      description: "Use BIA scores and dependency order to keep the recovery window visible.",
      action: "<span>↻</span> Recalculate",
    },
    drills: {
      breadcrumb: "Drill log",
      kicker: "DRILL EVIDENCE",
      title: "Turn rehearsals into evidence.",
      description: "Keep each action, approval, and outcome ready for the next review.",
      action: "<span>＋</span> Record event",
    },
  }
  const current = metadata[view] ?? metadata.inventory
  document.querySelector("#breadcrumb-current").textContent = current.breadcrumb
  document.querySelector("#page-kicker").textContent = current.kicker
  document.querySelector("#page-title").textContent = current.title
  document.querySelector("#page-description").textContent = current.description
  document.querySelector("#primary-action").innerHTML = current.action
}

function openAssetModal() {
  const modal = document.querySelector("#asset-modal")
  document.querySelector("#asset-form").reset()
  if (typeof modal.showModal === "function") modal.showModal()
  else modal.setAttribute("open", "")
  document.querySelector("#asset-name").focus()
}

function closeAssetModal() {
  const modal = document.querySelector("#asset-modal")
  if (typeof modal.close === "function" && modal.open) modal.close()
  else modal.removeAttribute("open")
}

document.querySelector("#close-asset").addEventListener("click", closeAssetModal)
document.querySelector("#cancel-asset").addEventListener("click", closeAssetModal)

document.querySelectorAll("[data-view-target]").forEach((button) => {
  button.addEventListener("click", () => switchView(button.dataset.viewTarget))
})

document.querySelector("#primary-action").addEventListener("click", () => {
  const activeView = document.querySelector(".workspace-view.active")?.dataset.view
  if (activeView === "inventory") openAssetModal()
  else if (activeView === "bia") document.querySelector("#bia-service").focus()
  else if (activeView === "incident") {
    renderIncident()
    showToast("Impact simulation refreshed")
  } else if (activeView === "recovery") {
    renderRecovery()
    showToast("Recovery order recalculated")
  } else if (activeView === "drills") {
    recordNextDrillEvent()
  }
})

document.querySelector("#export-report").addEventListener("click", exportEvidenceReport)

document.querySelector("#inventory-search").addEventListener("input", renderInventory)
document.querySelector("#clear-search").addEventListener("click", () => {
  document.querySelector("#inventory-search").value = ""
  renderInventory()
})

document.querySelector("#inventory-table").addEventListener("click", (event) => {
  const button = event.target.closest("[data-remove-asset]")
  if (!button) return
  const id = button.dataset.removeAsset
  const asset = assetById(id)
  if (!asset) return
  state.assets = state.assets.filter((item) => item.id !== id)
  state.assets = state.assets.map((item) => ({
    ...item,
    dependsOn: (item.dependsOn ?? []).filter((dependency) => dependency !== id),
  }))
  state.bia = state.bia.filter((record) => record.serviceId !== id)
  persistState()
  renderAll()
  showToast(asset.name + " removed from inventory")
})

document.querySelector("#asset-form").addEventListener("submit", (event) => {
  event.preventDefault()
  const name = document.querySelector("#asset-name").value.trim()
  const owner = document.querySelector("#asset-owner").value.trim()
  const type = document.querySelector("#asset-type").value
  const criticality = document.querySelector("#asset-criticality").value
  if (!name || !owner) return
  let id = slugify(name)
  let suffix = 2
  while (assetById(id)) {
    id = slugify(name) + "-" + suffix
    suffix += 1
  }
  state.assets.push({ id, name, type, owner, criticality, dependsOn: [] })
  persistState()
  renderAll()
  closeAssetModal()
  showToast(name + " added to inventory")
})

document.querySelector("#bia-service").addEventListener("change", loadBiaForm)

document.querySelector("#bia-form").addEventListener("submit", (event) => {
  event.preventDefault()
  const serviceId = document.querySelector("#bia-service").value
  const score = Number(document.querySelector("#bia-score").value)
  const rto = Number(document.querySelector("#bia-rto").value)
  const rpo = Number(document.querySelector("#bia-rpo").value)
  const downtime = Number(document.querySelector("#bia-downtime").value)
  if (
    !serviceId ||
    !Number.isFinite(score) ||
    score < 0 ||
    score > 100 ||
    !Number.isFinite(rto) ||
    !Number.isFinite(rpo) ||
    !Number.isFinite(downtime) ||
    downtime <= 0 ||
    rto > downtime ||
    rpo > downtime
  ) {
    showToast("Check the BIA values and downtime limits.", "error")
    return
  }
  const record = { serviceId, score, rto, rpo, downtime }
  const index = state.bia.findIndex((item) => item.serviceId === serviceId)
  if (index >= 0) state.bia[index] = record
  else state.bia.push(record)
  persistState()
  renderAll()
  showToast("BIA assessment saved")
})

document.querySelector("#incident-asset").addEventListener("change", renderIncident)
document.querySelector("#simulate-incident").addEventListener("click", () => {
  renderIncident()
  showToast("Impact simulation refreshed")
})
document.querySelector("#recalculate-recovery").addEventListener("click", () => {
  renderRecovery()
  showToast("Recovery order recalculated")
})

function recordNextDrillEvent() {
  const index = (state.drill?.events?.length ?? 0) - DEFAULT_STATE.drill.events.length
  const next = DRILL_NEXT_EVENTS[index]
  if (!next) {
    showToast("Drill timeline is complete", "error")
    return
  }
  state.drill.events.push({ ...next })
  if (next.kind === "finish") state.drill.status = "Completed"
  persistState()
  renderAll()
  showToast("Drill event recorded")
}

document.querySelector("#record-drill-event").addEventListener("click", recordNextDrillEvent)

renderAll()
