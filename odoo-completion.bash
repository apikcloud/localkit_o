#!/usr/bin/env bash
# Bash completion for the odoo command
# Provides tab-completion for module names after -u/--update and -i/--init

_odoo_list_modules() {
    local paths=("/mnt/extra-addons")
    local path
    for path in "${paths[@]}"; do
        [[ -d "$path" ]] || continue
        find "$path" -maxdepth 3 -name "__manifest__.py" -printf '%h\n' 2>/dev/null \
            | xargs -I{} basename {}
    done
}

_odoo_completion() {
    local cur prev
    _init_completion || return

    case "$prev" in
        -u|--update|-i|--init)
            # Support comma-separated module lists: odoo -u mod1,mod2,<TAB>
            local cur_prefix="" cur_module="$cur"
            if [[ "$cur" == *","* ]]; then
                cur_prefix="${cur%,*},"
                cur_module="${cur##*,}"
            fi

            local modules
            mapfile -t modules < <(_odoo_list_modules | sort -u)

            local m
            COMPREPLY=()
            for m in "${modules[@]}"; do
                [[ "$m" == "$cur_module"* ]] || continue
                COMPREPLY+=("${cur_prefix}${m}")
            done
            return
            ;;
        --log-level)
            COMPREPLY=($(compgen -W "debug info warning error critical" -- "$cur"))
            return
            ;;
    esac

    # Complete flags when cur starts with -
    if [[ "$cur" == -* ]]; then
        local opts="-u --update -i --init -d --database --db-filter
                    -c --config --addons-path --without-demo
                    --stop-after-init --test-enable --test-file --test-tags
                    --log-level --logfile --workers --max-cron-threads
                    --dev --pidfile --http-interface --http-port"
        COMPREPLY=($(compgen -W "$opts" -- "$cur"))
    fi
}

complete -F _odoo_completion odoo

