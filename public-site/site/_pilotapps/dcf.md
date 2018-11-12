---
title: DCF (Digital Cargo Files)
layout: document
parent: ['Documentation', '../documentation.html']
toc: true
---

DCF (Digital Cargo Files) is a mature project built using Java Spring Boot, AngularJS, ElasticSearch, and backed up by an Oracle DB (via Hibernate). It was chosen as a pilot for Radix due to it representing a common class of applications that we would like to be built and deployed in the platform.

The objective for the pilot was to validate the process of building and deploying this type of application, discover typical pain points, and codify best practices for future migrations into Radix.

## Summary

This is the first Java application we attempted to Dockerise and run in Radix. We:

  * evaluated the best-suited Docker base images,
  * resolved Java dependencies for building in an external network,
  * resolved front-end dependencies,
  * untangled the build order between front-end and back-end,
  * tried to optimise the Docker build, and
  * created a deployable Docker image.

The remainder of this document goes into detail on these steps.

## Overview of the project

DCF is currently stored in BitBucket; the first step was to clone the repository into GitHub (currently we only build from GitHub, but this might change).

The interesting parts of the application are organized like this:

```
dcf/
  ├ dcf-client/  <i>(Web front-end)</i>
  │   ├ Client/  <i>(Source code: HTML, CSS, JS)</i>
  │   ├ gulpfile.js  <i>(Build script for frontend)</i>
  │   ├ pom.xml  <i>(Maven)</i>
  │   └ package.json  <i>(Dependencies, managed by Yarn)</i>
  │
  └ dcf-spring/
      ├ src/  <i>(The Java sauce)</i>
      ├ pom.xml <i>(Dependencies, managed by Maven)</i>
      └ frontend.sh <i>(Triggers front-end build; copies artifacts to <b>src/main/resources/static/</b></i>
```

Constraints: - We cannot pull or connect to internal systems right now due to firewalls rules.

Observations: - The build and run instructions in the repo were a bit outdated, or maybe just autogenerated. The DCF team were really helpful in providing us with any information or necessary changes throughout this pilot!

## First iteration

We will be following a rough [[http://wiki.c2.com/?MakeItWorkMakeItRightMakeItFast|Make it Work, Make it Right, Make it Fast pattern]].

### Base image 

We start off by choosing a [[https://docs.docker.com/get-started/part2/#build-the-app|base image]] for our own build. The naming syntax of the OpenJDK images is: `openjdk:(version)-(jre|jdk)-(baseimage)?`. So for example the image `openjdk:8-jdk-slim` is Java 8 with JDK based on Debian Stretch (9) Slim.

### Base base image

The OpenJDK base images also build on top of other base images. OpenJDK has a few different variants depending on our needs. The most used base images used in OpenJDK:

  * No specific base image, the default based on Debian
  * `slim` - A minimal installation based on Debian Slim
  * `alpine` - An miniscule installation based on Alpine Linux. **Only available for Java 7 and 8**

Here is a quick comparison of the image sizes for the different base images on Java8 JDK: - openjdk:8-jdk **726MB** - openjdk:8-jdk-slim **244MB** - openjdk:8-jdk-alpine **102MB**

> **Protip** It is considered good practice to use the smallest images that satisfies your needs. It can drastically shorten build and deployment and when using continous integration and deployment with multiple builds a day it can be a real time saver.
> 
> **PS** But also be aware that the smaller images have things left out so for example `slim` uses the `-headless` OpenJDK package and lacks any UI libraries. Which for most servers should not be any problem. Here is what OpenJDK writes about the`alpine` variant:
> 
> //The main caveat to note is that it does use musl libc instead of glibc and friends, so certain software might run into issues depending on the depth of their libc requirements. However, most software doesn’t have an issue with this, so this variant is usually a very safe choice.//

### Java version

On https:%%//%%hub.docker.com/_/openjdk/ some of the latest available Java versions are - 11-ea-9 (aliases: 11-ea, 11) - 10.0.1-10 (aliases: 10.0.1, 10.0, 10) - 9.0.4-12 (aliases: 9.0.4, 9.0, 9) - 8u162 (aliases: 8) - 7u171 (aliases: 7)

### Extra utilities

But we also need Maven (`mvn`) to actually build our project. Normally we would configure some Debian apt repositories to pull down any software we need for the build process, but in the case of Maven there are official Docker images using the OpenJDK images as their base image, and Maven installed on top.

Maven follows the same naming scheme as it’s “parent” OpenJDK: - maven:3.5.3-jdk-11 - maven:3.5.3-jdk-10 - maven:3.5.3-jdk-9 - maven:3.5.3-jdk-8 - maven:3.5.3-jdk-7

### Deciding on base image

After consulting `dcf/dcf-spring/pom.xml` and finding the Java version:

```xml
<properties>
    <java.version>1.8</java.version>
    ...
</properties>
```

We continue forward using the **`maven:3.5.3-jdk-8-slim`** base image.

### Making the Dockerfile

A Dockerfile is a script for creating automated builds of Docker images. For our purposes we are trying to create a Docker image with the built DCF application, ready to deploy into the Radix cluster.

[[http://engineering.hipolabs.com/understand-docker-without-losing-your-shit/#creatingadockerfile|Quick info on Dockerfiles, images, and containers]]

We want to build a Docker image and run it (in a container) with the DCF code within it. The image will have all the requirements to trigger the build. When the image is eventually built, and the DCF code is on our local disk on `D:/bitbucket/dcf/` (yes, this also works on Windows 😀), we could simply write:

```
docker run -v D:/bitbucket/dcf:/src <name-of-docker-image>
```

This will mount `D:/bitbucket/dcf/` to `/src` inside the container. **PS:** The directory is __mounted__, which means any changes you make to `/src` inside the container ALSO affect the files in `D:/bitbucket/dcf/`. Assuming the image works correctly the code is built within the container and the application starts up. We don’t have such an image yet, so we need to write the Dockerfile.

When making a Dockerfile for software I have not built before I prefer to start with the base image and jump into the container and execute commands in a command line. Since there is bound to be lots of unknown behaviour and nuances it’s quicker to iterate that way.

```sh
docker run -v D:/bitbucket/dcf:/src -it maven:3.5.3-jdk-8-slim bash
```

Using `maven:3.5.3-jdk-8-slim` as the base image, we’ll issue commands (and write them down) until we can build the code in `/src` correctly. When it all works, we’ll transfer those commands into our Dockerfile and create our own image.

### Building with Maven

So, within the container we just started, we try:

```sh
cd /src/dcf
sh build.sh
```

This triggers the Maven build, which eventually fails with:

```
[ERROR] Failed to execute goal on project dcf-spring: Could not resolve dependencies for project com.statoil.tops.dcf:dcf-spring:jar:0.0.1-SNAPSHOT: Failed to collect dependencies at com.statoil:jefutil:jar:3.1: Failed to read artifact descriptor for com.statoil:jefutil:jar:3.1: Could not transfer artifact com.statoil:jefutil:pom:3.1 from/to public (http://st-icinga.st.statoil.no/nexus/content/groups/public): st-icinga.st.statoil.no: Name or service not known: Unknown host st-icinga.st.statoil.no: Name or service not known
```

It fails to download the `jefutil` dependency from st-icingia.st.statoil.no (The Nexus Repo). This is because we are running everything from a perspective of the cloud ☁️, outside the trusted statoil.no netork.

We talked to the DCF team and most of the dependencies hosted on The Nexus Repo were simply outside packages hosted inside to avoid dealing with Statoils proxy servers and firewalls. This means that with a bit of work we could have a build referencing mostly outside repos.

But for now we are playing fast and loose! So we copied all the dependencies into a new `lib` folder in the git repo. See appendix A for the layout of the dependencies.

There is also a couple of actually internal packages which we discussed with the DCF team and concluded for now would be acceptable to just host in the git repo together with the rest of the code.

We copy the dependencies into `/root/.m2/repository/` where maven will hopefully pick them up.

```
mkdir -p /root/.m2/repository/
cp -r /src/dcf/lib/* /root/.m2/repository/

cd /src/dcf
sh build.sh
```

Still fails. We then comment out all `<repository></repository>` blocks in `dcf/pom.xml` referencing anything `*.statoil.no`.

```sh
sh build.sh
```

Still fails.

```
[ERROR] Failed to execute goal on project dcf-spring: Could not resolve dependencies for project com.statoil.tops.dcf:dcf-spring:jar:0.0.1-SNAPSHOT: Could not find artifact javax.jms:jms:jar:1.1 in local-repo (file:///src/dcf/../repository), try downloading from http://java.sun.com/products/jms/docs.html
```

After a bit of Googling, the internet says that adding this to `dcf/pom.xml` might help:

```xml
 <repository>
     <id>repository.jboss.org-public</id>
     <name>JBoss.org Maven repository</name>
     <url>https://repository.jboss.org/nexus/content/groups/public</url>
 </repository>
```
Once more, `sh build.sh`…

```
[INFO] DCF 0.0.1-SNAPSHOT ................................. SUCCESS [  4.526 s]
[INFO] dcf_client ......................................... SUCCESS [ 10.852 s]
[INFO] dcf_Spring 0.0.1-SNAPSHOT .......................... SUCCESS [15:16 min]
[INFO] ------------------------------------------------------------------------
[INFO] BUILD SUCCESS
```

**However**, this should **NOT** actually succeed yet. The `build.sh` script references `frontend.sh` which builds the HTML/CSS/JS frontend.

We added the prefix “build.sh” to all log lines so that we can grep on them in the otherwise 100,000 line output. And now running `sh build.sh` gave a few hints that I originally did not pay attention to:

```
root@951743b62fae:/src/dcf# sh build.sh
: not found: build.sh:
build.sh Build and copy repos
build.sh: 9: cd: can't cd to dcf-spring/
```

After messing around a bit I tried `./build.sh` instead:

```
root@951743b62fae:/src/dcf# ./build.sh
bash: ./build.sh: /bin/sh^M: bad interpreter: No such file or directory
```

So, incorrect line encodings somehow got in and prevented the correct interpreter to be used. Just learned that `git` will convert line ending automatically by default when pulling and this can be disabled with `git config --global core.autocrlf false`

We change from CRLF to LF line endings using VS Code in both `build.sh` and `frontend.sh` and try again. It should still fail since we are missing `yarn` and `gulp` in the Docker image, which are called by the script:

```
[INFO] BUILD SUCCESS
```

Turns out the calls to `gulp` and `yarn` do fail, but the shell script continues anyway onto the next line when a command fails (anyone recalls [[https://stackoverflow.com/questions/2202869/what-does-the-on-error-resume-next-statement-do|`on error resume next`]]?). To avoid this behaviour we add `set -e` to the top of our scripts, `build.sh` and `frontend.sh` and try again:

```
./frontend.sh: line 11: gulp: command not found
```

Mkay!

### Installing nodejs, yarn, gulp

Here is a list of commands to install nodejs, yarn and gulp.

```
apt-get update && apt-get -y install apt-transport-https gpg
curl -sL https://deb.nodesource.com/setup_9.x | bash -
apt-get install -y nodejs

curl -sS https://dl.yarnpkg.com/debian/pubkey.gpg | apt-key add -
echo "deb https://dl.yarnpkg.com/debian/ stable main" | tee /etc/apt/sources.list.d/yarn.list
apt-get update && apt-get -y install yarn bash gnupg wget
npm install gulp 
# Or: 
yarn global add gulp
```
> **PS: Downloading a shell script and piping it to bash (as root!) is generally considered a VERY bad idea from a security perspective. But unfortunately it’s the official supported way of installing nodejs, believe it or not. We do have a bit more control since we are running this inside a Docker container but it’s a pattern to avoid if possible.**

Trying again:

```
root@951743b62fae:/src/dcf# sh build.sh
frontend.sh Compile project
internal/modules/cjs/loader.js:550
    throw err;
```
Looks like the npm dependencies are missing, let’s download them:

```
cd dcf-client/
yarn install
```
This fails:

```
error /src/dcf/dcf-client/node_modules/phantomjs: Command failed.
```
PhantomJS needs to be installed on the system, but unfortunately I have not found a Debian package/repository for it. Here is how we download and install it manually:

```
export PHANTOM_JS="phantomjs-1.9.8-linux-x86_64"
wget https://bitbucket.org/ariya/phantomjs/downloads/$PHANTOM_JS.tar.bz2
tar xvjf $PHANTOM_JS.tar.bz2
rm $PHANTOM_JS.tar.bz2
mv $PHANTOM_JS /usr/local/share
ln -sf /usr/local/share/$PHANTOM_JS/bin/phantomjs /usr/local/bin
phantomjs --version
```
`yarn install` fails again:

```
gyp ERR! stack Error: not found: make
```
We need `build-essential`

```
apt-get install -y build-essential
```
And we try again:

```
root@951743b62fae:/src/dcf# sh build.sh

[ERROR] Failed to execute goal on project dcf-spring: Could not resolve dependencies for project com.statoil.tops.dcf:dcf-spring:jar:0.0.1-SNAPSHOT: Could not find artifact com.statoil.tops.dcf:dcf-client:jar:0.0.1-SNAPSHOT in repository.jboss.org-public (https://repository.jboss.org/nexus/content/groups/public)
```
It’s looking for the frontend jar file. We haven’t been able to figure out how this gets built today so we just build it manually.

```
cd /src/dcf/dcf-client/
mvn package
```
And we try again:

```
root@951743b62fae:/src/dcf# sh build.sh
[INFO] BUILD SUCCESS
```
Woop woop!

## Second iteration — single Docker image

Now that we have all the commands necessary to build the application we can create a Dockerfile that allows us to re-build it repeatably whenever we make changes to the code, and get a platform universal image without external dependencies that we can deploy anywhere.

Here is a Dockerfile that builds successfully:

```
FROM maven:3.5.3-jdk-8-slim

COPY . /src/
COPY ./dcf/lib/ /root/.m2/repository/

RUN apt-get update && apt-get -y install apt-transport-https gpg
RUN curl -sL https://deb.nodesource.com/setup_9.x | bash -
RUN apt-get install -y nodejs

RUN curl -sS https://dl.yarnpkg.com/debian/pubkey.gpg | apt-key add -
RUN echo "deb https://dl.yarnpkg.com/debian/ stable main" | tee /etc/apt/sources.list.d/yarn.list
RUN apt-get update && apt-get -y install yarn bash gnupg wget
RUN npm install gulp
RUN yarn global add gulp

ENV PHANTOM_JS="phantomjs-1.9.8-linux-x86_64"

RUN wget https://bitbucket.org/ariya/phantomjs/downloads/$PHANTOM_JS.tar.bz2
RUN tar xvjf $PHANTOM_JS.tar.bz2
RUN rm $PHANTOM_JS.tar.bz2
RUN mv $PHANTOM_JS /usr/local/share
RUN ln -sf /usr/local/share/$PHANTOM_JS/bin/phantomjs /usr/local/bin
RUN phantomjs --version

RUN apt-get install -y build-essential

WORKDIR /src/dcf/dcf-client/
RUN yarn install
RUN mvn package

WORKDIR /src/dcf/

RUN mkdir -p /root/.m2/repository/com/statoil/tops/dcf/dcf-client/0.0.1-SNAPSHOT/
RUN cp /src/dcf/dcf-client/target/dcf-client-0.0.1-SNAPSHOT.jar  /root/.m2/repository/com/statoil/tops/dcf/dcf-client/0.0.1-SNAPSHOT/dcf-client-0.0.1-SNAPSHOT.jar

RUN sh build.sh

CMD ["-jar", "-Xms512M", "-Xmx512M", "-DSERVER_ROOT=/app", "-Dlog4j.configuration=/XXX", "-Dlog4j.threshold=debug", "-Djavax.net.ssl.trustStore=XXX", "/app/dcf-spring-0.0.1-SNAPSHOT.jar", "--spring.config.location=XXX"]

EXPOSE 8080

```
So now we have a Docker image that we can easily version, transport and deploy anywhere where Docker runs.

There are still a couple of drawbacks. The first build, when nothing is cached takes 18 minutes, and subsequent builds also take 18 minutes. And the resulting image is 2.3 GB!

## Third iteration — Docker multi-stage build

To improve build times and image sizes we mold things into a multi-stage Dockerfile:

```
FROM node:9-slim AS build-frontend

RUN apt-get update && apt-get install -y build-essential

RUN apt-get update && apt-get -y install bzip2 libfreetype6 libfreetype6-dev libfontconfig1 libfontconfig1-dev build-essential python2.7 \
    && ln -s /usr/bin/python2.7 /usr/bin/python2

RUN yarn global add gulp
RUN npm install gulp

COPY ./dcf/dcf-client/yarn.lock /src/dcf/dcf-client/yarn.lock
COPY ./dcf/dcf-client/package.json /src/dcf/dcf-client/package.json

WORKDIR /src/dcf/dcf-client

ENV PHANTOM_JS="phantomjs-1.9.8-linux-x86_64"
RUN wget https://bitbucket.org/ariya/phantomjs/downloads/$PHANTOM_JS.tar.bz2 \
    && tar xvjf $PHANTOM_JS.tar.bz2 \
    && mv $PHANTOM_JS /usr/local/share \
    && rm $PHANTOM_JS.tar.bz2 \
    && ln -sf /usr/local/share/$PHANTOM_JS/bin/phantomjs /usr/local/bin \
    && phantomjs --version

RUN yarn install

COPY ./dcf/dcf-client/ /src/dcf/dcf-client/

RUN /usr/local/bin/gulp build

# ===============================================
FROM maven:3.5.3-jdk-8-slim AS mvn-build-frontend

COPY . /src/
COPY ./dcf/lib/ /root/.m2/repository/

WORKDIR /src/dcf/dcf-client/
RUN mvn package

# ==========================================
FROM maven:3.5.3-jdk-8-slim AS build-backend

COPY --from=build-frontend /src/dcf/dcf-client/target /src/dcf-spring/src/main/resources/static
COPY --from=build-frontend /src/dcf/dcf-client/Client /src/dcf-spring/src/main/resources/static

COPY --from=mvn-build-frontend /src/dcf/dcf-client/target/dcf-client-0.0.1-SNAPSHOT.jar  /root/.m2/repository/com/statoil/tops/dcf/dcf-client/0.0.1-SNAPSHOT/dcf-client-0.0.1-SNAPSHOT.jar

COPY ./dcf/lib/ /root/.m2/repository/
COPY ./dcf/pom.xml /src/dcf/pom.xml
COPY ./dcf/dcf-spring/pom.xml /src/dcf/dcf-spring/pom.xml
COPY ./dcf/dcf-client/pom.xml /src/dcf/dcf-client/pom.xml

WORKDIR /src/dcf/
RUN mvn dependency:resolve -X

COPY . /src/

WORKDIR /src/dcf/

RUN mvn -U -X install

COPY ./AppLog.xml /src/AppLog.xml
COPY ./application.yml /src/application.yml

# =====================
FROM openjdk:8-jre-slim
COPY --from=build-backend /src/dcf/dcf-spring/target /app

ENTRYPOINT ["/usr/bin/java"]

# /usr/bin/java -jar -Xms512M -Xmx512M -DSERVER_ROOT=/app -Dlog4j.configuration=/XXX -Dlog4j.threshold=debug -Djavax.net.ssl.trustStore=XXX dcf-spring-0.0.1-SNAPSHOT.jar --spring.config.location=XXX

CMD ["-jar", "-Xms512M", "-Xmx512M", "-DSERVER_ROOT=/app", "-Dlog4j.configuration=/XXX", "-Dlog4j.threshold=debug", "-Djavax.net.ssl.trustStore=XXX", "/app/dcf-spring-0.0.1-SNAPSHOT.jar", "--spring.config.location=XXX"]

EXPOSE 8080
```
However, in this case, since the dependencies between the frontend and backend are a bit unclear and we don’t have the resources for further optimization we have not been able to improve build times that much using Docker’s [[https://thenewstack.io/understanding-the-docker-cache-for-faster-builds/|cache of image layers]].

Still, we are saving a few minutes by caching NPM dependencies in the frontend build. The resulting image size though has been reduced from 2.3GB to 415MB. If we could separate the source code for frontend and backend and build them separately build times (for subsequent builds) can probably be reduced by 50-70%.

> Protip</b>: By adding
>
>```
>"scripts": {
>    "build": "gulp build"
>},
>```
>to `dcf/dcf-client/packages.json`, we can skip having to install Gulp globally. Gulp is already defined as a [devDependency]>(https://stackoverflow.com/questions/18875674/whats-the-difference-between-dependencies-devdependencies-and-peerdependencies), which means it has been installed in the project’s `node_modules`. With the script above, the command `yarn install` will run that locally-installed Gulp.

Let’s build the Docker image:

```
docker build -t dcf:latest
```

# Deploying the image

After all this work, we have an image — but haven’t actually deployed it successfuly. If we attempt to start it:

```
docker run dcf:latest
```

The container starts up and then quits. A quick inspection of the code indcates that this is probably due to the application’s inability to connect to resources on the internal network (we are testing this externally).

For now, we will optimistically assume the image will work when running internally and call DCF-in-Radix a partial success. 🎉

# Appendix A — Java dependencies

This is the folder structure of the `lib` folder containing all the external Java dependencies.

```
└───lib
    ├───com
    │   ├───ibm
    │   │   ├───disthub2
    │   │   │   └───dhbcore
    │   │   │       └───DH000-L50930
    │   │   └───mq
    │   │       ├───com.ibm.mq
    │   │       │   └───7.5.0.1
    │   │       ├───com.ibm.mq.headers
    │   │       │   └───7.5.0.1
    │   │       ├───com.ibm.mq.jmqi
    │   │       │   └───7.5.0.1
    │   │       └───com.ibm.mqjms
    │   │           └───7.5.0.1
    │   ├───independentsoft
    │   │   └───jwebservices
    │   │       └───2.0-PRO-2
    │   ├───oracle
    │   │   └───jdbc
    │   │       └───ojdbc7
    │   │           └───12.1.0.2
    │   └───statoil
    │       ├───jefintegration
    │       │   └───3.1
    │       ├───jefutil
    │       │   └───3.1
    │       ├───security
    │       │   └───crba
    │       │       └───crba-client
    │       │           └───1.0.3
    │       └───tops
    │           └───dcf
    │               └───dcf-schemas
    │                   └───1.0
    └───javax
        └───jms
            └───jms
                └───1.1
```