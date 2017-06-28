from opensuse:42.2

RUN zypper --non-interactive in curl

#install kubectl
RUN curl -LO https://storage.googleapis.com/kubernetes-release/release/$(curl -s https://storage.googleapis.com/kubernetes-release/release/stable.txt)/bin/linux/amd64/kubectl
RUN chmod +x ./kubectl
RUN mv ./kubectl /usr/local/bin/kubectl

#install vim

RUN zypper --non-interactive in vim

#install nano

RUN zypper --non-interactive in nano

#install unzip

RUN zypper --non-interactive in unzip