import { afterEach, describe, expect, it, vi } from 'vitest'
import { flushPromises, mount } from '@vue/test-utils'
import { createMemoryHistory, createRouter } from 'vue-router'
import LoginPage from '@/pages/LoginPage.vue'

function answer(status: number, body: unknown) {
  const fetchMock = vi.fn<typeof fetch>(async () => new Response(JSON.stringify(body), { status }))
  vi.stubGlobal('fetch', fetchMock)
  return fetchMock
}

async function signIn() {
  const router = createRouter({
    history: createMemoryHistory(),
    routes: [
      { path: '/', component: { template: '<p>plan</p>' } },
      { path: '/login', component: LoginPage },
    ],
  })
  await router.push('/login')
  const wrapper = mount(LoginPage, { global: { plugins: [router] } })
  await wrapper.get('input[type=email]').setValue('ana@example.test')
  await wrapper.get('input[type=password]').setValue('correct horse')
  await wrapper.get('form').trigger('submit')
  await flushPromises()
  return { wrapper, router }
}

afterEach(() => vi.unstubAllGlobals())

describe('LoginPage', () => {
  it('signs in and goes to the plan', async () => {
    const fetchMock = answer(201, { email_address: 'ana@example.test' })
    const { router } = await signIn()
    expect(fetchMock).toHaveBeenCalledWith('/api/session', expect.objectContaining({
      body: JSON.stringify({ email_address: 'ana@example.test', password: 'correct horse' }),
    }))
    expect(router.currentRoute.value.path).toBe('/')
  })

  it('says the address or password is wrong', async () => {
    answer(401, { error: 'invalid_credentials' })
    const { wrapper, router } = await signIn()
    expect(wrapper.text()).toContain('Adresse ou mot de passe incorrect.')
    expect(router.currentRoute.value.path).toBe('/login')
  })

  it('says to wait after too many attempts', async () => {
    answer(429, { error: 'rate_limited' })
    const { wrapper } = await signIn()
    expect(wrapper.text()).toContain('Trop d’essais. Réessayer dans quelques minutes.')
  })

  it('says koti does not answer on a server error', async () => {
    answer(500, {})
    const { wrapper } = await signIn()
    expect(wrapper.text()).toContain('koti ne répond pas. Réessayer dans un instant.')
  })
})
