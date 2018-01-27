#!/usr/bin/env ruby

require 'nokogiri'
require 'liquid'

module Booxygen
  VERSION = "0.2.0"

  class Templates
    def initialize(dir)

    end
  end

  class Compound
    # Définition d'une structure pour stocker un nom + description brève + description complète
    MyClass = Struct.new(:name, :kind, :briefdesc, :detaileddesc)

    def initialize(node)
      @node = node

      @kind = node['kind']
      @full_name = node.at_xpath('compoundname').content
      @brief_desc = node.at_xpath('//compounddef/briefdescription/para')
      @detailed_desc = node.at_xpath('//compounddef/detaileddescription/para')

      @classes = []
      @enum = []
      @typedef = []
      @function = []
      @variable = []

      # Traitement des groupes / modules
      if @kind == 'group'

        # Traitement des classes
        node.xpath('innerclass').each do |innerclass|
          # Lecture des classes publiques seulement
          if innerclass['prot'] != 'private'

            File.open($dir + '/' + innerclass['refid'] + '.xml', 'r') do |file|
              xml = Nokogiri::XML(file)

              @classes << MyClass.new(innerclass.content, xml.at_xpath('//compounddef')['kind'], xml.at_xpath('//compounddef/briefdescription/para'), xml.at_xpath('//compounddef/detaileddescription/para'))
            end
          end
        end

        # Traitement des memberdef
        node.xpath('//memberdef').each do |memberdef|
          # Traitement des énumérations
          if memberdef['kind'] == 'enum'
            @enum << memberdef.at_xpath('name').content
          end

          # Traitement des typedefs
          if memberdef['kind'] == 'typedef'
            @typedef << memberdef.at_xpath('name').content
          end

          # Traitement des fonctions
          if memberdef['kind'] == 'function'
            @function << memberdef.at_xpath('name').content
          end

          # Traitement des variables
          if memberdef['kind'] == 'variable'
            @variable << memberdef.at_xpath('name').content
          end
        end

      end
    end

    def print(type)
      if @kind == type && @full_name == 'graphics'
        puts "[#{@kind}] #{@full_name}"
        puts '   Full desc: ' + @brief_desc  unless @brief_desc.nil?
        puts @detailed_desc unless @detailed_desc.nil?

        # Traitement des groupes / modules
        if @kind == 'group'
          # Traitement des classes
          if @classes.length > 0
            puts '- Classes:'
            @classes.each do |node|
              puts ' * ' + node.kind + ' - ' + node.name
              puts '   Desc: ' + node.briefdesc # unless node.briefdesc.nil?
              puts node.detaileddesc unless node.detaileddesc.nil?
            end
          end

          # Traitement des énumérations
          if @enum.length > 0
            puts '- Enum:'
            @enum.each do |node|
              puts ' * ' + node
            end
          end

          # Traitement des typedefs
          if @typedef.length > 0
            puts '- Typedefs:'
            @typedef.each do |node|
              puts ' * ' + node
            end
          end

          # Traitement des fonctions
          if @function.length > 0
            puts '- Functions:'
            @function.each do |node|
              puts ' * ' + node
            end
          end

          # Traitement des variables
          if @variable.length > 0
            puts '- Variables:'
            @variable.each do |node|
              puts ' * ' + node
            end
          end
          #
          puts('')
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
  # Définition d'une variable globale
  $dir = ARGV[0]
  Booxygen::run($dir)
else
  print "Unknown directory\n"
  abort
end
