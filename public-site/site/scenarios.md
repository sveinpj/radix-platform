---
title: Scenarios and examples
layout: document
toc: true
---

On this page you will find scenarios describing different app structures.
For each scenario you can find example code for at least one programming language. The code is meant to give you an idea of how your project should look when deploying it to the radix platform. The examples is also a way for you to try out the platform, simply [clone](https://git-scm.com/docs/git-clone) or copy the code to your own repository and follow the instructions on the TODO: getting-started page.

**If there are no examples for your programming language:** Note that the main difference between all the examples is in the ''radixconfig'' and ''Dockerfiles'', so you might still find these files and the project structures useful

----

### Scenario - 1

App with ''one'' container. No external back end dependencies. No storage. No secrets. Static/Dynamic web page

Examples : 
  * <del>https://github.com/larskaare/radix-test1</del>
  * [React.js](https://github.com/Statoil/radix-example-scenario-1-reactjs) 
  * [Static html](https://github.com/Statoil/radix-example-scenario-1-html)
  * [.NET core](https://github.com/Statoil/radix-example-scenario-1-dotnet)

<del>Github static file repository/url : https://github.com/Statoil/radix-example-static-html</del>

----

### Scenario - 2

App with ''multiple'' containers. No external dependencies. No back end dependencies. No storage. No secrets. Static/Dynamic web page

Examples:

Alt 1: Reverse proxy:
  * [Golang](https://github.com/Statoil/radix-example-scenario-2-golang)
  * [React.js](https://github.com/Statoil/radix-example-scenario-2-chat)
  * [.NET core](https://github.com/Statoil/radix-example-scenario-2-dotnet)
   

Alt 2: Two separate endpoints into app

Alt 3: [Dynamic web page storing requests in redis cache](https://github.com/Statoil/radix-example-redis-cache)

Alt 4: [Load balanced scaled dynamic web page running in 4 instances, storing requests in a redis cache](https://github.com/Statoil/radix-example-loadbalancer-api-db)

----

### Scenario - 3

App with ''one'' container. ''Reading from external open API''. No storage. No secrets. Dynamic web page - including information from external API.

Examples : 
  * [React.js](https://github.com/Statoil/radix-example-scenario-3-reactjs)
  * [https://github.com/statoil/radix-example-scenario-3-dotnet](.NET core)

----

### Scenario - 4

App with ''two'' containers. ''Reading from external open API''. No storage. No secrets. Dynamic web page - including information from external API.

Examples : 
  * [Golang: Go + Nginx](https://github.com/Statoil/radix-example-scenario-4-golang)
  * [Python: Django + PostgresSQL](https://github.com/Statoil/radix-example-scenario-4-webapp)

----

### Scenario - 5
Same as Scenario 1 - adding ''metrics - monitoring'' to the app using Prometheus and Grafana

Examples: 
  * [Node.js](https://github.com/Statoil/radix-example-scenario-5-nodejs)
  * [Golang](https://github.com/Statoil/radix-example-scenario-5-golang)

----

### Scenario - 6
Same as Scenario 1 - adding ''running unit tests as part of multistage docker build''. Broken tests fail build.

Examples : 
  * [Python](https://github.com/Statoil/radix-example-scenario-6-python)
  * [React.js](https://github.com/Statoil/radix-example-scenario-6-reactjs)
  * [.NET core](https://github.com/Statoil/radix-example-scenario-6-dotnet)

----

### Scenario - 7
Same as Scenario 1 - adding ''running linter and unit tests as part of multistage docker build''. Broken tests fail build.

Examples:
  * [Golang](https://github.com/Statoil/radix-example-scenario-7-golang)
  * [Python](https://github.com/Statoil/radix-example-scenario-7-python)
  * [React.js](https://github.com/Statoil/radix-example-scenario-7-reactjs)
  * [docker-multistage-with-test](https://github.com/larskaare/radix-test-scenario-docker-multistage-with-test)

----

### Scenario - 8
The platform does **not** currently support ''secrets''.


App with two container. Reading from external ''restricted'' API. No storage. ''Secrets''. Dynamic web page - including information from external API.

Alt 1: web app from mobile team, integrating with graph api and azure storage account - <del>https://github.com/Statoil/radix-example-mad-webpage</del>

Alt 2: Examples
  * [docker-multistage-with-test](https://github.com/larskaare/radix-test-scenario-docker-multistage-with-test)