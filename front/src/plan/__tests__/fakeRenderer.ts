import type { Camera, Scene } from 'three'
import { vi } from 'vitest'

// jsdom has no WebGL: the viewer's tests swap three's WebGLRenderer for this recorder.
export class FakeRenderer {
  static last: FakeRenderer | null = null
  scene: Scene | null = null
  camera: Camera | null = null
  dispose = vi.fn<() => void>()

  constructor() {
    FakeRenderer.last = this
  }

  setPixelRatio() {}
  setSize = vi.fn<(width: number, height: number, style?: boolean) => void>()
  // As WebGLRenderer.render does before drawing; picking reads these matrices.
  render(scene: Scene, camera: Camera) {
    scene.updateMatrixWorld()
    camera.updateMatrixWorld()
    this.scene = scene
    this.camera = camera
  }
}

export function sizeCanvas(canvas: HTMLCanvasElement) {
  canvas.getBoundingClientRect = () => ({ left: 0, top: 0, right: 800, bottom: 600, width: 800, height: 600, x: 0, y: 0, toJSON: () => ({}) })
  canvas.setPointerCapture = () => {}
  canvas.releasePointerCapture = () => {}
  canvas.hasPointerCapture = () => false
}

export function click(canvas: HTMLCanvasElement, at: [number, number], to: [number, number] = at) {
  canvas.dispatchEvent(new PointerEvent('pointerdown', { clientX: at[0], clientY: at[1], pointerId: 1, button: 0 }))
  canvas.dispatchEvent(new PointerEvent('pointerup', { clientX: to[0], clientY: to[1], pointerId: 1, button: 0 }))
}

// jsdom has no ResizeObserver: this one lets a test report a new size.
export class FakeResizeObserver {
  static last: FakeResizeObserver | null = null
  observed: Element[] = []
  disconnect = vi.fn<() => void>()

  constructor(readonly callback: () => void) {
    FakeResizeObserver.last = this
  }

  observe(element: Element) {
    this.observed.push(element)
  }
}
