from pathlib import Path
import re


PROJECT_ROOT = Path(__file__).resolve().parents[1]


def _read(path: str) -> str:
    return (PROJECT_ROOT / path).read_text(encoding="utf-8")


def _audit_sources() -> list[Path]:
    files = list((PROJECT_ROOT / "src").glob("__codex_*.gd"))
    files.extend((PROJECT_ROOT / "tests").glob("live_*.gd"))
    return sorted(files)


def test_export_preset_excludes_logs_ia_diagnostics() -> None:
    preset = _read("export_presets.cfg")
    excluded = preset.split('exclude_filter="', 1)[1].split('"', 1)[0]

    required_patterns = [
        "src/__codex_*.gd",
        "src/__codex_*.gd.uid",
        "tmp_*.log",
        "qa_api_report/**",
        "*.log",
        "*.jsonl",
        ".secrets/**",
        "tests/**",
        "projeto/**",
        "*.vault",
    ]
    missing = [pattern for pattern in required_patterns if pattern not in excluded]

    assert missing == []


def test_p0_harnesses_do_not_keep_literal_live_credentials() -> None:
    p0_files = [
        "src/__codex_api_vehicle_probe_existing_equipment.gd",
        "src/__codex_user425_live_check.gd",
        "src/__codex_user425_test_data_repair.gd",
    ]
    forbidden_literals = [
        '"lucasabm"',
        '"425"',
        "lucasabm/425",
        "_grupo_rs_api_login_with_credentials\", \"",
        "_grupo_rs_api_login_with_retry\", \"",
    ]

    offenders = []
    for path in p0_files:
        text = _read(path)
        for literal in forbidden_literals:
            if literal in text:
                offenders.append(f"{path}: {literal}")

    assert offenders == []


def test_live_harness_outputs_are_sanitized() -> None:
    forbidden_fragments = [
        "print(\"API_EQUIPMENT=OK %s\" % JSON.stringify",
        "print(\"API_VEHICLE=OK %s\" % JSON.stringify",
        "print(\"API_LOCATION=OK %s\" % JSON.stringify",
        "print(\"API_RECORD=OK %s\" % JSON.stringify",
        "print(\"SMART_4G_HYBRID_LIVE_RESULT=%s\" % JSON.stringify",
        "print(\"SMART_4G_PLATFORM_FALLBACK_LIVE_RESULT=%s\" % JSON.stringify",
        "print(\"SMART_4G_LIVE_EVENT=\", JSON.stringify",
        "print(\"VEHICLE_SNAPSHOT_JSON=%s\" % JSON.stringify",
        "print(\"USER425_REGISTRATION=%s\" % JSON.stringify",
        "print(\"USER425_PLATE_UPDATE=%s\" % JSON.stringify",
        "print(\"USER425_PLATE_RESTORE=%s\" % JSON.stringify",
        "print(\"REMOTE_REGISTRATION_RESULT=%s\" % JSON.stringify",
        "print(\"REAL_REENTRY_CHANGE_RESULT %s\" % str(",
        "serial=%s plate=%s",
        "plate=%s serial=%s",
        "serial=%s equipment=%s",
        "serial=%s old=%s new=%s",
        "vehicle=%s",
        "plate_initial=%s",
        "lat=%s lng=%s",
        "coordinates=%s",
    ]

    offenders = []
    for path in _audit_sources():
        text = path.read_text(encoding="utf-8")
        for fragment in forbidden_fragments:
            if fragment in text:
                offenders.append(f"{path.relative_to(PROJECT_ROOT)}: {fragment}")

    assert offenders == []


def test_no_live_prints_emit_raw_json_or_primary_identifiers() -> None:
    risky_prints = [
        re.compile(r"print\([^\n]*JSON\.stringify"),
        re.compile(r"print\([^\n]*(serial|plate|client|iccid|chip|lat|lng|coordinates)=%s"),
        re.compile(r"print\([^\n]*(equipment|vehicle|result|snapshot|payload)=%s"),
    ]
    allowed_files = {
        "src/__codex_experttexting_integration_check.gd",
        "src/__codex_firebase_sync_check.gd",
        "src/__codex_linksolutions_recovery_check.gd",
        "src/__codex_monitor_dashboard_check.gd",
        "src/__codex_remote_registration_catalog_check.gd",
        "src/__codex_sga_auth_shape_check.gd",
        "src/__codex_two_device_flow_check.gd",
        "src/__codex_update_system_check.gd",
    }

    offenders = []
    for path in _audit_sources():
        relative = path.relative_to(PROJECT_ROOT).as_posix()
        if relative in allowed_files:
            continue
        for line_number, line in enumerate(path.read_text(encoding="utf-8").splitlines(), 1):
            if any(pattern.search(line) for pattern in risky_prints):
                offenders.append(f"{relative}:{line_number}: {line.strip()}")

    assert offenders == []


def test_no_known_live_credentials_or_fixed_real_targets() -> None:
    forbidden = [
        '"lucasabm"',
        '"425"',
        "lucasabm/425",
        "997326976",
        "SMW - 6E12",
        "024003510",
        "024003657",
        "024004048",
        "895554830000003510",
    ]
    allowed_files = {
        "src/__codex_assistant_chat_check.gd",
        "src/__codex_experttexting_integration_check.gd",
        "src/__codex_firebase_sync_check.gd",
        "src/__codex_linksolutions_recovery_check.gd",
        "src/__codex_regional_integration_check.gd",
        "src/__codex_secret_vault_check.gd",
        "src/__codex_secret_vault_ui_check.gd",
    }

    offenders = []
    for path in _audit_sources():
        relative = path.relative_to(PROJECT_ROOT).as_posix()
        if relative in allowed_files:
            continue
        text = path.read_text(encoding="utf-8")
        for literal in forbidden:
            if literal in text:
                offenders.append(f"{relative}: {literal}")

    assert offenders == []


def test_historical_logs_are_export_excluded_not_operational_inputs() -> None:
    preset = _read("export_presets.cfg")
    excluded = preset.split('exclude_filter="', 1)[1].split('"', 1)[0]
    historical_patterns = [
        "*.log",
        "tmp_*.log",
        "projeto/**",
        "qa_api_report/**",
    ]

    assert all(pattern in excluded for pattern in historical_patterns)


if __name__ == "__main__":
    test_export_preset_excludes_logs_ia_diagnostics()
    test_p0_harnesses_do_not_keep_literal_live_credentials()
    test_live_harness_outputs_are_sanitized()
    test_no_live_prints_emit_raw_json_or_primary_identifiers()
    test_no_known_live_credentials_or_fixed_real_targets()
    test_historical_logs_are_export_excluded_not_operational_inputs()
    print("logs_ia_security_sanitization=PASS")
