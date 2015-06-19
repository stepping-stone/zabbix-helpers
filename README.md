#Zabbix Helpers

##Overview
Zabbix monitoring helper scripts, mostly Zabbix Agent user parameters.

##Scripts

###get-status.sh

Script:   `/usr/libexec/zabbix-helpers/get-status.sh`
Config:   `/etc/zabbix-helpers/get-status.conf`
Services: `/etc/zabbix-helpers/get-status.d/*.conf`

####Services
#####mysql

Requirements:
* MySQL Client

Create a dedicated MySQL user for the Zabbix Agent and store the credentials in a MySQL option file:
```bash
# The MySQL user.
mysqlUser=zabbix
# The MySQL user password.
mysqlUserPass=
# The MySQL user host.
mysqlUserHost=localhost

# Create the MySQL user.
mysql -u root -p -e "GRANT PROCESS ON *.* TO '${mysqlUser}'@'${mysqlUserHost}' IDENTIFIED BY '${mysqlUserPass}'; FLUSH PRIVILEGES"

# Store the credentials.
cat << EOF > /var/lib/zabbix/home/.my.cnf
[client]
user=${mysqlUser}
password=${mysqlUserPass}
EOF
chown root:zabbix /var/lib/zabbix/home/.my.cnf
chmod 640 /var/lib/zabbix/home/.my.cnf
```

#####haproxy-info

Requirements:
* socat

#####haproxy-state

Requirements:
* socat

###mysqlcheck.php

Requirements:
* PHP

Script: `/usr/share/zabbix-helpers/mysqlcheck.php`
Config: `/etc/zabbix-helpers/mysqlcheck.conf`

1. Create the database and table:

```bash
CREATE DATABASE `mysqlcheck` CHARACTER SET utf8;

USE `mysqlcheck`;

CREATE TABLE IF NOT EXISTS `mysqlcheck`
        ( id  INT PRIMARY KEY NOT NULL AUTO_INCREMENT
        , fqdn  VARCHAR(128) NOT NULL
        , date  DATETIME NOT NULL
        );

GRANT SELECT, INSERT, UPDATE, DELETE ON `mysqlcheck`.`mysqlcheck` TO 'mysqlcheck'@'localhost' IDENTIFIED BY '<Password>';
```

2. Adjust the config file. 
