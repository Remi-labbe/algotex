%{
  #define _POSIX_C_SOURCE 200809L
  #ifndef LABEL_SIZE
  #define LABEL_SIZE 128
  #endif // LABEL_SIZE
  #include <ctype.h>
  #include <stdlib.h>
  #include <stdio.h>
  #include <stdarg.h>
  #include <limits.h>
  #include <fcntl.h>
  #include <unistd.h>
  #include <string.h>
  #include "status.h"
  #include "types.h"
  #include "stable.h"
  #include "stack.h"

  int yylex(void);
  void yyerror(char const *);
  void free_symbols();
  void fail_with(const char *format, ...);
  void true_from_positive();
  // Variables labels [[
  static unsigned int new_label_number() {
    static unsigned int current_label_number = 0u;
    if ( current_label_number == UINT_MAX ) {
      fail_with("Error: maximum label number reached!\n");
    }
    return current_label_number++;
  }
  static void create_label(char *buf, size_t buf_size, const char *format, ...) {
    va_list ap;
    va_start(ap, format);
    if ( vsnprintf(buf, buf_size, format, ap) >= buf_size ) {
      va_end(ap);
      fail_with("Error in label generation: size of label exceeds maximum size!\n");
    }
    va_end(ap);
  }
  // ]]

  extern FILE *yyin;
  static int fd, offset = 0;
  symbol_table_entry *curr_fun = NULL;
%}
%union {
  int integer;
  char id[64];
  status s;
}
%type<s> expr func inst linst algo_b call_params param
%token ALGO_B ALGO_E
%token IF FI ELSE DOWHILE OD DO WHILEOD CALL RETURN IGNORE
%token TIMES
%token<id> ID
%token<integer> NUMBER
%token TRUE FALSE AND OR NOT EQ NEQ LTH GTH LEQ GEQ
%left AFFECT
%left OR
%left AND
%left EQ NEQ LTH GTH LEQ GEQ
%left '+' '-'
%left '*' TIMES '/'
%right UNOT
%right UMINUS
%start func
%%

func:
algo_b '{' lparams '}' linst algo_e {
  $$ = STATEMENT;
}
;

algo_b:
ALGO_B '{' ID '}' {
  curr_fun = new_symbol_table_entry($3);
  curr_fun->class = FUNCTION;
  curr_fun->nParams = 0;
  curr_fun->desc[0] = INT_T;
  dprintf(fd, ":%s\n", $3);
}
;

lparams:
%empty
| id ',' lparams
| id
;

id:
ID {
  if (search_symbol_table($1) != NULL) {
    fail_with("%s already exist: duplicated variable.\n", $1);
  }
  symbol_table_entry *ste = new_symbol_table_entry($1);
  ste->add = ++curr_fun->nParams;
  curr_fun->desc[ste->add] = INT_T;
  ste->class = PARAMETER;
  ste->desc[0] = INT_T;
}
;

algo_e:
ALGO_E {
  for(size_t i = 0; i < curr_fun->nParams; i++) {
    free_first_symbol_table_entry();
  }
}
;

linst:
  inst { $$ = STATEMENT; }
| error { yyerrok; }
| error linst { yyerrok; }
| inst linst {
  $$ = STATEMENT;
}
;

inst:
AFFECT '{' ID '}' '{' expr '}' {
  if ($6 >= ERR_TYP) {
    $$ = $6;
  } else {
    symbol_table_entry *ste;
    if ((ste = search_symbol_table($3)) == NULL) {
      $$ = STATEMENT;
      symbol_table_entry *ste = new_symbol_table_entry($3);
      ste->class = LOCAL_VARIABLE;
      ste->add = ++curr_fun->nLocalVariables;
      ste->desc[0] = INT_T;
      --offset;
    } else {
      $$ = STATEMENT;
      dprintf(fd, "\tpop ax\n");
      --offset;
      printf("SET\n");
      printf("offset set: %d\n", offset);
      printf("nloc:%zu\n", curr_fun->nLocalVariables);
      printf("nparams:%zu\n", curr_fun->nLocalVariables);
      printf("add:%d\n", ste->add);
      int delta;
      switch(ste->class) {
        case PARAMETER:
          delta = 2 * (offset + curr_fun->nLocalVariables + curr_fun->nParams - (ste->add - 1));
          printf("delta: %d\n", delta);
          dprintf(fd, "\tcp cx,sp\n"
                      "\tconst bx,%d\n", delta);
          dprintf(fd, "\tsub cx,bx\n");
          break;
        case LOCAL_VARIABLE:
          delta = 2 * (offset + curr_fun->nLocalVariables - (ste->add));
          dprintf(fd, "\tcp cx,sp\n"
                      "\tconst bx,%d\n", delta);
          dprintf(fd, "\tsub cx,bx\n");
          break;
        default:
          fail_with("invalid class on %s\n", ste->name);
      }
      dprintf(fd, "\tstorew ax,cx\n");
    }
  }
}
| IF '{' expr '}' if_b linst if_e end FI {
  status s = 0;
  if ((s = $3) >= ERR_TYP || (s = $6) >= ERR_TYP) {
    $$ = s;
  } else {
    $$ = STATEMENT;
  }
}
| IF '{' expr '}' if_b linst ELSE else_b if_e linst else_e end FI {
  status s = 0;
  if ((s = $3) >= ERR_TYP) {
    $$ = s;
  } else {
    $$ = STATEMENT;
  }
}
| DOWHILE  dowhile_t '{' expr '}' dowhile_b linst dowhile_e end OD {
  status s = 0;
  if ((s = $4) >= ERR_TYP) {
    $$ = s;
  } else {
    $$ = STATEMENT;
  }
}
| RETURN '{' expr '}' {
  --offset;
  printf("%d\n", offset);
  dprintf(fd, "\tpop ax\n");
  for (size_t i = 0; i < curr_fun->nLocalVariables; i++) {
    free_first_symbol_table_entry();
    dprintf(fd, "\tpop dx\n");
  }
  dprintf(fd, "\tret\n");
}
| IGNORE {
  $$ = STATEMENT;
}
;

if_b: %empty {
  push(new_label_number());
  unsigned int n = top();
  char nlabel[LABEL_SIZE] = {0};
  create_label(nlabel, LABEL_SIZE, "if_f%u", n);
  --offset;
  dprintf(fd, "\tpop ax\n"
              "\tconst bx,0\n"
              "\tconst cx,%s\n", nlabel);
  dprintf(fd, "\tcmp ax,bx\n"
              "\tjmpc cx\n");
}
;

if_e: %empty {
  unsigned int n = top();
  char nlabel[LABEL_SIZE] = {0};
  create_label(nlabel, LABEL_SIZE, "if_f%u", n);
  dprintf(fd, ":%s\n", nlabel);
}
;

else_b: %empty {
  unsigned int n = top();
  char nlabel[LABEL_SIZE] = {0};
  create_label(nlabel, LABEL_SIZE, "j_else%u", n);
  dprintf(fd, "\tconst cx,%s\n", nlabel);
  dprintf(fd, "\tjmp cx\n");
}
;

else_e: %empty {
  unsigned int n = top();
  char nlabel[LABEL_SIZE] = {0};
  create_label(nlabel, LABEL_SIZE, "j_else%u", n);
  dprintf(fd, ":%s\n", nlabel);
}
;

dowhile_t: %empty {
  push(new_label_number());
  unsigned int n = top();
  char label[LABEL_SIZE] = {0};
  create_label(label, LABEL_SIZE, "w_test%u", n);
  dprintf(fd, ":%s\n", label);
}
;

dowhile_b: %empty {
  unsigned int n = top();
  char label[LABEL_SIZE] = {0};
  create_label(label, LABEL_SIZE, "w_end%u", n);
  --offset;
  dprintf(fd, "\tpop ax\n"
              "\tconst bx,0\n"
              "\tconst cx,%s\n", label);
  dprintf(fd, "\tcmp ax,bx\n"
              "\tjmpc cx\n");
}
;

dowhile_e: %empty {
  unsigned int n = top();
  char tlabel[LABEL_SIZE] = {0};
  create_label(tlabel, LABEL_SIZE, "w_test%u", n);
  char elabel[LABEL_SIZE] = {0};
  create_label(elabel, LABEL_SIZE, "w_end%u", n);
  dprintf(fd, "\tconst ax,%s\n", tlabel);
  dprintf(fd, "\tjmp ax\n");
  dprintf(fd, ":%s\n", elabel);
}
;

end: %empty {
  pop();
}
;

call_params:
%empty {
  $$ = STATEMENT;
}
| param ',' call_params {
  status s;
  --offset;
  if ((s = $1) >= ERR_TYP || (s = $3) >= ERR_TYP) {
    $$ = s;
  } else {
    $$ = $1;
  }
}
| param {
  --offset;
  $$ = $1;
}
;

param: expr {
  $$ = $1;
  push(pop() + 1);
}
;

expr :
CALL '{' ID {
  symbol_table_entry *ste = search_symbol_table($3);
  if (ste == NULL || ste->class != FUNCTION) {
    fail_with("invalid name in fun call.\n");
  } else {
    push(0);
  }
} '}' '{' call_params '}' {
  if ($7 >= ERR_TYP) {
    $$ = $7;
  } else {
    symbol_table_entry *ste = search_symbol_table($3);
    size_t n = pop();
    if (ste->nParams != n) {
      fail_with("invalid number of parameters in function call\n");
    }
    $$ = INT;

    dprintf(fd, "\tconst ax,%s\n", $3);
    dprintf(fd, "\tcall ax\n");

    for(size_t i = 0; i < n; ++i) {
      dprintf(fd, "\tpop dx\n");
    }
    dprintf(fd, "\tpush ax\n");
    ++offset;
  }
}
| ID {
  symbol_table_entry *ste = search_symbol_table($1);
  if (ste == NULL) {
    $$ = ERR_DEC;
  } else {
    $$ = INT;
    int delta;
    printf("ID\n");
    printf("ste: %s - %d\n", ste->name, ste->add);
    printf("offset ret: %d\n", offset);
    printf("nloc:%zu\n", curr_fun->nLocalVariables);
    printf("nparams:%zu\n", curr_fun->nLocalVariables);
    printf("add:%d\n", ste->add);
    switch(ste->class) {
      case PARAMETER:
        delta = 2 * (offset + curr_fun->nLocalVariables + curr_fun->nParams - (ste->add - 1));
          printf("delta: %d\n", delta);
        dprintf(fd, "\tcp cx,sp\n"
                    "\tconst bx,%d\n", delta);
        dprintf(fd, "\tsub cx,bx\n");
        break;
      case LOCAL_VARIABLE:
        delta = 2 * (offset + curr_fun->nLocalVariables - (ste->add));
        dprintf(fd, "\tcp cx,sp\n"
                    "\tconst bx,%d\n", delta);
        dprintf(fd, "\tsub cx,bx\n");
        break;
      default:
        fail_with("invalid class on %s\n", ste->name);
    }
    dprintf(fd, "\tloadw ax,cx\n"
                "\tpush ax\n");
    ++offset;
  }
}
| NUMBER {
  ++offset;
  dprintf(fd, "\tconst ax,%d\n", $1);
  dprintf(fd, "\tpush ax\n");
  $$ = INT;
}
| TRUE {
  ++offset;
  dprintf(fd, "\tconst ax,1\n"
              "\tpush ax\n");
  $$ = INT;
}
| FALSE {
  ++offset;
  dprintf(fd, "\tconst ax,0\n"
              "\tpush ax\n");
  $$ = INT;
}
| '(' expr ')' {
  $$ = $2;
}
| expr '+' expr {
  --offset;
  status s = 0;
  if ((s = $1) >= ERR_TYP || ( s = $3) >= ERR_TYP) {
    $$ = s;
  } else {
    $$ = INT;
    dprintf(fd, "\tpop ax\n"
                "\tpop bx\n"
                "\tadd ax,bx\n"
                "\tpush ax\n");
  }
}
| expr '-' expr {
  --offset;
  status s = 0;
  if ((s = $1) >= ERR_TYP || ( s = $3) >= ERR_TYP) {
    $$ = s;
  } else {
    if ($1 == INT && $3 == INT) {
      $$ = INT;
      dprintf(fd, "\tpop ax\n"
                  "\tpop bx\n"
                  "\tsub bx,ax\n"
                  "\tpush bx\n");
    } else {
      $$ = ERR_TYP;
    }
  }
}
| expr '*' expr {
  --offset;
  status s = 0;
  if ((s = $1) >= ERR_TYP || ( s = $3) >= ERR_TYP) {
    $$ = s;
  } else {
    $$ = INT;
    dprintf(fd, "\tpop ax\n"
                "\tpop bx\n"
                "\tmul ax,bx\n"
                "\tpush ax\n");
  }
}
| expr TIMES expr {
  --offset;
  status s = 0;
  if ((s = $1) >= ERR_TYP || ( s = $3) >= ERR_TYP) {
    $$ = s;
  } else {
    $$ = INT;
    dprintf(fd, "\tpop ax\n"
                "\tpop bx\n"
                "\tmul ax,bx\n"
                "\tpush ax\n");
  }
}
| expr '/' expr {
  --offset;
  status s = 0;
  if ((s = $1) >= ERR_TYP || ( s = $3) >= ERR_TYP) {
    $$ = s;
  } else {
    if ($3 == 0) {
      $$ = ERR_DIV;
    } else {
      $$ = INT;
    }
    dprintf(fd, "\tpop bx\n"
                "\tpop cx\n"
                "\tconst ax,diverr\n"
                "\tconst dx,error\n"
                "\tdiv cx,bx\n"
                "\tjmpe dx\n"
                "\tpush cx\n");
  }
}
| '-' expr %prec UMINUS {
  if ($2 >= ERR_TYP) {
    $$ = $2;
  } else {
    $$ = INT;
    dprintf(fd, "\tpop ax\n"
                "\tconst bx,-1\n"
                "\tmul ax,bx\n"
                "\tpush ax\n");
  }
}
| expr AND expr {
  --offset;
  status s = 0;
  if ((s = $1) >= ERR_TYP || (s = $3) >= ERR_TYP) {
    $$ = s;
  } else {
    $$ = INT;
    true_from_positive();
    dprintf(fd, "\tand ax,bx\n"
                "\tpush ax\n");
  }
}
| expr OR expr {
  --offset;
  status s = 0;
  if ((s = $1) >= ERR_TYP || (s = $3) >= ERR_TYP) {
    $$ = s;
  } else {
    $$ = INT;
    true_from_positive();
    dprintf(fd, "\tor ax,bx\n"
                "\tpush ax\n");
  }
}
| expr EQ expr {
  --offset;
  status s = 0;
  if ((s = $1) >= ERR_TYP || (s = $3) >= ERR_TYP) {
    $$ = s;
  } else {
    $$ = INT;
    int n = new_label_number();
    char tlabel[LABEL_SIZE] = {0};
    create_label(tlabel, LABEL_SIZE, "jmptrue%u", n);
    char nlabel[LABEL_SIZE] = {0};
    create_label(nlabel, LABEL_SIZE, "jmpnext%u", n);
    dprintf(fd, "\tconst dx,%s\n", tlabel);
    dprintf(fd, "\tconst cx,%s\n", nlabel);
    dprintf(fd, "\tpop ax\n"
                "\tpop bx\n"
                "\tcmp ax,bx\n"
                "\tjmpc dx\n"
                "\tconst ax,0\n"
                "\tpush ax\n"
                "\tjmp cx\n");
    dprintf(fd, ":%s\n", tlabel);
    dprintf(fd, "\tconst ax,1\n"
                "\tpush ax\n");
    dprintf(fd, ":%s\n", nlabel);
  }
}
| expr NEQ expr {
  --offset;
  status s = 0;
  if ((s = $1) >= ERR_TYP || (s = $3) >= ERR_TYP) {
    $$ = s;
  } else {
    $$ = INT;
    int n = new_label_number();
    char tlabel[LABEL_SIZE] = {0};
    create_label(tlabel, LABEL_SIZE, "jmptrue%u", n);
    char nlabel[LABEL_SIZE] = {0};
    create_label(nlabel, LABEL_SIZE, "jmpnext%u", n);
    dprintf(fd, "\tconst dx,%s\n", tlabel);
    dprintf(fd, "\tconst cx,%s\n", nlabel);
    dprintf(fd, "\tpop ax\n"
                "\tpop bx\n"
                "\tcmp ax,bx\n"
                "\tjmpc dx\n"
                "\tconst ax,1\n"
                "\tpush ax\n"
                "\tjmp cx\n");
    dprintf(fd, ":%s\n", tlabel);
    dprintf(fd, "\tconst ax,0\n"
                "\tpush ax\n");
    dprintf(fd, ":%s\n", nlabel);
  }
}
| expr LTH expr {
  --offset;
  status s = 0;
  if ((s = $1) >= ERR_TYP || (s = $3) >= ERR_TYP) {
    $$ = s;
  } else {
    $$ = INT;
    int n = new_label_number();
    char tlabel[LABEL_SIZE] = {0};
    create_label(tlabel, LABEL_SIZE, "jmptrue%u", n);
    char nlabel[LABEL_SIZE] = {0};
    create_label(nlabel, LABEL_SIZE, "jmpnext%u", n);
    dprintf(fd, "\tconst dx,%s\n", tlabel);
    dprintf(fd, "\tconst cx,%s\n", nlabel);
    dprintf(fd, "\tpop ax\n"
                "\tpop bx\n"
                "\tsless bx,ax\n"
                "\tjmpc dx\n"
                "\tconst ax,0\n"
                "\tpush ax\n"
                "\tjmp cx\n");
    dprintf(fd, ":%s\n", tlabel);
    dprintf(fd, "\tconst ax,1\n"
                "\tpush ax\n");
    dprintf(fd, ":%s\n", nlabel);
  }
}
| expr LEQ expr {
  --offset;
  status s = 0;
  if ((s = $1) >= ERR_TYP || (s = $3) >= ERR_TYP) {
    $$ = s;
  } else {
    $$ = INT;
    int n = new_label_number();
    char tlabel[LABEL_SIZE] = {0};
    create_label(tlabel, LABEL_SIZE, "jmptrue%u", n);
    char nlabel[LABEL_SIZE] = {0};
    create_label(nlabel, LABEL_SIZE, "jmpnext%u", n);
    dprintf(fd, "\tconst dx,%s\n", tlabel);
    dprintf(fd, "\tconst cx,%s\n", nlabel);
    dprintf(fd, "\tpop ax\n"
                "\tpop bx\n"
                "\tsless bx,ax\n"
                "\tjmpc dx\n"
                "\tcmp ax,bx\n"
                "\tjmpc dx\n"
                "\tconst ax,0\n"
                "\tpush ax\n"
                "\tjmp cx\n");
    dprintf(fd, ":%s\n", tlabel);
    dprintf(fd, "\tconst ax,1\n"
                "\tpush ax\n");
    dprintf(fd, ":%s\n", nlabel);
  }
}
| expr GTH expr {
  --offset;
  status s = 0;
  if ((s = $1) >= ERR_TYP || (s = $3) >= ERR_TYP) {
    $$ = s;
  } else {
    $$ = INT;
    int n = new_label_number();
    char tlabel[LABEL_SIZE] = {0};
    create_label(tlabel, LABEL_SIZE, "jmptrue%u", n);
    char nlabel[LABEL_SIZE] = {0};
    create_label(nlabel, LABEL_SIZE, "jmpnext%u", n);
    dprintf(fd, "\tconst dx,%s\n", tlabel);
    dprintf(fd, "\tconst cx,%s\n", nlabel);
    dprintf(fd, "\tpop ax\n"
                "\tpop bx\n"
                "\tsless ax,bx\n"
                "\tjmpc dx\n"
                "\tconst ax,0\n"
                "\tpush ax\n"
                "\tjmp cx\n");
    dprintf(fd, ":%s\n", tlabel);
    dprintf(fd, "\tconst ax,1\n"
                "\tpush ax\n");
    dprintf(fd, ":%s\n", nlabel);
  }
}
| expr GEQ expr {
  --offset;
  status s = 0;
  if ((s = $1) >= ERR_TYP || (s = $3) >= ERR_TYP) {
    $$ = s;
  } else {
    $$ = INT;
    int n = new_label_number();
    char tlabel[LABEL_SIZE] = {0};
    create_label(tlabel, LABEL_SIZE, "jmptrue%u", n);
    char nlabel[LABEL_SIZE] = {0};
    create_label(nlabel, LABEL_SIZE, "jmpnext%u", n);
    dprintf(fd, "\tconst dx,%s\n", tlabel);
    dprintf(fd, "\tconst cx,%s\n", nlabel);
    dprintf(fd, "\tpop ax\n"
                "\tpop bx\n"
                "\tsless ax,bx\n"
                "\tjmpc dx\n"
                "\tcmp ax,bx\n"
                "\tjmpc dx\n"
                "\tconst ax,0\n"
                "\tpush ax\n"
                "\tjmp cx\n");
    dprintf(fd, ":%s\n", tlabel);
    dprintf(fd, "\tconst ax,1\n"
                "\tpush ax\n");
    dprintf(fd, ":%s\n", nlabel);
  }
}
| NOT expr %prec UNOT {
  if ($2 >= ERR_TYP) {
    $$ = $2;
  } else {
    $$ = INT;
    int n = new_label_number();
    char tlabel[LABEL_SIZE] = {0};
    create_label(tlabel, LABEL_SIZE, "jmptrue%u", n);
    char nlabel[LABEL_SIZE] = {0};
    create_label(nlabel, LABEL_SIZE, "jmpnext%u", n);
    dprintf(fd, "\tconst dx,%s\n", tlabel);
    dprintf(fd, "\tconst cx,%s\n", nlabel);
    dprintf(fd, "\tpop ax\n"
                "\tconst bx,1\n"
                "\tcmp bx,ax\n"
                "\tjmpc dx\n"
                "\tconst ax,1\n"
                "\tpush ax\n"
                "\tjmp cx\n");
    dprintf(fd, ":%s\n", tlabel);
    dprintf(fd, "\tconst ax,0\n"
                "\tpush ax\n");
    dprintf(fd, ":%s\n", nlabel);
  }
}
;
%%

void true_from_positive() {
  int n = new_label_number();
  char label1[LABEL_SIZE] = {0};
  create_label(label1, LABEL_SIZE, "jmp%u", n);
  dprintf(fd, "\tpop ax\n"
              "\tconst dx,%s\n", label1);
  dprintf(fd, "\tconst cx,0\n"
              "\tcmp ax,cx\n"
              "\tjmpc dx\n"
              "\tconst ax,1\n"
              ":%s\n", label1);
  n = new_label_number();
  char label2[LABEL_SIZE] = {0};
  create_label(label2, LABEL_SIZE, "jmp%u", n);
  dprintf(fd, "\tpop bx\n"
              "\tconst dx,%s\n", label2);
  dprintf(fd, "\tconst cx,0\n"
              "\tcmp bx,cx\n"
              "\tjmpc dx\n"
              "\tconst bx,1\n"
              ":%s\n", label2);
}

void yyerror(char const *s) {
  fprintf(stderr, "%s\n", s);
}

void fail_with(const char *format, ...) {
  va_list ap;
  va_start(ap, format);
  vfprintf(stderr, format, ap);
  va_end(ap);
  free_symbols();
  exit(EXIT_FAILURE);
}

void free_symbols() {
  while (symbol_table_head() != NULL) {
    free_first_symbol_table_entry();
  }
}

int main(int argc, char **argv) {
  if (argc != 2) {
    fail_with("usage: %s sample.tex", argv[0]);
  }
  yyin = fopen(argv[1], "r");
  if (yyin == NULL) {
    fail_with("Invalid file: %s", argv[1]);
  }
  size_t fnlen = strlen(argv[1]);
  char target[fnlen];
  strcpy(target, argv[1]);
  strcpy(target + fnlen - 3, "asm");
  fd = open(target, O_RDWR | O_CREAT | O_TRUNC, S_IWUSR | S_IRUSR);
  if (fd == -1) {
    perror("open");
    fail_with("couldn't create file: %s", argv[1]);
    exit(EXIT_FAILURE);
  }
  yyparse();
  free_symbols();
  return 0;
}
