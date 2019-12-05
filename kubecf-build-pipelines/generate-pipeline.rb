#!/usr/bin/env ruby

require 'erb'
require 'optparse'
require 'ostruct'
require 'yaml'

class PipelineDeployer
    # fix_key converts the key into something that can be a ruby variable name
    def fix_key(k)
        k.tr('-', '_').to_sym
    end

    def eval_context(config_file, secrets_file)
        # Load the configuration file
        @eval_context ||= binding.dup.tap do |context|
            vars_file="---\n"
            [secrets_file, config_file].each do |file|
                vars_file += File.read(file).split("\n").select{ |line| line !~ /^---$/ }.join("\n") + "\n"
            end
            YAML.load(vars_file).each do |k, v|
                context.local_variable_set fix_key(k), v
            end
        end
    end

    def render(template_file, config_file, secrets_file)
        # Render the template
        filename = File.join(__dir__, template_file)
        template = ERB.new(File.read(filename))
        template.filename = filename
        result = YAML.load template.result(eval_context(config_file, secrets_file))
        puts result.to_yaml
    end
end

PipelineDeployer.new.render *ARGV.first(3)
