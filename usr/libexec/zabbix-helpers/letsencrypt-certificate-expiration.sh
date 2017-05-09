#!/bin/bash
SECONDS_UNTIL_NEXT_INVALID=7776000    # 90 days times 86400 seconds per day
cert_dir="/etc/letsencrypt/live"
 
for folder in $(ls ${cert_dir}); do
    exp_date=$(openssl x509 -noout -enddate -in "${cert_dir}/${folder}/cert.pem" | cut -d= -f 2);
    t_remaining=$(( ($(date -d "${exp_date}" +%s)-$(date +%s)) ))
 
    if [[ ${t_remaining} -lt ${SECONDS_UNTIL_NEXT_INVALID} ]]; then
        SECONDS_UNTIL_NEXT_INVALID=${t_remaining};
    fi
done

echo $(( ${SECONDS_UNTIL_NEXT_INVALID} / 3600 ))
