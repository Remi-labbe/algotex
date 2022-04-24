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
  #include "status.h"
  #include "types.h"
  #include "stable.h"
  #include <fcntl.h>
  #include <unistd.h>
  #include <string.h>
  #define COMPATIBLES(a,b) ( \
              (a == INT_T && b == INT) \
              || (a == BOOL_T && b == BOOL) \
              )
  // Stack [[
  void push(unsigned int n);
  unsigned int pop();
  unsigned int top();
  #define STACK_CAPACITY 50
  static int stack[STACK_CAPACITY];
  static size_t stack_size = 0;
  // ]]
  int yylex(void);
  void yyerror(char const *);
  void fail_with(const char *format, ...);
  void print(status s);
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
  static int fd;
  symbol_table_entry *curr_fun = NULL;
%}
%union {
  int integer;
  char id[64];
  char str[512];
  status s;
}
%type<s> expr prog inst block_inst
%token IF FI ELSE DOWHILE OD DO WHILEOD
%token INCR DECR
%token<str> STRING
%token<id> ID
%token<integer> NUMBER
%token TRUE FALSE AND OR NOT EQ NEQ LTH GTH LEQ GEQ
%left AFFECT
%left OR
%left AND
%left EQ NEQ LTH GTH LEQ GEQ
%left '+' '-'
%left '*' '/'
%right UNOT
%right UMINUS
%start prog
%%

prog:
  %empty
| inst prog
;

block_inst:
  %empty
| error block_inst { yyerrok; }
| inst block_inst {
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
      ste->class = GLOBAL_VARIABLE;
      switch($6) {
      case INT:
        ste->desc[0] = INT_T;
        break;
      case BOOL:
        ste->desc[0] = BOOL_T;
        break;
        default:;
      }
      dprintf(fd, "\tconst ax,var:%s\n", $3);
      dprintf(fd, "\tpop bx\n"
                  "\tstorew bx,ax\n");
    } else {
      if (COMPATIBLES (ste->desc[0], $6)) {
        $$ = STATEMENT;
        dprintf(fd, "\tconst ax,var:%s\n", $3);
        dprintf(fd, "\tpop bx\n"
                    "\tstorew bx,ax\n");
      } else {
        $$ = ERR_TYP;
      }
    }
  }
}
| INCR '{' ID '}' {
  symbol_table_entry *ste;
  if ((ste = search_symbol_table($3)) == NULL) {
    $$ = ERR_DEC;
  } else {
    if (ste->desc[0] == INT_T) {
      $$ = INT;
      dprintf(fd, "\tconst bx,var:%s\n", $3);
      dprintf(fd, "\tloadw ax,bx\n"
                  "\tconst cx,1\n"
                  "\tadd ax,cx\n"
                  "\tstorew ax,bx\n");
    } else {
      $$ = ERR_TYP;
    }
  }
}
| DECR '{' ID '}' {
  symbol_table_entry *ste;
  if ((ste = search_symbol_table($3)) == NULL) {
    $$ = ERR_DEC;
  } else {
    if (ste->desc[0] == INT_T) {
      $$ = INT;
      dprintf(fd, "\tconst bx,var:%s\n", $3);
      dprintf(fd, "\tloadw ax,bx\n"
                  "\tconst cx,1\n"
                  "\tsub ax,cx\n"
                  "\tstorew ax,bx\n");
    } else {
      $$ = ERR_TYP;
    }
  }
}
| IF '{' expr '}' if_b block_inst if_e end FI {
  status s = 0;
  if ((s = $3) >= ERR_TYP || (s = $6) >= ERR_TYP) {
    $$ = s;
  } else {
    if ($3 == BOOL) {
      $$ = STATEMENT;
    } else {
      $$ = ERR_TYP;
    }
  }
}
| IF '{' expr '}' if_b block_inst ELSE else_b if_e block_inst else_e end FI {
  status s = 0;
  if ((s = $3) >= ERR_TYP) {
    $$ = s;
  } else {
    if ($3 == BOOL) {
      $$ = STATEMENT;
    } else {
      $$ = ERR_TYP;
    }
  }
}
| DOWHILE  dowhile_t '{' expr '}' dowhile_b block_inst dowhile_e end OD {
  status s = 0;
  if ((s = $4) >= ERR_TYP) {
    $$ = s;
  } else {
    if ($4 == BOOL) {
      $$ = STATEMENT;
    } else {
      $$ = ERR_TYP;
    }
  }
}
;

if_b: %empty {
  push(new_label_number());
  unsigned int n = top();
  char nlabel[LABEL_SIZE] = {0};
  create_label(nlabel, LABEL_SIZE, "if_f%u", n);
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

expr :
ID {
  symbol_table_entry *ste = search_symbol_table($1);
  if (ste == NULL) {
    $$ = ERR_DEC;
  } else {
    switch (ste->desc[0]){
    case INT_T:
      $$ = INT;
      break;
    case BOOL_T:
      $$ = BOOL;
      break;
    default:;
    }
    dprintf(fd, "\tconst bx,var:%s\n", $1);
    dprintf(fd, "\tloadw ax,bx\n"
                "\tpush ax\n");
  }
}
| NUMBER {
  dprintf(fd, "\tconst ax,%d\n", $1);
  dprintf(fd, "\tpush ax\n");
  $$ = INT;
}
| TRUE {
  dprintf(fd, "\tconst ax,1\n"
              "\tpush ax\n");
  $$ = BOOL;
}
| FALSE {
  dprintf(fd, "\tconst ax,0\n"
              "\tpush ax\n");
  $$ = BOOL;
}
| '(' expr ')' {
  $$ = $2;
}
| expr '+' expr {
  status s = 0;
  if ((s = $1) >= ERR_TYP || ( s = $3) >= ERR_TYP) {
    $$ = s;
  } else {
    if ($1 == INT && $3 == INT) {
      $$ = INT;
      dprintf(fd, "\tpop ax\n"
                  "\tpop bx\n"
                  "\tadd ax,bx\n"
                  "\tpush ax\n");
    } else {
      $$ = ERR_TYP;
    }
  }
}
| expr '-' expr {
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
  status s = 0;
  if ((s = $1) >= ERR_TYP || ( s = $3) >= ERR_TYP) {
    $$ = s;
  } else {
    if ($1 == INT && $3 == INT) {
      $$ = INT;
      dprintf(fd, "\tpop ax\n"
                  "\tpop bx\n"
                  "\tmul ax,bx\n"
                  "\tpush ax\n");
    } else {
      $$ = ERR_TYP;
    }
  }
}
| expr '/' expr {
  status s = 0;
  if ((s = $1) >= ERR_TYP || ( s = $3) >= ERR_TYP) {
    $$ = s;
  } else {
    if ($1 == INT && $3 == INT) {
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
    } else {
      $$ = ERR_TYP;
    }
  }
}
| '-' expr %prec UMINUS {
  if ($2 >= ERR_TYP) {
    $$ = $2;
  } else {
    if ( $2 == INT ) {
      $$ = INT;
      dprintf(fd, "\tpop ax\n"
                  "\tconst bx,-1\n"
                  "\tmul ax,bx\n"
                  "\tpush ax\n");
    } else {
      $$ = ERR_TYP;
    }
  }
}
| expr AND expr {
  status s = 0;
  if ((s = $1) >= ERR_TYP || ( s = $3) >= ERR_TYP) {
    $$ = s;
  } else {
    if ($1 == BOOL && $3 == BOOL) {
      $$ = BOOL;
      dprintf(fd, "\tpop ax\n"
                  "\tpop bx\n"
                  "\tand ax,bx\n"
                  "\tpush ax\n");
    } else {
      $$ = ERR_TYP;
    }
  }
}
| expr OR expr {
  status s = 0;
  if ((s = $1) >= ERR_TYP || ( s = $3) >= ERR_TYP) {
    $$ = s;
  } else {
    if ($1 == BOOL && $3 == BOOL) {
      $$ = BOOL;
      dprintf(fd, "\tpop ax\n"
                  "\tpop bx\n"
                  "\tor ax,bx\n"
                  "\tpush ax\n");
    } else {
      $$ = ERR_TYP;
    }
  }
}
| expr EQ expr {
  status s = 0;
  if ((s = $1) >= ERR_TYP || (s = $3) >= ERR_TYP) {
    $$ = s;
  } else {
    if (($1 == BOOL && $3 == BOOL) || ($1 == INT && $3 == INT)) {
      $$ = BOOL;
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
    } else {
      $$ = ERR_TYP;
    }
  }
}
| expr NEQ expr {
  status s = 0;
  if ((s = $1) >= ERR_TYP || (s = $3) >= ERR_TYP) {
    $$ = s;
  } else {
    if (($1 == BOOL && $3 == BOOL) || ($1 == INT && $3 == INT)) {
      $$ = BOOL;
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
    } else {
      $$ = ERR_TYP;
    }
  }
}
| expr LTH expr {
  status s = 0;
  if ((s = $1) >= ERR_TYP || (s = $3) >= ERR_TYP) {
    $$ = s;
  } else {
    if (($1 == BOOL && $3 == BOOL) || ($1 == INT && $3 == INT)) {
      $$ = BOOL;
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
    } else {
      $$ = ERR_TYP;
    }
  }
}
| expr LEQ expr {
  status s = 0;
  if ((s = $1) >= ERR_TYP || (s = $3) >= ERR_TYP) {
    $$ = s;
  } else {
    if (($1 == BOOL && $3 == BOOL) || ($1 == INT && $3 == INT)) {
      $$ = BOOL;
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
    } else {
      $$ = ERR_TYP;
    }
  }
}
| expr GTH expr {
  status s = 0;
  if ((s = $1) >= ERR_TYP || (s = $3) >= ERR_TYP) {
    $$ = s;
  } else {
    if (($1 == BOOL && $3 == BOOL) || ($1 == INT && $3 == INT)) {
      $$ = BOOL;
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
    } else {
      $$ = ERR_TYP;
    }
  }
}
| expr GEQ expr {
  status s = 0;
  if ((s = $1) >= ERR_TYP || (s = $3) >= ERR_TYP) {
    $$ = s;
  } else {
    if (($1 == BOOL && $3 == BOOL) || ($1 == INT && $3 == INT)) {
      $$ = BOOL;
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
    } else {
      $$ = ERR_TYP;
    }
  }
}
| NOT expr %prec UNOT {
  if ($2 >= ERR_TYP) {
    $$ = $2;
  } else {
    if ( $2 == BOOL ) {
      $$ = BOOL;
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
    } else {
      $$ = ERR_TYP;
    }
  }
}
;
%%

void yyerror(char const *s) {
  fprintf(stderr, "%s\n", s);
}

void fail_with(const char *format, ...) {
  va_list ap;
  va_start(ap, format);
  vfprintf(stderr, format, ap);
  va_end(ap);
  exit(EXIT_FAILURE);
}

void print(status s) {
  switch(s) {
    case ERR_DIV:
      yyerror("Division par 0");
      dprintf(fd, "\tconst ax,diverr\n"
                  "\tconst bx,error\n"
                  "\tjmpe bx\n");
      break;
    case ERR_TYP:
      yyerror("Conflit de types");
      dprintf(fd, "\tconst ax,typerr\n"
                  "\tconst bx,error\n"
                  "\tjmpe bx\n");
      break;
    case ERR_DEC:
      yyerror("Erreur variable.");
      dprintf(fd, "\tconst ax,decerr\n"
                  "\tconst bx,error\n"
                  "\tjmpe bx\n");
      break;
    case INT:
      dprintf(fd, "\tcp ax,sp\n"
                  "\tcallprintfd ax\n");
      break;
    case BOOL:;
      int n = new_label_number();
      char tlabel[LABEL_SIZE] = {0};
      create_label(tlabel, LABEL_SIZE, "jmptrue%u", n);
      char nlabel[LABEL_SIZE] = {0};
      create_label(nlabel, LABEL_SIZE, "jmpnext%u", n);
      dprintf(fd, "\tpop ax\n"
                  "\tconst bx,1\n");
      dprintf(fd, "\tconst cx,%s\n", tlabel);
      dprintf(fd, "\tcmp ax,bx\n"
                  "\tjmpc cx\n"
                  "\tconst ax,fout\n"
                  "\tcallprintfs ax\n"
                  "\tconst bx,%s\n", nlabel);
      dprintf(fd, "\tjmp bx\n"
                  ":%s\n", tlabel);
      dprintf(fd, "\tconst ax,tout\n"
                  "\tcallprintfs ax\n");
      dprintf(fd, ":%s\n", nlabel);
      break;
    case STATEMENT:
      break;
    default:
      yyerror("ERROR!");
  }

}

void print_vars() {
  dprintf(fd, "; Vars\n");
  symbol_table_entry *ste;
  for ( ste = symbol_table_head(); ste!=NULL; ste = ste->next){
    dprintf(fd, ":var:%s\n@%s 0\n", ste->name, "int");
  }
}

void free_vars() {
  while (symbol_table_head() != NULL) {
    free_first_symbol_table_entry();
  }
}

void print_header() {
  dprintf(fd,
        "; Calculette\n\n"
        "\tconst ax,debut\n"
        "\tjmp ax\n\n"
        ":diverr\n"
        "@string \"Erreur: division par 0\\n\"\n"
        ":typerr\n"
        "@string \"Erreur: types incompatibles\\n\"\n"
        ":decerr\n"
        "@string \"Erreur: variable redeclaree\\n\"\n"
        ":tout\n"
        "@string \"true\"\n"
        ":fout\n"
        "@string \"false\"\n\n"
        ":error\n"
        "\tcallprintfs ax\n"
        "\tconst ax,end\n"
        "\tjmp ax\n\n"
        ":debut\n"
        "; Préparation de la pile\n"
        "\tconst bp,pile\n"
        "\tconst sp,pile\n"
        "\tconst ax,2\n"
        "\tsub sp,ax\n"
  );
}

void print_footer() {
  dprintf(fd, "; La zone de la pile\n"
              ":pile\n"
              "@int 0\n"
  );
}

int main(int argc, char **argv) {
  if (argc != 2) {
    fail_with("usage: %s [sample.tex]", argv[0]);
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
  print_header();
  yyparse();
  dprintf(fd,
        ":end\n"
        "\tend\n\n"
  );
  print_vars();
  free_vars();
  print_footer();
  return 0;
}

void push(unsigned int n) {
  if (stack_size < STACK_CAPACITY) {
    stack[stack_size++] = n;
  } else {
    yyerror("stack full.");
  }
}

unsigned int top() {
  if (stack_size > 0) {
    return stack[stack_size - 1];
  } else {
    yyerror("stack empty.");
    return 0;
  }
}

unsigned int pop() {
  if (stack_size > 0) {
    return stack[--stack_size];
  } else {
    yyerror("stack empty.");
    return 0;
  }
}
