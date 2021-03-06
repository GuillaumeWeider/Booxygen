#!/usr/bin/env ruby

require 'nokogiri'
require 'liquid'

require 'fileutils'
require 'io/console'
#require 'awesome_print'

module Booxygen
  VERSION = "0.4.0"

  class Doxygen
    def initialize
      Liquid::Template.error_mode = :strict
      Liquid::Template.file_system = Liquid::LocalFileSystem.new('../templates')
      @index_hash = {}
      @types = {}
      @project_name = "Gamedev Framework (gf)"
    end

    # Fonction de traitement d'un type donné, dans un code XML donné
    def rec_parse(index, xsd, xsd_name, xml)
      result = {}

      # Si ce XSD n'a jamais été traité auparavant
      unless @types.has_key? xsd_name
        @types[xsd_name] = {}
      end

      # Si ce type complexe n'a pas encore été parsé
      unless @types[xsd_name].has_key? index['type']
        # Recherche des caractéristiques du type complexe donné
        xsd_complex_type = xsd.at_xpath("//xsd:complexType[@name='#{index['type']}']")

        # Récupération des éléments, attributs et simpleContent
        @types[xsd_name][index['type']] = {}
        @types[xsd_name][index['type']]['xsd_elements_list'] = xsd_complex_type.xpath('.//xsd:element')
        @types[xsd_name][index['type']]['xsd_attributes_list'] = xsd_complex_type.xpath('.//xsd:attribute')
        @types[xsd_name][index['type']]['xsd_simplecontent_list'] = xsd_complex_type.xpath('.//xsd:simpleContent')
      end

      # S'il n'y a aucun élément et aucun attribut, retourner l'ensemble du contenu
      if @types[xsd_name][index['type']]['xsd_elements_list'].all? {|x| x.nil?} && @types[xsd_name][index['type']]['xsd_attributes_list'].all? {|x| x.nil?}
        return xml.to_s
      else
        # Traitement des attributs
        @types[xsd_name][index['type']]['xsd_attributes_list'].each do |attribut|
          # Récupération du code XML correspondant
          result[attribut['name']] = xml[attribut['name']]

          # Si c'est un type "CompoundKind", traiter son XML correspondant
          if attribut['type'] == 'CompoundKind'
            result['details'] = parse(xml['refid'], false)
          end
        end

        # Traitement des éléments
        @types[xsd_name][index['type']]['xsd_elements_list'].each do |xsd_element|
          element_array = []

          # Récupération du code XML correspondant
          xml_elements_list = xml.xpath("./#{xsd_element['name']}")

          xml_elements_list.each do |xml_element_code|
            if xsd_element['type'].nil? || xsd_element['type'].start_with?('xsd:')
              # Si c'est un type inconnu ou qu'il n'y a pas de type
              element_array.push xml_element_code.content.to_s
            else
              # Si c'est un type connu
              element_array.push rec_parse(xsd_element, xsd, xsd_name, xml_element_code)
            end
          end

          # Si c'est un "CompoundDef", envoyer directement le contenu
          if xsd_element['name'] == 'compounddef'
            return element_array[0]
          end

          result[xsd_element['name']] = element_array
        end

        # Traitement du texte s'il s'agit d'un SimpleContent
        unless @types[xsd_name][index['type']]['xsd_simplecontent_list'].empty?
          result['content'] = xml.content.to_s
        end
      end

      result
    end

    # Fonction de traitement d'un fichier XML
    def parse(xml_filename, is_index)
      xml = Nokogiri::XML(File.open("#{$dir}#{xml_filename}.xml"))

      # Si le fichier correspond au fichier d'index
      if is_index
        xsd_first_element = 'doxygenindex'
      else
        xsd_first_element = 'doxygen'
      end

      xsd_name = xml.at_xpath("//#{xsd_first_element}")['xsi:noNamespaceSchemaLocation']
      xsd = Nokogiri::XML(File.open("#{$dir}#{xsd_name}"))

      xsd_doxygen_element = xsd.at_xpath("//xsd:element[@name='#{xsd_first_element}']")

      res = rec_parse(xsd_doxygen_element, xsd, xsd_name, xml.at_xpath("//#{xsd_first_element}"))

      if is_index
        @index_hash = res
      else
        res
      end
    end

    # Fonction de génération des fichiers HTML
    def generate_html
      compounds = []
      groups = []
      classes = []
      pages = []

      @index_hash['compound'].each do |value|
        #ap value
        #puts '============================'

        compounds.push value

        if value['kind'] == 'group'
          groups.push value
        elsif value['kind'] == 'class'
          classes.push value
        elsif value['kind'] == 'page'
          pages.push value
        end
      end

      loop do
        FileUtils.copy_entry('../files', '../output', false, false, true)

        template = Liquid::Template.parse(File.read('../templates/base.liquid'))
        template.assigns['PROJECT_NAME'] = @project_name
        template.assigns['compounds'] = compounds
        template.assigns['groups'] = groups

        # Main page
        pages.each do |compound|
          if compound['refid'] == 'indexpage'
            File.write('../output/html/main.html', template.render('pagetype' => 'mainpage',
                                                                   'TITLE' => 'Main page',
                                                                   'compound' => compound))
            break
          end
        end

        # Index
        File.write('../output/html/classes.html', template.render('pagetype' => 'classes',
                                                                  'TITLE' => 'Index page'))

        # Classes
        classes.each do |compound|
          File.write("../output/html/#{compound['refid']}.html", template.render('pagetype' => 'class',
                                                                                 'TITLE' => "#{compound['name'][0]}",
                                                                                 'compound' => compound))
        end

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
    dox.parse('index', true)
    dox.generate_html
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
