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
  router.beforeEach(async (to) => (to.meta.public || (await getSession()) ? true : '/login'))
  return router
}

export default createAppRouter(createWebHistory(import.meta.env.BASE_URL))
