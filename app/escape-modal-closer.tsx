"use client";

import { useEffect } from "react";

export function EscapeModalCloser() {
  useEffect(() => {
    const onKeyDown = (event: KeyboardEvent) => {
      if (event.key !== "Escape" || event.defaultPrevented) return;

      const backdrops = Array.from(document.querySelectorAll<HTMLElement>(".modal-backdrop")).filter((element) => {
        const style = window.getComputedStyle(element);
        return style.display !== "none" && style.visibility !== "hidden" && style.pointerEvents !== "none";
      });
      const topmost = backdrops.at(-1);
      if (!topmost) return;

      const explicitClose = topmost.querySelector<HTMLButtonElement>('button[aria-label="닫기"], button[aria-label="창 닫기"], button[aria-label="모달 닫기"]');
      const headerButtons = Array.from(topmost.querySelectorAll<HTMLButtonElement>(".student-modal > header button, section > header button"));
      const closeButton = explicitClose ?? headerButtons.find((button) => button.textContent?.trim() === "×" || button.textContent?.trim() === "✕");

      if (closeButton && !closeButton.disabled) {
        event.preventDefault();
        event.stopPropagation();
        closeButton.click();
      }
    };

    window.addEventListener("keydown", onKeyDown, true);
    return () => window.removeEventListener("keydown", onKeyDown, true);
  }, []);

  return null;
}
