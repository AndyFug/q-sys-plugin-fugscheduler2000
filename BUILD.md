# FugScheduler 2000 Build Workflow

FugScheduler 2000 follows the shared workspace workflow in `../QSYS_PLUGIN_BUILD.md`.

## Project-specific details

- Editable source: `src/`
- Generated/deployable artifact: `FugScheduler2000.qplug`
- Repo-local compiler/deploy tool: `scripts/compile_plugin.py`

## Compile

From `q-sys-plugin-fugscheduler2000/`:

```bash
python3 scripts/compile_plugin.py
```

Or run the VS Code task:

```text
Compile FugScheduler2000.qplug (local include compiler)
```

## Deploy

When the host Q-SYS Designer plugin folder is mounted, compile and deploy with:

```bash
python3 scripts/compile_plugin.py --deploy
```

The deploy command uses `QSYS_PLUGIN_DIR` when set, otherwise `/qsys-plugins` when available. An explicit directory may be supplied with `--deploy-dir`.

## Limitations

The local compiler only expands recursive `--[[ #include "file.lua" ]]` directives. Validate release builds with the official Q-SYS Plugin Compiler.
