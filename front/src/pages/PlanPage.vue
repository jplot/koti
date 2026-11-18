<script setup lang="ts">
import { computed, onMounted, ref, useTemplateRef } from 'vue'
import { useRouter } from 'vue-router'
import { getPlan, logout, PlanRefused, putPlan, Unauthorized } from '@/api'
import { Alert, AlertDescription, AlertTitle } from '@/components/ui/alert'
import { Button } from '@/components/ui/button'
import { ToggleGroup, ToggleGroupItem } from '@/components/ui/toggle-group'
import { roomArea } from '@/plan/geometry'
import PlanView2D from '@/plan/PlanView2D.vue'
import PlanView3D from '@/plan/PlanView3D.vue'
import { serializePlan } from '@/plan/serialize'
import type { KotiPlan } from '@/plan/types'

const router = useRouter()
const plan = ref<KotiPlan | null>(null)
const loaded = ref(false)
const levelId = ref<string | null>(null)
const view = ref<'2d' | '3d'>('2d')
const selected = ref<string | null>(null)
const failure = ref<{ title: string; details: string[] } | null>(null)
const fileInput = useTemplateRef<HTMLInputElement>('file')

const level = computed(() => plan.value?.levels.find((candidate) => candidate.id === levelId.value) ?? null)
const room = computed(() => level.value?.rooms.find((candidate) => candidate.id === selected.value) ?? null)
const metres = (centimetres: number) => `${(centimetres / 100).toLocaleString('fr-FR', { minimumFractionDigits: 2 })} m`

function show(next: KotiPlan) {
  plan.value = next
  levelId.value = next.levels[0]?.id ?? null
  selected.value = null
}

async function guarded(action: () => Promise<void>) {
  try {
    await action()
  } catch (error) {
    if (error instanceof Unauthorized) await router.push('/login')
    else failure.value = { title: 'koti ne répond pas.', details: [(error as Error).message] }
  }
}

onMounted(() =>
  guarded(async () => {
    const current = await getPlan()
    if (current) show(current)
    loaded.value = true
  }),
)

// reka-ui clears a single toggle group when its active item is clicked again: the view must stay set.
function chooseView(next: unknown) {
  if (next === '2d' || next === '3d') view.value = next
}

function chooseLevel(id: string) {
  levelId.value = id
  selected.value = null
}

async function importFile(event: Event) {
  const input = event.target as HTMLInputElement
  const file = input.files?.[0]
  input.value = ''
  if (!file) return
  failure.value = null
  let document: unknown
  try {
    document = JSON.parse(await file.text())
  } catch {
    failure.value = { title: 'Ce fichier n’est pas du JSON.', details: [] }
    return
  }
  await guarded(async () => {
    try {
      show(await putPlan(document))
    } catch (error) {
      if (!(error instanceof PlanRefused)) throw error
      failure.value = { title: 'Ce fichier n’est pas un plan koti valide :', details: error.errors }
    }
  })
}

function exportPlan() {
  if (!plan.value) return
  const url = URL.createObjectURL(new Blob([serializePlan(plan.value)], { type: 'application/json' }))
  const link = document.createElement('a')
  link.href = url
  link.download = 'koti-plan.json'
  link.click()
  URL.revokeObjectURL(url)
}

const signOut = () =>
  guarded(async () => {
    await logout()
    await router.push('/login')
  })
</script>

<template>
  <div class="flex min-h-svh flex-col bg-background">
    <header class="flex flex-wrap items-center gap-2 border-b p-3">
      <h1 class="mr-auto text-lg font-semibold">koti</h1>
      <select
        v-if="plan && plan.levels.length > 1"
        id="level"
        class="h-9 rounded-md border bg-background px-2 text-sm"
        aria-label="Niveau"
        :value="levelId"
        @change="chooseLevel(($event.target as HTMLSelectElement).value)"
      >
        <option v-for="candidate in plan.levels" :key="candidate.id" :value="candidate.id">{{ candidate.name }}</option>
      </select>
      <ToggleGroup
        v-if="level"
        :model-value="view"
        type="single"
        variant="outline"
        aria-label="Vue"
        @update:model-value="chooseView"
      >
        <ToggleGroupItem value="2d" data-view="2d">2D</ToggleGroupItem>
        <ToggleGroupItem value="3d" data-view="3d">3D</ToggleGroupItem>
      </ToggleGroup>
      <Button variant="outline" data-action="import" @click="fileInput?.click()">Importer un plan</Button>
      <Button v-if="plan" variant="outline" data-action="export" @click="exportPlan">Exporter</Button>
      <Button variant="ghost" data-action="logout" @click="signOut">Se déconnecter</Button>
      <input ref="file" type="file" accept=".json,application/json" class="hidden" @change="importFile" />
    </header>

    <Alert v-if="failure" variant="destructive" class="m-3 w-auto">
      <AlertTitle>{{ failure.title }}</AlertTitle>
      <AlertDescription v-if="failure.details.length">
        <ul class="list-disc pl-4">
          <li v-for="detail in failure.details" :key="detail" class="font-mono text-xs">{{ detail }}</li>
        </ul>
      </AlertDescription>
    </Alert>

    <main v-if="level" class="grid flex-1 grid-cols-1 md:grid-cols-[1fr_18rem]">
      <section class="relative min-h-[60svh] overflow-hidden">
        <PlanView2D v-if="view === '2d'" :level="level" :selected="selected" @select="selected = $event" />
        <PlanView3D v-else :level="level" :selected="selected" @select="selected = $event" />
      </section>
      <aside v-if="room" class="border-t p-4 md:border-t-0 md:border-l" data-panel="room">
        <h2 class="text-base font-semibold">{{ room.name }}</h2>
        <dl class="mt-2 grid grid-cols-[auto_1fr] gap-x-3 gap-y-1 text-sm">
          <dt class="text-muted-foreground">Surface</dt>
          <dd>{{ roomArea(room).toLocaleString('fr-FR') }} m²</dd>
          <dt class="text-muted-foreground">Sous plafond</dt>
          <dd>{{ metres(room.ceiling ?? level.height) }}</dd>
          <template v-if="room.finish">
            <dt class="text-muted-foreground">Revêtement</dt>
            <dd>{{ room.finish }}</dd>
          </template>
        </dl>
      </aside>
    </main>

    <main v-else-if="loaded" class="flex flex-1 flex-col items-center justify-center gap-3 p-6 text-center">
      <p>Aucun plan pour l’instant.</p>
      <Button @click="fileInput?.click()">Importer un plan</Button>
    </main>
  </div>
</template>
