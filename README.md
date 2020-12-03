# 1.快速启动
```
docker run -d -p 80:80 kodcloud/kodbox:v1.14
```
# 2.实现数据持久化——创建数据目录并在启动时挂载
```
mkdir /data
docker run -d -p 80:80 -v /data:/var/www/html kodcloud/kodbox:v1.14
```
# 3.以https方式启动

-  使用 LetsEncrypt 免费ssl证书
    - 80:80 不能省略
        ```
        docker run -d -p 80:80 -p 443:443  -e DOMAIN="你的域名" -e EMAIL="你的邮箱" --name kodbox kodcloud/kodbox:v1.14
        ```
    - 生成证书并配置nginx的https
        ```
        docker exec -it kodbox /usr/bin/letsencrypt-setup
        ```
    - 更新证书
        ```
        docker exec -it kodbox /usr/bin/letsencrypt-renew
        ```
-  使用已有ssl证书
    - 证书格式必须是 fullchain.pem  privkey.pem
        ```
        docker run -d -p 443:443  -v "你的证书目录":/etc/nginx/ssl --name kodbox kodcloud/kodbox:vv1.14
        ```

# 4.[使用docker-compose同时部署数据库（推荐）](https://github.com/KodCloud-dev/docker)
```
git clone https://github.com/KodCloud-dev/docker.git kodbox
cd ./kodbox/compose/
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
      - "MYSQL_ALLOW_EMPTY_PASSWORD=yes"
      - "MYSQL_DATABASE_FILE=/run/secrets/mysql_db"
      - "MYSQL_USER_FILE=/run/secrets/mysql_user"
      - "MYSQL_PASSWORD_FILE=/run/secrets/mysql_password"
    secrets:
      - mysql_db
      - mysql_password
      - mysql_user

  app:
    image: kodcloud/kodbox:v1.14
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