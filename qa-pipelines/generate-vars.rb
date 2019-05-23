#!/usr/bin/env ruby

DESCRIPTION = <<-EOF
    This script generates the concourse variables file on STDOUT.
    EOF

require 'optparse'
require 'yaml'

class VarFileGenerator
    def initialize
        @secret_files = []
        @vars_files = []
        @preset_files = []
        @flags_files = []
        @flags = Hash.new
    end

    def parse_options!
        OptionParser.new do |opts|
            opts.banner = "#{DESCRIPTION.lstrip}\n#{opts.banner}"
            opts.on('--secrets=SECRETS', 'Secrets file to load') do |f|
                @secret_files << f
            end
            opts.on('--vars-file=VARS', 'Vars file to load') do |f|
                @vars_files << f
            end
            opts.on('--preset-file=PRESET', 'Presets file to load') do |f|
                @preset_files << f
            end
            opts.on('--flags-file=FLAGS', 'Flags file to load') do |f|
                @flags_files << f
            end
        end.parse!
    end

    def decode_file(secrets_file)
        `gpg --decrypt --batch #{secrets_file}`
    end

    def read_secrets
        @secret_files.map { |f| decode_file(f).delete_prefix('---') }.join("\n")
    end

    def read_vars
        @vars_files.map { |f| File.read(f).delete_prefix('---') }.join("\n")
    end

    def read_presets
        @preset_files.map { |f| File.read(f).delete_prefix('---') }.join("\n")
    end

    def run
        parse_options!

        vars = Hash.new
        # The flags file contain defaults that should be set to false
        @flags_files.each do |f|
            YAML.load_file(f).keys.each { |k| vars[k] = false }
        end

        contents = read_secrets + read_vars + read_presets
        vars.merge! YAML.safe_load("---\n" + contents, [], [], true)
        puts vars.to_yaml
    end
end

VarFileGenerator.new.run