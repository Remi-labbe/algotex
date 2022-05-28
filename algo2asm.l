%{
  #include <limits.h>
  #include "status.h"
  #include "algo2asm.tab.h"
  void string_to_int(int *v, const char *s);
%}
%option noyywrap
NUMBER [[:digit:]]+
ID [[:alpha:]]+[[:alnum:]]*
PREF "\\"
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
{PREF}"times"         { return TIMES; }
{PREF}"SET"           { return AFFECT; }
{PREF}"IF"            { return IF; }
{PREF}"FI"            { return FI; }
{PREF}"ELSE"          { return ELSE; }
{PREF}"DOWHILE"       { return DOWHILE; }
{PREF}"OD"            { return OD; }
{PREF}"DO"            { return DO; }
{PREF}"WHILEOD"       { return WHILEOD; }
{PREF}"CALL"          { return CALL; }
{PREF}"RETURN"        { return RETURN; }
{PREF}"begin{algo}"   { return ALGO_B; }
{PREF}"end{algo}"     { return ALGO_E; }
{PREF}"COM{.*}"       { return IGNORE; }
{PREF}"IN{.*}"        { return IGNORE; }
{PREF}"OUT{.*}"       { return IGNORE; }
{PREF}"AUX{.*}"       { return IGNORE; }
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
