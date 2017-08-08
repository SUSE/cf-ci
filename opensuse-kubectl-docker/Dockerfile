#Base image for kube yaml installer
FROM opensuse:42.2

# Install: ruby, unzip, openssh, sshpass, vim, nano, curl, kubectl
# Install: wget, tar, helm, direnv
# NOTE: The `utilities` repo is added for access to `direnv`.
#
RUN true \
    && zypper --non-interactive addrepo http://download.opensuse.org/repositories/utilities/openSUSE_Leap_42.2/utilities.repo \
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
    && helm_version=$(curl -sSI https://github.com/kubernetes/helm/releases/latest | awk -v RS='\r\n' -F/ '/^Location:/ { print $NF }') \
    && wget https://kubernetes-helm.storage.googleapis.com/helm-${helm_version}-linux-amd64.tar.gz -O - | tar xz -C /usr/local/bin --strip-components=1 linux-amd64/helm \
    && chmod a+x /usr/local/bin/helm \
    && echo "source /etc/profile.d/bash_completion.sh" >> ~/.bashrc \
    && echo "source <(helm completion bash)" >> ~/.bashrc \
    && curl -LO https://storage.googleapis.com/kubernetes-release/release/$(curl -s https://storage.googleapis.com/kubernetes-release/release/stable.txt)/bin/linux/amd64/kubectl \
    && chmod +x ./kubectl \
    && mv ./kubectl /usr/local/bin/kubectl \
    && echo "source <(kubectl completion bash)" >> ~/.bashrc \
    && zypper clean -a \
    && true
