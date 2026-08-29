import json, sqlite3, sys
from pathlib import Path
sys.path.insert(0,r"C:\GRUPO RS CENTRAL\app\tools")
from local_sqlite_service import backup, connect, inspect

db=Path(r"C:\GRUPO RS CENTRAL\database\grupo_rs_central.sqlite")
con=connect(db); row=list(con.execute("SELECT * FROM devices WHERE branch_id='imperatriz' LIMIT 1").fetchone())
results={"duplicate_imei_blocked":False,"duplicate_iccid_blocked":False}
for kind in ("imei","iccid"):
    candidate=list(row); candidate[0]=f"imperatriz:DUP-{kind}"; candidate[2]=f"DUP-{kind}"
    if kind=="imei": candidate[4]="UNIQUE-ICCID"
    else: candidate[3]="UNIQUE-IMEI"
    try: con.execute("INSERT INTO devices VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?)",candidate); con.commit()
    except sqlite3.IntegrityError: results[f"duplicate_{kind}_blocked"]=True; con.rollback()
open_backup=backup(db,Path(r"C:\GRUPO RS CENTRAL\app\backups\open_database_test"),"4.2.1")
results["backup_open_ok"]=inspect(Path(open_backup["path"]))["ok"]; con.close()
corrupt=Path(r"C:\GRUPO RS CENTRAL\restore_test\corrupt.sqlite"); corrupt.write_bytes(b"not-a-sqlite")
try: results["corrupt_rejected"]=not inspect(corrupt).get("ok",False)
except sqlite3.DatabaseError: results["corrupt_rejected"]=True
empty=Path(r"C:\GRUPO RS CENTRAL\restore_test\empty.sqlite"); connect(empty).close()
try: backup(empty,Path(r"C:\GRUPO RS CENTRAL\restore_test\empty_backups"),"test"); results["empty_backup_refused"]=False
except RuntimeError: results["empty_backup_refused"]=True
results["open_backup"]=open_backup["path"]
print(json.dumps(results))
raise SystemExit(0 if all(results[key] for key in ("duplicate_imei_blocked","duplicate_iccid_blocked","backup_open_ok","corrupt_rejected","empty_backup_refused")) else 1)
