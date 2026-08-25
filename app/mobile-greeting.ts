"use client";

import { useEffect, useState } from "react";

function greetingForCurrentTime() {
  const hourPart = new Intl.DateTimeFormat("ko-KR", {
    timeZone: "Asia/Seoul",
    hour: "2-digit",
    hourCycle: "h23",
  }).formatToParts(new Date()).find((part) => part.type === "hour")?.value;
  const hour = Number(hourPart);
  if (hour >= 5 && hour < 12) return "좋은 아침이에요";
  if (hour >= 12 && hour < 18) return "오늘도 반갑습니다";
  return "오늘도 수고 많으셨어요";
}

export function useMobileGreeting() {
  const [greeting, setGreeting] = useState(greetingForCurrentTime);
  useEffect(() => {
    const refresh = () => setGreeting(greetingForCurrentTime());
    refresh();
    const timer = window.setInterval(refresh, 60_000);
    const refreshWhenVisible = () => {
      if (document.visibilityState === "visible") refresh();
    };
    window.addEventListener("focus", refresh);
    document.addEventListener("visibilitychange", refreshWhenVisible);
    return () => {
      window.clearInterval(timer);
      window.removeEventListener("focus", refresh);
      document.removeEventListener("visibilitychange", refreshWhenVisible);
    };
  }, []);
  return greeting;
}
