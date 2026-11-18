export type Session = { email_address: string }

export class Unauthorized extends Error {}
export class LoginRefused extends Error {}
export class TooManyAttempts extends Error {}

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
