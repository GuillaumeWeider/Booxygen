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

    def parse_define(element)

    end

    def parse_var(element)

    end

    def parse_func(element)

    end

    def parse_typedef(element)

    end

    def parse_enum(element)

    end

    def parse_inline_desc(element)

    end

    def parse_define_desc(element)

    end

    def parse_func_desc(element)

    end

    def parse_typedef_desc(element)

    end

    def parse_toplevel_desc(element)

    end

    def parse_var_desc(element)

    end

    def parse_enum_value_desc(element)

    end

    def parse_enum_desc(element)

    end

    def parse_desc(element)

    end

    def parse_desc_internal(element)

    end

    def parse_type(element)

    end

    def parse_ref(element)

    end

    def parse(file_path)
      filename = File.basename(file_path)

      @logger.info("Parsing #{filename}.xml")

      xml = Nokogiri::XML(File.open("#{filename}"))

      if xml.at_xpath('name(/*)') != 'doxygen'
        @logger.warn('File root tag isn\'t correct, skip it.')
      end

      compounddef = xml.xpath('compounddef')
      if compounddef.length != 1
        @logger.warn('File content isn\'t correct, skip it.')
      end

      compound = {}
      compound['kind'] = compounddef['kind']
      compound['id'] = compounddef['id']

      # Compound name is page filename, so we have to use title there. The same
      # is for groups.

      if ['page', 'group'].include?(compound['kind'])
        compound['name'] = compounddef.at_xpath('title/node()').to_s
      else
        compound['name'] = compounddef.at_xpath('compoundname/node()').to_s
      end

      if compound['kind'] == 'page'
        compound['url'] = compounddef.at_xpath('compoundname/node()').to_s + '.html'
      else
        compound['url'] = compound['id'] + '.html'
      end

      compound['briefdesc'] = '' #TODO

      compound['modules'] = []
      compound['dirs'] = []
      compound['files'] = []
      compound['namespaces'] = []
      compound['classes'] = []
      compound['base_classes'] = []
      compound['derived_classes'] = []
      compound['enums'] = []
      compound['typedefs'] = []
      compound['funcs'] = []
      compound['vars'] = []
      compound['defines'] = []
      compound['public_types'] = []
      compound['public_static_funcs'] = []
      compound['typeless_funcs'] = []
      compound['public_funcs'] = []
      compound['public_static_vars'] = []
      compound['public_vars'] = []
      compound['protected_types'] = []
      compound['protected_static_funcs'] = []
      compound['protected_funcs'] = []
      compound['protected_static_vars'] = []
      compound['protected_vars'] = []
      compound['private_funcs'] = []
      compound['related'] = []
      compound['groups'] = []

      if compound['kind'] == 'page'

      end

      compounddef_elements = compounddef.children
      compounddef_elements.each do |child|

        # Directory / file
        if ['innerdir', 'innerfile'].include?(child.name)
          id = child['refid']

          if @compounds.include?(id)
            file = @compounds[id]

            f = {}
            f['url'] = file['url']
            f['name'] = file['leaf_name']
            f['brief'] = file['brief']

            if child.name == 'innerdir'
              compound['dirs'].push(f)
            elsif child.name == 'innerfile'
              compound['files'].push(f)
            end

          end

          # Namespace / class
        elsif ['innernamespace', 'innerclass'].include?(child.name)
          id = child['refid']

          if @compounds.include?(id)
            symbol = @compounds[id]

            if child['name'] == 'innernamespace'
              namespace = {}
              namespace['url'] = symbol['url']

              if compound['kind'] == 'namespace'
                namespace['name'] = symbol['leaf_name']
              else
                namespace['name'] = symbol['name']
              end

              namespace['brief'] = symbol['brief']
              compound['namespaces'].push(namespace)

            elsif child['name'] == 'innerclass'

              class_val = {}
              class_val['kind'] = symbol['kind']
              class_val['url'] = symbol['url']

              if ['namespace', 'class', 'struct', 'union'].include?(compound['kind'])
                class_val['name'] = symbol['leaf_name']
              else
                class_val['name'] = symbol['name']
              end

              class_val['brief'] = symbol['brief']

              # Put classes into the public/protected section for
              # inner classes
              if ['class', 'struct', 'union'].include?(compound['kind'])
                if child['prot'] == 'public'
                  compound['public_types']['class'] += class_val
                elsif child['prot'] == 'protected'
                  compound['protected_types']['class'] += class_val
                end
              elsif ['namespace', 'group', 'file'].include?(compound['kind'])
                compound['classes'].push(class_val)
              end

              # Base class (if it links to anywhere)
            elsif child['name'] == 'basecompoundref'
              if ['class', 'struct', 'union'].include?(compound['kind'])

                unless child['refid'].nil?
                  id = child['refid']

                  if @compounds.include?(id)
                    symbol = @compounds[id]

                    class_val = {}
                    class_val['kind'] = symbol['kind']
                    class_val['url'] = symbol['url']
                    class_val['name'] = symbol['leaf_name']
                    class_val['brief'] = symbol['brief']
                    class_val['is_protected'] = child['prot'] == 'protected'
                    class_val['is_virtual'] = child['virt'] == 'virtual'

                    compound['base_classes'].push(class_val)
                  end
                end
              end

              # Derived class
            elsif child['name'] == 'derivedcompoundref'
              if ['class', 'struct', 'union'].include?(compound['kind'])

                unless child['refid'].nil?
                  id = child['refid']

                  if @compounds.include?(id)
                    symbol = @compounds[id]

                    class_val = {}
                    class_val['kind'] = symbol['kind']
                    class_val['url'] = symbol['url']
                    class_val['name'] = symbol['leaf_name']
                    class_val['brief'] = symbol['brief']

                    compound['derived_classes'].push(class_val)
                  end
                end
              end

            elsif child['name'] == 'innergroup'
              if compound['kind'] == 'group'

                group = @compounds[child['refid']]
                g = {}
                g['url'] = group['url']
                g['name'] = group['leaf_name']
                g['brief'] = group['brief']

                compound['modules'].push(g)
              end

              # Other, grouped in sections
            elsif child.tag == 'sectiondef'
              if child['kind'] == 'enum'
                child.each do |memberdef|
                  enum = parse_enum(memberdef)
                  unless enum.nil?
                    compound['enums'] += enum
                  end
                end
              elsif child['kind'] == 'typedef'
                child.each do |memberdef|
                  typedef = parse_typedef(memberdef)
                  if typedef
                    compound['typedefs'] += typedef
                  end
                end
              elsif child['kind'] == 'func'
                child.each do |memberdef|
                  func = parse_func(memberdef)
                  if func
                    compound['funcs'] += func
                  end
                end
              elsif child['kind'] == 'var'
                child.each do |memberdef|
                  var = parse_var(memberdef)
                  if var
                    compound['vars'] += var
                  end
                end
              elsif child['kind'] == 'define'
                child.each do |memberdef|
                  define = parse_define(memberdef)
                  if define
                    compound['defines'] += define
                  end
                end
              elsif child['kind'] == 'public-type'
                child.each do |memberdef|
                  if memberdef['kind'] == 'enum'
                    member = parse_enum(memberdef)
                  else
                    if memberdef['kind'] == 'typedef'
                      member = parse_typedef(memberdef)
                    end
                  end
                  #if member compound['public_types'] += [(memberdef['kind'], member)]
                  #end TODO
                end
              elsif child['kind'] == 'public-static-func'
                child.each do |memberdef|
                  func = parse_func(memberdef)
                  if func
                    compound['public_static_funcs'] += func
                  end
                end
              elsif child['kind'] == 'public-func'
                child.each do |memberdef|
                  func = parse_func(memberdef)
                  if func
                    if func['type'].nil?
                      compound['typeless_funcs'] += func
                    else
                      compound['public_funcs'] += func
                    end
                  end
                end
              elsif child['kind'] == 'public-static-attrib'
                child.each do |memberdef|
                  var = parse_var(memberdef)
                  if var
                    compound['public_static_vars'] += var
                  end
                end
              elsif child['kind'] == 'public-attrib'
                child.each do |memberdef|
                  var = parse_var(memberdef)
                  if var
                    compound['public_vars'] += var
                  end
                end
              elsif child['kind'] == 'protected-type'
                child.each do |memberdef|
                  if memberdef['kind'] == 'enum'
                    member = parse_enum(memberdef)
                  else
                    if memberdef['kind'] == 'typedef'
                      member = parse_typedef(memberdef)
                    end
                  end

                  #if member compound['protected_types'] += [(memberdef['kind'], member)]
                  #  end TODO
                end
              elsif child['kind'] == 'protected-static-func'
                child.each do |memberdef|
                  func = parse_func(memberdef)
                  if func
                    compound['protected_static_funcs'] += func
                  end
                end
              elsif child['kind'] == 'protected-func'
                child.each do |memberdef|
                  func = parse_func(memberdef)
                  if func
                    if func.type.nil?
                      compound['typeless_funcs'] += func
                    else
                      compound['protected_funcs'] += func
                    end
                  end
                end
              elsif child['kind'] == 'protected-static-attrib'
                child.each do |memberdef|
                  var = parse_var(memberdef)
                  if var
                    compound['protected_static_vars'] += var
                  end
                end
              elsif child['kind'] == 'protected-attrib'
                child.each do |memberdef|
                  var = parse_var(memberdef)
                  if var
                    compound['protected_vars'] += var
                  end
                end
              elsif child['kind'] == 'private-func'
                # Gather only private functions that are virtual and
                # documented
                child.each do |memberdef|
                  if memberdef['virt'] == 'non-virtual'
                    next
                  end

                  func = parse_func(memberdef)
                  if func
                    compound['private_funcs'] += func
                  end
                end
              elsif child['kind'] == 'related'
                child.each do |memberdef|
                  if memberdef['kind'] == 'enum'
                    enum = parse_enum(memberdef)
                    if enum
                      compound['related']['enum'] += enum
                    end
                  elsif memberdef['kind'] == 'typedef'
                    typedef = parse_typedef(memberdef)
                    if typedef
                      compound['related']['typedef'] += typedef
                    end
                  elsif memberdef['kind'] == 'function'
                    func = parse_func(memberdef)
                    if func
                      compound['related']['func'] += func
                    end
                  elsif memberdef['kind'] == 'variable'
                    var = parse_var(memberdef)
                    if var
                      compound['related']['var'] += var
                    end
                  elsif memberdef['kind'] == 'define'
                    define = parse_define(memberdef)
                    if define
                      compound['related']['define'] += define
                    end
                  end
                end
              elsif child['kind'] == 'user-defined'
                list = []

                  child.xpath('memberdef').each do |memberdef|
                  if memberdef['kind'] == 'enum'
                    enum = parse_enum(memberdef)
                    if enum
                      list['enum'] += enum
                    end
                  elsif memberdef['kind'] == 'typedef'
                    typedef = parse_typedef(memberdef)
                    if typedef
                      list['typedef'] += typedef
                    end
                  elsif memberdef['kind'] == 'function'
                    func = parse_func(memberdef)
                    if func
                      list['func'] += func
                    end
                  elsif memberdef['kind'] == 'variable'
                    var = parse_var(memberdef)
                    if var
                      list['var'] += var
                    end
                  elsif memberdef['kind'] == 'define'
                    define = parse_define(memberdef)
                    if define
                      list['define'] += define
                    end
                  end
                end

                if list
                  header = child.find('header')
                  if header.nil?
                    logger.error("{} member groups without @name are not supported, ignoring")
                  else
                    group = {}
                    group['name'] = header['text']
                    group['id'] = group['name']
                    group['description'] = parse_desc(child.find('description'))
                    group['members'] = list
                    compound['groups'] += [group]
                  end
                elsif !['private-type',
                        'private-static-func',
                        'private-static-attrib',
                        'private-attrib',
                        'friend'].include?(child['kind'])
                  logger.warning("{} unknown <sectiondef> kind {}".format(state.current, child['kind']))
                end
              elsif !['compoundname',
                      'briefdescription',
                      'detaileddescription',
                      'innerpage', # doesn't add anything to output
                      'location',
                      'includes',
                      'includedby',
                      'incdepgraph',
                      'invincdepgraph',
                      'inheritancegraph',
                      'collaborationgraph',
                      'listofallmembers',
                      'tableofcontents'].include?(child.name) and
                  !(['page', 'group'].include?(compounddef['kind']) and child.name == 'title')
                logger.warning("{} ignoring <{}> in <compounddef>".format(state.current, child.tag))
              end
            end
          end
        end
      end
    end

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


      @compounds.each_value do |element|
        puts 'ID: ' + element['id']
        puts 'Kind: ' + element['kind']
        puts 'Name: ' + element['name']
        puts 'Short name: ' + element['short_name']
        puts 'URL: ' + element['url']
        puts ''
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
