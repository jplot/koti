<script setup lang="ts">
import { ref } from 'vue'
import { useRouter } from 'vue-router'
import { login, LoginRefused, TooManyAttempts } from '@/api'
import { Alert, AlertDescription } from '@/components/ui/alert'
import { Button } from '@/components/ui/button'
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card'
import { Input } from '@/components/ui/input'
import { Label } from '@/components/ui/label'

const router = useRouter()
const email = ref('')
const password = ref('')
const error = ref<string | null>(null)
const busy = ref(false)

async function submit() {
  busy.value = true
  error.value = null
  try {
    await login(email.value, password.value)
    await router.push('/')
  } catch (refusal) {
    if (refusal instanceof LoginRefused) error.value = 'Adresse ou mot de passe incorrect.'
    else if (refusal instanceof TooManyAttempts) error.value = 'Trop d’essais. Réessayer dans quelques minutes.'
    else error.value = 'koti ne répond pas. Réessayer dans un instant.'
  } finally {
    busy.value = false
  }
}
</script>

<template>
  <main class="flex min-h-svh items-center justify-center bg-muted p-4">
    <Card class="w-full max-w-sm">
      <CardHeader>
        <CardTitle class="text-2xl">koti</CardTitle>
      </CardHeader>
      <CardContent>
        <form class="grid gap-4" @submit.prevent="submit">
          <div class="grid gap-2">
            <Label for="email">Adresse e-mail</Label>
            <Input id="email" v-model="email" type="email" autocomplete="username" required />
          </div>
          <div class="grid gap-2">
            <Label for="password">Mot de passe</Label>
            <Input id="password" v-model="password" type="password" autocomplete="current-password" required />
          </div>
          <Alert v-if="error" variant="destructive">
            <AlertDescription>{{ error }}</AlertDescription>
          </Alert>
          <Button type="submit" :disabled="busy">Se connecter</Button>
        </form>
      </CardContent>
    </Card>
  </main>
</template>
