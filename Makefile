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

algo2asm: algo2asm.lex.o algo2asm.tab.o stable.o stack.o
	$(CC) $+ -o $@ $(LDFLAGS)

algo2asm.tab.c algo2asm.tab.h: algo2asm.y algo2asm.lex.h
	$(YACC) $(YACCOPTS) $< -d -v
	# $(YACC) $(YACCOPTS) $< -d -v --graph

algo2asm.lex.c: algo2asm.l algo2asm.tab.h
	$(LEX) $(LEXOPTS) -o $@ $<

algo2asm.lex.h: algo2asm.l
	$(LEX) $(LEXOPTS) --header-file=$@ $<

### run

run: run.lex.o run.tab.o stack.o
	$(CC) $+ -o $@ $(LDFLAGS)

run.tab.c run.tab.h: run.y run.lex.h
	$(YACC) $(YACCOPTS) $< -d -v
	# $(YACC) $(YACCOPTS) $< -d -v --graph

run.lex.c: run.l run.tab.h
	$(LEX) $(LEXOPTS) -o $@ $<

run.lex.h: run.l
	$(LEX) $(LEXOPTS) --header-file=$@ $<

### others

stack.o: stack.h stack.c

%.o: %.c
	$(CC) -DYYDEBUG $(CFLAGS) $< -c

clean:
	$(RM) $(EXECS) *.o *.lex.* lex.yy.c *.tab.* *.err *.output *.out *.dot
