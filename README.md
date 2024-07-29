# 可道云docker镜像

[![buildx](https://github.com/KodCloud-dev/docker/actions/workflows/image.yml/badge.svg)](https://github.com/KodCloud-dev/docker/actions/workflows/image.yml)

## 1. 快速启动

```bash
docker run -d -p 80:80 kodcloud/kodbox
```

## 2. 实现数据持久化——创建数据目录并在启动时挂载

```bash
mkdir /data
docker run -d -p 80:80 -v /data:/var/www/html kodcloud/kodbox
```

## 3. 以https方式启动

- 使用已有ssl证书
  - 证书格式必须是 `fullchain.pem`  `privkey.pem`
  
    ```bash
    docker run -d -p 443:443  -v "你的证书目录":/etc/nginx/ssl --name kodbox kodcloud/kodbox
    ```

## 4. [使用docker-compose同时部署数据库（推荐）](https://github.com/KodCloud-dev/docker)

```bash
git clone https://github.com/KodCloud-dev/docker.git kodbox
cd ./kodbox/compose/
#需在db.env中设置数据库密码，还有yaml中的MYSQL_ROOT_PASSWORD
docker-compose up -d
```

```yaml
version: '3.5'

services:
  db:
    image: mariadb:10.6
    restart: always
    command: --transaction-isolation=READ-COMMITTED --log-bin=binlog --binlog-format=ROW
    volumes:
      - "./db:/var/lib/mysql"       #./db是数据库持久化目录，可以修改
    environment:
      - MYSQL_ROOT_PASSWORD=
      - MARIADB_AUTO_UPGRADE=1
      - MARIADB_DISABLE_UPGRADE_BACKUP=1
    env_file:
      - db.env
      
  app:
    image: kodcloud/kodbox
    restart: always
    ports:
      - 80:80                       #左边80是使用端口，可以修改
    volumes:
      - "./site:/var/www/html"      #./site是站点目录位置，可以修改
    environment:
      - MYSQL_HOST=db
      - REDIS_HOST=redis
    env_file:
      - db.env
    depends_on:
      - db
      - redis

  redis:
    image: redis:alpine
    restart: always
```

## 通过环境变量自动配置

kodbox容器支持通过环境变量自动配置。您可以在首次运行时预先配置安装页面上要求的所有内容。要启用自动配置，请通过以下环境变量设置数据库连接。

**MYSQL/MariaDB**:

- `MYSQL_DATABASE` 数据库名.
- `MYSQL_USER` 数据库用户.
- `MYSQL_PASSWORD` 数据库用户密码.
- `MYSQL_HOST` 数据库服务地址.
- `MYSQL_PORT` 数据库端口，默认3306

如果设置了任何值，则在首次运行时不会在安装页面中询问这些值。通过使用数据库类型的所有变量完成配置后，您可以通过设置管理员和密码（仅当您同时设置这两个值时才有效）来配置kodbox实例：

- `KODBOX_ADMIN_USER` 管理员用户名.
- `KODBOX_ADMIN_PASSWORD` 管理员密码.
- `RANDOM_ADMIN_PASSWORD` 值为·true·时生成随机密码，从日志查看.

**redis/memcached**:

- `REDIS_HOST` redis地址.
- `REDIS_PASSWORD` redis密码.

**uid/gid**:

- `PUID`代表站点运行用户nginx的用户uid
- `PGID`代表站点运行用户nginx的用户组gid

**PHP参数**

- `FPM_MAX` php-fpm最大进程数, 默认50
- `FPM_START` php-fpm初始进程数, 默认10
- `FPM_MIN_SPARE` php-fpm最小空闲进程数, 默认10
- `FPM_MAX_SPARE` php-fpm最大空闲进程数, 默认30

## 其他设置

- [自定义容器IP](https://docs.kodcloud.com/setup/docker/#ip)
- [挂载NFS卷](https://docs.kodcloud.com/setup/docker/#nfs)
- [挂载SMB卷](https://docs.kodcloud.com/setup/docker/#cifssmb)
