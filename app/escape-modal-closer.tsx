"use client";

import { useEffect } from "react";

export function EscapeModalCloser() {
  useEffect(() => {
    const onKeyDown = (event: KeyboardEvent) => {
      if (event.key !== "Escape" || event.defaultPrevented) return;

      const backdrops = Array.from(
        document.querySelectorAll<HTMLElement>(
          ".modal-backdrop, .nested-modal-backdrop",
        ),
      ).filter((element) => {
        const style = window.getComputedStyle(element);
        return (
          style.display !== "none" &&
          style.visibility !== "hidden" &&
          style.pointerEvents !== "none" &&
          element.getClientRects().length > 0
        );
      });
      const topmost = backdrops.at(-1);
      if (!topmost) return;

      const explicitClose = topmost.querySelector<HTMLButtonElement>(
        '.modal-close, button[aria-label*="닫기"]',
      );
      const headerButtons = Array.from(
        topmost.querySelectorAll<HTMLButtonElement>(
          ".modal > header button, .student-modal > header button, section > header button, form > header button",
        ),
      );
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
