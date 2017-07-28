#Base image for kube yaml installer
FROM opensuse:42.2

# Install: ruby, unzip, openssh, sshpass, vim, nano, curl, kubectl
# Install: wget, tar, helm, direnv
# NOTE: The `utilities` repo is added for access to `direnv`.
# NOTE: The `containers` repo is added for access to `helm`.
#
RUN true \
    && zypper --non-interactive addrepo http://download.opensuse.org/repositories/utilities/openSUSE_Leap_42.2/utilities.repo \
    && zypper --non-interactive addrepo http://download.opensuse.org/repositories/Virtualization:/containers/openSUSE_Leap_42.2/Virtualization:containers.repo \
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
    helm \
    direnv \
    && curl -LO https://storage.googleapis.com/kubernetes-release/release/$(curl -s https://storage.googleapis.com/kubernetes-release/release/stable.txt)/bin/linux/amd64/kubectl \
    && chmod +x ./kubectl \
    && mv ./kubectl /usr/local/bin/kubectl \
    && echo "source <(kubectl completion bash)" >> ~/.bashrc \
    && zypper clean -a \
    && true
