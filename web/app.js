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
}

const copyDefaultState = () => ({
  assets: DEFAULT_STATE.assets.map((asset) => ({
    ...asset,
    dependsOn: [...asset.dependsOn],
  })),
  bia: DEFAULT_STATE.bia.map((record) => ({ ...record })),
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
    return parsed
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
  const inventory = view === "inventory"
  document.querySelector("#breadcrumb-current").textContent = inventory
    ? "Inventory"
    : "Business impact"
  document.querySelector("#page-kicker").textContent = inventory
    ? "SYSTEM INVENTORY"
    : "BUSINESS IMPACT ANALYSIS"
  document.querySelector("#page-title").textContent = inventory
    ? "Know what keeps the business running."
    : "Make recovery targets explicit."
  document.querySelector("#page-description").textContent = inventory
    ? "Keep services, components, ownership, and dependencies ready for the next continuity decision."
    : "Translate service criticality into recovery targets your team can act on."
  document.querySelector("#primary-action").innerHTML = inventory
    ? "<span>＋</span> Add asset"
    : "<span>＋</span> Assess service"
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
  if (document.querySelector("#inventory-view").classList.contains("active")) {
    openAssetModal()
  } else {
    document.querySelector("#bia-service").focus()
  }
})

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

renderAll()
