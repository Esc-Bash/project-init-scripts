#!/usr/bin/env bash
set -euo pipefail

PROJECT_DIR="${1:-.}"

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
