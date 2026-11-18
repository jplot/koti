import {
  Color,
  DirectionalLight,
  HemisphereLight,
  Mesh,
  MeshStandardMaterial,
  PerspectiveCamera,
  Raycaster,
  Scene,
  Vector2,
  WebGLRenderer,
  type Group,
} from 'three'
import { OrbitControls } from 'three/examples/jsm/controls/OrbitControls.js'
import { levelBounds } from './geometry'
import { buildLevel, COLORS } from './scene'
import type { Level } from './types'

export type Viewer = { show(level: Level): void; select(roomId: string | null): void; dispose(): void }

// A press that moves farther than this is an orbit, not a click on a room.
const CLICK_SLOP = 4

export function createViewer(canvas: HTMLCanvasElement, onPick: (roomId: string | null) => void): Viewer {
  const renderer = new WebGLRenderer({ canvas, antialias: true })
  renderer.setPixelRatio(window.devicePixelRatio)
  const scene = new Scene()
  scene.background = new Color('#fafafa')
  scene.add(new HemisphereLight(0xffffff, 0x8a8a8a, 2))
  const sun = new DirectionalLight(0xffffff, 1.5)
  sun.position.set(1, 2, 1.5)
  scene.add(sun)
  const camera = new PerspectiveCamera(50, 1, 1, 100_000)
  const controls = new OrbitControls(camera, canvas)
  let group: Group | null = null
  let selected: string | null = null
  let pressed: [number, number] | null = null

  const render = () => renderer.render(scene, camera)
  const floors = () => (group?.children ?? []).filter((child): child is Mesh => child.userData.kind === 'room')

  function resize() {
    const { width, height } = canvas.getBoundingClientRect()
    renderer.setSize(width, height, false)
    camera.aspect = width / height || 1
    camera.updateProjectionMatrix()
    render()
  }

  function paint() {
    for (const floor of floors()) {
      ;(floor.material as MeshStandardMaterial).color.set(floor.userData.id === selected ? COLORS.selected : COLORS.floor)
    }
  }

  function frame(level: Level) {
    const { minX, minY, maxX, maxY } = levelBounds(level)
    const size = Math.max(maxX - minX, maxY - minY)
    controls.target.set((minX + maxX) / 2, 0, (minY + maxY) / 2)
    camera.position.set((minX + maxX) / 2, size, (minY + maxY) / 2 + size)
    controls.update()
  }

  function pick(event: PointerEvent) {
    const rect = canvas.getBoundingClientRect()
    const pointer = new Vector2(((event.clientX - rect.left) / rect.width) * 2 - 1, -((event.clientY - rect.top) / rect.height) * 2 + 1)
    const raycaster = new Raycaster()
    raycaster.setFromCamera(pointer, camera)
    const [hit] = raycaster.intersectObjects(floors(), false)
    onPick(hit ? (hit.object.userData.id as string) : null)
  }

  const down = (event: PointerEvent) => (pressed = [event.clientX, event.clientY])
  const up = (event: PointerEvent) => {
    if (pressed && Math.hypot(event.clientX - pressed[0], event.clientY - pressed[1]) < CLICK_SLOP) pick(event)
    pressed = null
  }

  canvas.addEventListener('pointerdown', down)
  canvas.addEventListener('pointerup', up)
  const sizing = new ResizeObserver(resize)
  sizing.observe(canvas)
  controls.addEventListener('change', render)
  resize()

  return {
    show(level) {
      if (group) scene.remove(group)
      group = buildLevel(level)
      scene.add(group)
      frame(level)
      paint()
      render()
    },
    select(roomId) {
      selected = roomId
      paint()
      render()
    },
    dispose() {
      canvas.removeEventListener('pointerdown', down)
      canvas.removeEventListener('pointerup', up)
      sizing.disconnect()
      controls.dispose()
      renderer.dispose()
    },
  }
}
