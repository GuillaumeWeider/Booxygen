def parse_ref(state: State, element: ET.Element) -> str:
    id = element.attrib['refid']

    if element.attrib['kindref'] == 'compound':
        url = id + '.html'
    elif element.attrib['kindref'] == 'member':
        i = id.rindex('_1')
        url = id[:i] + '.html' + '#' + id[i+2:]
    else: # pragma: no cover
        logging.critical("{}: unknown <ref> kind {}".format(state.current, element.attrib['kindref']))
        assert False

    if 'external' in element.attrib:
        for i in state.doxyfile['TAGFILES']:
            name, _, baseurl = i.partition('=')
            if os.path.basename(name) == os.path.basename(element.attrib['external']):
                url = os.path.join(baseurl, url)
                break
        else: # pragma: no cover
            logging.critical("{}: tagfile {} not specified in Doxyfile".format(state.current, element.attrib['external']))
            assert False
        class_ = 'm-dox-external'
    else:
        class_ = 'm-dox'

    return '<a href="{}" class="{}">{}</a>'.format(url, class_, add_wbr(parse_inline_desc(state, element).strip()))

def parse_type(state: State, type: ET.Element) -> str:
    # Constructors and typeless enums might not have it
    if type is None: return None
    out = html.escape(type.text) if type.text else ''

    i: ET.Element
    for i in type:
        if i.tag == 'ref':
            out += parse_ref(state, i)
        elif i.tag == 'anchor':
            out += '<a name="{}"></a>'.format(extract_id(i))
        else: # pragma: no cover
            logging.warning("{}: ignoring {} in <type>".format(state.current, i.tag))

        if i.tail: out += html.escape(i.tail)

    # Warn if suspicious stuff is present
    if '_EXPORT' in out or '_LOCAL' in out:
        logging.warning("{}: type contains an export macro: {}".format(state.current, ''.join(type.itertext())))

    # Remove spacing inside <> and before & and *
    return fix_type_spacing(out)

def parse_desc_internal(state: State, element: ET.Element, immediate_parent: ET.Element = None, trim = True, add_css_class = None):
    out = Empty()
    out.section = None
    out.templates = {}
    out.params = {}
    out.return_value = None
    out.add_css_class = None
    out.footer_navigation = False
    out.example_navigation = None
    out.search_keywords = []
    out.search_enum_values_as_keywords = False
    out.is_deprecated = False

    # DOXYGEN <PARA> PATCHING 1/4
    #
    # In the optimistic case, when parsing the <para> element, the parsed
    # content is treated as single reasonable paragraph and the caller is told
    # to write both <p> and </p> enclosing tag.
    #
    # Unfortunately Doxygen puts some *block* elements inside a <para> element
    # instead of closing it before and opening it again after. That is making
    # me raging mad. Nested paragraphs are no way valid HTML and they are ugly
    # and problematic in all ways you can imagine, so it's needed to be
    # patched. See the long ranty comments below for more parts of the story.
    out.write_paragraph_start_tag = element.tag == 'para'
    out.write_paragraph_close_tag = element.tag == 'para'
    out.is_reasonable_paragraph = element.tag == 'para'

    out.parsed: str = ''
    if element.text:
        out.parsed = html.escape(element.text.strip() if trim else element.text)

        # There's some inline text at the start, *do not* add any CSS class to
        # the first child element
        add_css_class = None

    # Needed later for deciding whether we can strip the surrounding <p> from
    # the content
    paragraph_count = 0
    has_block_elements = False

    # So we are able to merge content of adjacent sections. Tuple of (tag,
    # kind), set only if there is no i.tail, reset in the next iteration.
    previous_section = None

    # A CSS class to be added inline (not propagated outside of the paragraph)
    add_inline_css_class = None

    i: ET.Element
    for index, i in enumerate(element):
        # State used later
        code_block = None
        formula_block = None

        # A section was left open, but there's nothing to continue it, close
        # it. Expect that there was nothing after that would mess with us.
        # Don't reset it back to None just yet, as inline/block code
        # autodetection needs it.
        if previous_section and (i.tag != 'simplesect' or i.attrib['kind'] == 'return'):
            assert not out.write_paragraph_close_tag
            out.parsed = out.parsed.rstrip() + '</aside>'

        # DOXYGEN <PARA> PATCHING 2/4
        #
        # Upon encountering a block element nested in <para>, we need to act.
        # If there was any content before, we close the paragraph. If there
        # wasn't, we tell the caller to not even open the paragraph. After
        # processing the following tag, there probably won't be any paragraph
        # open, so we also tell the caller that there's no need to close
        # anything (but it's not that simple, see for more patching at the end
        # of the cycle iteration).
        #
        # Those elements are:
        # - <heading>
        # - <blockquote>
        # - <simplesect> (if not describing return type) and <xrefsect>
        # - <verbatim>, <preformatted> (those are the same thing!)
        # - <variablelist>, <itemizedlist>, <orderedlist>
        # - <image>, <table>
        # - <mcss:div>
        # - <formula> (if block)
        # - <programlisting> (if block)
        #
        # <parameterlist> and <simplesect kind="return"> are extracted out of
        # the text flow, so these are removed from this check.
        #
        # In addition, there's special handling to achieve things like this:
        #   <ul>
        #     <li>A paragraph
        #       <ul>
        #         <li>A nested list item</li>
        #       </ul>
        #     </li>
        # I.e., not wrapping "A paragraph" in a <p>, but only if it's
        # immediately followed by another and it's the first paragraph in a
        # list item. We check that using the immediate_parent variable.
        if element.tag == 'para':
            end_previous_paragraph = False

            # Straightforward elements
            if i.tag in ['heading', 'blockquote', 'xrefsect', 'variablelist', 'verbatim', 'preformatted', 'itemizedlist', 'orderedlist', 'image', 'table', '{http://mcss.mosra.cz/doxygen/}div']:
                end_previous_paragraph = True

            # <simplesect> describing return type is cut out of text flow, so
            # it doesn't contribute
            elif i.tag == 'simplesect' and i.attrib['kind'] != 'return':
                end_previous_paragraph = True

            # <formula> can be both, depending on what's inside
            elif i.tag == 'formula':
                if i.text.startswith('$') and i.text.endswith('$'):
                    formula_block = False
                else:
                    end_previous_paragraph = True
                    formula_block = True

            # <programlisting> is autodetected to be either block or inline
            elif i.tag == 'programlisting':
                element_children_count = len([listing for listing in element])

                # If it seems to be a standalone code paragraph, don't wrap it
                # in <p> and use <pre>:
                if (
                    # It's either alone in the paragraph, with no text or other
                    # elements around, or
                    ((not element.text or not element.text.strip()) and (not i.tail or not i.tail.strip()) and element_children_count == 1) or

                    # is a code snippet, i.e. filename instead of just .ext
                    # (Doxygen unfortunately doesn't put @snippet in its own
                    # paragraph even if it's separated by blank lines. It does
                    # so for @include and related, though.)
                    ('filename' in i.attrib and not i.attrib['filename'].startswith('.')) or

                    # or is code right after a note/attention/... section,
                    # there's no text after and it's the last thing in the
                    # paragraph (Doxygen ALSO doesn't separate end of a section
                    # and begin of a code block by a paragraph even if there is
                    # a blank line. But it does so for xrefitems such as @todo.
                    # I don't even.)
                    (previous_section and (not i.tail or not i.tail.strip()) and index + 1 == element_children_count)
                ):
                    end_previous_paragraph = True
                    code_block = True

                # Looks like inline code, but has multiple code lines, so it's
                # suspicious. Use code block, but warn.
                elif len([codeline for codeline in i]) > 1:
                    end_previous_paragraph = True
                    code_block = True
                    logging.warning("{}: inline code has multiple lines, fallback to a code block".format(state.current))

                # Otherwise wrap it in <p> and use <code>
                else:
                    code_block = False

            if end_previous_paragraph:
                out.is_reasonable_paragraph = False
                out.parsed = out.parsed.rstrip()
                if not out.parsed:
                    out.write_paragraph_start_tag = False
                elif immediate_parent and immediate_parent.tag == 'listitem' and i.tag in ['itemizedlist', 'orderedlist']:
                    out.write_paragraph_start_tag = False
                elif out.write_paragraph_close_tag:
                    out.parsed += '</p>'
                out.write_paragraph_close_tag = False

            # There might be *inline* elements that need to start a *new*
            # paragraph, on the other hand. OF COURSE DOXYGEN DOESN'T DO THAT
            # EITHER. There's a similar block of code that handles case with
            # non-empty i.tail() at the end of the loop iteration.
            if not out.write_paragraph_close_tag and (i.tag in ['linebreak', 'anchor', 'computeroutput', 'emphasis', 'bold', 'ref', 'ulink'] or (i.tag == 'formula' and not formula_block) or (i.tag == 'programlisting' and not code_block)):
                # Assume sanity -- we are *either* closing a paragraph because
                # a new block element appeared after inline stuff *or* opening
                # a paragraph because there's inline text after a block
                # element and that is mutually exclusive.
                assert not end_previous_paragraph
                out.parsed += '<p>'
                out.write_paragraph_close_tag = True

        # Block elements
        if i.tag in ['sect1', 'sect2', 'sect3']:
            assert element.tag != 'para' # should be top-level block element
            has_block_elements = True

            parsed = parse_desc_internal(state, i)
            assert parsed.section
            assert not parsed.templates and not parsed.params and not parsed.return_value

            # Top-level section has no ID or title
            if not out.section: out.section = ('', '', [])
            out.section = (out.section[0], out.section[1], out.section[2] + [parsed.section])
            out.parsed += '<section id="{}">{}</section>'.format(extract_id(i), parsed.parsed)

        elif i.tag == 'title':
            assert element.tag != 'para' # should be top-level block element
            has_block_elements = True

            if element.tag == 'sect1':
                tag = 'h2'
            elif element.tag == 'sect2':
                tag = 'h3'
            elif element.tag == 'sect3':
                tag = 'h4'
            else: # pragma: no cover
                assert False
            id = extract_id(element)
            title = html.escape(i.text)

            # Populate section info
            assert not out.section
            out.section = (id, title, [])
            out.parsed += '<{0}><a href="#{1}">{2}</a></{0}>'.format(tag, id, title)

        elif i.tag == 'heading':
            assert element.tag == 'para' # is inside a paragraph :/
            has_block_elements = True

            if i.attrib['level'] == '1':
                tag = 'h2'
            elif i.attrib['level'] == '2':
                tag = 'h3'
            elif i.attrib['level'] == '3':
                tag = 'h4'
            elif i.attrib['level'] == '4':
                tag = 'h5'
            else: # pragma: no cover
                assert False
            logging.warning("{}: prefer @section over Markdown heading for properly generated TOC".format(state.current))
            out.parsed += '<{0}>{1}</{0}>'.format(tag, html.escape(i.text))

        elif i.tag == 'para':
            assert element.tag != 'para' # should be top-level block element
            paragraph_count += 1

            # DOXYGEN <PARA> PATCHING 3/4
            #
            # Parse contents of the paragraph, don't trim whitespace around
            # nested elements but trim it at the begin and end of the paragraph
            # itself. Also, some paragraphs are actually block content and we
            # might not want to write the start/closing tag.
            #
            # There's also the patching of nested lists that results in the
            # immediate_parent variable in the section 2/4 -- we pass the
            # parent only if this is the first paragraph inside it.
            parsed = parse_desc_internal(state, i,
                immediate_parent=element if paragraph_count == 1 and not has_block_elements else None,
                trim=False,
                add_css_class=add_css_class)
            parsed.parsed = parsed.parsed.strip()
            if not parsed.is_reasonable_paragraph:
                has_block_elements = True
            if parsed.parsed:
                if parsed.write_paragraph_start_tag:
                    # If there is some inline content at the beginning, assume
                    # the CSS class was meant to be added to the paragraph
                    # itself, not into a nested (block) element.
                    out.parsed += '<p{}>'.format(' class="{}"'.format(add_css_class) if add_css_class else '')
                out.parsed += parsed.parsed
                if parsed.write_paragraph_close_tag: out.parsed += '</p>'

            # Also, to make things even funnier, parameter and return value
            # description come from inside of some paragraph, so bubble them
            # up. Unfortunately they can be scattered around, so merge them.
            if parsed.templates:
                out.templates.update(parsed.templates)
            if parsed.params:
                out.params.update(parsed.params)
            if parsed.return_value:
                if out.return_value:
                    logging.warning("{}: superfluous @return section found, ignoring: {} ".format(state.current, ''.join(i.itertext())))
                else:
                    out.return_value = parsed.return_value

            # The same is (of course) with bubbling up the <mcss:class>
            # element. Reset the current value with the value coming from
            # inside -- it's either reset back to None or scheduled to be used
            # in the next iteration. In order to make this work, the resetting
            # code at the end of the loop iteration resets it to None only if
            # this is not a paragraph or the <mcss:class> element -- so we are
            # resetting here explicitly.
            add_css_class = parsed.add_css_class

            # Bubble up also footer / example navigation, search keywords,
            # deprecation flag
            if parsed.footer_navigation: out.footer_navigation = True
            if parsed.example_navigation: out.example_navigation = parsed.example_navigation
            out.search_keywords += parsed.search_keywords
            if parsed.search_enum_values_as_keywords: out.search_enum_values_as_keywords = True
            if parsed.is_deprecated: out.is_deprecated = True

            # Assert we didn't miss anything important
            assert not parsed.section

        elif i.tag == 'blockquote':
            assert element.tag == 'para' # is inside a paragraph :/
            has_block_elements = True
            out.parsed += '<blockquote>{}</blockquote>'.format(parse_desc(state, i))

        elif i.tag in ['itemizedlist', 'orderedlist']:
            assert element.tag == 'para' # is inside a paragraph :/
            has_block_elements = True
            tag = 'ul' if i.tag == 'itemizedlist' else 'ol'
            out.parsed += '<{}{}>'.format(tag,
                ' class="{}"'.format(add_css_class) if add_css_class else '')
            for li in i:
                assert li.tag == 'listitem'
                out.parsed += '<li>{}</li>'.format(parse_desc(state, li))
            out.parsed += '</{}>'.format(tag)

        elif i.tag == 'table':
            assert element.tag == 'para' # is inside a paragraph :/
            has_block_elements = True
            out.parsed += '<table class="m-table{}">'.format(
                ' ' + add_css_class if add_css_class else '')
            thead_written = False
            inside_tbody = False

            row: ET.Element
            for row in i:
                assert row.tag == 'row'
                is_header_row = True
                row_data = ''
                for entry in row:
                    assert entry.tag == 'entry'
                    is_header = entry.attrib['thead'] == 'yes'
                    is_header_row = is_header_row and is_header
                    row_data += '<{0}>{1}</{0}>'.format('th' if is_header else 'td', parse_desc(state, entry))

                # Table head is opened upon encountering first header row
                # and closed upon encountering first body row (in case it was
                # ever opened). Encountering header row inside body again will
                # not do anything special.
                if is_header_row:
                    if not thead_written:
                        out.parsed += '<thead>'
                        thead_written = True
                else:
                    if thead_written and not inside_tbody:
                        out.parsed += '</thead>'
                    if not inside_tbody:
                        out.parsed += '<tbody>'
                        inside_tbody = True

                out.parsed += '<tr>{}</tr>'.format(row_data)

            if inside_tbody: out.parsed += '</tbody>'
            out.parsed += '</table>'

        elif i.tag == 'simplesect':
            assert element.tag == 'para' # is inside a paragraph :/

            # Return value is separated from the text flow
            if i.attrib['kind'] == 'return':
                if out.return_value:
                    logging.warning("{}: superfluous @return section found, ignoring: {} ".format(state.current, ''.join(i.itertext())))
                else:
                    out.return_value = parse_desc(state, i)
            # Ignore the RCS strings for now
            elif i.attrib['kind'] == 'rcs':
                logging.warning("{}: ignoring {} kind of <simplesect>".format(state.current, i.attrib['kind']))
            else:
                has_block_elements = True

                # There was a section open, but it differs from this one, close
                # it
                if previous_section and previous_section != i.attrib['kind']:
                    out.parsed = out.parsed.rstrip() + '</aside>'

                # Not continuing with a section from before, put a header in
                if not previous_section or previous_section != i.attrib['kind']:
                    if i.attrib['kind'] == 'see':
                        out.parsed += '<aside class="m-note m-default"><h4>See also</h4>'
                    elif i.attrib['kind'] == 'note':
                        out.parsed += '<aside class="m-note m-info"><h4>Note</h4>'
                    elif i.attrib['kind'] == 'attention':
                        out.parsed += '<aside class="m-note m-warning"><h4>Attention</h4>'
                    elif i.attrib['kind'] == 'warning':
                        out.parsed += '<aside class="m-note m-danger"><h4>Warning</h4>'
                    else: # pragma: no cover
                        out.parsed += '<aside class="m-note">'
                        logging.warning("{}: ignoring {} kind of <simplesect>".format(state.current, i.attrib['kind']))

                out.parsed += parse_desc(state, i)

                # There's something after, close it
                if i.tail and i.tail.strip():
                    out.parsed += '</aside>'
                    previous_section = None

                # Otherwise put the responsibility on the next iteration, maybe
                # there are more paragraphs that should be merged
                else:
                    previous_section = i.attrib['kind']

        elif i.tag == 'xrefsect':
            assert element.tag == 'para' # is inside a paragraph :/
            has_block_elements = True

            # Not merging these, as every has usually a different ID each. (And
            # apparently Doxygen is able to merge them *but only if* they
            # describe some symbol, not on a page.)
            id = i.attrib['id']
            match = xref_id_rx.match(id)
            file = match.group(1)
            if file.startswith(('deprecated', 'bug')):
                color = 'm-danger'
                out.is_deprecated = True
            elif file.startswith('todo'):
                color = 'm-dim'
            else:
                color = 'm-default'
            out.parsed += '<aside class="m-note {}"><h4><a href="{}.html#{}" class="m-dox">{}</a></h4>{}</aside>'.format(
                color, file, match.group(2), i.find('xreftitle').text, parse_desc(state, i.find('xrefdescription')))

        elif i.tag == 'parameterlist':
            assert element.tag == 'para' # is inside a paragraph :/
            has_block_elements = True

            out.param_kind = i.attrib['kind']
            assert out.param_kind in ['param', 'templateparam']
            for param in i:
                # This is an overcomplicated shit, so check sanity
                # http://www.stack.nl/~dimitri/doxygen/manual/commands.html#cmdparam
                assert param.tag == 'parameteritem'
                assert len(param.findall('parameternamelist')) == 1

                # This is only for PHP, ignore for now
                param_names = param.find('parameternamelist')
                assert param_names.find('parametertype') is None

                description = parse_desc(state, param.find('parameterdescription'))

                # Gather all names (so e.g. `@param x, y, z` is turned into
                # three params sharing the same description)
                for name in param_names.findall('parametername'):
                    if i.attrib['kind'] == 'param':
                        out.params[name.text] = (description, name.attrib['direction'] if 'direction' in name.attrib else '')
                    else:
                        assert i.attrib['kind'] == 'templateparam'
                        out.templates[name.text] = description

        elif i.tag == 'variablelist':
            assert element.tag == 'para' # is inside a paragraph :/
            has_block_elements = True
            out.parsed += '<dl class="m-dox">'

            for var in i:
                if var.tag == 'varlistentry':
                    out.parsed += '<dt>{}</dt>'.format(parse_type(state, var.find('term')).strip())
                else:
                    assert var.tag == 'listitem'
                    out.parsed += '<dd>{}</dd>'.format(parse_desc(state, var))

            out.parsed += '</dl>'

        elif i.tag in ['verbatim', 'preformatted']:
            assert element.tag == 'para' # is inside a paragraph :/
            has_block_elements = True
            out.parsed += '<pre>{}</pre>'.format(html.escape(i.text or ''))

        elif i.tag == 'image':
            assert element.tag == 'para' # is inside a paragraph :/
            has_block_elements = True

            name = i.attrib['name']
            if i.attrib['type'] == 'html':
                path = os.path.join(state.basedir, state.doxyfile['OUTPUT_DIRECTORY'], state.doxyfile['XML_OUTPUT'], name)
                if os.path.exists(path):
                    state.images += [path]
                else:
                    logging.warning("{}: image {} was not found in XML_OUTPUT".format(state.current, name))

                caption = i.text
                if caption:
                    out.parsed += '<figure class="m-figure{}"><img src="{}" alt="Image" /><figcaption>{}</figcaption></figure>'.format(
                        ' ' + add_css_class if add_css_class else '',
                        name, html.escape(caption))
                else:
                    out.parsed += '<img class="m-image{}" src="{}" alt="Image" />'.format(
                        ' ' + add_css_class if add_css_class else '', name)

        # Custom <div> with CSS classes (for making dim notes etc)
        elif i.tag == '{http://mcss.mosra.cz/doxygen/}div':
            has_block_elements = True

            out.parsed += '<div class="{}">{}</div>'.format(i.attrib['{http://mcss.mosra.cz/doxygen/}class'], parse_inline_desc(state, i).strip())

        # Adding a custom CSS class to the immediately following block/inline
        # element
        elif i.tag == '{http://mcss.mosra.cz/doxygen/}class':
            # Bubble up in case we are alone in a paragraph, as that's meant to
            # affect the next paragraph content.
            if len([listing for listing in element]) == 1:
                out.add_css_class = i.attrib['{http://mcss.mosra.cz/doxygen/}class']

            # Otherwise this is meant to only affect inline elements in this
            # paragraph:
            else:
                add_inline_css_class = i.attrib['{http://mcss.mosra.cz/doxygen/}class']

        # Enabling footer navigation in a page
        elif i.tag == '{http://mcss.mosra.cz/doxygen/}footernavigation':
            out.footer_navigation = True

        # Enabling navigation for an example
        elif i.tag == '{http://mcss.mosra.cz/doxygen/}examplenavigation':
            out.example_navigation = (i.attrib['{http://mcss.mosra.cz/doxygen/}page'],
                                      i.attrib['{http://mcss.mosra.cz/doxygen/}prefix'])

        # Search-related stuff
        elif i.tag == '{http://mcss.mosra.cz/doxygen/}search':
            # Space-separated keyword list
            if '{http://mcss.mosra.cz/doxygen/}keywords' in i.attrib:
                out.search_keywords += [(keyword, '', 0) for keyword in i.attrib['{http://mcss.mosra.cz/doxygen/}keywords'].split(' ')]

            # Keyword with custom result title
            elif '{http://mcss.mosra.cz/doxygen/}keyword' in i.attrib:
                out.search_keywords += [(
                    i.attrib['{http://mcss.mosra.cz/doxygen/}keyword'],
                    i.attrib['{http://mcss.mosra.cz/doxygen/}title'],
                    int(i.attrib['{http://mcss.mosra.cz/doxygen/}suffix-length'] or '0'))]

            # Add values of this enum as search keywords
            elif '{http://mcss.mosra.cz/doxygen/}enum-values-as-keywords' in i.attrib:
                out.search_enum_values_as_keywords = True

            # Nothing else at the moment
            else: assert False

        # Either block or inline
        elif i.tag == 'programlisting':
            assert element.tag == 'para' # is inside a paragraph :/

            # We should have decided about block/inline above
            assert code_block is not None

            # Doxygen doesn't add a space before <programlisting> if it's
            # inline, add it manually in case there should be a space before
            # it. However, it does add a space after it always.
            if not code_block:
                if out.parsed and not out.parsed[-1].isspace() and not out.parsed[-1] in '([{':
                    out.parsed += ' '

            # Hammer unhighlighted code out of the block
            # TODO: preserve links
            code = ''
            codeline: ET.Element
            for codeline in i:
                assert codeline.tag == 'codeline'

                tag: ET.Element
                for tag in codeline:
                    assert tag.tag == 'highlight'
                    if tag.text: code += tag.text

                    token: ET.Element
                    for token in tag:
                        if token.tag == 'sp':
                            if 'value' in token.attrib:
                                code += chr(int(token.attrib['value']))
                            else:
                                code += ' '
                        elif token.tag == 'ref':
                            # Ignoring <ref> until a robust solution is found
                            # (i.e., also ignoring false positives)
                            code += token.text
                        else: # pragma: no cover
                            logging.warning("{}: unknown {} in a code block ".format(state.current, token.tag))

                        if token.tail: code += token.tail

                    if tag.tail: code += tag.tail

                code += '\n'

            # Strip whitespace around if inline code, strip only trailing
            # whitespace if a block
            if not code_block: code = code.strip()

            if not 'filename' in i.attrib:
                logging.warning("{}: no filename attribute in <programlisting>, assuming C++".format(state.current))
                filename = 'file.cpp'
            else:
                filename = i.attrib['filename']

            # Custom mapping of filenames to languages
            mapping = [('.h', 'c++'),
                       ('.h.cmake', 'c++'),
                       # Pygments knows only .vert, .frag, .geo
                       ('.glsl', 'glsl'),
                       ('.conf', 'ini'),
                       ('.ansi', ansilexer.AnsiLexer)]
            for key, v in mapping:
                if not filename.endswith(key): continue

                if isinstance(v, str):
                    lexer = get_lexer_by_name(v)
                else:
                    lexer = v()
                break

            # Otherwise try to find lexer by filename
            else:
                # Put some bogus prefix to the filename in case it is just
                # `.ext`
                lexer = find_lexer_class_for_filename("code" + filename)
                if not lexer:
                    logging.warning("{}: unrecognized language of {} in <programlisting>, highlighting disabled".format(state.current, filename))
                    lexer = TextLexer()
                else: lexer = lexer()

            # Style console sessions differently
            if (isinstance(lexer, BashSessionLexer) or
                isinstance(lexer, ansilexer.AnsiLexer)):
                class_ = 'm-console'
            else:
                class_ = 'm-code'

            formatter = HtmlFormatter(nowrap=True)
            highlighted = highlight(code, lexer, formatter)
            # Strip whitespace around if inline code, strip only trailing
            # whitespace if a block
            highlighted = highlighted.rstrip() if code_block else highlighted.strip()
            out.parsed += '<{0} class="{1}{2}">{3}</{0}>'.format(
                'pre' if code_block else 'code',
                class_,
                ' ' + add_css_class if code_block and add_css_class else '',
                highlighted)

        # Either block or inline
        elif i.tag == 'formula':
            assert element.tag == 'para' # is inside a paragraph :/

            logging.debug("{}: rendering math: {}".format(state.current, i.text))

            # Assume that Doxygen wrapped the formula properly to distinguish
            # between inline, block or special environment
            rendered = latex2svg.latex2svg('{}'.format(i.text), params=m.math.latex2svg_params)

            # We should have decided about block/inline above
            assert formula_block is not None
            if formula_block:
                has_block_elements = True
                out.parsed += '<div class="m-math{}">{}</div>'.format(
                    ' ' + add_css_class if add_css_class else '',
                    m.math._patch(i.text, rendered, ''))
            else:
                # CSS classes and styling for proper vertical alignment. Depth is relative
                # to font size, describes how below the line the text is. Scaling it back
                # to 12pt font, scaled by 125% as set above in the config.
                attribs = ' class="m-math{}" style="vertical-align: -{:.1f}pt;"'.format(
                    ' ' + add_inline_css_class if add_inline_css_class else '',
                    rendered['depth']*12*1.25)
                out.parsed += m.math._patch(i.text, rendered, attribs)

        # Inline elements
        elif i.tag == 'linebreak':
            # Strip all whitespace before the linebreak, as it is of no use
            out.parsed = out.parsed.rstrip() + '<br />'

        elif i.tag == 'anchor':
            out.parsed += '<a name="{}"></a>'.format(extract_id(i))

        elif i.tag == 'computeroutput':
            content = parse_inline_desc(state, i).strip()
            if content: out.parsed += '<code>{}</code>'.format(content)

        elif i.tag == 'emphasis':
            content = parse_inline_desc(state, i).strip()
            if content: out.parsed += '<em{}>{}</em>'.format(
                ' class="{}"'.format(add_inline_css_class) if add_inline_css_class else '',
                content)

        elif i.tag == 'bold':
            content = parse_inline_desc(state, i).strip()
            if content: out.parsed += '<strong{}>{}</strong>'.format(
                ' class="{}"'.format(add_inline_css_class) if add_inline_css_class else '',
                content)

        elif i.tag == 'ref':
            out.parsed += parse_ref(state, i)

        elif i.tag == 'ulink':
            out.parsed += '<a href="{}"{}>{}</a>'.format(
                html.escape(i.attrib['url']),
                ' class="{}"'.format(add_inline_css_class) if add_inline_css_class else '',
                add_wbr(parse_inline_desc(state, i).strip()))

        # <span> with custom CSS classes
        elif i.tag == '{http://mcss.mosra.cz/doxygen/}span':
            out.parsed += '<span class="{}">{}</span>'.format(i.attrib['{http://mcss.mosra.cz/doxygen/}class'], parse_inline_desc(state, i).strip())

        # WHAT THE HELL WHY IS THIS NOT AN XML ENTITY
        elif i.tag in ['mdash', 'ndash', 'laquo', 'raquo']:
            out.parsed += '&{};'.format(i.tag)
        elif i.tag == 'nonbreakablespace':
            out.parsed += '&nbsp;'

        # Something new :O
        else: # pragma: no cover
            logging.warning("{}: ignoring <{}> in desc".format(state.current, i.tag))

        # Now we can reset previous_section to None, nobody needs it anymore.
        # Of course we're resetting it only in case nothing else (such as the
        # <simplesect> tag) could affect it in this iteration.
        if (i.tag != 'simplesect' or i.attrib['kind'] == 'return') and previous_section:
            previous_section = None

        # A custom inline CSS class was used (or was meant to be used) in this
        # iteration, reset it so it's not added again in the next iteration. If
        # this is a <mcss:class> element, it was added just now, don't reset
        # it.
        if i.tag != '{http://mcss.mosra.cz/doxygen/}class' and add_inline_css_class:
            add_inline_css_class = None

        # A custom block CSS class was used (or was meant to be used) in this
        # iteration, reset it so it's not added again in the next iteration. If
        # this is a paragraph, it might be added just now from within the
        # nested content, don't reset it.
        if i.tag != 'para' and add_css_class:
            add_css_class = None

        # DOXYGEN <PARA> PATCHING 4/4
        #
        # Besides putting notes and blockquotes and shit inside paragraphs,
        # Doxygen also doesn't attempt to open a new <para> for the ACTUAL NEW
        # PARAGRAPH after they end. So I do it myself and give a hint to the
        # caller that they should close the <p> again.
        if element.tag == 'para' and not out.write_paragraph_close_tag and i.tail and i.tail.strip():
            out.parsed += '<p>'
            out.write_paragraph_close_tag = True
            # There is usually some whitespace in between, get rid of it as
            # this is a start of a new paragraph. Stripping of the whole thing
            # is done by the caller.
            out.parsed += html.escape(i.tail.lstrip())

        # Otherwise strip if requested by the caller or if this is right after
        # a line break
        elif i.tail:
            tail: str = html.escape(i.tail)
            if trim:
                tail = tail.strip()
            elif out.parsed.endswith('<br />'):
                tail = tail.lstrip()
            out.parsed += tail

    # A section was left open in the last iteration, close it. Expect that
    # there was nothing after that would mess with us.
    if previous_section:
        assert not out.write_paragraph_close_tag
        out.parsed = out.parsed.rstrip() + '</aside>'

    # Brief description always needs to be single paragraph because we're
    # sending it out without enclosing <p>.
    if element.tag == 'briefdescription':
        assert not has_block_elements and paragraph_count <= 1
        if paragraph_count == 1:
            assert out.parsed.startswith('<p>') and out.parsed.endswith('</p>')
            out.parsed = out.parsed[3:-4]

    # Strip superfluous <p> for simple elments (list items, parameter and
    # return value description, table cells), but only if there is just a
    # single paragraph
    elif (element.tag in ['listitem', 'parameterdescription', 'entry'] or (element.tag == 'simplesect' and element.attrib['kind'] == 'return')) and not has_block_elements and paragraph_count == 1 and out.parsed:
        assert out.parsed.startswith('<p>') and out.parsed.endswith('</p>')
        out.parsed = out.parsed[3:-4]

    return out

def parse_desc(state: State, element: ET.Element) -> str:
    if element is None: return ''

    # Verify that we didn't ignore any important info by accident
    parsed = parse_desc_internal(state, element)
    assert not parsed.templates and not parsed.params and not parsed.return_value
    assert not parsed.section # might be problematic
    return parsed.parsed

def parse_enum_desc(state: State, element: ET.Element) -> str:
    # Verify that we didn't ignore any important info by accident
    parsed = parse_desc_internal(state, element.find('detaileddescription'))
    parsed.parsed += parse_desc(state, element.find('inbodydescription'))
    assert not parsed.templates and not parsed.params and not parsed.return_value
    assert not parsed.section # might be problematic
    return (parsed.parsed, parsed.search_keywords, parsed.search_enum_values_as_keywords, parsed.is_deprecated)

def parse_enum_value_desc(state: State, element: ET.Element) -> str:
    # Verify that we didn't ignore any important info by accident
    parsed = parse_desc_internal(state, element.find('detaileddescription'))
    assert not parsed.templates and not parsed.params and not parsed.return_value
    assert not parsed.section # might be problematic
    return (parsed.parsed, parsed.search_keywords, parsed.is_deprecated)

def parse_var_desc(state: State, element: ET.Element) -> str:
    # Verify that we didn't ignore any important info by accident
    parsed = parse_desc_internal(state, element.find('detaileddescription'))
    parsed.parsed += parse_desc(state, element.find('inbodydescription'))
    assert not parsed.templates and not parsed.params and not parsed.return_value
    assert not parsed.section # might be problematic
    return (parsed.parsed, parsed.search_keywords, parsed.is_deprecated)

def parse_toplevel_desc(state: State, element: ET.Element):
    # Verify that we didn't ignore any important info by accident
    parsed = parse_desc_internal(state, element)
    assert not parsed.return_value
    if parsed.params:
        logging.warning("{}: use @tparam instead of @param for documenting class templates, @param is ignored".format(state.current))
    return (parsed.parsed, parsed.templates, parsed.section[2] if parsed.section else '', parsed.footer_navigation, parsed.example_navigation, parsed.search_keywords, parsed.is_deprecated)

def parse_typedef_desc(state: State, element: ET.Element):
    # Verify that we didn't ignore any important info by accident
    parsed = parse_desc_internal(state, element.find('detaileddescription'))
    parsed.parsed += parse_desc(state, element.find('inbodydescription'))
    assert not parsed.params and not parsed.return_value
    assert not parsed.section # might be problematic
    return (parsed.parsed, parsed.templates, parsed.search_keywords, parsed.is_deprecated)

def parse_func_desc(state: State, element: ET.Element):
    # Verify that we didn't ignore any important info by accident
    parsed = parse_desc_internal(state, element.find('detaileddescription'))
    parsed.parsed += parse_desc(state, element.find('inbodydescription'))
    assert not parsed.section # might be problematic
    return (parsed.parsed, parsed.templates, parsed.params, parsed.return_value, parsed.search_keywords, parsed.is_deprecated)

def parse_define_desc(state: State, element: ET.Element):
    # Verify that we didn't ignore any important info by accident
    parsed = parse_desc_internal(state, element.find('detaileddescription'))
    parsed.parsed += parse_desc(state, element.find('inbodydescription'))
    assert not parsed.templates
    assert not parsed.section # might be problematic
    return (parsed.parsed, parsed.params, parsed.return_value, parsed.search_keywords, parsed.is_deprecated)

def parse_inline_desc(state: State, element: ET.Element) -> str:
    if element is None: return ''

    # Verify that we didn't ignore any important info by accident
    parsed = parse_desc_internal(state, element, trim=False)
    assert not parsed.templates and not parsed.params and not parsed.return_value
    assert not parsed.section
    return parsed.parsed

def parse_enum(state: State, element: ET.Element):
    assert element.tag == 'memberdef' and element.attrib['kind'] == 'enum'

    enum = Empty()
    enum.id = extract_id(element)
    enum.type = parse_type(state, element.find('type'))
    enum.name = element.find('name').text
    if enum.name.startswith('@'): enum.name = '(anonymous)'
    enum.brief = parse_desc(state, element.find('briefdescription'))
    enum.description, search_keywords, search_enum_values_as_keywords, enum.is_deprecated = parse_enum_desc(state, element)
    enum.is_protected = element.attrib['prot'] == 'protected'
    enum.is_strong = False
    if 'strong' in element.attrib:
        enum.is_strong = element.attrib['strong'] == 'yes'
    enum.values = []

    enum.has_value_details = False
    enumvalue: ET.Element
    for enumvalue in element.findall('enumvalue'):
        value = Empty()
        value.id = extract_id(enumvalue)
        value.name = enumvalue.find('name').text
        # There can be an implicit initializer for enum value
        value.initializer = html.escape(enumvalue.findtext('initializer', ''))
        if ''.join(enumvalue.find('briefdescription').itertext()).strip():
            logging.warning("{}: ignoring brief description of enum value {}::{}".format(state.current, enum.name, value.name))
        value.description, value_search_keywords, value.is_deprecated = parse_enum_value_desc(state, enumvalue)
        if value.description:
            enum.has_value_details = True
            if not state.doxyfile['M_SEARCH_DISABLED']:
                result = Empty()
                result.flags = ResultFlag.ENUM_VALUE|(ResultFlag.DEPRECATED if value.is_deprecated else ResultFlag(0))
                result.url = state.current_url + '#' + value.id
                result.prefix = state.current_prefix + [enum.name]
                result.name = value.name
                result.keywords = value_search_keywords
                if search_enum_values_as_keywords and value.initializer.startswith('='):
                    result.keywords += [(value.initializer[1:].lstrip(), '', 0)]
                state.search += [result]
        enum.values += [value]

    enum.has_details = enum.description or enum.has_value_details
    if enum.brief or enum.has_details or enum.has_value_details:
        if not state.doxyfile['M_SEARCH_DISABLED']:
            result = Empty()
            result.flags = ResultFlag.ENUM|(ResultFlag.DEPRECATED if enum.is_deprecated else ResultFlag(0))
            result.url = state.current_url + '#' + enum.id
            result.prefix = state.current_prefix
            result.name = enum.name
            result.keywords = search_keywords
            state.search += [result]
        return enum
    return None

def parse_template_params(state: State, element: ET.Element, description):
    if element is None: return False, None
    assert element.tag == 'templateparamlist'

    has_template_details = False
    templates = []
    i: ET.Element
    for i in element:
        assert i.tag == 'param'

        template = Empty()
        template.type = parse_type(state, i.find('type'))
        declname = i.find('declname')
        if declname is not None:
            # declname or decltype?!
            template.name = declname.text
        else:
            # Doxygen sometimes puts both in type, extract that
            parts = template.type.partition(' ')
            template.type = parts[0]
            template.name = parts[2]
        default = i.find('defval')
        template.default = parse_type(state, default) if default is not None else ''
        if template.name in description:
            template.description = description[template.name]
            del description[template.name]
            has_template_details = True
        else:
            template.description = ''
        templates += [template]

    # Some param description got unused
    if description:
        logging.warning("{}: template parameter description doesn't match parameter names: {}".format(state.current, repr(description)))

    return has_template_details, templates

def parse_typedef(state: State, element: ET.Element):
    assert element.tag == 'memberdef' and element.attrib['kind'] == 'typedef'

    typedef = Empty()
    typedef.id = extract_id(element)
    typedef.is_using = element.findtext('definition', '').startswith('using')
    typedef.type = parse_type(state, element.find('type'))
    typedef.args = parse_type(state, element.find('argsstring'))
    typedef.name = element.find('name').text
    typedef.brief = parse_desc(state, element.find('briefdescription'))
    typedef.description, templates, search_keywords, typedef.is_deprecated = parse_typedef_desc(state, element)
    typedef.is_protected = element.attrib['prot'] == 'protected'
    typedef.has_template_details, typedef.templates = parse_template_params(state, element.find('templateparamlist'), templates)

    typedef.has_details = typedef.description or typedef.has_template_details
    if typedef.brief or typedef.has_details:
        result = Empty()
        result.flags = ResultFlag.TYPEDEF|(ResultFlag.DEPRECATED if typedef.is_deprecated else ResultFlag(0))
        result.url = state.current_url + '#' + typedef.id
        result.prefix = state.current_prefix
        result.name = typedef.name
        result.keywords = search_keywords
        state.search += [result]
        return typedef
    return None

def parse_func(state: State, element: ET.Element):
    assert element.tag == 'memberdef' and element.attrib['kind'] == 'function'

    func = Empty()
    func.id = extract_id(element)
    func.type = parse_type(state, element.find('type'))
    func.name = fix_type_spacing(html.escape(element.find('name').text))
    func.brief = parse_desc(state, element.find('briefdescription'))
    func.description, templates, params, func.return_value, search_keywords, func.is_deprecated = parse_func_desc(state, element)

    # Extract function signature to prefix, suffix and various flags. Important
    # things affecting caller such as static or const (and rvalue overloads)
    # are put into signature prefix/suffix, other things to various is_*
    # properties.
    if func.type == 'constexpr': # Constructors
        func.type = ''
        func.is_constexpr = True
    elif func.type.startswith('constexpr'):
        func.type = func.type[10:]
        func.is_constexpr = True
    else:
        func.is_constexpr = False
    func.prefix = ''
    func.is_explicit = element.attrib['explicit'] == 'yes'
    func.is_virtual = element.attrib['virt'] != 'non-virtual'
    if element.attrib['static'] == 'yes':
        func.prefix += 'static '
    signature = element.find('argsstring').text
    if signature.endswith(' noexcept'):
        signature = signature[:-9]
        func.is_noexcept = True
    else:
        func.is_noexcept = False
    if signature.endswith('=default'):
        signature = signature[:-8]
        func.is_defaulted = True
    else:
        func.is_defaulted = False
    if signature.endswith('=delete'):
        signature = signature[:-7]
        func.is_deleted = True
    else:
        func.is_deleted = False
    if signature.endswith('=0'):
        signature = signature[:-2]
        func.is_pure_virtual = True
    else:
        func.is_pure_virtual = False
    func.suffix = html.escape(signature[signature.rindex(')') + 1:].strip())
    if func.suffix: func.suffix = ' ' + func.suffix
    func.is_protected = element.attrib['prot'] == 'protected'
    func.is_private = element.attrib['prot'] == 'private'

    func.has_template_details, func.templates = parse_template_params(state, element.find('templateparamlist'), templates)

    func.has_param_details = False
    func.params = []
    for p in element.findall('param'):
        name = p.find('declname')
        param = Empty()
        param.name = name.text if name is not None else ''
        param.type = parse_type(state, p.find('type'))

        # Recombine parameter name and array information back
        array = p.find('array')
        if array is not None:
            if name is not None:
                if param.type.endswith(')'):
                    param.type_name = param.type[:-1] + name.text + ')' + array.text
                else:
                    param.type_name = param.type + ' ' + name.text + array.text
            else:
                param.type_name = param.type + array.text
            param.type += array.text
        elif name is not None:
            param.type_name = param.type + ' ' + name.text
        else:
            param.type_name = param.type

        param.default = parse_type(state, p.find('defval'))
        if param.name in params:
            param.description, param.direction = params[param.name]
            del params[param.name]
            func.has_param_details = True
        else:
            param.description, param.direction = '', ''
        func.params += [param]

    # Some param description got unused
    if params: logging.warning("{}: function parameter description doesn't match parameter names: {}".format(state.current, repr(params)))

    func.has_details = func.description or func.has_template_details or func.has_param_details or func.return_value
    if func.brief or func.has_details:
        if not state.doxyfile['M_SEARCH_DISABLED']:
            result = Empty()
            result.flags = ResultFlag.FUNC|(ResultFlag.DEPRECATED if func.is_deprecated else ResultFlag(0))|(ResultFlag.DELETED if func.is_deleted else ResultFlag(0))
            result.url = state.current_url + '#' + func.id
            result.prefix = state.current_prefix
            result.name = func.name
            result.keywords = search_keywords
            result.params = [param.type for param in func.params]
            result.suffix = func.suffix
            state.search += [result]
        return func
    return None

def parse_var(state: State, element: ET.Element):
    assert element.tag == 'memberdef' and element.attrib['kind'] == 'variable'

    var = Empty()
    var.id = extract_id(element)
    var.type = parse_type(state, element.find('type'))
    if var.type.startswith('constexpr'):
        var.type = var.type[10:]
        var.is_constexpr = True
    else:
        var.is_constexpr = False
    var.is_static = element.attrib['static'] == 'yes'
    var.is_protected = element.attrib['prot'] == 'protected'
    var.is_private = element.attrib['prot'] == 'private'
    var.name = element.find('name').text
    var.brief = parse_desc(state, element.find('briefdescription'))
    var.description, search_keywords, var.is_deprecated = parse_var_desc(state, element)

    var.has_details = not not var.description
    if var.brief or var.has_details:
        if not state.doxyfile['M_SEARCH_DISABLED']:
            result = Empty()
            result.flags = ResultFlag.VAR|(ResultFlag.DEPRECATED if var.is_deprecated else ResultFlag(0))
            result.url = state.current_url + '#' + var.id
            result.prefix = state.current_prefix
            result.name = var.name
            result.keywords = search_keywords
            state.search += [result]
        return var
    return None

def parse_define(state: State, element: ET.Element):
    assert element.tag == 'memberdef' and element.attrib['kind'] == 'define'

    define = Empty()
    define.id = extract_id(element)
    define.name = element.find('name').text
    define.brief = parse_desc(state, element.find('briefdescription'))
    define.description, params, define.return_value, search_keywords, define.is_deprecated = parse_define_desc(state, element)
    define.has_param_details = False
    define.params = None
    for p in element.findall('param'):
        if define.params is None: define.params = []
        name = p.find('defname')
        if name is not None:
            if name.text in params:
                description, _ = params[name.text]
                del params[name.text]
                define.has_param_details = True
            else:
                description = ''
            define.params += [(name.text, description)]

    # Some param description got unused
    if params: logging.warning("{}: define parameter description doesn't match parameter names: {}".format(state.current, repr(params)))

    define.has_details = define.description or define.return_value
    if define.brief or define.has_details:
        if not state.doxyfile['M_SEARCH_DISABLED']:
            result = Empty()
            result.flags = ResultFlag.DEFINE|(ResultFlag.DEPRECATED if define.is_deprecated else ResultFlag(0))
            result.url = state.current_url + '#' + define.id
            result.prefix = []
            result.name = define.name
            result.keywords = search_keywords
            result.params = None if define.params is None else [param[0] for param in define.params]
            state.search += [result]
        return define
    return None
