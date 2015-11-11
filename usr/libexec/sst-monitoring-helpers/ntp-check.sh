#!/bin/bash
################################################################################
# ntp-check.sh - Checks if a NTP server is reachable and has an active peer
################################################################################
#
# Copyright (C) 2014 stepping stone GmbH
#                    Switzerland
#                    http://www.stepping-stone.ch
#                    support@stepping-stone.ch
#
# Authors:
#  Christian Affolter <christian.affolter@stepping-stone.ch>
#  
# Licensed under the EUPL, Version 1.1.
#
# You may not use this work except in compliance with the
# Licence.
# You may obtain a copy of the Licence at:
#
# http://www.osor.eu/eupl
#
# Unless required by applicable law or agreed to in
# writing, software distributed under the Licence is
# distributed on an "AS IS" basis,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either
# express or implied.
# See the Licence for the specific language governing
# permissions and limitations under the Licence.
#
# Description:
# Zabbix user parameter helper script which checks if a given NTP server is
# reachable and has an active system peer (pps.peer or sys.peer) for
# synchronization.
# It echos '0' (zero)  if the server is reachable but has no active system peer
# It echos '1' (one)   if the server is reachable and has an active system peer
# It echos '2' (two)   if the ntpq command return an non-zero exit code
# It echos '3' (three) if the NTP query request timed out.
# These values can be mapped easily within Zabbix.
#
# The script sends an 'associations' control message command to the given peer
# and checks for the condition of sys.peer or pps.peer. See ntpq(8) for more
# informations.
#
# Optionally, a request timeout can be passed in milliseconds, which defaults
# to 2'000 milliseconds. Don't set this too high as it may interfere with the
# Zabbix agent's processing timeout.
#
# Usage:
# ntp-check.sh <PEER-ADDRESS> [<TIMEOUT>]
# 
# Debug:
# DEBUG=true; ntp-check.sh <PEER-ADDRESS> [<TIMEOUT>]
# 
# Example:
# ntp-check.sh 0.pool.ntp.org
################################################################################

DEBUG="${DEBUG:-false}"

NTPQ_CMD="/usr/bin/ntpq"

if ! test -x "${NTPQ_CMD}"; then
    NTPQ_CMD="/usr/sbin/ntpq"

    if ! test -x "${NTPQ_CMD}"; then
        echo "Missing ntpq command: '${NTPQ_CMD}'" >&2
        exit 1
    fi
fi


function main ()
{
    local peer="$1"
    local timeout="${2:-"2000"}" # defaults to 2 seconds (2'000 milliseconds)

    if test -z "${peer}"; then
        echo "Missing NTP peer address (first argument)"
        return 1
    fi

    if [[ $timeout =~ ^[0-9]+ ]]; then
        # NTP retries each query once after a timeout. This results in an
        # actual timeout of TIMEOUT*2. Which is not what a user expects.
        # Therefor the user specified timeout gets dived in half to preserve the
        # original value.
        timeout=$(( $timeout / 2 ))
    else
        echo "Timeout (second argument) must be a positive integer"
        return 1
    fi


    local cmd="${NTPQ_CMD} -n -c 'timeout ${timeout}' -c 'associations' ${peer}"
    ${DEBUG} && echo "ntpq command: ${cmd}"

    local output
    output="$( export LC_MESSAGES=C; eval ${cmd} 2>&1 )"
    local returnCode=$?

    if ${DEBUG}; then
        echo "ntpq return code: ${returnCode}"
        echo -e "output:\n $output"
    fi

    if [ $returnCode -ne 0 ]; then
        ${DEBUG} && echo "ntpq command failed: $returnCode"
        echo "2" 
        return $returnCode

    elif [[ $output =~ "Request timed out" ]]; then
        ${DEBUG} && echo "Request timed out"
        echo "3"
        return $returnCode
    fi

    # search for a peer with a condition of pps.peer or sys.peer, which has been
    # declared as the system's active peer.
    local regex=" (pps|sys)\.peer "

    if [[ $output =~ $regex ]]; then
        ${DEBUG} && echo "Active system peer found"
        echo "1"
    else
        ${DEBUG} && echo "No active system peer found"
        echo "0"
    fi

    return $returnCode
}

main "$1" "$2"
