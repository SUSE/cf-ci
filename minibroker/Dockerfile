FROM opensuse/leap

ARG HELM_VERSION=2.8.2

RUN zypper install -y curl tar && \
    curl -LO "https://storage.googleapis.com/kubernetes-helm/helm-v${HELM_VERSION}-linux-amd64.tar.gz" && \
    tar xf helm-*-linux-amd64.tar.gz -C "/bin" --strip-components=1 linux-amd64/helm && \
    rm helm-*-linux-amd64.tar.gz
