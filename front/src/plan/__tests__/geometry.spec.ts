import { describe, expect, it } from 'vitest'
import { doorArcPath, doorLeaf, labelPoint, levelBounds, ringsPath, roomArea, toWorld } from '@/plan/geometry'
import type { Level, Opening, Room } from '@/plan/types'
import { level } from './studio'

const door: Opening = { id: 'd', kind: 'door', from: [100, 50], to: [180, 50], depth: 20, sill: 0, head: 204, hinge: 'from', swing: 1 }
const holed: Room = {
  id: 'r',
  name: 'Pièce trouée',
  outline: [[[0, 0], [400, 0], [400, 300], [0, 300]], [[100, 100], [150, 100], [150, 150], [100, 150]]],
}

describe('levelBounds', () => {
  it('frames a level with its walls and rooms', () => {
    expect(levelBounds(level)).toEqual({ minX: 0, minY: 0, maxX: 600, maxY: 400 })
  })

  it('frames an empty level with a default box', () => {
    const empty: Level = { ...level, walls: [], openings: [], rooms: [] }
    expect(levelBounds(empty)).toEqual({ minX: 0, minY: 0, maxX: 500, maxY: 500 })
  })
})

describe('rooms', () => {
  it('subtracts holes from a room area, in square metres', () => {
    expect(roomArea(holed)).toBe(11.8)
  })

  it('labels a room at its label point when it has one', () => {
    expect(labelPoint({ ...holed, label: [10, 20] })).toEqual([10, 20])
  })

  it('labels a room at the centroid of its outline otherwise', () => {
    expect(labelPoint(holed)).toEqual([200, 150])
  })
})

describe('ringsPath', () => {
  it('draws one closed subpath per ring', () => {
    expect(ringsPath([[[0, 0], [10, 0], [10, 10]]])).toBe('M0 0L10 0L10 10Z')
  })

  it('keeps holes as further subpaths', () => {
    expect(ringsPath(holed.outline)).toBe('M0 0L400 0L400 300L0 300ZM100 100L150 100L150 150L100 150Z')
  })
})

describe('doors', () => {
  it('hinges a door leaf on the face of its swing side', () => {
    expect(doorLeaf(door)).toEqual({ hinge: [100, 60], closed: [180, 60], open: [100, 140] })
  })

  it('swings the other way with swing -1', () => {
    expect(doorLeaf({ ...door, swing: -1 })).toEqual({ hinge: [100, 40], closed: [180, 40], open: [100, -40] })
  })

  it('hinges on `to` when asked', () => {
    expect(doorLeaf({ ...door, hinge: 'to' })).toEqual({ hinge: [180, 60], closed: [100, 60], open: [180, 140] })
  })

  it('draws the swing arc from the closed to the open leaf end', () => {
    expect(doorArcPath(door)).toBe('M180 60A80 80 0 0 1 100 140')
  })

  it('sweeps the arc the other way when the door swings the other way', () => {
    expect(doorArcPath({ ...door, swing: -1 })).toBe('M180 40A80 80 0 0 0 100 -40')
  })
})

describe('toWorld', () => {
  it('maps plan y to world z', () => {
    expect(toWorld([100, 200], 50)).toEqual([100, 50, 200])
  })
})
