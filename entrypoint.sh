#!/bin/sh
set -eu

# return true if specified directory is empty
directory_empty() {
    [ -z "$(ls -A "$1/")" ]
}

waiting_for_connection(){
  until nc -z -w 3 "$1" "$2"; do
    >&2 echo "Waiting for connection to the $1 host on port $2"
    sleep 1
  done
}

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

file_env MYSQL_SERVER
file_env MYSQL_DATABASE
file_env MYSQL_USER
file_env MYSQL_PASSWORD
file_env MYSQL_PORT
file_env CACHE_TYPE
file_env CACHE_HOST
file_env CACHE_PORT
file_env KODBOX_ADMIN_USER
file_env KODBOX_ADMIN_PASSWORD

MYSQL_PORT=${MYSQL_PORT:-3306}
CACHE_TYPE=${CACHE_TYPE:-redis}
CACHE_PORT=${CACHE_PORT:-6379}

waiting_for_db(){
  waiting_for_connection $MYSQL_SERVER $MYSQL_PORT
}

waiting_for_cache(){
  waiting_for_connection $CACHE_HOST $CACHE_PORT
}

if [ -n "${MYSQL_DATABASE+x}" ] && [ -n "${MYSQL_USER+x}" ] && [ -n "${MYSQL_PASSWORD+x}" ] && [ ! -f "/usr/src/kodbox/config/setting_user.php" ]; then
        mv /usr/src/kodbox/config/setting_user.example /usr/src/kodbox/config/setting_user.php
        sed -i "s/MYSQL_SERVER/${MYSQL_SERVER}/g" /usr/src/kodbox/config/setting_user.php
        sed -i "s/MYSQL_DATABASE/${MYSQL_DATABASE}/g" /usr/src/kodbox/config/setting_user.php
        sed -i "s/MYSQL_USER/${MYSQL_USER}/g" /usr/src/kodbox/config/setting_user.php
        sed -i "N;6 a 'DB_PWD' => '${MYSQL_PASSWORD}'," /usr/src/kodbox/config/setting_user.php
        sed -i "s/MYSQL_PORT/${MYSQL_PORT}/g" /usr/src/kodbox/config/setting_user.php
        touch /usr/src/kodbox/data/system/fastinstall.lock
        if [ -n "${KODBOX_ADMIN_USER+x}" ] && [ -n "${KODBOX_ADMIN_PASSWORD+x}" ]; then
            echo -e "ADM_NAME=${KODBOX_ADMIN_USER}\nADM_PWD=${KODBOX_ADMIN_PASSWORD}" >> /usr/src/kodbox/data/system/fastinstall.lock
        fi
        if [ -n "${CACHE_HOST+x}" ]; then
            sed -i "s/CACHE_TYPE/${CACHE_TYPE}/g" /usr/src/kodbox/config/setting_user.php
            sed -i "s/CACHE_HOST/${CACHE_HOST}/g" /usr/src/kodbox/config/setting_user.php
            sed -i "s/CACHE_PORT/${CACHE_PORT}/g" /usr/src/kodbox/config/setting_user.php
        else
            sed -i "s/CACHE_TYPE/file/g" /usr/src/kodbox/config/setting_user.php
            sed -i "s/CACHE_HOST/file/g" /usr/src/kodbox/config/setting_user.php
        fi
fi

if [ ! -z "$PUID" ]; then
  if [ -z "$PGID" ]; then
    PGID=${PUID}
  fi
  deluser nginx
  addgroup -g ${PGID} nginx
  adduser -D -S -h /var/cache/nginx -s /sbin/nologin -G nginx -u ${PUID} nginx
  chown -R nginx:nginx /var/lib/nginx/
fi

if  directory_empty "/var/www/html"; then
        if [ "$(id -u)" = 0 ]; then
            rsync_options="-rlDog --chown nginx:root"
        else
            rsync_options="-rlD"
        fi
        echo "KODBOX is installing ..."
        rsync $rsync_options --delete /usr/src/kodbox/ /var/www/html/
        if [ -n "${KODBOX_ADMIN_USER+x}" ] && [ -n "${KODBOX_ADMIN_PASSWORD+x}" ]; then
            waiting_for_cache
            waiting_for_db
            php /var/www/html/index.php "install/index/auto"
            chown -R nginx:root /var/www
        fi
else
        echo "KODBOX has been configured!"
fi

if [ -f /etc/nginx/ssl/fullchain.pem ] && [ -f /etc/nginx/ssl/privkey.pem ] && [ ! -f /etc/nginx/sites-enabled/*-ssl.conf ] ; then
        ln -s /etc/nginx/sites-available/private-ssl.conf /etc/nginx/sites-enabled/
        sed -i "s/#return 301/return 301/g" /etc/nginx/sites-available/default.conf
fi

exec "$@"

