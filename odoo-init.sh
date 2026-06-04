#!/usr/bin/env bash
# =============================================================================
# odoo-init.sh — Initialise un projet Odoo pour le dev natif (sans Docker)
#
# Usage : ./odoo-init.sh [--project <nom>] [--version <19.0>] [--db <dbname>]
#         ou interactif si aucun argument fourni
#
# Génère / met à jour :
#   - odoo.conf          (data_dir, addons_path, db_name, db_host)
#   - .vscode/tasks.json (venv, odoo, postgres, update, scaffold, shell)
#   - *.code-workspace   (extraPaths Pylance)
#   - .gitignore         (entrées locales ajoutées si absentes)
#
# Prérequis : uv, python3, git
# =============================================================================

set -euo pipefail

# ── Couleurs ─────────────────────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; BOLD='\033[1m'; RESET='\033[0m'

info()    { echo -e "${CYAN}ℹ ${RESET}$*"; }
success() { echo -e "${GREEN}✔ ${RESET}$*"; }
warn()    { echo -e "${YELLOW}⚠ ${RESET}$*"; }
error()   { echo -e "${RED}✖ ${RESET}$*" >&2; exit 1; }
header()  { echo -e "\n${BOLD}── $* ──${RESET}"; }

# ── Defaults ──────────────────────────────────────────────────────────────────
ODOO_BASE="${HOME}/apik/odoo"         # Racine des clones community/enterprise/themes
ODOO_VERSION=""
PROJECT_NAME=""
DB_NAME=""
DB_HOST="localhost"
DB_PORT="5432"
DB_USER="odoo"
DB_PASSWORD="odoo"
ADMIN_PASSWD="odoo"

# ── Parsing des arguments ──────────────────────────────────────────────────────
while [[ $# -gt 0 ]]; do
    case $1 in
        --project)  PROJECT_NAME="$2"; shift 2 ;;
        --version)  ODOO_VERSION="$2"; shift 2 ;;
        --db)       DB_NAME="$2";      shift 2 ;;
        --help|-h)
            echo "Usage: $0 [--project NAME] [--version X.0] [--db DBNAME]"
            exit 0 ;;
        *) error "Argument inconnu : $1" ;;
    esac
done

# ── Mode interactif si paramètres manquants ────────────────────────────────────
header "Configuration du projet Odoo"

if [[ -z "$PROJECT_NAME" ]]; then
    # Essaie de deviner depuis le nom du répertoire courant
    default_name=$(basename "$(pwd)" | sed 's/^odoo-//')
    read -rp "  Nom du projet [${default_name}]: " PROJECT_NAME
    PROJECT_NAME="${PROJECT_NAME:-$default_name}"
fi

if [[ -z "$ODOO_VERSION" ]]; then
    # Essaie de lire depuis odoo_version.txt (format apik/odoo:19.0-xxxx-enterprise)
    if [[ -f "odoo_version.txt" ]]; then
        detected=$(grep -oP '\d+\.\d+' odoo_version.txt | head -1 || true)
    fi
    default_version="${detected:-19.0}"
    read -rp "  Version Odoo [${default_version}]: " ODOO_VERSION
    ODOO_VERSION="${ODOO_VERSION:-$default_version}"
fi

if [[ -z "$DB_NAME" ]]; then
    default_db="${PROJECT_NAME//-/_}"
    read -rp "  Nom de la base de données [${default_db}]: " DB_NAME
    DB_NAME="${DB_NAME:-$default_db}"
fi

# ── Chemins dérivés ───────────────────────────────────────────────────────────
COMMUNITY_PATH="${ODOO_BASE}/${ODOO_VERSION}/community"
ENTERPRISE_PATH="${ODOO_BASE}/${ODOO_VERSION}/enterprise"
THEMES_PATH="${ODOO_BASE}/${ODOO_VERSION}/themes"
FILESTORE_DIR="/tmp/odoo/${PROJECT_NAME}"
VENV_DIR=".venv"
WORKSPACE_FILE="${PROJECT_NAME}.code-workspace"
CONF_FILE="odoo.conf"

# ── Vérifications ─────────────────────────────────────────────────────────────
header "Vérifications"

command -v uv &>/dev/null || error "'uv' n'est pas installé. Installe-le via : curl -Ls https://astral.sh/uv/install.sh | sh"

for dir in "$COMMUNITY_PATH" "$ENTERPRISE_PATH" "$THEMES_PATH"; do
    if [[ -d "$dir" ]]; then
        success "Trouvé : $dir"
    else
        warn "Absent  : $dir  (sera ignoré dans addons_path)"
    fi
done

# ── Calcul de l'addons_path ───────────────────────────────────────────────────
addons_paths=()
[[ -d "$COMMUNITY_PATH/addons" ]] && addons_paths+=("${COMMUNITY_PATH}/addons")
[[ -d "$ENTERPRISE_PATH" ]]       && addons_paths+=("$ENTERPRISE_PATH")
[[ -d "$THEMES_PATH" ]]           && addons_paths+=("$THEMES_PATH")
addons_paths+=(".")   # Toujours le projet courant en dernier

ADDONS_PATH=$(IFS=,; echo "${addons_paths[*]}")

# ── Filestore dans /tmp ────────────────────────────────────────────────────────
header "Filestore"
mkdir -p "$FILESTORE_DIR"
success "Filestore : $FILESTORE_DIR  (éphémère, nettoyé au reboot)"

# ── odoo.conf ─────────────────────────────────────────────────────────────────
header "odoo.conf"

cat > "$CONF_FILE" <<EOF
[options]
; ── Chemins ──────────────────────────────────────────────────────────────────
addons_path = ${ADDONS_PATH}
data_dir = ${FILESTORE_DIR}

; ── Base de données ──────────────────────────────────────────────────────────
db_host = ${DB_HOST}
db_port = ${DB_PORT}
db_user = ${DB_USER}
db_password = ${DB_PASSWORD}
db_name = ${DB_NAME}
admin_passwd = ${ADMIN_PASSWD}

; ── Limites (dev) ─────────────────────────────────────────────────────────────
limit_memory_soft = 1077721600
limit_memory_hard = 3355443200
limit_request = 8192
limit_time_cpu = 3200
limit_time_real = 3200
max_cron_threads = 0
workers = 0

; ── Logging ───────────────────────────────────────────────────────────────────
log_level = info
EOF

success "odoo.conf écrit"

# ── .vscode/tasks.json ────────────────────────────────────────────────────────
header ".vscode/tasks.json"
mkdir -p .vscode

# Calcul du python_path depuis community (pour odoo-bin)
ODOO_BIN="${COMMUNITY_PATH}/odoo-bin"

cat > .vscode/tasks.json <<EOF
{
    "version": "2.0.0",
    "tasks": [
        {
            "label": "🐍 Venv: créer / mettre à jour",
            "type": "shell",
            "command": "uv venv ${VENV_DIR} && uv pip install -r ${COMMUNITY_PATH}/requirements.txt && uv pip install -r requirements.txt",
            "options": { "cwd": "\${workspaceFolder}" },
            "group": "build",
            "presentation": { "reveal": "always", "panel": "shared" },
            "problemMatcher": []
        },
        {
            "label": "🐘 PostgreSQL: démarrer",
            "type": "shell",
            "command": "docker compose up postgres -d",
            "options": { "cwd": "\${workspaceFolder}" },
            "group": "build",
            "presentation": { "reveal": "always", "panel": "shared" },
            "problemMatcher": []
        },
        {
            "label": "🟢 Odoo: lancer",
            "type": "shell",
            "command": "${VENV_DIR}/bin/python ${ODOO_BIN} --config=${CONF_FILE} --dev=all",
            "options": { "cwd": "\${workspaceFolder}" },
            "group": "build",
            "dependsOn": "🐘 PostgreSQL: démarrer",
            "presentation": { "reveal": "always", "panel": "dedicated", "focus": true },
            "problemMatcher": []
        },
        {
            "label": "🔄 Odoo: update module",
            "type": "shell",
            "command": "\${input:moduleUpdate}",
            "options": { "cwd": "\${workspaceFolder}" },
            "presentation": { "reveal": "always", "panel": "shared" },
            "problemMatcher": []
        },
        {
            "label": "🛠  Odoo: scaffold module",
            "type": "shell",
            "command": "${VENV_DIR}/bin/python ${ODOO_BIN} scaffold \${input:moduleName} .",
            "options": { "cwd": "\${workspaceFolder}" },
            "presentation": { "reveal": "always", "panel": "shared" },
            "problemMatcher": []
        },
        {
            "label": "🐚 Odoo: shell",
            "type": "shell",
            "command": "${VENV_DIR}/bin/python ${ODOO_BIN} shell --config=${CONF_FILE} --db_name=${DB_NAME}",
            "options": { "cwd": "\${workspaceFolder}" },
            "presentation": { "reveal": "always", "panel": "dedicated", "focus": true },
            "problemMatcher": []
        }
    ],
    "inputs": [
        {
            "id": "moduleUpdate",
            "type": "promptString",
            "description": "Module(s) à mettre à jour (-u) — ex: sale,account",
            "default": ""
        },
        {
            "id": "moduleName",
            "type": "promptString",
            "description": "Nom du nouveau module à scaffolder",
            "default": "my_module"
        }
    ]
}
EOF

# Patch de la commande update avec la valeur résolue (le promptString gère déjà le nom)
# La task update utilise une commande construite depuis l'input, on la complète :
python3 - <<PYEOF
import json, sys

with open(".vscode/tasks.json") as f:
    data = json.load(f)

for t in data["tasks"]:
    if "update module" in t["label"]:
        t["command"] = (
            "${VENV_DIR}/bin/python ${ODOO_BIN} "
            "--config=${CONF_FILE} "
            "--db_name=${DB_NAME} "
            "-u \${input:moduleUpdate} "
            "--stop-after-init"
        )

with open(".vscode/tasks.json", "w") as f:
    json.dump(data, f, indent=4, ensure_ascii=False)
    f.write("\n")
PYEOF

success ".vscode/tasks.json écrit"

# ── *.code-workspace ──────────────────────────────────────────────────────────
header "Code workspace"

# Chemins extraPaths : uniquement ceux qui existent
extra_paths=()
[[ -d "$COMMUNITY_PATH" ]] && extra_paths+=("$COMMUNITY_PATH")
[[ -d "$ENTERPRISE_PATH" ]] && extra_paths+=("$ENTERPRISE_PATH")
[[ -d "$THEMES_PATH" ]] && extra_paths+=("$THEMES_PATH")

python3 - <<PYEOF
import json, os

extra = $(python3 -c "import json; print(json.dumps(extra_paths))" 2>/dev/null || echo "[]")

# Recalcule depuis bash (plus sûr)
paths_raw = """${extra_paths[*]:-}"""
extra = [p for p in paths_raw.split() if p]

workspace = {
    "folders": [{"path": "."}],
    "settings": {
        "python.analysis.extraPaths": extra,
        "python.autoComplete.extraPaths": extra,
        "python.defaultInterpreterPath": ".venv/bin/python",
    }
}

outfile = "${WORKSPACE_FILE}"
with open(outfile, "w") as f:
    json.dump(workspace, f, indent=4, ensure_ascii=False)
    f.write("\n")
print(f"  ✔ {outfile}")
PYEOF

success "Workspace écrit : ${WORKSPACE_FILE}"

# ── .gitignore — ajout des entrées locales ────────────────────────────────────
header ".gitignore"

GITIGNORE_ADDITIONS=(
    "# Odoo dev local"
    ".venv/"
    ".odoo-data/"
    "odoo.conf"
    ".vscode/tasks.json"
    "${WORKSPACE_FILE}"
    "*.log"
    "__pycache__/"
)

if [[ ! -f ".gitignore" ]]; then
    touch .gitignore
fi

added=0
for line in "${GITIGNORE_ADDITIONS[@]}"; do
    if ! grep -qxF "$line" .gitignore; then
        echo "$line" >> .gitignore
        added=$((added + 1))
    fi
done

if [[ $added -gt 0 ]]; then
    success ".gitignore — $added entrées ajoutées"
else
    info ".gitignore — rien à ajouter"
fi

# ── Résumé ────────────────────────────────────────────────────────────────────
echo ""
echo -e "${BOLD}╔══════════════════════════════════════════════════════╗${RESET}"
echo -e "${BOLD}║  Projet ${PROJECT_NAME} (Odoo ${ODOO_VERSION}) prêt          ${RESET}"
echo -e "${BOLD}╠══════════════════════════════════════════════════════╣${RESET}"
echo -e "  Filestore   : ${FILESTORE_DIR}"
echo -e "  DB          : ${DB_NAME} @ ${DB_HOST}:${DB_PORT}"
echo -e "  Addons      : ${ADDONS_PATH}"
echo -e "  Venv        : .venv  (uv)"
echo -e ""
echo -e "  ${CYAN}Prochaine étape :${RESET}"
echo -e "    Ctrl+Shift+P → Tasks: Run Task → 🐍 Venv: créer / mettre à jour"
echo -e "    Ctrl+Shift+P → Tasks: Run Task → 🟢 Odoo: lancer"
echo -e "${BOLD}╚══════════════════════════════════════════════════════╝${RESET}"
echo ""
