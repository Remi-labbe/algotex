#include "stack.h"
#include <stdio.h>

static unsigned int stack[STACK_CAPACITY];
static size_t stack_size = 0;

void push(unsigned int n) {
  if (stack_size < STACK_CAPACITY) {
    stack[stack_size++] = n;
  } else {
    fprintf(stderr, "stack full.");
  }
}

unsigned int top() {
  if (stack_size > 0) {
    return stack[stack_size - 1];
  } else {
    fprintf(stderr, "stack empty.");
    return 0;
  }
}

unsigned int pop() {
  if (stack_size > 0) {
    return stack[--stack_size];
  } else {
    fprintf(stderr, "stack empty.");
    return 0;
  }
}
