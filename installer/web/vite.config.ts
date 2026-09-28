import react from '@vitejs/plugin-react'
import tailwindcss from '@tailwindcss/vite'
import { defineConfig } from 'vite'

// La interfaz se compila acá y dist/ va al repo: el asistente se muestra antes de que
// haya Node en el equipo (lo sirve installer/server.py con el Python del sistema).
// Para desarrollar: bash install.sh --gui en una terminal y `npm run dev` apuntando a
// su puerto con IB_API=http://127.0.0.1:8421.
export default defineConfig({
  plugins: [react(), tailwindcss()],
  server: {
    proxy: { '/api': process.env.IB_API || 'http://127.0.0.1:8421' },
  },
})
