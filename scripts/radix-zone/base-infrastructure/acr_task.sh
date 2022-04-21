#!/usr/bin/env bash

#######################################################################################
### PURPOSE
###

# Create Azure Container Registry (ACR) Task
# This script will: 
# - create an ACR Task with a system-assigned identity
# - grant the Task system-assigned identity access to push to ACR
# - add credentials using the system-assigned identity to the task

#######################################################################################
### DOCS
###

# https://docs.microsoft.com/en-us/azure/container-registry/container-registry-tasks-authentication-managed-identity
# https://docs.microsoft.com/en-us/azure/container-registry/allow-access-trusted-services#example-acr-tasks

#######################################################################################
### PRECONDITIONS
###

# - ACR Exists

#######################################################################################
### INPUTS
###

# Required:
# - RADIX_ZONE_ENV      : Path to *.env file

#######################################################################################
### HOW TO USE
###

# NORMAL
# RADIX_ZONE_ENV=../radix_zone_dev.env ./acr_task.sh

#######################################################################################
### START
###

#######################################################################################
### Check for prerequisites binaries
###

echo ""
printf "Check for neccesary executables... "
hash az 2>/dev/null || {
    echo -e "\nError: Azure-CLI not found in PATH. Exiting..."
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

if [[ -z "$AZ_RESOURCE_CONTAINER_REGISTRY" ]]; then
    echo "AZ_RESOURCE_CONTAINER_REGISTRY not defined. Exiting..."
    exit 1
fi

if [[ -z "$AZ_RESOURCE_ACR_TASK_NAME" ]]; then
    echo "AZ_RESOURCE_ACR_TASK_NAME not defined. Exiting..."
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
echo -e "Create ACR Task with the following configuration:"
echo -e ""
echo -e "   > WHAT:"
echo -e "   -------------------------------------------------------------------"
echo -e "   -  AZ_RESOURCE_CONTAINER_REGISTRY    : $AZ_RESOURCE_CONTAINER_REGISTRY"
echo -e "   -  AZ_RESOURCE_ACR_TASK_NAME         : $AZ_RESOURCE_ACR_TASK_NAME";
echo -e ""
echo -e "   > WHO:"
echo -e "   -------------------------------------------------------------------"
echo -e "   -  AZ_SUBSCRIPTION                  : $(az account show --query name -otsv)"
echo -e "   -  AZ_USER                          : $(az account show --query user.name -o tsv)"
echo -e ""
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

function create_acr_task() {
    local TASK_NAME="$1"
    local ACR_NAME="$2"
    local NO_PUSH="$3"
    TASK_YAML="task.yaml"
    test -f "$TASK_YAML" && rm "$TASK_YAML"
    if [[ $NO_PUSH == "--no-push" ]]; then
        PUSH=""
        cat <<EOF >>${TASK_YAML}
version: v1.1.0
steps:
  - build: -t {{.Values.IMAGE}} -t {{.Values.CLUSTERTYPE_IMAGE}} -t {{.Values.CLUSTERNAME_IMAGE}} -f {{.Values.DOCKER_FILE_NAME}} .
EOF
    else
        cat <<EOF >>${TASK_YAML}
version: v1.1.0
steps:
  - build: -t {{.Values.IMAGE}} -t {{.Values.CLUSTERTYPE_IMAGE}} -t {{.Values.CLUSTERNAME_IMAGE}} -f {{.Values.DOCKER_FILE_NAME}} .
  - push:
    - {{.Values.IMAGE}}
    - {{.Values.CLUSTERTYPE_IMAGE}}
    - {{.Values.CLUSTERNAME_IMAGE}}
EOF
    fi
    printf "Create ACR Task: ${TASK_NAME} in ACR: ${ACR_NAME}..."
    az acr task create \
        --registry ${ACR_NAME} \
        --name ${TASK_NAME} \
        --context /dev/null \
        --file ${TASK_YAML} \
        --assign-identity [system] \
        --auth-mode None \
        $NO_PUSH \
        --output none

    rm "$TASK_YAML"
    printf " Done.\n"
}

function create_role_assignment(){
    local TASK_NAME="$1"
    local ACR_NAME="$2"
    printf "Get ID of ACR: ${ACR_NAME}..."
    REGISTRY_ID=$(az acr show --name ${ACR_NAME} --query id --output tsv)
    printf "Done.\n"

    printf "Get ID of task: ${TASK_NAME}..."
    TASK_IDENTITY=$(az acr task show --name ${TASK_NAME} --registry ${ACR_NAME} --query identity.principalId --output tsv)
    printf " Done.\n"

    printf "Create role assignment..."
    az role assignment create \
        --assignee $TASK_IDENTITY \
        --scope $REGISTRY_ID \
        --role "AcrPush" \
        --output none \
        2>/dev/null
    printf " Done.\n"
}

function add_task_credential() {
    local TASK_NAME="$1"
    local ACR_NAME="$2"
    printf "Add credentials for system-assigned identity to task: ${TASK_NAME}..."
    if [[ 
        $(az acr task credential list --registry ${ACR_NAME} --name ${TASK_NAME} | jq '.["'${ACR_NAME}'.azurecr.io"].identity') == null ||
        -z $(az acr task credential list --registry ${ACR_NAME} --name ${TASK_NAME} | jq '.["'${ACR_NAME}'.azurecr.io"].identity')
    ]]; then
        # Add credentials for user-assigned identity to the task
        az acr task credential add \
            --name ${TASK_NAME} \
            --registry ${ACR_NAME} \
            --login-server ${ACR_NAME}.azurecr.io \
            --use-identity [system] \
            &>/dev/null
        printf " Done.\n"
    else
        printf " Credential exists.\n"
    fi
}

function run_task() {
    echo "run task..."
    REGISTRY_URL="${AZ_RESOURCE_CONTAINER_REGISTRY}.azurecr.io"
    IMAGE_NAME="edc2021-olmt-demo1-frontend"
    TAG="gaebu"
    IMAGE="${REGISTRY_URL}/${IMAGE_NAME}:${TAG}"
    CLUSTERTYPE_IMAGE="${REGISTRY_URL}/${IMAGE_NAME}:${CLUSTER_TYPE}-${TAG}"
    CLUSTERNAME_IMAGE="${REGISTRY_URL}/${IMAGE_NAME}:${CLUSTER_NAME}-${TAG}"
    DOCKER_FILE_NAME="Dockerfile"

    az acr task run \
        --name ${ACR_TASK_NAME} \
        --registry ${AZ_RESOURCE_CONTAINER_REGISTRY} \
        --set IMAGE=${IMAGE} \
        --set CLUSTERTYPE_IMAGE=${CLUSTERTYPE_IMAGE} \
        --set CLUSTERNAME_IMAGE=${CLUSTERNAME_IMAGE} \
        --set DOCKER_FILE_NAME=${DOCKER_FILE_NAME} \
        --set CONTEXT=${CONTEXT}

    echo "Done."
}


create_acr_task "${AZ_RESOURCE_ACR_TASK_NAME}" "${AZ_RESOURCE_CONTAINER_REGISTRY}"
create_acr_task "${AZ_RESOURCE_ACR_TASK_NAME}-no-push" "${AZ_RESOURCE_CONTAINER_REGISTRY}" "--no-push"

create_role_assignment "${AZ_RESOURCE_ACR_TASK_NAME}" "${AZ_RESOURCE_CONTAINER_REGISTRY}"
create_role_assignment "${AZ_RESOURCE_ACR_TASK_NAME}-no-push" "${AZ_RESOURCE_CONTAINER_REGISTRY}"

add_task_credential "${AZ_RESOURCE_ACR_TASK_NAME}" "${AZ_RESOURCE_CONTAINER_REGISTRY}"
add_task_credential "${AZ_RESOURCE_ACR_TASK_NAME}-no-push" "${AZ_RESOURCE_CONTAINER_REGISTRY}"

echo ""
echo "Done creating ACR Task."