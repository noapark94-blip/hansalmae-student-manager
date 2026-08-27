export function familyTeacherName(value: string | null | undefined) {
  const name = value?.trim().replace(/\s*선생님$/, "").replace(/\s*T$/i, "") ?? "";
  if (!name) return "";
  const letters = Array.from(name);
  const displayName = /^[가-힣]+$/.test(name) && letters.length >= 3 ? letters.slice(1).join("") : name;
  return `${displayName}T`;
}

export function familyTeacherNames(value: string | null | undefined) {
  if (!value?.trim()) return "";
  return value.split(/\s*(?:,|·)\s*/).filter(Boolean).map(familyTeacherName).join(" · ");
}
