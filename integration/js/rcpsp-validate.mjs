import { readFileSync } from "node:fs"
import { resolve } from "node:path"
import { pathToFileURL } from "node:url"

const [problemPath, solutionPath] = process.argv.slice(2)
if (!problemPath || !solutionPath) {
  process.stderr.write("usage: node integration/js/rcpsp-validate.mjs PROBLEM.json SOLUTION.json\n")
  process.exitCode = 2
} else {
  const compiled = pathToFileURL(resolve("_build/js/release/build/cmd/rcpsp/rcpsp.js"))
  const { validate_json } = await import(compiled.href)
  const result = JSON.parse(validate_json(
    readFileSync(problemPath, "utf8"),
    readFileSync(solutionPath, "utf8"),
  ))
  process.stdout.write(`${JSON.stringify(result)}\n`)
  if (!result.ok) process.exitCode = 1
}
