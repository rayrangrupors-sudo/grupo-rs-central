# Validação local Godot da trilha Logs/IA

Este procedimento valida a trilha local de logs/atualização e a cobertura de sanitização sem login, sem chamadas de negócio e sem empacotamento.

Use o binário absoluto do workspace oficial:

```powershell
& '.\godot\Godot_v4.7.1-stable_win64_console.exe' --headless --path . -s 'res://tests/update_bootstrap_log_test.gd' -- --update-test-mode
```

O argumento `-- --update-test-mode` é obrigatório. Sem ele, `reset_test_state()` recusa limpar o estado isolado de teste e o teste deve falhar por segurança.

Para parse-only dos scripts relevantes:

```powershell
& '.\godot\Godot_v4.7.1-stable_win64_console.exe' --headless --path . --check-only -s 'res://tests/update_bootstrap_log_test.gd'
& '.\godot\Godot_v4.7.1-stable_win64_console.exe' --headless --path . --check-only -s 'res://ai/ai_sanitizer.gd'
& '.\godot\Godot_v4.7.1-stable_win64_console.exe' --headless --path . --check-only -s 'res://ai/ai_manager.gd'
```

Para a auditoria estática de sanitização:

```powershell
& 'C:\Users\lugan\.cache\codex-runtimes\codex-primary-runtime\dependencies\python\python.exe' tests/test_logs_ia_security_sanitization.py
```

O relatório operacional deve destacar somente falhas acionáveis. No relatório de atualização, a lista `actionable_failures` deve continuar limitada a eventos com `status == "failed"`.
