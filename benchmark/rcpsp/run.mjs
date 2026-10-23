import { execFileSync } from "node:child_process"
import { mkdirSync, readFileSync, writeFileSync } from "node:fs"
import { resolve, dirname, join } from "node:path"
import { fileURLToPath, pathToFileURL } from "node:url"

const root = resolve(dirname(fileURLToPath(import.meta.url)), "../..")
const options = {
  publicDir: null,
  outputDir: join(root, "benchmark/rcpsp/results"),
  python: process.env.RCPSP_PYTHON ?? "python",
  repeats: 3,
  timeLimit: 5,
  budget: 30,
}
for (let i = 2; i < process.argv.length; i += 2) {
  const key = process.argv[i]
  const value = process.argv[i + 1]
  if (!value) throw new Error(`missing value for ${key}`)
  if (key === "--public-dir") options.publicDir = resolve(value)
  else if (key === "--output-dir") options.outputDir = resolve(value)
  else if (key === "--python") options.python = value
  else if (key === "--repeats") options.repeats = Number(value)
  else if (key === "--time-limit") options.timeLimit = Number(value)
  else if (key === "--budget") options.budget = Number(value)
  else throw new Error(`unknown option ${key}`)
}
if (!Number.isInteger(options.repeats) || options.repeats < 1 ||
    !Number.isInteger(options.budget) || options.budget < 0 ||
    !Number.isFinite(options.timeLimit) || options.timeLimit <= 0) {
  throw new Error("invalid repeats, time limit, or search budget")
}
const { solve_json, validate_json } = await import(pathToFileURL(
  join(root, "_build/js/release/build/cmd/rcpsp/rcpsp.js"),
).href)

const algorithms = [
  "stable-topological", "critical-path", "recovery-heuristic",
  "budgeted-local-search",
]
const cases = ["ci", "recovery", "project"].map((name) => ({
  id: name,
  source: "synthetic-teaching",
  path: join(root, `examples/rcpsp/${name}.json`),
  official: null,
}))
if (options.publicDir) {
  const selection = JSON.parse(readFileSync(join(root, "benchmark/psplib/selection.json"), "utf8"))
  for (const item of selection.instances) cases.push({
    id: item.id,
    source: "PSPLIB",
    path: join(options.publicDir, `${item.id}.json`),
    official: item,
  })
}

function checkCandidate(problemText, result) {
  if (!["FEASIBLE", "OPTIMAL"].includes(result.status)) return { feasible: false, error: null }
  const checked = JSON.parse(validate_json(problemText, JSON.stringify(result)))
  return { feasible: checked.ok === true, error: checked.error ?? null }
}

function runMoonBit(problemText, algorithm, budget) {
  const result = JSON.parse(solve_json(problemText, algorithm, budget))
  if (result.error) throw new Error(`${algorithm}: ${result.error}`)
  return result
}

function runReference(path) {
  const stdout = execFileSync(options.python, [
    join(root, "benchmark/reference/ortools_rcpsp.py"), path,
    "--time-limit", String(options.timeLimit),
  ], { cwd: root, encoding: "utf8", maxBuffer: 10_000_000 })
  return JSON.parse(stdout)
}

function loadRatio(problem, makespan) {
  if (makespan === null || makespan === undefined || makespan === 0) return null
  const capacity = problem.resources.reduce((sum, resource) => sum + resource.capacity, 0)
  if (capacity === 0) return null
  const work = problem.tasks.reduce((sum, task) => sum + task.duration *
    task.demands.reduce((demand, item) => demand + item.amount, 0), 0)
  return work / (capacity * makespan)
}

const rows = []
const ablation = []
let invalid = 0
for (const entry of cases) {
  const problemText = readFileSync(entry.path, "utf8")
  const problem = JSON.parse(problemText)
  const n = problem.tasks.length
  for (let repeat = 1; repeat <= options.repeats; repeat++) {
    const reference = runReference(entry.path)
    const referenceCheck = checkCandidate(problemText, reference)
    if (["FEASIBLE", "OPTIMAL"].includes(reference.status) && !referenceCheck.feasible) invalid++
    const outputs = algorithms.map((algorithm) => {
      const result = runMoonBit(problemText, algorithm, options.budget)
      const check = checkCandidate(problemText, result)
      if (result.status === "FEASIBLE" && !check.feasible) invalid++
      return { algorithm, result, check }
    })
    const noSearch = runMoonBit(problemText, "budgeted-local-search", 0)
    const noSearchCheck = checkCandidate(problemText, noSearch)
    if (noSearch.status === "FEASIBLE" && !noSearchCheck.feasible) invalid++
    const full = outputs.find(({ algorithm }) => algorithm === "budgeted-local-search").result
    ablation.push({
      case_id: entry.id, source: entry.source, repeat,
      no_local_search_makespan: noSearch.makespan ?? null,
      full_makespan: full.makespan ?? null,
      delta_full_minus_no_search: full.makespan !== undefined && noSearch.makespan !== undefined
        ? full.makespan - noSearch.makespan : null,
      no_search_candidates: noSearch.candidates_evaluated,
      full_candidates: full.candidates_evaluated,
      no_search_valid: noSearchCheck.feasible,
    })
    const proven = entry.official?.official_optimal ??
      (reference.status === "OPTIMAL" ? reference.makespan : null)
    const bound = Math.max(
      entry.official?.official_lower_bound ?? 0,
      reference.lower_bound ?? 0,
    ) || null
    for (const { algorithm, result, check } of [
      ...outputs,
      { algorithm: "ortools-cp-sat", result: reference, check: referenceCheck },
    ]) {
      const makespan = check.feasible ? result.makespan : null
      if (makespan !== null && proven !== null && makespan < proven) invalid++
      rows.push({
        case_id: entry.id, source: entry.source, repeat, tasks: n,
        resources: problem.resources.length, time_unit: problem.time_unit,
        algorithm, status: result.status, feasible: check.feasible,
        validation_error: check.error, makespan,
        lower_bound: result.lower_bound ?? null,
        best_available_bound: bound, proven_optimum: proven,
        official_optimal: entry.official?.official_optimal ?? null,
        official_upper_bound: entry.official?.official_upper_bound ?? null,
        official_upper_bound_gap_pct: makespan !== null && entry.official?.official_upper_bound > 0
          ? 100 * (makespan - entry.official.official_upper_bound) / entry.official.official_upper_bound : null,
        reference_status: reference.status,
        reference_feasible_makespan: referenceCheck.feasible ? reference.makespan : null,
        optimality_gap_pct: makespan !== null && proven > 0
          ? 100 * (makespan - proven) / proven : null,
        bound_gap_pct: makespan !== null && bound > 0
          ? 100 * (makespan - bound) / bound : null,
        reference_feasible_gap_pct: makespan !== null && referenceCheck.feasible && reference.makespan > 0
          ? 100 * (makespan - reference.makespan) / reference.makespan : null,
        resource_utilization: loadRatio(problem, makespan),
        elapsed_ms: result.elapsed_ms,
        time_limit_seconds: algorithm === "ortools-cp-sat" ? options.timeLimit : null,
        search_budget: algorithm === "budgeted-local-search" ? options.budget : null,
        candidates_evaluated: result.candidates_evaluated,
        accepted_moves: result.accepted_moves,
        schedule: result.schedule,
      })
    }
  }
  process.stderr.write(`${entry.id}: ${options.repeats} repeats complete\n`)
}

function csv(items, columns) {
  const cell = (value) => {
    if (value === null || value === undefined) return ""
    const text = String(value)
    return /[",\n]/.test(text) ? `"${text.replaceAll('"', '""')}"` : text
  }
  return [columns.join(","), ...items.map((item) => columns.map((column) => cell(item[column])).join(","))].join("\n") + "\n"
}

const summary = []
for (const entry of cases) {
  for (const algorithm of [...algorithms, "ortools-cp-sat"]) {
    const subset = rows.filter((row) => row.case_id === entry.id && row.algorithm === algorithm)
    const feasible = subset.filter((row) => row.feasible)
    const mean = (items, field) => items.length
      ? items.reduce((sum, item) => sum + item[field], 0) / items.length : null
    summary.push({
      case_id: entry.id, source: entry.source, tasks: subset[0].tasks,
      algorithm, repeats: subset.length,
      success_rate: feasible.length / subset.length,
      mean_makespan: mean(feasible, "makespan"),
      mean_elapsed_ms: mean(subset, "elapsed_ms"),
      mean_resource_utilization: mean(feasible, "resource_utilization"),
      mean_optimality_gap_pct: mean(feasible.filter((row) => row.optimality_gap_pct !== null), "optimality_gap_pct"),
      proven_optimum: subset[0].proven_optimum,
      best_available_bound: subset[0].best_available_bound,
    })
  }
}

function chart(field, title, unit) {
  const names = [...algorithms, "ortools-cp-sat"]
  const colors = ["#4568dc", "#25a27b", "#d88027", "#9b59b6", "#374151"]
  const width = 1100, height = 100 + cases.length * 105
  const max = Math.max(1, ...summary.map((row) => row[field] ?? 0))
  const bars = summary.map((row) => {
    const caseIndex = cases.findIndex((entry) => entry.id === row.case_id)
    const algIndex = names.indexOf(row.algorithm)
    const y = 65 + caseIndex * 105 + algIndex * 17
    const caseMax = field === "mean_makespan"
      ? Math.max(1, ...summary.filter((item) => item.case_id === row.case_id)
        .map((item) => item[field] ?? 0)) : max
    const size = row[field] === null ? 0 : 650 * row[field] / caseMax
    return `<rect x="285" y="${y}" width="${size.toFixed(1)}" height="13" fill="${colors[algIndex]}"/>` +
      `<text x="${(293 + size).toFixed(1)}" y="${y + 11}" font-size="11">${row[field] === null ? "n/a" : row[field].toFixed(2)}</text>`
  }).join("\n")
  const labels = cases.map((entry, i) => `<text x="8" y="${110 + i * 105}" font-size="13">${entry.id}</text>`).join("\n")
  const legend = names.map((name, i) => `<text x="${10 + i * 210}" y="40" fill="${colors[i]}" font-size="12">${name}</text>`).join("\n")
  return `<svg xmlns="http://www.w3.org/2000/svg" width="${width}" height="${height}" viewBox="0 0 ${width} ${height}"><rect width="100%" height="100%" fill="white"/><text x="10" y="20" font-size="16" font-weight="bold">${title} (${unit})</text>${legend}${labels}${bars}</svg>\n`
}

mkdirSync(options.outputDir, { recursive: true })
writeFileSync(join(options.outputDir, "raw.json"), JSON.stringify({
  metadata: {
    node: process.version, platform: process.platform, arch: process.arch,
    moon: execFileSync("moon", ["version"], { cwd: root, encoding: "utf8" }).trim(),
    repeats: options.repeats, search_budget: options.budget,
    cp_sat_time_limit_seconds: options.timeLimit,
    included_public_instances: Boolean(options.publicDir),
  }, rows, ablation,
}, null, 2) + "\n")
const rowColumns = Object.keys(rows[0]).filter((key) => key !== "schedule")
writeFileSync(join(options.outputDir, "raw.csv"), csv(rows, rowColumns))
writeFileSync(join(options.outputDir, "summary.csv"), csv(summary, Object.keys(summary[0])))
writeFileSync(join(options.outputDir, "ablation.csv"), csv(ablation, Object.keys(ablation[0])))
writeFileSync(join(options.outputDir, "makespan.svg"), chart("mean_makespan", "Mean makespan, each case scaled separately", "numeric labels in problem units"))
writeFileSync(join(options.outputDir, "runtime.svg"), chart("mean_elapsed_ms", "Mean solver runtime", "ms"))
if (invalid) {
  process.stderr.write(`${invalid} invalid results or bound contradictions recorded\n`)
  process.exitCode = 1
}
