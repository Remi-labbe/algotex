%define parse.error verbose
%locations
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

  #define C_RED     "\x1B[31m"
  #define C_RESET   "\x1B[0m"

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

  int yylex(void);
  void yyerror(char const *);
  extern FILE *yyin;
  extern int yylineno;

  static int fd, offset = 0;
  char *target_name = NULL;
  symbol_table_entry *curr_fun = NULL;

  enum reg {
    AX,
    BX,
    CX,
    DX
  };

  /**
  * @function  fail_with
  * @abstract  Terminate the program outputing an error like fprintf.
  * @param     format...   defines the format of the output like printf
  */
  void fail_with(const char *format, ...);

  /**
  * @function  show_error
  * @abstract  show the error and continue reading the file.
  * @param     format...   defines the format of the output like printf
  */
  void show_error(const char *format, ...);

  /**
   * @function true_from_positive
   * @abstract load the value on top of the stack as a boolean
   * @param     r     the register used to store the boolean
   */
  void true_from_positive(enum reg r);

  /**
   * @function load_addr
   * @abstract store the addr of the var or parameter defined in ste in the register r
   * @param     r     the register used to store the addr
   * @param     ste   the symbol table entry of the var or parameter
   */
  void load_addr(enum reg r, symbol_table_entry *ste);
%}
%union {
  int integer;
  char id[64];
  status s;
}
%type<s> func lparams id linst inst call_params param expr
  dofori_b doford_b doforis_b dofords_b
%token ALGO_B ALGO_E
  IF ELSE DOWHILE DOFORI DOFORIS DOFORD DOFORDS DO REPEAT
  FI OD WHILEOD UNTIL
  CALL RETURN
  IGNORE INVALID
  TIMES INCR DECR
  TRUE FALSE AND OR NOT EQ NEQ LTH GTH LEQ GEQ
%token<id> ID
%token<integer> NUMBER
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
  if ($3 >= ERR_TYP || $5 >= ERR_TYP) {
    fail_with("invalid algorithm, exiting...\n");
  }
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
%empty { $$ = STATEMENT; }
| id ',' lparams {
  status s = 0;
  if ((s = $3) >= ERR_TYP || (s = $1) >= ERR_TYP) {
    $$ = s;
  } else {
    $$ = STATEMENT;
  }
}
| id { $$ = $1; }
;

id:
ID {
  if (search_symbol_table($1) != NULL) {
    $$ = ERR_DEC;
    show_error("line %d: duplicated var \"%s\".\n", yylineno,$1);
  } else {
    $$ = STATEMENT;
    symbol_table_entry *ste = new_symbol_table_entry($1);
    ste->add = ++curr_fun->nParams;
    curr_fun->desc[ste->add] = INT_T;
    ste->class = PARAMETER;
    ste->desc[0] = INT_T;
  }
}
;

algo_e:
ALGO_E {
  for(size_t i = 0; i < curr_fun->nParams + curr_fun->nLocalVariables; i++) {
    free_first_symbol_table_entry();
  }
}
;

linst:
  inst {
  if ($1 >= ERR_TYP) {
    $$ = $1;
    switch ($1) {
    case ERR_TYP:
      yyerror("incompatible types.");
      break;
    case ERR_DIV:
      yyerror("division by 0.");
      break;
    case ERR_DEC:
      yyerror("undeclared variable.");
      break;
    default:;
    }
    yyerrok;
  } else {
    $$ = STATEMENT;
  }
}
| error {
  $$ = ERR_SYN;
  yyerrok;
}
| error linst {
  $$ = ERR_SYN;
  yyerrok;
}
| inst linst {
  status s = 0;
  if ((s = $2) >= ERR_TYP || (s = $1) >= ERR_TYP) {
    $$ = s;
    switch (s) {
    case ERR_TYP:
      yyerror("incompatible types.");
      break;
    case ERR_DIV:
      yyerror("division by 0.");
      break;
    case ERR_DEC:
      yyerror("undeclared variable.");
      break;
    default:;
    }
    yyerrok;
  } else {
    $$ = STATEMENT;
  }
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
      load_addr(CX, ste);
      dprintf(fd, "\tstorew ax,cx\n");
    }
  }
}
| INCR '{' ID '}' {
  symbol_table_entry *ste;
  if ((ste = search_symbol_table($3)) == NULL) {
    $$ = ERR_DEC;
  } else {
    $$ = STATEMENT;
    load_addr(CX, ste);
    dprintf(fd, "\tloadw ax,cx\n"
                "\tconst bx,1\n"
                "\tadd ax,bx\n"
                "\tstorew ax,cx\n");
  }
}
| DECR '{' ID '}' {
  symbol_table_entry *ste;
  if ((ste = search_symbol_table($3)) == NULL) {
    $$ = ERR_DEC;
  } else {
    $$ = STATEMENT;
    load_addr(CX, ste);
    dprintf(fd, "\tloadw ax,cx\n"
                "\tconst bx,1\n"
                "\tsub ax,bx\n"
                "\tstorew ax,cx\n");
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
  if ((s = $3) >= ERR_TYP || (s = $6) >= ERR_TYP || (s = $10) >= ERR_TYP) {
    $$ = s;
  } else {
    $$ = STATEMENT;
  }
}
| DOFORI dofori_b linst dofor_e end OD {
  status s = 0;
  if ((s = $2) >= ERR_TYP || (s = $3) >= ERR_TYP) {
    $$ = s;
  } else {
    $$ = STATEMENT;
  }
}
| DOFORIS doforis_b linst dofor_e end OD {
  status s = 0;
  if ((s = $2) >= ERR_TYP || (s = $3) >= ERR_TYP) {
    $$ = s;
  } else {
    $$ = STATEMENT;
  }
}
| DOFORD doford_b linst dofor_e end OD {
  status s = 0;
  if ((s = $2) >= ERR_TYP || (s = $3) >= ERR_TYP) {
    $$ = s;
  } else {
    $$ = STATEMENT;
  }
}
| DOFORDS dofords_b linst dofor_e end OD {
  status s = 0;
  if ((s = $2) >= ERR_TYP || (s = $3) >= ERR_TYP) {
    $$ = s;
  } else {
    $$ = STATEMENT;
  }
}
| DOWHILE dowhile_t '{' expr '}' dowhile_b linst dowhile_e end OD {
  status s = 0;
  if ((s = $4) >= ERR_TYP || (s = $7) >= ERR_TYP) {
    $$ = s;
  } else {
    $$ = STATEMENT;
  }
}
| DO do_b linst WHILEOD '{' expr '}' do_e end {
  status s = 0;
  if ((s = $3) >= ERR_TYP || (s = $6) >= ERR_TYP) {
    $$ = s;
  } else {
    $$ = STATEMENT;
  }
}
| REPEAT repeat_b linst UNTIL '{' expr '}' repeat_e end {
  status s = 0;
  if ((s = $3) >= ERR_TYP || (s = $6) >= ERR_TYP) {
    $$ = s;
  } else {
    $$ = STATEMENT;
  }
}
| RETURN '{' expr '}' {
  if ($3 >= ERR_TYP) {
    $$ = $3;
  } else {
    $$ = STATEMENT;
    --offset;
    dprintf(fd, "\tpop ax\n");
    for (size_t i = 0; i < curr_fun->nLocalVariables; i++) {
      dprintf(fd, "\tpop dx\n");
    }
    dprintf(fd, "\tret\n");
  }
}
| IGNORE {
  $$ = STATEMENT;
}
| INVALID {
  $$ = ERR_SYN;
  fail_with("Instruction not implementable.\n");
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

dofori_b: '{' ID '}' '{' expr '}' '{' expr '}' {
  if ($5 >= ERR_TYP) {
    $$ = $5;
  } else if ($5 != INT) {
    $$ = ERR_TYP;
  } else {
    if (search_symbol_table($2) != NULL) {
      $$ = ERR_DEC;
    } else {
      $$ = STATEMENT;

      push(new_label_number());
      unsigned int n = top();

      // INIT LOOP VAR
      symbol_table_entry *var = new_symbol_table_entry($2);
      var->class = LOCAL_VARIABLE;
      var->add = ++curr_fun->nLocalVariables;
      var->desc[0] = INT_T;
      --offset;

      // SAVE END VAL
      char buf[16] = {0};
      snprintf(buf, sizeof(buf), "%u", n);
      symbol_table_entry *endval = new_symbol_table_entry(buf);
      endval->class = LOCAL_VARIABLE;
      endval->add = ++curr_fun->nLocalVariables;
      endval->desc[0] = INT_T;
      --offset;

      char label_start[LABEL_SIZE] = {0};
      create_label(label_start, LABEL_SIZE, "dofor_s%u", n);
      char label_loop[LABEL_SIZE] = {0};
      create_label(label_loop, LABEL_SIZE, "dofor_l%u", n);
      char label_next[LABEL_SIZE] = {0};
      create_label(label_next, LABEL_SIZE, "dofor_n%u", n);

      dprintf(fd, "\tconst cx,%s\n", label_start);
      dprintf(fd, "\tjmp cx\n"
                  ":%s\n", label_loop);

      // ++
      load_addr(CX, var);
      dprintf(fd, "\tloadw ax,cx\n"
                  "\tconst bx,1\n"
                  "\tadd ax,bx\n"
                  "\tstorew ax,cx\n");
      dprintf(fd, ":%s\n", label_start);
      load_addr(CX, var);
      dprintf(fd, "\tloadw ax,cx\n");
      load_addr(CX, endval);
      dprintf(fd, "\tloadw bx,cx\n");
      dprintf(fd, "\tconst cx,%s\n", label_next);
      dprintf(fd, "\tsless bx,ax\n"
                  "\tjmpc cx\n");
    }
  }
}
;

doforis_b: '{' ID '}' '{' expr '}' '{' expr '}' '{' expr '}' {
  if ($5 >= ERR_TYP) {
    $$ = $5;
  } else if ($5 != INT) {
    $$ = ERR_TYP;
  } else {
    if (search_symbol_table($2) != NULL) {
      $$ = ERR_DEC;
    } else {
      $$ = STATEMENT;

      push(new_label_number());
      unsigned int n = top();

      // INIT LOOP VAR
      symbol_table_entry *var = new_symbol_table_entry($2);
      var->class = LOCAL_VARIABLE;
      var->add = ++curr_fun->nLocalVariables;
      var->desc[0] = INT_T;
      --offset;

      // SAVE END VAL
      char endn[16] = {0};
      snprintf(endn, sizeof(endn), "%ue", n);
      symbol_table_entry *endval = new_symbol_table_entry(endn);
      endval->class = LOCAL_VARIABLE;
      endval->add = ++curr_fun->nLocalVariables;
      endval->desc[0] = INT_T;
      --offset;

      // SAVE STEP VAL
      char stepn[16] = {0};
      snprintf(stepn, sizeof(stepn), "%us", n);
      symbol_table_entry *stepval = new_symbol_table_entry(stepn);
      stepval->class = LOCAL_VARIABLE;
      stepval->add = ++curr_fun->nLocalVariables;
      stepval->desc[0] = INT_T;
      --offset;

      char label_start[LABEL_SIZE] = {0};
      create_label(label_start, LABEL_SIZE, "dofor_s%u", n);
      char label_loop[LABEL_SIZE] = {0};
      create_label(label_loop, LABEL_SIZE, "dofor_l%u", n);
      char label_next[LABEL_SIZE] = {0};
      create_label(label_next, LABEL_SIZE, "dofor_n%u", n);

      dprintf(fd, "\tconst cx,%s\n", label_start);
      dprintf(fd, "\tjmp cx\n"
                  ":%s\n", label_loop);

      // LOOP VAR
      load_addr(CX, var);
      dprintf(fd, "\tloadw ax,cx\n");

      // STEP VAL
      load_addr(BX, stepval);
      dprintf(fd, "\tloadw bx,bx\n");
      dprintf(fd, "\tadd ax,bx\n");
      dprintf(fd, "\tstorew ax,cx\n");
      dprintf(fd, ":%s\n", label_start);
      load_addr(CX, var);
      dprintf(fd, "\tloadw ax,cx\n");
      load_addr(CX, endval);
      dprintf(fd, "\tloadw bx,cx\n");

      // VERIFIY END CONDITION
      dprintf(fd, "\tconst cx,%s\n", label_next);
      dprintf(fd, "\tsless bx,ax\n"
                  "\tjmpc cx\n");
    }
  }
}
;

doford_b: '{' ID '}' '{' expr '}' '{' expr '}' {
  if ($5 >= ERR_TYP) {
    $$ = $5;
  } else if ($5 != INT) {
    $$ = ERR_TYP;
  } else {
    if (search_symbol_table($2) != NULL) {
      $$ = ERR_DEC;
    } else {
      $$ = STATEMENT;

      push(new_label_number());
      unsigned int n = top();

      // INIT LOOP VAR
      symbol_table_entry *var = new_symbol_table_entry($2);
      var->class = LOCAL_VARIABLE;
      var->add = ++curr_fun->nLocalVariables;
      var->desc[0] = INT_T;
      --offset;

      // SAVE END VAL
      char buf[16] = {0};
      snprintf(buf, sizeof(buf), "%u", n);
      symbol_table_entry *endval = new_symbol_table_entry(buf);
      endval->class = LOCAL_VARIABLE;
      endval->add = ++curr_fun->nLocalVariables;
      endval->desc[0] = INT_T;
      --offset;

      char label_start[LABEL_SIZE] = {0};
      create_label(label_start, LABEL_SIZE, "dofor_s%u", n);
      char label_loop[LABEL_SIZE] = {0};
      create_label(label_loop, LABEL_SIZE, "dofor_l%u", n);
      char label_next[LABEL_SIZE] = {0};
      create_label(label_next, LABEL_SIZE, "dofor_n%u", n);

      dprintf(fd, "\tconst cx,%s\n", label_start);
      dprintf(fd, "\tjmp cx\n"
                  ":%s\n", label_loop);

      // ++
      load_addr(CX, var);
      dprintf(fd, "\tloadw ax,cx\n"
                  "\tconst bx,1\n"
                  "\tsub ax,bx\n"
                  "\tstorew ax,cx\n");
      dprintf(fd, ":%s\n", label_start);
      load_addr(CX, var);
      dprintf(fd, "\tloadw ax,cx\n");
      load_addr(CX, endval);
      dprintf(fd, "\tloadw bx,cx\n");
      dprintf(fd, "\tconst cx,%s\n", label_next);
      dprintf(fd, "\tsless bx,ax\n"
                  "\tjmpc cx\n");
    }
  }
}
;

dofords_b: '{' ID '}' '{' expr '}' '{' expr '}' '{' expr '}' {
  if ($5 >= ERR_TYP) {
    $$ = $5;
  } else if ($5 != INT) {
    $$ = ERR_TYP;
  } else {
    if (search_symbol_table($2) != NULL) {
      $$ = ERR_DEC;
    } else {
      $$ = STATEMENT;

      push(new_label_number());
      unsigned int n = top();

      // INIT LOOP VAR
      symbol_table_entry *var = new_symbol_table_entry($2);
      var->class = LOCAL_VARIABLE;
      var->add = ++curr_fun->nLocalVariables;
      var->desc[0] = INT_T;
      --offset;

      // SAVE END VAL
      char endn[16] = {0};
      snprintf(endn, sizeof(endn), "%ue", n);
      symbol_table_entry *endval = new_symbol_table_entry(endn);
      endval->class = LOCAL_VARIABLE;
      endval->add = ++curr_fun->nLocalVariables;
      endval->desc[0] = INT_T;
      --offset;

      // SAVE STEP VAL
      char stepn[16] = {0};
      snprintf(stepn, sizeof(stepn), "%us", n);
      symbol_table_entry *stepval = new_symbol_table_entry(stepn);
      stepval->class = LOCAL_VARIABLE;
      stepval->add = ++curr_fun->nLocalVariables;
      stepval->desc[0] = INT_T;
      --offset;

      char label_start[LABEL_SIZE] = {0};
      create_label(label_start, LABEL_SIZE, "dofor_s%u", n);
      char label_loop[LABEL_SIZE] = {0};
      create_label(label_loop, LABEL_SIZE, "dofor_l%u", n);
      char label_next[LABEL_SIZE] = {0};
      create_label(label_next, LABEL_SIZE, "dofor_n%u", n);

      dprintf(fd, "\tconst cx,%s\n", label_start);
      dprintf(fd, "\tjmp cx\n"
                  ":%s\n", label_loop);

      // LOOP VAR
      load_addr(CX, var);
      dprintf(fd, "\tloadw ax,cx\n");

      // STEP VAL
      load_addr(BX, stepval);
      dprintf(fd, "\tloadw bx,bx\n");
      dprintf(fd, "\tsub ax,bx\n");
      dprintf(fd, "\tstorew ax,cx\n");
      dprintf(fd, ":%s\n", label_start);
      load_addr(CX, var);
      dprintf(fd, "\tloadw ax,cx\n");
      load_addr(CX, endval);
      dprintf(fd, "\tloadw bx,cx\n");

      // VERIFIY END CONDITION
      dprintf(fd, "\tconst cx,%s\n", label_next);
      dprintf(fd, "\tsless bx,ax\n"
                  "\tjmpc cx\n");
    }
  }
}
;

dofor_e: %empty {
  unsigned int n = top();
  char label_loop[LABEL_SIZE] = {0};
  create_label(label_loop, LABEL_SIZE, "dofor_l%u", n);
  char label_next[LABEL_SIZE] = {0};
  create_label(label_next, LABEL_SIZE, "dofor_n%u", n);
  dprintf(fd, "\tconst ax,%s\n", label_loop);
  dprintf(fd, "\tjmp ax\n"
              ":%s\n", label_next);
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

do_b: %empty {
  push(new_label_number());
  unsigned int n = top();
  char label[LABEL_SIZE] = {0};
  create_label(label, LABEL_SIZE, "do_b%u", n);
  dprintf(fd, ":%s\n", label);
}
;

do_e: %empty {
  unsigned int n = top();
  char loop[LABEL_SIZE] = {0};
  create_label(loop, LABEL_SIZE, "do_b%u", n);
  char elabel[LABEL_SIZE] = {0};
  create_label(elabel, LABEL_SIZE, "do_e%u", n);
  --offset;
  dprintf(fd, "\tpop ax\n"
              "\tconst bx,0\n"
              "\tconst cx,%s\n", elabel);
  dprintf(fd, "\tcmp ax,bx\n"
              "\tjmpc cx\n");
  dprintf(fd, "\tconst ax,%s\n", loop);
  dprintf(fd, "\tjmp ax\n");
  dprintf(fd, ":%s\n", elabel);
}
;

repeat_b: %empty {
  push(new_label_number());
  unsigned int n = top();
  char label[LABEL_SIZE] = {0};
  create_label(label, LABEL_SIZE, "repeat_b%u", n);
  dprintf(fd, ":%s\n", label);
}
;

repeat_e: %empty {
  unsigned int n = top();
  char loop[LABEL_SIZE] = {0};
  create_label(loop, LABEL_SIZE, "repeat_b%u", n);
  --offset;
  dprintf(fd, "\tpop ax\n"
              "\tconst bx,0\n"
              "\tconst cx,%s\n", loop);
  dprintf(fd, "\tcmp ax,bx\n"
              "\tjmpc cx\n");
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
  status s = 0;
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
  if (ste == NULL){
    $<s>$ = ERR_DEC;
  } else if (ste->class != FUNCTION) {
    $<s>$ = ERR_TYP;
  } else {
    push(0);
  }
} '}' '{' call_params '}' {
  status s = 0;
  if ((s = $<s>4) >= ERR_TYP || (s = $7) >= ERR_TYP) {
    $$ = s;
  } else {
    symbol_table_entry *ste = search_symbol_table($3);
    size_t n = pop();
    if (ste->nParams != n) {
      $$ = ERR_SYN;
    } else {
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
}
| ID {
  symbol_table_entry *ste = search_symbol_table($1);
  if (ste == NULL) {
    $$ = ERR_DEC;
  } else {
    $$ = INT;
    load_addr(CX, ste);
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
    true_from_positive(AX);
    true_from_positive(BX);
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
    true_from_positive(AX);
    true_from_positive(BX);
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

void load_addr(enum reg r, symbol_table_entry *ste) {
  int delta;
  char r_str[16] = {0};

  switch(r){
  case AX:
    snprintf(r_str, sizeof(r_str), "ax");
    break;
  case BX:
    snprintf(r_str, sizeof(r_str), "bx");
    break;
  case CX:
    snprintf(r_str, sizeof(r_str), "cx");
    break;
  default:
    fail_with("Can't use this register here!");
  }

  switch(ste->class) {
    case PARAMETER:
      delta = 2 * (offset + curr_fun->nLocalVariables + curr_fun->nParams - (ste->add - 1));
      dprintf(fd, "\tcp %s,sp\n", r_str);
      dprintf(fd, "\tconst dx,%d\n", delta);
      dprintf(fd, "\tsub %s,dx\n", r_str);
      break;
    case LOCAL_VARIABLE:
      delta = 2 * (offset + curr_fun->nLocalVariables - (ste->add));
      dprintf(fd, "\tcp %s,sp\n", r_str);
      dprintf(fd, "\tconst dx,%d\n", delta);
      dprintf(fd, "\tsub %s,dx\n", r_str);
      break;
    default:
      fail_with("invalid class on %s\n", ste->name);
  }
}

void true_from_positive(enum reg r) {
  char r_str[16] = {0};
  int n = new_label_number();
  char label[LABEL_SIZE] = {0};

  switch(r){
  case AX:
    snprintf(r_str, sizeof(r_str), "ax");
    break;
  case BX:
    snprintf(r_str, sizeof(r_str), "bx");
    break;
  default:
    fail_with("Can't use this register here!");
  }

  create_label(label, LABEL_SIZE, "jmp%u", n);
  dprintf(fd, "\tpop %s\n", r_str);
  dprintf(fd, "\tconst dx,%s\n", label);
  dprintf(fd, "\tconst cx,0\n"
              "\tcmp %s,cx\n", r_str);
  dprintf(fd, "\tjmpc dx\n"
              "\tconst %s,1\n", r_str);
  dprintf(fd, ":%s\n", label);
}

/**
 * @function  yyerror
 * @abstract  define the format of the error output of bison
 * @param     s     String defining the error;
 */
void yyerror(char const *s) {
  int line = yylloc.first_line;
  int col = yylloc.first_column;
  fprintf(stderr, C_RED "error" C_RESET ":%d:%d\n  %d | %s\n\n", line, col, line, s);
}

/**
 * @function  free_symbols
 * @abstract  Clears the symbol table
 */
void free_symbols() {
  while (symbol_table_head() != NULL) {
    free_first_symbol_table_entry();
  }
}

void fail_with(const char *format, ...) {
  va_list ap;
  va_start(ap, format);
  vfprintf(stderr, format, ap);
  va_end(ap);
  if (target_name != NULL) {
    switch(fork()) {
    case -1:
      fprintf(stderr, "error in fork trying to delete target file.\n");
      break;
    case 0:;
      const char* const argv[] = {"/bin/rm", "-f", target_name, NULL};

      execvp(argv[0], (char * const *)argv);
      fprintf(stderr, "error in fork trying to delete target file.\n");
      break;
    default:;
    }
  }
  free_symbols();
  exit(EXIT_FAILURE);
}

void show_error(const char *format, ...) {
  va_list ap;
  va_start(ap, format);
  vfprintf(stderr, format, ap);
  va_end(ap);
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
  target_name = target;
  yyparse();
  free_symbols();
  return 0;
}
