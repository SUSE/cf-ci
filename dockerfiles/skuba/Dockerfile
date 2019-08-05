FROM registry.suse.com/suse/sle15

ARG VERSION
ARG REPO_ENV
ARG REPO

RUN zypper ar --no-gpgcheck "${REPO}" "skuba-${REPO_ENV}" && \
    zypper ar --no-gpgcheck "http://download.suse.de/ibs/SUSE:/CA/SLE_15_SP1/SUSE:CA.repo" && \
    zypper in --auto-agree-with-licenses --no-confirm "skuba-${VERSION}" terraform ca-certificates-suse && \
    zypper clean -a

VOLUME ["/app"]

WORKDIR /app
