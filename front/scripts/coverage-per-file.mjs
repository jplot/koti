// Vitest checks one threshold set, either overall or per file; CONTRIBUTING asks for 95 % overall and 70 % per file.
import { readFileSync } from 'node:fs'

const MINIMUM = 70
const summary = JSON.parse(readFileSync(new URL('../coverage/coverage-summary.json', import.meta.url)))
const low = Object.entries(summary)
  .filter(([file, { lines }]) => file !== 'total' && lines.pct < MINIMUM)
  .map(([file, { lines }]) => `${lines.pct} %  ${file}`)

if (low.length > 0) {
  console.error(`Line coverage below ${MINIMUM} % per file:\n${low.join('\n')}`)
  process.exit(1)
}
