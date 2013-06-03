require 'strscan'
require 'set'
require 'dominic/node'

class Set
  alias === include?
end

module Dominic
  class Parser
    ScopeMarker = Node.new
    def initialize(source)
      @source = source
      @scanner = StringScanner.new(source)
      @token = nil
      @pos = 0
      @formatting = []
    end

    def parse_document
      @document = Root.new
      @stack = [@document]
      switch(:initial)
      parse
      @document
    end

    def token
      @token || advance
    end

    def advance
      @token = next_token
      if @token && tag = @token[:tag]
        if tag =~ END_RE
          @tag_closed = true
          @tag_name = $1
        else
          @tag_closed = false
          @tag_name = tag
        end
      else
        @tag_closed = nil
        @tag_name = nil
      end
      @token
    end

    ATTR_RE = /
      ([^=\s>]+)       # Key
      (?:
        \s*=\s*
        (?:
          "([^"]*?)"   # Quotation marks
        |
          '([^']*?)'   # Apostrophes
        |
          ([^>\s]*)    # Unquoted
        )
      )?
      \s*
    /x

    END_RE = /\A\s*\/\s*(.+)\s*\z/

    TOKEN_RE = /
      (?:
        (?<space>[\t\n\f\r])                                    # Space
      |
        (?<text>[^<]+)                                         # Text
      |
        <!--(?<comment>.*?)--\s*>                                 # Comment
      |
        <!\[CDATA\[(?<cdata>.*?)\]\]>                           # CDATA
      |
        <!DOCTYPE(?<doctype>
          \s+\w+
          (?:(?:\s+\w+)?(?:\s+(?:"[^"]*"|'[^']*'))+)?   # External ID
          (?:\s+\[.+?\])?                               # Int Subset
          \s*
        )>
      |
        <(?<tag>
          \s*
          [^>\s]+                                       # Tag
          \s*
          (?:$ATTR_RE)*                                 # Attributes
        )>
      )
    /xis;

    PARAGRAPH = Set[*
      %w(address article aside blockquote dir div dl fieldset footer form h1 h2) +
      %w(h3 h4 h5 h6 header hgroup hr menu nav ol p pre section table ul)
    ]

    VOID = Set[*
      %w(area base br col command embed hr img input keygen link meta param) +
      %w(source track wbr)
    ]

    FORMATTING = Set[*
      %w(a b big code em font i nobr s small strike strong tt u)
    ]

    SPECIAL = Set[*
      %w(address applet area article aside base basefont bgsound blockquote body br button caption center col colgroup dd details dir div dl dt embed fieldset figcaption figure footer form frame frameset h1 h2 h3 h4 h5 h6 head header hgroup hr html iframe img input isindex li link listing main marquee menu menuitem meta nav noembed noframes noscript object ol p param plaintext pre script section select source style summary table tbody td textarea tfoot th thead title tr track ul wbr)
    ]

    def next_token
      return if @pos == @source.size
      @source.match(/\G#{TOKEN_RE}/, @pos).tap do |md|
        if !md
          raise "Tokenize error: #{@source[@pos..-1]}"
        end
        @pos += md[0].size
      end
    end

    def tag_name
      @tag_name
    end

    def tag_closed?
      @tag_closed
    end

    def tag?
      token && token[:tag]
    end

    def start_tag?(name = nil)
      tag? && !tag_closed? && (!name || name === tag_name )
    end

    def end_tag?(name = nil)
      tag? && tag_closed? && (!name || name === tag_name)
    end

    private

    ## State
    def switch(state)
      @state = state
    end

    def jump(state)
      @state = state
      send(state)
    end

    def parse
      while token
        send(@state)
      end
    end

    ## Node stack
    def current
      @stack.last
    end

    def insert(node)
      current.children << node
      node.parent = current
    end

    def open(node)
      insert(node)
      @stack << node
    end

    def pop_until(name)
      if idx = @stack.rindex { |node| Tag === node and node.name == name }
        @stack.slice!(idx..-1)
      end
    end

    ## Active formatting elements

    # 12.2.3.3
    def reconstruct_formatting
      last = @formatting.last
      if last.nil? || last == ScopeMarker || @stack.include?(last)
        # do nothing
        return
      end
    end

    ## States
    def initial
      switch(:before_html)
    end

    def before_html
      open Tag.new(:name => 'html')
      advance if start_tag?('html')
      jump(:before_head)
    end

    def before_head
      tag = Tag.new(:name => 'head')
      if start_tag?('head')
        advance
        open(tag)
        jump(:in_head)
      else
        insert(tag)
        jump(:after_head)
      end
    end

    def in_head
      @stack.pop
      advance if end_tag?('head')
      jump(:after_head)
    end

    def after_head
      open Tag.new(:name => 'body')
      advance if start_tag?('body')
      jump(:in_body)
    end

    def in_body
      return unless token

      if start_tag?(PARAGRAPH)
        pop_until('p')
      end

      case
      when text = token[:text]
        insert Text.new(:content => text)
      when start_tag?(VOID)
        insert Tag.new(:name => tag_name)
      when start_tag?('table')
        open Tag.new(:name => tag_name)
        switch(:in_table)
      when start_tag?(/\Ah[1-6]\z/)
        @stack.pop if current.name =~ /\Ah/
        open Tag.new(:name => tag_name)
      when start_tag?
        tag = Tag.new(:name => tag_name)
        open(tag)
        if FORMATTING.include?(tag_name)
          @formatting << tag
        end

      when end_tag?('table')
        pop_until('table')
      when end_tag?
        if FORMATTING.include?(tag_name)
          if other = @stack.rindex { |node| Tag === node && node.name == tag_name }
            rest = @stack.slice!(other..-1)
            furthest = rest.detect { |node| SPECIAL.include?(node.name) }

            if furthest
              common = rest[0].parent
              furthest.parent.children.delete(furthest)
              common.children << furthest
              furthest.parent = common

              foo = Tag.new(:name => tag_name)
              furthest.children.each do |node|
                foo.children << node
                node.parent = foo
              end.clear

              furthest.children << foo
              foo.parent = furthest
              @stack << furthest
              advance
              return
            elsif rest.size > 1
              open Tag.new(:name => rest.last.name)
              advance
              return
            end
          end
        end

        pos = @stack.size
        node = @stack[pos -= 1]

        until SPECIAL.include?(node.name)
          if node.name == tag_name
            pop_until('p')
            break
          end
          node = @stack[pos -= 1]
        end
      end

      advance
    end

    def in_table
      case
      when start_tag?(Set.new %w[td th tr])
        open Tag.new(:name => 'tbody')
        switch(:in_table_body)
        return
      end
      advance
    end

    def in_table_body
      case
      when start_tag?(Set.new %w[th td])
        open Tag.new(:name => 'tr')
        switch(:in_row)
        return
      end
      in_table
    end

    def in_row
      case
      when start_tag?(Set.new %w[th td])
        open Tag.new(:name => tag_name)
        @formatting << :marker
        switch(:in_cell)
      end
      advance
    end

    def in_cell
      in_body
    end
  end
end
