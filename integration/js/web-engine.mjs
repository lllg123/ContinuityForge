import assert from "node:assert/strict"
import { analyze_workspace } from "../../web/engine.mjs"

const request = {
  assets: [
    { id: "api", asset_type: "Service", depends_on: ["db"], duration: 20, resource: "platform", priority: 2 },
    { id: "db", asset_type: "Component", depends_on: [], duration: 10, resource: "data", priority: 3 },
    { id: "worker", asset_type: "Service", depends_on: ["api"], duration: 15, resource: "platform", priority: 1 },
  ],
  failed_asset_id: "db",
  target_window: 45,
  search_budget: 10,
}

const result = JSON.parse(analyze_workspace(JSON.stringify(request)))
assert.equal(result.ok, true)
assert.deepEqual(result.result.dependency_order, ["db", "api", "worker"])
assert.deepEqual(result.result.affected.map((item) => item.path), [
  ["db", "api"],
  ["db", "api", "worker"],
])
assert.equal(result.result.optimized.makespan, 45)
assert.equal(result.result.lower_bound, 45)
assert.deepEqual(result.result.critical_path, ["db", "api", "worker"])
assert.equal(result.result.critical_path_duration, 45)
assert.ok(result.result.optimized.elapsed_ms >= 0)
assert.equal(result.result.bottleneck_load, 35)
assert.equal(result.result.target_met, true)
assert.deepEqual(result.result.baselines.map((item) => item.makespan), [45, 45, 45])

const invalid = JSON.parse(analyze_workspace(JSON.stringify({
  ...request,
  assets: [{ ...request.assets[0], depends_on: ["missing"] }],
})))
assert.equal(invalid.ok, false)
assert.match(invalid.error, /unknown dependency/)

const cyclic = JSON.parse(analyze_workspace(JSON.stringify({
  ...request,
  assets: request.assets.slice(0, 2).map((asset) =>
    asset.id === "db" ? { ...asset, depends_on: ["api"] } : asset,
  ),
})))
assert.equal(cyclic.ok, false)
assert.match(cyclic.error, /dependency cycle/)

process.stdout.write("Web MoonBit engine integration passed\n")
