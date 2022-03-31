#!/bin/bash

if [ $# -gt 0 ]
  then
    source $1
fi

## Capture MSR Info
[ -z "$MSR_HOSTNAME" ] && read -p "Enter the MSR hostname and press [ENTER]:" MSR_HOSTNAME
[ -z "$MSR_USER" ] && read -p "Enter the MSR username and press [ENTER]:" MSR_USER
[ -z "$MSR_PASSWORD" ] && read -s -p "Enter the MSR token or password and press [ENTER]:" MSR_PASSWORD
echo ""
echo "***************************************\\n"

[ -z "$REPO_FILE" ] && read -p "Repositories file(repositories.json):" REPO_FILE
[ -z "$REPO_MIRROR_COUNT" ] && read -p "Repositories Mirror Count(default: 10):" REPO_MIRROR_COUNT


TOKEN=$(curl -kLsS -u ${MSR_USER}:${MSR_PASSWORD} "https://${MSR_HOSTNAME}/auth/token" | jq -r '.token')
CURLOPTS=(-kLsS -H 'accept: application/json' -H 'content-type: application/json' -H "Authorization: Bearer ${TOKEN}")

## Read repositories file
repo_list=$(cat ${REPO_FILE} | jq -c -r '.[]') 

pending=0
# Loop through repositories
while IFS= read -r row ; do
    namespace=$(echo "$row" | jq -r .namespace)
    reponame=$(echo "$row" | jq -r .name)
    status="Not Enabled"

    ## Get existing mirroring policies
    pollMirroringPolicies=$(curl "${CURLOPTS[@]}" -X GET \
        "https://${MSR_HOSTNAME}/api/v0/repositories/${namespace}/${reponame}/pollMirroringPolicies")
    
    policies_num=$(echo $repos | jq 'length')
    policies=$(echo $pollMirroringPolicies | jq -c -r '.[]')
    while IFS= read -r policy; do
        id=$(echo $policy | jq -r .id)
        enabled=$(echo $policy | jq -r .enabled)
        if [ $enabled == "true" ]
        then
            lastStatus=$(echo $policy | jq -r .lastStatus.code)
            if [[ $lastStatus == "SUCCESS" ]]
            then
                status=COMPLETE
            else
                status=Pending
                pending=$((pending+1))
            fi
        elif [ $enabled == "false" ] && [ $pending -le $REPO_MIRROR_COUNT ]
        then
            postdata=$(echo { \"enabled\": true })
            response=$(curl "${CURLOPTS[@]}" -X PUT -d "$postdata" \
                "https://${MSR_HOSTNAME}/api/v0/repositories/${namespace}/${reponame}/pollMirroringPolicies/${id}")
            status=Enabling
            pending=$((pending+1))
        fi

        echo "Repo: ${namespace}/${reponame}, PolicyId: ${id}, Enabled: ${enabled} ==> Status: ${status}"
        id=
        enabled=
        status=
    done <<< "$policies"
done <<< "$repo_list"
echo "=========================================\\n"