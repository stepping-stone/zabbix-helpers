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
BASH_CMD="/bin/bash"
CAT_CMD="/bin/cat"
DIRNAME_CMD="/bin/dirname"
FIND_CMD="/usr/bin/find"
HEAD_CMD="/bin/head"
LS_CMD="/bin/ls"
READLINK_CMD="/bin/readlink"
SED_CMD="/bin/sed"
TAIL_CMD="/bin/tail"
TIMEOUT_CMD="/usr/bin/timeout"
TOUCH_CMD="/bin/touch"

##############
# Main function.
function main ()
{
    # Call the setService function.
    setService
    # If the status file must be generated or updated, call the generateStatusFile function.
    if ! checkStatusFile; then
       generateStatusFile
    fi
    # Print the whole status file, if the corresponding parameter is set.
    if ${showAll}; then
        ${CAT_CMD} ${statusFile}
    # Else, return the selected value.
    else
        getValue
    fi
}

##############
# Check and load service configuration.
function setService ()
{
    # Set to false by default.
    serviceAvailable=false

    # Search for the selected service in the available service list.
    for availableService in ${availableServiceList[@]}; do
        if [ "${availableService}" == "${serviceName}" ]; then
            serviceAvailable=true
            break
        fi
    done

    # Build the service configuration path out of the selected service.
    serviceConfPath="${serviceConfDir}/${serviceName}.${serviceConfSuff}"

    # Check wheater the selected service is available.
    if ${serviceAvailable}; then
        source ${serviceConfPath}

        # Check wheater the status generation command is defined.
        if [ -z "${statusGenerationCommand}" ]; then
            echo "Error: Missing status generation command." >&2
            exit 1
        fi

        # Define the values by using the values from the configuration or setting a default.
        statusFile="${statusFileDir}/${statusFileName:-sst.${serviceName}.status}"
        valuePattern="${valuePattern:-${defaultValuePattern}}"
        datePattern="${datePattern:-${defaultDatePattern}}"

        # Print out some informational debug messages.
        ${showDebugMessages} && echo "Info: Using the service \"${serviceName}\"."
        ${showDebugMessages} && echo "Info: Service description is \"${serviceDescription}\"."
        ${showDebugMessages} && echo "Info: Using the status file \"${statusFile}\"."
        ${showDebugMessages} && echo "Info: Using the status generation command \"${statusGenerationCommand}\"."
        if [[ ${valueName} ]]; then
            ${showDebugMessages} && echo "Info: Using the value name \"${valueName}\"."
            ${showDebugMessages} && echo "Info: Using the value pattern \"${valuePattern}\"."
        fi
        ${showDebugMessages} && echo "Info: Using the date pattern \"${datePattern}\"."

        # Substitute the placeholders.
        valuePattern=$(echo ${valuePattern} | ${SED_CMD} -e "s/%VALUE_NAME%/${valueName}/g" -e "s/%VALUE%/\\\(\.\*\\\)/g")
        datePattern=$(echo ${datePattern} | ${SED_CMD} -e "s/%VALUE_NAME%/${dateValueName}/g" -e "s/%VALUE%/${dateGenerationCommand}/g")
    else
        echo -e "Error: The service \"${serviceName}\" isn't supported.\n" >&2
        showAvailableServices "error"
    fi
}

##############
# Check wheater the status file exists and is younger than update interval.
function checkStatusFile ()
{
    # Check wheater the status file exists.
    if [ -f ${statusFile} ]; then
        ${showDebugMessages} && echo "Info: The status file exists."
        # Check wheater the status file is read and writable.
        if [[ -r ${statusFile} && -w ${statusFile} ]]; then
            # Lookup the age of the status file.
            checkStatusFileAge=$(${FIND_CMD} ${statusFile} -mmin +${updateInterval} 2> /dev/null)
            checkStatusFileAgeStatusCode=${?}
            # Check wheater the status file age lookup was successful.
            if [ ${checkStatusFileAgeStatusCode} -eq 0 ]; then
                ${showDebugMessages} && echo "Info: The status file age check was successful."
                # If there is no return value, the status file age is younger than the update interval.
                # Else, the status file is older than the update interval.
                if [ -z ${checkStatusFileAge} ]; then
                    ${showDebugMessages} && echo "Info: The status file is younger than ${updateInterval} min."
                    # Return true regardless of the status file age, if the generation is forced.
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
                ${showDebugMessages} && echo "Error: The status file age check wasn't successful. Status code: ${checkStatusFileAgeStatusCode}" >&2
                exit 1
            fi
        else
            ${showDebugMessages} && echo "Error: The status file is not read or writable." >&2
            exit 1
        fi
    else
        # If the status file doesn't exist yet, test wheater it's creatable.
        ${showDebugMessages} && echo "Info: The status file doesn't exist yet."
        ${TOUCH_CMD} -c ${statusFile} 2> /dev/null
        testStatusFileStatusCode=${?}
        if [ ${testStatusFileStatusCode} -eq 0 ]; then
            ${showDebugMessages} && echo "Info: The status file can be created."
            return 1
        else
            ${showDebugMessages} && echo "Error: The status file cannot be created." >&2
            exit 1
        fi
    fi
}

##############
# Generate the status file.
function generateStatusFile ()
{

    # Execute the status generation command and append the exit status.
    statusOutput=$(${TIMEOUT_CMD} ${statusGenerationTimeout} ${BASH_CMD} -c "${statusGenerationCommand}; echo \${PIPESTATUS[@]}")
    timeoutStatusCode=${?}
    # Check weather the timeout has been reached.
    if [ ${timeoutStatusCode} -eq 124 ]; then
        ${showDebugMessages} && echo "Error: The timeout of ${statusGenerationTimeout} seconds for the status generation command has been reached."
    else
        # Filter out the exit status.
        statusOutputStatusCode=$(echo "${statusOutput}" | ${TAIL_CMD} -1)
        # Filter out the status output.
        statusOutput=$(echo "${statusOutput}" | ${HEAD_CMD} -n -2)
        # Check wheater one of the exit status is not 0.
        for code in ${statusOutputStatusCode}; do
            if [[ ${code} != 0 ]]; then
                statusFailed=true
                break
            fi
        done
        if [ ! ${statusFailed} ]; then
            ${showDebugMessages} && echo "Info: The status generation command was successful."
            # Check wheater the status output is empty.
            if [ -z "${statusOutput}" ]; then
                ${showDebugMessages} && echo "Error: The status generation command produced an empty output." >&2
            else
                # Write down the status output and the date to the status file.
                printf 2> /dev/null '%b\n' "${statusOutput}" "${datePattern}" > "${statusFile}"
                writeStatusOutputStatusCode=${?}
                if [ ${writeStatusOutputStatusCode} -eq 0 ]; then
                    ${showDebugMessages} && echo "Info: The status could be written down successfully."
                else
                    ${showDebugMessages} && echo "Error: The status couldn't be written down. Status code: ${writeStatusOutputStatusCode}" >&2
                    exit 1
                fi
            fi
        else
            ${showDebugMessages} && echo "Error: The status generation command failed. Status code: ${statusOutputStatusCode}" >&2
        fi
    fi
}

##############
# Get the value.
function getValue ()
{
    # Execute the value lookup commando.
    returnValue=$(${SED_CMD} -n "s/${valuePattern}/\1/p" ${statusFile} 2> /dev/null)
    returnValueStatusCode=${?}
    # Check wheater the value lookup commando was successful.
    if [ ${returnValueStatusCode} -eq 0 ]; then
        # Check wheater the value is empty.
        if [ -z ${returnValue} ]; then
            ${showDebugMessages} && echo "Error: Value doesn't exist or is empty." >&2
            exit 1
        else
            ${showDebugMessages} && echo "Info: The value could be looked up successfully."
            echo ${returnValue}
            exit 0
        fi
    else
        ${showDebugMessages} && echo "Error: The value lookup commando failed. Status code: ${returnValueStatusCode}" >&2
        exit 1
    fi
}

##############
# Show available services.
function showAvailableServices ()
{
    # Set the log destination out of the parameter.
    if [ "${1}" == "error" ]; then
        logDest="2"
    else
        logDest="1"
    fi

    # Print a list of all available services.
    echo -e "List of available services:" >&"${logDest}"
    for availableService in ${availableServiceList[@]}; do
        while read line; do
            if [[ ${line} == serviceDescription=* ]]; then
                serviceDescription=$(echo ${line} | ${SED_CMD} -n 's/serviceDescription="\(.*\)"/\1/p')
                break
            fi
        done < "${serviceConfDir}/${availableService}.${serviceConfSuff}"
        echo -e "\t- ${availableService} (${serviceDescription})" >&"${logDest}"
    done

    # Exit correspondingly.
    if [ "${logDest}" -eq 2 ]; then
        exit 1
    else
        exit 0
    fi
}

##############
# Show the help text.
function showHelp ()
{
    # Set the log destination out of the parameter.
    if [ "${1}" == "error" ]; then
        logDest="2"
    else
        logDest="1"
    fi

    # Print a help text.
    echo -e "Usage: $(${BASENAME_CMD} ${0}) [-d] [-f] -s <SERVICE> -v <VALUE NAME> | -a\n" \
    "\t-d\t\tDebug mode\n" \
    "\t-f\t\tForce generation / update of the status\n" \
    "\t-h\t\tShow this help text\n" \
    "\t-s <SERVICE>\tThe service which should be used\n" \
    "\t-v <VALUE NAME>\tThe name of the value which should be returned\n" \
    "\t-a\t\tPrint the entire status file\n" >&"${logDest}"

    # Print the available services.
    showAvailableServices "${1}"
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
            ;;
        d)
            showDebugMessages=true
            ;;
        f)
            forceGeneration=true
            ;;
        \?)
            echo -e "Error: Invalid option -$OPTARG.\n" >&2
            showHelp "error"
            ;;
        :)
            echo -e "Error: Option -$OPTARG requires an argument.\n" >&2
            showHelp "error"
            ;;
    esac
done

# Check for required options.
if [[ ${serviceName} ]] && ( [[ ${valueName} ]] || ${showAll} ) && ! ( [[ ${valueName} ]] && ${showAll} ); then
    # Set the path to the script file. Used in the configuration files.
    scriptFile=$(${READLINK_CMD} -f ${0})
    scriptPath=$(${DIRNAME_CMD} ${scriptFile})

    # Load the configuration.
    confFile="${scriptPath}/../../../etc/zabbix-helpers/get-status.conf"
    source ${confFile}
    sourceConfFileStatusCode=${?}
    if [ ${sourceConfFileStatusCode} -eq 0 ]; then
        ${showDebugMessages} && echo "Info: Configuration file loaded successfully."
    else
        ${showDebugMessages} && echo "Error: Couldn't load the configuration file. Status code: ${sourceConfFileStatusCode}" >&2
        exit 1
    fi
 
    # Get available services.
    serviceConfList=$(${LS_CMD} ${serviceConfDir}/*.${serviceConfSuff} 2> /dev/null)
    serviceConfListStatusCode=${?}
    if [ ${serviceConfListStatusCode} -eq 0 ]; then
        ${showDebugMessages} && echo "Info: Looked up available services successfully."
    else
        ${showDebugMessages} && echo "Error: There is no service available. Status code: ${serviceConfListStatusCode}" >&2
        exit 1
    fi
    for serviceConf in ${serviceConfList}; do
        availableServiceList+=($(${BASENAME_CMD} -s.conf ${serviceConf}))
    done

    # Call the main function.
    main
else
    echo -e "Error: Missing or wrongly used option(s).\n" >&2
    # Call the showHelp function and exit.
    showHelp "error"
fi
