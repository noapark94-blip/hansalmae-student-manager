import { defineConfig, loadEnv } from "vite";
import vinext from "vinext";

export default defineConfig(({ mode }) => {
  const env = loadEnv(mode, process.cwd(), "");
  return {
    envPrefix: ["VITE_", "NEXT_PUBLIC_"],
    define: {
      "process.env.NEXT_PUBLIC_SUPABASE_URL": JSON.stringify(env.NEXT_PUBLIC_SUPABASE_URL),
      "process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY": JSON.stringify(env.NEXT_PUBLIC_SUPABASE_ANON_KEY),
    },
    plugins: [vinext()],
  };
});
