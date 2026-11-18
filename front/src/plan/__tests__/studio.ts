import studio from '../../../../catalog/examples/studio.json'
import type { KotiPlan, Level } from '@/plan/types'

export const plan = studio as unknown as KotiPlan
export const level = plan.levels[0] as Level
