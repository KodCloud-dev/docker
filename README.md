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
    image: mariadb:lts
    command: --transaction-isolation=READ-COMMITTED
    restart: always
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

**站点自动更新**:

- `KODBOX_AUTO_UPDATE` 默认 `1`，镜像内 kodbox 版本较新时自动覆盖升级已有站点。
- 设置为 `0` 时，保留已有站点版本和文件，跳过镜像升级覆盖、升级赋权和 `pre-upgrade`/`post-upgrade` 钩子；`before-starting` 钩子仍执行。
- 首次部署（`/var/www/html` 为空，忽略初始化锁文件）仍正常初始化；已有子目录站点（例如 NFS 挂载到 `/var/www/html/kodbox`）也会保留，不要求根目录存在 `config/version.php`。此开关只控制容器启动时的镜像覆盖，不影响 kodbox 后台手动更新；PHP、Nginx 等运行环境仍随新镜像更新。
- `KODBOX_UPDATE=1` 也遵守此开关，不会强制覆盖已有站点。

在 Compose 的 `app` 服务中配置，重建容器后生效：

```yaml
environment:
  - KODBOX_AUTO_UPDATE=0
```

**PHP参数**

- `FPM_MAX` php-fpm最大进程数, 默认50
- `FPM_START` php-fpm初始进程数, 默认10
- `FPM_MIN_SPARE` php-fpm最小空闲进程数, 默认10
- `FPM_MAX_SPARE` php-fpm最大空闲进程数, 默认30

## 其他设置

- [自定义容器IP](https://docs.kodcloud.com/setup/docker/#ip)
- [挂载NFS卷](https://docs.kodcloud.com/setup/docker/#nfs)
- [挂载SMB卷](https://docs.kodcloud.com/setup/docker/#cifssmb)

### PHP 安全更新与站点权限

镜像基于 `php:8.5.12-fpm-alpine3.24`，包含 CVE-2026-109618 和
CVE-2026-109619 的修复。修改 Dockerfile 后需要重新构建并使用新镜像重建应用容器；
仅重启旧容器或更新宿主机 PHP 不会生效。Compose 中的 `image` 也需要指向新构建的镜像。

首次安装或镜像内的 kodbox 新版本覆盖站点后，入口脚本会在安装程序或升级后钩子运行前，
将 `/var/www/html`（包含持久化站点文件）的所有者修复为 `nginx:nginx`，
兼容 `PUID`/`PGID`，并确保所有者可读写文件、可进入目录。不会沿符号链接修改站点外的目标。
以非 root 用户运行时不更改所有者，挂载目录需要预先授予该用户所有权。
