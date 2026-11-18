import { afterEach, describe, expect, it, vi } from 'vitest'
import { getPlan, getSession, login, LoginRefused, logout, PlanRefused, putPlan, TooManyAttempts, Unauthorized } from '@/api'

function answer(status: number, body?: unknown) {
  const fetchMock = vi.fn<typeof fetch>(async () => new Response(body === undefined ? null : JSON.stringify(body), { status }))
  vi.stubGlobal('fetch', fetchMock)
  return fetchMock
}

afterEach(() => vi.unstubAllGlobals())

describe('getSession', () => {
  it('returns null when no session is open', async () => {
    answer(401)
    expect(await getSession()).toBeNull()
  })

  it('returns the signed-in account', async () => {
    answer(200, { email_address: 'ana@example.test' })
    expect(await getSession()).toEqual({ email_address: 'ana@example.test' })
  })
})

describe('login', () => {
  it('sends the credentials as JSON and returns the session', async () => {
    const fetchMock = answer(201, { email_address: 'ana@example.test' })
    expect(await login('ana@example.test', 'correct horse')).toEqual({ email_address: 'ana@example.test' })
    expect(fetchMock).toHaveBeenCalledWith('/api/session', expect.objectContaining({
      method: 'POST',
      credentials: 'same-origin',
      body: JSON.stringify({ email_address: 'ana@example.test', password: 'correct horse' }),
    }))
  })

  it('raises LoginRefused on 401', async () => {
    answer(401, { error: 'invalid_credentials' })
    await expect(login('ana@example.test', 'wrong')).rejects.toBeInstanceOf(LoginRefused)
  })

  it('raises TooManyAttempts on 429', async () => {
    answer(429, { error: 'rate_limited' })
    await expect(login('ana@example.test', 'wrong')).rejects.toBeInstanceOf(TooManyAttempts)
  })
})

describe('logout', () => {
  it('closes the session', async () => {
    const fetchMock = answer(204)
    await logout()
    expect(fetchMock).toHaveBeenCalledWith('/api/session', expect.objectContaining({ method: 'DELETE' }))
  })

  it('raises Unauthorized when the session is already gone', async () => {
    answer(401)
    await expect(logout()).rejects.toBeInstanceOf(Unauthorized)
  })

  it('raises on a server error', async () => {
    answer(500)
    await expect(logout()).rejects.toThrow('HTTP 500')
  })
})

describe('getPlan', () => {
  it('returns null when no plan was imported', async () => {
    answer(404)
    expect(await getPlan()).toBeNull()
  })

  it('returns the plan', async () => {
    answer(200, { format: 'koti-plan' })
    expect(await getPlan()).toEqual({ format: 'koti-plan' })
  })

  it('raises Unauthorized on 401', async () => {
    answer(401)
    await expect(getPlan()).rejects.toBeInstanceOf(Unauthorized)
  })
})

describe('putPlan', () => {
  it('sends the document and returns the stored plan', async () => {
    const fetchMock = answer(200, { format: 'koti-plan' })
    expect(await putPlan({ format: 'koti-plan' })).toEqual({ format: 'koti-plan' })
    expect(fetchMock).toHaveBeenCalledWith('/api/plan', expect.objectContaining({ method: 'PUT', body: '{"format":"koti-plan"}' }))
  })

  it('raises PlanRefused with the messages on 422', async () => {
    answer(422, { errors: ['value at `/format` does not match const: "koti-plan"'] })
    const refusal = await putPlan({}).catch((error: unknown) => error)
    expect(refusal).toBeInstanceOf(PlanRefused)
    expect((refusal as PlanRefused).errors).toEqual(['value at `/format` does not match const: "koti-plan"'])
  })
})
