import { createRouter, createWebHistory, type RouterHistory } from 'vue-router'
import { getSession } from '@/api'
import LoginPage from '@/pages/LoginPage.vue'
import PlanPage from '@/pages/PlanPage.vue'

export function createAppRouter(history: RouterHistory) {
  const router = createRouter({
    history,
    routes: [
      { path: '/', component: PlanPage },
      { path: '/login', component: LoginPage, meta: { public: true } },
    ],
  })
  router.beforeEach(async (to) => {
    if (to.meta.public) return true
    try {
      return (await getSession()) ? true : '/login'
    } catch {
      // koti does not answer: the page loads anyway and shows its own failure instead of a blank screen.
      return true
    }
  })
  return router
}

export default createAppRouter(createWebHistory(import.meta.env.BASE_URL))
