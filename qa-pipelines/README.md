The CAP QA pipeline is a concourse pipeline which runs a series of tests intended to validate a build or release candidate generated from http://github.com/suse/scf. While the entire [qa-pipelines/](./) directory contains only [one pipeline definition file](qa-pipeline.yml), the behaviour of the pipeline is customized according to how it's deployed. When deploying a pipeline via [set-pipeline](set-pipeline), the script expects the name of the [_pool_](#pool-requirements), and a file called a [_preset file_](#preset-file-instructions) containing parameters which specify the tasks to run. Additionally, the pipeline will read values from the [pipeline configuration file](config.yml) which customize certain behaviours that affect how a task runs (such as what version of CAP to deploy pre-upgrade, or what version to upgrade to). See config.yml for comments on the available settings.

Table of Contents
=================

  * [Pipeline deployment overview](#pipeline-deployment-overview)
    * [Pipeline deployment prerequisites](#pipeline-deployment-prerequisites)
    * [set-pipeline usage](#set-pipeline-usage)
  * [Pool requirements](#pool-requirements)
  * [Preset file instructions](#preset-file-instructions)
  * [Additional considerations](#additional-considerations)
    * [Deploy a pipeline which does a non-upgrade test of a custom bundle (which is neither an RC or a release)](#deploy-a-pipeline-which-does-a-non-upgrade-test-of-a-custom-bundle-not-an-rc-or-a-release)
    * [Continue a test suite from where a previous build left off](#continue-a-test-suite-from-where-a-previous-build-left-off)
    * [Terraform deployments](#terraform-deployments)
  * [Dev Nightly Upgrades CI](#dev-nightly-upgrades-ci)
  * [PR pipeline](#pr-pipeline)
  * [Single Brain Pipeline](#single-brain-pipeline)

# Pipeline deployment overview

Pipelines are deployed to a concourse installation with the [set-pipeline](qa-pipelines/set-pipeline) script. Before attempting to deploy a pipeline, ensure you have satisfied the following prerequisites

## Pipeline deployment prerequisites

- A pool-specific config file in the directory of the `set-pipeline` script. `set-pipeline` will look for a file containing various configurable values in the current working directory named `config-${POOL_NAME}.yml`. See [config-provo.yml](config-provo.yml) for an example.

- A cloneable git repository with kube configs which also serve as lock files, as well as a pool-specific config following the `config-${POOL_NAME}.yml` naming convention. See [Pool requirements](#pool-requirements) for more details.

- A concourse CI deployment, a `fly` CLI in your PATH, and a [logged in fly target](https://concourse-ci.org/fly.html#fly-login) with a name which is passed to the `-t` option of `set-pipeline`

## set-pipeline usage

```
./set-pipeline [options] <feature-flags preset file>

The pipeline configuration file "qa-pipeline.yml" must exist.
The configuration file "config-<config variant>.yml" must exist.
Available options:
    -h, --help          Print this help and exit
    -p, --prefix=       Set additional pipeline prefix
    --pool=provo        Pool to take pool config and kube config from. Default is 'provo'
    -t, --target=       Set fly target concourse
    -b, --branch=       Use a specific branch or tag. Defaults to the current branch
```

Example usage:
    `./set-pipeline --pool=azure -p my-azure -t my-target`

When a new pipeline is deployed, all jobs will be paused, so when you want to start a new build from a job on this pipeline, you can drill down to the job in the concourse UI, unpause it, and click the '+' sign.

Additionally, when deploying a pipeline, a `CONCOURSE_SECRETS_FILE` environment variable must be set, which points to the location of the file `secure/concourse-secrets.yml.gpg` from your clone of https://github.com/SUSE/cloudfoundry. You must have a private GPG key in your keyring capable of decrypting this file.  If a `CONCOURSE_SECRETS_FILE_poolname` environment variable exists (where `poolname` is the name of the pool), that will be used instead.

# Pool requirements

In our usage of [concourse pools](https://github.com/concourse/pool-resource), the lock files used by concourse signal which kubernetes deployments are available (and for some types of pools may also be valid kubernetes configs for accessing those kubernetes hosts). When a config is taken from the `unclaimed/` directory by a pipeline which is running a cf-deploy task (see [Additional considerations](#additional-considerations) for an example case where this may not be true), the cf-deploy task expects that the kubernetes deployment does not have existing `scf` or `uaa` namespaces, and that its tiller also does not have `scf` or `uaa` releases (even historical ones... this means they should be deleted with `helm delete --purge`)

Pipelines with terraform flags enabled may create the pool resource before inserting it into the selected pool.

Pools should be contained in a branch named `${pool_name}-kube-hosts` with a path named `${pool_name}-kube-hosts/` which has `claimed/` and `unclaimed/` directories with an empty `.gitkeep` file
## s3 bucket location and path specifications, and access credentials.
These are used for fetching the latest release of `s3-config-(bucket|prefix)-sles`. The appropriate path is used to determine the latest CAP config bundle for the `s3.scf-config-sles` resource defined in `qa-pipeline.yml`
## docker registry specification and access credentials.
These are used for fetching the images referenced from the determined charts.
## a `src-ci-repo` setting
This is used to clone the ci repo from the running tasks. When each task executes, its manifest will reference a script to run which is located in a path of the ci repo cloned in the task container.
## a `kube-pool-repo` setting.
This setting hould be public, or accessible via the `kube-pool-key` also included in that file. This repository should contain a branch named `${POOL_NAME}-kube-hosts` with the directory structure shown below, for each pool which uses this repository. For SUSE CAP QA and dev purposes, we're using https://github.com/suse/cf-ci-pools (accessible to members of the SUSE github org for security purposes) for all such pools

```
# branch ${POOL_NAME}-kube-hosts:
└── ${POOL_NAME}-kube-hosts
    ├── claimed
    │   ├── .gitkeep
    │   └── pool-resource-1
    └── unclaimed
        ├── .gitkeep
        └── pool-resource-2
```

The files placed in the `claimed/` and `unclaimed/` are the *lock files* in terms of [the concourse pool resource](https://github.com/concourse/pool-resource#git-repository-structure). These files may also be valid kubernetes configs for pipeline access of kubernetes hosts to deploy CAP to, or (such as for cloud-based services such as AKS, EKS, etc) may instead be files containing information which can be used (along with platform-specific credentials also embedded in the pipeline via the secrets file and CLI tools in the cf-ci-orchestration image) to obtain expiring configs to access clusters deployed to those platforms.

For CaaSP and kubernetes hosts that support it, we prefer to use kubeconfig files which will not expire. On kube hosts which support this type of access (such as CaaSP3 clusters), we may create a `cap-qa` namespace and appropriate bindings to its service-account, via a [create-qa-config.sh](../qa-tools/create-qa-config.sh) script

# Preset file instructions

When deploying a pipeline, you'll need to provide a 'preset' file which contains a flag for each task you want to enable. The canonical list of flags with a description of what each one does can be seen in [flags.yml](flags.yml). This file is also symlinked from within the preset file [full-upgrades.yml](pipeline-presets/full-upgrades.yml) and has all the flags set to run our full, canonical, upgrade pipeline, which deploys a pre-upgrade version, runs smoke and brains, usb-deploy, upgrades the deployment to the latest release in the s3 path specified in the pipeline config file, usb-post-upgrade, smoke, brains, and cats, and finally the teardown task.

All tasks are run sequentially, so if any task encounters a failure, the build will abort and the kube resource will remain locked in the pool.

- When testing deploys of new builds (rather than upgrades) we use [deploy.yml](pipeline-presets/deploy.yml) preset, which only has deploy, smoke, brains, cats, and teardown tasks enabled:
```
# flags.yml:

# NON-UPGRADE PIPELINES START HERE
# deploy for non-upgrade pipelines
enable-cf-deploy: false

# run tests for non-upgrade pipelines, and post-upgrade tests for upgrade pipelines
enable-cf-smoke-tests: true
enable-cf-brain-tests: true
enable-cf-acceptance-tests: true

# tear down CAP deployment
enable-cf-teardown: true
```
- When running an upgrade test, 'pre-upgrade' tasks will also be enabled. 'pre-upgrade' tasks take the CAP chart bundle from the `cap-sle-url` specified in the pipeline config.


# Additional considerations

The composability of the pipeline tasks means there are some interesting things you can do, besides just running the full upgrade pipeline in a linear way. In addition to what's supported by the tracked preset files, you may want to do something like the following:

## Deploy a pipeline which does a non-upgrade test of a custom bundle (not an RC or a release).
In order to do this, set `cap-install-url` in the config.yml file to the URL of the custom bundle (or path in S3)

## Continue a test suite from where a previous build left off.
Sometimes running tests may fail for timing-related reasons which may be intermittent. If this happens, and you want to try to re-run the test and continue the build from where it left if, you can deploy a new pipeline with only the failed test and following tasks enabled, unlock the config which was used, and run a build from the new pipeline. Note, when re-running a failed test suite, you will need to delete the previous test running pod.

## Terraform deployments
For supported platforms, the QA CI can automatically spin up and tear down kube hosts via terraform. This will happen when the associated flag (following the naming convention `terraform-${platform_name}` is set to true in the preset file.

# Dev Nightly Upgrades CI

Nightly Builds are builds which happen every night from develop branch of scf. The build lands in s3://cap-release-archives/nightly/ and will be picked up by any unpaused pipeline deployed with the `--nightly` flag with an available pool resource.

The idea here is to test bare minimum of these nightly builds, i.e.
1. We want to make sure `helm install` and `helm upgrades` are not broken due to any changes
2. Also, catch well in advance, if any changes to scf have broken qa-pipelines

The `cap-ci` pool [here](https://github.com/SUSE/cf-ci-pools/tree/cap-ci-kube-hosts), composed of kube clusters on ECP in `cap-ci` project, will be our dedicated pool for nightly testing.

Concourse config for Dev ECP pool: [config-capci.yml](config-capci.yml)

Example command to deploy CI on concourse:

`./set-pipeline -t provo -p Official-DEV-Nightly-Upgrades --pool=capci --nightly pipeline-presets/cap-qa-upgrades-lite.yml`

[pipeline-presets/cap-qa-upgrades-lite.yml](pipeline-presets/cap-qa-upgrades-lite.yml) is more than enough to accomplish our goals here


# PR pipeline

Similar to the nightly build deployment, a pipeline can also be deployed which will use the helm charts generated for a given PR, which end up in s3://cap-release-archives/prs/ . In order to deploy such a pipeline, use the `--pr` flag with the number of the PR. For example, to deploy a pipeline which would use s3://cap-release-archives/prs/PR-2327-scf-sle-2.16.0+cf6.10.0.90.gdd77c7c3.zip, you can use the parameter `--pr 2327` when running the `set-pipeline` script


# Single Brain Pipeline

You can deploy a pipeline which will skip the normal series of tasks, and instead run one individual brain test, by using the preset file `pipeline-presets/single-brain.yml`.

Such a pipeline will show one job for each brain test, which you can trigger a build from to run the corresponding brain test with the first available pool resource.

