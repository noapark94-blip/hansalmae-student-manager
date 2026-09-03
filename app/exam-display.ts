const GENERIC_EXAM_TYPES = new Set(["", "시험", "test", "exam"]);

export function examCategoryLabel(examType?: string | null) {
  const rawType = examType?.trim() ?? "";
  return GENERIC_EXAM_TYPES.has(rawType.toLowerCase()) ? "기타 시험" : rawType;
}
