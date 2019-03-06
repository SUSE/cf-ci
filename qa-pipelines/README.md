The CAP QA pipeline is a concourse pipeline which runs a series of tests intended to validate a build or release candidate generated from http://github.com/suse/scf. While the entire [qa-pipelines/](./) directory contains only [one pipeline configuration file](qa-pipeline.yml), the behaviour of the pipeline is customized according to how it's deployed. When deploying a pipeline via [set-pipeline](set-pipeline), the script expects the name of the [_pool_](#pool-requirements), and a file called a [_preset file_](#preset-file-instructions) containing parameters which specify the tasks to run.

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
  * [Dev Nightly Upgrades CI](
  #dev-nightly-upgrades)

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

Additionally, when deploying a pipeline, a `CONCOURSE_SECRETS_FILE` environment variable must be set, which points to the location of the file `secure/concourse-secrets.yml.gpg` from your clone of https://github.com/SUSE/cloudfoundry. You must have a private GPG key in your keyring capable of decrypting this file.

# Pool requirements

In our usage of [concourse pools](https://github.com/concourse/pool-resource), the lock files used by concourse signal which kubernetes deployments are available, but should also be valid kubernetes configs for accessing those kubernetes hosts. When a config is taken from the `unlocked/` directory by a pipeline which is running a cf-deploy task (see [Additional considerations](#additional-considerations) for an example case where this may not be true), the cf-deploy task expects that the kubernetes deployment does not have existing `scf` or `uaa` namespaces, and that its tiller also does not have `scf` or `uaa` releases (even historical ones... this means they should be deleted with `helm delete --purge`)

The pool-specific config file follows a `config-${POOL_NAME}.yml` naming convention, and is expected to contain some settings worth noting ([config-provo.yml](config-provo.yml) may be useful as a reference):

## s3 bucket location and path specifications, and access credentials.
These are used for fetching the latest release. Depending on the (sles or opensuse) job a build is generated from, either `s3-config-(bucket|prefix)-opensuse` or `s3-config-(bucket|prefix)-sles` variables will be used. The appropriate path is used to determine the latest CAP config bundle for the `s3.scf-config-sles` and `s3.s3.scf-config-opensuse` resources defined in `qa-pipeline.yml`
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

The files placed in the `claimed/` and `unclaimed/` are the *lock files* in terms of [the concourse pool resource](https://github.com/concourse/pool-resource#git-repository-structure), but are also expected to be valid kubernetes configs for pipeline access of kubernetes hosts to deploy CAP to.

For QA purposes, we prefer to use config files which will not 'expire', which means when using CaaSP, the configs which can be obtained from velum or the caasp-cli are generally not used. Instead, we create a `cap-qa` namespace and appropriate bindings to its service-account, via a [create-qa-config.sh](../qa-tools/create-qa-config.sh) script

# Preset file instructions

When deploying a pipeline, you'll need to provide a 'preset' file which contains a flag for each task you want to enable. The canonical list of flags with a description of what each one does can be seen in [flags.yml](flags.yml). This file is also symlinked from within the preset file [cap-qa-full-upgrades.yml](pipeline-presets/cap-qa-full-upgrades.yml) and has all the flags set to run our full, canonical, upgrade pipeline, which deploys a pre-upgrade version, runs smoke and brains, usb-deploy, upgrades the deployment to the latest release in the s3 path specified in the pipeline config file, usb-post-upgrade, smoke, brains, and cats, and finally the teardown task.

All tasks are run sequentially, so if any task encounters a failure, the build will abort and the kube resource will remain locked in the pool.

- When testing deploys of new builds (rather than upgrades) we use [cap-qa-deployment.yml](pipeline-presets/cap-qa-deployment.yml) preset, which only has the last 5 tasks from the flags.yml enabled:
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
- When running an upgrade test, 'pre-upgrade' tasks will also be enabled. 'pre-upgrade' tasks take the CAP chart bundle from the URL specified in the pipeline config, either `cap-sle-url` or `cap-opensuse-url` depending on the job used


# Additional considerations

The composability of the pipeline tasks means there are some interesting things you can do, besides just running the full upgrade pipeline in a linear way. In addition to what's supported by the tracked preset files, you may want to do something like the following:

## Deploy a pipeline which does a non-upgrade test of a custom bundle (not an RC or a release).
In order to do this, replace the CAP bundle URLs in the pipeline config, enable *only* the pre-upgrade tests, and deploy the pipeline. The deploy will use the bundle from the `cap-sle-url` or `cap-opensuse-url` settings in the pipeline config.
## Continue a test suite from where a previous build left off.
Sometimes running tests may fail for timing-related reasons which may be intermittent. If this happens, and you want to try to re-run the test and continue the build from where it left if, you can deploy a new pipeline with only the failed test and following tasks enabled, unlock the config which was used, and run a build from the new pipeline


# Dev Nightly Upgrades CI

Nightly Builds are builds which happen every night from develop branch of scf. The build lands in s3://cap-release-archives/nightly/
The idea here is to test bare minimum of these nightly builds, i.e.
1. we want to make sure `helm install` and `helm upgrades` are not broken due to any changes
2. Also, catch well in advance, if any changes to scf has broken qa-pipelines.

Dev ECP pool: https://github.com/SUSE/cf-ci-pools/tree/cap-ci-kube-hosts
Concourse config for Dev ECP pool: [config-capci.yml](config-capci.yml)
Example command to deploy CI on concourse:
`./set-pipeline -t provo -p Official-DEV-Nightly-Upgrades --pool=capci pipeline-presets/cap-qa-upgrades-lite.yml`

[cap-qa-upgrades-lite.yml](pipeline-presets/cap-qa-upgrades-lite.yml) is more than enough to accomplish our goals here
