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
UAA_RELPATH = 'src/uaa-fissile-release'
UAA_ROLE_MANIFEST_RELPATH = 'role-manifest.yml'
UAA_ENVRC_RELPATH = '.envrc'
SECRETS_RELPATH = 'secure/concourse-secrets.yml.gpg'

secrets_path = ENV['CONCOURSE_SECRETS_FILE']

opts = OpenStruct.new(
    secrets_dir: '../../cloudfoundry',
    prefix: '',
    print: false,
    scf: OpenStruct.new(
        dir: '../../scf',
        ),
    uaa: OpenStruct.new(
        enabled: true,
        ),
    )
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
        opts.scf.dir = scf_dir
        if opts.uaa.dir.nil?
            uaa_dir = File.join(scf_dir, UAA_RELPATH)
            uaa_role_manifest = File.join(uaa_dir, UAA_ROLE_MANIFEST_RELPATH)
            if File.exist? uaa_role_manifest
                opts.uaa.dir = uaa_dir
            else
                puts "UAA role manifest not found at #{uaa_role_manifest}"
            end
        end
    end
    parser.on('--secrets-dir=DIR', 'Path to secrets repository checkout') do |secrets_dir|
        secrets_path = File.join(secrets_dir, SECRETS_RELPATH)
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
    parser.on('--uaa[=no]', TrueClass, 'Enable building UAA components (defaults to building them)') do |v|
        opts.uaa.enabled = v
    end
end
parser.parse!

pipeline, variant = ARGV.take(2)

# Load the pipeline configuration YAML template file
pipeline_name = "#{opts.prefix}scf-#{pipeline}"
template = open("scf-#{pipeline}.yaml.erb", 'r') do |f|
    ERB.new(f.read, nil, '<>')
end

# Load the secrets file, followed by the local config overrides
fail "Neither CONCOURSE_SECRETS_FILE env var nor --secrets-dir option defined" if secrets_path.nil?
fail "Secrets not found at #{secrets_path}" unless File.exist? secrets_path

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

opts.scf.dir = File.absolute_path(opts.scf.dir)
opts.scf.role_manifest = File.absolute_path(File.join(opts.scf.dir, ROLE_MANIFEST_RELPATH))
fail "Role manifest not found at #{opts.scf.role_manifest}" unless File.exist? opts.scf.role_manifest

opts.scf.envrc = File.absolute_path(File.join(opts.scf.dir, ENVRC_RELPATH))
fail ".envrc not found at #{opts.scf.envrc}" unless File.exist? opts.scf.envrc

if opts.uaa.enabled
    opts.uaa.dir = File.absolute_path(UAA_RELPATH, opts.scf.dir)
    fail "Failed to find UAA submodule" unless Dir.exist? opts.uaa.dir
    opts.uaa.role_manifest = File.absolute_path(UAA_ROLE_MANIFEST_RELPATH, opts.uaa.dir)
    fail "Failed to find UAA role manifest" unless File.exist? opts.uaa.role_manifest
    opts.uaa.envrc = File.absolute_path(UAA_ENVRC_RELPATH, opts.uaa.dir)
    fail "Failed to find UAA envrc" unless File.exist? opts.uaa.envrc
end

# Expose variables to the ERB template
b = binding
vars.each_pair do |name, value|
    b.local_variable_set(name.gsub('-', '_'), value)
end
b.local_variable_set 'uaa_releases', {}
b.local_variable_set 'uaa_roles', []

def configure_project(b, project_name, opts)
    config = opts[project_name]
    role_manifest = YAML.load_file(config.role_manifest)
    release_paths = Open3.capture2('bash', '-c', "source '#{config.envrc}' && echo $FISSILE_RELEASE").first.chomp.split(',')
    roles = role_manifest['roles'].reject { |r| r['type'] == 'docker' }

    # The releases we have. The key should be the release name (e.g.
    # "nats-release"); the value is the relative path to the release directory.
    releases = Hash[release_paths.map do |path|
        name = File.basename(path)
        name += '-release' unless name.end_with? '-release'
        [name, Pathname.new(path).relative_path_from(Pathname.new(opts.scf.dir))]
    end]
    dir_relpath = Pathname.new(config.dir).relative_path_from(Pathname.new(opts.scf.dir))
    b.local_variable_set("#{project_name}_releases", releases)
    b.local_variable_set("#{project_name}_roles", roles)
    b.local_variable_set("#{project_name}_dir", dir_relpath)
end

configure_project b, 'scf', opts
configure_project b, 'uaa', opts if opts.uaa.enabled

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
