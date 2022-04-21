#!/usr/bin/env bash

#######################################################################################
### PURPOSE
###

# Bootstrap ingress-nginx in a radix cluster

#######################################################################################
### PRECONDITIONS
###

# - AKS cluster is available
# - User has role cluster-admin

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
echo "Start bootstrap of ingress-nginx... "

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
echo -e "Install ingress-nginx will use the following configuration:"
echo -e ""
echo -e "   > WHERE:"
echo -e "   ------------------------------------------------------------------"
echo -e "   -  RADIX_ZONE                       : $RADIX_ZONE"
echo -e "   -  CLUSTER_NAME                     : $CLUSTER_NAME"
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
### Verify cluster access
###
printf "Verifying cluster access..."
if [[ $(kubectl cluster-info 2>&1) == *"Unable to connect to the server"* ]]; then
    printf "ERROR: Could not access cluster. Quitting...\n"
    exit 1
fi
printf " OK\n"


#######################################################################################
### Create secret required by ingress-nginx
###

echo "Install secret ingress-ip in cluster"

# Path to Public IP Prefix which contains the public inbound IPs
IPPRE_INBOUND_ID="/subscriptions/$AZ_SUBSCRIPTION_ID/resourceGroups/$AZ_RESOURCE_GROUP_COMMON/providers/Microsoft.Network/publicIPPrefixes/$AZ_IPPRE_INBOUND_NAME"

# list of AVAILABLE public ips assigned to the Radix Zone
echo "Getting list of available public inbound ips in $RADIX_ZONE..."
AVAILABLE_INBOUND_IPS="$(az network public-ip list | jq '.[] | select(.publicIpPrefix.id=="'$IPPRE_INBOUND_ID'" and .ipConfiguration.resourceGroup==null)' | jq '{name: .name, id: .id}' | jq -s '.')"

SELECTED_IP="$(echo $AVAILABLE_INBOUND_IPS | jq '.[0:1]')"

if [[ "$AVAILABLE_INBOUND_IPS" == "[]" ]]; then
    echo "ERROR: Query returned no ips. Please check the variable AZ_IPPRE_INBOUND_NAME in RADIX_ZONE_ENV and that the IP-prefix exists. Exiting..."
    exit 1
elif [[ -z $AVAILABLE_INBOUND_IPS ]]; then
    echo "ERROR: Found no available ips to assign to the destination cluster. Exiting..."
    exit 1
else
    echo "-----------------------------------------------------------"
    echo ""
    echo "The following public IP(s) are currently available:"
    echo ""
    echo $AVAILABLE_INBOUND_IPS | jq -r '.[].name'
    echo ""
    echo "The following public IP will be assigned as inbound IP to the cluster:"
    echo ""
    echo $SELECTED_IP | jq -r '.[].name'
    echo ""
    echo "-----------------------------------------------------------"
fi

echo ""
USER_PROMPT="true"
if [[ $USER_PROMPT == true ]]; then
    while true; do
        read -p "Is this correct? (Y/n) " yn
        case $yn in
            [Yy]* ) echo ""; echo "Sounds good, continuing."; break;;
            [Nn]* ) echo ""; echo "Quitting."; exit 0;;
            * ) echo "Please answer yes or no.";;
        esac
    done
fi
echo ""

SELECTED_IP_ID=$(echo $SELECTED_IP | jq -r '.[].id')
SELECTED_IP_RAW_ADDRESS="$(az network public-ip show --ids $SELECTED_IP_ID --query ipAddress -o tsv)"

echo "controller:
  service:
    loadBalancerIP: $SELECTED_IP_RAW_ADDRESS" > config

kubectl create namespace ingress-nginx --dry-run=client -o yaml |
    kubectl apply -f -

kubectl create secret generic ingress-nginx-ip --namespace ingress-nginx \
            --from-file=./config \
            --dry-run=client -o yaml |
            kubectl apply -f -

rm config

echo "Done."