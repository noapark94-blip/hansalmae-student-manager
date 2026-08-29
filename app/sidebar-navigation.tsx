"use client";

import { useEffect, useMemo, useState } from "react";
import type { SupabaseClient } from "@supabase/supabase-js";
import type { UserRole } from "./supabase";
import type { View } from "./page";
import { HansalmaeIcon, viewIcon } from "./hansalmae-icons";

type MenuItem = { id: View; label: string; icon: string };
type MenuFolder = { id: string; name: string; itemIds: View[] };
type MenuLayout = { folders: MenuFolder[]; labels?: Partial<Record<View, string>> };

const hiddenStandaloneViews = new Set<View>(["bulk-import", "bulk-accounts", "guide", "attendance"]);
const defaultMenuLabel = (item: MenuItem) => item.id === "assignments" ? "첨삭 관리" : item.label;

const defaultLayout: MenuLayout = {
  folders: [
    { id: "main", name: "바로가기", itemIds: ["dashboard"] },
    { id: "classes", name: "클래스 관리", itemIds: ["class-management", "assignments", "vocabulary-tests"] },
    { id: "students", name: "학생 관리", itemIds: ["students"] },
    { id: "schedules", name: "시간표", itemIds: ["schedule", "corrections", "transport"] },
    { id: "lessons", name: "수업 관리", itemIds: ["makeups", "consultations"] },
    { id: "operations", name: "학원 운영", itemIds: ["alimtalk", "communications", "tuition", "analytics", "backup", "audit"] },
    { id: "accounts", name: "계정 설정", itemIds: ["settings", "my-account"] },
  ],
  labels: {},
};

export function SidebarNavigation({ supabase, role, items, activeView, onSelect }: { supabase: SupabaseClient; role: UserRole; items: MenuItem[]; activeView: View; onSelect: (view: View) => void }) {
  const usableItems = useMemo(() => items.filter((item) => !hiddenStandaloneViews.has(item.id) && (item.id !== "assignments" || ["admin","teacher","assistant","manager"].includes(role))), [items, role]);
  const [layout, setLayout] = useState<MenuLayout>(defaultLayout);
  const [collapsed, setCollapsed] = useState<Record<string, boolean>>({});
  const [editing, setEditing] = useState(false);
  const [draft, setDraft] = useState<MenuLayout>(defaultLayout);
  const [saving, setSaving] = useState(false);
  const [editError, setEditError] = useState("");

  useEffect(() => {
    let active = true;
    void supabase.rpc("get_app_menu_layout").then(({ data }) => {
      if (active && isMenuLayout(data)) setLayout(mergeMissingItems(data, usableItems));
    });
    return () => { active = false; };
  }, [supabase, usableItems]);

  const visible = useMemo(() => new Set(usableItems.map((item) => item.id)), [usableItems]);
  const itemMap = useMemo(() => new Map(usableItems.map((item) => [item.id, item])), [usableItems]);
  const folders = layout.folders.map((folder) => ({ ...folder, itemIds: folder.itemIds.filter((id) => visible.has(id)) })).filter((folder) => folder.itemIds.length);

  const displayLabel = (source: MenuLayout, item: MenuItem) => source.labels?.[item.id]?.trim() || defaultMenuLabel(item);
  const selectItem=(id:View)=>onSelect(id);
  const isActive=(id:View)=>activeView===id;

  const beginEditing = () => {
    setDraft(mergeMissingItems(layout, usableItems));
    setCollapsed({});
    setEditError("");
    setEditing(true);
  };
  const cancelEditing = () => { setEditing(false); setEditError(""); };
  const addFolder = () => setDraft((current) => ({ ...current, folders: [...current.folders, { id: crypto.randomUUID(), name: "새 폴더", itemIds: [] }] }));
  const renameFolder = (id: string, name: string) => setDraft((current) => ({ ...current, folders: current.folders.map((folder) => folder.id === id ? { ...folder, name } : folder) }));
  const moveFolder = (index: number, direction: -1 | 1) => setDraft((current) => ({ ...current, folders: move(current.folders, index, direction) }));
  const deleteFolder = (id: string) => setDraft((current) => {
    if (current.folders.length <= 1) return current;
    const index = current.folders.findIndex((folder) => folder.id === id);
    if (index < 0) return current;
    const target = current.folders[index];
    const destinationIndex = index > 0 ? index - 1 : 1;
    const destinationId = current.folders[destinationIndex]?.id;
    return {
      ...current,
      folders: current.folders
        .filter((folder) => folder.id !== id)
        .map((folder) => folder.id === destinationId ? { ...folder, itemIds: [...folder.itemIds, ...target.itemIds.filter((itemId) => !folder.itemIds.includes(itemId))] } : folder),
    };
  });
  const renameItem = (itemId: View, name: string) => setDraft((current) => ({ ...current, labels: { ...(current.labels ?? {}), [itemId]: name } }));
  const moveItemSmart = (folderIndex: number, itemIndex: number, direction: -1 | 1) => setDraft((current) => {
    const folders = current.folders.map((folder) => ({ ...folder, itemIds: [...folder.itemIds] }));
    const source = folders[folderIndex];
    if (!source) return current;
    const itemId = source.itemIds[itemIndex];
    if (!itemId) return current;
    const targetIndex = itemIndex + direction;
    if (targetIndex >= 0 && targetIndex < source.itemIds.length) {
      [source.itemIds[itemIndex], source.itemIds[targetIndex]] = [source.itemIds[targetIndex], source.itemIds[itemIndex]];
      return { ...current, folders };
    }
    const nextFolderIndex = folderIndex + direction;
    const nextFolder = folders[nextFolderIndex];
    if (!nextFolder) return current;
    source.itemIds.splice(itemIndex, 1);
    if (direction < 0) nextFolder.itemIds.push(itemId);
    else nextFolder.itemIds.unshift(itemId);
    return { ...current, folders };
  });
  const saveEditing = async () => {
    setSaving(true);
    setEditError("");
    const cleaned: MenuLayout = {
      folders: draft.folders.map((folder) => ({ ...folder, name: folder.name.trim() || "이름 없는 폴더" })),
      labels: Object.fromEntries(Object.entries(draft.labels ?? {}).map(([key, value]) => [key, String(value ?? "").trim()])) as Partial<Record<View, string>>,
    };
    const { error } = await supabase.rpc("save_app_menu_layout", { p_layout: cleaned });
    if (error) { setEditError("메뉴 구성을 저장하지 못했습니다."); setSaving(false); return; }
    setLayout(cleaned);
    setSaving(false);
    setEditing(false);
  };

  if (editing) {
    return <nav aria-label="메뉴 편집" className="folder-navigation sidebar-direct-editor">
      <div className="sidebar-direct-toolbar">
        <strong>메뉴 편집</strong>
        <div><button type="button" onClick={addFolder}>＋ 폴더</button><button type="button" onClick={cancelEditing}>취소</button><button type="button" className="save" onClick={() => void saveEditing()} disabled={saving}>{saving ? "저장 중" : "완료"}</button></div>
      </div>
      {draft.folders.map((folder, folderIndex) => <section className="nav-folder nav-folder-edit" key={folder.id}>
        <div className="nav-folder-title nav-folder-title-edit">
          <input aria-label="폴더 이름" value={folder.name} onChange={(event) => renameFolder(folder.id, event.target.value)} />
          <span className="folder-order-actions">
            <button type="button" aria-label="폴더 위로" onClick={() => moveFolder(folderIndex, -1)} disabled={folderIndex === 0}>↑</button>
            <button type="button" aria-label="폴더 아래로" onClick={() => moveFolder(folderIndex, 1)} disabled={folderIndex === draft.folders.length - 1}>↓</button>
            <button type="button" className="delete" aria-label="폴더 삭제" onClick={() => deleteFolder(folder.id)} disabled={draft.folders.length === 1}>×</button>
          </span>
        </div>
        <div className="nav-folder-items nav-folder-items-edit">
          {folder.itemIds.map((id, itemIndex) => {
            const item = itemMap.get(id);
            if (!item) return null;
            const canUp = !(folderIndex === 0 && itemIndex === 0);
            const canDown = !(folderIndex === draft.folders.length - 1 && itemIndex === folder.itemIds.length - 1);
            return <div className="nav-edit-row" key={id}>
              <span className="nav-icon"><HansalmaeIcon name={viewIcon[id]} /></span>
              <input aria-label={`${defaultMenuLabel(item)} 이름`} value={draft.labels?.[id] ?? defaultMenuLabel(item)} onChange={(event) => renameItem(id, event.target.value)} />
              <span className="nav-edit-row-arrows"><button type="button" aria-label="위로" onClick={() => moveItemSmart(folderIndex, itemIndex, -1)} disabled={!canUp}>↑</button><button type="button" aria-label="아래로" onClick={() => moveItemSmart(folderIndex, itemIndex, 1)} disabled={!canDown}>↓</button></span>
            </div>;
          })}
          {folder.itemIds.length === 0 && <p className="nav-edit-empty">비어 있는 폴더</p>}
        </div>
      </section>)}
      {editError && <p className="sidebar-edit-error">{editError}</p>}
    </nav>;
  }

  return <nav aria-label="주요 메뉴" className="folder-navigation">
    <button type="button" className="menu-customize-button" onClick={beginEditing}><span className="nav-icon"><HansalmaeIcon name="menu" /></span>메뉴 편집</button>
    {folders.map((folder) => <section className="nav-folder" key={folder.id}>
      <button type="button" className="nav-folder-title" aria-expanded={!collapsed[folder.id]} onClick={() => setCollapsed((current) => ({ ...current, [folder.id]: !current[folder.id] }))}>
        <span>{folder.name}</span><i>{collapsed[folder.id] ? "＋" : "－"}</i>
      </button>
      {!collapsed[folder.id] && <div className="nav-folder-items">{folder.itemIds.map((id) => { const item = itemMap.get(id); return item ? <button type="button" key={id} className={isActive(id)?"active":""} onClick={() => selectItem(id)}><span className="nav-icon"><HansalmaeIcon name={viewIcon[id]} /></span>{displayLabel(layout, item)}</button> : null; })}</div>}
    </section>)}
  </nav>;
}

function mergeMissingItems(layout: MenuLayout, items: MenuItem[]): MenuLayout {
  const validIds = new Set(items.map((item) => item.id));
  const used = new Set<View>();
  const folders:MenuFolder[] = layout.folders.map((folder) => ({ ...folder, itemIds: folder.itemIds.filter((id) => {
    if (!validIds.has(id) || used.has(id)) return false;
    used.add(id);
    return true;
  }) }));
  const missing:View[] = items.map((item) => item.id).filter((id) => !used.has(id));
  if (!folders.length) return { ...defaultLayout, labels: layout.labels ?? {} };
  for (const id of missing) {
    const defaultFolderId=defaultLayout.folders.find(folder=>folder.itemIds.includes(id))?.id;
    const targetIndex=Math.max(0,folders.findIndex(folder=>folder.id===defaultFolderId));
    folders[targetIndex]={...folders[targetIndex],itemIds:[...folders[targetIndex].itemIds,id]};
  }
  const validLabelEntries = Object.entries(layout.labels ?? {}).filter(([id]) => validIds.has(id as View));
  return { folders, labels: Object.fromEntries(validLabelEntries) as Partial<Record<View, string>> };
}

function isMenuLayout(value: unknown): value is MenuLayout {
  if (!value || typeof value !== "object" || !("folders" in value) || !Array.isArray((value as MenuLayout).folders)) return false;
  return (value as MenuLayout).folders.every((folder) => typeof folder.id === "string" && typeof folder.name === "string" && Array.isArray(folder.itemIds));
}

function move<T>(values: T[], index: number, direction: -1 | 1) { const target = index + direction; if (target < 0 || target >= values.length) return values; const next = [...values]; [next[index], next[target]] = [next[target], next[index]]; return next; }
