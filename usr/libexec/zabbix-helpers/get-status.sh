#!/bin/bash
################################################################################
# get-status.sh - Get the status of services for monitoring purposes.
################################################################################
#
# Copyright (C) 2019 stepping stone GmbH
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
# This script retrieves the status of multiple services, caches them for a
# certain period and returns the selected value.
#
# Usage:
# get-status.sh [-d] [-f] -s <SERVICE> [-o <OPTIONS>] -v <VALUE NAME> | -a
#
# Example:
# get-status.sh -s mysql-status -v Max_used_connections
################################################################################

##############
# Load all necessary functions.
function main ()
{
    # Call the initializeScript function.
    initializeScript
    # Call the getOptions function and pass the options.
    getOptions "${@}"
    # Call the setService function.
    setService
    # If the status file must be generated or updated, call the generateStatusFile function.
    if ! checkStatusFile; then
       generateStatusFile "${serviceOptions}"
    fi
    # Call the getValue function.
    getValue
    # Exit with the global status code.
    exit "${globalStatusCode}"
}

##############
# Initialize the script.
function initializeScript ()
{
    # Set option defaults.
    globalStatusCode=0
    showDebugMessages=false

    # Paths for external commands.
    BASENAME_CMD="/bin/basename"
    BASH_CMD="/bin/bash"
    CAT_CMD="/bin/cat"
    COLUMN_CMD="/usr/bin/column"
    DIRNAME_CMD="/bin/dirname"
    FIND_CMD="/usr/bin/find"
    GREP_CMD="/bin/grep"
    HEAD_CMD="/bin/head"
    LS_CMD="/bin/ls"
    READLINK_CMD="/bin/readlink"
    SED_CMD="/bin/sed"
    TAIL_CMD="/bin/tail"
    TIMEOUT_CMD="/usr/bin/timeout"
    TOUCH_CMD="/bin/touch"

    # Set the path to the script file. Used in the configuration files.
    scriptFile=$(${READLINK_CMD} -f ${0})
    scriptPath=$(${DIRNAME_CMD} ${scriptFile})

    # Load the configuration.
    globalConfFile="${scriptPath}/../../../etc/zabbix-helpers/get-status.conf"
    source "${globalConfFile}"
    # Check whether the configuration could be loaded successfully.
    sourceGlobalConfFileStatusCode=${?}
    if [ ${sourceGlobalConfFileStatusCode} -ne 0 ]; then
        echo "Error: Couldn't load the configuration file. Status code: ${sourceGlobalConfFileStatusCode}" >&2
        exit 1
    fi
    ${showDebugMessages} && echo "Info: Configuration file loaded successfully."

    # Get available services.
    serviceConfList=$(${LS_CMD} ${serviceConfDir}/*.${serviceConfSuff} 2> /dev/null)
    serviceConfListStatusCode=${?}
    if [ ${serviceConfListStatusCode} -ne 0 ]; then
        echo "Error: There is no service available. Status code: ${serviceConfListStatusCode}" >&2
        exit 1
    fi
    ${showDebugMessages} && echo "Info: Looked up available services successfully."
    for serviceConf in "${serviceConfList}"; do
        availableServiceList+=($(${BASENAME_CMD} -s.conf ${serviceConf}))
    done
}

##############
# Get the options and check them.
function getOptions ()
{
    forceGeneration=false
    showAll=false
    serviceOptionsRequired=false
    unset valueName
    unset serviceName

    # Get the options.
    while getopts ':s:o:v:ahdf' option; do
        case "${option}" in
            a)
                showAll=true
                ;;
            s)
                serviceName="${OPTARG}"
                ;;
            v)
                valueName="${OPTARG}"
                ;;
            o)
                serviceOptions="${OPTARG}"
                ;;
            h)
                showHelp
                ;;
            d)
                showDebugMessages=true
                ;;
            f)
                forceGeneration=true
                ;;
            \?)
                echo -e "Error: Invalid option -${OPTARG}.\n" >&2
                showHelp "error"
                ;;
            :)
                echo -e "Error: Option -${OPTARG} requires an argument.\n" >&2
                showHelp "error"
                ;;
        esac
    done

    # Check for required options.
    if [[ ${serviceName} ]] && ( [[ ${valueName} ]] || ${showAll} ) && ! ( [[ ${valueName} ]] && ${showAll} ); then
        ${showDebugMessages} && echo "Info: All required options are set."
    else
        echo -e "Error: Missing or wrongly used option(s).\n" >&2
        showHelp "error"
    fi
}

##############
# Check and load service configuration.
function setService ()
{
    # Search for the selected service in the available service list.
    serviceAvailable=false
    for availableService in ${availableServiceList[@]}; do
        if [ "${availableService}" == "${serviceName}" ]; then
            serviceAvailable=true
            break
        fi
    done
    # Check whether the selected service is available.
    if ! ${serviceAvailable}; then
        echo -e "Error: The service \"${serviceName}\" isn't supported.\n" >&2
        showAvailableServices "error"
    fi

    # Build the service configuration path out of the selected service.
    serviceConfFile="${serviceConfDir}/${serviceName}.${serviceConfSuff}"

    # Load the service configuration.
    source "${serviceConfFile}"
    # Check whether the configuration could be loaded successfully.
    sourceServiceConfFileStatusCode=${?}
    if [ ${sourceServiceConfFileStatusCode} -ne 0 ]; then
        echo "Error: Couldn't load the configuration file. Status code: ${sourceServiceConfFileStatusCode}" >&2
        exit 1
    fi
    ${showDebugMessages} && echo "Info: Service configuration file loaded successfully."

    if ${serviceOptionsRequired}; then
        ${showDebugMessages} && echo "Info: Service requires additional options."
        if ! [ "${serviceOptions}" ]; then
            echo -e "Error: Services requires additional options, but no options has been specified.\n" >&2
            showHelp "error"
        fi
    fi

    # Check whether the status generation command is defined.
    if [ -z "${statusGenerationCommand}" ]; then
        echo "Error: Missing status generation command in configuration file ${serviceConfFile}." >&2
        exit 1
    fi

    # Define the values by using the values from the configuration or setting a default.
    if ! [ "${serviceOptions}" ]; then
        statusFile="${statusFileDir}/${statusFileName:-sst.${serviceName}.zabbix}"
    else
        statusFile="${statusFileDir}/${statusFileName:-sst.${serviceName}-${serviceOptions}-.zabbix}"
    fi
    valuePattern="${valuePattern:-${defaultValuePattern}}"
    datePattern="${datePattern:-${defaultDatePattern}}"

    # Print out some informational debug messages.
    ${showDebugMessages} && echo "Info: Using the service \"${serviceName}\"."
    if [[ ${submoduleName} ]]; then
        ${showDebugMessages} && echo "Info: Using the submodule \"${submoduleName}\"."
    fi
    ${showDebugMessages} && echo "Info: Service description is \"${serviceDescription}\"."
    ${showDebugMessages} && echo "Info: Using the status file \"${statusFile}\"."
    ${showDebugMessages} && echo "Info: Using the status generation command \"${statusGenerationCommand}\"."
    if [[ ${valueName} ]]; then
        ${showDebugMessages} && echo "Info: Using the value name \"${valueName}\"."
        ${showDebugMessages} && echo "Info: Using the value pattern \"${valuePattern}\"."
    fi
    ${showDebugMessages} && echo "Info: Using the date pattern \"${datePattern}\"."

    # Substitute the placeholders.
    sedValuePattern=$(echo ${valuePattern} | ${SED_CMD} -e "s/%VALUE_NAME%/${valueName}/g" -e "s/%VALUE%/\\\(\.\*\\\)/g")
    grepValuePattern=$(echo ${valuePattern} | ${SED_CMD} -e "s/%VALUE_NAME%/${valueName}/g" -e "s/%VALUE%/\.\*/g")
    datePattern=$(echo ${datePattern} | ${SED_CMD} -e "s/%VALUE_NAME%/${dateValueName}/g" -e "s/%VALUE%/${dateGenerationCommand}/g")
}

##############
# Check whether the status file exists and is younger than update interval.
function checkStatusFile ()
{
    statusFileOk=false

    # Check whether the status file exists.
    if [ ! -f "${statusFile}" ]; then
        ${showDebugMessages} && echo "Info: The status file doesn't exist yet."
        # Check whether the status file is creatable.
        ${TOUCH_CMD} "${statusFile}" 2> /dev/null
        testStatusFileStatusCode=${?}
        if [ ${testStatusFileStatusCode} -ne 0 ]; then
            echo "Error: The status file cannot be created." >&2
            exit 1
        else
            ${showDebugMessages} && echo "Info: The status file can be created."
            rm "${statusFile}" 2> /dev/null
            return 1
        fi
    fi

    ${showDebugMessages} && echo "Info: The status file exists."

    # Check whether the status file is read and writable.
    if [[ ! -r "${statusFile}" || ! -w "${statusFile}" ]]; then
        echo "Error: The status file is not read or writable." >&2
        exit 1
    fi
    statusFileOk=true
    ${showDebugMessages} && echo "Info: The status file is read and writable."

    # Lookup the age of the status file.
    checkStatusFileAge=$(${FIND_CMD} "${statusFile}" -mmin +${updateInterval} 2> /dev/null)
    checkStatusFileAgeStatusCode=${?}
    # Check whether the status file age lookup was successful.
    if [ ${checkStatusFileAgeStatusCode} -ne 0 ]; then
        ${showDebugMessages} && echo "Error: The status file age check wasn't successful. Status code: ${checkStatusFileAgeStatusCode}" >&2
        globalStatusCode="1"
    else
        ${showDebugMessages} && echo "Info: The status file age check was successful."
    fi

    # If there is a return value, the status file older than update interval and should be updated.
    if [[ "${checkStatusFileAge}" ]]; then
        ${showDebugMessages} && echo "Info: The status file is older than ${updateInterval} minutes."
        return 1
    fi

    ${showDebugMessages} && echo "Info: The status file is younger than ${updateInterval} minutes."

    # Return true regardless of the status file age, if the generation is forced.
    if "${forceGeneration}"; then
        ${showDebugMessages} && echo "Info: Force the generation / update of the status file."
        return 1
    else
        return 0
    fi
}

##############
# Generate the status file.
function generateStatusFile ()
{
    # Prepare the options.
    OLDIFS=${IFS}
    IFS=','
    for serviceOption in ${@}; do
        serviceOptionsArray+=(${serviceOption})
    done
    IFS=${OLDIFS}
    # Execute the status generation command and append the exit status.
    statusOutput=$(${TIMEOUT_CMD} ${statusGenerationTimeout} ${BASH_CMD} -c "${statusGenerationCommand}; echo \${PIPESTATUS[@]}" "${serviceOptionsArray[@]}" 2> /dev/null)
    timeoutStatusCode=${?}
    # Check weather the timeout command was successful and the timeout has not been reached.
    if [ ${timeoutStatusCode} -eq 124 ]; then
        if ${statusFileOk}; then
            ${showDebugMessages} && echo "Error: The timeout of ${statusGenerationTimeout} seconds for the status generation command has been reached." >&2
            globalStatusCode="1"
            return
        else
            echo "Error: The timeout of ${statusGenerationTimeout} seconds for the status generation command has been reached." >&2
            exit 1
        fi
    elif [ ${timeoutStatusCode} -ne 0 ]; then
        if ${statusFileOk}; then
            ${showDebugMessages} && echo "Error: The timeout command failed. Status code: ${timeoutStatusCode}" >&2
            globalStatusCode="1"
            return
        else
            echo "Error: The timeout command failed." >&2
            exit 1
        fi
    fi

    # Filter out the exit status.
    statusOutputStatusCode=$(echo "${statusOutput}" | ${TAIL_CMD} -1)
    # Filter out the status output.
    statusOutput=$(echo "${statusOutput}" | ${HEAD_CMD} -n -1)

    # Check whether the status generation command was successful.
    statusOutputFailed=false
    for code in ${statusOutputStatusCode}; do
        if [ ${code} -ne 0 ]; then
            statusOutputFailed=true
            break
        fi
    done
    if ${statusOutputFailed}; then
        if ${statusFileOk}; then
            ${showDebugMessages} && echo "Error: The status generation command failed. Status code: ${statusOutputStatusCode}" >&2
            globalStatusCode=1
            return
        else
            echo "Error: The status generation command failed. Status code: ${statusOutputStatusCode}" >&2
            exit 1
        fi
    fi
    ${showDebugMessages} && echo "Info: The status generation command was successful."

    # Check whether the status output is empty.
    if [ -z "${statusOutput}" ]; then
        if ${statusFileOk}; then
            ${showDebugMessages} && echo "Error: The status generation command produced an empty output." >&2
            globalStatusCode="1"
            return
        else
            echo "Error: The status generation command produced an empty output." >&2
            exit 1
        fi
    fi

    # Write down the status output and the date to the status file.
    printf 2> /dev/null '%b\n' "${statusOutput}" "${datePattern}" > "${statusFile}"
    writeStatusOutputStatusCode=${?}
    # Check whether the output could be written down successfully.
    if [ ${writeStatusOutputStatusCode} -ne 0 ]; then
        if ${statusFileOk}; then
            ${showDebugMessages} && echo "Error: The status couldn't be written down. Status code: ${writeStatusOutputStatusCode}" >&2
            globalStatusCode="1"
            return
        else
            echo "Error: The status couldn't be written down. Status code: ${writeStatusOutputStatusCode}" >&2
            exit 1
        fi
    fi

    ${showDebugMessages} && echo "Info: The status could be written down successfully."
}

##############
# Get the value.
function getValue ()
{
    # Execute the value lookup commando.
    if ${showAll}; then
        returnValue=$(${CAT_CMD} "${statusFile}" 2> /dev/null)
    else
        returnValue=$(${SED_CMD} -n "s/${sedValuePattern}/\1/p" "${statusFile}" 2> /dev/null)
    fi
    returnValueStatusCode=${?}
    # Check whether the value lookup commando was successful.
    if [ ${returnValueStatusCode} -ne 0 ]; then
        echo "Error: The value lookup commando failed. Status code: ${returnValueStatusCode}" >&2
        exit 1
    fi

    # Check whether the value is empty.
    if [ -z "${returnValue}" ]; then
        # Check whether the value exists.
        if ! ${GREP_CMD} -qP "${grepValuePattern}" "${statusFile}"; then
            echo "Error: Value doesn't exist." >&2
            exit 1
        fi
        ${showDebugMessages} && echo "Info: Value is empty."
        returnValue="${emptyReturnValue}"
    fi

    ${showDebugMessages} && echo "Info: The value could be looked up successfully."

    # Return the value.
    echo "${returnValue}"
}

##############
# Show available services.
function showAvailableServices ()
{
    # Set the log destination out of the parameter.
    logDest="1"
    if [ "${1}" == "error" ]; then
        logDest="2"
    fi

    # Print a list of all available services.
    echo -e "\nList of available services:" >&"${logDest}"
    unset availableServiceText
    for availableService in ${availableServiceList[@]}; do
        while read line; do
            if [[ ${line} == serviceDescription=* ]]; then
                serviceDescription=$(echo ${line} | ${SED_CMD} -n 's/serviceDescription="\(.*\)"/\1/p')
                break
            fi
            serviceDescription="No description"
        done < "${serviceConfDir}/${availableService}.${serviceConfSuff}"
        while read line; do
            if [[ ${line} == serviceOptionsRequired=true ]]; then
                serviceOptionsRequired=true
                break
            fi
            serviceOptionsRequired=false
        done < "${serviceConfDir}/${availableService}.${serviceConfSuff}"
        while read line; do
            if [[ ${line} == serviceOptionsAvailable=* ]]; then
                serviceOptionsAvailable=$(echo ${line} | ${SED_CMD} -n 's/serviceOptionsAvailable="\(.*\)"/\1/p')
                break
            fi
            unset serviceOptionsAvailable
        done < "${serviceConfDir}/${availableService}.${serviceConfSuff}"
        if ${serviceOptionsRequired}; then
            availableServiceText+="\t- ${availableService}\t${serviceDescription}\t(This service requires additional options: ${serviceOptionsAvailable})\n"
        else
            availableServiceText+="\t- ${availableService}\t${serviceDescription}\t\n"
        fi
    done
    echo -e "${availableServiceText}" | ${COLUMN_CMD} -t -s $'\t' >&"${logDest}"

    # Exit correspondingly.
    if [ "${logDest}" -eq 2 ]; then
        exit 1
    fi
    exit "${globalStatusCode}"
}

##############
# Show the help text.
function showHelp ()
{
    # Set the log destination out of the parameter.
    logDest="1"
    if [ "${1}" == "error" ]; then
        logDest="2"
    fi

    # Print a help text.
    echo "Usage: $(${BASENAME_CMD} ${0}) [-d] [-f] -s <SERVICE> [-o <OPTIONS>] -v <VALUE NAME> | -a" >&"${logDest}"
    echo -e "\t-d\tDebug mode\n" \
    "\t-f\tForce generation / update of the status\n" \
    "\t-h\tShow this help text\n" \
    "\t-s <SERVICE>\tThe service which should be used\n" \
    "\t-o <OPTIONS>\tComma-separated list of additional options to pass to the service (Not required by every service)\n" \
    "\t-v <VALUE NAME>\tThe name of the value which should be returned\n" \
    "\t-a\tPrint the entire status file\n" | ${COLUMN_CMD} -t -s $'\t' >&"${logDest}"

    # Print the available services.
    showAvailableServices "${1}"
}

# Call the main function and pass the options.
main "${@}"
