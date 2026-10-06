export default defineNuxtRouteMiddleware((to) => {
  const config = useRuntimeConfig()
  if (config.public.appEnv === 'local' && to.path === '/') {
    return navigateTo('/threads')
  }
})
