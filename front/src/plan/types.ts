// The koti-plan format v1, as catalog/koti-plan.schema.json defines it. Lengths in centimetres.
export type Point = [number, number]
export type Ring = Point[]

export type Wall = { id: string; footprint: Ring; height?: number }

export type Opening = {
  id: string
  kind: 'door' | 'window' | 'sliding'
  name?: string
  from: Point
  to: Point
  depth: number
  sill: number
  head: number
  hinge?: 'from' | 'to'
  swing?: 1 | -1
}

export type Room = { id: string; name: string; outline: Ring[]; ceiling?: number; finish?: string; label?: Point }

export type Level = {
  id: string
  name: string
  elevation: number
  height: number
  walls: Wall[]
  openings: Opening[]
  rooms: Room[]
}

export type KotiPlan = { format: 'koti-plan'; version: 1; unit: 'cm'; name?: string; levels: Level[] }

export type Bounds = { minX: number; minY: number; maxX: number; maxY: number }
