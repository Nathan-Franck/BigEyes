import { defineConfig } from 'vite'
import preact from '@preact/preset-vite'
import topLevelAwait from 'vite-plugin-top-level-await';
import zipPack from 'vite-plugin-zip-pack';

// https://vitejs.dev/config/
export default defineConfig({
  base: '',
  plugins: [
    preact(),
    topLevelAwait(),
    zipPack(),
    {
      name: 'wasm-loader',
      configureServer(server) {
        return () => {
          server.middlewares.use((req, res, next) => {
            if (req.originalUrl.endsWith('.wasm')) {
              res.type('application/wasm');
            }
            next();
          });
        };
      },
    },
  ],
})
