#!/bin/bash
################################################################################
# get-status.sh - Get the status of services for monitoring purposes.
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

# Set option defaults.
forceGeneration=false
unset serviceName
showAll=false
showDebugMessages=false
unset valueName
serviceAvailable=false

# Paths for external commands.
BASENAME_CMD="/bin/basename"
CAT_CMD="/bin/cat"
DIRNAME_CMD="/bin/dirname"
FIND_CMD="/usr/bin/find"
LS_CMD="/bin/ls"
READLINK_CMD="/bin/readlink"
SED_CMD="/bin/sed"
TOUCH_CMD="/bin/touch"

##############
# Main function.
function main ()
{
    setService
    if ! checkStatusFile; then
       generateStatusFile
    fi
    if ${showAll}; then
        ${CAT_CMD} ${statusFile}
    else
        getValue
    fi
}

##############
# Check and load service configuration.
function setService ()
{
    serviceAvailable=false

    for availableService in ${availableServiceList[@]}; do
        if [ "${availableService}" == "${serviceName}" ]; then
            serviceAvailable=true
            break
        fi
    done

    serviceConfPath="${serviceConfDir}/${serviceName}.${serviceConfSuff}"

    if ${serviceAvailable}; then
        source ${serviceConfPath}

        if [ -z "${statusGenerationCommand}" ]; then
            echo "Error: Missing status generation command." >&2
            exit 1
        fi

        statusFile="${statusFileDir}/${statusFileName:-sst.${serviceName}.status}"
        valuePattern="${valuePattern:-${defaultValuePattern}}"
        datePattern="${datePattern:-${defaultDatePattern}}"

        ${showDebugMessages} && echo "Info: Using the service \"${serviceName}\"."
        ${showDebugMessages} && echo "Info: Service description is \"${serviceDescription}\"."
        ${showDebugMessages} && echo "Info: Using the status file \"${statusFile}\"."
        ${showDebugMessages} && echo "Info: Using the status generation command \"${statusGenerationCommand}\"."
        if [[ ${valueName} ]]; then
            ${showDebugMessages} && echo "Info: Using the value name \"${valueName}\"."
            ${showDebugMessages} && echo "Info: Using the value pattern \"${valuePattern}\"."
        fi
        ${showDebugMessages} && echo "Info: Using the date pattern \"${datePattern}\"."

        # Replace placeholders.
        valuePattern=$(echo ${valuePattern} | ${SED_CMD} -e "s/%VALUE_NAME%/${valueName}/g" -e "s/%VALUE%/\\\(\.\*\\\)/g")
        datePattern=$(echo ${datePattern} | ${SED_CMD} -e "s/%VALUE_NAME%/${dateValueName}/g" -e "s/%VALUE%/${dateGenerationCommand}/g")
    else
        echo -e "Error: The service \"${serviceName}\" isn't supported.\n" >&2
        showAvailableServices
        exit 1
    fi
}

##############
# Check wheater the status file exists and is younger than update interval. 
function checkStatusFile ()
{
    if [ -f ${statusFile} ]; then
        ${showDebugMessages} && echo "Info: The status file exists."
        if [[ -r ${statusFile} && -w ${statusFile} ]]; then
            checkStatusFileAge=$(${FIND_CMD} ${statusFile} -mmin +${updateInterval} 2> /dev/null)
            statusCode=${?}
            if [ ${statusCode} -eq 0 ]; then
                ${showDebugMessages} && echo "Info: The status file age check was successful."
                if [ -z ${checkStatusFileAge} ]; then
                    ${showDebugMessages} && echo "Info: The status file is younger than ${updateInterval} min."
                    if ${forceGeneration}; then
                        ${showDebugMessages} && echo "Info: Force the generation / update of the status file."
                        return 1
                    else
                        return 0
                    fi
                else
                    ${showDebugMessages} && echo "Info: The status file is older than ${updateInterval} min."
                    return 1
                fi
            else
                ${showDebugMessages} && echo "Error: The status file age check wasn't successful. Status code: ${statusCode}" >&2
                exit 1
            fi
        else
            ${showDebugMessages} && echo "Error: The status file is not read or writable." >&2
            exit 1
        fi
    else
        ${showDebugMessages} && echo "Info: The status file doesn't exist yet."
        ${TOUCH_CMD} -c ${statusFile} 2> /dev/null
        statusCode=${?}
        if [ ${statusCode} -eq 0 ]; then
            ${showDebugMessages} && echo "Info: The status file can be created."
            return 1
        else
            ${showDebugMessages} && echo "Error: The status file cannot be created."
            exit 1
        fi
    fi
}

##############
# Generate the status file by using the status generation command. 
function generateStatusFile ()
{
    statusOutput=$(${statusGenerationCommand} 2> /dev/null)
    statusCode=${?}
    if [ ${statusCode} -eq 0 ]; then
        ${showDebugMessages} && echo "Info: The status generation command was successful."
        echo 2> /dev/null "${statusOutput}" > ${statusFile}
        statusCode=${?}
        if [ ${statusCode} -eq 0 ]; then
            ${showDebugMessages} && echo "Info: The status could be written down successfully."
            echo 2> /dev/null -e "${datePattern}" >> ${statusFile}
            statusCode=${?}
            if [ ${statusCode} -eq 0 ]; then
                ${showDebugMessages} && echo "Info: The date could be generated / updated successfully."
                ${showDebugMessages} && echo "Info: The status file could be generated / updated successfully."
            else
                ${showDebugMessages} && echo "Error: The date couldn't be generated / updated. Status code: ${statusCode}"
                exit 1
            fi
        else    
            ${showDebugMessages} && echo "Error: The status couldn't be written down. Status code: ${statusCode}"
            exit 1
        fi
    else
        ${showDebugMessages} && echo "Error: The status generation command failed. Status code: ${statusCode}" >&2
        exit 1
    fi
}

##############
# Get the value.
function getValue ()
{
    returnValue=$(${SED_CMD} -n "s/${valuePattern}/\1/p" ${statusFile} 2> /dev/null)
    statusCode=${?}
    if [ ${statusCode} -eq 0 ]; then
        if [ -z ${returnValue} ]; then
            ${showDebugMessages} && echo "Error: Value doesn't exist or is empty."
            exit 1
        else
            ${showDebugMessages} && echo "Info: The value could be looked up successfully."
            echo ${returnValue}
            exit 0
        fi
    else
        ${showDebugMessages} && echo "Error: The value lookup commando failed. Status code: ${statusCode}"
        exit 1
    fi
}

##############
# Show available services.
function showAvailableServices ()
{
    echo -e "List of available services:" >&2
    for availableService in ${availableServiceList[@]}; do
        while read line; do
            if [[ ${line} == serviceDescription=* ]]; then
                serviceDescription=$(echo ${line} | ${SED_CMD} -n 's/serviceDescription="\(.*\)"/\1/p')
                break
            fi
        done < "${serviceConfDir}/${availableService}.${serviceConfSuff}"
        echo -e "\t- ${availableService} (${serviceDescription})" >&2
    done
}

##############
# Show the help text.
function showHelp ()
{
    echo -e "Usage: $(${BASENAME_CMD} ${0}) [-d] [-f] -s <SERVICE> -v <VALUE> | -a\n" \
    "\t-d\t\tDebug mode\n" \
    "\t-f\t\tForce generation / update of the status\n" \
    "\t-h\t\tShow this help text\n" \
    "\t-s <SERVICE>\tThe service which should be used\n" \
    "\t-v <VALUE NAME>\tThe name of the value which should be returned\n" \
    "\t-a\t\tPrint the entire status file\n" >&2
   
    showAvailableServices
}

# Get options.
while getopts ':s:v:ahdf' option; do
    case "$option" in
        a)
            showAll=true
            ;;
        s)
            serviceName="${OPTARG}"
            ;;
        v)
            valueName="${OPTARG}"
            ;;
        h)
            showHelp
            exit 0
            ;;
        d)  
            showDebugMessages=true
            ;;
        f)
            forceGeneration=true
            ;;
        \?)
            echo -e "Error: Invalid option -$OPTARG.\n" >&2
            showHelp
            exit 1
            ;;
        :)
            echo -e "Error: Option -$OPTARG requires an argument.\n" >&2
            showHelp
            exit 1
            ;;
    esac
done

# Check for required options.
if [[ ${serviceName} ]] && ( [[ ${valueName} ]] || ${showAll} ); then
    # Set the path to the script file, used in the configuration.
    scriptFile=$(${READLINK_CMD} -f ${0})
    scriptPath=$(${DIRNAME_CMD} ${scriptFile})

    # Load the configuration.
    confFile="${scriptPath}/../../../etc/zabbix-helpers/get-status.conf"
    source ${confFile}
    statusCode=${?}                                                     
    if [ ${statusCode} -eq 0 ]; then
        ${showDebugMessages} && echo "Info: Configuration file loaded successfully."
    else
        ${showDebugMessages} && echo "Error: Couldn't load the configuration file. Status code: ${statusCode}" >&2
        exit 1
    fi
    
    # Get available services.
    serviceConfList=$(${LS_CMD} ${serviceConfDir}/*.${serviceConfSuff} 2> /dev/null)
    statusCode=${?}                                                     
    if [ ${statusCode} -eq 0 ]; then
        ${showDebugMessages} && echo "Info: Looked up available services successfully."
    else
        ${showDebugMessages} && echo "Error: There is no service available. Status code: ${statusCode}" >&2
        exit 1
    fi
    for serviceConf in ${serviceConfList}; do
        availableServiceList+=($(${BASENAME_CMD} -s.conf ${serviceConf}))
    done

    # Call the main function.
    main
else
    echo -e "Error: Missing option.\n" >&2
    # Call the showHelp function and exit.
    showHelp
    exit 1
fi
