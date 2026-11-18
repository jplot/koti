import type { KotiPlan } from '@/plan/types'

export type Session = { email_address: string }

export class Unauthorized extends Error {}
export class LoginRefused extends Error {}
export class TooManyAttempts extends Error {}
export class PlanRefused extends Error {
  constructor(readonly errors: string[]) {
    super('plan refused')
  }
}

function request(method: string, path: string, body?: unknown): Promise<Response> {
  const headers: Record<string, string> = { Accept: 'application/json' }
  if (body !== undefined) headers['Content-Type'] = 'application/json'
  return fetch(path, {
    method,
    credentials: 'same-origin',
    headers,
    body: body === undefined ? undefined : JSON.stringify(body),
  })
}

function ok(response: Response): Response {
  if (response.status === 401) throw new Unauthorized()
  if (!response.ok) throw new Error(`HTTP ${response.status}`)
  return response
}

export async function getSession(): Promise<Session | null> {
  const response = await request('GET', '/api/session')
  return response.status === 401 ? null : ok(response).json()
}

export async function login(email: string, password: string): Promise<Session> {
  const response = await request('POST', '/api/session', { email_address: email, password })
  if (response.status === 401) throw new LoginRefused()
  if (response.status === 429) throw new TooManyAttempts()
  return ok(response).json()
}

export async function logout(): Promise<void> {
  ok(await request('DELETE', '/api/session'))
}

export async function getPlan(): Promise<KotiPlan | null> {
  const response = await request('GET', '/api/plan')
  return response.status === 404 ? null : ok(response).json()
}

export async function putPlan(document: unknown): Promise<KotiPlan> {
  const response = await request('PUT', '/api/plan', document)
  if (response.status === 422) throw new PlanRefused((await response.json()).errors)
  return ok(response).json()
}
