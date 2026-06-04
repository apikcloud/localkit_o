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
            "command": "bash .vscode/odoo-start.sh",
            "options": {"cwd": WS},
            "group": "build",
            "dependsOn": "🐘 PostgreSQL: démarrer",
            "presentation": DEDICATED,
            "problemMatcher": []
        },
        {
            "label": "🔍 Odoo: gérer les instances",
            "type": "shell",
            "command": "bash .vscode/odoo-ps.sh",
            "options": {"cwd": WS},
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

# ── .vscode/odoo-start.sh ─────────────────────────────────────────────────────
# Wrapper appelé par la task "Odoo: lancer".
# Vérifie si le port 8069 est libre ; propose un alternatif via read sinon.
header ".vscode/odoo-start.sh"

cat > .vscode/odoo-start.sh <<EOF
#!/usr/bin/env bash
# Généré par odoo-init.sh — ne pas versionner (.gitignore)
set -euo pipefail

VENV="${PROJECT_PATH}/${VENV_DIR}"
ODOO_BIN="${ODOO_BIN}"
CONF="${PROJECT_PATH}/${CONF_FILE}"
DEFAULT_PORT=8069

# ── Couleurs ──────────────────────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; BOLD='\033[1m'; RESET='\033[0m'

# ── Détection : qui occupe un port TCP ? ──────────────────────────────────────
# Retourne "native:<pid>" ou "docker:<container>" ou "" si libre
port_occupant() {
    local port=\$1

    # 1. Process natif Python/odoo-bin
    local pid
    pid=\$(lsof -iTCP:\$port -sTCP:LISTEN -t 2>/dev/null | head -1 || true)
    if [[ -n "\$pid" ]]; then
        local cmdline
        cmdline=\$(cat /proc/\$pid/cmdline 2>/dev/null | tr '\0' ' ' || true)
        if echo "\$cmdline" | grep -q "odoo-bin"; then
            echo "native:\$pid"
            return
        fi
    fi

    # 2. Conteneur Docker exposant ce port
    local container
    container=\$(docker ps --format '{{.Names}} {{.Ports}}' 2>/dev/null \
        | awk -v p=":\$port->" '\$0 ~ p {print \$1}' | head -1 || true)
    if [[ -n "\$container" ]]; then
        echo "docker:\$container"
        return
    fi

    # 3. Autre process quelconque (ex: nginx, autre appli)
    if [[ -n "\$pid" ]]; then
        local procname
        procname=\$(ps -p "\$pid" -o comm= 2>/dev/null || echo "PID \$pid")
        echo "other:\$procname"
        return
    fi

    echo ""
}

# ── Listage de toutes les instances Odoo actives (natif + Docker) ─────────────
list_odoo_instances() {
    local found=0

    # Natif : process python avec odoo-bin dans la cmdline
    lsof -iTCP -sTCP:LISTEN 2>/dev/null \
        | awk '\$1 == "python" || \$1 == "python3" {print \$2, \$9}' \
        | sort -u \
        | while read -r pid portinfo; do
            local cmdline
            cmdline=\$(cat /proc/\$pid/cmdline 2>/dev/null | tr '\0' ' ' || true)
            if echo "\$cmdline" | grep -q "odoo-bin"; then
                local port cwd project
                port=\$(echo "\$portinfo" | grep -oP ':\K[0-9]+\$' || echo "?")
                cwd=\$(readlink /proc/\$pid/cwd 2>/dev/null || echo "inconnu")
                project=\$(basename "\$cwd")
                echo -e "  🐍 natif   PID \${CYAN}\$pid\${RESET}  :\${port}  \${YELLOW}\$project\${RESET}  (\$cwd)"
                found=1
            fi
        done

    # Docker : conteneurs avec port 8069 ou autre exposé
    docker ps --format '{{.Names}} {{.Image}} {{.Ports}}' 2>/dev/null \
        | grep -i "odoo\|8069" \
        | while read -r name image ports; do
            echo -e "  🐳 docker  \${CYAN}\$name\${RESET}  \${YELLOW}\$image\${RESET}  (\$ports)"
            found=1
        done

    [[ \$found -eq 0 ]] && echo -e "  \${YELLOW}(aucune instance Odoo détectée)\${RESET}"
}

# ── Choix du port ─────────────────────────────────────────────────────────────
PORT=\$DEFAULT_PORT
occupant=\$(port_occupant \$PORT)

if [[ -n "\$occupant" ]]; then
    kind=\${occupant%%:*}
    detail=\${occupant#*:}

    echo ""
    echo -e "\${YELLOW}⚠  Port \$PORT déjà utilisé"
    case "\$kind" in
        native) echo -e "   → instance Odoo native (PID \$detail)\${RESET}" ;;
        docker) echo -e "   → conteneur Docker : \$detail\${RESET}" ;;
        other)  echo -e "   → autre process : \$detail\${RESET}" ;;
    esac
    echo ""
    echo -e "\${BOLD}Instances Odoo actives :\${RESET}"
    list_odoo_instances
    echo ""
    read -rp "  Port à utiliser [laisser vide pour annuler] : " input_port
    [[ -z "\$input_port" ]] && { echo "Annulé."; exit 0; }
    PORT="\$input_port"

    new_occupant=\$(port_occupant "\$PORT")
    if [[ -n "\$new_occupant" ]]; then
        echo -e "\${RED}✖ Port \$PORT également occupé (\${new_occupant#*:}). Abandon.\${RESET}"
        exit 1
    fi
fi

echo ""
echo -e "\${GREEN}▶ Lancement Odoo sur le port \${PORT}…\${RESET}"
echo ""

exec "\$VENV/bin/python" "\$ODOO_BIN" \\
    --config="\$CONF" \\
    --http-port="\$PORT" \\
    --dev=all
EOF

chmod +x .vscode/odoo-start.sh
success ".vscode/odoo-start.sh écrit"

# ── .vscode/odoo-ps.sh ────────────────────────────────────────────────────────
# Script appelé par la task "Odoo: gérer les instances".
# Liste toutes les instances odoo-bin actives et propose de les terminer.
header ".vscode/odoo-ps.sh"

cat > .vscode/odoo-ps.sh <<'PSEOF'
#!/usr/bin/env bash
# Généré par odoo-init.sh — ne pas versionner (.gitignore)
set -euo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; BOLD='\033[1m'; RESET='\033[0m'

echo ""
echo -e "${BOLD}── Instances Odoo actives ──${RESET}"
echo ""

# ── Collecte ──────────────────────────────────────────────────────────────────
# Chaque entrée : "native:<pid>:<port>:<cwd>" ou "docker:<name>:<ports>:<image>"
entries=()

# Natif
while read -r pid portinfo; do
    cmdline=$(cat /proc/$pid/cmdline 2>/dev/null | tr '\0' ' ' || true)
    if echo "$cmdline" | grep -q "odoo-bin"; then
        port=$(echo "$portinfo" | grep -oP ':\K[0-9]+$' || echo "?")
        cwd=$(readlink /proc/$pid/cwd 2>/dev/null || echo "inconnu")
        entries+=("native:$pid:$port:$cwd")
    fi
done < <(
    lsof -iTCP -sTCP:LISTEN 2>/dev/null \
        | awk '$1 == "python" || $1 == "python3" {print $2, $9}' \
        | sort -u
)

# Docker
while read -r name image ports; do
    entries+=("docker:$name:$ports:$image")
done < <(
    docker ps --format '{{.Names}} {{.Image}} {{.Ports}}' 2>/dev/null \
        | grep -i "odoo\|8069" || true
)

# ── Affichage ─────────────────────────────────────────────────────────────────
if [[ ${#entries[@]} -eq 0 ]]; then
    echo -e "  ${GREEN}Aucune instance Odoo en cours d'exécution.${RESET}"
    echo ""
    exit 0
fi

i=1
for entry in "${entries[@]}"; do
    IFS=: read -r kind id_or_pid port_or_ports cwd_or_image <<< "$entry"
    if [[ "$kind" == "native" ]]; then
        project=$(basename "$cwd_or_image")
        echo -e "  ${CYAN}[$i]${RESET}  🐍 natif   PID ${BOLD}$id_or_pid${RESET}  :${port_or_ports}  ${YELLOW}$project${RESET}  ($cwd_or_image)"
    else
        echo -e "  ${CYAN}[$i]${RESET}  🐳 docker  ${BOLD}$id_or_pid${RESET}  ${YELLOW}$cwd_or_image${RESET}  ($port_or_ports)"
    fi
    ((i++))
done

echo ""
echo -e "  ${CYAN}[a]${RESET}  Terminer toutes les instances"
echo -e "  ${CYAN}[0]${RESET}  Annuler"
echo ""
read -rp "  Choix : " choice

# ── Action ────────────────────────────────────────────────────────────────────
stop_entry() {
    local entry="$1"
    IFS=: read -r kind id_or_pid port_or_ports cwd_or_image <<< "$entry"
    if [[ "$kind" == "native" ]]; then
        local project
        project=$(basename "$cwd_or_image")
        kill "$id_or_pid" \
            && echo -e "  ${GREEN}✔${RESET} PID $id_or_pid ($project :$port_or_ports) terminé" \
            || echo -e "  ${RED}✖${RESET} PID $id_or_pid : échec"
    else
        docker stop "$id_or_pid" &>/dev/null \
            && echo -e "  ${GREEN}✔${RESET} Conteneur $id_or_pid arrêté" \
            || echo -e "  ${RED}✖${RESET} Conteneur $id_or_pid : échec"
    fi
}

case "$choice" in
    0|"")
        echo "Annulé."
        exit 0
        ;;
    a|A)
        for entry in "${entries[@]}"; do
            stop_entry "$entry"
        done
        ;;
    *)
        idx=$((choice - 1))
        if [[ $idx -ge 0 && $idx -lt ${#entries[@]} ]]; then
            stop_entry "${entries[$idx]}"
        else
            echo -e "  ${RED}✖${RESET} Choix invalide."
            exit 1
        fi
        ;;
esac

echo ""
PSEOF

chmod +x .vscode/odoo-ps.sh
success ".vscode/odoo-ps.sh écrit"

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
    ".vscode/odoo-start.sh"
    ".vscode/odoo-ps.sh"
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
