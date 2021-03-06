require_relative 'grammar/PeepholeParser.rb'

module Peephole
  class GenerateC
    include Peephole::TokenData

    def ind()
      return '  ' * @indent
    end

    # Public: Executes a depth fist traversal of a tree object and calls a function on each node as
    #         it is entered.
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


    # Public: Executes a depth first traversal on a tree object and carries calls two functions for
    #         each node. First |on_enter| is called with the current node as argument as we enter
    #         the node (ie before the children are traversed.  Then |traverse| iterates on all
    #         children (in doing so calling |on_enter| and |on_exit| on all children nodes).
    #         Finally |on_exit| is called on the node.
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

    #
    #
    def build_declaration_map(tree)

      declaration_map = {}

      tree.children.each do |declaration|
        if declaration.type == DECLARATION
          # find the name of the newly declared variable
          name = declaration.children[0].text

          # if two declarations have the same name throw an execption to be caught and show to the
          # user
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
      s = "\n" << ind << 'CODE *' << name + ' = '
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
      @indent += 1
      format = ''
      argument_string = ''
      instr_index = 1;
      instr_count = 0;
      next_instr = '*c';

      # sets the |argument| variable to be nil if |node| is nil, otherwise to the text contained
      # within |node| this is set at this level because the variable is at the NAMED/UNNAMED level,
      # but needs to be used at the INSTRUCTION level in order to get passed in the is_<inst>()
      # method.
      set_argument = lambda do |args|
        argument_string = ''
        args.each do |arg_node|
          if arg_node != nil
            argument_string << ", &arg_#{arg_node.text}"
            # print the argument declaration
            format << "#{ind}int arg_#{arg_node.text};\n"
          end
        end
      end

      #
      print_check_instruction = lambda do |instruction|
        # print the instruction checking if statement
        format << "#{ind}if (!is_#{instruction}(#{next_instr}#{argument_string})) {\n"
        format << "#{ind}  return 0;\n"
        format << "#{ind}}\n"
      end

      # block to be run up entering a parent node
      in_a_node = lambda do |node|
        children = node.children
        instr_count += 1

        case node.type
        when NAMED_INSTRUCTION
          # print the instruciton declaration
          name =  'instr_' << children[0].text
          format << declaration_string(name, next_instr)
          set_argument.call(children[2...node.children.size])
          instr_index += 1
        when UNNAMED_INSTRUCTION
          # number the isntruction and print the declaration
          name =  'instr_' << instr_index.to_s
          format << declaration_string(name, next_instr)
          set_argument.call(children[1...node.children.size])
          instr_index += 1
        when INSTRUCTION
          instruction_variable = children[0].text
          instruction = declarations.has_key?(instruction_variable) ? '%s' : instruction_variable
          print_check_instruction.call(instruction)
        when INSTRUCTION_SET
          print_check_instruction.call("%s")
         when INSTRUCTION_COUNT
          format << "#{ind}if (#{next_instr} == NULL) {\n#{ind}  return 0;\n#{ind}}\n"
        else
          next
        end
      end

      traverse(rule, in_a_node)
      @indent -= 1
      return [format, (instr_index - 1).to_s]
    end

    #
    #
    def get_variable_instructions(rule, declarations)
      index = 1
      variable_names = []
      variable_instructions = []

      parent_name = lambda do |node|
        case node.parent.type
        when NAMED_INSTRUCTION
          return node.parent.children[0].text
        when UNNAMED_INSTRUCTION
          return 'unnamed'
        end
      end

      in_a_node = lambda do |line|
        case line.type
        when INSTRUCTION
          instruction = line.children[0].text
          if declarations[instruction] != nil
            variable_names += [parent_name.call(line)]
            variable_instructions += [instruction]
          end
        when INSTRUCTION_SET
          variable_names += [parent_name.call(line)]
          # create a name for the new set we'll create
          name = 'inlined_' << index.to_s

          # create a set containing all the instructions in this declaration
          set = Set.new
          line.children.each { |instr| set.add(instr.text) }

          # add the set to |declarations|, add a new entry to |variable_instructions|, increment
          declarations[name] = set
          variable_instructions += [name]
          index += 1
        end
      end

      traverse(rule, in_a_node)
      return [variable_names, variable_instructions]
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

    #
    #
    def build_c_condition(condition)
      separator = ''
      case condition.type
      when T_INT
        return condition.text
      when T_VARIABLE
        return 'arg_' << condition.text
      when CONDITION_EQUAL
        separator = ' == '
      when CONDITION_NEQUAL
        separator = ' != '
      when CONDITION_AND
        separator = ' && '
      when CONDITION_OR
        separator = ' || '
      when CONDITION_LT
        separator = ' < '
      when CONDITION_GT
        separator = ' > '
      when CONDITION_LE
        separator = ' <= '
      when CONDITION_GT
        separator = ' >= '
      end

      children_strings = []
      condition.children.each { |child| children_strings += [build_c_condition(child)]}
      return '(' << children_strings.join(separator) << ')'
    end

    #
    #
    def build_if_statement_string(if_statements, replace_count, variable_names, variable_types)
      string = "\n"

      first = true
      if_statements.each do |stmt|
        case stmt.type
        when STATEMENT_IF
          if first
            string << ind
            first = false
          else
            string << ' else '
          end
          string << 'if (' << build_c_condition(stmt.children[0]) << ") {\n"
          string << build_statements_string(stmt, replace_count, variable_names, variable_types)
          string << ind << '}'
        when STATEMENT_ELSE
          return string
        end
      end

      string << " else {\n#{ind}  return 0;\n#{ind}}"
      return string
    end

    #
    #
    def build_statements_string(rule, replace_count, variable_names, variable_types)

      @indent += 1
      string = ''
      stmt_count = 1

      # code run up entering a parent node
      rule.children.each do |node|
        children = node.children

        created = false
        case node.type
        when STATEMENT_INSTRUCTION
          instruction_type = children[0].text
          string << "\n" << ind << 'CODE *statement_' << stmt_count.to_s
          string<< ' = makeCODE' << instruction_type << '('
          for i in 1...node.children.size do
            string << build_c_expression(children[i]) + ', '
          end
          string << "NULL);\n"
          created = true
        when STATEMENT_VARIABLE
          instr_name = children[0].text
          string << "\n" << ind << 'CODE *statement_' << stmt_count.to_s
          string << ' = copy(instr_' << instr_name << ");\n"
          created = true
        when STATEMENT_SWITCH
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

          string << "\n" << ind << 'CODE *statement_' << stmt_count.to_s
          string << ' = makeCODE' << instruction_type << '('
          for i in 1...current_case.children.size do
            string << build_c_expression(current_case.children[i]) + ', '
          end
          string << "NULL);\n"
          created = true
        when STATEMENT_COMPOUND
          # deal with if statements!
          string << build_if_statement_string(children, replace_count, variable_names, variable_types)
        end

        if created
          if stmt_count > 1
            prev_stmt = "#{ind}statement_#{(stmt_count - 1).to_s}"
            string << "#{prev_stmt}->next = statement_#{stmt_count.to_s};\n"
          end
          stmt_count += 1
        end
      end

      if stmt_count == 1
        string << "\n#{ind}return replace(c, #{replace_count}, NULL);\n"
      else
        string << "\n#{ind}return replace(c, #{replace_count}, statement_1);\n"
      end
      @indent -= 1
      return string
    end

    #
    #
    def build_rule(rule, declarations)
      rule_code = ''
      variables = get_variable_instructions(rule, declarations)
      variable_names = variables[0]
      variable_instructions = variables[1]

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
      # the function.  This is done in-place (|fixed| is never copied) which means we don't have to
      # deal with crazy space complexity.
      set_variables = lambda do |fixed, i|
        if i < variable_instructions.size
          # figure out which variable we should be setting
          variable = variable_instructions[i]
          declarations[variable].each do |instr|
            # for each possible instruction, set it and recurse on the right hand of the list
            # note that we can simply set this variable (instead of copying the entire list)
            # since we'll overwrite it when the recursion ends and we return here
            # in order for this we must not change to original list (|variable_instructions|)
            fixed[i] = instr
            set_variables.call(fixed, i+1)
          end
        else
          # print the signature
          rule_code << 'int ' << (signature_format % fixed) << "(CODE **c) {\n"

          # store the method name so that we can print it in 'init_patterns' later
          @c_methods += [signature_format % fixed]

          # print the declarations
          rule_code << declarations_format % fixed

          # print the statements
          rule_code << build_statements_string(rule, declarations_count, variable_names, fixed)

          # close off the method
          rule_code << "}\n\n\n"
        end
      end

      # call the block created above with an empty array (same size as |variable_instructions.size|)
      # start at index 0 so we get full coverage of the variable instructions.
      set_variables.call([] * variable_instructions.size, 0)
      rule_code
    end

    # Internal: Prints the contents of the peephole_helpers.h file, meant to be
    # printed at the top of each generated file.
    #
    def build_c_helpers()
      helpers_file = File.dirname(__FILE__) + '/peephole_helpers.h'
      helpers_code = ''
      File.foreach(helpers_file) { |line| helpers_code << line }
      helpers_code << "\n" # Extra empty line for separation
    end

    #
    #
    def build_c_code(tree, file_name)
      c_code = ''
      declarations = build_declaration_map(tree)
      tree.children.each do |rule|
        if rule.type == RULE
          c_code << build_rule(rule, declarations.clone)
        end
      end

      base_name = /([^\.]+)/.match(File.basename(file_name))
      c_code << "int init_patterns_#{base_name}() {\n"
      @c_methods.each { |m| c_code << '  ADD_PATTERN(' << m << ");\n" }
      c_code << "  return 1;\n}\n"
    end

    #
    #
    def generate(files, use_stdout)
      c_helpers = build_c_helpers
      files.each do |file_name|
        @c_methods = []
        @indent = 0

        parser = Peephole::Parser.new(open(file_name))
        tree = parser.start.tree
        if use_stdout
          puts c_helpers
          puts build_c_code(tree)
        else
          output_filename = File.basename(file_name.sub(/\.patterns?|\.peep(?:hole)?/, ''))
          output_path = File.dirname(file_name) + '/' + output_filename + '.gen.h'
          File.open(output_path, 'w') do |output_handle|
            output_handle.puts c_helpers
            output_handle.puts build_c_code(tree, file_name)
          end
          $stderr.puts "Generated #{output_path}"
        end
      end
    end
  end # GenerateC

  module Generate
    def self.generate_c(files, use_stdout)
      GenerateC.new.generate(files, use_stdout)
    end
  end # Generate
end # Peephole
