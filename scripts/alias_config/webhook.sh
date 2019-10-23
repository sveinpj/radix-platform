#!/bin/bash

# Set alias script vars
export RADIX_APP_CNAME="webhook-radix-github-webhook-prod.$CLUSTER_NAME.$RADIX_ZONE_NAME"    # The CNAME you want to create an alias for
export RADIX_APP_ALIAS_NAME="webhook"                                                        # The name of the alias
export RADIX_APP_NAME="radix-github-webhook"                                                 # The name of the app in the cluster
unset RADIX_NAMESPACE                                                                        # Use the radix app environment
export RADIX_APP_COMPONENT="webhook"                                                         # The component which should receive the traffic
export RADIX_APP_COMPONENT_PORT="3001"
