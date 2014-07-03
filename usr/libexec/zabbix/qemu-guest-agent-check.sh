#!/bin/bash
################################################################################
# qemu-guest-agent-check.sh - Pings the Qemu Guest Agent and send it via zabbix
################################################################################
#
# Copyright (C) 2014 stepping stone GmbH
#                    Switzerland
#                    http://www.stepping-stone.ch
#                    support@stepping-stone.ch
#  
# Authors:
#  David Vollmer <david.vollmer@stepping-stone.ch>
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
# This script pings the qemu guest agent and sends the result via the
# zabbix_sender to the monitoring server.
#
################################################################################

################################################################################
# Source and define logging functions
################################################################################

LIB_DIR=${LIB_DIR:="/usr/share/stepping-stone/lib/bash"}

source "${LIB_DIR}/input-output.lib.sh" && \
 source "${LIB_DIR}/syslog.lib.sh"

if [ ${?} != "0" ]
then
   echo "Could not source the needed libs" >&2
   exit 1
fi

##############
# Check if the last command was successful, otherwise throw an error
#
# Check if the last command run successful
# $1: Name of the command
# $2: Exit status of the command
# $3: What to print if it failed
# $4: Severity as one of debug, info, error, die
function checkReturnStatus () {
   if [[ "${2}" != "0" ]]
   then
      # use 'error' as default severity
      severity="error"

      if [ "${4}" != "" ]
      then
         # set severity to parameter 4 if its set
         severity="${4}"
      fi

      # send messages to the specific loglevel
      ${severity} "Command ${1} failed with status ${2}: ${3}"

      # increase the error counter
      errorCount=$((errorCount + 1))

   else
      debug "Successfully run ${1}."

   fi
}


##############
# Send the state the state of a machine to the monitoring server
#
# $1: For which Host the value is
# $2: Keyname
# $3: Value to send
function sendToZabbix () {

   info "Running ${zabbixCmd} -c ${zabbixConfig} -s ${1} -k ${2} -o ${3}"
   local zabbixOutput
   zabbixOutput="$( ${zabbixCmd} -c ${zabbixConfig} -s ${1} -k ${2} -o ${3} )"
   if [ "${?}" != "0" ]
   then
      error "Zabbix exited not 0 with: ${zabbixOutput}"
   else
      info "Sent info successful to Zabbix Server"
   fi

}

##############
# Get the state of specific machine
function pingMachine () {

   returnVal="$( $virshCmd qemu-agent-command --pretty ${machine} '{"execute":"guest-ping"}' 2>&1 )"
   exitVal="$?"

   checkReturnStatus "guest-ping ${machine}" "$exitVal" "Ping on ${machine} failed" "info"

   return ${exitVal}

}


##############
# Get hostname from the UUID
#
# $1: UUID
function getHostFromUuid ()
{
   hostName="$( virsh dumpxml ${1} | grep -Eio "kvm-[0-9]{3,4}" | head -n 1 )"
   echo ${hostName}
   return $?
}

##############
# Cycle trough all running machines and send their state to the monitoring server
function sendAllStates (){
machines="$( getAllUuids )"
for machine in ${machines}
do
   info "Processing ${machine}"

done

}

##############
# Show the usage / help
function showHelp (){
echo -e "Usage: $( basename $0 )

-d\tBe verbose
-h\tShow this help text
-m MACHINE-UUID\tOnly process this machine
-n\tDo not actually send anything to the server


" >&2

}


##############
# Get the uuids from all running machines
function getAllUuids () {

   kvmMachines="$( $virshCmd list --name )"
   echo ${kvmMachines}
}



################################################################################
# Define variables
################################################################################

virshCmd="/usr/bin/virsh"
zabbixCmd="/usr/bin/zabbix_sender"
zabbixItemName="sst.qemu.guestagent.ping[]"
zabbixConfig="/etc/zabbix/zabbix_agentd.conf"

scriptLock="/var/run/$( basename $0 ).lock"


################################################################################
# The actual start of the script
################################################################################

info "Starting $(basename $0)"

##############
# Initialization

# Check command line parameters
while getopts ":i:" option
do
   case $option in
   i )
      instances="${OPTARG}"
      ;;
   : )
      echo "Option -${OPTARG} requires a parameter. Usage: $( basename $0 ) [-i instancePath]" >&2
      exit 1
      ;;
   * )
      echo "Unknown parameter ${OPTARG}. Usage: $( basename $0 ) [-i instancePath]" >&2
      exit 1
      ;;
   esac
done

# Set a lock to prevent concurrent running of the script
(
flock -n 9 || checkReturnStatus "locking" "nolock" "We seem to be already running. If not, remove the lock file ${scriptLock} manually." "die"

# If there were no instances set on the command line we will create a list
if [ "$instances" == "" ]
then
   # Get the list of instances
   instances="$( getAllUuids )"
fi

info "Going to process the following instances: $( echo "${instances}" | tr "\n" " " )"

# Cycle trough the list of machines and process them
for machine in ${instances}
do
   # Ping every instance
   info "Pinging ${machine}"
   returnVal=$( pingMachine ${machine} )
   exitVal="$?"

   # Retrieve the hostname
   hostName=$( getHostFromUuid ${machine} )
   if [ "${hostName}" == "" ]
   then
      error "Could not get hostname for ${machine}"
      continue
   fi

   # Send state
   sendToZabbix ${hostName} ${zabbixItemName} ${exitVal}

done

# Remove the lock from the script
) 9>${scriptLock}


