import { spawnSync } from "node:child_process"

const result = spawnSync("moon", ["run", "--target", "js", "cmd/js_probe"], {
  cwd: new URL("../..", import.meta.url),
  encoding: "utf8",
})

if (result.status !== 0) {
  process.stderr.write(result.stderr)
  process.exit(result.status ?? 1)
}

if (result.stdout.trim() !== "continuityforge-core-ready") {
  throw new Error(`unexpected MoonBit output: ${result.stdout}`)
}

process.stdout.write("JavaScript integration probe passed\n")
