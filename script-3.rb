#!/usr/bin/env ruby

require 'nokogiri'
require 'liquid'

module Booxygen
  VERSION = "0.3.2"

  class Templates
    def initialize(dir)

    end
  end

  class Doxygen
    def initialize
      @compounds = {}
    end

    def parse(directory)
      xml = Nokogiri::XML(File.open(directory + '/index.xml'))

      xsd_name = xml.at_xpath('//doxygenindex')['xsi:noNamespaceSchemaLocation']
      xsd = Nokogiri::XML(File.open(directory + xsd_name))

      xsd_first_element = xsd.at_xpath('//xsd:element')

      @compounds = rec_parse(xsd_first_element,xsd,xml.at_xpath('//doxygenindex'))
    end

    def rec_parse(index, xsd_file, xml)
      result = {}

      xsd_complex_type = xsd_file.at_xpath("//xsd:complexType[@name='#{index['type']}']")

      # Récupération des éléments et attributs
      xsd_elements_list = xsd_complex_type.xpath('.//xsd:sequence/xsd:element')
      xsd_attributs_list = xsd_complex_type.xpath('.//xsd:attribute')


      # Traitement des attributs
      xsd_attributs_list.each do |attribut|
        result[attribut['name']] = xml[attribut['name']]
      end


      # Traitement des éléments
      xsd_elements_list.each do |xsd_element|
        xml_elements_list = xml.xpath("./#{xsd_element['name']}")

        xml_elements_list.each_with_index do |xml_element_code, index_nbr|
          element = {}

          if xsd_element['type'].start_with?('xsd:')
            # Si c'est un type inconnu
            element[xsd_element['name']] = xml_element_code
          else
            # Si c'est un type connu
            element[xsd_element['name']] = rec_parse(xsd_element, xsd_file, xml_element_code)
          end

          result[index_nbr] = element
        end
      end

      result
    end

    def rec_print_res(content)
      if content.is_a?(Array)
        content.each do |value|
          rec_print_res value
        end
      elsif content.is_a?(Hash)
        content.each do |key, value|
          print "#{key} : "
          rec_print_res value
        end
      else
        print content, "\n"
      end
    end

    def print_res
      @compounds.each do |node|
        rec_print_res node
        print "\n"
      end
    end
  end

  def self.run(directory)
    dox = Doxygen.new
    dox.parse(directory)
    dox.print_res
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
