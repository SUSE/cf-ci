#Base image for kube yaml installer
FROM opensuse/leap:42.3

# Install: ruby, unzip, openssh, sshpass, vim, nano, curl, kubectl
# Install: wget, tar, helm, direnv
# Install python dependencies for az cli prerequisites
# "zypper removerepo "OSS Update" is now required because that repo isn't reachable
# NOTE: The `utilities` repo is added for access to `direnv`.
#
RUN true \
    && zypper removerepo "OSS Update" \
    && zypper --non-interactive addrepo http://download.opensuse.org/repositories/utilities/openSUSE_Leap_42.3/utilities.repo \
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
    direnv \
    bash-completion docker-bash-completion systemd-bash-completion \
    python-xml python-pyOpenSSL python-devel \
    && rpm --import https://packages.microsoft.com/keys/microsoft.asc \
    && zypper addrepo --name 'Azure CLI' --check https://packages.microsoft.com/yumrepos/azure-cli azure-cli \
    && zypper --non-interactive install --from azure-cli azure-cli \
    && zypper refresh \
    && helm_version=v2.8.2 \
    && wget https://kubernetes-helm.storage.googleapis.com/helm-${helm_version}-linux-amd64.tar.gz -O - | tar xz -C /usr/local/bin --strip-components=1 linux-amd64/helm \
    && chmod a+x /usr/local/bin/helm \
    && echo "eval \"\$(direnv hook bash)\"" >> ~/.bashrc \
    && echo "source /etc/profile.d/bash_completion.sh" >> ~/.bashrc \
    && echo "source <(helm completion bash)" >> ~/.bashrc \
    && curl -LO https://storage.googleapis.com/kubernetes-release/release/v1.9.8/bin/linux/amd64/kubectl \
    && chmod +x ./kubectl \
    && mv ./kubectl /usr/local/bin/kubectl \
    && echo "source <(kubectl completion bash)" >> ~/.bashrc \
    && zypper clean -a \
    && true

RUN true \
    && curl https://dl.google.com/dl/cloudsdk/release/google-cloud-sdk.tar.gz > /tmp/google-cloud-sdk.tar.gz \
    && mkdir -p /usr/local/gcloud \
    && tar -C /usr/local/gcloud -xvf /tmp/google-cloud-sdk.tar.gz \
    && /usr/local/gcloud/google-cloud-sdk/install.sh --quiet 

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

ENV PATH $PATH:/usr/local/gcloud/google-cloud-sdk/bin
