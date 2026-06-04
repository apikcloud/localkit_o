#!/usr/bin/env bash
# =============================================================================
# odoo-init.sh — Initialise un projet Odoo pour le dev natif (sans Docker)
#
# Usage : ./odoo-init.sh [--project <nom>] [--version <19.0>] [--db <dbname>]
#                        [--project-path <path>]
#         ou interactif si aucun argument fourni
#
# Génère / met à jour :
#   - .config/odoo.conf  (upsert par sed, création propre sans commentaires)
#   - docker-compose.yml (postgres exposé :5432, service odoo commenté — backup en .old)
#   - .vscode/tasks.json (venv, pip install, odoo, postgres, update, scaffold, shell)
#   - *.code-workspace   (extraPaths Pylance + defaultInterpreterPath)
#   - .gitignore         (entrées locales ajoutées si absentes)
#
# Prérequis : uv, python3
# =============================================================================

set -euo pipefail

# ── Couleurs ──────────────────────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; BOLD='\033[1m'; RESET='\033[0m'

info()    { echo -e "${CYAN}ℹ ${RESET}$*"; }
success() { echo -e "${GREEN}✔ ${RESET}$*"; }
warn()    { echo -e "${YELLOW}⚠ ${RESET}$*"; }
error()   { echo -e "${RED}✖ ${RESET}$*" >&2; exit 1; }
header()  { echo -e "\n${BOLD}── $* ──${RESET}"; }

# ── Defaults ──────────────────────────────────────────────────────────────────
ODOO_BASE="${HOME}/apik/odoo"   # Racine des clones community/enterprise/themes
ODOO_VERSION=""
PROJECT_NAME=""
PROJECT_PATH=""                 # Racine du projet (défaut: cwd)
DB_NAME=""
DB_HOST="localhost"
DB_PORT="5432"
DB_USER="odoo"
DB_PASSWORD="odoo"
ADMIN_PASSWD="odoo"

# ── Parsing des arguments ─────────────────────────────────────────────────────
while [[ $# -gt 0 ]]; do
    case $1 in
        --project)       PROJECT_NAME="$2";  shift 2 ;;
        --version)       ODOO_VERSION="$2";  shift 2 ;;
        --db)            DB_NAME="$2";       shift 2 ;;
        --project-path)  PROJECT_PATH="$2";  shift 2 ;;
        --help|-h)
            echo "Usage: $0 [--project NAME] [--version X.0] [--db DBNAME] [--project-path PATH]"
            exit 0 ;;
        *) error "Argument inconnu : $1" ;;
    esac
done

# ── Mode interactif si paramètres manquants ───────────────────────────────────
header "Configuration du projet Odoo"

if [[ -z "$PROJECT_NAME" ]]; then
    default_name=$(basename "$(pwd)" | sed 's/^odoo-//')
    read -rp "  Nom du projet [${default_name}]: " PROJECT_NAME
    PROJECT_NAME="${PROJECT_NAME:-$default_name}"
fi

if [[ -z "$ODOO_VERSION" ]]; then
    detected=""
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

if [[ -z "$PROJECT_PATH" ]]; then
    default_path="$(pwd)"
    read -rp "  Racine du projet [${default_path}]: " PROJECT_PATH
    PROJECT_PATH="${PROJECT_PATH:-$default_path}"
fi
PROJECT_PATH="$(realpath "${PROJECT_PATH/#\~/$HOME}")"

# ── Chemins dérivés ───────────────────────────────────────────────────────────
COMMUNITY_PATH="${ODOO_BASE}/${ODOO_VERSION}/community"
ENTERPRISE_PATH="${ODOO_BASE}/${ODOO_VERSION}/enterprise"
THEMES_PATH="${ODOO_BASE}/${ODOO_VERSION}/themes"
FILESTORE_DIR="/tmp/odoo/${PROJECT_NAME}"
VENV_DIR=".venv"
WORKSPACE_FILE="${PROJECT_NAME}.code-workspace"
CONF_DIR=".config"
CONF_FILE="${CONF_DIR}/odoo.conf"
ODOO_BIN="${COMMUNITY_PATH}/odoo-bin"

# ── Vérifications ─────────────────────────────────────────────────────────────
header "Vérifications"

command -v uv &>/dev/null \
    || error "'uv' n'est pas installé. Installe-le via : curl -Ls https://astral.sh/uv/install.sh | sh"

for dir in "$COMMUNITY_PATH" "$ENTERPRISE_PATH" "$THEMES_PATH"; do
    if [[ -d "$dir" ]]; then
        success "Trouvé : $dir"
    else
        warn "Absent  : $dir  (ignoré dans addons_path)"
    fi
done

# ── Calcul de l'addons_path ───────────────────────────────────────────────────
addons_paths=()
[[ -d "${COMMUNITY_PATH}/addons" ]] && addons_paths+=("${COMMUNITY_PATH}/addons")
[[ -d "$ENTERPRISE_PATH" ]]         && addons_paths+=("$ENTERPRISE_PATH")
[[ -d "$THEMES_PATH" ]]             && addons_paths+=("$THEMES_PATH")
addons_paths+=("$PROJECT_PATH")     # Racine du projet (là où est le .workspace)

ADDONS_PATH=$(IFS=,; echo "${addons_paths[*]}")

# ── Filestore dans /tmp ───────────────────────────────────────────────────────
header "Filestore"
mkdir -p "$FILESTORE_DIR"
success "Filestore : $FILESTORE_DIR  (éphémère, nettoyé au reboot)"

# ── Fonction upsert pour odoo.conf ────────────────────────────────────────────
# Remplace la valeur si la clé existe (même commentée), sinon ajoute à la fin.
upsert_conf() {
    local file="$1" key="$2" value="$3"
    if grep -qE "^;?[[:space:]]*${key}[[:space:]]*=" "$file" 2>/dev/null; then
        sed -i -E "s|^;?[[:space:]]*${key}[[:space:]]*=.*|${key} = ${value}|" "$file"
    else
        echo "${key} = ${value}" >> "$file"
    fi
}

# ── .config/odoo.conf ─────────────────────────────────────────────────────────
header ".config/odoo.conf"
mkdir -p "$CONF_DIR"

if [[ ! -f "$CONF_FILE" ]]; then
    info "Création de $CONF_FILE"
    cat > "$CONF_FILE" <<EOF
[options]
addons_path = ${ADDONS_PATH}
data_dir = ${FILESTORE_DIR}
db_host = ${DB_HOST}
db_port = ${DB_PORT}
db_user = ${DB_USER}
db_password = ${DB_PASSWORD}
db_name = ${DB_NAME}
admin_passwd = ${ADMIN_PASSWD}
limit_memory_soft = 1077721600
limit_memory_hard = 3355443200
limit_request = 8192
limit_time_cpu = 3200
limit_time_real = 3200
max_cron_threads = 0
workers = 0
log_level = info
EOF
    success "$CONF_FILE créé"
else
    info "Mise à jour de $CONF_FILE (upsert)"
    # Garantit que [options] est présent
    grep -q '^\[options\]' "$CONF_FILE" || sed -i '1s/^/[options]\n/' "$CONF_FILE"

    upsert_conf "$CONF_FILE" "addons_path"       "$ADDONS_PATH"
    upsert_conf "$CONF_FILE" "data_dir"          "$FILESTORE_DIR"
    upsert_conf "$CONF_FILE" "db_host"           "$DB_HOST"
    upsert_conf "$CONF_FILE" "db_port"           "$DB_PORT"
    upsert_conf "$CONF_FILE" "db_user"           "$DB_USER"
    upsert_conf "$CONF_FILE" "db_password"       "$DB_PASSWORD"
    upsert_conf "$CONF_FILE" "db_name"           "$DB_NAME"
    upsert_conf "$CONF_FILE" "admin_passwd"      "$ADMIN_PASSWD"
    upsert_conf "$CONF_FILE" "limit_memory_soft" "1077721600"
    upsert_conf "$CONF_FILE" "limit_memory_hard" "3355443200"
    upsert_conf "$CONF_FILE" "limit_request"     "8192"
    upsert_conf "$CONF_FILE" "limit_time_cpu"    "3200"
    upsert_conf "$CONF_FILE" "limit_time_real"   "3200"
    upsert_conf "$CONF_FILE" "max_cron_threads"  "0"
    upsert_conf "$CONF_FILE" "workers"           "0"
    upsert_conf "$CONF_FILE" "log_level"         "info"

    success "$CONF_FILE mis à jour"
fi

# ── docker-compose.yml ────────────────────────────────────────────────────────
header "docker-compose.yml"

COMPOSE_FILE="docker-compose.yml"

if [[ -f "$COMPOSE_FILE" ]]; then
    mv "$COMPOSE_FILE" "${COMPOSE_FILE}.old"
    warn "Existant sauvegardé → ${COMPOSE_FILE}.old"
fi

cat > "$COMPOSE_FILE" <<EOF
services:
  # Service odoo désactivé pour le dev natif (sans Docker)
  # odoo:
  #   image: apik/odoo:${ODOO_VERSION}-enterprise
  #   command: odoo --dev=all
  #   depends_on:
  #     - postgres
  #   ports:
  #     - "8069:8069"
  #   environment:
  #     - HOST=postgres
  #     - USER=${DB_USER}
  #     - PASSWORD=${DB_PASSWORD}
  #   volumes:
  #     - ./.config:/etc/odoo:rw
  #     - .:/mnt/extra-addons:rw
  #     - ${PROJECT_NAME}_odoo:/var/lib/odoo

  postgres:
    image: pgvector/pgvector:pg16
    ports:
      - "${DB_PORT}:5432"
    environment:
      - POSTGRES_DB=postgres
      - POSTGRES_PASSWORD=${DB_PASSWORD}
      - POSTGRES_USER=${DB_USER}
      - PGDATA=/var/lib/postgresql/data/pgdata
    volumes:
      - ${PROJECT_NAME}_postgres:/var/lib/postgresql/data/pgdata

volumes:
  # ${PROJECT_NAME}_odoo:
  ${PROJECT_NAME}_postgres:
EOF

success "docker-compose.yml écrit"

# ── .vscode/tasks.json ────────────────────────────────────────────────────────
# Les vars bash sont passées via sys.argv pour éviter toute substitution dans
# les literals VSCode (${workspaceFolder}, ${input:...}).
header ".vscode/tasks.json"
mkdir -p .vscode

python3 /dev/stdin \
    "$VENV_DIR" "$ODOO_BIN" "$CONF_FILE" "$DB_NAME" "$COMMUNITY_PATH" \
    > .vscode/tasks.json <<'PYEOF'
import json, sys

venv, odoo_bin, conf, db, community = sys.argv[1:]

# Literals VSCode — ne doivent pas être substitués par bash
WS       = "${workspaceFolder}"
I_MODULE = "${input:moduleUpdate}"
I_NAME   = "${input:moduleName}"
I_PKG    = "${input:packageName}"

# Présentation réutilisables
SILENT_CLOSE  = {"reveal": "silent", "panel": "shared", "close": True}
DEDICATED     = {"reveal": "always", "panel": "dedicated", "focus": True}

tasks = {
    "version": "2.0.0",
    "tasks": [
        {
            "label": "🐍 Venv: créer / mettre à jour",
            "type": "shell",
            "command": (
                f"uv venv {venv} "
                f"&& uv pip install -r {community}/requirements.txt "
                f"&& uv pip install -r requirements.txt"
            ),
            "options": {"cwd": WS},
            "group": "build",
            "presentation": SILENT_CLOSE,
            "problemMatcher": []
        },
        {
            "label": "📦 Venv: installer un package",
            "type": "shell",
            "command": f"uv pip install {I_PKG}",
            "options": {"cwd": WS},
            "presentation": SILENT_CLOSE,
            "problemMatcher": []
        },
        {
            "label": "🐘 PostgreSQL: démarrer",
            "type": "shell",
            "command": "docker compose up postgres -d",
            "options": {"cwd": WS},
            "group": "build",
            "presentation": SILENT_CLOSE,
            "problemMatcher": []
        },
        {
            "label": "🟢 Odoo: lancer",
            "type": "shell",
            "command": f"{venv}/bin/python {odoo_bin} --config={conf} --dev=all",
            "options": {"cwd": WS},
            "group": "build",
            "dependsOn": "🐘 PostgreSQL: démarrer",
            "presentation": DEDICATED,
            "problemMatcher": []
        },
        {
            "label": "🔄 Odoo: update module",
            "type": "shell",
            "command": (
                f"{venv}/bin/python {odoo_bin} "
                f"--config={conf} "
                f"--db_name={db} "
                f"-u {I_MODULE} "
                "--stop-after-init"
            ),
            "options": {"cwd": WS},
            "presentation": SILENT_CLOSE,
            "problemMatcher": []
        },
        {
            "label": "🛠  Odoo: scaffold module",
            "type": "shell",
            "command": f"{venv}/bin/python {odoo_bin} scaffold {I_NAME} .",
            "options": {"cwd": WS},
            "presentation": SILENT_CLOSE,
            "problemMatcher": []
        },
        {
            "label": "🐚 Odoo: shell",
            "type": "shell",
            "command": f"{venv}/bin/python {odoo_bin} shell --config={conf} --db_name={db}",
            "options": {"cwd": WS},
            "presentation": DEDICATED,
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
        },
        {
            "id": "packageName",
            "type": "promptString",
            "description": "Package(s) à installer — ex: requests pandas",
            "default": ""
        }
    ]
}

print(json.dumps(tasks, indent=4, ensure_ascii=False))
PYEOF

success ".vscode/tasks.json écrit"

# ── *.code-workspace ──────────────────────────────────────────────────────────
header "Code workspace"

extra_paths=()
[[ -d "$COMMUNITY_PATH" ]] && extra_paths+=("$COMMUNITY_PATH")
[[ -d "$ENTERPRISE_PATH" ]] && extra_paths+=("$ENTERPRISE_PATH")
[[ -d "$THEMES_PATH" ]]     && extra_paths+=("$THEMES_PATH")

python3 /dev/stdin "$WORKSPACE_FILE" "${extra_paths[@]:-}" <<'PYEOF'
import json, sys

outfile  = sys.argv[1]
extra    = [p for p in sys.argv[2:] if p]

workspace = {
    "folders": [{"path": "."}],
    "settings": {
        "python.analysis.extraPaths":    extra,
        "python.autoComplete.extraPaths": extra,
        "python.defaultInterpreterPath": ".venv/bin/python",
    }
}

with open(outfile, "w") as f:
    json.dump(workspace, f, indent=4, ensure_ascii=False)
    f.write("\n")
PYEOF

success "Workspace écrit : ${WORKSPACE_FILE}"

# ── .gitignore ────────────────────────────────────────────────────────────────
header ".gitignore"

GITIGNORE_ADDITIONS=(
    "# Odoo dev local"
    ".venv/"
    ".config/odoo.conf"
    ".vscode/tasks.json"
    "${WORKSPACE_FILE}"
    "*.log"
    "__pycache__/"
)

[[ ! -f ".gitignore" ]] && touch .gitignore

added=0
for line in "${GITIGNORE_ADDITIONS[@]}"; do
    if ! grep -qxF "$line" .gitignore; then
        echo "$line" >> .gitignore
        added=$((added + 1))
    fi
done

[[ $added -gt 0 ]] && success ".gitignore — $added entrées ajoutées" \
                   || info    ".gitignore — rien à ajouter"

# ── Résumé ────────────────────────────────────────────────────────────────────
echo ""
echo -e "${BOLD}╔══════════════════════════════════════════════════════╗${RESET}"
echo -e "${BOLD}║  Projet ${PROJECT_NAME} (Odoo ${ODOO_VERSION}) prêt${RESET}"
echo -e "${BOLD}╠══════════════════════════════════════════════════════╣${RESET}"
echo -e "  Projet     : ${PROJECT_PATH}"
echo -e "  Filestore  : ${FILESTORE_DIR}"
echo -e "  DB         : ${DB_NAME} @ ${DB_HOST}:${DB_PORT}"
echo -e "  Conf       : ${CONF_FILE}"
echo -e "  Addons     : ${ADDONS_PATH}"
echo -e "  Venv       : ${VENV_DIR}  (uv)"
echo -e ""
echo -e "  ${CYAN}Prochaine étape :${RESET}"
echo -e "    Ctrl+Shift+P → Tasks: Run Task → 🐍 Venv: créer / mettre à jour"
echo -e "    Ctrl+Shift+P → Tasks: Run Task → 🟢 Odoo: lancer"
echo -e "${BOLD}╚══════════════════════════════════════════════════════╝${RESET}"
echo ""
