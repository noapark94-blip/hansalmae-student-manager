"use client";

import { useEffect, useMemo, useState } from "react";
import type { SupabaseClient } from "@supabase/supabase-js";
import type { UserRole } from "./supabase";
import type { View } from "./page";
import { HansalmaeIcon, viewIcon } from "./hansalmae-icons";
import { reorderById, useSortableOrder } from "./use-sortable-order";

type MenuItem = { id: View; label: string; icon: string };
type MenuFolder = { id: string; name: string; itemIds: View[] };
type MenuLayout = { folders: MenuFolder[] };

const hiddenStandaloneViews = new Set<View>(["bulk-import", "bulk-accounts", "guide", "attendance", "makeups"]);
const menuLabel = (item:MenuItem) => item.id === "assignments" ? "첨삭 관리" : item.label;

const defaultLayout: MenuLayout = {
  folders: [
    { id: "main", name: "바로가기", itemIds: ["dashboard"] },
    { id: "classes", name: "클래스 관리", itemIds: ["class-management", "assignments"] },
    { id: "students", name: "학생 관리", itemIds: ["students"] },
    { id: "schedules", name: "시간표", itemIds: ["schedule", "corrections", "transport"] },
    { id: "lessons", name: "수업 관리", itemIds: ["consultations"] },
    { id: "operations", name: "학원 운영", itemIds: ["communications", "tuition", "tuition-settings", "analytics", "backup", "audit"] },
    { id: "accounts", name: "계정 설정", itemIds: ["settings", "my-account"] },
  ],
};

export function SidebarNavigation({ supabase, role, items, activeView, onSelect }: { supabase: SupabaseClient; role: UserRole; items: MenuItem[]; activeView: View; onSelect: (view: View) => void }) {
  const usableItems = useMemo(() => items.filter((item) => !hiddenStandaloneViews.has(item.id) && (item.id !== "assignments" || role === "admin" || role === "teacher")), [items, role]);
  const [layout, setLayout] = useState<MenuLayout>(defaultLayout);
  const [collapsed, setCollapsed] = useState<Record<string, boolean>>({});
  const [editing, setEditing] = useState(false);

  useEffect(() => {
    let active = true;
    void supabase.rpc("get_app_menu_layout").then(({ data }) => {
      if (active && isMenuLayout(data)) setLayout(normalizeLayout(data, usableItems));
    });
    return () => { active = false; };
  }, [supabase, usableItems]);

  const visible = useMemo(() => new Set(usableItems.map((item) => item.id)), [usableItems]);
  const itemMap = useMemo(() => new Map(usableItems.map((item) => [item.id, item])), [usableItems]);
  const folders = layout.folders.map((folder) => ({ ...folder, itemIds: folder.itemIds.filter((id) => visible.has(id)) })).filter((folder) => folder.itemIds.length);

  return <>
    <nav aria-label="주요 메뉴" className="folder-navigation">
      <button type="button" className="menu-customize-button" onClick={() => setEditing(true)}><span className="nav-icon"><HansalmaeIcon name="menu" /></span>내 메뉴 편집</button>
      {folders.map((folder) => <section className="nav-folder" key={folder.id}>
        <button type="button" className="nav-folder-title" aria-expanded={!collapsed[folder.id]} onClick={() => setCollapsed((current) => ({ ...current, [folder.id]: !current[folder.id] }))}>
          <span>{folder.name}</span><i>{collapsed[folder.id] ? "＋" : "－"}</i>
        </button>
        {!collapsed[folder.id] && <div className="nav-folder-items">{folder.itemIds.map((id) => { const item = itemMap.get(id); return item ? <button type="button" key={id} className={activeView === id ? "active" : ""} onClick={() => onSelect(id)}><span className="nav-icon"><HansalmaeIcon name={viewIcon[id]} /></span>{menuLabel(item)}</button> : null; })}</div>}
      </section>)}
    </nav>
    {editing && <MenuLayoutEditor supabase={supabase} items={usableItems} value={layout} onClose={() => setEditing(false)} onSaved={(next) => { setLayout(next); setEditing(false); }} />}
  </>;
}

function MenuLayoutEditor({ supabase, items, value, onClose, onSaved }: { supabase: SupabaseClient; items: MenuItem[]; value: MenuLayout; onClose: () => void; onSaved: (layout: MenuLayout) => void }) {
  const [draft, setDraft] = useState<MenuLayout>(() => mergeMissingItems(value, items));
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState("");
  const itemMap = new Map(items.map((item) => [item.id, item]));
  const folderSortable=useSortableOrder((activeId,overId)=>setDraft((current)=>({folders:reorderById(current.folders,activeId,overId)})));
  const itemSortable=useSortableOrder((activeId,overId)=>setDraft((current)=>{
    const source=current.folders.find((folder)=>folder.itemIds.includes(activeId as View));
    const target=current.folders.find((folder)=>folder.itemIds.includes(overId as View));
    if(!source||!target)return current;
    if(source.id===target.id)return{folders:current.folders.map((folder)=>folder.id===source.id?{...folder,itemIds:reorderById(folder.itemIds.map((id)=>({id})),activeId,overId).map((item)=>item.id as View)}:folder)};
    return{folders:current.folders.map((folder)=>folder.id===source.id?{...folder,itemIds:folder.itemIds.filter((id)=>id!==activeId)}:folder.id===target.id?{...folder,itemIds:[...folder.itemIds.slice(0,folder.itemIds.indexOf(overId as View)),activeId as View,...folder.itemIds.slice(folder.itemIds.indexOf(overId as View))]}:folder)};
  }));

  const addFolder = () => setDraft((current) => ({ folders: [...current.folders, { id: crypto.randomUUID(), name: "새 폴더", itemIds: [] }] }));
  const renameFolder = (id: string, name: string) => setDraft((current) => ({ folders: current.folders.map((folder) => folder.id === id ? { ...folder, name } : folder) }));
  const moveFolder = (index: number, direction: -1 | 1) => setDraft((current) => ({ folders: move(current.folders, index, direction) }));
  const deleteFolder = (id: string) => setDraft((current) => { const target = current.folders.find((folder) => folder.id === id); const rest = current.folders.filter((folder) => folder.id !== id); if (!rest.length) return current; return { folders: rest.map((folder, index) => index === 0 ? { ...folder, itemIds: [...folder.itemIds, ...(target?.itemIds ?? [])] } : folder) }; });
  const assign = (itemId: View, folderId: string) => setDraft((current) => ({ folders: current.folders.map((folder) => ({ ...folder, itemIds: folder.id === folderId ? [...folder.itemIds.filter((id) => id !== itemId), itemId] : folder.itemIds.filter((id) => id !== itemId) })) }));
  const moveItem = (folderId: string, index: number, direction: -1 | 1) => setDraft((current) => ({ folders: current.folders.map((folder) => folder.id === folderId ? { ...folder, itemIds: move(folder.itemIds, index, direction) } : folder) }));
  const save = async () => { setSaving(true); setError(""); const cleaned = { folders: draft.folders.map((folder) => ({ ...folder, name: folder.name.trim() || "이름 없는 폴더" })) }; const { error: saveError } = await supabase.rpc("save_app_menu_layout", { p_layout: cleaned }); if (saveError) { setError("내 메뉴 구성을 저장하지 못했습니다. Supabase 최신 적용 여부를 확인해 주세요."); setSaving(false); return; } onSaved(cleaned); };

  return <div className="modal-backdrop menu-editor-backdrop" onMouseDown={(event) => { if (event.target === event.currentTarget) onClose(); }}><section className="menu-editor" role="dialog" aria-modal="true" aria-labelledby="menu-editor-title">
    <header><div><p className="eyebrow">개인 메뉴 설정</p><h2 id="menu-editor-title">내 메뉴 폴더 편집</h2><span>폴더와 메뉴 순서는 내 계정에만 적용됩니다.</span></div><button type="button" aria-label="닫기" onClick={onClose}>×</button></header>
    <div className="menu-editor-toolbar"><button type="button" className="secondary-button" onClick={addFolder}>＋ 새 폴더</button><small>끌어서 이동하세요. 모바일에서는 손잡이를 길게 누르세요.</small></div>
    <div className="menu-folder-editor-list">{draft.folders.map((folder, folderIndex) => <article key={folder.id} {...folderSortable.itemProps(folder.id)} className={folderSortable.draggingId===folder.id?"dragging":""}>
      <header><button type="button" data-drag-handle aria-label={`${folder.name} 폴더 이동`}>☷</button><input aria-label="폴더 이름" value={folder.name} onChange={(event) => renameFolder(folder.id, event.target.value)} /><span><button type="button" onClick={() => moveFolder(folderIndex, -1)} disabled={folderIndex === 0}>▲</button><button type="button" onClick={() => moveFolder(folderIndex, 1)} disabled={folderIndex === draft.folders.length - 1}>▼</button><button type="button" className="danger" onClick={() => deleteFolder(folder.id)} disabled={draft.folders.length === 1}>삭제</button></span></header>
      <div>{folder.itemIds.map((itemId, itemIndex) => { const item = itemMap.get(itemId); return item ? <p key={itemId} {...itemSortable.itemProps(itemId)} className={itemSortable.draggingId===itemId?"dragging":""}><button type="button" data-drag-handle aria-label={`${menuLabel(item)} 이동`}>☷</button><span className="nav-icon"><HansalmaeIcon name={viewIcon[item.id]} /></span><b>{menuLabel(item)}</b><select value={folder.id} onChange={(event) => assign(itemId, event.target.value)}>{draft.folders.map((option) => <option key={option.id} value={option.id}>{option.name}</option>)}</select><button type="button" onClick={() => moveItem(folder.id, itemIndex, -1)} disabled={itemIndex === 0}>▲</button><button type="button" onClick={() => moveItem(folder.id, itemIndex, 1)} disabled={itemIndex === folder.itemIds.length - 1}>▼</button></p> : null; })}{folder.itemIds.length === 0 && <em>이 폴더에 배정된 메뉴가 없습니다.</em>}</div>
    </article>)}</div>
    {error && <p className="form-error" role="alert">{error}</p>}
    <footer><button type="button" className="secondary-button" onClick={onClose}>취소</button><button type="button" className="primary" onClick={() => void save()} disabled={saving}>{saving ? "저장 중…" : "메뉴 구성 저장"}</button></footer>
  </section></div>;
}

function normalizeLayout(layout:MenuLayout,items:MenuItem[]):MenuLayout{
  const next=mergeMissingItems(layout,items);
  const assignments=next.folders.some(folder=>folder.itemIds.includes("assignments"));
  if(!assignments)return next;
  const folders:MenuFolder[]=next.folders.map(folder=>({...folder,itemIds:folder.itemIds.filter(id=>id!=="assignments")}));
  let classIndex=folders.findIndex(folder=>folder.id==="classes");
  if(classIndex<0){folders.splice(Math.min(1,folders.length),0,{id:"classes",name:"클래스 관리",itemIds:[]});classIndex=folders.findIndex(folder=>folder.id==="classes");}
  const classItems:View[]=folders[classIndex].itemIds.filter(id=>id!=="class-management");
  const itemIds:View[]=["class-management",...classItems,"assignments"].filter((id,index,array)=>array.indexOf(id)===index) as View[];
  folders[classIndex]={...folders[classIndex],name:"클래스 관리",itemIds};
  return{folders};
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
  if (!folders.length) return defaultLayout;
  if (missing.length) folders[0] = { ...folders[0], itemIds:[...folders[0].itemIds,...missing] };
  return { folders };
}

function isMenuLayout(value: unknown): value is MenuLayout {
  if (!value || typeof value !== "object" || !("folders" in value) || !Array.isArray((value as MenuLayout).folders)) return false;
  return (value as MenuLayout).folders.every((folder) => typeof folder.id === "string" && typeof folder.name === "string" && Array.isArray(folder.itemIds));
}

function move<T>(values: T[], index: number, direction: -1 | 1) { const target = index + direction; if (target < 0 || target >= values.length) return values; const next = [...values]; [next[index], next[target]] = [next[target], next[index]]; return next; }
