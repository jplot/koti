import { beforeAll, describe, expect, it, vi } from 'vitest'
import { mount } from '@vue/test-utils'
import PlanView3D from '@/plan/PlanView3D.vue'
import { click, FakeRenderer, FakeResizeObserver, sizeCanvas } from './fakeRenderer'
import { level } from './studio'

vi.mock('three', async (original) => ({
  ...(await original<typeof import('three')>()),
  WebGLRenderer: (await import('./fakeRenderer')).FakeRenderer,
}))

beforeAll(() => {
  sizeCanvas(HTMLCanvasElement.prototype as HTMLCanvasElement)
  vi.stubGlobal('ResizeObserver', FakeResizeObserver)
})

const mountView = () => mount(PlanView3D, { props: { level, selected: null }, attachTo: document.body })

describe('PlanView3D', () => {
  it('renders the level on its canvas', () => {
    const wrapper = mountView()
    expect(FakeRenderer.last?.scene?.children.some((child) => child.userData.level === 'studio')).toBe(true)
    wrapper.unmount()
  })

  it('emits the room picked on the canvas', () => {
    const wrapper = mountView()
    click(wrapper.get('canvas').element as HTMLCanvasElement, [2, 2])
    expect(wrapper.emitted('select')).toEqual([[null]])
    wrapper.unmount()
  })

  it('releases the renderer when it goes away', () => {
    const wrapper = mountView()
    const renderer = FakeRenderer.last
    wrapper.unmount()
    expect(renderer?.dispose).toHaveBeenCalled()
  })

  it('redraws when the level changes', async () => {
    const wrapper = mountView()
    await wrapper.setProps({ level: { ...level, id: 'etage', elevation: 280 } })
    const shown = FakeRenderer.last?.scene?.children.find((child) => child.userData.level === 'etage')
    expect(shown?.position.y).toBe(280)
    wrapper.unmount()
  })

  it('redraws when the selection changes', async () => {
    const wrapper = mountView()
    const renders = vi.spyOn(FakeRenderer.last as FakeRenderer, 'render')
    await wrapper.setProps({ selected: 'cuisine' })
    expect(renders).toHaveBeenCalled()
    wrapper.unmount()
  })
})
