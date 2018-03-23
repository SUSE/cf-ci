#!/bin/bash -x

#####################################################
#
# TODO: check all resources and services for existence befor creating
#
#####################################################


AZ_CLI=/usr/bin/az


LOCATION="westus"
MASTERCOUNT=1
AGENTCOUNT=3
SSHKEY="~/.ssh/id_rsa.pub"
VMSIZE="Standard_D2_v2"
DEBUG=1

function help_message {
    echo "Usage:"
    echo "$0 [OPTION...]"
    echo " Mandatory options:"
    echo "  -s SUBSCRIPTION ID  the azure subscription id to use"
    echo "  -p PREFIX           the prefix to use for azure resources and services"
    echo "  -d DNSPREFIX        the dns prefix to use for the container service"
    echo " Optional options:"
    echo "  -l LOCATION         the location to use. Default: ${LOCATION}"
    echo "  -m MASTERCOUNT      the number of master nodes. Default: ${MASTERCOUNT}"
    echo "  -a AGENTCOUNT       the number of agent nodes. Default: ${AGENTCOUNT}"
    echo "  -k SSHKEY           the public ssh key file. Default: ${SSHKEY}"
    echo "  -v VMSIZE           the vm size. Default: ${VMSIZE}"
}

if [ ! -f $AZ_CLI ]; then
    echo "$AZ_CLI not found."
    exit 1
fi

while getopts ":hs:p:l:d:m:a:k:v:" ARGS;
do
    case $ARGS in
        h )
            help_message >&2
            exit 1
            ;;
        p )
            PREFIX=$OPTARG
            ;;
        s )
            SUBID=$OPTARG
            ;;
        l )
            LOCATION=$OPTARG
            ;;
        d )
            DNSPREFIX=$OPTARG
            ;;
        m )
            MASTERCOUNT=$OPTARG
            ;;
        a )
            AGENTCOUNT=$OPTARG
            ;;
        k )
            SSHKEY=$OPTARG
            ;;
        v )
            VMSIZE=$OPTARG
            ;;
        \?)
            echo "Invalid option: -$OPTARG" >&2
            help_message >&2
            exit 1
            ;;
        *)
            help_message >&2
            exit 1
            ;;
    esac
done

if [ -z "$SUBID" ] || [ -z "$PREFIX" ] || [ -z "$DNSPREFIX" ]; then
    echo "Missing mandatory option"
    help_message >&2
    exit 1
fi

if [ $DEBUG ]; then
    echo "Prefix: $PREFIX"
    echo
    echo "Subscription id $SUBID"
    echo
    echo "Location: $LOCATION"
    echo 
    echo "Dnsprefix: $DNSPREFIX"
    echo
    echo "Mastercount: $MASTERCOUNT"
    echo
    echo "Agentcount: $AGENTCOUNT"
    echo
    echo "ssh key: $SSHKEY"
    echo
    echo "vm size: $VMSIZE"
    echo
fi

# Creating resource group and service principal
${AZ_CLI} account set --subscription "${SUBID}"
${AZ_CLI} group create --name "${PREFIX}-resource-group" --location "${LOCATION}"
SP=$($AZ_CLI ad sp create-for-rbac \
             --role="Contributor" \
             --scopes="/subscriptions/${SUBID}/resourceGroups/${PREFIX}-resource-group")

APPID=$(echo "${SP}" | grep appId | awk '{print $2}' | sed -n 's/^.*"\(.*\)".*$/\1/p')
PASSWORD=$(echo "${SP}" | grep password | awk '{print $2}' | sed -n 's/^.*"\(.*\)".*$/\1/p')

if [ $DEBUG ]; then
    echo "Password: ${PASSWORD}"
    echo
    echo "AppID: ${APPID}"
    echo
fi

########################################################################
#
# TODO: capture `az acs create` output and use to get network interface of one agent
#
########################################################################



# Creating container service
${AZ_CLI} acs create \
               --name "${PREFIX}-container-service" \
               --resource-group "${PREFIX}-resource-group" \
               --orchestrator-type "Kubernetes" \
               --dns-prefix "${DNSPREFIX}" \
               --master-count "${MASTERCOUNT}" \
               --admin-username "${PREFIX}-admin" \
               --agent-count "${AGENTCOUNT}" \
               --client-secret "${PASSWORD}" \
               --ssh-key-value "${SSHKEY}" \
               --service-principal "${APPID}" \
               --master-vm-size "${VMSIZE}"

# Update kernel command line
${AZ_CLI} vm list -g "${PREFIX}-resource-group" | jq '.[] | select (.tags.poolName | contains("agent")) | .name' | \
  xargs -i{} ${AZ_CLI} vm run-command invoke \
    --resource-group "${PREFIX}-resource-group" \
    --command-id RunShellScript \
    --scripts "sudo sed -i 's/GRUB_CMDLINE_LINUX_DEFAULT=\"console=tty1 console=ttyS0 earlyprintk=ttyS0 rootdelay=300\"/GRUB_CMDLINE_LINUX_DEFAULT=\"console=tty1 console=ttyS0 earlyprintk=ttyS0 rootdelay=300 swapaccount=1\"/g' /etc/default/grub.d/50-cloudimg-settings.cfg" --name {}

# Update grub
${AZ_CLI} vm list -g "${PREFIX}-resource-group" | jq '.[] | select (.tags.poolName | contains("agent")) | .name' | \
  xargs -i{} ${AZ_CLI} vm run-command invoke \
    --resource-group "${PREFIX}-resource-group" \
    --command-id RunShellScript \
    --scripts "sudo update-grub" --name {}

# Restart VMs
${AZ_CLI} vm list -g "${PREFIX}-resource-group" | jq '.[] | select (.tags.poolName | contains("agent")) | .name' | \
  xargs -i{} ${AZ_CLI} vm restart --no-wait \
    --resource-group "${PREFIX}-resource-group" \
    --name {}


# Create Public IP
${AZ_CLI} network public-ip create -g "${PREFIX}-resource-group" \
                                   -n "${PREFIX}-access" \
                                   --version "IPv4" \
                                   --allocation-method "static"

########################################################################
#
# TODO: Assign IP address to interface of one kubernetes agent, see previous todo
#
########################################################################

# Create Inbound Rule for k8s-master NSG
${AZ_CLI} network nsg rule create --resource-group "${PREFIX}-resource-group" \
                                  --nsg-name "k8s-master" \
                                  --name "${PREFIX}-cap-ports" \
                                  --direction "Inbound" \
                                  --destination-port-ranges "80 443 4443 2222 2793" \
                                  --access "Allow"
