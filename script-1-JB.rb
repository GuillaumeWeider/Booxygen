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
    end

    def print
      puts "#{@full_name} [#{@kind}]"
    end
  end

  class Doxygen
    def initialize
      @compounds = []
    end

    def parse(filename)
      File.open(filename) do |file|
        xml = Nokogiri::XML(file)

        xml.xpath("//compounddef").each do |node|
          @compounds << Compound.new(node)
        end

      end
    end

    def print
      @compounds.each do |c|
        c.print
      end
    end
  end

  def self.run(filename)
    dox = Doxygen.new
    dox.parse(filename)
    dox.print
  end
end


# main

if ARGV.length != 1
  print "Usage: booxygen <all.xml>\n"
  abort
end

Booxygen::run(ARGV[0])
