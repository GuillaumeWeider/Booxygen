#!/usr/bin/env ruby

require 'nokogiri'
require 'liquid'

module Booxygen
  VERSION = "0.3.1"

  class Templates
    def initialize(dir)

    end
  end

  class Doxygen
    def initialize
      @compounds = []
    end

    def parse(directory)
      xml = Nokogiri::XML(File.open(directory + '/index.xml'))

      xsd_name = xml.at_xpath('//doxygenindex')['xsi:noNamespaceSchemaLocation']
      xsd = Nokogiri::XML(File.open(directory + xsd_name))

      xsd_first_element = xsd.at_xpath('//xsd:element')

      # DoxygenType
      xsd_complex_type = xsd.at_xpath('//xsd:complexType[@name=\'' + xsd_first_element['type'] + '\']')

      # Elements et attributs de DoxygenType
      xsd_elements_list = xsd_complex_type.xpath('xsd:sequence/xsd:element')
      # xsd_attributs_list = xsd_complex_type.xpath('xsd:attribute')

      xsd_elements_list.each do |xsd_element|

        # Code de chacun des éléments
        xml_elements_list = xml.xpath('//doxygenindex/' + xsd_element['name'])

        xml_elements_list.each do |xml_element_code|
          element = {}

          # Récupération des éléments et attributs associés au type
          xsd_complex_type2 = xsd.at_xpath('//xsd:complexType[@name=\'' + xsd_element['type'] + '\']')

          xsd_elements_list2 = xsd_complex_type2.xpath('xsd:sequence/xsd:element')
          xsd_attributs_list2 = xsd_complex_type2.xpath('xsd:attribute')

          # Traiter tous les attributs
          xsd_attributs_list2.each do |attr2|
            element[attr2['name']] = xml_element_code[attr2['name']]
            puts attr2['name'] + ' : ' + element[attr2['name']]
          end

          # Traiter tous les éléments du XSD
          xsd_elements_list2.each do |xsd_element2|

            # Code de chacun des éléments en XML
            xml_elements_list2 = xml_element_code.xpath('./' + xsd_element2['name'])

            sub_element = {}
            xml_elements_list2.each do |xml_element_code2|

              if xsd_element2['type'].start_with?('xsd:')
                # Si c'est un type inconnu
                sub_element[0] = xml_element_code2
                puts xsd_element2['name'] + ' : ' + sub_element[0]

              else
                # Si c'est un type connu
                # Récupération des éléments et attributs associés au type
                xsd_complex_type3 = xsd.at_xpath('//xsd:complexType[@name=\'' + xsd_element2['type'] + '\']')

                xsd_elements_list3 = xsd_complex_type3.xpath('xsd:sequence/xsd:element')
                xsd_attributs_list3 = xsd_complex_type3.xpath('xsd:attribute')

                # Traiter tous les attributs
                xsd_attributs_list3.each do |attr3|
                  sub_element[attr3['name']] = xml_element_code2[attr3['name']]
                  puts attr3['name'] + ' : ' + sub_element[attr3['name']]
                end

                # Traiter tous les éléments
                xsd_elements_list3.each do |element3|
                  sub_element[element3['name']] = xml_element_code2.xpath(element3['name'])
                  sub_element[element3['name']].each do |element3_to_print|
                    puts element3['name'] + ' : ' + element3_to_print
                  end
                end
              end
            end

            #element['subelement_list'].push(sub_element)

            puts ' '
          end
          @compounds.push(element)
        end
      end

    end

    def print
      #@compounds.each do |node|
      #  puts node['kind'] + ' ' + node.at_xpath('name')
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
  # Définition d'une variable globale
  $dir = ARGV[0]
  Booxygen::run($dir)
else
  print "Unknown directory\n"
  abort
end
