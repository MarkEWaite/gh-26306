FROM public.ecr.aws/amazoncorretto/amazoncorretto:17 as jre-build
    
RUN jlink \
    --add-modules ALL-MODULE-PATH \
    --no-man-pages \
    --compress=2 \
    --output /javaruntime

FROM public.ecr.aws/ubuntu/ubuntu:22.04

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
    ca-certificates \
    curl \
    git \
    git-lfs \
    gnupg \
    gpg \
    libfontconfig1 \
    libfreetype6 \
    procps \
    python3-pip \
    ssh-client \
    tini \
    unzip \
    && git lfs install

ENV LANG C.UTF-8

ARG TARGETARCH
ARG COMMIT_SHA

ARG user=jenkins
ARG group=jenkins
ARG uid=1000
ARG gid=1000
ARG http_port=8080
ARG agent_port=50000
ARG JENKINS_HOME=/var/jenkins_home
ARG REF=/usr/share/jenkins/ref

ENV JENKINS_HOME $JENKINS_HOME
ENV JENKINS_SLAVE_AGENT_PORT ${agent_port}
ENV REF $REF

# Jenkins is run with user `jenkins`, uid = 1000
# If you bind mount a volume from the host or a data container,
# ensure you use the same uid
RUN mkdir -p $JENKINS_HOME \
    && chown ${uid}:${gid} $JENKINS_HOME \
    && groupadd -g ${gid} ${group} \
    && useradd -d "$JENKINS_HOME" -u ${uid} -g ${gid} -l -m -s /bin/bash ${user}

# Jenkins home directory is a volume, so configuration and build history
# can be persisted and survive image upgrades
VOLUME $JENKINS_HOME

# $REF (defaults to `/usr/share/jenkins/ref/`) contains all reference configuration we want
# to set on a fresh new installation. Use it to bundle additional plugins
# or config file with your custom jenkins Docker image.
RUN mkdir -p ${REF}/init.groovy.d

RUN curl -sL https://updates.jenkins.io/stable/latestCore.txt > ${REF}/jenkins_version

# see https://github.com/docker/docker/issues/8331
RUN JENKINS_VERSION=$(cat ${REF}/jenkins_version) \
    && JENKINS_URL=https://get.jenkins.io/war-stable/${JENKINS_VERSION}/jenkins.war \
    && JENKINS_SHA_URL=${JENKINS_URL}.sha256 \
    && curl -fsSL ${JENKINS_URL} -o jenkins.war \
    && curl -sL ${JENKINS_SHA_URL} >/tmp/jenkins_sha \
    && sha256sum -c --strict /tmp/jenkins_sha \
    && rm -f /tmp/jenkins_sha

RUN mv jenkins.war /usr/share/jenkins/jenkins.war

ENV JENKINS_UC https://updates.jenkins.io
ENV JENKINS_UC_EXPERIMENTAL=https://updates.jenkins.io/experimental
ENV JENKINS_INCREMENTALS_REPO_MIRROR=https://repo.jenkins-ci.org/incrementals
RUN chown -R ${user} "$JENKINS_HOME" "$REF"

ARG PLUGIN_CLI_VERSION=2.14.0
ARG PLUGIN_CLI_URL=https://github.com/jenkinsci/plugin-installation-manager-tool/releases/download/${PLUGIN_CLI_VERSION}/jenkins-plugin-manager-${PLUGIN_CLI_VERSION}.jar
RUN curl -fsSL ${PLUGIN_CLI_URL} -o /opt/jenkins-plugin-manager.jar

# for main web interface:
EXPOSE ${http_port}

# will be used by attached agents:
EXPOSE ${agent_port}

ENV COPY_REFERENCE_FILE_LOG $JENKINS_HOME/copy_reference_file.log

ENV JAVA_HOME=/opt/java/openjdk
ENV PATH "${JAVA_HOME}/bin:${PATH}"
COPY --from=jre-build /javaruntime $JAVA_HOME

RUN pip3 install -U pip
RUN pip3 install -U boto3
RUN curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
RUN unzip awscliv2.zip
RUN ./aws/install

USER ${user}

# For security reasons these files are manually copied from https://github.com/jenkinsci/docker
COPY --chmod=0755 files/jenkins-support /usr/local/bin/jenkins-support
COPY --chmod=0755 files/jenkins.sh /usr/local/bin/jenkins.sh
COPY --chmod=0755 files/jenkins-plugin-cli.sh /bin/jenkins-plugin-cli

COPY files/jenkins.yaml ${REF}/jenkins.yaml
ENV CASC_JENKINS_CONFIG ${REF}/jenkins.yaml
RUN echo 2.0 > ${REF}/jenkins.install.UpgradeWizard.state
COPY --chown=${user}:${group} files/init.groovy.d/*.groovy ${REF}/init.groovy.d/
COPY files/SafeRestart.groovy /usr/share/jenkins/ref/SafeRestart.groovy.override
COPY files/plugins.txt /usr/share/jenkins/ref/plugins.txt
RUN jenkins-plugin-cli --plugin-file /usr/share/jenkins/ref/plugins.txt \
    --jenkins-version=$(cat ${REF}/jenkins_version) \
    --latest=true \
    --latest-specified
RUN mv /usr/share/jenkins/ref/plugins.txt /usr/share/jenkins/ref/plugins.txt.override
RUN git config -f /usr/share/jenkins/ref/.gitconfig.override credential.helper '!aws codecommit credential-helper $@'
RUN git config -f /usr/share/jenkins/ref/.gitconfig.override  credential.UseHttpPath true

ENTRYPOINT ["/usr/bin/tini", "--", "/usr/local/bin/jenkins.sh"]
