#Base image for kube yaml installer
FROM opensuse/leap:15.1

# Install: ruby, unzip, openssh, sshpass, vim, nano, curl, kubectl
# Install: wget, tar, helm, direnv
# Install python dependencies for az cli prerequisites
# "zypper removerepo "OSS Update" is now required because that repo isn't reachable
# NOTE: The `utilities` repo is added for access to `direnv`.
#
RUN true \
    && zypper removerepo "OSS Update" \
    && zypper --non-interactive --gpg-auto-import-keys refresh \
    && zypper --non-interactive install ruby \
    unzip \
    openssh \
    sshpass \
    vim \
    nano \
    curl \
    wget \
    tar \
    gzip \
    direnv \
    git-core \
    bash-completion docker-bash-completion systemd-bash-completion \
    python-xml python-pyOpenSSL python-devel \
    && curl -sS "https://s3.amazonaws.com/aws-cli/awscli-bundle.zip" -o "awscli-bundle.zip" \
    && unzip awscli-bundle.zip \
    && ./awscli-bundle/install -i /usr/local/aws -b /usr/local/bin/aws \
    && rm -rf aws-cli-bundle aws-cli-bundle.zip \
    && curl -o aws-iam-authenticator https://amazon-eks.s3-us-west-2.amazonaws.com/1.12.7/2019-03-27/bin/linux/amd64/aws-iam-authenticator \
    && chmod +x ./aws-iam-authenticator \
    && mv ./aws-iam-authenticator /usr/local/bin/aws-iam-authenticator \
    && rpm --import https://packages.microsoft.com/keys/microsoft.asc \
    && zypper addrepo --name 'Azure CLI' --check https://packages.microsoft.com/yumrepos/azure-cli azure-cli \
    && zypper --non-interactive install --from azure-cli azure-cli \
    && helm_version=v2.8.2 \
    && wget https://kubernetes-helm.storage.googleapis.com/helm-${helm_version}-linux-amd64.tar.gz -O - | tar xz -C /usr/local/bin --strip-components=1 linux-amd64/helm \
    && mv /usr/local/bin/helm /usr/local/bin/helm_${helm_version} \
    && chmod a+x /usr/local/bin/helm_${helm_version} \
    && helm_version=v2.11.0 \
    && wget https://kubernetes-helm.storage.googleapis.com/helm-${helm_version}-linux-amd64.tar.gz -O - | tar xz -C /usr/local/bin --strip-components=1 linux-amd64/helm \
    && mv /usr/local/bin/helm /usr/local/bin/helm_${helm_version} \
    && chmod a+x /usr/local/bin/helm_${helm_version} \
    && echo "eval \"\$(direnv hook bash)\"" >> ~/.bashrc \
    && echo "source /etc/profile.d/bash_completion.sh" >> ~/.bashrc \
    && echo "source <(helm completion bash)" >> ~/.bashrc \
    && curl -LO https://storage.googleapis.com/kubernetes-release/release/v1.11.8/bin/linux/amd64/kubectl \
    && chmod +x ./kubectl \
    && mv ./kubectl /usr/local/bin/kubectl \
    && echo "source <(kubectl completion bash)" >> ~/.bashrc \
    && curl -sLo /usr/local/bin/klog.sh "https://raw.githubusercontent.com/SUSE/scf/develop/container-host-files/opt/scf/bin/klog.sh" \
    && chmod +x /usr/local/bin/klog.sh \
    && curl -sLo /usr/local/bin/k "https://github.com/aarondl/kctl/releases/download/v0.0.12/kctl-linux-amd64" \
    && chmod +x /usr/local/bin/k \
    && zypper clean -a \
    && true

RUN true \
    && wget https://github.com/stedolan/jq/releases/download/jq-1.5/jq-linux64 -O /usr/local/bin/jq \
    && chmod +x /usr/local/bin/jq

RUN true \
    && wget "https://packages.cloudfoundry.org/stable?release=linux64-binary&version=6.42.0" -O - | tar xz -C /usr/local/bin cf \
    && chmod a+x /usr/local/bin/cf

RUN true \
    && curl -L https://github.com/SUSE/stampy/releases/download/0.0.0/stampy-0.0.0.22.gbb93bf3.linux-amd64.tgz | tar xz stampy \
    && mv stampy /usr/local/bin/stampy \
    && chmod +x /usr/local/bin/stampy

RUN true \
    && curl https://dl.google.com/dl/cloudsdk/release/google-cloud-sdk.tar.gz > /tmp/google-cloud-sdk.tar.gz \
    && mkdir -p /usr/local/gcloud \
    && tar -C /usr/local/gcloud -xvf /tmp/google-cloud-sdk.tar.gz \
    && /usr/local/gcloud/google-cloud-sdk/install.sh --quiet

COPY helm /usr/local/bin/helm

RUN true \
    && chmod a+x /usr/local/bin/helm

ENV PATH $PATH:/usr/local/gcloud/google-cloud-sdk/bin
