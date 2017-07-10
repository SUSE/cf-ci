#Base image for kube yaml installer
FROM opensuse:42.2

#install: curl, kubectl, unzip, openssh, sshpass, vim, nano
RUN true \
    && zypper ref \
    && zypper --non-interactive in unzip \
    openssh \
    sshpass \
    vim \
    nano \
    curl \
    && curl -LO https://storage.googleapis.com/kubernetes-release/release/$(curl -s https://storage.googleapis.com/kubernetes-release/release/stable.txt)/bin/linux/amd64/kubectl \
    && chmod +x ./kubectl \
    && mv ./kubectl /usr/local/bin/kubectl \
    echo "source <(kubectl completion bash)" >> ~/.bashrc
    zypper clean -a
    && true
