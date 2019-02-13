---
title: The radixconfig.yaml file
layout: document
parent: ['Docs', '../../docs.html']
toc: true
---

# Overview 

In order for Radix to configure your application it needs the a configuration file. This must be placed in the root of your app repository and be named `radixconfig.yaml`. The file is expected in YAML or JSON format (in either case, it must have the `.yaml` extension).

> Radix only reads `radixconfig.yaml` from the `master` branch. If the file is changed in other branches, those changes will be ignored.

The basic format of the file is this; the configuration keys are explained in the Reference section below:

```yaml
apiVersion: radix.equinor.com/v1
kind: RadixApplication
metadata: ...
spec: ...
```

# Reference

## `name`

```yaml
apiVersion: radix.equinor.com/v1
kind: RadixApplication
metadata:
  name: myapp
spec:
```

`name` needs to match the name given in when registering an application.

## `environments`

```yaml
spec:
  environments:
    - name: dev
      build:
        from: master
    - name: prod
      build:
        from: release
```

The `environments` section of the spec lists the environments for the application and the branch each environment will build from. If you omit the `build.from` key for the environment, no automatic builds or deployments will be created. This configuration is useful for a promotion-based [workflow](../../guides/workflows).

## `components`

```yaml
spec:
  components:
    - name: frontend
      src: frontend
      ports:
      - name: http
        port: 80
    - name: backend
      src: backend
      replicas: 2
      ports:
      - name: http
        port: 5000
```

This is where you specify the various components for your application — it needs at least one. Each component needs a `name`; this will be used for building the Docker images (appName-componentName). It needs a `src`, which is the folder (relative to the repository root) where the `Dockerfile` of the component can be found and used for building on the platform. It needs a list of `ports` exposed by the component, which map with the ports exposed in the `Dockerfile`. `replicas` can be used to [horizontally scale](https://en.wikipedia.org/wiki/Scalability#Horizontal_and_vertical_scaling) the component. If `replicas` is not set it defaults to `1`.

### `public`

```yaml
spec:
  components:
    - name: frontend
      public: true
```

The `public` field of a component, if set to `true`, is used to make the component accessible on the internet by generating a public endpoint. Any component without `public: true` can only be accessed from another component in the app.

### `monitoring`

```yaml
spec:
  components:
    - name: frontend
      monitoring: true
```

The `monitoring` field of a component, if set to `true`, is used to expose custom application metrics in the Radix monitoring dashboards. It is expected that the component provides a `/metrics` endpoint: his will be queried periodically (every five seconds) by an instance of [Prometheus](https://prometheus.io/) running within Radix. General metrics, such as resource usage, will always be available in monitors, regardless of this being set.

### `resources`

```yaml
spec:
  components:
    - name: frontend
      resources:
        requests:
          memory: "64Mi"
          cpu: "100m"
        limits:
          memory: "128Mi"
          cpu: "200m"
```

The `resources` section of a component can specify how much CPU and memory each component needs. `resources` is used to ensure that each component is allocated enough resources to run as it should. `limits` describes the maximum amount of compute resources allowed. `requests` describes the minimum amount of compute resources required. If `requests` is omitted for a component it defaults to the settings in `limits`. If `limits` is omitted, its value defaults to an implementation-defined value. [More info](https://kubernetes.io/docs/concepts/configuration/manage-compute-resources-container/)

### `environmentVariables`

```yaml
spec:
  components:
    - name: backend
      environmentVariables:
        - environment: dev
          variables:
            DB_HOST: "db-dev"
            DB_PORT: "1234"
        - environment: prod
          variables:
            DB_HOST: "db-prod"
            DB_PORT: "9876"
```

An array of objects containing the `environment` name and variables to be set in the component.

Environment variables are defined per Radix environment. By default, each application container will have the following default environment variables.

- RADIX_APP
- RADIX_CLUSTERNAME
- RADIX_CONTAINER_REGISTRY
- RADIX_COMPONENT
- RADIX_ENVIRONMENT
- RADIX_DNS_ZONE
- RADIX_PORTS (only available if `ports` are set)
- RADIX_PORT_NAMES (only available if `ports` are set)
- RADIX_PUBLIC_DOMAIN_NAME (if `component.public: true`)

### `secrets`

```yaml
spec:
  components:
    - name: backend
      secrets:
        - DB_PASS
```

The `secrets` key contains a list of names. Values for these can be set via the Radix Web Console (under each active component within an environment). Each secret must be set on all environments. Secrets are available in the component as environment variables; a component will not be able to start without the secret being set.

## `dnsAppAlias`

```yaml
spec:
  dnsAppAlias:
    environment: prod
    component: frontend
```

As a convenience for nicer URLs, `dnsAppAlias` creates a DNS alias in the form of `<app-name>.app.radix.equinor.com` for the specified environment and component.

In the example above, the component **frontend** hosted in environment **prod** will be accessible from `myapp.app.radix.equinor.com`, in addition to the default endpoint provided for the frontend component, `frontend-myapp-prod.<clustername>.dev.radix.equinor.com`.

# Example `radixconfig.yaml` file

This example showcases all options; in many cases the defaults will be a good choice instead.

```yaml
apiVersion: radix.equinor.com/v1
kind: RadixApplication
metadata:
  name: myapp
spec:
  environments:
    - name: dev
      build:
        from: master
    - name: prod
  components:
    - name: frontend
      src: frontend
      ports:
       - name: http
         port: 80
      public: true
      monitoring: true
      resources: 
        requests: 
          memory: "64Mi"
          cpu: "100m"
        limits: 
          memory: "128Mi"
          cpu: "200m"
    - name: backend
      src: backend
      replicas: 2
      ports:
        - name: http
          port: 5000
      environmentVariables:
        - environment: dev
          variables:
            DB_HOST: "db-dev"
            DB_PORT: "1234"
        - environment: prod
          variables:
            DB_HOST: "db-prod"
            DB_PORT: "9876"
      secrets:
        - DB_PASS
  dnsAppAlias:
    environment: prod
    component: frontend
```