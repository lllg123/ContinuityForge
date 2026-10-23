import { readFileSync } from "node:fs"
import { resolve } from "node:path"
import { pathToFileURL } from "node:url"

const [inputPath, algorithm = "budgeted-local-search", budgetText = "30"] = process.argv.slice(2)
if (!inputPath || !/^\d+$/.test(budgetText)) {
  process.stderr.write("usage: node integration/js/rcpsp-cli.mjs PROBLEM.json [algorithm] [budget]\n")
  process.exitCode = 2
} else {
  const compiled = pathToFileURL(resolve("_build/js/release/build/cmd/rcpsp/rcpsp.js"))
  const { solve_json } = await import(compiled.href)
  const input = readFileSync(inputPath, "utf8")
  const output = solve_json(input, algorithm, Number(budgetText))
  process.stdout.write(`${output}\n`)
  if (Object.hasOwn(JSON.parse(output), "error")) process.exitCode = 1
}
