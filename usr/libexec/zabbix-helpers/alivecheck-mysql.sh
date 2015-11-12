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
# 2 = Timeout reached
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

returnValue=0

# Main function
#
# main
function main ()
{
    dbWrite
    if dbRead > /dev/null && [ "$(dbRead)" ]; then
        returnValue=1
    fi
}

# Write to the database
#
# dbWrite
function dbWrite ()
{
    ${MYSQL_CMD} -u "${dbUser}" -h "${dbHost}" "${dbName}" --connect-timeout="${mysqlTimeout}" \
    -e "INSERT INTO \`${dbTable}\` (hostname,date) VALUES ('${hostname}','${date}')" \
    > /dev/null 2>&1
}

# Read from the database
#
# dbRead
function dbRead ()
{
    ${MYSQL_CMD} -u "${dbUser}" -h "${dbHost}" "${dbName}" --connect-timeout="${mysqlTimeout}" \
    -e "SELECT hostname,date FROM \`${dbTable}\` WHERE hostname='${hostname}' AND date='${date}'" \
    2> /dev/null
}

# Cleanup the database
#
# dbCleanup
function dbCleanup ()
{
    ${MYSQL_CMD} -u "${dbUser}" -h "${dbHost}" "${dbName}" --connect-timeout="${mysqlTimeout}" \
    -e "DELETE FROM \`${dbTable}\` WHERE hostname='${hostname}' AND date='${date}'" \
    > /dev/null 2>&1
}
trap "echo \${returnValue}; dbCleanup" EXIT

trap "returnValue=2; exit 1" SIGHUP

main
