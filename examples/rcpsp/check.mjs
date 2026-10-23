import assert from "node:assert/strict"
import { readFileSync } from "node:fs"
import { dirname, join, resolve } from "node:path"
import { fileURLToPath, pathToFileURL } from "node:url"

const root = resolve(dirname(fileURLToPath(import.meta.url)), "../..")
const { solve_json, validate_json } = await import(pathToFileURL(
  join(root, "_build/js/release/build/cmd/rcpsp/rcpsp.js"),
).href)
const cases = [
  { name: "ci", expected: 11, failure: "ci-deadline-fail", rejectedBy: "hard deadline" },
  { name: "recovery", expected: 8, failure: "recovery-capacity-fail", rejectedBy: "capacity" },
  { name: "project", expected: 11, failure: "project-deadline-fail", rejectedBy: "hard deadline" },
]
for (const item of cases) {
  const validInput = readFileSync(join(root, `examples/rcpsp/${item.name}.json`), "utf8")
  const invalidInput = readFileSync(join(root, `examples/rcpsp/${item.failure}.json`), "utf8")
  const candidate = solve_json(validInput, "from-input", 0)
  const result = JSON.parse(candidate)
  assert.equal(result.status, "FEASIBLE")
  assert.equal(result.makespan, item.expected)
  assert.equal(JSON.parse(validate_json(validInput, candidate)).ok, true)
  const failedSearch = JSON.parse(solve_json(invalidInput, "from-input", 0))
  assert.equal(failedSearch.status, "UNKNOWN")
  const rejected = JSON.parse(validate_json(invalidInput, candidate))
  assert.equal(rejected.ok, false)
  assert.match(rejected.error, new RegExp(item.rejectedBy))
  process.stdout.write(`${item.name}: feasible ${item.expected}; failure UNKNOWN; prior schedule rejected: ${rejected.error}\n`)
  if (item.name === "ci") {
    const moreMemory = JSON.parse(validInput)
    moreMemory.resources.find((resource) => resource.id === "memory").capacity = 5
    const improved = JSON.parse(solve_json(JSON.stringify(moreMemory), "from-input", 0))
    assert.equal(improved.status, "FEASIBLE")
    assert.equal(improved.makespan, 10)
  }
  if (item.name === "recovery") {
    const unbounded = JSON.parse(invalidInput)
    delete unbounded.target_makespan
    delete unbounded.tasks.find((task) => task.id === "smoke").deadline
    const delayed = JSON.parse(solve_json(JSON.stringify(unbounded), "from-input", 0))
    assert.equal(delayed.status, "FEASIBLE")
    assert.equal(delayed.makespan, 10)
  }
}
