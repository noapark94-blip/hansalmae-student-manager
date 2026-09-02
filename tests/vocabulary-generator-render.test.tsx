import assert from "node:assert/strict";
import test from "node:test";
import React from "react";
import { renderToString } from "react-dom/server";
import { VocabularyTestGenerator } from "../app/vocabulary-test-generator";

test("vocabulary generator renders all source modes without crashing", () => {
  const supabase = {} as never;
  const profile = {
    id: "teacher-test",
    display_name: "테스트 선생님",
    role: "teacher",
  } as never;

  const html = renderToString(
    <VocabularyTestGenerator supabase={supabase} profile={profile} />,
  );

  assert.match(html, /DB에서 출제/);
  assert.match(html, /직접 입력/);
  assert.match(html, /DB \+ 직접 입력/);
});
