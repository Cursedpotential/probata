# Local entrypoint; does not edit host configuration or start a background worker.
$ErrorActionPreference = 'Stop'
$env:UV_CACHE_DIR = 'E:/AI_Workspace/.intake-dev/uv-cache'
$env:TEMP = 'E:/AI_Workspace/.intake-dev/temp'
$env:TMP = $env:TEMP
$env:PYTHONDONTWRITEBYTECODE = '1'
$env:FASTMCP_CHECK_FOR_UPDATES = 'off'
& 'C:/Users/matts/.local/bin/uv.exe' run --frozen --no-sync --project $PSScriptRoot python "$PSScriptRoot/cli.py" @args
exit $LASTEXITCODE
