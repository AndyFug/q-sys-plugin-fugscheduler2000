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

## Numbered development build

When intentionally producing a distinct build for deployment or shared testing, increment the fourth `BuildVersion` component and generate matching UTC timestamps automatically:

```bash
python3 scripts/compile_plugin.py --new-build
```

This updates `src/info.lua` and the self-contained metadata fallback in `src/runtime.lua`, then compiles. Ordinary compilation remains idempotent and does not change metadata.

## Deploy

To produce a newly numbered build and deploy it while simulation is stopped:

```bash
python3 scripts/compile_plugin.py --new-build --deploy
```

To redeploy the same numbered build without changing its metadata:

```bash
python3 scripts/compile_plugin.py --deploy
```

The deploy command uses `QSYS_PLUGIN_DIR` when set, otherwise `/qsys-plugins` when available. An explicit directory may be supplied with `--deploy-dir`.

## Limitations

The local compiler only expands recursive `--[[ #include "file.lua" ]]` directives. Validate release builds with the official Q-SYS Plugin Compiler.
