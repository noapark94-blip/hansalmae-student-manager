"use client";

import { useEffect } from "react";

const SUBJECTS=["국어","영어","수학"] as const;

export function CorrectionSubjectTabs(){
  useEffect(()=>{
    const setup=()=>{
      const groups=document.querySelector<HTMLElement>(".correction-subject-groups");
      if(!groups)return;
      if(groups.dataset.tabsReady==="1")return;

      const sections=SUBJECTS.map(subject=>({
        subject,
        section:groups.querySelector<HTMLElement>(`.correction-subject-group.subject-${subject}`),
      })).filter(item=>item.section);

      if(!sections.length)return;
      groups.dataset.tabsReady="1";

      const tabs=document.createElement("div");
      tabs.className="correction-subject-tabs";
      tabs.setAttribute("role","tablist");
      tabs.setAttribute("aria-label","첨삭 과목 선택");
      groups.parentElement?.insertBefore(tabs,groups);

      const activate=(subject:string)=>{
        tabs.querySelectorAll<HTMLButtonElement>("button").forEach(button=>{
          const active=button.dataset.subject===subject;
          button.classList.toggle("active",active);
          button.setAttribute("aria-selected",active?"true":"false");
        });
        sections.forEach(item=>{
          const active=item.subject===subject;
          item.section!.hidden=!active;
          item.section!.classList.toggle("tab-active",active);
        });
      };

      sections.forEach(item=>{
        const count=item.section!.querySelector(".correction-subject-header span")?.textContent?.trim()||"";
        const button=document.createElement("button");
        button.type="button";
        button.dataset.subject=item.subject;
        button.setAttribute("role","tab");
        button.innerHTML=`<span>${item.subject}</span>${count?`<em>${count}</em>`:""}`;
        button.addEventListener("click",()=>activate(item.subject));
        tabs.appendChild(button);
      });

      const preferred=sections.find(item=>item.subject==="영어")?.subject??sections[0].subject;
      activate(preferred);
    };

    setup();
    const observer=new MutationObserver(()=>setup());
    observer.observe(document.body,{childList:true,subtree:true});
    return()=>observer.disconnect();
  },[]);

  return null;
}
