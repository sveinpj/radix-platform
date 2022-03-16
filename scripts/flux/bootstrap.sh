#!/usr/bin/env bash

#######################################################################################
### PURPOSE
###

# Install flux in radix cluster.

#######################################################################################
### INPUTS
###

# Required:
# - RADIX_ZONE_ENV          : Path to *.env file
# - CLUSTER_NAME            : Ex: "test-2", "weekly-93"
# - GIT_REPO                : Ex: "ssh://git@github.com/equinor/radix-flux"
# - GIT_BRANCH              : Ex: "master"
# - GIT_DIR                 : Ex: "clusters/development"

# Optional:
# - USER_PROMPT             : Is human interaction is required to run script? true/false. Default is true.

#######################################################################################
### HOW TO USE
###

# Normal usage
# RADIX_ZONE_ENV=../radix-zone/radix_zone_dev.env CLUSTER_NAME="weekly-2" ./bootstrap.sh

# Configure a dev cluster to use custom configs
# RADIX_ZONE_ENV=../radix-zone/radix_zone_dev.env CLUSTER_NAME="weekly-2" OVERRIDE_GIT_BRANCH=my-test-configs OVERRIDE_GIT_DIR=my-test-directory ./bootstrap.sh

#######################################################################################
### DOCS
###

# - https://github.com/fluxcd/flux/tree/master/chart/flux
# - https://github.com/equinor/radix-flux/

#######################################################################################
### COMPONENTS
###

# - AZ keyvault
#     Holds git deploy key to config repo
# - Flux CRDs
#     The CRDs are no longer in the Helm chart and must be installed separately
# - Flux Helm Chart
#     Installs everything else

#######################################################################################
### START
###

echo ""
echo "Start installing Flux..."

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
hash flux 2>/dev/null || {
    echo -e "\nError: flux not found in PATH. Exiting..."
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

if [[ ! -z "$OVERRIDE_GIT_BRANCH" ]]; then
    GIT_BRANCH="$OVERRIDE_GIT_BRANCH"
fi

if [[ ! -z "$OVERRIDE_GIT_DIR" ]]; then
    GIT_DIR="$OVERRIDE_GIT_DIR"
fi

if [[ -z "$CLUSTER_NAME" ]]; then
    echo "Please provide CLUSTER_NAME" >&2
    exit 1
fi

if [[ -z "$GIT_REPO" ]]; then
    echo "Please provide GIT_REPO" >&2
    exit 1
fi

if [[ -z "$GIT_BRANCH" ]]; then
    echo "Please provide GIT_BRANCH" >&2
    exit 1
fi

if [[ -z "$GIT_DIR" ]]; then
    echo "Please provide GIT_DIR" >&2
    exit 1
fi

if [[ -z "$FLUX_VERSION" ]]; then
    echo "Please provide FLUX_VERSION" >&2
    exit 1
fi

# Optional inputs

if [[ -z "$USER_PROMPT" ]]; then
    USER_PROMPT=true
fi

# Flux vars

FLUX_PRIVATE_KEY_NAME="flux-github-deploy-key-private"
FLUX_PUBLIC_KEY_NAME="flux-github-deploy-key-public"
FLUX_DEPLOY_KEYS_GENERATED=false

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
echo -e "Install Flux v2 will use the following configuration:"
echo -e ""
echo -e "   > WHERE:"
echo -e "   ------------------------------------------------------------------"
echo -e "   -  RADIX_ZONE                       : $RADIX_ZONE"
echo -e "   -  CLUSTER_NAME                     : $CLUSTER_NAME"
echo -e ""
echo -e "   > WHAT:"
echo -e "   -------------------------------------------------------------------"
echo -e "   -  AZ_RESOURCE_KEYVAULT             : $AZ_RESOURCE_KEYVAULT"
echo -e "   -  GIT_REPO                         : $GIT_REPO"
echo -e "   -  GIT_BRANCH                       : $GIT_BRANCH"
echo -e "   -  GIT_DIR                          : $GIT_DIR"
echo -e "   -  FLUX_VERSION                     : $FLUX_VERSION"
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
    echo "Please set your kubectl current-context to be $CLUSTER_NAME"
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

printf "\nWorking on namespace..."
if [[ $(kubectl get namespace flux-system 2>&1) == *"Error"* ]];then
    kubectl create ns flux-system 2>&1 >/dev/null
fi
printf "...Done"

#######################################################################################
### CREDENTIALS
###

FLUX_PRIVATE_KEY="$(az keyvault secret show --name "$FLUX_PRIVATE_KEY_NAME" --vault-name "$AZ_RESOURCE_KEYVAULT")"
FLUX_PUBLIC_KEY="$(az keyvault secret show --name "$FLUX_PUBLIC_KEY_NAME" --vault-name "$AZ_RESOURCE_KEYVAULT")"

printf "\nLooking for flux deploy keys for GitHub in keyvault \"${AZ_RESOURCE_KEYVAULT}\"..."
if [[ -z "$FLUX_PRIVATE_KEY" ]] || [[ -z "$FLUX_PUBLIC_KEY" ]]; then
    printf "\nNo keys found. Start generating flux private and public keys and upload them to keyvault..."
    ssh-keygen -t ed25519 -N "" -C "radix@statoilsrm.onmicrosoft.com" -f id_ed25519."$RADIX_ENVIRONMENT" 2>&1 >/dev/null
    az keyvault secret set --file=./id_ed25519."$RADIX_ENVIRONMENT" --name="$FLUX_PRIVATE_KEY_NAME" --vault-name="$AZ_RESOURCE_KEYVAULT" 2>&1 >/dev/null
    az keyvault secret set --file=./id_ed25519."$RADIX_ENVIRONMENT".pub --name="$FLUX_PUBLIC_KEY_NAME" --vault-name="$AZ_RESOURCE_KEYVAULT" 2>&1 >/dev/null
    rm id_ed25519."$RADIX_ENVIRONMENT" 2>&1 >/dev/null
    rm id_ed25519."$RADIX_ENVIRONMENT".pub 2>&1 >/dev/null
    FLUX_DEPLOY_KEYS_GENERATED=true
    printf "...Done\n"
else
    printf "...Keys found."
fi

az keyvault secret download \
    --vault-name $AZ_RESOURCE_KEYVAULT \
    --name "$FLUX_PRIVATE_KEY_NAME" \
    --file "$FLUX_PRIVATE_KEY_NAME" \
    2>&1 >/dev/null

printf "...Done\n"

# Create secret for Flux v2 to use to authenticate with ACR.
printf "\nCreating k8s secret \"radix-docker\"..."
az keyvault secret download \
    --vault-name "$AZ_RESOURCE_KEYVAULT" \
    --name "radix-cr-cicd-${RADIX_ENVIRONMENT}" \
    --file sp_credentials.json \
        2>&1 >/dev/null

kubectl create secret docker-registry radix-docker \
    --namespace="flux-system" \
    --docker-server="radix$RADIX_ENVIRONMENT.azurecr.io" \
    --docker-username="$(jq -r '.id' sp_credentials.json)" \
    --docker-password="$(jq -r '.password' sp_credentials.json)" \
    --docker-email=radix@statoilsrm.onmicrosoft.com \
    --dry-run=client -o yaml |
    kubectl apply -f - \
        2>&1 >/dev/null
rm -f sp_credentials.json
printf "...Done\n"

# Create ConfigMap radix-flux-config which will provide values for flux deployments
echo "Creating \"radix-flux-config\"..."

# list of public ips assigned to the cluster
printf "\nGetting list of public ips assigned to $CLUSTER_NAME..."
ASSIGNED_IPS="$(az network public-ip list \
    --query "[?ipConfiguration.resourceGroup=='MC_${AZ_RESOURCE_GROUP_CLUSTERS}_${CLUSTER_NAME}_${AZ_INFRASTRUCTURE_REGION}'].ipAddress" \
    --output json)"

if [[ "$ASSIGNED_IPS" == "[]" ]]; then
    echo "ERROR: Could not find Public IP of cluster."
else
    # Loop through list of IPs and create a comma separated string. 
    for ipaddress in $(echo $ASSIGNED_IPS | jq -cr '.[]')
    do
        if [[ -z $IP_LIST ]]; then
            IP_LIST=$(echo $ipaddress)
        else
            IP_LIST="$IP_LIST,$(echo $ipaddress)"
        fi
    done
    printf "...Done\n"
fi

printf "\nGetting Slack Webhook URL..."
SLACK_WEBHOOK_URL="$(az keyvault secret show --vault-name $AZ_RESOURCE_KEYVAULT --name slack-webhook-$RADIX_ZONE | jq -r .value)"
printf "...Done\n"

IMAGE_REGISTRY="${AZ_RESOURCE_CONTAINER_REGISTRY}.azurecr.io"

# Create configmap for Flux v2 to use for variable substitution. (https://fluxcd.io/docs/components/kustomize/kustomization/#variable-substitution)
printf "Deploy \"radix-flux-config\" configmap in flux-system namespace..."
cat <<EOF >radix-flux-config.yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: radix-flux-config
  namespace: flux-system
data:
  dnsZone: "$AZ_RESOURCE_DNS"
  appAliasBaseURL: "app.$AZ_RESOURCE_DNS"
  prometheusName: radix-stage1
  imageRegistry: "$IMAGE_REGISTRY"
  clusterName: "$CLUSTER_NAME"
  clusterType: "$CLUSTER_TYPE"
  activeClusterIPs: "$IP_LIST"
  slackWebhookURL: "$SLACK_WEBHOOK_URL"
EOF

kubectl apply -f radix-flux-config.yaml 2>&1 >/dev/null
rm radix-flux-config.yaml
printf "...Done.\n"

#######################################################################################
### INSTALLATION

echo ""
echo "Starting installation of Flux..."

flux bootstrap git \
    --private-key-file="$FLUX_PRIVATE_KEY_NAME" \
    --url="$GIT_REPO" \
    --branch="$GIT_BRANCH" \
    --path="$GIT_DIR" \
    --components-extra=image-reflector-controller,image-automation-controller \
    --version="$FLUX_VERSION" \
    --silent
echo "done."

rm "$FLUX_PRIVATE_KEY_NAME"

echo -e ""
echo -e "A Flux service has been provisioned in the cluster to follow the GitOps way of thinking."

if [ "$FLUX_DEPLOY_KEYS_GENERATED" = true ]; then
    FLUX_DEPLOY_KEY_NOTIFICATION="*** IMPORTANT ***\nPlease add a new deploy key in the radix-flux repository (https://github.com/equinor/radix-flux/settings/keys) with the value from $FLUX_PUBLIC_KEY_NAME secret in $AZ_RESOURCE_KEYVAULT Azure keyvault."
    echo ""
    echo -e "${__style_yellow}$FLUX_DEPLOY_KEY_NOTIFICATION${__style_end}"
    echo ""
fi

#######################################################################################
### END
###

echo "Bootstrap of Flux is done!"
echo ""
