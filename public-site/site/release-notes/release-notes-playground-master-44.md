---
title: Release Notes - playground-master-44
layout: document
toc: true
---

Release: `playground-master-44`  
Version: `f7f42a581f455c02b7f52e93a98702d83dd5e99e`  
Channel: weekly

Release for week 44 in weekly [channel]({% link releases.md %}).

## Shortcuts
* [Web console](https://web-radix-web-console-prod.playground-master-44.dev.radix.equinor.com)


## New
* Story OR-129, Prepare for scaling. Default to 2 pods for each "components"

## Improvements
* Added auditing for cluster (azure logs)

## Fixes
* Bug OR-182, Pipeline should create namespaces for all environments in the config, if not already there
* Bug	OR-186, Name of our environment variables should be “radix-clustername” and “radix-environment”
* Bug	OR-202, Add logging to trigger pipeline job to see what is sent from webhook


## Known issues
* The Friday Night Killer is still active. Applications might be murdered this coming friday.

## Ops
* Kubernetes version 1.11.3
  