%{
  #include <limits.h>
  #include "status.h"
  #include "algo2asm.tab.h"
  void string_to_int(int *v, const char *s);
  static void update_loc(){
    static int curr_line = 1;
    static int curr_col  = 1;

    yylloc.first_line   = curr_line;
    yylloc.first_column = curr_col;

    char *s;
    for(s = yytext; *s != 0; s++){
      if(*s == '\n'){
        curr_line++;
        curr_col = 1;
      }else{
        curr_col++;
      }
    }

    yylloc.last_line   = curr_line;
    yylloc.last_column = curr_col-1;
  }
  #define YY_USER_ACTION update_loc();
%}
%option noyywrap yylineno
NUMBER [[:digit:]]+
ID [[:alpha:]]+[[:alnum:]]*
%%
"true"                { return TRUE; }
"false"               { return FALSE; }
"!"                   { return NOT; }
"&&"                  { return AND; }
"||"                  { return OR; }
"<"                   { return LTH; }
">"                   { return GTH; }
"<="                  { return LEQ; }
">="                  { return GEQ; }
"=="                  { return EQ; }
"!="                  { return NEQ; }
"\\times"             { return TIMES; }
"\\SET"               { return AFFECT; }
"\\INCR"              { return INCR; }
"\\DECR"              { return DECR; }
"\\IF"                { return IF; }
"\\FI"                { return FI; }
"\\ELSE"              { return ELSE; }
"\\DOWHILE"           { return DOWHILE; }
"\\DOFORI"            { return DOFORI; }
"\\DOFORD"            { return DOFORD; }
"\\DOFORIS"           { return DOFORIS; }
"\\DOFORDS"           { return DOFORDS; }
"\\OD"                { return OD; }
"\\DO"                { return DO; }
"\\WHILEOD"           { return WHILEOD; }
"\\REPEAT"            { return REPEAT; }
"\\UNTIL"             { return UNTIL; }
"\\CALL"              { return CALL; }
"\\RETURN"            { return RETURN; }
"\\begin{algo}"       { return ALGO_B; }
"\\end{algo}"         { return ALGO_E; }
"\\DOFOREACH"         |
"\\DOFOR"             { return INVALID; }
"\\CUT"               |
"\\BREAK"             |
"\\COM{".*"}"         |
"\\ACT{".*"}"         |
"\\LABEL{".*"}"       |
"\\IN{".*"}"          |
"\\OUT{".*"}"         |
"\\AUX{".*"}"         { return IGNORE; }
{NUMBER}              { string_to_int(&yylval.integer, yytext); return NUMBER; }
{ID}                  { strncpy(yylval.id, yytext, 64); return ID; }
[[:blank:]]|\n
.                     { return yytext[0]; }
%%

void string_to_int(int *r, const char *s) {
  char *p;
  long v;
  errno = 0;
  v = strtol(s, &p, 10);
  if ( ( *p != '\0' || ( errno == ERANGE
                     && ( v == LONG_MIN || v == LONG_MAX ) ) )
       || ( v < INT_MIN || v > INT_MAX ) ) {
    fprintf(stderr, "Error converting string to int\n");
    exit(EXIT_FAILURE);
  }
  *r = v;
}
