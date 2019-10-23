#!/bin/bash

# Set alias script vars
export RADIX_APP_CNAME="prometheus.$CLUSTER_NAME.$RADIX_ZONE_NAME"  # The CNAME you want to create an alias for
export RADIX_APP_ALIAS_NAME="prometheus"                            # The name of the alias
export RADIX_APP_NAME="prometheus"                                  # The name of the app in the cluster
export RADIX_NAMESPACE="default"                                    # Ovverided namespace
export RADIX_APP_COMPONENT="prometheus-operator-prometheus"         # The component which should receive the traffic
export RADIX_APP_COMPONENT_PORT="9090"
