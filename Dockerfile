FROM php:8.3-fpm-alpine3.22

# RUN sed -i 's/dl-cdn.alpinelinux.org/mirrors.aliyun.com/g' /etc/apk/repositories
# entrypoint.sh and dependencies
RUN set -ex; \
    \
    apk update && apk upgrade &&\
    apk add --no-cache \
        bash \
        rsync \
        supervisor \
        imagemagick \
        imagemagick-pdf \
        imagemagick-jpeg \
        imagemagick-raw \
        imagemagick-tiff \
        imagemagick-heic \
        imagemagick-webp \
        imagemagick-svg \
        ffmpeg \
        tzdata \
        unzip \
        p7zip \
        nginx \
        coreutils \
        # forward request and error logs to docker log collector
        && ln -sf /dev/stdout /var/log/nginx/access.log \
        && ln -sf /dev/stderr /var/log/nginx/error.log \
        && mkdir -p /run/nginx \
        && mkdir -p /var/log/supervisor && \
	cp /usr/share/zoneinfo/Asia/Shanghai /etc/localtime && \
	echo "Asia/Shanghai" > /etc/timezone

ADD conf/supervisord.conf /etc/supervisord.conf

# Copy our nginx config
RUN rm -Rf /etc/nginx/nginx.conf
ADD conf/nginx.conf /etc/nginx/nginx.conf

# nginx site conf
RUN mkdir -p /etc/nginx/sites-available/; \
    mkdir -p /etc/nginx/sites-enabled/; \
    mkdir -p /etc/nginx/ssl/; \
    mkdir /var/www/html/; \
    mkdir -p /docker-entrypoint-hooks.d/pre-installation \
             /docker-entrypoint-hooks.d/post-installation \
             /docker-entrypoint-hooks.d/pre-upgrade \
             /docker-entrypoint-hooks.d/post-upgrade \
             /docker-entrypoint-hooks.d/before-starting; \
    chown -R nginx:root /var/www; \
    chmod -R g=u /var/www

ADD conf/private-ssl.conf /etc/nginx/sites-available/private-ssl.conf
  
# install the PHP extensions we need
RUN set -ex; \
    \
    apk add --no-cache --virtual .build-deps \
        $PHPIZE_DEPS \
        autoconf \
        freetype-dev \
        icu-dev \
        libevent-dev \
        libjpeg-turbo-dev \
        libmcrypt-dev \
        libpng-dev \
        libmemcached-dev \
        libxml2-dev \
        libzip-dev \
        openldap-dev \
        pcre-dev \
        libwebp-dev \
        bzip2-dev \
        gettext-dev \
        curl-dev \
        imagemagick-dev \
    ; \
    \
    docker-php-ext-configure gd --with-freetype --with-jpeg --with-webp; \
    docker-php-ext-configure intl; \
    docker-php-ext-configure ldap; \
    docker-php-ext-install -j "$(nproc)" \
        bcmath \
        exif \
        ftp \
        gd \
        intl \
        ldap \
        opcache \
        pcntl \
        pdo_mysql \
        mysqli \
        zip \
        bz2 \
        gettext \
#        sockets \
    ; \
    \
# pecl will claim success even if one install fails, so we need to perform each install separately
    pecl install memcached-3.3.0 \
        --configureoptions 'enable-memcached-igbinary="yes"'; \
    pecl install redis-6.2.0 \
        --configureoptions 'enable-redis-igbinary="yes" enable-redis-zstd="yes" enable-redis-lz4="yes"'; \
    # pecl install mcrypt-1.0.5; \
    pecl install imagick-3.8.0; \
    # pecl install swoole-5.1.1; \
    \
    docker-php-ext-enable \
        memcached \
        redis \
        # mcrypt \
        imagick \
        # swoole \
    ; \
    rm -r /tmp/pear; \    
    \
    runDeps="$( \
        scanelf --needed --nobanner --format '%n#p' --recursive /usr/local/lib/php/extensions \
            | tr ',' '\n' \
            | sort -u \
            | awk 'system("[ -e /usr/local/lib/" $1 " ]") == 0 { next } { print "so:" $1 }' \
    )"; \
    apk add --no-network --virtual .kodbox-phpext-rundeps $runDeps; \
    apk del --no-network .build-deps

# tweak php-fpm config
ENV fpm_conf=/usr/local/etc/php-fpm.d/www.conf
ENV php_vars=/usr/local/etc/php/conf.d/docker-vars.ini
RUN { \
        echo 'opcache.enable=1'; \
        echo 'opcache.interned_strings_buffer=32'; \
        echo 'opcache.max_accelerated_files=10000'; \
        echo 'opcache.memory_consumption=128'; \
        echo 'opcache.save_comments=1'; \
        echo 'opcache.revalidate_freq=60'; \
        echo 'opcache.jit=1255'; \
        echo 'opcache.jit_buffer_size=128M'; \
    } > "${PHP_INI_DIR}/conf.d/opcache-recommended.ini"; \
    \
    echo "cgi.fix_pathinfo=1" > ${php_vars} &&\
    echo "upload_max_filesize = 512M"  >> ${php_vars} &&\
    echo "post_max_size = 512M"  >> ${php_vars} &&\
    echo "memory_limit = 512M"  >> ${php_vars} && \
    echo "max_execution_time = 3600"  >> ${php_vars} && \
    echo "max_input_time = 3600"  >> ${php_vars} && \
    sed -i \
        -e "s/;catch_workers_output\s*=\s*yes/catch_workers_output = yes/g" \
        -e "s/pm.max_children = 5/pm.max_children = 50/g" \
        -e "s/pm.start_servers = 2/pm.start_servers = 10/g" \
        -e "s/pm.min_spare_servers = 1/pm.min_spare_servers = 10/g" \
        -e "s/pm.max_spare_servers = 3/pm.max_spare_servers = 30/g" \
        -e "s/;pm.max_requests = 500/pm.max_requests = 500/g" \
        -e "s/user = www-data/user = nginx/g" \
        -e "s/group = www-data/group = nginx/g" \
        -e "s/;listen.mode = 0660/listen.mode = 0666/g" \
        -e "s/;listen.owner = www-data/listen.owner = nginx/g" \
        -e "s/;listen.group = www-data/listen.group = nginx/g" \
        -e "s/listen = 127.0.0.1:9000/listen = \/var\/run\/php-fpm.sock/g" \
        -e "s/^;clear_env = no$/clear_env = no/" \
        ${fpm_conf}

VOLUME /var/www/html

RUN set -ex; \
    curl -fsSL -o kodbox.zip \
		"https://api.kodcloud.com/?app/version&download=server.link"; \ 
    unzip kodbox.zip -d /usr/src/kodbox/; \
    curl -fsSL -o update.zip \
		"https://api.kodcloud.com/?app/version&download=server.linkUpdate"; \
    mv update.zip /usr/src/kodbox/; \
    sed -i "s/MyISAM/InnoDB/g" /usr/src/kodbox/app/controller/install/data/mysql.sql; \
    rm kodbox.zip

COPY entrypoint.sh /

EXPOSE 80 443

ENTRYPOINT ["/entrypoint.sh"]
CMD ["supervisord","-n","-c","/etc/supervisord.conf"]
