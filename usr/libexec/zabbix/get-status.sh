#!/bin/bash
################################################################################
# get-status.sh - Handling and returning the status of several services for 
#                 monitoring purposes.
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
# This file is part of the stoney cloud.
#
# stoney cloud is free software: you can redistribute it and/or
# modify it under the terms of the GNU Affero General Public 
# License as published  by the Free Software Foundation, version
# 3 of the License.
#
# stoney cloud is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU Affero General Public License for more details.
#
# You should have received a copy of the GNU Affero General Public
# License  along with stoney cloud.
# If not, see <http://www.gnu.org/licenses/>.
#
################################################################################

DEBUG="${DEBUG:-false}"


# Space separated list of all available services.
availableServices='mysql'
# The status file directory.
statusFileDir=/var/cache/zabbix
# The update interval (in minutes).
updateInterval="5"
# The date value name.
dateValueName="LastSuccessfulUpdate"
# The date generation command.
dateGenerationCommand="$(date +%s)"


##############
# Main function.
function main ()
{
    checkService
    setService
    if ! checkFile; then
       generateStatus
    fi
    getValue
}

##############
# Check wheater the selected service is available.
function checkService ()
{
    for services in $availableServices; do
        if [[ ${services} = ${service} ]]; then
            serviceAvailable=true
        fi
    done

    if ! [[ ${serviceAvailable} ]]; then
        echo -e "Error: The service \"${service}\" isn't supported.\n" >&2
        showAvailableServices
        exit 1
    fi

    ${DEBUG} && echo -e "Info: Using the service \"${service}\"."
}

##############
# Set service configuration based on the argument.
#
# Set these variables for each service:
#  $statusFileName - The name of the status file.
#  $statusGenerationCommand - The command used to generate the status.
#  $valuePattern - The pattern used to get the value.
#  $datePattern - The pattern in which the date should be saved.
function setService ()
{
    case $service in
        mysql)
            statusFileName="sst.mysql.status"
            statusGenerationCommand="/usr/bin/mysql -N -B --connect-timeout=3 -e 'SHOW STATUS;'"
            valuePattern="^${value}\t\K.*"
            datePattern="${dateValueName}\t${dateGenerationCommand}"
            ;;
    esac

    statusFile="${statusFileDir}/${statusFileName}"

    ${DEBUG} && echo -e "Info: Using the status file \"${statusFile}\"."
    ${DEBUG} && echo -e "Info: Using the status generation command \"${statusGenerationCommand}\"."
    ${DEBUG} && echo -e "Info: Using the value pattern \"${valuePattern}\"."
    ${DEBUG} && echo -e "Info: Using the date pattern \"${datePattern}\"."
}

##############
# Check wheater the status file exists and is younger than update interval. 
function checkFile ()
{
    if [[ ${FORCE} ]]; then
        ${DEBUG} && echo -e "Info: Force the generation / update of the status."
        return 1
    elif [[ -f ${statusFile} ]]; then
        ${DEBUG} && echo -e "Info: The status file exists."

        if test $(find ${statusFile} -mmin +${updateInterval} 2> /dev/null); then
            ${DEBUG} && echo -e "Info: The status file is older than ${updateInterval} min."
            return 1
        else
            ${DEBUG} && echo -e "Info: The status file is younger than ${updateInterval} min."
            return 0
        fi
    else
        ${DEBUG} && echo -e "Info: The status file doesn't exist yet."
        return 1
    fi
}

##############
# Generate the status by using the status generation command. 
function generateStatus ()
{
    if touch ${statusFile} 2> /dev/null; then
        ${DEBUG} && echo -e "Info: The status file is accessible."
        ${DEBUG} && echo -e "Info: The status is going to be generated / updated."

        if eval ${statusGenerationCommand} > ${statusFile} 2> /dev/null; then
                ${DEBUG} && echo -e "Info: The status could be generated / updated successfully."
            if echo -e ${datePattern} >> ${statusFile}; then
                ${DEBUG} && echo -e "Info: The date could be generated / updated successfully."
            else
                ${DEBUG} && echo -e "Error: The date couldn't be generated / updated."
            fi
        else
            ${DEBUG} && echo -e "Error: The status couldn't be generated / updated."
        fi
    else
        ${DEBUG} && echo -e "Error: The status file is not accessible."
    fi
}

##############
# Get the value based on the argument. 
function getValue ()
{
    if grep -oP ${valuePattern} ${statusFile} 2> /dev/null; then
        ${DEBUG} && echo -e "Info: The value could be looked up successfully."
    else
        ${DEBUG} && echo -e "Error: The value couldn't be looked up."
        exit 1
    fi
}

##############
# Show available services
function showAvailableServices ()
{
    echo -e "List of available services:" >&2
    for services in $availableServices; do
        echo -e "\t- ${services}" >&2
    done
}

##############
# Show the help text.
function showHelp ()
{
    echo -e "Usage: $(basename $0) [-d] [-f] -s <SERVICE> -v <VALUE>\n" \
    "\t-d\t\tDebug mode\n" \
    "\t-f\t\tForce generation / update of the status\n" \
    "\t-h\t\tShow this help text\n" \
    "\t-s <SERVICE>\tThe service which should be used\n" \
    "\t-v <VALUE>\tThe value which should be returned\n" >&2
   
    showAvailableServices
}

while getopts ':s:v:hdf' option; do
    case "$option" in
        s)
            service="${OPTARG}"
            ;;
        v)
            value="${OPTARG}"
            ;;
        h)
            showHelp
            exit 0
            ;;
        d)  
            DEBUG=true
            ;;
        f)
            FORCE=true
            ;;
        \?)
            echo "Error: Invalid option -$OPTARG" >&2
            exit 1
            ;;
        :)
            echo "Error: Option -$OPTARG requires an argument." >&2
            exit 1
            ;;
    esac
done

if [[ ${service} ]] && [[ ${value} ]]; then
    main
else
    showHelp
    exit 1
fi
