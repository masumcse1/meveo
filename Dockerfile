#################################################################
#####                Build meveo source code                #####
#################################################################
FROM maven:3.6-jdk-11-slim AS build-meveo

# Install git packages 

RUN apt-get -y update
RUN apt-get -y install git
 
ARG SCM="scm:git:ssh://git@github.com:meveo-org/meveo.git"
ARG BUILD_NUMBER

WORKDIR /usr/src/meveo

COPY . .

# Download all dependencies using docker cache
#RUN mvn dependency:go-offline

RUN --mount=type=cache,target=/root/.m2 \
    --mount=type=cache,target=/usr/src/meveo/target/classes \
    --mount=type=cache,target=/usr/src/meveo/meveo-admin-ejbs/target/classes \
    --mount=type=cache,target=/usr/src/meveo/meveo-admin-web/target/classes \
    --mount=type=cache,target=/usr/src/meveo/meveo-annotations/target/classes \
    --mount=type=cache,target=/usr/src/meveo/meveo-api/target/classes \
    --mount=type=cache,target=/usr/src/meveo/meveo-api-dto/target/classes \
    --mount=type=cache,target=/usr/src/meveo/meveo-el-resolver/target/classes \
    --mount=type=cache,target=/usr/src/meveo/meveo-json-schema/target/classes \
    --mount=type=cache,target=/usr/src/meveo/meveo-model/target/classes \
    --mount=type=cache,target=/usr/src/meveo/meveo-reporting/target/classes \
    --mount=type=cache,target=/usr/src/meveo/meveo-security/target/classes \
    --mount=type=cache,target=/usr/src/meveo/meveo-ws/target/classes \
    mvn package -Dscm.url=${SCM} -DskipTests -Dmaven.test.skip=true

##################################################################
#####                Build meveo docker image                #####
##################################################################

#FROM jboss/wildfly:18.0.1.Final
FROM openjdk:11.0.7-jdk-slim-buster


### ------------------------- base ------------------------- ###
# Install packages necessary
RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        apt-transport-https ca-certificates curl jsvc unzip \
# procps : for 'free' command
        procps \
# iputils-ping : for 'ping' command
        iputils-ping \
# iproute2 : for 'ip' command
        iproute2 \
# postgresql-client : for 'pg_isready' command
        postgresql-client \
# java.lang.UnsatisfiedLinkError: /usr/local/openjdk-11/lib/libfontmanager.so: libfreetype.so.6: cannot open shared object file: No such file or directory
# java.lang.NoClassDefFoundError: Could not initialize class sun.awt.X11FontManager
# https://github.com/docker-library/openjdk/pull/235#issuecomment-424466077
        fontconfig libfreetype6 \
    && apt-get autoremove -y && rm -rf /var/lib/apt/lists/*

# Set the timezone (Default timezone is UTC.)
# ENV TZ Europe/Paris
# RUN echo "Europe/Paris" > /etc/timezone \
#     && rm /etc/localtime && ln -s /usr/share/zoneinfo/Europe/Paris /etc/localtime \
#     && dpkg-reconfigure -f noninteractive tzdata

# Create a user and group used to launch processes
# The user ID 1000 is the default for the first "regular" user on Fedora/RHEL,
# so there is a high chance that this ID will be equal to the current user
# making it easier to use volumes (no permission issues)
RUN groupadd -r jboss -g 2002 \
    && useradd -u 2002 -r -g jboss -m -d /opt/jboss -s /sbin/nologin -c "JBoss user" jboss \
    && chmod 755 /opt/jboss

# Set the working directory to jboss' user home directory
WORKDIR /opt/jboss

### ------------------------- base-end ------------------------- ###

### ------------------------- NodeJs & NPM ------------------------------- ###

ENV NODE_VERSION=16.14.0
# RUN apt install -y curl

ENV NVM_DIR=./.nvm

RUN mkdir -p .nvm \
	&& chown -R jboss:jboss .nvm
	
RUN curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.0/install.sh | bash

RUN . "$NVM_DIR/nvm.sh" && nvm install ${NODE_VERSION}
RUN . "$NVM_DIR/nvm.sh" && nvm use v${NODE_VERSION}
RUN . "$NVM_DIR/nvm.sh" && nvm alias default v${NODE_VERSION}

ENV PATH="./.nvm/versions/node/v${NODE_VERSION}/bin/:${PATH}"

RUN npm config set user 0
RUN npm config set unsafe-perm true
	
RUN node --version
RUN npm --version

RUN ln -s "${PWD}/.nvm/versions/node/v${NODE_VERSION}/bin/node" /usr/bin/node
RUN ln -s "${PWD}/.nvm/versions/node/v${NODE_VERSION}/bin/npm" /usr/bin/npm

### ------------------------- Jboss Wildfly ----------------------------- ###
# Ref: https://github.com/jboss-dockerfiles/wildfly/blob/18.0.1.Final/Dockerfile

# Set the WILDFLY_VERSION env variable
ENV WILDFLY_VERSION 18.0.1.Final
ARG WILDFLY_SHA1=ef0372589a0f08c36b15360fe7291721a7e3f7d9
ENV JBOSS_HOME /opt/jboss/wildfly

# Add the WildFly distribution to /opt, and make wildfly the owner of the extracted tar content
# Make sure the distribution is available from a well-known place
RUN cd $HOME \
    && curl -O https://download.jboss.org/wildfly/${WILDFLY_VERSION}/wildfly-${WILDFLY_VERSION}.tar.gz \
    && sha1sum wildfly-${WILDFLY_VERSION}.tar.gz | grep ${WILDFLY_SHA1} \
    && tar xf wildfly-${WILDFLY_VERSION}.tar.gz \
    && mv $HOME/wildfly-${WILDFLY_VERSION} ${JBOSS_HOME} \
    && rm wildfly-${WILDFLY_VERSION}.tar.gz \
    && chown -R jboss:0 ${JBOSS_HOME} \
    && chmod -R g+rw ${JBOSS_HOME}

### ------------------------- Jboss Wildfly - End ----------------------------- ###

# Change to the jboss user
USER jboss

### ------------------------- Keycloak ----------------------------- ###
# Ref: https://github.com/keycloak/keycloak-containers/blob/10.0.2/adapter-wildfly/Dockerfile

ARG KEYCLOAK_VERSION=10.0.2

WORKDIR ${JBOSS_HOME}

RUN curl -L https://downloads.jboss.org/keycloak/${KEYCLOAK_VERSION}/adapters/keycloak-oidc/keycloak-wildfly-adapter-dist-${KEYCLOAK_VERSION}.tar.gz | tar zx
RUN curl -L https://downloads.jboss.org/keycloak/${KEYCLOAK_VERSION}/adapters/saml/keycloak-saml-wildfly-adapter-dist-${KEYCLOAK_VERSION}.tar.gz | tar zx

### ------------------------- Keycloak - End ----------------------------- ###



### ------------------------- Liquibase ----------------------------- ###
# Ref: https://github.com/liquibase/docker/blob/main/3.10.x/Dockerfile

# Create a directory to install liquibase
RUN mkdir -p /opt/jboss/liquibase
WORKDIR /opt/jboss/liquibase

# Latest Liquibase Release Version
ARG LIQUIBASE_VERSION=3.10.2

# Download, install, clean up
RUN set -x \
  && curl -L https://github.com/liquibase/liquibase/releases/download/v${LIQUIBASE_VERSION}/liquibase-${LIQUIBASE_VERSION}.tar.gz | tar -xzf -


# RUN curl -o /liquibase/lib/<db platform>.jar <url to maven jar driver>
RUN curl -o /opt/jboss/liquibase/lib/postgresql.jar https://repo1.maven.org/maven2/org/postgresql/postgresql/42.2.12/postgresql-42.2.12.jar



### ------------------------- Postgresql module ----------------------------- ###

WORKDIR ${JBOSS_HOME}

ARG POSTGRESQL_VERSION=42.2.5

COPY --chown=jboss:jboss docker/configs/postgresql/module.xml ${JBOSS_HOME}/modules/system/layers/base/org/postgresql/main/module.xml

RUN curl -O https://jdbc.postgresql.org/download/postgresql-${POSTGRESQL_VERSION}.jar \
    && mv postgresql-${POSTGRESQL_VERSION}.jar ${JBOSS_HOME}/modules/system/layers/base/org/postgresql/main/ \
    && sed -i "s|\[POSTGRESQL\_VERSION\]|${POSTGRESQL_VERSION}|g" ${JBOSS_HOME}/modules/system/layers/base/org/postgresql/main/module.xml



### ------------------------- Wildfly-Exporter module ----------------------------- ###

# ARG WILDFLY_EXPORTER_MODULE=wildfly_exporter_module-0.0.5.jar
# ARG WILDFLY_EXPORTER_SERVLET=wildfly_exporter_servlet-0.0.5.war

# # Add a module jar file to wildfly
# # https://github.com/nlighten/wildfly_exporter#add-exporter-module-jars-to-wildfly
# COPY --chown=jboss:jboss docker/configs/wildfly_exporter/${WILDFLY_EXPORTER_MODULE} ${JBOSS_HOME}/modules/${WILDFLY_EXPORTER_MODULE}
# RUN cd ${JBOSS_HOME}/modules \
#     && jar -xvf ${WILDFLY_EXPORTER_MODULE} \
#     && rm -rf META-INF \
#     && rm -f ${WILDFLY_EXPORTER_MODULE}

# # Add a deployment war file for the metrics servlet
# # https://github.com/nlighten/wildfly_exporter#deploy-exporter-servlet
# COPY --chown=jboss:jboss docker/configs/wildfly_exporter/${WILDFLY_EXPORTER_SERVLET} ${JBOSS_HOME}/standalone/deployments/metrics.war



### ------------------------- glowroot ----------------------------- ###
### https://glowroot.org/
### https://github.com/glowroot/glowroot/releases

ARG GLOWROOT_VERSION=0.13.6

RUN set -ex \
    && curl -L https://github.com/glowroot/glowroot/releases/download/v${GLOWROOT_VERSION}/glowroot-${GLOWROOT_VERSION}-dist.zip > glowroot.zip \
    && unzip glowroot.zip \
    && rm glowroot.zip \
    && ls ${JBOSS_HOME}/glowroot/glowroot.jar
    
### ------------------------- Configurations ----------------------------- ###


### Create some folders for meveo volumes and db resource
RUN mkdir -p ${JBOSS_HOME}/meveodata /tmp/meveo/binary/storage /tmp/meveo/infinispan /opt/jboss/liquibase \
    && chown -R jboss:jboss ${JBOSS_HOME}/meveodata /tmp/meveo /opt/jboss/liquibase \
### Backup the original standalone-full.xml
    && cp ${JBOSS_HOME}/standalone/configuration/standalone-full.xml ${JBOSS_HOME}/standalone/configuration/standalone-full.xml.org

### cli commands
COPY --chown=jboss:jboss docker/configs/cli ${JBOSS_HOME}/cli

### meveo configuration
COPY --chown=jboss:jboss docker/configs/props ${JBOSS_HOME}/props

### Changelog files for Liquibase
COPY --chown=jboss:jboss --from=build-meveo /usr/src/meveo/meveo-model/src/main/db_resources /opt/jboss/liquibase/db_resources

### meveo.war
COPY --chown=jboss:jboss --from=build-meveo /usr/src/meveo/meveo-admin-web/target/meveo.war ${JBOSS_HOME}/standalone/deployments/meveo.war

# Ensure signals are forwarded to the JVM process correctly for graceful shutdown
ENV LAUNCH_JBOSS_IN_BACKGROUND true

# Expose the ports we're interested in
EXPOSE 8080 8787 9990

COPY --chown=jboss:jboss docker/docker-entrypoint.sh /
RUN chmod +x /docker-entrypoint.sh

ENTRYPOINT [ "/docker-entrypoint.sh" ]
