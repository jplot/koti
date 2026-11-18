import { describe, expect, it } from 'vitest'
import { mount } from '@vue/test-utils'
import { createMemoryHistory, createRouter } from 'vue-router'
import App from '@/App.vue'

describe('App', () => {
  it('shows the page of the current route', async () => {
    const router = createRouter({
      history: createMemoryHistory(),
      routes: [{ path: '/', component: { template: '<p>la page</p>' } }],
    })
    await router.push('/')
    expect(mount(App, { global: { plugins: [router] } }).text()).toBe('la page')
  })
})
