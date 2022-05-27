/*
  Copyright 2016 Nicolas Bedon
  Copyright 2022 Remi Labbe
  This file is part of CASIPRO.

  CASIPRO is free software: you can redistribute it and/or modify
  it under the terms of the GNU General Public License as published by
  the Free Software Foundation, either version 3 of the License, or
  (at your option) any later version.

  CASIPRO is distributed in the hope that it will be useful,
  but WITHOUT ANY WARRANTY; without even the implied warranty of
  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
  GNU General Public License for more details.

  You should have received a copy of the GNU General Public License
  along with CASIPRO.  If not, see <http://www.gnu.org/licenses/>.
*/

#ifndef _TYPES_H
#define _TYPES_H

#include <stdbool.h>
#include <stdlib.h>
#include <errno.h>

#define MAX_PARAMS 10 // Max # of parameters for functions

typedef enum { VOID_T,
	       INT_T, BOOL_T, STRING_T,
	       INT_T_LVALUE, BOOL_T_LVALUE, STRING_T_LVALUE } symbol_type;
// Addition of the parameter type to handle easily function parameters
typedef enum { GLOBAL_VARIABLE, LOCAL_VARIABLE, PARAMETER, FUNCTION } symbol_class;

#define COMPATIBLE_TYPES(a,b) ( ((a)==(b))			 \
				|| ((a)==INT_T&&(b)==INT_T_LVALUE)	\
				|| ((a)==INT_T_LVALUE&&(b)==INT_T)	\
				|| ((a)==BOOL_T&&(b)==BOOL_T_LVALUE)	\
				|| ((a)==BOOL_T_LVALUE&&(b)==BOOL_T)	\
				|| ((a)==STRING_T&&(b)==STRING_T_LVALUE) \
				|| ((a)==STRING_T_LVALUE&&(b)==STRING_T) )

typedef struct _symbol_table_entry {
  const char *name;
  symbol_class class;
  // Unused for global variables and functions,
  // #of local variable for local variables (and parameters)
  unsigned int add;
  // Number of parameters for functions
  size_t nParams;
  // Number of local variables for function
  // (parameters are excluded from this count)
  size_t nLocalVariables;
  // Variable: type is in desc[0]
  // Function: desc[0] is the return type,
  //           desc[i] the type of the ith parameter
  symbol_type desc[MAX_PARAMS+1];
  struct _symbol_table_entry *next;
} symbol_table_entry;

void fail_with(const char *format, ...);

#endif
