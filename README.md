### Jasmin Peephole Visual Compiler ###


## Description ##
----------------

This compiler was created to generate code  for the peephole pattern portion of McGill's compilers course
([COMP 520](http://www.cs.mcgill.ca/~cs520/)). It takes as input a language defined specifically for this compiler
(explained more in [`grammar/README`](https://github.com/vbonnet/Peephole-Compiler/blob/master/grammar/README.md)).
The language is designed to resemble the [Jasmin](http://jasmin.sourceforge.net/) bytecode while still allow for the
creation of complex patterns.  The output of the compiler is .c files that depend on the
[optimize.c](http://www.cs.mcgill.ca/~cs520/2012/joos/a-/optimize.c) API.


## Dependendices ##
-------------------

This project uses [ANTLR](http://antlr.org/) for its parser generator.  ANTLR provides many target languages, this
project is using the [Ruby target](http://antlr.ohboyohboyohboy.org/) for ANTLR.  The docs for the code generated
by this target can be found at http://rubydoc.info/github/ohboyohboyohboy/antlr3/.  Unfortunately the docs themselves
are somewhat lacking as the main developer seems to have dropped the project.  Honestly given the support provided
for ANTLR+Ruby we probably should've picked a different language.  But @vbonnet wanted to code in Ruby, so that was
that.


## Installation ##
------------------

The first step in installation is to install the actual repo.

    git clone git://github.com/vbonnet/Peephole-Compiler.git

The repo comes with the ANTLR code inside the `lib/` directory.  However the Ruby target requires some ruby code not
included with the project.  To download this code simply run

    gem install antlr3

Now you're set to go!  To generate the Lexer+Parser simply run: (There will be a Makefile later, I'm just lazy)

     ./gen_grammar

That should generate `PeepholeLexer.rb` and `PeepholeParser.rb` inside `src/grammar/`.


## Running the code ##
----------------------

You can run the code by simply running the command:

    ruby src/peephole.rb tests/math.patterns

This currently prints to stdout (I recommend `[_command] > tests/math.h; emacs tests/math.h`) for now.
It'll soon be printing to a file, just you wait.  This should generate valid c code (built around
optimize.c) for the file parsed.  The way to use the output is still bad atm, firstly you have to move
[`peephole_helpers.h`](https://github.com/vbonnet/Peephole-Compiler/blob/master/peephole_helpers.h)
into your JOOS directory.  Then you add the following to your `patterns.h` file:

    #include "peephole_helpers.h"
    #include "[_generate_file].h"

Finally you have to rename `init_patterns()` in the generated file and then call it.  This part is
particularly ugly and will be fixed soon.


## Style guides ##
------------------

* The Ruby code should follow the [Github Ruby styleguide](https://github.com/styleguide/ruby)
* The grammar has its own style, defined in
[`grammar/README`](https://github.com/vbonnet/Peephole-Compiler/blob/master/grammar/README.md)


## Contributing ##
------------------

Go for it!  Submit a pull request, feel free.  We're working on our own stuff atm, so feel free to
write up feature requests but know they may not be addressed in what you may consider reasonable
time.  Honestly you're better off just adding whatever you want yourself.  Bugs we will likely
address in reasonable time seeing as we're using this ourselves.
