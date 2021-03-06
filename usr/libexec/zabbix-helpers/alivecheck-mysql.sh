#!/bin/bash
################################################################################
# alivecheck-mysql.sh - Check the availability of a MySQL service
################################################################################
#
# Copyright (C) 2015 - 2019 stepping stone GmbH
#                           Switzerland
#                           http://www.stepping-stone.ch
#                           support@stepping-stone.ch
#
# Authors:
#  Pascal Jufer <pascal.jufer@stepping-stone.ch>
#  Christian Affolter <christian.affolter@stepping-stone.ch>
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
# It echos '0' (zero)  if an unknown error occurred
# It echos '1' (one)   if MySQL is alive and working
# It echos '2' (two(   if the database write (INSERT) failed
# It echos '3' (three) if the database read (SELECT) failed
# It echos '4' (four)  if the database cleanup (DELETE) failed
# These values can be mapped easily within Zabbix.
#
# Usage:
# # normal operation
# alivecheck-mysql.sh
# 
# # enable debug mode
# DEBUG=true alivecheck-mysql.sh
################################################################################

# Root directory of the script
ROOT_DIR="$(dirname $(readlink -f ${0}))/../../.."

# Load the configuration file
source "${ROOT_DIR}/etc/zabbix-helpers/alivecheck-mysql.conf"

DATE_CMD="/bin/date"
HOSTNAME_CMD="/bin/hostname"
MYSQL_CMD="/usr/bin/mysql"
TIMEOUT_CMD="/usr/bin/timeout"
MKTEMP_CMD="/usr/bin/mktemp"

TIMESTAMP="$( ${DATE_CMD} +"%F %H:%M:%S" )"
MY_HOSTNAME="$( ${HOSTNAME_CMD} )"


# Main function
#
# main
function main ()
{
    prepareMysqlClient

    dbWrite
    dbRead
    dbCleanup

    debug "MySQL is alive"
    echo "1"
    exit 0
}

# Prepare options for the mysql client
#
# prepareMysqlClient
function prepareMysqlClient ()
{
    # Do not enable any MySQL client SSL/TLS options by default
    mysqlSslOpts=""

    # Enable SSL/TLS options if requested
    if [[ "$dbSsl" = true ]]; then
        debug "Enabling secure connections"

        # Lookup version of MySQL client
        local mysqlClientVersion="$( ${MYSQL_CMD} --version | awk '{ print $5 }' | awk -F\, '{ print $1 }' )"
        debug "Detected MySQL client version: ${mysqlClientVersion}"

        # Use --ssl-mode from within version 5.7 (only Oracle MySQL, not MariaDB)
        if [[ ! "$mysqlClientVersion" =~ 'MariaDB' ]] && [[ $( printf "5.7\n${mysqlClientVersion}" | sort -V | head -n1 ) == "5.7" ]]; then
            if [[ "$dbSslVerifyIdentity" = true ]]; then
                mysqlSslOpts="--ssl-mode=VERIFY_IDENTITY --ssl-ca="${dbSslCaCert}""
            else
                mysqlSslOpts="--ssl-mode=REQUIRED --ssl-ca="${dbSslCaCert}""
            fi
        # Otherwise use --ssl
        else
            mysqlSslOpts="--ssl --ssl-ca="${dbSslCaCert}""
            if [[ "$dbSslVerifyIdentity" = true ]]; then
                mysqlSslOpts+=" --ssl-verify-server-cert"
            fi
        fi
    fi
}


# Echos the last database client output
#
# dbGetOutput
function dbGetOutput ()
{
    echo "$_DB_STDOUT"
}


# Echos the last database client error
#
# dbGetError
function dbGetError ()
{
    echo "$_DB_STDERR"
}


# Executes a query on the the database server
#
# dbExecute query
function dbExecute ()
{
   
    local query="$1"

    # MySQL client command with connection and command timeout 
    # The user credentials are stored within ~/.my.cnf
    local cmd="${TIMEOUT_CMD} --signal KILL ${mysqlCmdTimeout}s
                   ${MYSQL_CMD} --host="${dbHost}"
                                --database="${dbName}"
                                --connect-timeout="${mysqlConTimeout}"
                                --batch
                                --silent
                                ${mysqlSslOpts}"
    
    local tmpStdErrFile=$( ${MKTEMP_CMD} )
    _DB_STDOUT="$( ${cmd} --execute="${query}" 2>"${tmpStdErrFile}" )"
    local returnCode=$?
    _DB_STDERR=$( <"${tmpStdErrFile}" )
    rm "${tmpStdErrFile}"

    debug "MySQL command:     ${cmd}"
    debug "MySQL query:       ${query}"
    debug "MySQL return code: ${returnCode}"
    debug "MySQL output:      ${_DB_STDOUT}"
    debug "MySQL error:       ${_DB_STDERR}"

    return "$returnCode"
}

# Echo a message if debug mode has been enabled
#
# debug message
function debug ()
{
    if [[ "$DEBUG" = true ]]; then
        echo -e "$1"
    fi
}

# Exit with an error code
#
# error value message
function error ()
{
    echo "$1"
    debug "ERROR: $2" >&2
    exit 1
}

# Write to the database
#
# dbWrite
function dbWrite ()
{
    local query="INSERT INTO ${dbTable} (hostname,date)
                 VALUES ('${MY_HOSTNAME}', '${TIMESTAMP}');"

    debug "Executing dbWrite"
    dbExecute "$query" || error "2" "dbWrite failed: $(dbGetError)"
}

# Read from the database
#
# dbRead
function dbRead ()
{
    local query="SELECT COUNT(*) FROM ${dbTable}
                 WHERE hostname='${MY_HOSTNAME}' AND date='${TIMESTAMP}'"

    debug "Executing dbRead"
    dbExecute "$query" || error "3" "dbRead failed: $(dbGetError)"

    if ! [[ $(dbGetOutput) =~ ^[0-9]+$ ]]; then
        error "3" "dbRead failed: Missing previously inserted record. MySQL output: $(dbGetOutput)"
    fi
}

# Cleanup the database
#
# dbCleanup
function dbCleanup ()
{
    local doNotExitOnError="$1"

    # Note, that all entries from this host will be deleted, instead of
    # only the exact host AND date entry. This automatically cleans-up old
    # stall entries.
    local query="DELETE FROM ${dbTable} WHERE hostname='${MY_HOSTNAME}'"

    debug "Executing dbCleanup"
    if [[ "$doNotExitOnError" = true ]]; then
        dbExecute "$query" || debug "dbCleanup failed: $(dbGetError)"
    else
        dbExecute "$query" || error "4" "dbCleanup failed: $(dbGetError)"
    fi
}


# Cleanup DB on HUP, INT or TERM signals and exit with an unknown error (0)
trap "dbCleanup 'true'; echo 0; exit 1" SIGHUP SIGINT SIGTERM

main
