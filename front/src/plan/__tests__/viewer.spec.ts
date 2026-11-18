import { beforeEach, describe, expect, it, vi } from 'vitest'
import type { Mesh, MeshStandardMaterial, PerspectiveCamera } from 'three'
import { createViewer } from '@/plan/viewer'
import type { Level } from '@/plan/types'
import { click, FakeRenderer, FakeResizeObserver, sizeCanvas } from './fakeRenderer'
import { level } from './studio'

vi.mock('three', async (original) => ({
  ...(await original<typeof import('three')>()),
  WebGLRenderer: (await import('./fakeRenderer')).FakeRenderer,
}))

const square: Level = {
  ...level,
  walls: [],
  openings: [],
  rooms: [{ id: 'salle', name: 'Salle', outline: [[[0, 0], [400, 0], [400, 300], [0, 300]]] }],
}

let canvas: HTMLCanvasElement
beforeEach(() => {
  canvas = document.createElement('canvas')
  sizeCanvas(canvas)
  vi.stubGlobal('ResizeObserver', FakeResizeObserver)
})

const floorColor = (id: string) => {
  const floor = FakeRenderer.last?.scene?.getObjectByName(`room:${id}`) as Mesh
  return (floor.material as MeshStandardMaterial).color.getHexString()
}

describe('createViewer', () => {
  it('picks the room under a click without drag', () => {
    const onPick = vi.fn<(roomId: string | null) => void>()
    createViewer(canvas, onPick).show(square)
    click(canvas, [400, 300])
    expect(onPick).toHaveBeenCalledWith('salle')
  })

  it('picks nothing beside the rooms', () => {
    const onPick = vi.fn<(roomId: string | null) => void>()
    createViewer(canvas, onPick).show(square)
    click(canvas, [2, 2])
    expect(onPick).toHaveBeenCalledWith(null)
  })

  it('ignores a drag', () => {
    const onPick = vi.fn<(roomId: string | null) => void>()
    createViewer(canvas, onPick).show(square)
    click(canvas, [400, 300], [410, 300])
    expect(onPick).not.toHaveBeenCalled()
  })

  it('highlights the selected room floor', () => {
    const viewer = createViewer(canvas, () => {})
    viewer.show(level)
    const before = floorColor('piece')
    viewer.select('cuisine')
    expect(floorColor('cuisine')).not.toBe(before)
    expect(floorColor('piece')).toBe(before)
  })

  it('frames an empty level without NaN', () => {
    createViewer(canvas, () => {}).show({ ...level, walls: [], openings: [], rooms: [] })
    const camera = FakeRenderer.last?.camera as PerspectiveCamera
    expect(camera.position.toArray().every(Number.isFinite)).toBe(true)
  })

  it('follows the size of its canvas', () => {
    createViewer(canvas, () => {})
    expect(FakeResizeObserver.last?.observed).toEqual([canvas])
    canvas.getBoundingClientRect = () => ({ left: 0, top: 0, right: 375, bottom: 300, width: 375, height: 300, x: 0, y: 0, toJSON: () => ({}) })
    FakeResizeObserver.last?.callback()
    expect(FakeRenderer.last?.setSize).toHaveBeenLastCalledWith(375, 300, false)
  })

  it('releases the renderer on dispose', () => {
    createViewer(canvas, () => {}).dispose()
    expect(FakeRenderer.last?.dispose).toHaveBeenCalled()
    expect(FakeResizeObserver.last?.disconnect).toHaveBeenCalled()
  })
})
