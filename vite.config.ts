import { defineConfig } from "vite";
import vinext from "vinext";

export default defineConfig({
  envPrefix: ["VITE_", "NEXT_PUBLIC_"],
  plugins: [vinext()],
});
