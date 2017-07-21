# cf-ci

The concourse build pipeline for the [scf] repository.

[scf]: https://github.com/SUSE/scf

To set the pipeline, use the ruby wrapper script to generate and set it:

```ruby
# This assumes the concourse target is named `lol`
ruby deploy.rb --target=lol develop
```

For local development, copy `config-production.yaml` to a different file (e.g.
`config-vagrant.yaml`) and provide the second word on the command line:
```
ruby deploy.rb --target=rofl develop vagrant
```

This assumes the secrets directory and the SCF directory (for the role manifest)
are located relative to this one like in GitHub URLs.  If not, provide additonal
`--secrets-dir` and `--scf-dir` arguments.
