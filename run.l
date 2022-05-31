%{
  #include <limits.h>
  #include "status.h"
  #include "run.tab.h"
  void string_to_int(int *v, const char *s);
%}
%option noyywrap
NUMBER [[:digit:]]+
ID [[:alpha:]]+[[:alnum:]]*
%%
"true"                { return TRUE; }
"false"               { return FALSE; }
"\\SIPRO"             { return SIPRO; }
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
