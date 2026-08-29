#!/usr/bin/env python3
"""Backup diario local e copia opcional para pasta sincronizada do Google Drive."""
import json, shutil, sys
from pathlib import Path
from local_sqlite_service import backup, digest

APP_ROOT=Path(r"C:\GRUPO RS CENTRAL\app")
DATABASE=Path(r"C:\GRUPO RS CENTRAL\database\grupo_rs_central.sqlite")
LOCAL_BACKUPS=APP_ROOT / "backups" / "automaticos"
DRIVE_BACKUPS=Path(r"G:\Meu Drive\Grupo RS Central\Backups")
LOG=APP_ROOT / "backups" / "backup.log"

def record(message):
    LOG.parent.mkdir(parents=True,exist_ok=True)
    with LOG.open("a",encoding="utf-8") as stream: stream.write(message+"\n")

def main():
    result=backup(DATABASE,LOCAL_BACKUPS,"4.2.1")
    source=Path(result["path"]); manifest_path=Path(result["manifest"]); manifest=result
    state="pending"
    try:
        if Path(r"G:\Meu Drive").exists():
            DRIVE_BACKUPS.mkdir(parents=True,exist_ok=True)
            target=DRIVE_BACKUPS/source.name
            target_manifest=DRIVE_BACKUPS/manifest_path.name
            if target.exists() and digest(target)!=digest(source): raise RuntimeError("arquivo de mesmo nome com hash diferente no Drive")
            if not target.exists(): shutil.copy2(source,target)
            if digest(target)!=digest(source): raise RuntimeError("hash divergiu apos copia ao Drive")
            manifest["drive_state"]="copied_to_synced_folder"
            manifest_path.write_text(json.dumps(manifest,ensure_ascii=False,indent=2),encoding="utf-8")
            shutil.copy2(manifest_path,target_manifest); state="copied_to_synced_folder"
        record(f"{result['created_at']} success file={source.name} drive={state} sha256={result['sha256']}")
        print(json.dumps({"ok":True,"backup":str(source),"drive_state":state,"sha256":result["sha256"]},ensure_ascii=False))
    except Exception as exc:
        record(f"{result['created_at']} local_success drive_error={exc} file={source.name}")
        print(json.dumps({"ok":True,"backup":str(source),"drive_state":"pending","drive_error":str(exc)},ensure_ascii=False))

if __name__=="__main__":
    try: main()
    except Exception as exc:
        record(f"failure reason={exc}"); print(json.dumps({"ok":False,"error":str(exc)},ensure_ascii=False)); sys.exit(1)
