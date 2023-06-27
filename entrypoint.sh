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
file_env FPM_MAX
file_env FPM_START
file_env FPM_MIN_SPARE
file_env FPM_MAX_SPARE

MYSQL_PORT=${MYSQL_PORT:-3306}
CACHE_TYPE=${CACHE_TYPE:-redis}
CACHE_PORT=${CACHE_PORT:-6379}

FPM_MAX=${FPM_MAX:-50}
FPM_START=${FPM_START:-10}
FPM_MIN_SPARE=${FPM_MIN_SPARE:-10}
FPM_MAX_SPARE=${FPM_MAX_SPARE:-30}

waiting_for_db(){
  waiting_for_connection $MYSQL_SERVER $MYSQL_PORT
}

waiting_for_cache(){
  waiting_for_connection $CACHE_HOST $CACHE_PORT
}

CONIG_FILE=/usr/src/kodbox/config/setting_user.php

if [ -n "${MYSQL_DATABASE+x}" ] && [ -n "${MYSQL_USER+x}" ] && [ -n "${MYSQL_PASSWORD+x}" ] && [ ! -f "$CONIG_FILE" ]; then
  mv /usr/src/kodbox/config/setting_user.example $CONIG_FILE
  sed -i "s/MYSQL_SERVER/${MYSQL_SERVER}/g" $CONIG_FILE
  sed -i "s/MYSQL_DATABASE/${MYSQL_DATABASE}/g" $CONIG_FILE
  sed -i "s/MYSQL_USER/${MYSQL_USER}/g" $CONIG_FILE
  sed -i "N;6 a 'DB_PWD' => '${MYSQL_PASSWORD}'," $CONIG_FILE
  sed -i "s/MYSQL_PORT/${MYSQL_PORT}/g" $CONIG_FILE
  touch /usr/src/kodbox/data/system/fastinstall.lock
  if [ -n "${KODBOX_ADMIN_USER+x}" ] && [ -n "${KODBOX_ADMIN_PASSWORD+x}" ]; then
    echo -e "ADM_NAME=${KODBOX_ADMIN_USER}\nADM_PWD=${KODBOX_ADMIN_PASSWORD}" >> /usr/src/kodbox/data/system/fastinstall.lock
  fi
  if [ -n "${CACHE_HOST+x}" ]; then
    sed -i "s/CACHE_TYPE/${CACHE_TYPE}/g" $CONIG_FILE
    sed -i "s/CACHE_HOST/${CACHE_HOST}/g" $CONIG_FILE
    sed -i "s/CACHE_PORT/${CACHE_PORT}/g" $CONIG_FILE
  else
    sed -i "s/CACHE_TYPE/file/g" $CONIG_FILE
    sed -i "s/CACHE_HOST/file/g" $CONIG_FILE
  fi
fi

if [ -n "${PUID+x}" ]; then
  if [ ! -n "${PGID+x}" ]; then
    PGID=${PUID}
  fi
  deluser nginx
  addgroup -g ${PGID} nginx
  adduser -D -S -h /var/cache/nginx -s /sbin/nologin -G nginx -u ${PUID} nginx
  chown -R nginx:nginx /var/lib/nginx/
fi

if [ -n "${FPM_MAX+x}" ]; then
  sed -i "s/pm.max_children = .*/pm.max_children = ${FPM_MAX}/g" /usr/local/etc/php-fpm.d/www.conf
  sed -i "s/pm.start_servers = .*/pm.start_servers = ${FPM_START}/g" /usr/local/etc/php-fpm.d/www.conf
  sed -i "s/pm.min_spare_servers = .*/pm.min_spare_servers = ${FPM_MIN_SPARE}/g" /usr/local/etc/php-fpm.d/www.conf
  sed -i "s/pm.max_spare_servers = .*/pm.max_spare_servers = ${FPM_MAX_SPARE}/g" /usr/local/etc/php-fpm.d/www.conf
fi

if  directory_empty "/var/www/html"; then
  if [ "$(id -u)" = 0 ]; then
    rsync_options="-rlDog --chown nginx:nginx"
  else
    rsync_options="-rlD"
  fi
  echo "KODBOX is installing ..."
  rsync $rsync_options --delete /usr/src/kodbox/ /var/www/html/
  if [ -f "$CONIG_FILE" ]; then
    if [ -n "${CACHE_HOST+x}" ]; then
      waiting_for_cache
    fi
    waiting_for_db
    php /var/www/html/index.php "install/index/auto"
    chown -R nginx:root /var/www
  fi
else
  echo "KODBOX has been configured!"
fi

if [ -f /etc/nginx/ssl/fullchain.pem ] && [ -f /etc/nginx/ssl/privkey.pem ] && [ ! -f /etc/nginx/sites-enabled/*-ssl.conf ] ; then
  ln -s /etc/nginx/sites-available/private-ssl.conf /etc/nginx/sites-enabled/
  sed -i "s/#return 301/return 301/g" /etc/nginx/nginx.conf
fi

exec "$@"

