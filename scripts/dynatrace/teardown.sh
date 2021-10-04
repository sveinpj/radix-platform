#!/bin/bash


#######################################################################################
### PURPOSE
### 

# Delete connection between cluster and dynatrace


#######################################################################################
### PRECONDITIONS
### 

# - AKS cluster is available
# - Dynatrace secrets are available in keyvault: API_URL and API_TOKEN


#######################################################################################
### INPUTS
### 

# Required:
# - RADIX_ZONE_ENV      : Path to *.env file
# - CLUSTER_NAME        : Ex: "test-2", "weekly-93"

# Optional:
# - USER_PROMPT         : Is human interaction is required to run script? true/false. Default is true.


#######################################################################################
### HOW TO USE
### 

# Normal usage
# RADIX_ZONE_ENV=../radix-zone/radix_zone_dev.env CLUSTER_NAME="weekly-2" ./teardown.sh

#######################################################################################
### START
### 

echo ""
echo "Start teardown of Dynatrace..."

#######################################################################################
### Check for prerequisites binaries
###

echo ""
printf "Check for neccesary executables... "
hash az 2> /dev/null || { echo -e "\nError: Azure-CLI not found in PATH. Exiting...";  exit 1; }
printf "All is good."
echo ""


#######################################################################################
### Read inputs and configs
###

# Required inputs

if [[ -z "$RADIX_ZONE_ENV" ]]; then
    echo "Please provide RADIX_ZONE_ENV" >&2
    exit 1
else
    if [[ ! -f "$RADIX_ZONE_ENV" ]]; then
        echo "RADIX_ZONE_ENV=$RADIX_ZONE_ENV is invalid, the file does not exist." >&2
        exit 1
    fi
    source "$RADIX_ZONE_ENV"
fi

if [[ -z "$CLUSTER_NAME" ]]; then
    echo "Please provide CLUSTER_NAME" >&2
    exit 1
fi

# Optional inputs

if [[ -z "$USER_PROMPT" ]]; then
    USER_PROMPT=true
fi

#######################################################################################
### Prepare az session
###

printf "Logging you in to Azure if not already logged in... "
az account show >/dev/null || az login >/dev/null
az account set --subscription "$AZ_SUBSCRIPTION_ID" >/dev/null
printf "Done.\n"


#######################################################################################
### Verify task at hand
###

echo -e ""
echo -e "Teardown of Dynatrace will use the following configuration:"
echo -e ""
echo -e "   > WHAT:"
echo -e "   ------------------------------------------------------------------"
echo -e "   -  CLUSTER_NAME                     : $CLUSTER_NAME"
echo -e ""
echo -e "   > WHO:"
echo -e "   -------------------------------------------------------------------"
echo -e "   -  AZ_SUBSCRIPTION                  : $(az account show --query name -otsv)"
echo -e "   -  AZ_USER                          : $(az account show --query user.name -o tsv)"
echo -e ""

echo ""

if [[ $USER_PROMPT == true ]]; then
    read -p "Is this correct? (Y/n) " -n 1 -r
    if [[ "$REPLY" =~ (N|n) ]]; then
    echo ""
    echo "Quitting."
    exit 0
    fi
    echo ""
fi

echo ""

# Get secrets: api-url and tenant-token from keyvault
API_URL=$(az keyvault secret show --vault-name "$AZ_RESOURCE_KEYVAULT" --name dynatrace-api-url | jq -r .value)
if [[ -z "$API_URL" ]]; then
    echo "Please provide API_URL" >&2
    exit 1
fi
API_TOKEN=$(az keyvault secret show --vault-name "$AZ_RESOURCE_KEYVAULT" --name dynatrace-tenant-token | jq -r .value)
if [[ -z "$API_TOKEN" ]]; then
    echo "Please provide API_TOKEN" >&2
    exit 1
fi

getClusterId() {
    response=$(apiRequest "GET" "/config/v1/kubernetes/credentials")

    if echo "$response" | grep -Fq "\"name\":\"${CLUSTER_NAME}\""; then
        CREDENTIAL_ID="$(echo $response | jq '.values' | jq -r '.[] | select(.name=="'$CLUSTER_NAME'").id')"
    else
        echo "Error: Credential with cluster name \"${CLUSTER_NAME}\" not found in Dynatrace."
        exit 1
    fi
}

deleteK8sConfiguration() {
    response=$(apiRequest "DELETE" "/config/v1/kubernetes/credentials/${CREDENTIAL_ID}")

    if [[ -z "$response" ]]; then
        echo "Successfully deleted Kubernetes Configuration."
    else
        echo "Error deleting Kubernetes cluster from Dynatrace: $response"
    fi
}

apiRequest() {
    method=$1
    url=$2

    response="$(curl -sS -X ${method} "${API_URL}${url}" \
        -H "accept: application/json; charset=utf-8" \
        -H "Authorization: Api-Token ${API_TOKEN}" \
        -H "Content-Type: application/json; charset=utf-8")"

    echo "$response"
}

#######################################################################################
### Main
###

echo "Get ID of cluster credential..."
getClusterId
echo "Delete cluster credential..."
deleteK8sConfiguration


#######################################################################################
### END
###

echo ""
echo "Teardown of Dynatrace is done!"