# How to deploy the pipeline


## Presets

You can find the preset files in https://github.com/SUSE/cf-ci/tree/master/ qa-pipelines/pipeline-presets. When deploying a pipeline, you just need to choose the preset file or create one of your own.


## Secrets

The required credentials are stored encrypted in https://github.com/SUSE/cloudfoundry/blob/master/secure/concourse-secrets.yml.gpg. You need to provide the location of this file via an environment variable.
E.g.
```
export CONCOURSE_SECRETS_FILE=~/src/cloudfoundry/secure/concourse-secrets.yml.gpg
```

## Deployment

You can then deploy a pipeline with the `set_pipeline.sh` command run from `cf-ci/qa-pipelines/`

For example:
```./set-pipeline --prefix --target just_a_test ./pipeline-presets/cap-qa-deployment.yml```

