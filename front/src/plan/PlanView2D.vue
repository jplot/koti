<script setup lang="ts">
import { computed } from 'vue'
import { doorArcPath, doorLeaf, labelPoint, levelBounds, ringsPath, roomArea, windowLines } from './geometry'
import type { Level } from './types'

const props = defineProps<{ level: Level; selected: string | null }>()
const emit = defineEmits<{ select: [roomId: string | null] }>()

const MARGIN = 40

const frame = computed(() => {
  const { minX, minY, maxX, maxY } = levelBounds(props.level)
  return { x: minX - MARGIN, y: minY - MARGIN, width: maxX - minX + 2 * MARGIN, height: maxY - minY + 2 * MARGIN }
})

const doors = computed(() =>
  props.level.openings
    .filter((opening) => opening.kind === 'door')
    .map((opening) => ({ id: opening.id, leaf: doorLeaf(opening), arc: doorArcPath(opening) })),
)

const windowEdges = computed(() =>
  props.level.openings
    .filter((opening) => opening.kind === 'window')
    .flatMap((opening) => windowLines(opening).map((line, index) => ({ key: `${opening.id}-${index}`, line }))),
)

const slidings = computed(() => props.level.openings.filter((opening) => opening.kind === 'sliding'))

const labels = computed(() =>
  props.level.rooms.map((room) => ({
    id: room.id,
    at: labelPoint(room),
    text: `${room.name} · ${roomArea(room).toLocaleString('fr-FR')} m²`,
  })),
)
</script>

<template>
  <svg
    class="plan-2d h-full w-full"
    :viewBox="`${frame.x} ${frame.y} ${frame.width} ${frame.height}`"
    role="img"
    :aria-label="`Plan du niveau ${level.name}`"
  >
    <rect class="backdrop" v-bind="frame" @click="emit('select', null)" />
    <path
      v-for="room in level.rooms"
      :key="room.id"
      class="room"
      :class="{ selected: room.id === selected }"
      :data-room-id="room.id"
      :d="ringsPath(room.outline)"
      fill-rule="evenodd"
      @click.stop="emit('select', room.id)"
    />
    <path v-for="wall in level.walls" :key="wall.id" class="wall" :d="ringsPath([wall.footprint])" />
    <g v-for="door in doors" :key="door.id">
      <line class="leaf" :x1="door.leaf.hinge[0]" :y1="door.leaf.hinge[1]" :x2="door.leaf.open[0]" :y2="door.leaf.open[1]" />
      <path class="arc" :d="door.arc" />
    </g>
    <line
      v-for="edge in windowEdges"
      :key="edge.key"
      class="window"
      :x1="edge.line[0][0]"
      :y1="edge.line[0][1]"
      :x2="edge.line[1][0]"
      :y2="edge.line[1][1]"
    />
    <line
      v-for="sliding in slidings"
      :key="sliding.id"
      class="sliding"
      :x1="sliding.from[0]"
      :y1="sliding.from[1]"
      :x2="sliding.to[0]"
      :y2="sliding.to[1]"
    />
    <text v-for="label in labels" :key="label.id" class="label" :x="label.at[0]" :y="label.at[1]">{{ label.text }}</text>
  </svg>
</template>

<style scoped>
.backdrop {
  fill: var(--background);
}
.room {
  fill: var(--muted);
  cursor: pointer;
}
.room.selected {
  fill: color-mix(in oklab, var(--primary) 25%, var(--muted));
}
.wall {
  fill: var(--foreground);
  pointer-events: none;
}
.leaf,
.window,
.sliding {
  stroke: var(--foreground);
  stroke-width: 2;
  pointer-events: none;
}
.arc {
  fill: none;
  stroke: var(--muted-foreground);
  stroke-width: 1;
  stroke-dasharray: 4 4;
  pointer-events: none;
}
.label {
  fill: var(--foreground);
  font-size: 14px;
  text-anchor: middle;
  dominant-baseline: middle;
  pointer-events: none;
}
</style>
