#!/bin/bash

SECONDS_UNTIL_NEXT_INVALID=$((90*24*60*60)) # 90 days
cert_dir="/etc/letsencrypt/live"

for folder in "$cert_dir"/*
do
	if ! test -f "${folder}/cert.pem"
	then
		continue
	fi

	exp_date=$(openssl x509 -noout -enddate -in "${folder}/cert.pem" | cut -d= -f 2)
	t_remaining=$(( ($(date -d "${exp_date}" +%s)-$(date +%s)) ))

	if test "${t_remaining}" -lt "${SECONDS_UNTIL_NEXT_INVALID}"
	then
		SECONDS_UNTIL_NEXT_INVALID="${t_remaining}"
	fi
done

echo $(( ${SECONDS_UNTIL_NEXT_INVALID} / 3600 ))
