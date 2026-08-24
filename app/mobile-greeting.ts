"use client";

import { useEffect, useState } from "react";

function greetingForCurrentTime() {
  const hour = Number(new Intl.DateTimeFormat("ko-KR", { timeZone: "Asia/Seoul", hour: "2-digit", hourCycle: "h23" }).format(new Date()));
  if (hour >= 5 && hour < 12) return "좋은 아침이에요";
  if (hour >= 12 && hour < 18) return "오늘도 반갑습니다";
  return "오늘도 수고 많으셨어요";
}

export function useMobileGreeting() {
  const [greeting, setGreeting] = useState("오늘도 반갑습니다");
  useEffect(() => {
    const refresh = () => setGreeting(greetingForCurrentTime());
    refresh();
    const timer = window.setInterval(refresh, 60_000);
    return () => window.clearInterval(timer);
  }, []);
  return greeting;
}
