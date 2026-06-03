: << 'CMDBLOCK'
@echo off
REM software-engineer
REM Copyright (C) 2026 demwick
REM Licensed under the GNU Affero General Public License v3.0 or later.
REM See LICENSE in the repository root for the full license text.
REM
REM Cross-platform polyglot wrapper for software-engineer hook scripts.
REM On Windows: cmd.exe runs the batch portion, finds bash, and calls the target script.
REM On Unix: the shell interprets this file as bash (": ..." is a no-op).
REM
REM Hook scripts are extensionless (e.g. "session-start", not "session-start.sh")
REM so Claude Code's Windows auto-detection doesn't prepend "bash" to .sh filenames.
REM
REM Usage: run-hook.cmd <script-name> [args...]

if "%~1"=="" (
    echo run-hook.cmd: missing script name >&2
    exit /b 1
)

set "HOOK_DIR=%~dp0"
set "SCRIPT=%~1"
shift

REM Prefer Git for Windows bash if present
if exist "C:\Program Files\Git\bin\bash.exe" (
    "C:\Program Files\Git\bin\bash.exe" "%HOOK_DIR%%SCRIPT%" %1 %2 %3 %4 %5 %6 %7 %8 %9
    exit /b %ERRORLEVEL%
)
if exist "C:\Program Files (x86)\Git\bin\bash.exe" (
    "C:\Program Files (x86)\Git\bin\bash.exe" "%HOOK_DIR%%SCRIPT%" %1 %2 %3 %4 %5 %6 %7 %8 %9
    exit /b %ERRORLEVEL%
)

REM Fall back to whatever bash is on PATH (WSL, MSYS2, Cygwin, etc.)
bash "%HOOK_DIR%%SCRIPT%" %1 %2 %3 %4 %5 %6 %7 %8 %9
exit /b %ERRORLEVEL%

CMDBLOCK

# ---- Unix path ----
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SCRIPT_NAME="${1:-}"

if [ -z "$SCRIPT_NAME" ]; then
    echo "run-hook.cmd: missing script name" >&2
    exit 1
fi

shift
exec bash "${SCRIPT_DIR}/${SCRIPT_NAME}" "$@"
