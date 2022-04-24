/* Time-stamp: <annexe1.c  19 fév 21 09:47:20> */

/*
  #include <limits.h>
  #include <stdarg.h>
  static unsigned int new_label_number();
  static void create_label(char *buf, size_t buf_size, const char *format, ...);
  void fail_with(const char *format, ...);
 */

// Used for the generation of unique labels
static unsigned int new_label_number() {
  static unsigned int current_label_number = 0u;
  if ( current_label_number == UINT_MAX ) {
    fail_with("Line %d: error: maximum label number reached!\n", yylineno);
  }
  return current_label_number++;
}

/*
 * char buf1[MAXBUF], char buf2[MAXBUF];
 * unsigned ln = new_label_number();
 * create_label(buf1, MAXBUF, "%s:%u:%s", "loop", ln, "begin"); // "loop:10:begin"
 * create_label(buf2, MAXBUF, "%s:%u:%s", "loop", ln, "end");   // "loop:10:end"
*/
static void create_label(char *buf, size_t buf_size, const char *format, ...) {
  va_list ap;
  va_start(ap, format);
  if ( vsnprintf(buf, buf_size, format, ap) >= buf_size ) {
    va_end(ap);
    fail_with("Line %d: error in label generation: size of label exceeds maximum size!\n", yylineno);
  }
  va_end(ap);
}

void fail_with(const char *format, ...) {
  va_list ap;
  va_start(ap, format);
  vfprintf(stderr, format, ap);
  va_end(ap);
  exit(EXIT_FAILURE);
}
