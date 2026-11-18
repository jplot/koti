import type { Bounds, Level, Opening, Point, Ring, Room } from './types'

const EMPTY: Bounds = { minX: 0, minY: 0, maxX: 500, maxY: 500 }

const round = (value: number) => Math.round(value * 100) / 100

export function levelBounds(level: Level): Bounds {
  const points = [...level.walls.map((wall) => wall.footprint), ...level.rooms.flatMap((room) => room.outline)].flat()
  if (points.length === 0) return EMPTY
  const xs = points.map(([x]) => x)
  const ys = points.map(([, y]) => y)
  return { minX: Math.min(...xs), minY: Math.min(...ys), maxX: Math.max(...xs), maxY: Math.max(...ys) }
}

export function ringsPath(rings: Ring[]): string {
  return rings.map((ring) => `M${ring.map(([x, y]) => `${round(x)} ${round(y)}`).join('L')}Z`).join('')
}

function signedArea(ring: Ring): number {
  return ring.reduce((sum, [x, y], index) => {
    const [nextX, nextY] = ring[(index + 1) % ring.length] as Point
    return sum + x * nextY - nextX * y
  }, 0) / 2
}

export function roomArea(room: Room): number {
  const [outline = [], ...holes] = room.outline
  const square = Math.abs(signedArea(outline)) - holes.reduce((sum, hole) => sum + Math.abs(signedArea(hole)), 0)
  return Math.round(square / 1000) / 10
}

export function labelPoint(room: Room): Point {
  if (room.label) return room.label
  const outline = room.outline[0] ?? []
  const area = signedArea(outline)
  const sum = outline.reduce(
    ([cx, cy], [x, y], index) => {
      const [nextX, nextY] = outline[(index + 1) % outline.length] as Point
      const cross = x * nextY - nextX * y
      return [cx + (x + nextX) * cross, cy + (y + nextY) * cross]
    },
    [0, 0],
  )
  return [round(sum[0] / (6 * area)), round(sum[1] / (6 * area))]
}

export function doorLeaf(opening: Opening): { hinge: Point; closed: Point; open: Point } {
  const [fromX, fromY] = opening.from
  const [toX, toY] = opening.to
  const length = Math.hypot(toX - fromX, toY - fromY)
  const swing = opening.swing ?? 1
  // The normal (-dy, dx) of from→to: the side a door with swing 1 opens to.
  const [nx, ny] = [(fromY - toY) / length, (toX - fromX) / length]
  const offset = (swing * opening.depth) / 2
  const [hingeEnd, otherEnd] = opening.hinge === 'to' ? [opening.to, opening.from] : [opening.from, opening.to]
  const hinge: Point = [round(hingeEnd[0] + nx * offset), round(hingeEnd[1] + ny * offset)]
  return {
    hinge,
    closed: [round(otherEnd[0] + nx * offset), round(otherEnd[1] + ny * offset)],
    open: [round(hinge[0] + nx * swing * length), round(hinge[1] + ny * swing * length)],
  }
}

export function doorArcPath(opening: Opening): string {
  const { hinge, closed, open } = doorLeaf(opening)
  const radius = round(Math.hypot(closed[0] - hinge[0], closed[1] - hinge[1]))
  const cross = (closed[0] - hinge[0]) * (open[1] - hinge[1]) - (closed[1] - hinge[1]) * (open[0] - hinge[0])
  return `M${closed[0]} ${closed[1]}A${radius} ${radius} 0 0 ${cross > 0 ? 1 : 0} ${open[0]} ${open[1]}`
}

export function toWorld([x, y]: Point, height: number): [number, number, number] {
  return [x, height, y]
}
