#!/bin/bash
################################################################################
# dnsbl-check.sh - Check an IP address against a DNS based blacklist
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
# Zabbix user parameter helper script which checks a given IPv4 address against
# a given DNS based blacklist. It echos '1' (one) if the IP appears on the
# blacklist, '0' (zero) if the IP is not blacklistet, '2' (two) if the query
# timed out and '3' (three) on any other (dig) error. These values can be mapped
# easily within Zabbix.
#
# The script reverses the IP address octets, prepend them to the BL domain and
# queries the DNS resolver for an A record of this domain via the dig command.
# If the answer contains <RESULT> which defaults to 127.0.0.2, the IP is
# considered to be blacklisted.
# Note that the script currently does not perform any input validation, feel
# free to enhance it.
#
# Usage:
# dnsbl-check.sh <BLACKLIST> <IP> [<RESULT>]
# 
# Example:
# dnsbl-check.sh bl.example.com 192.0.2.123
# results in the following DNS query: "123.2.0.192.bl.example.com IN A"
################################################################################

DEBUG="${DEBUG:-false}"

DIG_CMD="/usr/bin/dig"


function main ()
{
    local blDomain="$1"
    local ipAddress="$2"
    local result="${3:-"127.0.0.2"}"

    if test -z "${blDomain}"; then
        echo "Missing blacklist domain (frist argument)" >&2
        return 1
    fi

    if test -z "${ipAddress}"; then
        echo "Missing IP address (second argument)" >&2
        return 1
    fi

    if test -z "${result}"; then
        echo "The expected result (optional, third argument) can't be empty" >&2
        return 1
    fi


    # Replace all dots with a whitespace, to produce word splitting and
    # assign each IP octet to an array element.
    local -a ipOctets=(${ipAddress//./ })

    local reverseIp="${ipOctets[3]}.${ipOctets[2]}.${ipOctets[1]}.${ipOctets[0]}"

    local digCommand
    digCommand="${DIG_CMD} -t A -q ${reverseIp}.${blDomain} +short +tries=2 +time=1"
    ${DEBUG} && echo "dig command: ${digCommand}"

    local answer
    answer="$( ${digCommand} > /dev/null 2>&1)"
    local digReturnCode=$?

    if ${DEBUG}; then
        echo "dig return code: ${digReturnCode}"
        echo "answer: '$answer'"
    fi

    if [ ${digReturnCode} -ne 0 ]; then
        case "${digReturnCode}" in
            1)
                ${DEBUG} && echo "Dig: Usage error"
                echo "3"
                ;;

            8)
                ${DEBUG} && echo "Dig: Couldn't open batch file"
                echo "3"
                ;;

            9)
                ${DEBUG} && echo "Dig: No reply from server"
                echo "2"
                ;;

            10)
                ${DEBUG} && echo "Dig: Internal error"
                echo "3"
                ;;

            *)
                ${DEBUG} && echo "Dig: Unknown error"
                echo "3"
                ;;
        esac

        # Terminate
        return $digReturnCode
    fi

    if [ "${answer}" == "${result}" ]; then
        ${DEBUG} && echo "IP is blacklisted"
        echo "1"
    else
        ${DEBUG} && echo "IP is not blacklisted"
        echo "0"
    fi

    return $digReturnCode
}

main "$1" "$2" "$3"
