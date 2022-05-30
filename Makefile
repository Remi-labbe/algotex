SHELL=/bin/sh
LEX=flex
YACC=bison
CC=gcc
CFLAGS=-g -std=c11 -pedantic -Wall
LDFLAGS=-lfl
# --nounput: ne génère pas la fonction yyunput() inutile
# --DYY_NO_INPUT: ne prend pas en compte la fonction input() inutile
# -D_POSIX_SOURCE: déclare la fonction fileno()
LEXOPTS=-D_POSIX_SOURCE -DYY_NO_INPUT --nounput
YACCOPTS=

EXECS=algo2asm run

all: $(EXECS)

### algo2asm

algo2asm: lex.algo2asm.o algo2asm.tab.o stable.o stack.o
	$(CC) $+ -o $@ $(LDFLAGS)

algo2asm.tab.c algo2asm.tab.h: algo2asm.y lex.algo2asm.h
	# $(YACC) $(YACCOPTS) $< -d -v
	$(YACC) $(YACCOPTS) $< -d -v --graph

### run

run: lex.run.o run.tab.o stack.o
	$(CC) $+ -o $@ $(LDFLAGS)

run.tab.c run.tab.h: run.y lex.run.h
	# $(YACC) $(YACCOPTS) $< -d -v
	$(YACC) $(YACCOPTS) $< -d -v --graph

### others

lex.%.c: %.l %.tab.h
	$(LEX) $(LEXOPTS) -o $@ $<

lex.%.h: %.l
	$(LEX) $(LEXOPTS) --header-file=$@ $<

%.o: %.c
	$(CC) -DYYDEBUG $(CFLAGS) $< -c

clean:
	$(RM) $(EXECS) *.o lex.*.* *.tab.* *.err *.output *.out *.dot *.gv *.asm
