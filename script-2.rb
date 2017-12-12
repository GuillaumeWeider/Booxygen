#!/usr/bin/env ruby

require 'nokogiri'
require 'liquid'

module Booxygen
  VERSION = "0.1.0"

  class Templates
    def initialize(dir)

    end

  end

  class Compound
    def initialize(node)
      @node = node

      @kind = node['kind']
      @full_name = node.at_xpath("compoundname").content
      @classes = []

      if @kind == 'group'
        @classes = node.xpath("innerclass")
      end
    end

    def print(compoundtype)
      if @kind == compoundtype
        puts "[#{@kind}] #{@full_name}"
        if @kind == 'group'
          puts '- Classes:'
          @classes.each do |class0|
            puts ' * ' + class0
          end
        end
      end
    end
  end

  class Doxygen
    def initialize
      @compounds = []
    end

    def parse(directory)
      Dir[directory + '/*.xml'].each do |filename|
        File.open(filename) do |file|
          xml = Nokogiri::XML(file)

          xml.xpath('//compounddef').each do |node|
            @compounds << Compound.new(node)
          end
        end
      end
    end

    def print
      # Possible kinds: class, file, dir, struct, page, namespace, group
      @compounds.each do |c|
        c.print('group')
      end
      #@compounds.each do |c|
      #  c.print('dir')
      #end
    end
  end

  def self.run(directory)
    dox = Doxygen.new
    dox.parse(directory)
    dox.print
  end
end

# Programme principal

if ARGV.length != 1
  print "Usage: booxygen <directory>\n"
  abort
end

if Dir.exist?(ARGV[0])
  Booxygen::run(ARGV[0])
else
  print "Unknown directory\n"
  abort
end
