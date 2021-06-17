# 1.快速启动
```
docker run -d -p 80:80 kodcloud/kodbox
```
# 2.实现数据持久化——创建数据目录并在启动时挂载
```
mkdir /data
docker run -d -p 80:80 -v /data:/var/www/html kodcloud/kodbox
```
# 3.以https方式启动
 
-  使用已有ssl证书
    - 证书格式必须是 fullchain.pem  privkey.pem
        ```
        docker run -d -p 443:443  -v "你的证书目录":/etc/nginx/ssl --name kodbox kodcloud/kodbox
        ```

# 4.[使用docker-compose同时部署数据库（推荐）](https://github.com/KodCloud-dev/docker)
```
git clone https://github.com/KodCloud-dev/docker.git kodbox
cd ./kodbox/compose/
修改docker-compose.yaml，设置数据库root密码（MYSQL_ROOT_PASSWORD=密码）
docker-compose up -d
```
- 把环境变量都写在TXT文件中
- 如果修改数据库名称(MYSQL_DATABASE)，需要同时修改./mysql-init-files/kodbox.sql 首行“use 数据库名称”

```
version: "3.5"

services:
  db:
    image: mariadb:10.5.5
    command: --transaction-isolation=READ-COMMITTED --binlog-format=ROW
    volumes:
      - "./db:/var/lib/mysql"
      - "./mysql-init-files:/docker-entrypoint-initdb.d"
    environment:
      - "TZ=Asia/Shanghai"
      - "MYSQL_ROOT_PASSWORD="
      - "MYSQL_DATABASE_FILE=/run/secrets/mysql_db"
      - "MYSQL_USER_FILE=/run/secrets/mysql_user"
      - "MYSQL_PASSWORD_FILE=/run/secrets/mysql_password"
    restart: always
    secrets:
      - mysql_db
      - mysql_password
      - mysql_user

  app:
    image: kodcloud/kodbox
    ports:
      - 80:80
    links:
      - db
      - redis
    volumes:
      - "./data:/var/www/html"
    environment:
      - "MYSQL_SERVER=db"
      - "MYSQL_DATABASE_FILE=/run/secrets/mysql_db"
      - "MYSQL_USER_FILE=/run/secrets/mysql_user"
      - "MYSQL_PASSWORD_FILE=/run/secrets/mysql_password"
      - "SESSION_HOST=redis"
    restart: always
    secrets:
      - mysql_db
      - mysql_password
      - mysql_user

  redis:
    image: redis:alpine3.12
    environment:
      - "TZ=Asia/Shanghai"
    restart: always

secrets:
  mysql_db:
    file: "./mysql_db.txt"
  mysql_password:
    file: "./mysql_password.txt"
  mysql_user:
    file: "./mysql_user.txt"

```
## 通过环境变量自动配置

kodbox容器支持通过环境变量自动配置。您可以在首次运行时预先配置安装页面上要求的所有内容。要启用自动配置，请通过以下环境变量设置数据库连接。

**MYSQL/MariaDB**:

-	`MYSQL_DATABASE` 数据库名.
-	`MYSQL_USER` 数据库用户.
-	`MYSQL_PASSWORD` 数据库用户密码.
-	`MYSQL_SERVER` 数据库服务地址.
-   `MYSQL_PORT` 数据库端口，默认3306

如果设置了任何值，则在首次运行时不会在安装页面中询问这些值。通过使用数据库类型的所有变量完成配置后，您可以通过设置管理员和密码（仅当您同时设置这两个值时才有效）来配置kodbox实例：

-	`KODBOX_ADMIN_USER` 管理员用户名，可以不设置，访问网页时自己填.
-	`KODBOX_ADMIN_PASSWORD` 管理员密码，可以不设置，访问网页时自己填.

**redis/memcached**:

-	`SESSION_TYPE` 缓存类型，默认redis，仅当配置`SESSION_HOST`时生效.
-	`SESSION_HOST` 缓存地址.
-	`SESSION_PORT` 缓存端口，默认6379，仅当配置`SESSION_HOST`时生效.
