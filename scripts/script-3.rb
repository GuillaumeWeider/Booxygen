#!/usr/bin/env ruby

require 'nokogiri'
require 'liquid'

require 'logger'
require 'fileutils'
require 'io/console'
#require 'awesome_print'

module Booxygen
  VERSION = "0.5.0"

  class Doxygen
    def initialize
      Liquid::Template.error_mode = :strict
      Liquid::Template.file_system = Liquid::LocalFileSystem.new('../templates')
      @compounds = {}
      @project_name = "Gamedev Framework (gf)"
      @logger = Logger.new(STDOUT)
    end

    # def parse(file_path)
    #   filename = File.basename(file_path)
    #
    #   @logger.info("Parsing #{filename}.xml")
    #
    #   xml = Nokogiri::XML(File.open("#{filename}"))
    #
    #   if xml.at_xpath('name(/*)') != 'doxygen'
    #     @logger.warn('File root tag isn\'t correct, skip it.')
    #   end
    #
    #   compounddef = xml.xpath('compounddef')
    #   if compounddef.length != 1
    #     @logger.warn('File content isn\'t correct, skip it.')
    #   end
    #
    #
    # end

    def start

      # Build XML files list
      xml_files = Dir.glob("#{$dir}/*.xml")
      xml_files.sort

      # Treat all XML files
      xml_files.each do |filename|
        # If file is index.xml skip for now, nothing important in it
        next if File.basename(filename) == 'index.xml'

        xml = Nokogiri::XML(File.open("#{filename}"))

        compounddef = xml.at_xpath('//compounddef')

        # If it's a valid kind, parse it
        if ['namespace', 'group', 'class', 'struct', 'union', 'dir', 'file', 'page'].include?(compounddef['kind'])
          compound = {}
          compound['id'] = ''
          compound['kind'] = ''
          compound['name'] = ''
          compound['short_name'] = ''
          compound['url'] = ''
          compound['briefdesc'] = ''
          compound['children'] = []
          compound['parent'] = nil

          # Parsing
          compound['id'] = compounddef['id']
          compound['kind'] = compounddef['kind']

          if ['page', 'group'].include?(compound['kind'])
            compound['name'] = compounddef.at_xpath('title/node()').to_s
          else
            compound['name'] = compounddef.at_xpath('compoundname/node()').to_s
          end
          compound['short_name'] = compound['name']

          if compound['kind'] == 'page'
            compound['url'] = compounddef.at_xpath('compoundname/node()').to_s + '.html'
          else
            compound['url'] = compound['id'] + '.html'
          end

          compound['briefdesc'] = '' #TODO

          if ['namespace', 'class', 'struct', 'union'].include?(compound['kind'])
            compounddef.xpath('innerclass').each do |element|
              compound['children'].push(element['refid'])
            end
            compounddef.xpath('innernamespace').each do |element|
              compound['children'].push(element['refid'])
            end
          elsif ['dir', 'file'].include?(compound['kind'])
            compounddef.xpath('innerdir').each do |element|
              compound['children'].push(element['refid'])
            end
            compounddef.xpath('innerfile').each do |element|
              compound['children'].push(element['refid'])
            end
          elsif compound['kind'] == 'page'
            compounddef.xpath('innerpage').each do |element|
              compound['children'].push(element['refid'])
            end
          elsif compound['kind'] == 'group'
            compounddef.xpath('innergroup').each do |element|
              compound['children'].push(element['refid'])
            end
          end

          @compounds[compound['id']] = compound
        end
      end

      @compounds.each_value do |element|
        element['children'].each do |refid|
          if @compounds.has_key?(refid)
            @compounds[refid]['parent'] = element['id']
          end
        end
      end

      @compounds.each_value do |element|
        unless element['parent'].nil?
          if ['namespace', 'struct', 'class', 'union'].include?(element['kind'])
            prefix = @compounds[element['parent']]['name'] + '::'
            if element['name'].start_with?(prefix)
              element['short_name'] = element['name'][prefix.length..element['name'].length]
            end
          end
        end
      end


      # Treat all XML files, parse
      xml_files.each do |file_path|
        # If file is index.xml skip for now
        next if File.basename(file_path) == 'index.xml'

        #parse(file_path)
      end

      # Generate ?
      #
      # Copy source files ?




      #@compounds.each_value do |element|
      #  puts 'ID: ' + element['id']
      #  puts 'Kind: ' + element['kind']
      #  puts 'Name: ' + element['name']
      #  puts 'Short name: ' + element['short_name']
      #  puts 'URL: ' + element['url']
      #  puts ''
      #end

      classes = []

      @compounds.each do |value|

        if value['kind'] == 'class'
          classes.push value
        end
      end

      loop do
        FileUtils.copy_entry('../files', '../output', false, false, true)

        template = Liquid::Template.parse(File.read('../templates/base.liquid'))
        template.assigns['PROJECT_NAME'] = @project_name
        template.assigns['compounds'] = @compounds

        # Main page
        #pages.each do |compound|
        #  if compound['refid'] == 'indexpage'
        #    File.write('../output/html/main.html', template.render('pagetype' => 'mainpage',
        #                                                           'TITLE' => 'Main page',
        #                                                           'compound' => compound))
        #    break
        #  end
        #end

        # Index
        File.write('../output/html/classes.html', template.render('pagetype' => 'classes',
                                                                  'TITLE' => 'Index page',
                                                                  'classes' => classes))

        # Classes
        #classes.each do |compound|
        #  File.write("../output/html/#{compound['refid']}.html", template.render('pagetype' => 'class',
        #                                                                         'TITLE' => "#{compound['name'][0]}",
        #                                                                         'compound' => compound))
        #end

        # ?

        print "\n", "Press any key to reload Liquid, or 'q' to quit."
        if STDIN.getch == "q"
          print "\n"
          break
        end
      end

    end
  end

  def self.run
    dox = Doxygen.new
    dox.start
  end

end

#
# Programme principal
#

if ARGV.length != 1
  print "Usage: booxygen <xml-directory>\n"
  abort
end

if Dir.exist?(ARGV[0])
  # Définition d'une variable globale
  $dir = ARGV[0]
  Booxygen::run
else
  print "Unknown directory\n"
  abort
end
