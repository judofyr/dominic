require_relative 'helper'
require 'pathname'

class TestHTML5Lib < Minitest::Test
  DIR = Pathname.new(__FILE__).parent + 'html5lib-tests'
  TREE = DIR + 'tree-construction'

  i_suck_and_my_tests_are_order_dependent!

  if TREE.exist?
    TREE.each_entry do |file|
      next unless file.extname == '.dat'
      current_test = {}
      current_string = nil
      i = 0

      lines = (TREE + file).readlines
      lines << '#done'

      lines.each do |line|
        if line =~ /^#(.*)$/
          if $1 == 'data' && !current_test.empty?
            doc = current_test['document'].strip
            data = current_test['data'].strip

            define_method("test_#{file.basename('.dat')}_#{i}") do
              parser = Dominic::Parser.new(data)
              if doc
                tree = parser.parse_document
                assert_equal doc, tree.to_test.strip
              end
            end
            i += 1

            current_test = {}
            current_string = nil
          end

          current_test[$1] = current_string = ""
        else
          current_string << line
        end
      end
    end
  end
end

