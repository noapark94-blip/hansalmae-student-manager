"use client";

import { useEffect } from "react";

const SUBJECTS=["국어","영어","수학"] as const;

export function CorrectionSubjectTabs(){
  useEffect(()=>{
    const sync=()=>{
      document.querySelectorAll<HTMLElement>(".correction-slot-students .correction-student").forEach(card=>{
        card.classList.remove("subject-국어","subject-영어","subject-수학");
        const meta=card.querySelector("small")?.textContent||"";
        const subject=SUBJECTS.find(item=>meta.includes(item));
        if(subject)card.classList.add(`subject-${subject}`);
      });

      const groups=document.querySelector<HTMLElement>(".correction-subject-groups");
      if(!groups)return;

      const sections=SUBJECTS.map(subject=>({
        subject,
        section:groups.querySelector<HTMLElement>(`.correction-subject-group.subject-${subject}`),
      })).filter((item):item is {subject:(typeof SUBJECTS)[number];section:HTMLElement}=>Boolean(item.section));
      if(!sections.length)return;

      let tabs=groups.previousElementSibling as HTMLElement|null;
      if(!tabs?.classList.contains("correction-subject-tabs")){
        tabs=document.createElement("div");
        tabs.className="correction-subject-tabs";
        tabs.setAttribute("role","tablist");
        tabs.setAttribute("aria-label","첨삭 과목 선택");
        groups.parentElement?.insertBefore(tabs,groups);
      }

      const available=sections.map(item=>item.subject);
      let active=tabs.dataset.activeSubject||"";
      if(!available.includes(active as (typeof SUBJECTS)[number])) active=available.includes("영어")?"영어":available[0];
      tabs.dataset.activeSubject=active;

      const signature=sections.map(item=>`${item.subject}:${item.section.querySelector(".correction-subject-header span")?.textContent?.trim()||""}`).join("|");
      if(tabs.dataset.signature!==signature){
        tabs.dataset.signature=signature;
        tabs.replaceChildren();
        sections.forEach(item=>{
          const count=item.section.querySelector(".correction-subject-header span")?.textContent?.trim()||"";
          const button=document.createElement("button");
          button.type="button";
          button.dataset.subject=item.subject;
          button.setAttribute("role","tab");
          button.innerHTML=`<span>${item.subject}</span>${count?`<em>${count}</em>`:""}`;
          button.addEventListener("click",()=>{
            tabs!.dataset.activeSubject=item.subject;
            sync();
          });
          tabs!.appendChild(button);
        });
      }

      tabs.querySelectorAll<HTMLButtonElement>("button").forEach(button=>{
        const selected=button.dataset.subject===active;
        button.classList.toggle("active",selected);
        button.setAttribute("aria-selected",selected?"true":"false");
      });
      sections.forEach(item=>{
        const selected=item.subject===active;
        item.section.hidden=!selected;
        item.section.classList.toggle("tab-active",selected);
      });
    };

    let queued=false;
    const requestSync=()=>{
      if(queued)return;
      queued=true;
      requestAnimationFrame(()=>{queued=false;sync()});
    };
    sync();
    const observer=new MutationObserver(requestSync);
    observer.observe(document.body,{childList:true,subtree:true,characterData:true});
    return()=>observer.disconnect();
  },[]);

  return null;
}
