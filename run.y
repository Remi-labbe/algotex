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
  #include <fcntl.h>
  #include <unistd.h>
  #include <string.h>
  #include "stack.h"
  int yylex(void);
  typedef struct yy_buffer_state * YY_BUFFER_STATE;
  extern YY_BUFFER_STATE yy_scan_string(char * str);
  extern void yy_delete_buffer(YY_BUFFER_STATE buffer);
  void yyerror(char const *s);
  void fail_with(const char *format, ...);
  void print_header(void);
  void print_main(void);
  void print_footer(void);

  #define BUF_SIZE 512
  #define PATTERN "_main.asm"
  #define PATTERN_LEN_ADD strlen(PATTERN)

  extern FILE *yyin;
  static int fd;
%}
%union {
  int integer;
  char id[64];
  status s;
}
%type<s> expr
%type<id> id
%token<integer> NUMBER
%token<id> ID
%token SIPRO TRUE FALSE
%left '/'
%right UMINUS
%start call
%%

call: SIPRO '{' id '}' '{' lparams '}' {
  dprintf(fd, "\tconst ax,%s\n", $3);
  dprintf(fd, "\tcall ax\n");
  dprintf(fd, "\tcallprintfd ax\n");
  size_t n = pop();
  for(size_t i = 0; i < n; ++i) {
    dprintf(fd, "\tpop dx\n");
  }
  dprintf(fd,
        ":end\n"
        "\tend\n\n"
  );
  print_footer();
  printf("Created %s_main.asm\n", $3);
}
;

id: ID {
  char fun_file_name[128] = {0};
  strncpy(fun_file_name, $1, strlen($1) + 1);
  strncpy(fun_file_name + strlen(fun_file_name), ".asm", strlen(".asm") + 1);
  int fun_file = open(fun_file_name, O_RDONLY, S_IRUSR);
  if (fun_file == -1) {
    fail_with("Invalid file: [%s]", fun_file_name);
  }
  size_t fnlen = strlen($1);
  char target[fnlen + PATTERN_LEN_ADD];
  strncpy(target, $1, fnlen);
  strncpy(target + fnlen, PATTERN, strlen(PATTERN) + 1);
  fd = open(target, O_RDWR | O_CREAT | O_TRUNC, S_IWUSR | S_IRUSR);
  if (fd == -1) {
    perror("open");
    fail_with("couldn't create file: %s", target);
    exit(EXIT_FAILURE);
  }
  print_header();
  char buf[BUF_SIZE] = {0};
  ssize_t n;
  while ((n = read(fun_file, buf, BUF_SIZE)) > 0) {
    if (write(fd, buf, n) == -1) {
      fail_with("error writing function.\n");
    }
  }
  dprintf(fd, "\n"
              "; function end\n\n"
              );
  // function result is stored in ax
  print_main();
  push(0);

}

lparams:
%empty
| param
| param ',' lparams
;

param: expr {
  push(pop() + 1);
}
;

expr :
NUMBER {
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
| expr '/' expr {
  /* keep division to handle fractions */
  status s = 0;
  if ((s = $1) >= ERR_TYP || (s = $3) >= ERR_TYP) {
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

void print_header() {
  dprintf(fd,
        "; Jump to main\n"
        "\tconst ax,main\n"
        "\tjmp ax\n\n"
        ":diverr\n"
        "@string \"Erreur: division par 0\\n\"\n"
        ":decerr\n"
        "@string \"Erreur: variable redeclaree\\n\"\n"
        ":error\n"
        "\tcallprintfs ax\n"
        "\tconst ax,end\n"
        "\tjmp ax\n\n"
  );
}

void print_main() {
  dprintf(fd, ":main\n"
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
    fail_with("usage: %s \"\\SIPRO{function_name}{arg1,arg2...}\"", argv[0]);
  }
  YY_BUFFER_STATE buffer = yy_scan_string(argv[1]);
  yyparse();
  yy_delete_buffer(buffer);
  return 0;
}