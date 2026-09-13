"use client";
import {createContext,useCallback,useContext,useEffect,useLayoutEffect,useRef,useState,type ReactNode} from 'react';
const StartupContext=createContext<null|(()=>()=>void)>(null);

// Track real first-page loaders; later navigation never reopens the launch screen.
export function InitialPageGate({children,fallback}:{children:ReactNode;fallback:ReactNode}){
 const [starting,setStarting]=useState(true);
 const pending=useRef(0),finished=useRef(false),frame=useRef<number|null>(null),mounted=useRef(false);
 const cancel=useCallback(()=>{if(frame.current!==null)cancelAnimationFrame(frame.current);frame.current=null;},[]);
 const settle=useCallback(()=>{cancel();if(!mounted.current||finished.current||pending.current)return;frame.current=requestAnimationFrame(()=>{frame.current=requestAnimationFrame(()=>{frame.current=null;if(mounted.current&&!pending.current){finished.current=true;setStarting(false);}});});},[cancel]);
 const register=useCallback(()=>{pending.current++;cancel();let active=true;return()=>{if(!active)return;active=false;pending.current--;settle();};},[cancel,settle]);
 useEffect(()=>{mounted.current=true;settle();return()=>{mounted.current=false;cancel();};},[cancel,settle]);
 return <StartupContext.Provider value={starting?register:null}>
  {starting&&<div style={{position:'fixed',inset:0,zIndex:5000,overflow:'auto'}}>{fallback}</div>}
  <div style={{display:'contents'}} inert={starting} aria-hidden={starting||undefined}>{children}</div>
 </StartupContext.Provider>;
}
export function useInitialPageLoading(){const register=useContext(StartupContext);useLayoutEffect(()=>register?.(),[register]);return register!==null;}
