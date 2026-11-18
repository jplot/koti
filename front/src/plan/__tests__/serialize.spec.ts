import { describe, expect, it } from 'vitest'
import schema from '../../../../catalog/koti-plan.schema.json'
import { serializePlan } from '@/plan/serialize'
import type { KotiPlan } from '@/plan/types'
import { plan } from './studio'

// PostgreSQL's jsonb hands keys back shortest first, then by bytes: this is the studio as GET /api/plan serves it.
function asJsonb(value: unknown): unknown {
  if (Array.isArray(value)) return value.map(asJsonb)
  if (value === null || typeof value !== 'object') return value
  const keys = Object.keys(value).sort((a, b) => a.length - b.length || (a < b ? -1 : 1))
  return Object.fromEntries(keys.map((key) => [key, asJsonb((value as Record<string, unknown>)[key])]))
}

const schemaOrder = (value: object, properties: object) => Object.keys(properties).filter((key) => key in value)

describe('serializePlan', () => {
  it('writes every object’s keys in the order of the schema', () => {
    const written = JSON.parse(serializePlan(asJsonb(plan) as KotiPlan))
    const pairs: [object, object][] = [[written, schema.properties]]
    for (const level of written.levels) {
      pairs.push([level, schema.$defs.level.properties])
      for (const wall of level.walls) pairs.push([wall, schema.$defs.wall.properties])
      for (const opening of level.openings) pairs.push([opening, schema.$defs.opening.properties])
      for (const room of level.rooms) pairs.push([room, schema.$defs.room.properties])
    }
    expect(pairs.map(([value]) => Object.keys(value))).toEqual(pairs.map(([value, properties]) => schemaOrder(value, properties)))
  })

  it('keeps every value', () => {
    expect(JSON.parse(serializePlan(asJsonb(plan) as KotiPlan))).toEqual(plan)
  })

  it('indents with two spaces and ends with a newline', () => {
    const text = serializePlan(plan)
    expect(text.startsWith('{\n  "format": "koti-plan",')).toBe(true)
    expect(text.endsWith('}\n')).toBe(true)
  })
})
