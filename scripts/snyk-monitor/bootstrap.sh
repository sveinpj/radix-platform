#!/usr/bin/env bash

#######################################################################################
### PURPOSE
###

# Bootstrap snyk-monitor in a radix cluster

#######################################################################################
### PRECONDITIONS
###

# - AKS cluster is available
# - User has role cluster-admin
# - secret "radix-snyk-sa-access-token-${RADIX_ZONE}" exists in keyvault

#######################################################################################
### INPUTS
###

# Required:
# - RADIX_ZONE_ENV      : Path to *.env file
# - CLUSTER_NAME        : Ex: "playground-2", "weekly-93"

# Optional:           
# - USER_PROMPT         : Is human interaction is required to run script? true/false. Default is true.

#######################################################################################
### HOW TO USE
###

# NORMAL
# RADIX_ZONE_ENV=../radix-zone/radix_zone_dev.env CLUSTER_NAME="weekly-2" ./bootstrap.sh

#######################################################################################
### START
###

# Script vars
WORK_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

echo ""
echo "Start bootstrap of snyk-monitor... "

#######################################################################################
### Check for prerequisites binaries
###

echo ""
printf "Check for neccesary executables... "
hash az 2>/dev/null || {
    echo -e "\nError: Azure-CLI not found in PATH. Exiting..."
    exit 1
}
hash kubectl 2>/dev/null || {
    echo -e "\nError: kubectl not found in PATH. Exiting..."
    exit 1
}
hash helm 2>/dev/null || {
    echo -e "\nError: helm not found in PATH. Exiting..."
    exit 1
}
hash jq 2>/dev/null || {
    echo -e "\nError: jq not found in PATH. Exiting..."
    exit 1
}
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
echo -e "Bootstrap snyk-monitor will use the following configuration:"
echo -e ""
echo -e "   > WHERE:"
echo -e "   ------------------------------------------------------------------"
echo -e "   -  RADIX_ZONE                       : $RADIX_ZONE"
echo -e "   -  CLUSTER_NAME                     : $CLUSTER_NAME"
echo -e ""
echo -e "   > WHAT:"
echo -e "   -------------------------------------------------------------------"
echo -e "   -  AZ_RESOURCE_KEYVAULT             : $AZ_RESOURCE_KEYVAULT"
echo -e ""
echo -e "   > WHO:"
echo -e "   -------------------------------------------------------------------"
echo -e "   -  AZ_SUBSCRIPTION                  : $(az account show --query name -otsv)"
echo -e "   -  AZ_USER                          : $(az account show --query user.name -o tsv)"
echo -e ""

echo ""

if [[ $USER_PROMPT == true ]]; then
    while true; do
        read -p "Is this correct? (Y/n) " yn
        case $yn in
            [Yy]* ) break;;
            [Nn]* ) echo ""; echo "Quitting."; exit 0;;
            * ) echo "Please answer yes or no.";;
        esac
    done
fi

echo ""

#######################################################################################
### CLUSTER?
###

kubectl_context="$(kubectl config current-context)"

if [ "$kubectl_context" = "$CLUSTER_NAME" ] || [ "$kubectl_context" = "${CLUSTER_NAME}-admin" ]; then
    echo "kubectl is ready..."
else
    echo "Please set your kubectl current-context to be ${CLUSTER_NAME}-admin"
    exit 1
fi

#######################################################################################
### Create secret required by snyk-monitor
###
# https://docs.snyk.io/products/snyk-container/image-scanning-library/kubernetes-workload-and-image-scanning/install-the-snyk-controller-with-helm

echo "Install secret \"snyk-monitor\" in cluster..."

# Create namespace
kubectl create namespace snyk-monitor \
2>&1 >/dev/null

SNYK_INTEGRATION_ID="$(az keyvault secret show --vault-name $AZ_RESOURCE_KEYVAULT --name radix-snyk-sa-access-token-${RADIX_ZONE} 2>/dev/null | jq -r .value)"
if [[ $SNYK_INTEGRATION_ID == "" ]]; then
    echo "Error: Could not find secret \"radix-snyk-sa-access-token-${RADIX_ZONE}\" in keyvault. Quitting.."
    exit 1
fi

# Create new dockercfg.json file to provide access to ACR.
test -f "dockercfg.json" && rm "dockercfg.json"
if [[ $(kubectl get secret radix-docker 2>&1) == *"Error"* ]]; then
    echo "Error: Could not find secret \"radix-docker\" in cluster. Quitting.."
    exit 1
else
    echo $(kubectl get secret radix-docker -ojsonpath='{.data.\.dockerconfigjson}') | base64 -d | jq . >> dockercfg.json

    kubectl create secret generic snyk-monitor \
        --namespace snyk-monitor \
        --from-file=dockercfg.json \
        --from-literal=integrationId=$SNYK_INTEGRATION_ID

    rm "dockercfg.json"
fi

echo "Done."
