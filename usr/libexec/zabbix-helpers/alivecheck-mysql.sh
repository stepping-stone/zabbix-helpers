#!/bin/bash
################################################################################
# alivecheck-mysql.sh - Check the availability of a MySQL service
################################################################################
#
# Copyright (C) 2015 stepping stone GmbH
#                    Switzerland
#                    http://www.stepping-stone.ch
#                    support@stepping-stone.ch
#
# Authors:
#  Pascal Jufer <pascal.jufer@stepping-stone.ch>
#
# This program is free software: you can redistribute it and/or
# modify it under the terms of the GNU Affero General Public 
# License as published  by the Free Software Foundation, version
# 3 of the License.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU Affero General Public License for more details.
#
# You should have received a copy of the GNU Affero General Public
# License  along with this program.
# If not, see <http://www.gnu.org/licenses/>.
#
#
# Description:
# Check the availability of a MySQL service by writing and reading
# to resp. from a database.
# Return values:
# 0 = Service is down
# 1 = Service is up
#
# Usage:
# alivecheck-mysql.sh
################################################################################

# Root directory of the script
ROOT_DIR="$(dirname $(readlink -f ${0}))/../../.."

# Load the configuration file
source "${ROOT_DIR}/etc/zabbix-helpers/alivecheck-mysql.conf"

DATE_CMD="/bin/date"
HOSTNAME_CMD="/bin/hostname"
MYSQL_CMD="/usr/bin/mysql"

date=$(${DATE_CMD} +"%Y%m%d%H%M%S")
hostname=$(${HOSTNAME_CMD})

# Main function
#
# main
function main ()
{
    dbWrite
    if dbRead > /dev/null && [ "$(dbRead)" ]; then
        echo "1"
    else
        echo "0"
    fi
    dbCleanup
}

# Write to the database
#
# dbWrite
function dbWrite ()
{
    ${MYSQL_CMD} -u ${dbUser} -p ${dbName} << EOF_SQL > /dev/null 2>&1
INSERT INTO \`${dbTable}\` (hostname, date) VALUES ("${hostname}", "${date}")
EOF_SQL
}

# Read from the database
#
# dbRead
function dbRead ()
{
    ${MYSQL_CMD} -u ${dbUser} -p ${dbName} << EOF_SQL 2> /dev/null
SELECT hostname, date FROM \`${dbTable}\` WHERE hostname="${hostname}" AND date="${date}"
EOF_SQL
}

# Cleanup the database
#
# dbCleanup
function dbCleanup ()
{
    ${MYSQL_CMD} -u ${dbUser} -p ${dbName} << EOF_SQL 2> /dev/null 2>&1
DELETE FROM \`${dbTable}\` WHERE hostname="${hostname}" AND date="${date}"
EOF_SQL
}

main
