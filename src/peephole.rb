#!/usr/bin/env ruby

unless Kernel.respond_to?(:require_relative)
  module Kernel
    def require_relative(path)
      require File.join(File.dirname(__FILE__), path)
    end
  end
end

require_relative 'grammar/PeepholeParser.rb'

$c_methods = []

# Internal: Prints all methods that can be called on this objects.  Each of method is ont its own line.
#
# obj - the object whose possible methods will be printed
#
# sideffect: prints method list to stdout
#
def list_methods(obj)
  puts obj.methods.sort.join("\n").to_s
end


# Public: Executes a depth fist traversal of a tree object and calls a function on each node as it is entered.
#
# tree - The ANTLR3::AST::BaseTree object to be traversed.
# func - The function to call on each node.
#
# Examples
#
#   apply(tree) do |one, two, ...|
#     # body omitted
#   end
#
def apply(tree, &func)
  traverse(tree, func)
end


# Public: Executes a depth first traversal on a tree object and carries calls two functions for each node. First
#         |on_enter| is called with the current node as argument as we enter the node (ie before the children are
#         traversed.  Then |traverse| iterates on all children (in doing so calling |on_enter| and |on_exit| on all
#         children nodes).  Finally |on_exit| is called on the node.
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
#   This assumes the variable |tree| has been loaded with an AST generated form the string "int_oper={iadd|isub}"
#   print(tree)
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
def build_declaration_map(tree)
  include Peephole::TokenData

  declaration_map = {}

  tree.children.each do |declaration|
    if declaration.type == DECLARATION
      # find the name of the newly declared variable
      name = declaration.children[0].text

      # if two declarations have the same name throw an execptio to  be caught and show to the user
      throw 'redeclaration of instruction set' if declaration_map[name] != nil

      # find the set of instructions associated with this declaration
      set = declaration.children[1]
      instruction_set = Set.new
      set.each { |instr| instruction_set.add(instr.text) }

      # add {name => instruction_set} to the map
      declaration_map[name] = instruction_set
    else
      break
    end
  end

  return declaration_map
end

#
#
def declaration_string(name, next_instr)
  s =  'CODE *' << name + ' = '
  if (next_instr == '*c')
    s << next_instr << ";\n"
  else
    s << 'next(' << next_instr << ");\n"
  end
  next_instr.replace(name)
  return s
end

#
#
def build_declarations_format(rule, declarations)
  include Peephole::TokenData

  format = ''

  instr_index = 1;
  next_instr = '*c';
  # block to be run up entering a parent node
  in_a_node = lambda do |node|
    children = node.children

    case node.type
    when NAMED_INSTRUCTION
      # print the instruciton declaration
      name =  'instr_' << children[0].text
      format << '  ' << declaration_string(name, next_instr)
      instr_index += 1
    when UNNAMED_INSTRUCTION
      # number the isntruction and print the declaration
      name =  'instr_' << instr_index.to_s
      format << '  ' << declaration_string(name, next_instr)
      instr_index += 1
    when INSTRUCTION
      if declarations[children[0].text] == nil
        # print the actual instruction name if available
        instruction = children[0].text
      else
        # otherwise set is as variable to be hooked later
        instruction = "%s"
      end

      argument = nil
      if children[1] != nil
        # get the arguments name if it exists
        argument = 'arg_' << children[1].text
        # print the argument declaration
        format << '  int ' << argument << ";\n"
      end

      # print the instruction checking if statement
      format << '  if (!is_' << instruction << '(' << next_instr
      format << ", &" << argument unless argument == nil
      format << ")) {\n"
      format << "    return 0;\n  }"
    else
      next
    end
  end

  # code to be run when we exit a parent node
  out_a_node = lambda do |node|
    case node.type
    when NAMED_INSTRUCTION, UNNAMED_INSTRUCTION, INSTRUCTION
      format << "\n"
    else
      next
    end
  end

  traverse(rule, in_a_node, out_a_node)
  format << "  next = next(" << next_instr << ");\n\n"
  return [format, instr_index - 1]
end

#
#
def get_variable_instructions(rule, declarations)
  index = 1
  variable_instructions = []
  variable_names = []

  name_line = lambda do |node|
    case node.type
    when NAMED_INSTRUCTION
      variable_names += [node.children[0].text]
    when UNNAMED_INSTRUCTION
      variable_names += ['unnamed']
    end
  end

  in_a_node = lambda do |line|
    case line.type
    when INSTRUCTION
      instruction = line.children[0].text
      if declarations[instruction] != nil
        name_line.call(line.parent)
        variable_instructions += [instruction]
      end
    when INSTRUCTION_SET
      name_line.call(line.parent)
      # create a name for the new set we'll create
      name = 'inlined_' << index.to_s

      # create a set containing all the instructions in this declaration
      set = Set.new
      line.children.each { |instr| set.add(instr.text) }

      # add the set to |declarations|, add a new entry to |variable_instructions|, increment index
      declarations[name] = set
      variable_instructions += [name]
      index += 1
    end
  end

  traverse(rule, in_a_node)
  return [variable_instructions, variable_names]
end

#
#
def build_c_expression(expression)
  separator = ''
  case expression.type
  when T_INT
    return expression.text
  when T_VARIABLE
    return 'arg_' << expression.text
  when EXPRESSION_ADD
    separator = ' + '
  when EXPRESSION_SUBTRACT
    separator = ' - '
  when EXPRESSION_MULTIPLY
    separator = ' * '
  when EXPRESSION_DIVIDE
    separator = ' / '
  when EXPRESSION_REMAINDER
    separator = ' % '
  end

  children_strings = []
  expression.children.each { |child| children_strings += [build_c_expression(child)]}
  return '(' << children_strings.join(separator) << ')'
end

def build_statements_string(rule, replace_count, variable_names, variable_types)
  include Peephole::TokenData

  string = ''
  statement_count = 0

  # code run up entering a parent node
  rule.children.each do |node|
    children = node.children

    create = false
    case node.type
    when STATEMENT_INSTRUCTION
      statement_count += 1
      string << '  CODE *statement_' << statement_count << ' = makeCODE'  << instruction_type << '('
      create = true
    when STATEMENT_VARIABLE
      statement_count += 1
      variable = children[0].text
      i = variable_names.index(variable)
      if i != nil
        # TODO deal with [#]
        instruction_type = variable_types[i]

        string << '  statement_' << statement_count.to_s << ' = instr_' << variable << ";\n"
      end
      created = true
    when STATEMENT_SWITCH
      statement_count += 1
      # find the instruction type that has been fixed to the variable being switched on
      variable = children[0].text
      i = variable_names.index(variable)
      instruction_type = variable_types[i]

      current_case = nil
      children.each do |child|
        if child.type == STATEMENT_CASE && child.children[0].text == instruction_type
          current_case = child.children[1]
          break
        end
      end

      instruction_type = current_case.children[0].text
      expression = current_case.children[1]

      string << "\n  CODE *statement_" << statement_count.to_s << ' = makeCODE'  << instruction_type << '('
      string << build_c_expression(expression) unless expression == nil
      string << ", NULL);\n"
      created = true
    end
    if created && statement_count > 1
      string << '  statement_' << (statement_count - 1).to_s << '->next = statement_' << statement_count.to_s
    end
  end

  string << "\n  statement_" << statement_count.to_s << '->next = next'
  string << "\n" << '  return replace(c, ' << replace_count << ", statement_1);\n";
  return string
end

#
#
def print_rule(rule, declarations)
  variables = get_variable_instructions(rule, declarations)
  variable_instructions = variables[0]
  variable_names = variables[1]

  signature_format = rule.children[0].text << ('_%s') * variable_instructions.size

  dec = build_declarations_format(rule, declarations)
  declarations_format = dec[0]
  declarations_count = dec[1]

  # We have a bunch of unfixed (INSTRUCTION_SETs) variables for each rule (potential).
  # A function need to be printed for every single possible combination for all of these
  # instructions.  This loop iterates over all possibilities and then prints a method for that
  # combination.  It does this by fixing the current variable in the array |fixed| to be one of
  # the possible instructions.  Then it recurses on the (unset) right hand side of the array.
  # Once all those have been completed it fixes a different instruction to the current variable.
  # In doing so we cover all possible combinations of instructions, and at each level we print
  # the funtion.  This is done inplace (|fixed| is never copied) which means we don't have to deal
  # with crazy space complexity.
  set_variables = lambda do |fixed, i|
    if i < variable_instructions.size
      # figure out which variable we should be setting
      variable = variable_instructions[i]
      declarations[variable].each do |instr|
        # for each possible instruction, set it and recurse on the right hand of the list
        # note that we can simply set this variable (insteaad of copying the entire list)
        # since we'll overwrite it when the recursion ends and we return here
        # in order for this we must not change to original list (|variable_instructions|)
        fixed[i] = instr
        set_variables.call(fixed, i+1)
      end
    else
      # print the signature
      puts 'int ' << (signature_format % fixed) << "(CODE **c) {\n"

      # store the method name so that we can print it in 'init_patterns' later
      $c_methods += [signature_format % fixed]

      # print the declarations
      puts declarations_format % fixed

      # print the statements
      puts build_statements_string(rule, declarations_count.to_s, variable_names, fixed.clone)

      # close off the method
      puts "}\n\n\n"
    end
  end

  # call the block created above with an empty array (same size as |variable_instructions.size|)
  # start at index 0 so we get full coverage of the variable instructions.
  set_variables.call([] * variable_instructions.size, 0)
end

#
#
def print_c_code(tree)
  declarations = build_declaration_map(tree)

  include Peephole::TokenData
  tree.children.each do |rule|
    if rule.type == RULE
      print_rule(rule, declarations.clone)
    end
  end

  init_patterns = "int init_patterns() {\n"
  $c_methods.each { |m| init_patterns << '  ADD_PATTERN(' << m << ");\n" }
  init_patterns << "}\n"
  puts init_patterns
end

# MAIN
ARGV.each do |arg|
  f = open(arg)
  parser = Peephole::Parser.new(f)
  print_c_code(parser.start.tree)
end

