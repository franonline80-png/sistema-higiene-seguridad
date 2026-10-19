"use strict";
const SESSION_TABLE="sesiones_usuario";
let currentSessionId=null,sessionStartedAt=null,sessionAccessToken=null,sessionClosePromise=null,sessionMode="database";
function localSessionKey(){return "hys_session_history_"+(user&&user.id?user.id:"unknown")}
function readLocalSessions(){
 try{const v=JSON.parse(localStorage.getItem(localSessionKey())||"[]");return Array.isArray(v)?v:[]}catch(e){return []}
}
function writeLocalSessions(rows){try{localStorage.setItem(localSessionKey(),JSON.stringify(rows.slice(0,500)))}catch(e){console.warn("No se pudo guardar historial local",e)}}
function upsertLocalSession(row){
 const rows=readLocalSessions(),i=rows.findIndex(x=>x.id===row.id);
 if(i>=0)rows[i]=Object.assign({},rows[i],row);else rows.unshift(row);
 writeLocalSessions(rows);
}
function newLocalId(){return "local-"+Date.now()+"-"+Math.random().toString(36).slice(2,10)}
function sessionDuration(seconds){
 if(seconds===null||seconds===undefined||!Number.isFinite(Number(seconds)))return "No disponible";
 let n=Math.max(0,Math.floor(Number(seconds)));const d=Math.floor(n/86400);n%=86400;const h=Math.floor(n/3600);n%=3600;const m=Math.floor(n/60);const s=n%60;
 return (d?d+" d ":"")+(h?String(h).padStart(2,"0")+" h ":"")+(String(m).padStart(2,"0")+" min ")+String(s).padStart(2,"0")+" s";
}
function sessionDate(value){
 if(!value)return "—";const d=new Date(value);if(Number.isNaN(d.getTime()))return String(value);
 return d.toLocaleString("es-AR",{day:"2-digit",month:"2-digit",year:"numeric",hour:"2-digit",minute:"2-digit",second:"2-digit",hour12:false});
}
function sessionStatus(row){
 if(row.estado==="cerrada")return '<span class="badge ok">Cerrada</span>';
 if(row.estado==="interrumpida")return '<span class="badge off">Interrumpida</span>';
 const age=Date.now()-new Date(row.inicio).getTime();
 return age>24*60*60*1000?'<span class="badge off">Sin cierre · revisar</span>':'<span class="badge warn">Abierta</span>';
}
function closeLocalSession(){
 if(!currentSessionId||!sessionStartedAt)return;
 const ended=new Date(),duration=Math.max(0,Math.floor((ended.getTime()-new Date(sessionStartedAt).getTime())/1000));
 upsertLocalSession({id:currentSessionId,usuario_id:user?user.id:"",inicio:sessionStartedAt,fin:ended.toISOString(),duracion_segundos:duration,estado:"cerrada",almacenamiento:"dispositivo"});
 currentSessionId=null;sessionStartedAt=null;sessionStorage.removeItem("hys_session_id");sessionStorage.removeItem("hys_session_started_at");
}
async function startSessionTracking(){
 const {data:auth}=await db.auth.getSession();sessionAccessToken=auth&&auth.session?auth.session.access_token:null;
 if(!user||!sessionAccessToken)return;
 const existingId=sessionStorage.getItem("hys_session_id");
 if(existingId){
  if(existingId.startsWith("local-")){
   const row=readLocalSessions().find(r=>r.id===existingId&&r.estado==="abierta");
   if(row){currentSessionId=row.id;sessionStartedAt=row.inicio;sessionMode="local";return}
  }else{
   const {data:existing,error}=await db.from(SESSION_TABLE).select("id,inicio,estado").eq("id",existingId).eq("usuario_id",user.id).maybeSingle();
   if(!error&&existing&&existing.estado==="abierta"){currentSessionId=existing.id;sessionStartedAt=existing.inicio;sessionMode="database";return}
  }
  sessionStorage.removeItem("hys_session_id");sessionStorage.removeItem("hys_session_started_at");
 }
 try{
  const {data,error}=await db.from(SESSION_TABLE).insert({usuario_id:user.id}).select("id,inicio").single();
  if(error)throw error;
  currentSessionId=data.id;sessionStartedAt=data.inicio;sessionMode="database";
 }catch(e){
  console.warn("Historial de sesiones de Supabase no disponible; se usará almacenamiento local en este dispositivo.",e);
  currentSessionId=newLocalId();sessionStartedAt=new Date().toISOString();sessionMode="local";
  upsertLocalSession({id:currentSessionId,usuario_id:user.id,inicio:sessionStartedAt,fin:null,duracion_segundos:null,estado:"abierta",almacenamiento:"dispositivo"});
 }
 sessionStorage.setItem("hys_session_id",currentSessionId);sessionStorage.setItem("hys_session_started_at",sessionStartedAt);
}
async function closeCurrentSession(){
 if(sessionClosePromise)return sessionClosePromise;if(!currentSessionId||!sessionStartedAt)return;
 if(sessionMode==="local"){closeLocalSession();return}
 const id=currentSessionId,ended=new Date(),duration=Math.max(0,Math.floor((ended.getTime()-new Date(sessionStartedAt).getTime())/1000));
 sessionClosePromise=(async()=>{
  const {error}=await db.from(SESSION_TABLE).update({fin:ended.toISOString(),duracion_segundos:duration,estado:"cerrada"}).eq("id",id).eq("usuario_id",user?user.id:"").eq("estado","abierta");
  if(error){
   upsertLocalSession({id:id,usuario_id:user?user.id:"",inicio:sessionStartedAt,fin:ended.toISOString(),duracion_segundos:duration,estado:"cerrada",almacenamiento:"dispositivo"});
  }
  currentSessionId=null;sessionStartedAt=null;sessionStorage.removeItem("hys_session_id");sessionStorage.removeItem("hys_session_started_at");
 })();
 try{await sessionClosePromise}finally{sessionClosePromise=null}
}
function closeSessionOnPageExit(){
 if(!currentSessionId||!sessionStartedAt)return;
 if(sessionMode==="local"){closeLocalSession();return}
 if(!sessionAccessToken)return;
 const id=currentSessionId,ended=new Date(),duration=Math.max(0,Math.floor((ended.getTime()-new Date(sessionStartedAt).getTime())/1000));
 const body=JSON.stringify({fin:ended.toISOString(),duracion_segundos:duration,estado:"cerrada"});
 try{fetch(SUPABASE_URL+"/rest/v1/"+SESSION_TABLE+"?id=eq."+encodeURIComponent(id)+"&usuario_id=eq."+encodeURIComponent(user?user.id:"")+"&estado=eq.abierta",{method:"PATCH",headers:{"apikey":SUPABASE_ANON_KEY,"Authorization":"Bearer "+sessionAccessToken,"Content-Type":"application/json","Prefer":"return=minimal"},body:body,keepalive:true})}catch(e){}
 currentSessionId=null;sessionStartedAt=null;sessionStorage.removeItem("hys_session_id");sessionStorage.removeItem("hys_session_started_at");
}
window.addEventListener("pagehide",closeSessionOnPageExit);
async function renderSessionsModule(){
 const v=$("view");
 v.innerHTML='<div class="page-title"><div><h2>Actividad y sesiones</h2><p>Historial de accesos de tu cuenta, con fecha, hora y duración registrada.</p></div><button class="btn btn-blue" id="sessionsReload" type="button">↻ Actualizar historial</button></div><div class="session-summary"><div class="dashboard-metric"><div class="dashboard-metric-label">Última sesión registrada</div><div class="dashboard-metric-number" id="sessionLastDate" style="font-size:19px">—</div><div class="dashboard-metric-foot">Fecha y hora de inicio</div></div><div class="dashboard-metric"><div class="dashboard-metric-label">Duración última sesión cerrada</div><div class="dashboard-metric-number session-duration" id="sessionLastDuration" style="font-size:22px">—</div><div class="dashboard-metric-foot">Tiempo entre inicio y cierre</div></div><div class="dashboard-metric"><div class="dashboard-metric-label">Sesiones registradas</div><div class="dashboard-metric-number" id="sessionCount">—</div><div class="dashboard-metric-foot">Últimos 100 registros</div></div></div><div class="panel"><h3>Historial de sesiones</h3><p class="muted">El historial se guarda en la base de datos cuando está habilitada. Si no está disponible, se conserva localmente en este dispositivo y navegador; esos registros no se sincronizan con otros dispositivos.</p><div id="sessionsStatus" class="status" role="status">Consultando historial...</div><div class="table-wrap"><table><thead><tr><th>Inicio</th><th>Cierre</th><th>Duración</th><th>Estado</th></tr></thead><tbody id="sessionsBody"><tr><td colspan="4" class="empty">Cargando...</td></tr></tbody></table></div></div>';
 $("sessionsReload").onclick=()=>renderSessionsModule();await loadSessionHistory();
}
async function loadSessionHistory(){
 const body=$("sessionsBody"),status=$("sessionsStatus");if(!body||!user)return;status.textContent="Consultando historial...";
 let rows=[],usingLocal=false;
 try{
  const {data,error}=await db.from(SESSION_TABLE).select("id,usuario_id,inicio,fin,duracion_segundos,estado").eq("usuario_id",user.id).order("inicio",{ascending:false}).limit(100);
  if(error)throw error;rows=data||[];
 }catch(e){
  console.warn("Consultando historial local de sesiones",e);rows=readLocalSessions().sort((a,b)=>String(b.inicio).localeCompare(String(a.inicio))).slice(0,100);usingLocal=true;
 }
 $("sessionCount").textContent=rows.length;const last=rows[0];$("sessionLastDate").textContent=last?sessionDate(last.inicio):"Sin registros";
 const lastClosed=rows.find(r=>r.estado==="cerrada"&&r.duracion_segundos!==null);$("sessionLastDuration").textContent=lastClosed?sessionDuration(lastClosed.duracion_segundos):"—";body.replaceChildren();
 if(!rows.length)body.innerHTML='<tr><td colspan="4" class="empty">Todavía no hay sesiones registradas.</td></tr>';
 else rows.forEach(r=>{
  const tr=document.createElement("tr");const duration=r.estado==="cerrada"?sessionDuration(r.duracion_segundos):r.estado==="interrumpida"?"No verificable":r.inicio?sessionDuration(Math.floor((Date.now()-new Date(r.inicio).getTime())/1000))+" (transcurrido)":"—";
  [sessionDate(r.inicio),sessionDate(r.fin),duration].forEach(value=>{const td=document.createElement("td");td.textContent=value;tr.appendChild(td)});
  const td=document.createElement("td");td.innerHTML=sessionStatus(r)+(r.almacenamiento==="dispositivo"?' <span class="muted">(este dispositivo)</span>':"");tr.appendChild(td);body.appendChild(tr);
 });
 status.className="status";status.textContent=usingLocal?"Historial local: solo está disponible en este dispositivo y navegador.":"Historial actualizado desde la base de datos. Las horas se muestran en la zona horaria del dispositivo.";
}
