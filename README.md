#Zabbix Helpers
##Overview
Zabbix monitoring helper scripts.

##Scripts
###get-status.sh
Script: `/usr/libexec/zabbix-helpers/get-status.sh`

Config: `/etc/zabbix-helpers/get-status.conf`

Services: `/etc/zabbix-helpers/get-status.d/*.conf`

####Services
#####mysql
######mysql - Requirements
* MySQL Client
* MySQL user, database option file:
Create a dedicated MySQL user for the Zabbix Agent and store the credentials in a MySQL option file:
```bash
# The MySQL user.
mysqlUser=zabbix
# The MySQL user password.
mysqlUserPass=
# The MySQL user host.
mysqlUserHost="%"

# Create the MySQL user.
mysql -u root -p -e "GRANT PROCESS ON *.* TO '${mysqlUser}'@'${mysqlUserHost}' IDENTIFIED BY '${mysqlUserPass}'"

# Store the credentials.
cat << EOF > /var/lib/zabbix/home/.my.cnf
[client]
user=${mysqlUser}
password=${mysqlUserPass}
EOF
chown root:zabbix /var/lib/zabbix/home/.my.cnf
chmod 640 /var/lib/zabbix/home/.my.cnf
```

#####haproxy
######haproxy - Requirements
* socat

###alivecheck-mysql.sh
Script: `/usr/libexec/zabbix-helpers/alivecheck-mysql.sh`

Config: `/etc/zabbix-helpers/alivecheck-mysql.conf`

####alivecheck-mysql.sh - Requirements
* MySQL
* MySQL user, database and option file:
Create a dedicated MySQL user for the Zabbix Agent and store the credentials in a MySQL option file, create the database:
```bash
# The MySQL user.
mysqlUser="zabbix"
# The MySQL user password.
mysqlUserPass=
# The MySQL user host.
mysqlUserHost="%"

# Create the database and the user.
mysql -u root -p << EOF_SQL
CREATE DATABASE \`alivecheck\` CHARACTER SET utf8;
USE \`alivecheck\`;
CREATE TABLE IF NOT EXISTS \`alivecheck\`
        ( id  INT PRIMARY KEY NOT NULL AUTO_INCREMENT
        , hostname  VARCHAR(128) NOT NULL
        , date  DATETIME NOT NULL
        );
GRANT SELECT, INSERT, DELETE ON \`alivecheck\`.\`alivecheck\` TO \`${mysqlUser}\`@\`${mysqlUserHost}\` IDENTIFIED BY "${mysqlUserPass}"
EOF_SQL

# Store the credentials.
cat << EOF > /var/lib/zabbix/home/.my.cnf
[client]
user=${mysqlUser}
password=${mysqlUserPass}
EOF
chown root:zabbix /var/lib/zabbix/home/.my.cnf
chmod 640 /var/lib/zabbix/home/.my.cnf
```
###healthcheck-mysql.php
Script: `/usr/share/zabbix-helpers/healthcheck-mysql.php`

Config: `/etc/zabbix-helpers/healthcheck-mysql.conf`

####healthcheck-mysql.php - Requirements
* PHP
* MySQL
* Create the database and table:
```bash
# The MySQL user.
mysqlUser="healthcheck"
# The MySQL user password.
mysqlUserPass=
# The MySQL user host.
mysqlUserHost="%"

mysql -u root -p << EOF_SQL
CREATE DATABASE \`healthcheck\` CHARACTER SET utf8;
USE \`healthcheck\`;
CREATE TABLE IF NOT EXISTS \`healthcheck\`
        ( id  INT PRIMARY KEY NOT NULL AUTO_INCREMENT
        , hostname  VARCHAR(128) NOT NULL
        , date  DATETIME NOT NULL
        );
GRANT SELECT, INSERT, UPDATE, DELETE ON \`healthcheck\`.\`healthcheck\` TO \`${mysqlUser}\`@\`${mysqlUserHost}\` IDENTIFIED BY "${mysqlUserPass}";
EOF_SQL
```
* Adjust the config file.

####healthcheck-mysql.php - Usage
* Integrate the healthcheck into your Apache virtual host by adding the following to your config file (PHP must be enabled):
```apache
    Alias "/healthcheck" "/usr/share/zabbix-helpers/healthcheck-mysql.php"
    <Directory "/usr/share/zabbix-helpers">
        Require all granted
    </Directory>
```
You may want to restrict the access (replace the Require from above):
```apache
        Require ip <SomeIPs>
        ...
        Require local
```
