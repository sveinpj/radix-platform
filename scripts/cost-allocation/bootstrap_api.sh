
#######################################################################################
### PURPOSE
###

# Bootstrap requirements for radix-cost-allocation-api in a radix cluster

#######################################################################################
### PRECONDITIONS
###

# - AKS cluster is available
# - User has role cluster-admin

#######################################################################################
### INPUTS
###

# Required:
# - RADIX_ZONE_ENV               : Path to *.env file

# Optional:
# - USER_PROMPT                  : Is human interaction required to run script? true/false. Default is true.
# - REGENERATE_SQL_PASSWORD      : Should existing password for SQL login be regenerated and stored in KV? true/false. default is false

#######################################################################################
### HOW TO USE
###

# NORMAL
# RADIX_ZONE_ENV=../radix-zone/radix_zone_dev.env ./bootstrap_api.sh

# Generate and store new SQL user password - new password is stored in KV and updated for SQL user
# The SQL_PASSWORD secret for radix-cost-allocation-api app in Radix must be updated and restarted
# RADIX_ZONE_ENV=../radix-zone/radix_zone_dev.env REGENERATE_SQL_PASSWORD=true ./bootstrap_api.sh

#######################################################################################
### START
###

echo ""
echo "Start bootstrap of radix-cost-allocation-api... "

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
hash sqlcmd 2>/dev/null || {
    echo -e "\nERROR: sqlcmd not found in PATH. Exiting... " >&2
    exit 1
}
printf "All is good."
echo ""

#######################################################################################
### Set default values for optional input
###

USER_PROMPT=${USER_PROMPT:=true}

REGENERATE_SQL_PASSWORD=${REGENERATE_SQL_PASSWORD:-false}

#######################################################################################
### Read inputs and configs
###

# Required inputs

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

case $REGENERATE_SQL_PASSWORD in
    true|false) ;;
    *)
        echo 'ERROR: REGENERATE_SQL_PASSWORD must be true or false' >&2
        exit 1
        ;;
esac

# Load dependencies
LIB_AZURE_SQL_FIREWALL_PATH="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )/../azure-sql/lib_firewall.sh"
if [[ ! -f "$LIB_AZURE_SQL_FIREWALL_PATH" ]]; then
   echo "ERROR: The dependency LIB_AZURE_SQL_FIREWALL_PATH=$LIB_AZURE_SQL_FIREWALL_PATH is invalid, the file does not exist." >&2
   exit 1
else
   source "$LIB_AZURE_SQL_FIREWALL_PATH"
fi

LIB_AZURE_SQL_SECURITY_PATH="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )/../azure-sql/lib_security.sh"
if [[ ! -f "$LIB_AZURE_SQL_SECURITY_PATH" ]]; then
   echo "ERROR: The dependency LIB_AZURE_SQL_SECURITY_PATH=$LIB_AZURE_SQL_SECURITY_PATH is invalid, the file does not exist." >&2
   exit 1
else
   source "$LIB_AZURE_SQL_SECURITY_PATH"
fi

#######################################################################################
### Prepare az session
###

printf "Logging you in to Azure if not already logged in... "
az account show >/dev/null || az login >/dev/null
az account set --subscription "$AZ_SUBSCRIPTION_ID" >/dev/null
printf "Done.\n"

#######################################################################################
### Ask user to verify inputs and az login
###

echo -e ""
echo -e "Bootstrap Radix Cost Allocation API with the following configuration:"
echo -e ""
echo -e "   > WHERE:"
echo -e "   ------------------------------------------------------------------"
echo -e "   -  AZ_RESOURCE_KEYVAULT              : $AZ_RESOURCE_KEYVAULT"
echo -e "   -  COST_ALLOCATION_SQL_SERVER_NAME   : $COST_ALLOCATION_SQL_SERVER_NAME"
echo -e "   -  COST_ALLOCATION_SQL_DATABASE_NAME : $COST_ALLOCATION_SQL_DATABASE_NAME"
echo -e ""
echo -e "   > WHAT:"
echo -e "   ------------------------------------------------------------------"
echo -e "   -  REGENERATE_SQL_PASSWORD           : $REGENERATE_SQL_PASSWORD"
echo -e ""
echo -e "   > WHO:"
echo -e "   -------------------------------------------------------------------"
echo -e "   -  AZ_SUBSCRIPTION                   : $(az account show --query name -otsv)"
echo -e "   -  AZ_USER                           : $(az account show --query user.name -o tsv)"
echo -e ""

if [[ $USER_PROMPT == true ]]; then
    while true; do
        read -p "Is this correct? (Y/n) " yn
        case $yn in
            [Yy]* ) echo ""; break;;
            [Nn]* ) echo ""; echo "Quitting."; exit 1;;
            * ) echo "Please answer yes or no.";;
        esac
    done
fi

#######################################################################################
### Get/generate password for database user and create/update user in Azure SQL Database
###

echo "Generate password for API SQL user and store in KV"

generate_password_and_store $AZ_RESOURCE_KEYVAULT $KV_SECRET_COST_ALLOCATION_DB_API $REGENERATE_SQL_PASSWORD || exit

API_SQL_PASSWORD=$(az keyvault secret show --vault-name "$AZ_RESOURCE_KEYVAULT" --name $KV_SECRET_COST_ALLOCATION_DB_API | jq -r .value)
ADMIN_SQL_PASSWORD=$(az keyvault secret show --vault-name "$AZ_RESOURCE_KEYVAULT" --name $KV_SECRET_COST_ALLOCATION_SQL_ADMIN | jq -r .value) 

if [[ -z $ADMIN_SQL_PASSWORD ]]; then
    printf "ERROR: SQL admin password not set" >&2
    exit 1
fi

echo "Whitelist IP in firewall rule for SQL Server"
whitelistRuleName="ClientIpAddress_$(date +%Y%m%d%H%M%S)"

add_local_computer_sql_firewall_rule \
    $COST_ALLOCATION_SQL_SERVER_NAME \
    $AZ_RESOURCE_GROUP_COST_ALLOCATION_SQL \
    $whitelistRuleName \
    || exit

echo "Creating/updating SQL user for Radix Cost Allocation API"
create_or_update_sql_user \
    $COST_ALLOCATION_SQL_SERVER_FQDN \
    $COST_ALLOCATION_SQL_ADMIN_LOGIN \
    $ADMIN_SQL_PASSWORD \
    $COST_ALLOCATION_SQL_DATABASE_NAME \
    $COST_ALLOCATION_SQL_API_USER \
    $API_SQL_PASSWORD \
    "datareader"

echo "Remove IP in firewall rule for SQL Server"
delete_sql_firewall_rule \
    $COST_ALLOCATION_SQL_SERVER_NAME \
    $AZ_RESOURCE_GROUP_COST_ALLOCATION_SQL \
    $whitelistRuleName \
    || exit

echo "Done."