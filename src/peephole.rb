#!/usr/bin/env ruby

unless Kernel.respond_to?(:require_relative)
  module Kernel
    def require_relative(path)
      require File.join(File.dirname(__FILE__), path)
    end
  end
end

require_relative 'generate/GenerateC.rb'

module Peephole

  # Internal: Prints all methods that can be called on this objects.  Each of method is ont its own
  #           line.
  #
  # obj - the object whose possible methods will be printed
  #
  # sideffect: prints method list to stdout
  #
  def list_methods(obj)
    puts obj.methods.sort.join("\n").to_s
  end

  # Public: Executes a depth first traversal on a tree object and carries calls two functions for
  #         each node. First |on_enter| is called with the current node as argument as we enter the
  #         node (ie before the children are traversed.  Then |traverse| iterates on all children
  #         (in doing so calling |on_enter| and |on_exit| on all children nodes).  Finally |on_exit|
  #         is called on the node.
  #
  # tree     - The ANTLR3::AST::BaseTree object to be traversed.
  # on_enter - The function to call on each node on the way down the tree.
  # on_exit  - The function to call on each node on the way back up the tree.
  # on_leaf  - The function to call on leaves as they are hit.
  #
  # Example
  #
  #   on_enter = lambda do |node|
  #     # body omitted
  #   end
  #   on_exit = lambda do |node|
  #     # body omitted
  #   end
  #   one_leaf = lamnda do |leaf|
  #     # body omitted
  #   end
  #   traverse(tree, on_enter, on_exit)
  #
  def traverse(tree, on_enter, on_exit = nil, on_leaf = nil)
    on_enter.call(tree) unless on_enter == nil
    tree.children.each do |child|
      if child.empty?
        on_leaf.call(child) unless on_leaf == nil
      else
        traverse(child, on_enter, on_exit, on_leaf)
      end
    end
    on_exit.call(tree) unless on_exit == nil
  end

  # Public: Prints the AST to stdout
  #
  # tree - The ANTLR3::AST::BaseTree object to print.
  #
  # Example
  #
  #   This assumes the variable |tree| has been loaded with an AST generated form the string
  #   "int_oper={iadd|isub}" print(tree)
  #     # => "
  #   START  :(22)
  #   DECLARATION  :(24)
  #     int_oper
  #     INSTRUCTION_SET  :(28)
  #        iadd
  #        isub
  #   "
  #
  def print_ast(tree)
    indent = 0
    print_node = lambda do |node|
      s = ' ' * (2 * indent)
      indent += 1
      s << node.text.to_s
      puts s << '  :(' << node.type.to_s << ')'
    end
    print_leaf = lambda do |leaf|
      s = ' ' * (2 * indent)
      puts s << leaf.text.to_s
    end
    traverse(tree, print_node, lambda{ |_|  indent -= 1 }, print_leaf)
  end

  #
  #
  def self.main()
    arguments = ARGV.clone

    mode = :generate
    use_stdout = false
    option_found = false
    begin
      if arguments.include?('-p')
        mode = :print
        arguments.delete('-p')
      end
      if arguments.include?('-s')
        use_stdout = true
        arguments.delete('-s')
      end
    end while option_found

    if arguments.empty?
      $stderr.puts 'Usage:'
      $stderr.puts "  ruby #{__FILE__} dir_or_file1 dir_or_file2 ..."
      $stderr.puts # Blank line
      $stderr.puts 'When a directory is given, files ending with the following extensions'
      $stderr.puts 'will be processed:'
      $stderr.puts '  .peep  .peephole  .pattern  .patterns'
      exit 1
    end

    # Expand directory arguments to individual files
    expanded_arguments = []
    arguments.each do |argument|
      argument = '.' if argument.empty? # Avoid having the pattern match the filesystem root
      if File.directory?(argument)
         expanded_arguments.concat(Dir[argument + '/**/*.{peep,peephole,pattern,patterns}'])
      else
        expanded_arguments << argument
      end
    end

    case mode
    when :generate
      Generate.generate_c(expanded_arguments, use_stdout)
    when :print
      expanded_arguments.each do |file|
        #    parser = Peephole::Parser.new(open(file))
        #    print_ast(parser.start.tree)
      end
    end
  end
end # Peephole

# Run
Peephole.main
