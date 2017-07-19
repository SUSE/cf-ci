#!/usr/bin/env ruby

require 'erb'
require 'open3'
require 'optparse'
require 'ostruct'
require 'pathname'
require 'tempfile'
require 'yaml'

ROLE_MANIFEST_RELPATH = 'container-host-files/etc/hcf/config/role-manifest.yml'
ENVRC_RELPATH = '.envrc'
SECRETS_RELPATH = 'secure/concourse-secrets.yml.gpg'

opts = OpenStruct.new(
    scf_dir: '../../scf',
    secrets_dir: '../../cloudfoundry',
    prefix: '',
    print: false)
parser = OptionParser.new do |parser|
    parser.banner = (<<-EOF).gsub(/^ +/, '')
        This script will deploy the pipeline to build SCF directly into concourse.

        Usage: #{$0} <master|check> [config variant]

        Pipeline variant may be any word, as long as scf-<variant>.yaml.erb exists
        Config variant may be any word, as long as config-<variant>.yaml exists.  Defaults to 'production'.

    EOF
    parser.on('--scf-dir=DIR', 'Path to scf.git checkout') do |scf_dir|
        role_manifest = File.join(scf_dir, ROLE_MANIFEST_RELPATH)
        unless File.exist? role_manifest
            fail "Role manifest not found in SCF directory #{scf_dir}"
        end
        opts.scf_dir = scf_dir
    end
    parser.on('--secrets-dir=DIR', 'Path to secrets repository checkout') do |secrets_dir|
        secrets_path = File.join(secrets_dir, SECRETS_RELPATH)
        unless File.exist? secrets_path
            fail "Secrets not found at #{secrets_path}"
        end
        opts.secrets_dir = secrets_dir
    end
    parser.on('--target=concourse', 'Fly target') do |fly_target|
        opts.target = fly_target
    end
    parser.on('--print', 'Just print the pipeline, do not deploy') do
        opts.print = true
    end
    parser.on('--prefix=PREFIX', 'Pipeline name prefix') do |prefix|
        opts.prefix = prefix.gsub(/-*$/, '') + '-'
    end
end
parser.parse!

opts.scf_dir = File.absolute_path(opts.scf_dir)
opts.role_manifest = File.absolute_path(File.join(opts.scf_dir, ROLE_MANIFEST_RELPATH))
fail "Role manifest not found at #{opts.role_manifest}" unless File.exist? opts.role_manifest

opts.envrc = File.absolute_path(File.join(opts.scf_dir, ENVRC_RELPATH))
fail ".envrc not found at #{opts.envrc}" unless File.exist? opts.envrc

role_manifest = YAML.load_file(opts.role_manifest)
release_paths = Open3.capture2('bash', '-c', "source '#{opts.envrc}' && echo $FISSILE_RELEASE").first.chomp.split(',')

pipeline, variant = ARGV.take(2)

# The releases we have. The key should be the same as the start of the generated
# file name (e.g. cf-release-tarball-nnn.tgz); each should have two items,
# "target" (the make target to run), and "path" (relative path from
# scf-infrastructure to the release directory).
releases = Hash[release_paths.map do |path|
    name = File.basename(path)
    name += '-release' unless name.end_with? '-release'
    [name, Pathname.new(path).relative_path_from(Pathname.new(opts.scf_dir))]
end]

pipeline_name = "#{opts.prefix}scf-#{pipeline}"
template = open("scf-#{pipeline}.yaml.erb", 'r') do |f|
    ERB.new(f.read, nil, '<>')
end

# Load the secrets file, followed by the local config overrides
variant ||= 'production'
config_file_name = "config-#{variant}.yaml"
gpg_r, gpg_w = IO.pipe
gpg_process = Process.spawn(
    'gpg', '--decrypt', '--batch',
    File.join(opts.secrets_dir, SECRETS_RELPATH),
    out: gpg_w)
gpg_w.close
# Note that we jam the two YAML files together so the local configs can refer
# to anchors in the secrets file
vars = YAML.load(gpg_r.read + open(config_file_name, 'r').read.sub(/^---\n/m, ''))

# docker hub registry needs special handling
vars.select {|name| name == 'dockerhub-registry'}.map do |name, value|
    vars[name] = [nil, '', 'index.docker.io'].include?(value) ? '' : "#{value.sub(/\/+$/, '')}/"
end

# Expose variables to the ERB template
b = binding
vars.each_pair do |name, value|
    b.local_variable_set(name.gsub('-', '_'), value)
end
b.local_variable_set('roles',
    role_manifest['roles'].reject { |r| r['type'] == 'docker' } )

if opts.print
    # Dry run mode
    template.run(b)
    exit
end

pipeline_r, pipeline_w = IO.pipe
pipeline_thread = Thread.new do
    pipeline_w.write template.result(b)
    pipeline_w.close
end

vars_r, vars_w = IO.pipe
vars_thread = Thread.new do
    vars_w.write vars.to_yaml
    vars_w.close
end

fly_cmd = ['fly']
if opts.target
    fly_cmd << '--target' << opts.target
end
fly_cmd += [
    "set-pipeline",
    "--pipeline=#{pipeline_name}",
    "--config=/dev/fd/#{pipeline_r.fileno}",
    "--load-vars-from=/dev/fd/#{vars_r.fileno}",
]
fly_process = Process.spawn(*fly_cmd,
    pipeline_r.fileno => pipeline_r.fileno,
    vars_r.fileno => vars_r.fileno)

pipeline_thread.join
vars_thread.join
exit 1 unless Process.wait2(fly_process).last.success?
