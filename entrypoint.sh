#!/bin/sh
set -eu

# version_greater A B returns whether A > B
version_greater() {
    [ "$(printf '%s\n' "$@" | sort -t '.' -n -k1,1 -k2,2 -k3,3 -k4,4 | head -n 1)" != "$1" ]
}

# return true if specified directory is empty
directory_empty() {
    [ -z "$(ls -A "$1/")" ]
}

run_as() {
    if [ "$(id -u)" = 0 ]; then
        su -p "$user" -s /bin/sh -c "$1"
    else
        sh -c "$1"
    fi
}

# Execute all executable files in a given directory in alphanumeric order
run_path() {
    local hook_folder_path="/docker-entrypoint-hooks.d/$1"
    local return_code=0

    if ! [ -d "${hook_folder_path}" ]; then
        echo "=> Skipping the folder \"${hook_folder_path}\", because it doesn't exist"
        return 0
    fi

    echo "=> Searching for scripts (*.sh) to run, located in the folder: ${hook_folder_path}"

    (
        find "${hook_folder_path}" -type f -maxdepth 1 -iname '*.sh' -print | sort | while read -r script_file_path; do
            if ! [ -x "${script_file_path}" ]; then
                echo "==> The script \"${script_file_path}\" was skipped, because it didn't have the executable flag"
                continue
            fi

            echo "==> Running the script (cwd: $(pwd)): \"${script_file_path}\""

            run_as "${script_file_path}" || return_code="$?"

            if [ "${return_code}" -ne "0" ]; then
                echo "==> Failed at executing \"${script_file_path}\". Exit code: ${return_code}"
                exit 1
            fi

            echo "==> Finished the script: \"${script_file_path}\""
        done
    )
}

# usage: file_env VAR [DEFAULT]
#    ie: file_env 'XYZ_DB_PASSWORD' 'example'
# (will allow for "$XYZ_DB_PASSWORD_FILE" to fill in the value of
#  "$XYZ_DB_PASSWORD" from a file, especially for Docker's secrets feature)
file_env() {
    local var="$1"
    local fileVar="${var}_FILE"
    local def="${2:-}"
    local varValue=$(env | grep -E "^${var}=" | sed -E -e "s/^${var}=//")
    local fileVarValue=$(env | grep -E "^${fileVar}=" | sed -E -e "s/^${fileVar}=//")
    if [ -n "${varValue}" ] && [ -n "${fileVarValue}" ]; then
        echo >&2 "error: both $var and $fileVar are set (but are exclusive)"
        exit 1
    fi
    if [ -n "${varValue}" ]; then
        export "$var"="${varValue}"
    elif [ -n "${fileVarValue}" ]; then
        export "$var"="$(cat "${fileVarValue}")"
    elif [ -n "${def}" ]; then
        export "$var"="$def"
    fi
    unset "$fileVar"
}

waiting_for_connection(){
  until nc -z -w 3 "$1" "$2"; do
    >&2 echo "Waiting for connection to the $1 host on port $2"
    sleep 1
  done
}

if [ -n "${PUID+x}" ]; then
    if [ ! -n "${PGID+x}" ]; then
        PGID=${PUID}
    fi
    deluser nginx
    addgroup -g ${PGID} nginx
    adduser -D -S -h /var/cache/nginx -s /sbin/nologin -G nginx -u ${PUID} nginx
    chown -R nginx:nginx /var/lib/nginx/
fi

if [ -n "${FPM_MAX+x}" ] && [ -n "${FPM_START+x}" ] && [ -n "${FPM_MIN_SPARE+x}" ] && [ -n "${FPM_MAX_SPARE+x}" ]; then
    sed -i "s/pm.max_children = .*/pm.max_children = ${FPM_MAX}/g" /usr/local/etc/php-fpm.d/www.conf
    sed -i "s/pm.start_servers = .*/pm.start_servers = ${FPM_START}/g" /usr/local/etc/php-fpm.d/www.conf
    sed -i "s/pm.min_spare_servers = .*/pm.min_spare_servers = ${FPM_MIN_SPARE}/g" /usr/local/etc/php-fpm.d/www.conf
    sed -i "s/pm.max_spare_servers = .*/pm.max_spare_servers = ${FPM_MAX_SPARE}/g" /usr/local/etc/php-fpm.d/www.conf
fi

if expr "$1" : "supervisord" 1>/dev/null || [ "${KODBOX_UPDATE:-0}" -eq 1 ]; then
    uid="$(id -u)"
    gid="$(id -g)"
    if [ "$uid" = '0' ]; then
        user='nginx'
        group='nginx'
    else
        user="$uid"
        group="$gid"
    fi

    # If another process is syncing the html folder, wait for
    # it to be done, then escape initalization.
    (
        if ! flock -n 9; then
            # If we couldn't get it immediately, show a message, then wait for real
            echo "Another process is initializing Kodbox. Waiting..."
            flock 9
        fi

        installed_version="0.0.0"
        if [ -f /var/www/html/config/version.php ]; then
            # shellcheck disable=SC2016
            installed_version="$(php -r 'require "/var/www/html/config/version.php"; echo KOD_VERSION . "." . KOD_VERSION_BUILD;')"
        fi
        # shellcheck disable=SC2016
        image_version="$(php -r 'require "/usr/src/kodbox/config/version.php"; echo KOD_VERSION . "." . KOD_VERSION_BUILD;')"

        if version_greater "$image_version" "$installed_version"; then
            echo "Initializing Kodbox $image_version ..."
            if [ "$installed_version" != "0.0.0" ]; then
                echo "Upgrading Kodbox from $installed_version ..."
            fi
            if [ "$(id -u)" = 0 ]; then
                rsync_options="-rlDog --chown $user:$group"
            else
                rsync_options="-rlD"
            fi

            # Install
            if [ "$installed_version" = "0.0.0" ]; then
                echo "New Kodbox instance"

                file_env KODBOX_ADMIN_PASSWORD
                file_env KODBOX_ADMIN_USER
                file_env MYSQL_DATABASE
                file_env MYSQL_PASSWORD
                file_env MYSQL_USER

                install=false
                CONIG_FILE="/usr/src/kodbox/config/setting_user.php"

                [ -n "${MYSQL_SERVER+x}" ] && MYSQL_HOST=${MYSQL_SERVER}

                if [ -n "${MYSQL_DATABASE+x}" ] && [ -n "${MYSQL_USER+x}" ] && [ -n "${MYSQL_PASSWORD+x}" ] && [ -n "${MYSQL_HOST+x}" ]; then
                    if [ -f /usr/src/kodbox/config/setting_user.example ] && ! [ -f ${CONIG_FILE} ]; then  
                        cp /usr/src/kodbox/config/setting_user.example ${CONIG_FILE}
                    fi
                    echo "Installing with MySQL database"
                    MYSQL_PORT=${MYSQL_PORT:-3306}
                    sed 's,{{MYSQL_HOST}},'"${MYSQL_HOST}"',' -i ${CONIG_FILE}
                    sed 's,{{MYSQL_PORT}},'"${MYSQL_PORT}"',' -i ${CONIG_FILE}
                    sed 's,{{MYSQL_USER}},'"${MYSQL_USER}"',' -i ${CONIG_FILE}
                    sed 's,{{MYSQL_DATABASE}},'"${MYSQL_DATABASE}"',' -i ${CONIG_FILE}  
                    sed "N;6 a 'DB_PWD' => '${MYSQL_PASSWORD}'," -i ${CONIG_FILE}
                    install=true
                fi

                if [ -n "${KODBOX_ADMIN_USER+x}" ] && [ -n "${KODBOX_ADMIN_PASSWORD+x}" ]; then
                    echo -e "ADM_NAME=${KODBOX_ADMIN_USER}\nADM_PWD=${KODBOX_ADMIN_PASSWORD}" >> /usr/src/kodbox/data/system/fastinstall.lock
                fi

                if [ -n "${REDIS_HOST+x}" ] || [ -n "${CACHE_HOST+x}" ]; then
                    echo "Configuring Redis as session handler"
                    file_env REDIS_HOST_PASSWORD
                    CACHE_HOST=${REDIS_HOST:-redis}
                    CACHE_TYPE=${CACHE_TYPE:-redis}
                    CACHE_PORT=${CACHE_PORT:-6379}
                elif [ -n "${MEMCACHED_HOST+x}" ]; then
                    echo "Configuring Memcached as session handler"
                    file_env MEMCACHED_HOST_PASSWORD
                    CACHE_HOST=${MEMCACHED_HOST}
                    CACHE_TYPE=${CACHE_TYPE:-memcached}
                    CACHE_PORT=${CACHE_PORT:-11211}
                else
                    CACHE_TYPE=${CACHE_TYPE:-file}
                    CACHE_PORT=${CACHE_PORT:-0}
                fi

                if [ -n "${CACHE_TYPE+x}" ] && [ -n "${CACHE_HOST+x}" ]; then
                    sed 's,{{CACHE_TYPE}},'"${CACHE_TYPE}"',' -i $CONIG_FILE
                    sed 's,{{CACHE_HOST}},'"${CACHE_HOST}"',' -i $CONIG_FILE
                    sed 's,{{CACHE_PORT}},'"${CACHE_PORT}"',' -i $CONIG_FILE
                fi

                if [ -n "${REDIS_HOST_PASSWORD+x}" ]; then
                    sed '/CACHE_PASSWORD/s/^#//g' -i $CONIG_FILE
                    sed 's,{{CACHE_PASSWORD}},'"${REDIS_HOST_PASSWORD}"',' -i $CONIG_FILE
                elif [ -n "${MEMCACHED_HOST_PASSWORD+x}" ]; then
                    sed '/CACHE_PASSWORD/s/^#//g' -i $CONIG_FILE
                    sed 's,{{CACHE_PASSWORD}},'"${MEMCACHED_HOST_PASSWORD}"',' -i $CONIG_FILE
                fi

                if [ "$install" = true ]; then
                    run_path pre-installation

                    echo "Starting Kodbox installation"
                    rsync $rsync_options --delete --exclude '/*.zip' --exclude '/config/setting_user.example' /usr/src/kodbox/ /var/www/html/
                    if [ -f "$CONIG_FILE" ]; then
                        if [ -n "${CACHE_HOST+x}" ]; then
                            waiting_for_connection $CACHE_HOST $CACHE_PORT
                        fi
                        waiting_for_connection $MYSQL_HOST $MYSQL_PORT
                        run_as 'php /var/www/html/index.php install/index/auto'
                    fi
                    run_path post-installation
                else
                    rsync $rsync_options --delete --exclude '/*.zip' --exclude '/config/setting_user.example' /usr/src/kodbox/ /var/www/html/
                    echo "Please run the web-based installer on first connect!"
                fi
            # Upgrade
            else
                run_path pre-upgrade

                if [ -f "/usr/src/kodbox/update.zip" ]; then
                    unzip -o /usr/src/kodbox/update.zip -d /usr/src/update
                    rsync $rsync_options /usr/src/update/ /var/www/html/
                    supervisorctl restart php-fpm
                fi

                run_path post-upgrade
            fi

            echo "Initializing finished"
        fi

    ) 9> /var/www/html/kodbox-init-sync.lock

    run_path before-starting
fi

if [ -f /etc/nginx/ssl/fullchain.pem ] && [ -f /etc/nginx/ssl/privkey.pem ] && [ ! -f /etc/nginx/sites-enabled/*-ssl.conf ] ; then
    ln -s /etc/nginx/sites-available/private-ssl.conf /etc/nginx/sites-enabled/
    sed -i "s/#return 301/return 301/g" /etc/nginx/nginx.conf
fi

exec "$@"