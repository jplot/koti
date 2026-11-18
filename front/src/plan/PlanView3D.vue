<script setup lang="ts">
import { onBeforeUnmount, onMounted, useTemplateRef, watch } from 'vue'
import type { Level } from './types'
import { createViewer, type Viewer } from './viewer'

const props = defineProps<{ level: Level; selected: string | null }>()
const emit = defineEmits<{ select: [roomId: string | null] }>()

const canvas = useTemplateRef<HTMLCanvasElement>('canvas')
let viewer: Viewer | null = null

onMounted(() => {
  viewer = createViewer(canvas.value as HTMLCanvasElement, (roomId) => emit('select', roomId))
  viewer.show(props.level)
  viewer.select(props.selected)
})
watch(
  () => props.level,
  (level) => viewer?.show(level),
)
watch(
  () => props.selected,
  (roomId) => viewer?.select(roomId),
)
onBeforeUnmount(() => viewer?.dispose())
</script>

<template>
  <canvas ref="canvas" class="block h-full w-full touch-none" :aria-label="`Plan en 3D du niveau ${level.name}`" />
</template>
