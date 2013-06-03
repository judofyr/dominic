module Dominic
  class Node
    attr_accessor :parent, :children

    def initialize(options = {})
      options.each do |key, value|
        send("#{key}=", value)
      end
    end

    def children
      @children ||= []
    end

    def to_test
      pretty_children.map { |s| "| #{s}\n" }.join
    end

    def pretty_children(level = 0)
      children.flat_map do |node|
        ["  " * level + node.pretty, *node.pretty_children(level + 1)]
      end
    end

    def append(node)
      children << node
      node.parent = self
    end

    def remove_child(node)
      children.delete(node)
      node.parent = nil
    end

    def remove
      parent.remove_child(self) if parent
    end
  end

  class Root < Node
    def name
      '(root)'
    end

    def pretty
      ''
    end
  end

  class Tag < Node
    attr_accessor :name, :attributes

    def pretty
      "<#{name}>"
    end
  end

  class Text < Node
    attr_accessor :content

    def pretty
      content.inspect
    end
  end
end

