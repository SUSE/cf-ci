#!/usr/bin/env ruby

require 'erb'
require 'open3'
require 'optparse'
require 'ostruct'
require 'pathname'
require 'tempfile'
require 'yaml'

ROLE_MANIFEST_RELPATH = 'src/hcf-release/src/hcf-config/role-manifest.yml'
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

        Pipeline variant may be any word, as long as hcf-<variant>.yaml.erb exists
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

pipeline_name = "#{opts.prefix}hcf-#{pipeline}"
template = open("hcf-#{pipeline}.yaml.erb", 'r') do |f|
    ERB.new(f.read, nil, '<>')
end

b = binding
variant ||= 'production'
config_file_name = "config-#{variant}.yaml"
YAML.load_file(config_file_name).each_pair do |name, value|
    b.local_variable_set(name.gsub('-', '_'), value)
end
b.local_variable_set('roles',
    role_manifest['roles'].reject { |r| r['type'] == 'docker' } )

if opts.print
    template.run(b)
    exit
end

begin
    pipeline_file = Tempfile.new("hcf-#{pipeline}.yaml")
    pipeline_file.write template.result(b)
    pipeline_file.close

    gpg_r, gpg_w = IO.pipe
    gpg_process = Process.spawn(
        'gpg', '--decrypt', '--batch',
        File.join(opts.secrets_dir, SECRETS_RELPATH),
        out: gpg_w)

    fly_cmd = ['fly']
    if opts.target
        fly_cmd << '--target' << opts.target
    end
    fly_cmd += [
        "set-pipeline",
        "--pipeline=#{pipeline_name}",
        "--config=#{pipeline_file.path}",
        "--load-vars-from=/dev/fd/#{gpg_r.fileno}",
        "--load-vars-from=#{config_file_name}",
    ]
    fly_process = Process.spawn(*fly_cmd, gpg_r.fileno => gpg_r.fileno)

    gpg_w.close

    exit 1 unless Process.wait2(gpg_process).last.success?
    exit 1 unless Process.wait2(fly_process).last.success?
ensure
    pipeline_file.close!
end
