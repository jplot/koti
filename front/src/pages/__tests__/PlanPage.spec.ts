import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'
import { flushPromises, mount } from '@vue/test-utils'
import { createMemoryHistory, createRouter } from 'vue-router'
import PlanPage from '@/pages/PlanPage.vue'
import type { KotiPlan } from '@/plan/types'
import { level, plan } from '@/plan/__tests__/studio'

type Route = () => Response
const json = (status: number, body?: unknown) => () =>
  new Response(body === undefined ? null : JSON.stringify(body), { status })

function serve(routes: Record<string, Route>) {
  const fetchMock = vi.fn<typeof fetch>(async (input, init) => {
    const route = routes[`${init?.method ?? 'GET'} ${String(input)}`]
    if (!route) throw new Error(`no route for ${init?.method} ${String(input)}`)
    return route()
  })
  vi.stubGlobal('fetch', fetchMock)
  return fetchMock
}

async function open() {
  const router = createRouter({
    history: createMemoryHistory(),
    routes: [
      { path: '/', component: PlanPage },
      { path: '/login', component: { template: '<p>connexion</p>' } },
    ],
  })
  await router.push('/')
  const wrapper = mount(PlanPage, { global: { plugins: [router], stubs: { PlanView3D: true } } })
  await flushPromises()
  return { wrapper, router }
}

async function upload(wrapper: Awaited<ReturnType<typeof open>>['wrapper'], text: string) {
  const input = wrapper.get('input[type=file]')
  Object.defineProperty(input.element, 'files', { value: [new File([text], 'plan.json', { type: 'application/json' })], configurable: true })
  await input.trigger('change')
  await flushPromises()
}

const twoLevels: KotiPlan = { ...plan, levels: [level, { ...level, id: 'etage', name: 'Étage', elevation: 280 }] }

beforeEach(() => {
  URL.createObjectURL = vi.fn<(blob: Blob) => string>(() => 'blob:plan')
  URL.revokeObjectURL = vi.fn<(url: string) => void>()
})
afterEach(() => vi.unstubAllGlobals())

describe('PlanPage', () => {
  it('shows the empty state when no plan exists', async () => {
    serve({ 'GET /api/plan': json(404) })
    const { wrapper } = await open()
    expect(wrapper.text()).toContain('Aucun plan pour l’instant.')
    expect(wrapper.text()).toContain('Importer un plan')
  })

  it('shows the 2d view of the first level, then the 3d view, keeping the selected room', async () => {
    serve({ 'GET /api/plan': json(200, plan) })
    const { wrapper } = await open()
    await wrapper.get('path.room[data-room-id=cuisine]').trigger('click')
    await wrapper.get('[data-view="3d"]').trigger('click')
    expect(wrapper.find('svg.plan-2d').exists()).toBe(false)
    expect(wrapper.findComponent({ name: 'PlanView3D' }).props('selected')).toBe('cuisine')
  })

  it('stays in 2D when the active 2D button is clicked again', async () => {
    serve({ 'GET /api/plan': json(200, plan) })
    const { wrapper } = await open()
    await wrapper.get('[data-view="2d"]').trigger('click')
    expect(wrapper.find('svg.plan-2d').exists()).toBe(true)
  })

  it('says koti does not answer when the plan load fails', async () => {
    serve({ 'GET /api/plan': json(500) })
    const { wrapper } = await open()
    expect(wrapper.text()).toContain('koti ne répond pas.')
    expect(wrapper.text()).toContain('HTTP 500')
  })

  it('says koti does not answer when the network is down', async () => {
    vi.stubGlobal('fetch', vi.fn<typeof fetch>(async () => Promise.reject(new TypeError('Failed to fetch'))))
    const { wrapper } = await open()
    expect(wrapper.text()).toContain('koti ne répond pas.')
  })

  it('keeps the plan and says so when an import fails on the server', async () => {
    serve({ 'GET /api/plan': json(200, plan), 'PUT /api/plan': json(500) })
    const { wrapper } = await open()
    await upload(wrapper, JSON.stringify(plan))
    expect(wrapper.text()).toContain('koti ne répond pas.')
    expect(wrapper.findAll('path.room')).toHaveLength(2)
  })

  it('switches level and clears the selection', async () => {
    serve({ 'GET /api/plan': json(200, twoLevels) })
    const { wrapper } = await open()
    await wrapper.get('path.room[data-room-id=cuisine]').trigger('click')
    await wrapper.get('select#level').setValue('etage')
    expect(wrapper.get('svg.plan-2d').attributes('aria-label')).toBe('Plan du niveau Étage')
    expect(wrapper.find('[data-panel=room]').exists()).toBe(false)
  })

  it('shows the selected room panel', async () => {
    serve({ 'GET /api/plan': json(200, plan) })
    const { wrapper } = await open()
    await wrapper.get('path.room[data-room-id=piece]').trigger('click')
    const panel = wrapper.get('[data-panel=room]').text()
    expect(panel).toContain('Pièce')
    expect(panel).toContain('9,8 m²')
    expect(panel).toContain('2,50 m')
    expect(panel).toContain('parquet')
  })

  it('keeps the current plan when an import is refused', async () => {
    serve({
      'GET /api/plan': json(200, plan),
      'PUT /api/plan': json(422, { errors: ['value at `/format` does not match const: "koti-plan"'] }),
    })
    const { wrapper } = await open()
    await upload(wrapper, '{"format":"x"}')
    expect(wrapper.text()).toContain('Ce fichier n’est pas un plan koti valide :')
    expect(wrapper.text()).toContain('value at `/format` does not match const: "koti-plan"')
    expect(wrapper.findAll('path.room')).toHaveLength(2)
  })

  it('replaces the plan with an accepted import', async () => {
    serve({ 'GET /api/plan': json(404), 'PUT /api/plan': json(200, plan) })
    const { wrapper } = await open()
    await upload(wrapper, JSON.stringify(plan))
    expect(wrapper.findAll('path.room')).toHaveLength(2)
  })

  it('says « Ce fichier n’est pas du JSON. » for a non-JSON file', async () => {
    const fetchMock = serve({ 'GET /api/plan': json(200, plan) })
    const { wrapper } = await open()
    await upload(wrapper, 'pas du json')
    expect(wrapper.text()).toContain('Ce fichier n’est pas du JSON.')
    expect(fetchMock).toHaveBeenCalledTimes(1)
  })

  it('goes to /login when the plan load answers 401', async () => {
    serve({ 'GET /api/plan': json(401) })
    const { router } = await open()
    expect(router.currentRoute.value.path).toBe('/login')
  })

  it('goes to /login when an import answers 401', async () => {
    serve({ 'GET /api/plan': json(200, plan), 'PUT /api/plan': json(401) })
    const { wrapper, router } = await open()
    await upload(wrapper, JSON.stringify(plan))
    expect(router.currentRoute.value.path).toBe('/login')
  })

  it('exports the plan as koti-plan.json', async () => {
    serve({ 'GET /api/plan': json(200, plan) })
    const { wrapper } = await open()
    const clicks = vi.spyOn(HTMLAnchorElement.prototype, 'click').mockImplementation(() => {})
    await wrapper.get('[data-action=export]').trigger('click')
    const blob = vi.mocked(URL.createObjectURL).mock.calls[0]?.[0] as Blob
    expect((clicks.mock.contexts[0] as HTMLAnchorElement).download).toBe('koti-plan.json')
    expect(JSON.parse(await blob.text())).toEqual(plan)
  })

  it('signs out', async () => {
    serve({ 'GET /api/plan': json(200, plan), 'DELETE /api/session': json(204) })
    const { wrapper, router } = await open()
    await wrapper.get('[data-action=logout]').trigger('click')
    await flushPromises()
    expect(router.currentRoute.value.path).toBe('/login')
  })
})
