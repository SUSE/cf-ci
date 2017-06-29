#Base image for kube yaml installer
FROM opensuse:42.2

#install: surl, kubectl, unzip, openssh, sshpass,vim, nano
RUN true \
    && zypper ref \
    && zypper --non-interactive in curl \
    && curl -LO https://storage.googleapis.com/kubernetes-release/release/$(curl -s https://storage.googleapis.com/kubernetes-release/release/stable.txt)/bin/linux/amd64/kubectl \
    && chmod +x ./kubectl \
    && mv ./kubectl /usr/local/bin/kubectl \
    && zypper --non-interactive in unzip \
    && zypper --non-interactive in openssh \
    && zypper --non-interactive in sshpass \
    && zypper --non-interactive in vim \
    && zypper --non-interactive in nano \
    && true