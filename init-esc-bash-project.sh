#!/usr/bin/env bash
set -euo pipefail

RAW_PROJECT_DIR="${1:-.}"

if [[ "${RAW_PROJECT_DIR}" == *".."* ]]; then
  echo "Error: project directory must not include '..' path traversal segments." >&2
  exit 1
fi

PROJECT_DIR="$(realpath -m "${RAW_PROJECT_DIR}")"

if [[ "${PROJECT_DIR}" == "/" ]]; then
  echo "Error: refusing to initialize in the filesystem root directory." >&2
  exit 1
fi

mkdir -p "${PROJECT_DIR}/bin" "${PROJECT_DIR}/lib" "${PROJECT_DIR}/tests"

if [[ ! -f "${PROJECT_DIR}/README.md" ]]; then
  cat > "${PROJECT_DIR}/README.md" <<'README'
# Bash Project

Project initialized with `init-esc-bash-project.sh`.
README
fi

if [[ ! -f "${PROJECT_DIR}/bin/main.sh" ]]; then
  cat > "${PROJECT_DIR}/bin/main.sh" <<'SCRIPT'
#!/usr/bin/env bash
set -euo pipefail

echo "Hello from your Bash project"
SCRIPT
  chmod +x "${PROJECT_DIR}/bin/main.sh"
fi

if [[ ! -f "${PROJECT_DIR}/tests/smoke.sh" ]]; then
  cat > "${PROJECT_DIR}/tests/smoke.sh" <<'TEST'
#!/usr/bin/env bash
set -euo pipefail

"$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/bin/main.sh"
TEST
  chmod +x "${PROJECT_DIR}/tests/smoke.sh"
fi

echo "Initialized Esc Bash project structure in ${PROJECT_DIR}"
