#!/bin/bash

#######################################################################################
### PURPOSE
### 

# Tear down radix zone infrastructure


#######################################################################################
### INPUTS
### 

# Required:
# - RADIX_ZONE_ENV      : Path to *.env file

# Optional:
# - USER_PROMPT         : Is human interaction is required to run script? true/false. Default is true.


#######################################################################################
### HOW TO USE
### 

# RADIX_ZONE_ENV=../radix_zone_us.env ./teardown.sh


#######################################################################################
### START
### 

echo ""
echo "Start tear down of Radix Zone... "


#######################################################################################
### Check for prerequisites binaries
###

echo ""
printf "Check for neccesary executables... "
hash az 2> /dev/null || { echo -e "\nError: Azure-CLI not found in PATH. Exiting... " >&2;  exit 1; }
printf "Done.\n"


#######################################################################################
### Read inputs and configs
###

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

if [[ -z "$USER_PROMPT" ]]; then
    USER_PROMPT=true
fi



#######################################################################################
### Prepare az session
###

printf "Logging you in to Azure if not already logged in... "
az account show >/dev/null || az login >/dev/null
az account set --subscription "$AZ_SUBSCRIPTION" >/dev/null
printf "Done.\n"


#######################################################################################
### Verify task at hand
###

echo -e ""
echo -e "Tear down will use the following configuration:"
echo -e ""
echo -e "   > WHERE:"
echo -e "   ------------------------------------------------------------------"
echo -e "   -  RADIX_ZONE                       : $RADIX_ZONE"
echo -e "   -  AZ_RADIX_ZONE_LOCATION           : $AZ_RADIX_ZONE_LOCATION"
echo -e "   -  RADIX_ENVIRONMENT                : $RADIX_ENVIRONMENT"
echo -e ""
echo -e "   > WHAT:"
echo -e "   -------------------------------------------------------------------"
echo -e "   -  AZ_RESOURCE_CONTAINER_REGISTRY   : $AZ_RESOURCE_CONTAINER_REGISTRY"
echo -e "   -  AZ_RESOURCE_DNS                  : $AZ_RESOURCE_DNS"
echo -e ""
echo -e "   > WHO:"
echo -e "   -------------------------------------------------------------------"
echo -e "   -  AZ_SUBSCRIPTION                  : $AZ_SUBSCRIPTION"
echo -e "   -  AZ_USER                          : $(az account show --query user.name -o tsv)"
echo -e ""
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




#######################################################################################
### Remove infrastructure
###

echo "Deleting Azure Container Registry: ${AZ_RESOURCE_CONTAINER_REGISTRY}..."
az acr delete --name "${AZ_RESOURCE_CONTAINER_REGISTRY}" --resource-group "${AZ_RESOURCE_GROUP_COMMON}" 2>&1 >/dev/null
echo "...Done."

echo "Deleting Azure DNS: ${AZ_RESOURCE_DNS}..."
az network dns zone delete --yes -g "${AZ_RESOURCE_GROUP_COMMON}" -n "${AZ_RESOURCE_DNS}" 2>&1 >/dev/null
echo "...Done."



#######################################################################################
### END
###

echo ""
echo "Teardown done!"