import { describe, expect, it } from 'vitest'
import { Box3, Mesh, ShapeGeometry, Vector3, type Object3D } from 'three'
import { buildLevel } from '@/plan/scene'
import type { Level } from '@/plan/types'
import { level } from './studio'

const meshes = (group: Object3D, kind: string, id?: string) =>
  group.children.filter((child): child is Mesh => child.userData.kind === kind && (id === undefined || child.userData.id === id))

const box = (mesh: Mesh) => new Box3().setFromObject(mesh)
// Rotations leave ±1e-15 behind; `+ 0` also turns -0 into 0.
const whole = (values: number[]) => values.map((value) => Math.round(value) + 0)

describe('buildLevel', () => {
  it('extrudes every wall to its height', () => {
    const group = buildLevel(level)
    const [w1] = meshes(group, 'wall', 'w1')
    expect(meshes(group, 'wall')).toHaveLength(6)
    expect(whole(box(w1 as Mesh).min.toArray())).toEqual([0, 0, 0])
    expect(whole(box(w1 as Mesh).max.toArray())).toEqual([250, 250, 20])
  })

  it('extrudes a wall to its own height when it has one', () => {
    const [w6] = meshes(buildLevel(level), 'wall', 'w6')
    expect(box(w6 as Mesh).max.y).toBeCloseTo(220)
  })

  it('lays every room floor with its holes', () => {
    const group = buildLevel(level)
    const [floor] = meshes(group, 'room', 'piece')
    expect(meshes(group, 'room')).toHaveLength(2)
    const shape = ((floor as Mesh).geometry as ShapeGeometry).parameters.shapes
    expect(Array.isArray(shape) ? shape[0]?.holes : shape.holes).toHaveLength(1)
  })

  it('gives a door no sill block', () => {
    expect(meshes(buildLevel(level), 'sill', 'entree')).toHaveLength(0)
  })

  it('blocks a window below its sill and above its head, with glass between', () => {
    const group = buildLevel(level)
    const [sill] = meshes(group, 'sill', 'fenetre')
    const [lintel] = meshes(group, 'lintel', 'fenetre')
    expect(whole([box(sill as Mesh).min.y, box(sill as Mesh).max.y])).toEqual([0, 90])
    expect(whole([box(lintel as Mesh).min.y, box(lintel as Mesh).max.y])).toEqual([215, 250])
    expect(meshes(group, 'glass', 'fenetre')).toHaveLength(1)
  })

  it('gives no lintel when the head reaches the wall top', () => {
    const tall: Level = { ...level, openings: level.openings.map((opening) => ({ ...opening, head: 250 })) }
    expect(meshes(buildLevel(tall), 'lintel')).toHaveLength(0)
  })

  it('orients a y-axis opening along z', () => {
    const [lintel] = meshes(buildLevel(level), 'lintel', 'baie')
    const size = box(lintel as Mesh).getSize(new Vector3())
    expect(size.z).toBeCloseTo(80)
    expect(size.x).toBeCloseTo(10)
  })

  it('lifts the group to the level elevation', () => {
    expect(buildLevel({ ...level, elevation: 280 }).position.y).toBe(280)
  })
})
