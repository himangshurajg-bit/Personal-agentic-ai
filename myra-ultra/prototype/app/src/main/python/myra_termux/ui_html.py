# -*- coding: utf-8 -*-
"""MYRA Phone UI — ek hi HTML page. Gemini Live voice (continuous), tool cards, permission prompts."""

HTML = r"""<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1, viewport-fit=cover">
<meta name="theme-color" content="#0b0910">
<title>MYRA</title>
<style>
:root{
  --ink:#0b0910; --panel:#15111c; --panel-2:#1d1827; --line:#2c2538; --text:#f5f1f8; --muted:#a79fb6;
  --crimson:#ff3b5c; --crimson-d:#c81f3f; --ember:#ff8a4c; --mint:#38d996; --sky:#4cc9f0;
  --r-sm:12px; --r-md:18px; --r-lg:28px;
  --font: ui-sans-serif, system-ui, -apple-system, "Segoe UI", Roboto, "Noto Sans", "Noto Sans Devanagari", sans-serif;
  --safe-b: env(safe-area-inset-bottom, 0px);
  --ringc: var(--crimson);
}
*{box-sizing:border-box;-webkit-tap-highlight-color:transparent}
html,body{height:100%;margin:0;background:var(--ink);color:var(--text);font-family:var(--font);font-size:16px;line-height:1.5}
body{display:flex;flex-direction:column;max-width:560px;margin:0 auto;overflow:hidden;position:relative}
button{font:inherit;color:inherit;cursor:pointer}
:focus-visible{outline:2px solid var(--sky);outline-offset:2px}
main,.langlist,.sbody,.quick{scrollbar-width:thin;scrollbar-color:#3b3249 transparent}
main::-webkit-scrollbar,.langlist::-webkit-scrollbar,.sbody::-webkit-scrollbar{width:6px}
main::-webkit-scrollbar-thumb,.langlist::-webkit-scrollbar-thumb,.sbody::-webkit-scrollbar-thumb{background:#3b3249;border-radius:6px}
svg{width:22px;height:22px;stroke:currentColor;fill:none;stroke-width:1.8;stroke-linecap:round;stroke-linejoin:round;flex:none}
.sr{position:absolute;width:1px;height:1px;overflow:hidden;clip:rect(0 0 0 0)}

/* ---- hero: MYRA ki photo + orb ---- */
.hero{position:relative;height:clamp(250px,42vh,380px);flex:none;overflow:hidden;transition:height .45s cubic-bezier(.2,.8,.2,1)}
body.chatting .hero{height:158px}
.portrait{position:absolute;inset:0;width:100%;height:100%;object-fit:cover;object-position:50% 14%;transition:object-position .45s}
body.chatting .portrait{object-position:50% 20%}
.hero::after{content:"";position:absolute;inset:0;background:linear-gradient(180deg,#0b091099 0,#0b091000 26%,#0b091000 52%,#0b0910e6 88%,#0b0910 100%)}
header{position:absolute;z-index:3;top:0;left:0;right:0;display:flex;align-items:center;gap:10px;padding:12px 14px}
.brand{font-weight:800;letter-spacing:.18em;font-size:15px;text-shadow:0 1px 8px #000}
.brand b{color:var(--crimson)}
.ver{color:#d9d2e4;font-size:12px;text-shadow:0 1px 6px #000}
.sp{flex:1}
.chip,.iconbtn{min-height:44px;border:1px solid #ffffff2e;background:#0b0910a6;-webkit-backdrop-filter:blur(8px);backdrop-filter:blur(8px);border-radius:999px;display:inline-flex;align-items:center;gap:8px;padding:0 14px;transition:background .15s,border-color .15s}
.iconbtn{width:44px;padding:0;justify-content:center}
.chip:hover,.iconbtn:hover{background:#1d1827e6;border-color:#ffffff55}
#langchip{max-width:44vw}
#langchip span{overflow:hidden;text-overflow:ellipsis;white-space:nowrap}
.orbdock{position:absolute;z-index:3;left:0;right:0;bottom:8px;display:flex;flex-direction:column;align-items:center;gap:6px;pointer-events:none}
.orbwrap{position:relative;width:84px;height:84px;pointer-events:auto;transition:transform .45s}
body.chatting .orbwrap{transform:scale(.78)}
.orb{position:absolute;inset:0;border-radius:50%;border:2px solid var(--ringc);padding:0;background:radial-gradient(circle at 35% 28%,#ff8aa0 0,var(--crimson) 40%,var(--crimson-d) 80%);
  box-shadow:0 0 0 4px #0b0910b3,0 10px 34px -6px var(--ringc);display:grid;place-items:center;transition:transform .2s,background .4s,box-shadow .4s,border-color .4s}
.orb svg{width:36%;height:36%;stroke:#fff;stroke-width:1.9}
.orb:active{transform:scale(.95)}
.ring{position:absolute;inset:-8px;border-radius:50%;border:2px solid var(--ringc);opacity:0;pointer-events:none}
.state-listening{--ringc:var(--mint)} .state-thinking{--ringc:var(--ember)} .state-speaking{--ringc:var(--sky)}
.state-listening .orb{background:radial-gradient(circle at 35% 28%,#9cf5cd 0,var(--mint) 42%,#16845a 100%)}
.state-thinking .orb{background:radial-gradient(circle at 35% 28%,#ffc29b 0,var(--ember) 42%,#b4501b 100%);animation:breathe 1.2s ease-in-out infinite}
.state-speaking .orb{background:radial-gradient(circle at 35% 28%,#b8ecff 0,var(--sky) 42%,#1e7ea0 100%)}
.state-listening .ring,.state-speaking .ring{animation:pulse 1.5s ease-out infinite}
.live-on .orb svg{stroke-width:2.4}
@keyframes pulse{0%{transform:scale(.9);opacity:.85}100%{transform:scale(1.35);opacity:0}}
@keyframes breathe{50%{transform:scale(.93)}}
.status{font-size:14px;color:#e9e3f1;min-height:22px;text-align:center;text-shadow:0 1px 8px #000;padding:0 16px}
.greet{position:absolute;z-index:2;left:18px;bottom:128px;font-size:22px;font-weight:800;text-shadow:0 2px 14px #000;transition:opacity .3s}
body.chatting .greet{opacity:0}

/* ---- chat ---- */
main{flex:1;min-height:0;overflow-y:auto;padding:6px 16px 10px;scroll-behavior:smooth;overscroll-behavior:contain}
.msg{max-width:88%;padding:11px 14px;border-radius:var(--r-md);margin:8px 0;white-space:pre-wrap;word-wrap:break-word;overflow-wrap:anywhere}
.me{margin-left:auto;background:#3a1620;border:1px solid #5a2231;border-bottom-right-radius:6px}
.ai{background:var(--panel);border:1px solid var(--line);border-bottom-left-radius:6px}
.tool{display:flex;gap:10px;align-items:flex-start;margin:6px 0;padding:10px 12px;border-radius:var(--r-sm);background:var(--panel-2);border:1px solid var(--line);font-size:14px}
.tool svg{width:18px;height:18px;margin-top:2px}
.tool.ok svg{color:var(--mint)} .tool.bad svg{color:var(--crimson)}
.tool .n{font-weight:700}
.tool .r{color:var(--muted);word-break:break-word;white-space:pre-wrap}
.confirm{margin:10px 0;padding:14px;border-radius:var(--r-md);background:#2a1a10;border:1px solid #6a3a1c}
.confirm p{margin:0 0 12px}
.confirm .row,.setup .row{display:flex;gap:10px}
.btn{min-height:48px;flex:1;border-radius:var(--r-sm);border:1px solid var(--line);background:var(--panel-2);font-weight:700;padding:0 14px}
.btn.go{background:var(--crimson);border-color:var(--crimson);color:#fff}
.btn:disabled{opacity:.5}
.empty{color:var(--muted);text-align:center;margin:14px 12px}
.setup{margin:10px 0;padding:16px;border-radius:var(--r-md);background:var(--panel);border:1px solid var(--line);display:flex;flex-direction:column;gap:12px}
.setup h3{margin:0;font-size:17px}
.setup p{margin:0;color:var(--muted);font-size:14px}
.banner{position:fixed;left:8px;right:8px;top:8px;z-index:9;background:#3a1620;border:1px solid var(--crimson);border-radius:var(--r-sm);padding:10px 12px;font-size:13px;display:none}
.quick{display:flex;gap:8px;overflow-x:auto;padding:4px 16px 10px;scrollbar-width:none;flex:none}
.quick::-webkit-scrollbar{display:none}
.quick .chip{flex:none;font-size:14px;min-height:44px;background:var(--panel);border-color:var(--line);-webkit-backdrop-filter:none;backdrop-filter:none}
footer{padding:8px 12px calc(12px + var(--safe-b));border-top:1px solid var(--line);background:linear-gradient(#0b0910cc,#0b0910);flex:none}
.composer{display:flex;gap:8px;align-items:center}
.composer input{flex:1;min-width:0;min-height:48px;border-radius:999px;border:1px solid var(--line);background:var(--panel);color:var(--text);padding:0 18px;font:inherit}
.composer input::placeholder{color:#7d7590}
.send{width:48px;height:48px;border-radius:50%;border:0;background:var(--crimson);display:grid;place-items:center;color:#fff}
.send:disabled{background:var(--panel-2);color:var(--muted)}

/* ---- settings sheet ---- */
dialog{width:min(560px,100%);max-height:88vh;margin:auto auto 0;border:1px solid var(--line);border-bottom:0;border-radius:var(--r-lg) var(--r-lg) 0 0;background:var(--panel);color:var(--text);padding:0;overflow:hidden}
dialog::backdrop{background:#000a}
.sheet{display:flex;flex-direction:column;max-height:88vh}
.sheet h2{margin:0;font-size:18px;padding:18px 20px 8px}
.sbody{overflow-y:auto;padding:4px 20px 16px;display:flex;flex-direction:column;gap:18px}
.f{display:flex;flex-direction:column;gap:6px;font-size:14px;color:var(--muted)}
input.t{min-height:48px;border-radius:var(--r-sm);border:1px solid var(--line);background:var(--ink);color:var(--text);padding:0 14px;font:inherit}
.langlist{max-height:30vh;overflow-y:auto;border:1px solid var(--line);border-radius:var(--r-sm);background:var(--ink)}
.langlist button{display:flex;width:100%;justify-content:space-between;gap:10px;min-height:46px;align-items:center;padding:0 14px;border:0;background:none;text-align:left;border-bottom:1px solid #1d1827}
.langlist button[aria-checked=true]{background:#3a1620;font-weight:700}
.langlist small{color:var(--muted)}
.tog{display:flex;align-items:center;justify-content:space-between;min-height:48px;gap:12px}
.tog input{width:26px;height:26px;accent-color:var(--crimson);flex:none}
.sfoot{display:flex;gap:10px;padding:12px 20px calc(16px + var(--safe-b));border-top:1px solid var(--line)}
.note{font-size:13px;color:var(--muted)}
.toast{position:fixed;left:50%;bottom:92px;transform:translateX(-50%);background:var(--panel-2);border:1px solid var(--line);padding:10px 16px;border-radius:999px;font-size:14px;opacity:0;pointer-events:none;transition:opacity .2s;max-width:92vw;text-align:center;z-index:10}
.toast.on{opacity:1}
@media (prefers-reduced-motion:reduce){*{animation:none!important;transition:none!important;scroll-behavior:auto!important}}
@media (max-height:560px){.hero{height:120px!important}.greet{display:none}}
</style>
</head>
<body class="state-idle">
<div class="banner" id="banner" role="alert"></div>
<section class="hero" id="hero">
  <img class="portrait" id="portrait" alt="MYRA" decoding="async">
  <header>
    <span class="brand">MY<b>R</b>A</span><span class="ver" id="ver"></span>
    <span class="sp"></span>
    <button class="chip" id="langchip" aria-label="Language badlo"><svg viewBox="0 0 24 24"><circle cx="12" cy="12" r="9"/><path d="M3 12h18M12 3c3 3.2 3 14.8 0 18M12 3c-3 3.2-3 14.8 0 18"/></svg><span id="langname">Auto</span></button>
    <button class="iconbtn" id="gear" aria-label="Settings"><svg viewBox="0 0 24 24"><circle cx="12" cy="12" r="3"/><path d="M19.4 15a1.7 1.7 0 0 0 .3 1.9l.1.1a2 2 0 1 1-2.8 2.8l-.1-.1a1.7 1.7 0 0 0-1.9-.3 1.7 1.7 0 0 0-1 1.5V21a2 2 0 1 1-4 0v-.1a1.7 1.7 0 0 0-1.1-1.5 1.7 1.7 0 0 0-1.9.3l-.1.1a2 2 0 1 1-2.8-2.8l.1-.1a1.7 1.7 0 0 0 .3-1.9 1.7 1.7 0 0 0-1.5-1H3a2 2 0 1 1 0-4h.1a1.7 1.7 0 0 0 1.5-1.1 1.7 1.7 0 0 0-.3-1.9l-.1-.1a2 2 0 1 1 2.8-2.8l.1.1a1.7 1.7 0 0 0 1.9.3H9a1.7 1.7 0 0 0 1-1.5V3a2 2 0 1 1 4 0v.1a1.7 1.7 0 0 0 1 1.5 1.7 1.7 0 0 0 1.9-.3l.1-.1a2 2 0 1 1 2.8 2.8l-.1.1a1.7 1.7 0 0 0-.3 1.9V9a1.7 1.7 0 0 0 1.5 1H21a2 2 0 1 1 0 4h-.1a1.7 1.7 0 0 0-1.5 1z"/></svg></button>
  </header>
  <div class="greet" id="greet">Namaste</div>
  <div class="orbdock">
    <div class="orbwrap"><div class="ring"></div>
      <button class="orb" id="orb" aria-label="Live baat-cheet shuru karo"><svg viewBox="0 0 24 24"><rect x="9" y="3" width="6" height="12" rx="3"/><path d="M5 11a7 7 0 0 0 14 0M12 18v3"/></svg></button></div>
    <div class="status" id="status" aria-live="polite">Orb dabao — MYRA hamesha sunegi</div>
  </div>
</section>

<main id="log" aria-live="polite" aria-label="Baat-cheet"><div class="empty" id="empty">Orb dabake bolo — torch, battery, WhatsApp, alarm, YouTube. SMS ya call se pehle main aapse puchungi.</div></main>

<div class="quick" id="quick" role="toolbar" aria-label="Quick commands"></div>

<footer>
  <form class="composer" id="form" autocomplete="off">
    <label class="sr" for="msg">Message</label>
    <input id="msg" type="text" placeholder="Ya yahan likho…" enterkeyhint="send" maxlength="2000">
    <button class="send" id="send" aria-label="Bhejo" disabled><svg viewBox="0 0 24 24"><path d="M5 12h14M13 6l6 6-6 6"/></svg></button>
  </form>
</footer>

<dialog id="sheet" aria-labelledby="stitle">
  <div class="sheet">
    <h2 id="stitle">Settings</h2>
    <div class="sbody">
      <label class="f">Gemini API key<input class="t" id="key" type="text" inputmode="text" autocapitalize="off" autocomplete="off" autocorrect="off" spellcheck="false" placeholder="AIza…"><span class="note" id="keynote"></span></label>
      <label class="f">Aapka naam<input class="t" id="uname" type="text" maxlength="30" placeholder="Jaise: Vikash" autocomplete="off"></label>
      <div class="f" style="gap:8px">Language<input class="t" id="lsearch" type="search" placeholder="Language dhundo (Hindi, Tamil, Spanish…)" aria-label="Language dhundo">
        <div class="langlist" id="langlist" role="radiogroup" aria-label="Languages"></div></div>
      <div class="tog"><span>Headphones lage hain<br><span class="note">ON = beech mein bol ke MYRA ko rok sakte ho. OFF = jab MYRA bole tab mic band (echo nahi aata)</span></span><input type="checkbox" id="bargein" aria-label="Headphones mode"></div>
      <button class="btn" id="reset" type="button">Chat saaf karo</button>
    </div>
    <div class="sfoot"><button class="btn" id="close" type="button">Band karo</button><button class="btn go" id="save" type="button">Save</button></div>
  </div>
</dialog>
<div class="toast" id="toast" role="status"></div>

<script>
(function(){
"use strict";
var $=function(id){return document.getElementById(id)};
var qs=new URLSearchParams(location.search), TOKEN=qs.get("t")||sessionStorage.getItem("mt")||"";
if(qs.get("t")){sessionStorage.setItem("mt",TOKEN);history.replaceState(null,"",location.pathname)}
var S={state:null,cursor:0,busy:false,mode:"idle",lang:"auto",bargein:false,pickLang:null};
var L={on:false,ws:null,ctx:null,stream:null,proc:null,src:null,playT:0,srcs:[],handle:null,cfg:null,mi:0,ready:false,uDiv:null,aDiv:null,heard:false,tick:null,bytes:0,retry:0};
try{S.bargein=localStorage.getItem("bargein")==="1"}catch(e){}
$("portrait").src="/a/myra.jpg?t="+encodeURIComponent(TOKEN);

function banner(t){var b=$("banner");b.textContent=t;b.style.display="block";clearTimeout(banner.t);banner.t=setTimeout(function(){b.style.display="none"},9000)}
window.addEventListener("error",function(e){banner("Page error: "+(e.message||e))});
window.addEventListener("unhandledrejection",function(e){banner("Error: "+((e.reason&&e.reason.message)||e.reason))});
function api(path,body){
  var o={headers:{"X-Myra-Token":TOKEN,"Content-Type":"application/json"}};
  if(body!==undefined){o.method="POST";o.body=JSON.stringify(body)}
  return fetch(path,o).then(function(r){return r.json().then(function(j){j._s=r.status;return j},function(){return {_s:r.status,error:"Server ne galat jawab diya ("+r.status+")"}})});
}
function toast(t){var el=$("toast");el.textContent=t;el.classList.add("on");clearTimeout(toast.t);toast.t=setTimeout(function(){el.classList.remove("on")},3200)}
function setMode(m,txt){
  S.mode=m;var c=[];if(document.body.classList.contains("chatting"))c.push("chatting");c.push("state-"+m);if(L.on)c.push("live-on");document.body.className=c.join(" ");
  var def={idle:"Orb dabao — MYRA hamesha sunegi",listening:"Sun rahi hoon…",thinking:"Soch rahi hoon…",speaking:"Bol rahi hoon…"};
  $("status").textContent=txt||def[m]||"";
  $("orb").setAttribute("aria-label",L.on?"Live band karo":"Live baat-cheet shuru karo");
}
var ICON={ok:'<svg viewBox="0 0 24 24"><path d="M5 12.5l4.5 4.5L19 7.5"/></svg>',bad:'<svg viewBox="0 0 24 24"><circle cx="12" cy="12" r="9"/><path d="M12 7v6M12 16.5v.5"/></svg>'};
function chatting(){$("empty").style.display="none";document.body.classList.add("chatting")}
function add(cls,text){chatting();var d=document.createElement("div");d.className=cls;d.textContent=text;$("log").appendChild(d);scroll();return d}
function scroll(){var l=$("log");l.scrollTop=l.scrollHeight}
function addTool(e){
  var d=document.createElement("div");d.className="tool "+(e.ok?"ok":"bad");
  d.innerHTML=(e.ok?ICON.ok:ICON.bad)+'<div><div class="n"></div><div class="r"></div></div>';
  d.querySelector(".n").textContent=e.name.replace(/_/g," ");d.querySelector(".r").textContent=e.result;
  chatting();$("log").appendChild(d);scroll();
}
function addLaunch(e){
  var d=document.createElement("div");d.className="confirm";
  d.innerHTML='<p></p><div class="row"><a class="btn go" style="display:grid;place-items:center;text-decoration:none"></a></div>';
  d.querySelector("p").textContent="Android ne background se app kholne nahi diya — ek tap karo:";
  var a=d.querySelector("a");a.textContent=e.label;a.href=e.url;chatting();$("log").appendChild(d);scroll();
  if(navigator.vibrate)navigator.vibrate(60);
}
function addLaunch(e){
  var d=document.createElement("div");d.className="confirm";
  d.innerHTML='<p></p><div class="row"><a class="btn go" style="display:grid;place-items:center;text-decoration:none"></a></div>';
  d.querySelector("p").textContent="Android ne background se app kholne nahi diya — ek tap karo:";
  var a=d.querySelector("a");a.textContent=e.label;a.href=e.url;chatting();$("log").appendChild(d);scroll();
  if(navigator.vibrate)navigator.vibrate(60);
}
function addConfirm(e){
  var d=document.createElement("div");d.className="confirm";d.setAttribute("role","alertdialog");
  d.innerHTML='<p></p><div class="row"><button class="btn" data-a="0">Mana karo</button><button class="btn go" data-a="1">Haan, karo</button></div>';
  d.querySelector("p").textContent=e.text;chatting();
  d.querySelectorAll("button").forEach(function(b){b.onclick=function(){
    d.querySelectorAll("button").forEach(function(x){x.disabled=true});
    api("/api/confirm",{id:e.id,ok:b.dataset.a==="1"}).then(function(){d.querySelector("p").textContent=e.text+(b.dataset.a==="1"?"  — ✓ permission di":"  — ✗ mana kiya");var r=d.querySelector(".row");if(r)r.remove()});
  }});
  $("log").appendChild(d);scroll();var g=d.querySelector(".go");if(g)g.focus({preventScroll:true});
  if(navigator.vibrate)navigator.vibrate(80);
}

/* ---- events (tool cards, permission prompts, REST chat replies) ---- */
function poll(){
  api("/api/events?after="+S.cursor+"&wait=15").then(function(j){
    if(j._s===401){banner("Link purana hai — Termux ka naya link kholo");return}
    (j.events||[]).forEach(handle);poll();
  }).catch(function(){setTimeout(poll,1500)});
}
function handle(e){
  S.cursor=Math.max(S.cursor,e.n);
  if(e.type==="tool")addTool(e);
  else if(e.type==="confirm")addConfirm(e);
  else if(e.type==="launch")addLaunch(e);
  else if(e.type==="launch")addLaunch(e);
  else if(e.type==="reply"){add("msg ai",e.text||"…")}
  else if(e.type==="error"){add("msg ai",e.text);S.busy=false;upd();if(!L.on)setMode("idle")}
  else if(e.type==="done"){S.busy=false;upd();if(!L.on)setMode("idle")}
}
function upd(){$("send").disabled=!$("msg").value.trim()||(S.busy&&!L.on)}

/* ---- typed message: Live ho to Live ko, warna REST chat ---- */
function send(text){
  text=(text||"").trim();if(!text)return;
  $("msg").value="";upd();add("msg me",text);
  if(L.on&&L.ready){wsend({realtimeInput:{text:text}});setMode("thinking");return}
  if(S.busy)return;S.busy=true;upd();setMode("thinking");
  api("/api/chat",{text:text}).then(function(j){
    if(j.error){S.busy=false;upd();setMode("idle");if(/key/i.test(j.error)){showSetup()}else add("msg ai",j.error)}
  }).catch(function(){S.busy=false;upd();setMode("idle");add("msg ai","Server se connection toot gaya. Termux mein myra-termux web dobara chalao.")});
}

/* ================= GEMINI LIVE (continuous voice) ================= */
function wsend(o){if(L.ws&&L.ws.readyState===1)L.ws.send(JSON.stringify(o))}
function b64ToBytes(b){var s=atob(b),n=s.length,u=new Uint8Array(n);for(var i=0;i<n;i++)u[i]=s.charCodeAt(i);return u}
function bytesToB64(u){var s="",i,CH=0x8000;for(i=0;i<u.length;i+=CH)s+=String.fromCharCode.apply(null,u.subarray(i,i+CH));return btoa(s)}
function liveStart(){
  if(L.on)return;
  api("/api/live").then(function(cfg){
    if(cfg._s!==200||!cfg.key){showSetup();toast("Pehle Gemini API key daalo");return}
    L.cfg=cfg;L.on=true;L.mi=0;L.retry=0;L.heard=false;setMode("thinking","Jud rahi hoon…");openAudio();connect()
  });
}
function liveStop(msg){
  L.on=false;L.ready=false;
  try{if(L.ws){L.ws.onclose=null;L.ws.close()}}catch(e){}L.ws=null;
  try{if(L.proc){L.proc.disconnect();L.proc.onaudioprocess=null}}catch(e){}
  try{if(L.src)L.src.disconnect()}catch(e){}
  try{if(L.stream)L.stream.getTracks().forEach(function(t){t.stop()})}catch(e){}
  stopPlayback();clearInterval(L.tick);L.stream=L.proc=L.src=null;
  try{if(L.ctx)L.ctx.close()}catch(e){}L.ctx=null;
  setMode("idle",msg);
}
function openAudio(){
  var AC=window.AudioContext||window.webkitAudioContext;
  L.ctx=new AC();if(L.ctx.state==="suspended")L.ctx.resume();L.playT=0;
  L.tick=setInterval(function(){
    if(!L.on||!L.ctx)return;
    var talking=L.playT>L.ctx.currentTime+0.02;
    if(talking&&S.mode!=="speaking")setMode("speaking");
    else if(!talking&&S.mode==="speaking")setMode("listening");
  },120);
  if(!navigator.mediaDevices||!navigator.mediaDevices.getUserMedia){toast("Is browser mein mic nahi (https/localhost chahiye) — text se baat karo");return Promise.resolve()}
  return navigator.mediaDevices.getUserMedia({audio:{echoCancellation:true,noiseSuppression:true,autoGainControl:true,channelCount:1}}).then(function(st){
    L.stream=st;L.src=L.ctx.createMediaStreamSource(st);L.proc=L.ctx.createScriptProcessor(4096,1,1);
    L.proc.onaudioprocess=onMic;L.src.connect(L.proc);L.proc.connect(L.ctx.destination);
  }).catch(function(err){
    toast(err&&err.name==="NotAllowedError"?"Mic ki permission do (address bar ke lock icon se) — tab tak text se baat karo":"Mic nahi mila: "+(err&&err.name));
  });
}
function onMic(ev){
  if(!L.ready)return;
  var talking=L.ctx&&L.playT>L.ctx.currentTime-0.25;
  if(talking&&!S.bargein)return;                       // MYRA bol rahi ho to mic band (echo/khud ko sunna nahi)
  var inp=ev.inputBuffer.getChannelData(0),ratio=L.ctx.sampleRate/16000,n=Math.floor(inp.length/ratio),out=new Int16Array(n);
  for(var i=0;i<n;i++){var a=Math.floor(i*ratio),b=Math.min(inp.length,Math.floor((i+1)*ratio)),s=0,c=0;for(var k=a;k<b;k++){s+=inp[k];c++}
    var v=c?s/c:0;v=Math.max(-1,Math.min(1,v));out[i]=v<0?v*32768:v*32767}
  wsend({realtimeInput:{audio:{mimeType:"audio/pcm;rate=16000",data:bytesToB64(new Uint8Array(out.buffer))}}});
}
function connect(){
  if(!L.on)return;
  var model=L.cfg.models[Math.min(L.mi,L.cfg.models.length-1)];
  var url="wss://generativelanguage.googleapis.com/ws/google.ai.generativelanguage.v1beta.GenerativeService.BidiGenerateContent?key="+encodeURIComponent(L.cfg.key);
  var ws=new WebSocket(url);L.ws=ws;L.ready=false;
  ws.onopen=function(){
    var setup={setup:{model:"models/"+model,
      generationConfig:{responseModalities:["AUDIO"],speechConfig:{voiceConfig:{prebuiltVoiceConfig:{voiceName:L.cfg.voice||"Aoede"}}}},
      systemInstruction:{parts:[{text:L.cfg.system}]},
      tools:[{functionDeclarations:L.cfg.tools}],
      inputAudioTranscription:{},outputAudioTranscription:{},
      contextWindowCompression:{slidingWindow:{}},sessionResumption:L.handle?{handle:L.handle}:{}}};
    ws.send(JSON.stringify(setup));
  };
  ws.onmessage=function(ev){
    var done=function(t){try{onServer(JSON.parse(t))}catch(e){banner("Live parse error: "+e.message)}};
    if(typeof ev.data==="string")done(ev.data);else ev.data.text().then(done);
  };
  ws.onclose=function(ev){
    if(L.ws!==ws||!L.on)return;
    L.ready=false;
    if(!L.heard&&L.mi<L.cfg.models.length-1){L.mi++;setTimeout(connect,300);return}      // pehla model na chale to dusra
    if(L.retry++<5){setMode("thinking","Dobara jud rahi hoon…");setTimeout(connect,Math.min(4000,600*L.retry))}
    else{liveStop("Live band ho gaya"+(ev.reason?": "+ev.reason:""));toast("Live connection toot gaya: "+(ev.reason||ev.code))}
  };
  ws.onerror=function(){};
}
function finishTurn(){L.uDiv=null;L.aDiv=null}
function onServer(m){
  if(m.setupComplete){L.ready=true;L.heard=true;L.retry=0;setMode("listening");return}
  if(m.sessionResumptionUpdate&&m.sessionResumptionUpdate.newHandle)L.handle=m.sessionResumptionUpdate.newHandle;
  if(m.goAway){try{L.ws.close()}catch(e){}return}
  if(m.toolCall){setMode("thinking");(m.toolCall.functionCalls||[]).forEach(runTool);return}
  var sc=m.serverContent;if(!sc)return;
  if(sc.interrupted){stopPlayback();}
  var mt=sc.modelTurn;
  if(mt&&mt.parts)mt.parts.forEach(function(p){if(p.inlineData&&/audio\/pcm/.test(p.inlineData.mimeType||""))playPcm(b64ToBytes(p.inlineData.data))});
  if(sc.inputTranscription&&sc.inputTranscription.text){
    if(!L.uDiv)L.uDiv=add("msg me","");L.uDiv.textContent+=sc.inputTranscription.text;scroll();
  }
  if(sc.outputTranscription&&sc.outputTranscription.text){
    if(!L.aDiv)L.aDiv=add("msg ai","");L.aDiv.textContent+=sc.outputTranscription.text;scroll();
  }
  if(sc.turnComplete)finishTurn();
}
function runTool(c){
  api("/api/tool",{name:c.name,args:c.args||{}}).then(function(j){
    wsend({toolResponse:{functionResponses:[{id:c.id,name:c.name,response:{result:String(j.result!==undefined?j.result:(j.error||"❌ tool fail"))}}]}});
  }).catch(function(e){
    wsend({toolResponse:{functionResponses:[{id:c.id,name:c.name,response:{result:"❌ "+e.message}}]}});
  });
}
function playPcm(u8){
  if(!L.ctx)return;
  var n=Math.floor(u8.length/2),f=new Float32Array(n),dv=new DataView(u8.buffer,u8.byteOffset,n*2);
  for(var i=0;i<n;i++)f[i]=dv.getInt16(i*2,true)/32768;
  var buf=L.ctx.createBuffer(1,n,24000);buf.copyToChannel(f,0);
  var s=L.ctx.createBufferSource();s.buffer=buf;s.connect(L.ctx.destination);
  var t=Math.max(L.ctx.currentTime+0.03,L.playT);s.start(t);L.playT=t+buf.duration;L.srcs.push(s);L.bytes+=u8.length;
  s.onended=function(){var k=L.srcs.indexOf(s);if(k>=0)L.srcs.splice(k,1)};
}
function stopPlayback(){L.srcs.forEach(function(s){try{s.stop()}catch(e){}});L.srcs=[];L.playT=0}

/* ---- settings / setup ---- */
function showSetup(){
  if($("setupcard"))return;chatting();
  var d=document.createElement("div");d.className="setup";d.id="setupcard";
  d.innerHTML='<h3>Pehle Gemini API key daalo</h3><p>Free key: aistudio.google.com/apikey → "Create API key" → copy → yahan paste karo.</p><input class="t" id="key2" type="text" autocapitalize="off" autocomplete="off" autocorrect="off" spellcheck="false" placeholder="AIza…" aria-label="Gemini API key"><div class="row"><button class="btn go" id="key2save" type="button">Key save karo</button></div><p id="key2msg" role="status"></p>';
  $("log").appendChild(d);scroll();
  $("key2save").onclick=function(){
    var k=$("key2").value.trim();if(!k){$("key2msg").textContent="Key paste karo";return}
    $("key2save").disabled=true;$("key2msg").textContent="Check kar rahi hoon…";
    saveSettings({api_key:k}).then(function(ok){$("key2save").disabled=false;if(ok){d.remove();toast("Key save ho gayi ✓ — ab orb dabao");}else $("key2msg").textContent=saveSettings.err||"Save nahi hua"});
  };
}
function saveSettings(b){
  return api("/api/settings",b).then(function(j){
    if(j._s!==200||j.ok===false){saveSettings.err=j.error||"Save nahi hua ("+j._s+")";banner(saveSettings.err);return false}
    if(j.state)applyState(j.state);return true;
  }).catch(function(e){saveSettings.err="Server tak nahi pahunch paya: "+e.message;banner(saveSettings.err);return false});
}
function renderLangs(filter){
  var Lg=(S.state&&S.state.languages)||[],box=$("langlist"),f=(filter||"").toLowerCase();box.innerHTML="";
  var items=[{code:"auto",name:"Auto — Hinglish",native:""}].concat(Lg).filter(function(x){return !f||(x.name+" "+x.native+" "+x.code).toLowerCase().indexOf(f)>=0}).slice(0,80);
  items.forEach(function(x){var b=document.createElement("button");b.type="button";b.setAttribute("role","radio");b.setAttribute("aria-checked",String(x.code===(S.pickLang||S.lang)));
    b.innerHTML="<span></span><small></small>";b.firstChild.textContent=x.name;b.lastChild.textContent=x.native||"";
    b.onclick=function(){S.pickLang=x.code;[].forEach.call(box.children,function(c){c.setAttribute("aria-checked","false")});b.setAttribute("aria-checked","true")};box.appendChild(b)});
  if(!items.length)box.innerHTML='<div class="note" style="padding:14px">Koi language nahi mili</div>';
}
function openSheet(){
  $("uname").value=(S.state&&S.state.name)||"";$("bargein").checked=S.bargein;S.pickLang=S.lang;$("lsearch").value="";$("key").value="";renderLangs("");
  $("keynote").textContent=S.state&&S.state.has_key?"Key set hai ✓ (naya daalo to badal jayegi)":"aistudio.google.com/apikey se free key lo";
  try{$("sheet").showModal()}catch(e){$("sheet").setAttribute("open","")}
}
function applyState(st){
  S.state=st;S.lang=st.language||"auto";$("ver").textContent="v"+st.version;
  var l=(st.languages||[]).filter(function(x){return x.code===S.lang})[0];$("langname").textContent=l?l.name.replace(/ \(.*/,""):"Auto";
  $("greet").textContent=st.name?("Namaste, "+st.name):"Namaste";
}
$("save").onclick=function(){
  var b={name:$("uname").value},k=$("key").value.trim();if(k)b.api_key=k;var langChanged=S.pickLang&&S.pickLang!==S.lang;if(langChanged)b.language=S.pickLang;
  S.bargein=$("bargein").checked;try{localStorage.setItem("bargein",S.bargein?"1":"0")}catch(e){}
  $("save").disabled=true;
  saveSettings(b).then(function(ok){$("save").disabled=false;if(!ok)return;$("sheet").close();toast(k?"Key save ho gayi ✓":"Save ho gaya");
    var sc=$("setupcard");if(sc&&k)sc.remove();
    if(langChanged&&L.on){L.handle=null;try{L.ws.close()}catch(e){}}});
};
$("close").onclick=function(){$("sheet").close()};
$("reset").onclick=function(){api("/api/reset",{}).then(function(){$("log").innerHTML='<div class="empty" id="empty">Chat saaf. Naya kuch bolo.</div>';document.body.classList.remove("chatting");L.handle=null;$("sheet").close()})};
$("gear").onclick=openSheet;$("langchip").onclick=openSheet;
$("lsearch").oninput=function(){renderLangs(this.value)};
$("orb").onclick=function(){if(L.on)liveStop("Live band — orb dabao to dobara shuru");else liveStart()};
$("msg").oninput=upd;
$("form").onsubmit=function(e){e.preventDefault();send($("msg").value)};
var Q=[["Battery","battery kitni hai?"],["Torch on","torch on karo"],["Location","meri location batao"],["WhatsApp","whatsapp kholo"],["YouTube","youtube kholo"],["Alarm","subah 6 baje ka alarm lagao"],["Wi-Fi","wifi ka haal batao"],["Camera","camera kholo"]];
Q.forEach(function(q){var b=document.createElement("button");b.type="button";b.className="chip";b.textContent=q[0];b.onclick=function(){send(q[1])};$("quick").appendChild(b)});
setMode("idle");
api("/api/state").then(function(st){
  if(st._s===401){$("status").textContent="Link expire — Termux mein naya link kholo";return}
  applyState(st);if(!st.has_key)showSetup();poll();
}).catch(function(){banner("Server se connect nahi ho paya")});
})();
</script>
</body>
</html>
"""
