import assert from "node:assert/strict"
import { readFileSync } from "node:fs"
import { analyze_workspace } from "../../web/engine.mjs"
import { analyzeScenario, ganttMarkup, graphMarkup, toEngineRequest, validateScenario } from "../../web/scheduling.js"

function preset(name) {
  return JSON.parse(readFileSync(new URL(`../../web/scenarios/${name}.json`, import.meta.url), "utf8"))
}

const incident = preset("incident")
const ci = preset("ci")
const incidentResult = analyzeScenario(incident, analyze_workspace)
const ciResult = analyzeScenario(ci, analyze_workspace)
assert.equal(incidentResult.optimized.makespan, 35)
assert.equal(incidentResult.bottleneck_resource, "compute-team")
assert.deepEqual(incidentResult.affected.map((item) => item.asset_id), ["checkout-api"])
assert.equal(ciResult.baselines[0].makespan, 40)
assert.equal(ciResult.optimized.makespan, 35)
assert.deepEqual(ciResult.critical_path, ["compile-api", "unit-api", "integration", "package"])
assert.equal(ciResult.critical_path_duration, 35)
assert.ok(ciResult.baselines.every((item) => item.elapsed_ms >= 0))
assert.deepEqual(toEngineRequest(ci).assets[0].depends_on, [])
const escapeHtml = (value) => String(value).replaceAll("&", "&amp;").replaceAll("<", "&lt;")
assert.match(graphMarkup(ci, ciResult, escapeHtml), /class="graph-node critical"/)
assert.match(ganttMarkup(ci, ciResult.optimized, ciResult, escapeHtml), /Compile API/)
const escapedScenario = { ...ci, tasks: ci.tasks.map((task) =>
  task.id === "lint" ? { ...task, label: "<script>" } : task,
) }
assert.doesNotMatch(graphMarkup(escapedScenario, ciResult, escapeHtml), /<script>/)

assert.throws(() => validateScenario({ ...ci, schemaVersion: "2.0" }), /version 1.0/)
assert.throws(() => validateScenario({ ...ci, tasks: [ci.tasks[0], ci.tasks[0]] }), /unique/)
assert.throws(() => analyzeScenario({
  ...ci,
  tasks: [{ ...ci.tasks[0], dependsOn: ["missing"] }],
}, analyze_workspace), /unknown dependency/)

process.stdout.write("Scheduling workspace scenarios passed\n")
