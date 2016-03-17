#!/bin/bash
################################################################################
# open-file-descriptors.sh - print the amount of open file descriptors for a
#                            specific user, group or process
################################################################################
#
# Copyright (C) 2016 stepping stone GmbH
#                    Switzerland
#                    http://www.stepping-stone.ch
#                    support@stepping-stone.ch
#
# Authors:
#  Yannick Denzer <yannick.denzer@stepping-stone.ch>
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
# This script prints the amount of open file descriptors owned by processes
# which are either matched by looking up their process name or full command
# line, or whose user or group ID is listed in a given list.
#
# Usage:
# open-file-descriptors.sh [-u userlist] [-g grouplist] [-c pattern] [-f]
#
# See `open-file-descriptors.sh -h` for more information and examples.
#
################################################################################

usage() {
	cat <<EOF >&2
Description:

	This script prints the amount of open file descriptors owned by processes
	which are either matched by looking up their process name or full command
	line, or whose user or group ID is listed in a given list.

Usage:

	$(basename $0) [-h] [-d] [-f] [-u userlist] [-g grouplist] [-c pattern]

Options:

	-h	Show this help text and exit immediately.
	-d	Enable debugging mode (print error messages to stderr).
	-f	Use the full command line instead of the process name
		for matching (see option -c).
	-u	Only match processes whose effective user ID is listed
		in 'userlist' (separated by comma).
	-g	Only match processes in the process group IDs listed
		in 'grouplist' (separated by comma).
	-c	Specifies an extended regular expression for matching
		against the process names or command lines.

Examples:

	Retrieve the total amount of open file descriptors which are owned by
	processes whose effective user ID is 'postgres' (-u) and whose process
	name is 'postgres' (-c):

		$(basename $0) -u postgres -c postgres

	Retrieve the total amount of open file descriptors which are owned by
	processes whose effective user ID is 'glassfish' (-u) and whose command
	line (-f) matches the given regular expression (-c):

		$(basename $0) -f -u glassfish \\
			-c '^/[^ ]+/java -cp /[^ ]+/glassfish.jar '

Debugging:

	$(basename $0) prints -1 either if no process was matched or if an
	error occoured. In case an error occoured, additional debugging
	inromation is displayed when the option '-d' is specified. Note that
	$(basename $0) also prints -1 if no process was matched.

EOF
	exit 1
}

debug=0
fullcmd=0
userlist=""
grouplist=""
command=""

while getopts ':u:g:c:hdf' option
do
	case "${option}" in
		h)
			usage
			;;
		d)
			debug=1
			;;
		f)
			fullcmd=1
			;;
		u)
			userlist="${OPTARG}"
			;;
		g)
			grouplist="${OPTARG}"
			;;
		c)
			command="${OPTARG}"
			;;
		\?)
			echo -e "Error: invalid option -${OPTARG}.\n" >&2
			usage
			;;
		:)
			echo -e "Error: option -${OPTARG} requires an argument.\n" >&2
			usage
			;;
	esac
done

[ -z "$userlist" -a -z "$grouplist" -a -z "$command" ] && usage
[ "$debug" = "0" ] && exec 2>/dev/null

args=()

[ -n "$userlist" ] && args+=('-u' "$userlist")
[ -n "$grouplist" ] && args+=('-g' "$grouplist")
[ "$fullcmd" = "1" ] && args+=('-f')
[ -n "$command" ] && args+=('--' "$command")

echo invoking \`pgrep "${args[@]}"\` >&2

if ! pids=$(pgrep "${args[@]}")
then
	echo -1
	exit 1
fi

for pid in ${pids}
do
	ls /proc/${pid}/fd
done | wc -l

exit 0
