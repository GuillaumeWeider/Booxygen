#!/usr/bin/env ruby

require 'nokogiri'
require 'liquid'

module Booxygen
  VERSION = "0.3.0"

  class Templates
    def initialize(dir)

    end
  end

  class Compound
    def initialize(node)
      @node = node

      @kind = node['kind']
      @full_name = node.at_xpath('compoundname').content
      @brief_desc = node.at_xpath('//compounddef/briefdescription/para')
      @detailed_desc = node.at_xpath('//compounddef/detaileddescription/para')

      # CompoundKind
      @classes = []
      # MemberKind
      @memberdef = Hash.new {|h,k| h[k] = [] }

      # Traitement des groupes (modules)
      if @kind == 'group'

        # Traitement des classes
        node.xpath('innerclass').each do |innerclass|

          # Lecture des classes publiques seulement
          if innerclass['prot'] != 'private'

            File.open($dir + '/' + innerclass['refid'] + '.xml', 'r') do |file|
              xml = Nokogiri::XML(file)

              tmp = {}
              tmp['name'] = innerclass.content
              tmp['kind'] = xml.at_xpath('//compounddef')['kind']
              tmp['briefdesc'] = xml.at_xpath('//compounddef/briefdescription/para')
              tmp['detaileddesc'] = xml.at_xpath('//compounddef/detaileddescription/para')

              @classes << tmp
            end
          end
        end

        memberdef_enum = %w{enum typedef function variable}

        # Traitement des memberdef
        node.xpath('//memberdef').each do |member|

          memberdef_enum.each do |member_enum|
            if member['kind'] == member_enum
              @memberdef[member_enum].push(member.at_xpath('name').content)
              break
            end
          end

        end
        #

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
              puts ' * ' + node['kind'] + ' - ' + node['name']
              puts '   Desc: ' + node['briefdesc'] unless node['briefdesc'].nil?
              puts node['detaileddesc'] unless node['detaileddesc'].nil?
            end
          end

          memberdef_enum = %w{enum typedef function variable}

          # Affichage
          memberdef_enum.each do |member_enum|
            if @memberdef[member_enum].length > 0
              puts '- ' + member_enum + ':'
              @memberdef[member_enum].each do |value|
                puts ' * ' + value
              end
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
