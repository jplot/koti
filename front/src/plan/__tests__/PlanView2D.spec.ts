import { describe, expect, it } from 'vitest'
import { mount } from '@vue/test-utils'
import PlanView2D from '@/plan/PlanView2D.vue'
import type { Level } from '@/plan/types'
import { level } from './studio'

const draw = (props: { level: Level; selected: string | null } = { level, selected: null }) => mount(PlanView2D, { props })

describe('PlanView2D', () => {
  it('draws every room, wall and opening of the level', () => {
    const wrapper = draw()
    expect(wrapper.findAll('path.room')).toHaveLength(2)
    expect(wrapper.findAll('path.wall')).toHaveLength(6)
    expect(wrapper.findAll('line.leaf')).toHaveLength(1)
    expect(wrapper.findAll('path.arc')).toHaveLength(1)
    expect(wrapper.findAll('line.window')).toHaveLength(2)
    expect(wrapper.findAll('line.sliding')).toHaveLength(1)
  })

  it('fills a holed room with evenodd', () => {
    expect(draw().get('path.room[data-room-id=piece]').attributes('fill-rule')).toBe('evenodd')
  })

  it('emits the room id on click and null on the background', async () => {
    const wrapper = draw()
    await wrapper.get('path.room[data-room-id=cuisine]').trigger('click')
    await wrapper.get('rect.backdrop').trigger('click')
    expect(wrapper.emitted('select')).toEqual([['cuisine'], [null]])
  })

  it('marks the selected room', () => {
    const wrapper = draw({ level, selected: 'cuisine' })
    expect(wrapper.get('path.room[data-room-id=cuisine]').classes()).toContain('selected')
    expect(wrapper.get('path.room[data-room-id=piece]').classes()).not.toContain('selected')
  })

  it('labels a room with its name and area', () => {
    expect(draw().text()).toContain('Pièce · 9,8 m²')
  })

  it('keeps a finite viewBox for an empty level', () => {
    const wrapper = draw({ level: { ...level, walls: [], openings: [], rooms: [] }, selected: null })
    expect(wrapper.get('svg').attributes('viewBox')).toBe('-40 -40 580 580')
  })
})
