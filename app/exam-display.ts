const GENERIC_EXAM_TYPES = new Set(["", "시험", "test", "exam"]);

export function examCategoryLabel(examType?: string | null, examTitle?: string | null) {
  const rawType = examType?.trim() ?? "";
  const searchable = `${rawType} ${examTitle?.trim() ?? ""}`.toLowerCase();

  if (/(영단어|고등단어|중등단어|단어\s*시험|vocabulary)/i.test(searchable)) return "영단어 시험";
  if (/(모의\s*고사|모의고사|mock)/i.test(searchable)) return "모의고사";
  if (/(주간\s*평가|주간평가|weekly)/i.test(searchable)) return "주간평가";
  if (/(월간\s*평가|월간평가|monthly)/i.test(searchable)) return "월간평가";
  if (/중간\s*고사/i.test(searchable)) return "중간고사";
  if (/기말\s*고사/i.test(searchable)) return "기말고사";
  if (/(대학수학능력시험|수능)/i.test(searchable)) return "수능";
  if (/첨삭\s*시험/i.test(searchable)) return "첨삭 시험";
  if (/(기타\s*시험|custom)/i.test(searchable)) return "기타 시험";

  return GENERIC_EXAM_TYPES.has(rawType.toLowerCase()) ? "기타 시험" : rawType;
}
