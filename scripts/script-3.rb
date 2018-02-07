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
      if element.name == 'memberdef' and element['kind'] == 'define'

        define = {}
        define['id'] = element['id']
        define['name'] = element.at_xpath('name').to_s
        define['briefdesc'] = '' #TODO
        define['description'] = '' #TODO
        define['params'] = []

        element.xpath('param').each do |param|
          name = param.at_xpath('defname')
          unless name.nil?
            #TODO
          end
        end

        if define['briefdesc'] or define['description']
          return define
        else
          return nil
        end
      end
    end

    def parse_var(element)
      if element.name == 'memberdef' and element['kind'] == 'variable'

        var = {}
        var['id'] = element['id']
        var['name'] = element.at_xpath('name').to_s
        var['briefdesc'] = '' #TODO
        var['description'] = '' #TODO

        var['type'] = parse_type(element.at_xpath('type'))
        if var['type'].start_with?('constexpr')
          var['type'] = var['type'][10..length]
          var['is_constexpr'] = true
        else
          var['is_constexpr'] = false
        end

        var['is_static'] = element['static'] == 'yes'
        var['is_protected'] = element['prot'] == 'protected'
        var['is_private'] = element['prot'] == 'private'

        if var['briefdesc'] or var['description']
          return var
        else
          return nil
        end
      end
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
      element.to_s
    end

    def parse_ref(element)
      id = element['refid']
      url = '#'
      if element['kindref'] == 'compound'
        url = id + '.html'
      elsif element['kindref'] == 'member'
        index = id.rindex('_1')
        url = id[index..length] + '.html' + '#' + id[index + 1..length]
      end

      "<a href=\"#{url}\">#{element.innerHTML}</a>" # TODO Vérifier le texte
    end

    def parse(file_path)
      filename = File.basename(file_path)

      unless filename.start_with?('group_')
        return
      end
      @logger.info("Parsing #{filename}")

      xml = Nokogiri::XML(File.open("#{file_path}"))

      if xml.at_xpath('/*').name != 'doxygen'
        @logger.warn('File root tag isn\'t correct, skip it.')
      end

      compounddef = xml.xpath('//compounddef')

      if compounddef.length != 1
        @logger.warn("File content isn't correct, skip it.")
        return
      else
        compounddef = compounddef[0]
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

        puts 'ICI: ' + child.name
        # Directory / file
        if ['innerdir', 'innerfile'].include?(child.name)
          id = child['refid']

          if @compounds.include?(id)
            file = @compounds[id]

            f = {}
            f['url'] = file['url']
            f['name'] = file['short_name']
            f['briefdesc'] = file['briefdesc']

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

            if child.name == 'innernamespace'
              namespace = {}
              namespace['url'] = symbol['url']

              if compound['kind'] == 'namespace'
                namespace['name'] = symbol['short_name']
              else
                namespace['name'] = symbol['name']
              end

              namespace['briefdesc'] = symbol['briefdesc']
              compound['namespaces'].push(namespace)

            elsif child.name == 'innerclass'
              class_val = {}
              class_val['kind'] = symbol['kind']
              class_val['url'] = symbol['url']

              if ['namespace', 'class', 'struct', 'union'].include?(compound['kind'])
                class_val['name'] = symbol['short_name']

              else
                class_val['name'] = symbol['name']
              end

              class_val['briefdesc'] = symbol['briefdesc']

              # Put classes into the public/protected section for
              # inner classes
              if ['class', 'struct', 'union'].include?(compound['kind'])
                if child['prot'] == 'public'
                  compound['public_types'].push ['class', class_val]
                elsif child['prot'] == 'protected'
                  compound['protected_types'].push ['class', class_val]
                end
              elsif ['namespace', 'group', 'file'].include?(compound['kind'])
                compound['classes'].push(class_val)
              end
            end
          end
          # Base class (if it links to anywhere)
        elsif child.name == 'basecompoundref'
          if ['class', 'struct', 'union'].include?(compound['kind'])

            unless child['refid'].nil?
              id = child['refid']

              if @compounds.include?(id)
                symbol = @compounds[id]

                class_val = {}
                class_val['kind'] = symbol['kind']
                class_val['url'] = symbol['url']
                class_val['name'] = symbol['short_name']
                class_val['briefdesc'] = symbol['briefdesc']
                class_val['is_protected'] = child['prot'] == 'protected'
                class_val['is_virtual'] = child['virt'] == 'virtual'

                compound['base_classes'].push(class_val)
              end
            end
          end

          # Derived class
        elsif child.name == 'derivedcompoundref'
          if ['class', 'struct', 'union'].include?(compound['kind'])

            unless child['refid'].nil?
              id = child['refid']

              if @compounds.include?(id)
                symbol = @compounds[id]

                class_val = {}
                class_val['kind'] = symbol['kind']
                class_val['url'] = symbol['url']
                class_val['name'] = symbol['short_name']
                class_val['briefdesc'] = symbol['briefdesc']

                compound['derived_classes'].push(class_val)
              end
            end
          end

        elsif child.name == 'innergroup'
          if compound['kind'] == 'group'

            group = @compounds[child['refid']]
            g = {}
            g['url'] = group['url']
            g['name'] = group['short_name']
            g['briefdesc'] = group['briefdesc']

            compound['modules'].push(g)
          end

          # Other, grouped in sections
        elsif child.name == 'sectiondef'
          if child['kind'] == 'enum'
            child.elements.each do |memberdef|
              enum = parse_enum(memberdef)
              unless enum.nil?
                compound['enums'].push enum
              end
            end
          elsif child['kind'] == 'typedef'
            child.elements.each do |memberdef|
              typedef = parse_typedef(memberdef)
              if typedef
                compound['typedefs'].push typedef
              end
            end
          elsif child['kind'] == 'func'
            child.elements.each do |memberdef|
              func = parse_func(memberdef)
              if func
                compound['funcs'].push func
              end
            end
          elsif child['kind'] == 'var'
            child.elements.each do |memberdef|

              var = parse_var(memberdef)
              if var
                compound['vars'].push var
              end
            end
          elsif child['kind'] == 'define'
            child.elements.each do |memberdef|
              define = parse_define(memberdef)
              if define
                compound['defines'].push define
              end
            end
          elsif child['kind'] == 'public-type'
            child.elements.each do |memberdef|
              member = nil
              if memberdef['kind'] == 'enum'
                member = parse_enum(memberdef)
              else
                if memberdef['kind'] == 'typedef'
                  member = parse_typedef(memberdef)
                end
              end
              unless member.nil?
                compound['public_types'].push [memberdef['kind'], member]
              end
            end
          elsif child['kind'] == 'public-static-func'
            child.elements.each do |memberdef|
              func = parse_func(memberdef)
              if func
                compound['public_static_funcs'].push func
              end
            end
          elsif child['kind'] == 'public-func'
            child.elements.each do |memberdef|
              func = parse_func(memberdef)
              if func
                if func['type'].nil?
                  compound['typeless_funcs'].push func
                else
                  compound['public_funcs'].push func
                end
              end
            end
          elsif child['kind'] == 'public-static-attrib'
            child.elements.each do |memberdef|
              var = parse_var(memberdef)
              if var
                compound['public_static_vars'].push var
              end
            end
          elsif child['kind'] == 'public-attrib'
            child.elements.each do |memberdef|
              var = parse_var(memberdef)
              if var
                compound['public_vars'].push var
              end
            end
          elsif child['kind'] == 'protected-type'
            child.elements.each do |memberdef|
              member = nil
              if memberdef['kind'] == 'enum'
                member = parse_enum(memberdef)
              else
                if memberdef['kind'] == 'typedef'
                  member = parse_typedef(memberdef)
                end
              end
              unless member.nil?
                compound['protected_types'].push [memberdef['kind'], member]
              end
            end
          elsif child['kind'] == 'protected-static-func'
            child.elements.each do |memberdef|
              func = parse_func(memberdef)
              if func
                compound['protected_static_funcs'].push func
              end
            end
          elsif child['kind'] == 'protected-func'
            child.elements.each do |memberdef|
              func = parse_func(memberdef)
              if func
                if func['type'].nil?
                  compound['typeless_funcs'].push func
                else
                  compound['protected_funcs'].push func
                end
              end
            end
          elsif child['kind'] == 'protected-static-attrib'
            child.elements.each do |memberdef|
              var = parse_var(memberdef)
              if var
                compound['protected_static_vars'].push var
              end
            end
          elsif child['kind'] == 'protected-attrib'
            child.elements.each do |memberdef|
              var = parse_var(memberdef)
              if var
                compound['protected_vars'].push var
              end
            end
          elsif child['kind'] == 'private-func'
            # Gather only private functions that are virtual and
            # documented
            child.elements.each do |memberdef|
              if memberdef['virt'] == 'non-virtual'
                next
              end

              func = parse_func(memberdef)
              if func
                compound['private_funcs'].push func
              end
            end
          elsif child['kind'] == 'related'
            child.elements.each do |memberdef|
              if memberdef['kind'] == 'enum'
                enum = parse_enum(memberdef)
                if enum
                  compound['related'].push ['enum', enum]
                end
              elsif memberdef['kind'] == 'typedef'
                typedef = parse_typedef(memberdef)
                if typedef
                  compound['related'].push ['typedef', typedef]
                end
              elsif memberdef['kind'] == 'function'
                func = parse_func(memberdef)
                if func
                  compound['related'].push ['func', func]
                end
              elsif memberdef['kind'] == 'variable'
                var = parse_var(memberdef)
                if var
                  compound['related'].push ['var', var]
                end
              elsif memberdef['kind'] == 'define'
                define = parse_define(memberdef)
                if define
                  compound['related'].push ['define', define]
                end
              end
            end
          elsif child['kind'] == 'user-defined'
            list = []

            child.xpath('memberdef').each do |memberdef|
              if memberdef['kind'] == 'enum'
                enum = parse_enum(memberdef)
                if enum
                  list['enum'].push enum
                end
              elsif memberdef['kind'] == 'typedef'
                typedef = parse_typedef(memberdef)
                if typedef
                  list['typedef'].push typedef
                end
              elsif memberdef['kind'] == 'function'
                func = parse_func(memberdef)
                if func
                  list['func'].push func
                end
              elsif memberdef['kind'] == 'variable'
                var = parse_var(memberdef)
                if var
                  list['var'].push var
                end
              elsif memberdef['kind'] == 'define'
                define = parse_define(memberdef)
                if define
                  list['define'].push define
                end
              end
            end

            if list
              header = child.at_xpath('header')
              if header.nil?
                logger.error("{} member groups without @name are not supported, ignoring")
              else
                group = {}
                group['name'] = header['text']
                group['id'] = group['name']
                group['description'] = parse_desc(child.at_xpath('description'))
                group['members'] = list
                compound['groups'].push group
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
            logger.warning("{} ignoring <{}> in <compounddef>".format(state.current, child.name))
          end
        end
      end

      compound
    end

    def start

      # Build XML files list
      xml_files = Dir.glob("#{$dir}/*.xml").sort

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

          # Look for children's ID
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

      # Look for parent's ID
      @compounds.each_value do |element|
        element['children'].each do |refid|
          if @compounds.has_key?(refid)
            @compounds[refid]['parent'] = element['id']
          end
        end
      end

      # Create the short name, without namespace prefix
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

      groups = []

      # Treat all XML files, parse
      xml_files.each do |file_path|
        # If file is index.xml skip for now
        next if File.basename(file_path) == 'index.xml'


        # parsed = parse(file_path)
        # if parsed.nil?
        #   next
        # end
        #
        # if parsed['kind'] == 'group'
        #   groups.push parsed
        # end
        # puts 'ID: ' + parsed['id']
        # puts 'Kind: ' + parsed['kind']
        # puts 'Name: ' + parsed['name']
        # puts 'URL: ' + parsed['url']
        # puts ''
      end


      classes = []

      @compounds.each_value do |value|

        if value['kind'] == 'class'
          classes.push value
        end
      end

      loop do
        FileUtils.copy_entry('../files', '../output', false, false, true)

        template = Liquid::Template.parse(File.read('../templates/base.liquid'))
        template.assigns['PROJECT_NAME'] = @project_name
        template.assigns['compounds'] = @compounds
        template.assigns['groups'] = groups

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
                                                                  'classes_index' => classes))

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
