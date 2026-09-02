import type { MetadataRoute } from "next";

export default function manifest(): MetadataRoute.Manifest {
  return {
    name: "한살매 수업노트",
    short_name: "한살매노트",
    description: "학생·학부모·선생님을 위한 수업, 시간표, 출결 및 학습 기록 서비스",
    start_url: "/",
    display: "standalone",
    background_color: "#f8eef3",
    theme_color: "#922d61",
    orientation: "portrait",
    icons: [
      {
        src: "/app-icon-192-v5.png",
        sizes: "192x192",
        type: "image/png",
        purpose: "any",
      },
      {
        src: "/app-icon-512-v5.png",
        sizes: "512x512",
        type: "image/png",
        purpose: "any",
      },
      {
        src: "/app-icon-maskable-512-v5.png",
        sizes: "512x512",
        type: "image/png",
        purpose: "maskable",
      },
    ],
  };
}
