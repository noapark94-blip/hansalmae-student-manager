import { generate, type Config } from "./engine";
self.onmessage = (event: MessageEvent<Config>) => {
  try {
    self.postMessage(generate(event.data));
  } catch {
    self.postMessage({
      candidates: [],
      problems: [
        "후보 생성 중 오류가 발생했습니다. 조건을 확인하고 다시 시도해 주세요.",
      ],
    });
  }
};
