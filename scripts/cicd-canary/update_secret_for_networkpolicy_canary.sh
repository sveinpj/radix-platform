#!/usr/bin/env bash

# PURPOSE
# Configures the secrets for radix network policy canary on the cluster given the context.

# Example 1:
# RADIX_ZONE_ENV=./../radix-zone/radix_zone_dev.env CLUSTER_NAME="weekly-01" ./update_secret_for_networkpolicy_canary.sh
#
# Example 2: Using a subshell to avoid polluting parent shell
# (RADIX_ZONE_ENV=./../radix-zone/radix_zone_dev.env CLUSTER_NAME="weekly-01" ./update_secret_for_networkpolicy_canary.sh)
#

# INPUTS:
#   RADIX_ZONE_ENV          (Mandatory)

echo ""
echo "Updating secret for the radix network policy canary"

#######################################################################################
### Check for prerequisites binaries
###

echo ""
printf "Check for neccesary executables... "
hash az 2>/dev/null || {
    echo -e "\nERROR: Azure-CLI not found in PATH. Exiting..." >&2
    exit 1
}
hash jq 2>/dev/null || {
    echo -e "\nERROR: jq not found in PATH. Exiting..." >&2
    exit 1
}
printf "All is good."
echo ""

# Validate mandatory input

if [[ -z "$RADIX_ZONE_ENV" ]]; then
    echo "ERROR: Please provide RADIX_ZONE_ENV" >&2
    exit 1
else
    if [[ ! -f "$RADIX_ZONE_ENV" ]]; then
        echo "ERROR: RADIX_ZONE_ENV=$RADIX_ZONE_ENV is invalid, the file does not exist." >&2
        exit 1
    fi
    source "$RADIX_ZONE_ENV"
fi

#######################################################################################
### Prepare az session
###

printf "Logging you in to Azure if not already logged in... "
az account show >/dev/null || az login >/dev/null
az account set --subscription "$AZ_SUBSCRIPTION_ID" >/dev/null
printf "Done.\n"

#######################################################################################
### Verify cluster access
###
printf "Verifying cluster access..."
if [[ $(kubectl cluster-info 2>&1) == *"Unable to connect to the server"* ]]; then
    printf "ERROR: Could not access cluster. Quitting...\n"  >&2
    exit 1
fi
printf " OK\n"

function getApiToken() {
    # Get auth token for Radix API
    printf "Getting auth token for Radix API...\n"
    API_ACCESS_TOKEN_RESOURCE=$(echo ${OAUTH2_PROXY_SCOPE} | awk '{print $4}' | sed 's/\/.*//')
    if [[ -z ${API_ACCESS_TOKEN_RESOURCE} ]]; then
        echo "ERROR: Could not get Radix API access token resource." >&2
        exit 1
    fi

    API_ACCESS_TOKEN=$(az account get-access-token --resource ${API_ACCESS_TOKEN_RESOURCE} | jq -r '.accessToken')
    if [[ -z ${API_ACCESS_TOKEN} ]]; then
        echo "ERROR: Could not get Radix API access token." >&2
        exit 1
    fi
    printf " Done.\n"
}

function getSecret() {
    SECRET_VALUES=$(az keyvault secret show \
    --vault-name "$AZ_RESOURCE_KEYVAULT" \
    --name radix-cicd-canary-values |
    jq '.value | fromjson')
    NETWORKPOLICY_CANARY_PASSWORD=$(echo $SECRET_VALUES | jq -r '.networkPolicyCanary.password')
    if [[ -z "$NETWORKPOLICY_CANARY_PASSWORD" ]]; then
        echo "ERROR: Could not get networkPolicyCanary.password from radix-cicd-canary-values in ${AZ_RESOURCE_KEYVAULT}." >&2
        exit 1
    fi
}

function getAppEnvironments() {
    APP_ENVIRONMENTS=$(curl \
        --silent \
        -X GET \
        "https://server-radix-api-prod.${CLUSTER_NAME}.${AZ_RESOURCE_DNS}/api/v1/applications/radix-networkpolicy-canary/environments" \
        -H 'accept: application/json' \
        -H 'Content-Type: application/json' \
        -H "Authorization: Bearer ${API_ACCESS_TOKEN}" \
        | jq .[].name --raw-output)
    if [[ -z "$APP_ENVIRONMENTS" ]]; then
        echo "ERROR: Could not get the app environments of radix-networkpolicy-canary."  >&2
        exit 1
    fi
    printf " Retrieved app environments $(echo $APP_ENVIRONMENTS | tr '\n' ' ')\n\n"
}

function updateSecret() {
    app_env=$1
    secret_name=$2
    secret_value=$3
    radix_component=$4
    printf "Updating ${secret_name} for environment ${app_env} in ${radix_component} component \n"
    API_REQUEST=$(curl \
         --silent \
         -X PUT \
         "https://server-radix-api-prod.${CLUSTER_NAME}.${AZ_RESOURCE_DNS}/api/v1/applications/radix-networkpolicy-canary/environments/${app_env}/components/${radix_component}/secrets/${secret_name}" \
         -H "accept: application/json" \
         -H "Authorization: bearer ${API_ACCESS_TOKEN}" \
         -H "Content-Type: application/json" \
         -d "{ \"secretValue\": \"${secret_value}\"}")
    if [[ "${API_REQUEST}" != "\"Success\"" ]]; then
        echo -e "\nERROR: API request failed."  >&2
        exit 1
    fi
    printf "Secret updated\n"
}

function resetAppRegistrationPassword() {
    # Generate new secret for App Registration.
    printf "Re-generate client secret for App Registration \"$APP_REGISTRATION_NETWORKPOLICY_CANARY\"...\n"
    APP_REGISTRATION_CLIENT_ID=$(az ad app list --display-name "$APP_REGISTRATION_NETWORKPOLICY_CANARY" | jq -r '.[].appId')

    UPDATED_APP_REGISTRATION_PASSWORD=$(az ad app credential reset --id "$APP_REGISTRATION_CLIENT_ID" --credential-description "${RADIX_ZONE}-${RADIX_ENVIRONMENT}" --append 2>/dev/null | jq -r '.password') # For some reason, description can not be too long.
    if [[ -z "$UPDATED_APP_REGISTRATION_PASSWORD" ]]; then
        echo -e "\nERROR: Could not re-generate client secret for App Registration \"$APP_REGISTRATION_NETWORKPOLICY_CANARY\". Exiting..." >&2
        exit 1
    fi
    printf " Done.\n"
}

function environmentIsOauthEnvironment() {
    env=$1
    GET_ENV=$(curl \
        --silent \
        --request GET \
        "https://server-radix-api-prod.${CLUSTER_NAME}.${AZ_RESOURCE_DNS}/api/v1/applications/radix-networkpolicy-canary/environments/${env}" \
        --header 'accept: application/json' \
        --header 'Content-Type: application/json' \
        --header "Authorization: Bearer ${API_ACCESS_TOKEN}")

    if [[ $(echo ${GET_ENV} | jq -r .error) != null ]]; then
        echo "${GET_ENV}" | jq . >&2
        echo "ERROR: Could not get the app secrets of the ${env} environment in radix-networkpolicy-canary." >&2
        return 1
    elif [[ $(echo ${GET_ENV} | jq --raw-output '.secrets[] | select(.name=="web-oauth2proxy-clientsecret")') ]]; then
        return 0
    else
        return 1
    fi
}

function getOauthAppEnvironments(){
    OAUTH_APP_ENVIRONMENTS=""
    for app_env in $APP_ENVIRONMENTS
    do
    if environmentIsOauthEnvironment $app_env;
    then
      printf "$app_env is OAuth2-enabled app environment. Updating \n"
      OAUTH_APP_ENVIRONMENTS="${OAUTH_APP_ENVIRONMENTS} $app_env"
    else
      printf "$app_env is not OAuth2-enabled app environment\n"
    fi
    done
    if [[ "$OAUTH_APP_ENVIRONMENTS" == "" ]]
    then
      printf "ERROR: No OAuth2-enabled app environments.\n" >&2
      exit 1
    fi
}

function updateNetworkPolicyCanaryHttpPassword(){
    printf "Updating NETWORKPOLICY_CANARY_PASSWORD...\n"
    getApiToken
    getAppEnvironments
    getSecret
    for app_env in $APP_ENVIRONMENTS
    do
      updateSecret $app_env NETWORKPOLICY_CANARY_PASSWORD ${NETWORKPOLICY_CANARY_PASSWORD} web
    done
}


function updateNetworkPolicyOauthAppRegistrationPasswordAndRedisSecret(){
    printf "Resetting ${APP_REGISTRATION_NETWORKPOLICY_CANARY} credentials and updating radixapp secrets...\n"
    getApiToken
    getAppEnvironments
    getOauthAppEnvironments
    resetAppRegistrationPassword
    for app_env in $OAUTH_APP_ENVIRONMENTS
    do
      updateSecret $app_env web-oauth2proxy-clientsecret ${UPDATED_APP_REGISTRATION_PASSWORD} web
      redis_password=$(openssl rand -base64 32 | tr -- '+/' '-_')
      updateSecret $app_env web-oauth2proxy-redispassword $redis_password web
      updateSecret $app_env REDIS_PASSWORD $redis_password redis
    done
}

### MAIN
updateNetworkPolicyCanaryHttpPassword
updateNetworkPolicyOauthAppRegistrationPasswordAndRedisSecret
