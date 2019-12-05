# cf-ci

This repository contains various continuous integration related things.

To deploy all pipelines, use [deploy-all](deploy-all).

## [automation-scripts](automation-scripts/)
### [prep-new-cluster.sh](automation-scripts/prep-new-cluster.sh)
Script to prepare a new bare-metal cluster (for setting up CaaSP clusters).

## [certstrap](certstrap/)
Command line x509 certificate generation; see
https://github.com/square/certstrap/ for details.  Currently used to generate
Kubernetes certificates on the vagrant box.

## [cf-usb](cf-usb/)
Pipeline for CF-USB. Deployed as [openSUSE](https://concourse.suse.de/teams/main/pipelines/cf-usb)
and [SLE](https://concourse.suse.de/teams/main/pipelines/cf-usb-sle) variants.

## [cf-usb-plugin](cf-usb-plugin/)
CF CLI plugin for cf-usb.  Deployed as [check pipeline](https://concourse.ca-west-1.howdoi.website/teams/main/pipelines/cf-usb-plugin-check)
and [master pipeline](https://concourse.ca-west-1.howdoi.website/teams/main/pipelines/cf-usb-plugin-master).

## [minibroker](minibroker/)
OSB-API compliant helm-based service broker; see upstream at https://github.com/osbkit/minibroker/.  Deployed as
[check pipeline](https://concourse.ca-west-1.howdoi.website/teams/main/pipelines/minibroker-check)
and [master pipeline](https://concourse.ca-west-1.howdoi.website/teams/main/pipelines/minibroker-master).

## [qa-pipelines](qa-pipelines/)
This is full of magic, refer to [qa-pipelines README](qa-pipelines/README.md)

## [qa-tools](qa-tools/)
Various scripts for QA (not CI)

## [sample-apps](sample-apps/)
Sample applications for SCF, for use with [qa-pipelines](#qa-pipelines)

## [user-acceptance-tests](user-acceptance-tests/)
[behave](https://behave.readthedocs.io/)-style acceptance tests
