import type { KotiPlan, Level, Opening, Room, Wall } from './types'

// The schema's property order. PostgreSQL's jsonb sorts keys shortest first, so the plan comes back from the
// API reordered; writing it in this order keeps an exported file diffable against the one imported.
const ORDER = {
  plan: ['format', 'version', 'unit', 'name', 'levels'],
  level: ['id', 'name', 'elevation', 'height', 'walls', 'openings', 'rooms'],
  wall: ['id', 'footprint', 'height'],
  opening: ['id', 'kind', 'name', 'from', 'to', 'depth', 'sill', 'head', 'hinge', 'swing'],
  room: ['id', 'name', 'outline', 'ceiling', 'finish', 'label'],
} as const

function ordered<T extends object>(value: T, keys: readonly string[]): T {
  const source = value as Record<string, unknown>
  return Object.fromEntries(keys.filter((key) => source[key] !== undefined).map((key) => [key, source[key]])) as T
}

const orderedLevel = (level: Level): Level => ({
  ...ordered(level, ORDER.level),
  walls: level.walls.map((wall: Wall) => ordered(wall, ORDER.wall)),
  openings: level.openings.map((opening: Opening) => ordered(opening, ORDER.opening)),
  rooms: level.rooms.map((room: Room) => ordered(room, ORDER.room)),
})

export function serializePlan(plan: KotiPlan): string {
  const text = JSON.stringify(ordered({ ...plan, levels: plan.levels.map(orderedLevel) }, ORDER.plan), null, 2)
  return `${text}\n`
}
