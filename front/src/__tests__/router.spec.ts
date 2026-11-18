import { afterEach, describe, expect, it, vi } from 'vitest'
import { createMemoryHistory } from 'vue-router'
import { createAppRouter } from '@/router'

function session(status: number) {
  vi.stubGlobal('fetch', vi.fn<typeof fetch>(async () => new Response(status === 200 ? '{"email_address":"ana@example.test"}' : null, { status })))
}

afterEach(() => vi.unstubAllGlobals())

describe('the router', () => {
  it('sends a visitor without a session to the sign-in page', async () => {
    session(401)
    const router = createAppRouter(createMemoryHistory())
    await router.push('/')
    expect(router.currentRoute.value.path).toBe('/login')
  })

  it('lets a signed-in account reach the plan', async () => {
    session(200)
    const router = createAppRouter(createMemoryHistory())
    await router.push('/')
    expect(router.currentRoute.value.path).toBe('/')
  })
})
