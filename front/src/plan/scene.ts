import { BoxGeometry, ExtrudeGeometry, Group, Mesh, MeshStandardMaterial, Path, Shape, ShapeGeometry, type BufferGeometry } from 'three'
import type { Level, Opening, Ring } from './types'

export const COLORS = { wall: '#e5e5e5', floor: '#d4d4d4', selected: '#93c5fd', block: '#e5e5e5', glass: '#bae6fd' }

function outline<T extends Shape | Path>(target: T, ring: Ring): T {
  // Points as (x, -y): rotateX(-π/2) then lays plan y along world z.
  ring.forEach(([x, y], index) => (index === 0 ? target.moveTo(x, -y) : target.lineTo(x, -y)))
  return target
}

function mesh(geometry: BufferGeometry, color: string, kind: string, id: string, opacity = 1): Mesh {
  const material = new MeshStandardMaterial({ color, transparent: opacity < 1, opacity })
  const result = new Mesh(geometry, material)
  result.name = `${kind}:${id}`
  result.userData = { kind, id }
  return result
}

function block(opening: Opening, kind: string, bottom: number, top: number, thickness: number, color: string, opacity = 1) {
  const [fromX, fromY] = opening.from
  const [toX, toY] = opening.to
  const length = Math.hypot(toX - fromX, toY - fromY)
  const result = mesh(new BoxGeometry(length, top - bottom, thickness), color, kind, opening.id, opacity)
  result.position.set((fromX + toX) / 2, (bottom + top) / 2, (fromY + toY) / 2)
  result.rotation.y = -Math.atan2(toY - fromY, toX - fromX)
  return result
}

function openingBlocks(opening: Opening, height: number): Mesh[] {
  const blocks: Mesh[] = []
  if (opening.sill > 0) blocks.push(block(opening, 'sill', 0, opening.sill, opening.depth, COLORS.block))
  if (opening.head < height) blocks.push(block(opening, 'lintel', opening.head, height, opening.depth, COLORS.block))
  if (opening.kind !== 'door') blocks.push(block(opening, 'glass', opening.sill, opening.head, 2, COLORS.glass, 0.35))
  return blocks
}

export function buildLevel(level: Level): Group {
  const group = new Group()
  group.userData = { level: level.id }
  group.position.y = level.elevation
  for (const wall of level.walls) {
    const geometry = new ExtrudeGeometry(outline(new Shape(), wall.footprint), { depth: wall.height ?? level.height, bevelEnabled: false })
    group.add(mesh(geometry.rotateX(-Math.PI / 2), COLORS.wall, 'wall', wall.id))
  }
  for (const room of level.rooms) {
    const [contour = [], ...holes] = room.outline
    const shape = outline(new Shape(), contour)
    shape.holes = holes.map((hole) => outline(new Path(), hole))
    const floor = mesh(new ShapeGeometry(shape).rotateX(-Math.PI / 2), COLORS.floor, 'room', room.id)
    floor.position.y = 0.5
    group.add(floor)
  }
  for (const opening of level.openings) group.add(...openingBlocks(opening, level.height))
  return group
}
