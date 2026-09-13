@echo off
set "UV=C:\Users\matts\.local\bin\uv.exe"
if not exist "%UV%" (
  echo Propria Search requires uv at %UV%. Install uv or set up the declared pyproject runtime. 1>&2
  exit /b 127
)
if not defined UV_PROJECT_ENVIRONMENT set "UV_PROJECT_ENVIRONMENT=E:\AI_Workspace\Projects\Propria\.runtime\search\env"
"%UV%" run --project "%~dp0." --locked python "%~dp0smart_explore.py" %*
