import assert from "node:assert/strict"
import { readFileSync } from "node:fs"
import { analyze_workspace as published } from "../../web/engine.mjs"
import { toEngineRequest } from "../../web/scheduling.js"

const compiledSource = readFileSync(
  new URL("../../_build/js/release/build/web/engine/engine.js", import.meta.url),
  "utf8",
)
const { analyze_workspace: rebuilt } = await import(
  `data:text/javascript;base64,${Buffer.from(compiledSource).toString("base64")}`
)

function withoutTiming(value) {
  if (Array.isArray(value)) return value.map(withoutTiming)
  if (value !== null && typeof value === "object") {
    return Object.fromEntries(Object.entries(value)
      .filter(([key]) => key !== "elapsed_ms")
      .map(([key, entry]) => [key, withoutTiming(entry)]))
  }
  return value
}

const scenarios = ["incident", "ci"].map((name) =>
  JSON.parse(readFileSync(new URL(`../../web/scenarios/${name}.json`, import.meta.url), "utf8")),
)
const requests = scenarios.map(toEngineRequest)
requests.push({
  ...requests[0],
  assets: [{ ...requests[0].assets[0], depends_on: ["missing"] }],
})

for (const request of requests) {
  const input = JSON.stringify(request)
  const publishedResult = JSON.parse(published(input))
  const rebuiltResult = JSON.parse(rebuilt(input))
  assert.deepEqual(withoutTiming(publishedResult), withoutTiming(rebuiltResult))
}

process.stdout.write("Published and rebuilt MoonBit engines agree on scheduling scenarios\n")
