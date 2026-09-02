self.addEventListener("install", () => self.skipWaiting());
self.addEventListener("activate", event => event.waitUntil(self.clients.claim()));

// Keep the app under an active service-worker scope so Android Chrome can
// evaluate PWA installability immediately on the login screen.
self.addEventListener("fetch", event => {
  if (event.request.method !== "GET") return;
  event.respondWith(fetch(event.request));
});

self.addEventListener("push", event => {
  const payload = event.data?.json() ?? {};
  event.waitUntil(self.registration.showNotification(payload.title ?? "한살매 수업노트", {
    body: payload.body ?? "새 알림이 도착했습니다.",
    icon: "/app-icon-192-v11.png",
    badge: "/app-icon-192-v11.png",
    tag: payload.notificationId ?? "hansalmae-notification",
    data: { url: payload.url ?? "/", notificationId: payload.notificationId },
  }));
});

self.addEventListener("notificationclick", event => {
  event.notification.close();
  const target = new URL(event.notification.data?.url ?? "/", self.location.origin).href;
  event.waitUntil(clients.matchAll({ type: "window", includeUncontrolled: true }).then(windows => {
    const existing = windows.find(client => client.url.startsWith(self.location.origin));
    if (existing) {
      return existing.navigate(target).then(client => client?.focus());
    }
    return clients.openWindow(target);
  }));
});
