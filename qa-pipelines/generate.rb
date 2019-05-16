#!/usr/bin/env ruby

require 'erb'
require 'optparse'
require 'ostruct'
require 'yaml'

class PipelineDeployer
    TEMPLATE_NAME = 'qa-pipeline.yml.erb'

    # fix_key converts the key into something that can be a ruby variable name
    def fix_key(k)
        k.tr('-', '_').to_sym
    end

    # make_open_struct converts a hash to an openstruct, recursively
    def make_open_struct(o)
        case o
        when Hash
            OpenStruct.new.tap do |s|
                o.each { |k, v| s[fix_key(k)] = make_open_struct(v) }
            end
        when Array
            o.map { |i| make_open_struct(i) }
        else
            o
        end
    end

    def eval_context(flags_file='flags.yml', all_flags_file='flags.yml')
        # Load the configuration file
        @eval_context ||= binding.dup.tap do |context|
            flags = open(File.join(__dir__, all_flags_file), 'r', &YAML.method(:load))
            flags.each do |k, v|
                context.local_variable_set fix_key(k), false
            end
            flags = open(File.join(__dir__, flags_file), 'r', &YAML.method(:load))
            flags.each do |k, v|
                context.local_variable_set fix_key(k), make_open_struct(v)
            end
        end
    end

    def render(flags_file, all_flags_file)
        # Render the template
        filename = File.join(__dir__, TEMPLATE_NAME)
        template = ERB.new(File.read(filename))
        template.filename = filename
        result = YAML.load template.result(eval_context(flags_file, all_flags_file))
        puts result.to_yaml
    end
end

PipelineDeployer.new.render *ARGV.first(2)
