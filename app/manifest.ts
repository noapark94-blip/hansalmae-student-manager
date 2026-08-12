import type { MetadataRoute } from "next";

export default function manifest(): MetadataRoute.Manifest {
  return {
    name: "한살매 입시전문학원",
    short_name: "한살매",
    description: "한살매입시전문학원 학생·수업·출결 통합 관리",
    start_url: "/",
    display: "standalone",
    background_color: "#faf8f5",
    theme_color: "#922d61",
    orientation: "portrait",
    icons: [
      {
        src: "/app-icon-192.png",
        sizes: "192x192",
        type: "image/png",
        purpose: "any",
      },
      {
        src: "/app-icon-512.png",
        sizes: "512x512",
        type: "image/png",
        purpose: "any",
      },
      {
        src: "/app-icon-maskable-512.png",
        sizes: "512x512",
        type: "image/png",
        purpose: "maskable",
      },
    ],
  };
}
