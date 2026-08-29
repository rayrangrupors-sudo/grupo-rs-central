#!/usr/bin/env python3
"""Servico SQLite offline do Grupo RS Central. Nao realiza chamadas de rede."""
import hashlib, json, os, shutil, sqlite3, sys
from datetime import datetime, timezone
from pathlib import Path

VERSION=1
TABLES=("devices","telemetry_raw","locations","communications","ignition_events","maintenance","alerts","movements","audit_log")
SCHEMA="""
PRAGMA journal_mode=WAL; PRAGMA foreign_keys=ON; PRAGMA synchronous=FULL;
CREATE TABLE IF NOT EXISTS branches(id TEXT PRIMARY KEY,name TEXT NOT NULL,created_at TEXT NOT NULL);
CREATE TABLE IF NOT EXISTS devices(id TEXT PRIMARY KEY,branch_id TEXT NOT NULL REFERENCES branches(id),sku TEXT NOT NULL,imei TEXT,iccid TEXT,plate TEXT,carrier TEXT,model TEXT,status TEXT NOT NULL,quantity REAL NOT NULL DEFAULT 0,created_at TEXT NOT NULL,updated_at TEXT NOT NULL,raw_json TEXT NOT NULL,UNIQUE(branch_id,sku));
CREATE UNIQUE INDEX IF NOT EXISTS ux_devices_imei ON devices(branch_id,imei) WHERE imei IS NOT NULL AND imei<>'';
CREATE UNIQUE INDEX IF NOT EXISTS ux_devices_iccid ON devices(branch_id,iccid) WHERE iccid IS NOT NULL AND iccid<>'';
CREATE INDEX IF NOT EXISTS ix_devices_plate ON devices(branch_id,plate); CREATE INDEX IF NOT EXISTS ix_devices_status ON devices(branch_id,status);
CREATE TABLE IF NOT EXISTS telemetry_raw(id TEXT PRIMARY KEY,branch_id TEXT NOT NULL,device_id TEXT,received_at TEXT NOT NULL,protocol TEXT,payload TEXT NOT NULL,operator TEXT,raw_json TEXT NOT NULL);
CREATE INDEX IF NOT EXISTS ix_telemetry_date ON telemetry_raw(branch_id,device_id,received_at);
CREATE TABLE IF NOT EXISTS locations(id TEXT PRIMARY KEY,branch_id TEXT NOT NULL,device_id TEXT,latitude REAL NOT NULL,longitude REAL NOT NULL,accuracy REAL,recorded_at TEXT NOT NULL,operator TEXT,raw_json TEXT NOT NULL);
CREATE INDEX IF NOT EXISTS ix_locations_date ON locations(branch_id,device_id,recorded_at);
CREATE TABLE IF NOT EXISTS communications(id TEXT PRIMARY KEY,branch_id TEXT NOT NULL,device_id TEXT,communicated_at TEXT NOT NULL,protocol TEXT,signal REAL,payload TEXT,operator TEXT,raw_json TEXT NOT NULL);
CREATE INDEX IF NOT EXISTS ix_communications_date ON communications(branch_id,device_id,communicated_at);
CREATE TABLE IF NOT EXISTS ignition_events(id TEXT PRIMARY KEY,branch_id TEXT NOT NULL,device_id TEXT,state INTEGER NOT NULL,occurred_at TEXT NOT NULL,operator TEXT,raw_json TEXT NOT NULL);
CREATE INDEX IF NOT EXISTS ix_ignition_date ON ignition_events(branch_id,device_id,occurred_at);
CREATE TABLE IF NOT EXISTS maintenance(id TEXT PRIMARY KEY,branch_id TEXT NOT NULL,device_id TEXT,status TEXT NOT NULL,opened_at TEXT NOT NULL,completed_at TEXT,operator TEXT,raw_json TEXT NOT NULL);
CREATE INDEX IF NOT EXISTS ix_maintenance_date ON maintenance(branch_id,opened_at);
CREATE TABLE IF NOT EXISTS alerts(id TEXT PRIMARY KEY,branch_id TEXT NOT NULL,device_id TEXT,kind TEXT NOT NULL,severity TEXT,occurred_at TEXT NOT NULL,acknowledged_at TEXT,operator TEXT,raw_json TEXT NOT NULL);
CREATE INDEX IF NOT EXISTS ix_alerts_date ON alerts(branch_id,occurred_at);
CREATE TABLE IF NOT EXISTS movements(id TEXT PRIMARY KEY,branch_id TEXT NOT NULL,device_id TEXT,sku TEXT,movement_type TEXT NOT NULL,quantity REAL NOT NULL,reason TEXT,occurred_at TEXT NOT NULL,operator TEXT,raw_json TEXT NOT NULL);
CREATE INDEX IF NOT EXISTS ix_movements_date ON movements(branch_id,occurred_at); CREATE INDEX IF NOT EXISTS ix_movements_operator ON movements(branch_id,operator,occurred_at);
CREATE TABLE IF NOT EXISTS audit_log(id TEXT PRIMARY KEY,branch_id TEXT NOT NULL,action TEXT NOT NULL,entity_type TEXT,entity_id TEXT,operator TEXT,occurred_at TEXT NOT NULL,details TEXT,raw_json TEXT NOT NULL);
CREATE INDEX IF NOT EXISTS ix_audit_date ON audit_log(branch_id,occurred_at); CREATE INDEX IF NOT EXISTS ix_audit_operator ON audit_log(branch_id,operator,occurred_at);
CREATE TABLE IF NOT EXISTS runtime_state(branch_id TEXT NOT NULL,key TEXT NOT NULL,value_json TEXT NOT NULL,PRIMARY KEY(branch_id,key));
CREATE TABLE IF NOT EXISTS schema_migrations(version INTEGER PRIMARY KEY,applied_at TEXT NOT NULL,description TEXT NOT NULL);
"""
def now(): return datetime.now(timezone.utc).isoformat(timespec="seconds")
def connect(path):
    path.parent.mkdir(parents=True,exist_ok=True); con=sqlite3.connect(path,timeout=30); con.row_factory=sqlite3.Row; con.executescript(SCHEMA)
    con.execute("INSERT OR IGNORE INTO schema_migrations VALUES(?,?,?)",(VERSION,now(),"initial offline schema")); con.commit(); return con
def pick(row,*keys):
    for key in keys:
        value=row.get(key)
        if value is not None and str(value).strip(): return str(value).strip()
    return ""
def identity(prefix,row,index): return pick(row,"id","event_id","movement_id","sku","serial","imei") or f"{prefix}-{index:08d}"
def empty(): return {"schema":3,"products":[],"movements":[],"system_logs":[],"maintenances":[],"runtime":{}}
def counts(con,branch=None): return {t:con.execute(f"SELECT COUNT(*) FROM {t}"+(" WHERE branch_id=?" if branch else ""),(branch,) if branch else ()).fetchone()[0] for t in TABLES}
def valid(con): return con.execute("PRAGMA integrity_check").fetchone()[0]=="ok"
def digest(path):
    value=hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda:stream.read(1048576),b""): value.update(chunk)
    return value.hexdigest()

def save(con,branch,snapshot):
    stamp=now(); products=snapshot.get("products",[]); movements=snapshot.get("movements",[]); maint=snapshot.get("maintenances",[]); logs=snapshot.get("system_logs",[])
    with con:
        con.execute("INSERT OR IGNORE INTO branches VALUES(?,?,?)",(branch,branch.title(),stamp))
        for table in ("devices","movements","maintenance","audit_log","runtime_state"): con.execute(f"DELETE FROM {table} WHERE branch_id=?",(branch,))
        for i,row in enumerate(products):
            sku=pick(row,"sku","serial","imei") or f"DEVICE-{i:08d}"; created=pick(row,"created_at","registered_at","date") or stamp
            con.execute("INSERT INTO devices VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?)",(f"{branch}:{sku}",branch,sku,pick(row,"imei","serial"),pick(row,"iccid","chip_number","chip"),pick(row,"plate","placa"),pick(row,"carrier","operator","operadora"),pick(row,"model","modelo","category"),pick(row,"status") or "IN_STOCK",float(row.get("quantity",1) or 0),created,pick(row,"updated_at") or created,json.dumps(row,ensure_ascii=False,separators=(",",":"))))
        for i,row in enumerate(movements):
            key=identity("movement",row,i); con.execute("INSERT INTO movements VALUES(?,?,?,?,?,?,?,?,?,?)",(f"{branch}:{key}",branch,pick(row,"device_id"),pick(row,"sku","serial"),pick(row,"type","movement_type") or "UNKNOWN",float(row.get("quantity",0) or 0),pick(row,"reason","details"),pick(row,"date","occurred_at","created_at") or stamp,pick(row,"operator","user"),json.dumps(row,ensure_ascii=False,separators=(",",":"))))
        for i,row in enumerate(maint):
            key=identity("maintenance",row,i); con.execute("INSERT INTO maintenance VALUES(?,?,?,?,?,?,?,?)",(f"{branch}:{key}",branch,pick(row,"device_id","sku","serial"),pick(row,"status") or "OPEN",pick(row,"opened_at","date","created_at") or stamp,pick(row,"completed_at"),pick(row,"operator","user"),json.dumps(row,ensure_ascii=False,separators=(",",":"))))
        for i,row in enumerate(logs):
            key=identity("audit",row,i); con.execute("INSERT INTO audit_log VALUES(?,?,?,?,?,?,?,?,?)",(f"{branch}:{key}",branch,pick(row,"action") or "EVENT",pick(row,"entity_type") or "device",pick(row,"entity_id","sku","serial"),pick(row,"operator","user"),pick(row,"date","occurred_at","created_at") or stamp,pick(row,"details","message"),json.dumps(row,ensure_ascii=False,separators=(",",":"))))
        runtime=snapshot.get("runtime",{}) if isinstance(snapshot.get("runtime",{}),dict) else {}
        for key,value in runtime.items(): con.execute("INSERT INTO runtime_state VALUES(?,?,?)",(branch,str(key),json.dumps(value,ensure_ascii=False)))
    return counts(con,branch)

def load(con,branch):
    result=empty(); mapping={"products":"devices","movements":"movements","maintenances":"maintenance","system_logs":"audit_log"}
    for key,table in mapping.items(): result[key]=[json.loads(r[0]) for r in con.execute(f"SELECT raw_json FROM {table} WHERE branch_id=? ORDER BY rowid",(branch,))]
    result["runtime"]={r[0]:json.loads(r[1]) for r in con.execute("SELECT key,value_json FROM runtime_state WHERE branch_id=?",(branch,))}; return result

def ensure_branch(con,branch,stamp):
    con.execute("INSERT OR IGNORE INTO branches VALUES(?,?,?)",(branch,branch.title(),stamp))

def device_values(branch,row):
    stamp=now(); sku=pick(row,"sku","serial","imei")
    if not sku: raise RuntimeError("dispositivo sem sku/serie")
    created=pick(row,"created_at","registered_at","date") or stamp
    updated=pick(row,"updated_at") or stamp
    return (f"{branch}:{sku}",branch,sku,pick(row,"imei","serial"),pick(row,"iccid","chip_number","chip"),pick(row,"plate","placa"),pick(row,"carrier","operator","operadora"),pick(row,"model","modelo","category"),pick(row,"status","tracker_status") or "IN_STOCK",float(row.get("quantity",row.get("stock",1)) or 0),created,updated,json.dumps(row,ensure_ascii=False,separators=(",",":")))

def upsert_device(con,branch,row,old_sku=""):
    values=device_values(branch,row); stamp=now()
    with con:
        ensure_branch(con,branch,stamp)
        if old_sku and old_sku!=values[2]: con.execute("DELETE FROM devices WHERE branch_id=? AND sku=?",(branch,old_sku))
        con.execute("""INSERT INTO devices VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?)
            ON CONFLICT(branch_id,sku) DO UPDATE SET imei=excluded.imei,iccid=excluded.iccid,plate=excluded.plate,
            carrier=excluded.carrier,model=excluded.model,status=excluded.status,quantity=excluded.quantity,
            updated_at=excluded.updated_at,raw_json=excluded.raw_json""",values)
    return get_device(con,branch,values[2])

def movement_values(branch,row,index=0):
    key=identity("movement",row,index); sku=pick(row,"sku","serial")
    return (f"{branch}:{key}",branch,pick(row,"device_id") or (f"{branch}:{sku}" if sku else ""),sku,pick(row,"type","movement_type") or "UNKNOWN",float(row.get("quantity",0) or 0),pick(row,"reason","details"),pick(row,"date","occurred_at","timestamp","created_at") or now(),pick(row,"operator","user"),json.dumps(row,ensure_ascii=False,separators=(",",":")))

def upsert_device_with_movement(con,branch,row,movement):
    values=device_values(branch,row); stamp=now()
    with con:
        ensure_branch(con,branch,stamp)
        con.execute("""INSERT INTO devices VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?)
            ON CONFLICT(branch_id,sku) DO UPDATE SET imei=excluded.imei,iccid=excluded.iccid,plate=excluded.plate,
            carrier=excluded.carrier,model=excluded.model,status=excluded.status,quantity=excluded.quantity,
            updated_at=excluded.updated_at,raw_json=excluded.raw_json""",values)
        con.execute("INSERT OR REPLACE INTO movements VALUES(?,?,?,?,?,?,?,?,?,?)",movement_values(branch,movement))
    return get_device(con,branch,values[2])

def append_audit(con,branch,row):
    key=identity("audit",row,0); stamp=now()
    values=(f"{branch}:{key}",branch,pick(row,"action") or "EVENT",pick(row,"entity_type") or "device",pick(row,"entity_id","sku","serial"),pick(row,"operator","user"),pick(row,"date","occurred_at","timestamp","created_at") or stamp,pick(row,"details","message"),json.dumps(row,ensure_ascii=False,separators=(",",":")))
    with con:
        ensure_branch(con,branch,stamp)
        con.execute("INSERT OR REPLACE INTO audit_log VALUES(?,?,?,?,?,?,?,?,?)",values)
    return {"ok":True,"id":values[0]}

def get_device(con,branch,sku):
    row=con.execute("SELECT raw_json FROM devices WHERE branch_id=? AND (sku=? OR imei=?) LIMIT 2",(branch,sku,sku)).fetchall()
    if len(row)!=1: return {"ok":False,"found":False,"ambiguous":len(row)>1}
    return {"ok":True,"found":True,"product":json.loads(row[0][0])}

def delete_device(con,branch,sku):
    with con: cursor=con.execute("DELETE FROM devices WHERE branch_id=? AND sku=?",(branch,sku))
    return {"ok":True,"deleted":cursor.rowcount}

def inspect(path):
    if not path.is_file(): return {"ok":False,"error":"arquivo nao encontrado"}
    con=sqlite3.connect(path); con.row_factory=sqlite3.Row
    try:
        ok=valid(con); return {"ok":ok,"integrity":"ok" if ok else "failed","size":path.stat().st_size,"sha256":digest(path),"record_counts":counts(con)}
    finally: con.close()

def backup(db_path,backup_dir,app_version):
    source=connect(db_path)
    if sum(counts(source).values())==0: source.close(); raise RuntimeError("backup recusado: banco vazio")
    backup_dir.mkdir(parents=True,exist_ok=True); stamp=datetime.now().strftime("%Y-%m-%d_%H%M%S"); target=backup_dir/f"backup_{stamp}.sqlite"; temp=backup_dir/f".{target.name}.tmp"
    if target.exists(): source.close(); raise RuntimeError("backup ja existe")
    destination=sqlite3.connect(temp); source.backup(destination); destination.close(); source.close()
    checked=inspect(temp)
    if not checked.get("ok"): temp.unlink(missing_ok=True); raise RuntimeError("backup invalido")
    os.replace(temp,target); manifest={"created_at":now(),"app_version":app_version,"schema_version":VERSION,"file":target.name,"size":target.stat().st_size,"sha256":digest(target),"record_counts":checked["record_counts"],"integrity":"ok","drive_state":"pending"}
    manifest_path=target.with_suffix(".manifest.json"); manifest_path.write_text(json.dumps(manifest,ensure_ascii=False,indent=2),encoding="utf-8")
    return {"ok":True,"path":str(target),"manifest":str(manifest_path),**manifest}

def restore(current,source,confirmation,operator):
    if confirmation!="RESTAURAR": raise RuntimeError("confirmacao RESTAURAR obrigatoria")
    if not inspect(source).get("ok"): raise RuntimeError("backup invalido")
    safety=backup(current,current.parent/"pre_restore","pre-restore"); temp=current.with_suffix(".restore.tmp.sqlite"); shutil.copy2(source,temp)
    if not inspect(temp).get("ok"): temp.unlink(missing_ok=True); raise RuntimeError("copia temporaria invalida")
    os.replace(temp,current); con=connect(current)
    with con:
        con.execute("INSERT OR IGNORE INTO branches VALUES('system','System',?)",(now(),)); con.execute("INSERT INTO audit_log VALUES(?,?,?,?,?,?,?,?,?)",(f"system:restore:{datetime.now().timestamp()}","system","RESTORE","database",source.name,operator,now(),f"source={source}; safety={safety['path']}","{}"))
    con.close(); return {"ok":True,"safety_backup":safety["path"],"restored_from":str(source)}

def main():
    operation,db_raw,request_raw,response_raw=sys.argv[1:]; db_path=Path(db_raw); request_path=Path(request_raw); response_path=Path(response_raw); request=json.loads(request_path.read_text(encoding="utf-8")) if request_path.exists() else {}
    if operation=="backup": result=backup(db_path,Path(request["backup_dir"]),str(request.get("app_version","unknown")))
    elif operation=="inspect": result=inspect(Path(request.get("path",db_path)))
    elif operation=="restore": result=restore(db_path,Path(request["path"]),str(request.get("confirmation","")),str(request.get("operator","unknown")))
    else:
        con=connect(db_path)
        try:
            if operation=="init": result={"ok":True,"integrity":valid(con),"counts":counts(con)}
            elif operation=="save": result={"ok":True,"counts":save(con,str(request["branch"]),request["snapshot"])}
            elif operation=="load": result={"ok":True,"snapshot":load(con,str(request["branch"])),"counts":counts(con,str(request["branch"]))}
            elif operation=="upsert_device": result={"ok":True,**upsert_device(con,str(request["branch"]),request["product"],str(request.get("old_sku","")))}
            elif operation=="upsert_device_with_movement": result={"ok":True,**upsert_device_with_movement(con,str(request["branch"]),request["product"],request["movement"])}
            elif operation=="append_audit": result=append_audit(con,str(request["branch"]),request["event"])
            elif operation=="get_device": result=get_device(con,str(request["branch"]),str(request["sku"]))
            elif operation=="delete_device": result=delete_device(con,str(request["branch"]),str(request["sku"]))
            elif operation=="health": result={"ok":valid(con),"integrity":"ok" if valid(con) else "failed"}
            else: raise RuntimeError(f"operacao desconhecida: {operation}")
        finally: con.close()
    response_path.write_text(json.dumps(result,ensure_ascii=False),encoding="utf-8")

if __name__=="__main__":
    try: main()
    except Exception as exc:
        if len(sys.argv)>=5: Path(sys.argv[4]).write_text(json.dumps({"ok":False,"error":str(exc)},ensure_ascii=False),encoding="utf-8")
        raise
