(in-package "TLI")

;;;; Module EXPORTS

;;; Copyright (c) 1999-2000 The ThinLisp Group
;;; Copyright (c) 1995-1997 Gensym Corporation.
;;; All rights reserved.

;;; This file is part of ThinLisp.

;;; ThinLisp is open source; you can redistribute it and/or modify it
;;; under the terms of the ThinLisp License as published by the ThinLisp
;;; Group; either version 1 or (at your option) any later version.

;;; ThinLisp is distributed in the hope that it will be useful, but
;;; WITHOUT ANY WARRANTY; without even the implied warranty of
;;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.

;;; For additional information see <http://www.thinlisp.org/>

;;; Author: Jim Allard
;;; Author: Mike Colena






;;;; Exported Symbols




;;; Some symbols are imported from the underlying Lisp into TL.  The following
;;; circustances require importing:

;;; * translatable symbols generated by the readtable (e.g. quote, lambda),
;;; * self-evaluating symbols (not having T or NIL makes my brain hurt),
;;; * lambda-list keywords (so I can easily expand tl:defun), *features*, and
;;; * Lisp type names.

;;; All symbols generated automatically by the default elements of the readtable
;;; (such as quote) that need to be translated, and all self-evaluating symbols
;;; must be imported from Lisp into TL.  Note that the symbols generated by
;;; backquote need not be imported, since we have implemented our own version of
;;; backquote in tlt/lisp/backquote.lisp.

(defmacro underlying-lisp-symbols-exported-by-tl ()
  ''(quote t nil &optional &rest &key &aux &body &whole &allow-other-keys
     &environment function lambda optimize declare declaration speed safety
     compilation-speed space debug dynamic-extent ignore type special inline
     notinline
     
     *features* *package* in-package

     *terminal-io* *standard-input* *standard-output* *error-output* *query-io*
     *debug-io* *trace-output* *print-case* *print-base* *print-escape*
     *print-pretty* *print-length* *print-circle* *print-level*
     ftype function

     ;; The following are compile-time only, untranslatable lisp operations.
     concatenate trace describe untrace time

     ;; The following are used by the read-eval-print loop.
     * ** *** + ++ +++
     ))

(import
  (underlying-lisp-symbols-exported-by-tl)
  (find-package "TL"))

(export
  (underlying-lisp-symbols-exported-by-tl)
  (find-package "TL"))




;;; All symbols available in TLT defined packages are exported from within this
;;; file.  Package creation is handled in BOOT.

(defmacro intern-in-package (package-name symbol-names)
  `(loop with package = (find-package ,package-name)
	 with name-list = (copy-list ,symbol-names)
	 for name-cons on name-list
	 do
     (setf (car name-cons) (intern (car name-cons) package))
	 finally (return name-list)))

;; Note that the above operation is a macro, since Lucid decided that export
;; wasn't just a function, but also had compile-time-eval semantics.  Thanks for
;; nothing.  -jra 4/4/95




;;; The following macro returns a form which evaluates to a list of strings
;;; naming the symbols not inherited from Lisp that are to be exported from TL.

(defmacro exported-tl-print-names ()
  ''("SPECIAL-FORM-P"
     "MACRO-FUNCTION"
     "DEFMACRO"
     "MACROEXPAND"
     "MACROEXPAND-1"
     "*MACROEXPAND-HOOK*"
     "DESTRUCTURING-BIND"
     "DESTRUCTURING-BIND-STRICT"
     "DESTRUCTURING-BIND-FORGIVING"
     "DEFINE-COMPILER-MACRO"
     "COMPILER-MACRO-FUNCTION"
     "COMPILER-MACROEXPAND"
     "COMPILER-MACROEXPAND-1"

     ;; TL specific extentions for code walking, for performing full
     ;; macroexpansion to all levels, and for translating forms for debugging
     ;; purposes.
     "WALK"
     "MACROEXPAND-ALL"
     "DEBUG-TRANSLATE-FORM"
     "TRANS"
     "ILISP-TRANSLATE-FORM"
     "EVAL-FEATURE"
     "WITH-PACKAGE-SPECIFIC-SYMBOLS"
     "FEATURE-CASE"
     "DEFUN-FOR-MACRO"
     "DEFVAR-FOR-MACRO"
     "DEFPARAMETER-FOR-MACRO"
     "DEF-TRANSLATABLE-LISP-VAR"
     "SPLIT-DECLARATIONS-AND-BODY"
     "VOID"
     "C-COMMENT-FORM"

     "SPLIT-DECLARATIONS-AND-DOCUMENTATION-FROM-STATEMENTS"
     "THINLISP-MAKE-SYMBOL"
     "DEF-SUBSTITUTION-MACRO"
     "DEFUN-SUBSTITUTION-MACRO"
     "DEFMACRO-FOR-CONSTANT"
     "TEMPORARY-PROGN"
     "LAMBDA-LISTS-CONFORM-P"
     "CONGRUENT-LAMBDA-LIST-P"
     "FORMAT-SYMBOL"

     ;; Symbols for defining, compiling, and translating systems.
     "TRANSLATE-SYSTEM"
     "TRANSLATE-MODULE"
     "DECLARE-SYSTEM"
     "COMPILE-SYSTEM"
     "COMPILE-TLT"
     "LOAD-SYSTEM"
     "FIND-SYSTEM"
     "SYSTEM-NICKNAMES"
     "SYSTEM-USED-SYSTEMS"
     "SYSTEM-ALL-USED-SYSTEMS"
     "SYSTEM-MODULES"
     "SYSTEM-ALIAS"
     "NORMALIZE-SYSTEM-NAME"
     "NORMALIZE-MODULE-NAME"

     ;; Symbols for memory allocation and queries.
     "REALLOC-REGION-UP-TO-LIMIT"
     "REGION-BYTES-SIZE"
     "REGION-BYTES-USED"
     "REGION-BYTES-AVAILABLE"

     ;; Foreign functions
     "DEF-TL-FOREIGN-FUNCTION"

     ;; The following symbols are TL extensions to the declarations in Common
     ;; Lisp.
     "MACROS-ONLY"
     "RETURN-TYPE"
     "VARIABLE-DECLARATION"
     "FUNCTIONAL"
     "SIDE-EFFECT-FREE"
     "ALLOW-UNWIND-PROTECT"
     "REQUIRE-LOCAL-EXIT"
     "DLL-EXPORTED-FUNCTION"
     "STATIC-FUNCTION"
     "C-TYPE"
     "POINTER"

     ;; Symbols needed for declarations
     "PROCLAIM"
     "DECLAIM"

     ;; Symbols needed for environments
     "VARIABLE-INFORMATION"
     "FUNCTION-INFORMATION"
     "DECLARATION-INFORMATION"
     "OPTIMIZE-INFORMATION"
     "AUGMENT-ENVIRONMENT"
     "DEFINE-DECLARATION"
     "PARSE-MACRO"
     ;; "ENCLOSE", skipped, no lexical closures in TL.  -jra 4/2/95

     ;; Symbols needed for declarations.  Most are imported from Lisp to simplify
     ;; use expansions of declarations to the native Lisp compiler.
     "OPTIMIZE"
     "DECLARATION"
     "SPEED"
     "SAFETY"
     "COMPILATION-SPEED"
     "SPACE"
     "DEBUG"
     "DYNAMIC-EXTENT"
     "IGNORE"
     "TYPE"
     "SPECIAL"

     ;; Special form symbols
     "BLOCK"
     "CATCH"
     "DECLARE"
     "EVAL-WHEN"
     "FLET"
     "FUNCTION"
     "GO"
     "IF"
     "LABELS"
     "LET"
     "LET*"
     "MACROLET"
     ;; "MULTIPLE-VALUE-CALL" not implemented
     "MULTIPLE-VALUE-BIND"
     "MULTIPLE-VALUE-PROG1"
     "MULTIPLE-VALUE-SETQ"
     "PROGN"
     ;; "PROGV" not implemented
     ;; "QUOTE" used from the Lisp package because of readtable effects
     "RETURN-FROM"
     "SETQ"
     "PSETQ"
     "TAGBODY"
     "THE"
     "THROW"
     "UNWIND-PROTECT"
     ;; "GENERIC-FLET", "GENERIC-LABELS" not implemented
     "SYMBOL-MACROLET"
     ;; "WITH-ADDED-METHODS" not implemented
     "LOCALLY"
     ;; "LOAD-TIME-EVAL" not implemented
     
     "LAMBDA-LIST-KEYWORDS"
     "LAMBDA-PARAMETERS-LIMIT"
     "MULTIPLE-VALUES-LIMIT"
     "DEFUN"
     "SETF"
     "DEFSETF"
     "GET-SETF-METHOD"
     "GET-SETF-EXPANSION"
     "DEFINE-MODIFY-MACRO"
     "DEFINE-SETF-METHOD"

     ;; Formatting and errors
     "ERROR"
     "CERROR"
     "WARN"
     "FORMAT"
     "STRING-UPCASE"
     "STRING-DOWNCASE"
     "NSTRING-UPCASE"
     "NSTRING-DOWNCASE"
     "STRING-CAPITALIZE"
     "NSTRING-CAPITALIZE"

     ;; Needed for eval-when.
     "LOAD"
     "EVAL"
     "COMPILE"

     ;; Needed for case
     "OTHERWISE"

     ;; Symbols imported from Lisp are exported
     "QUOTE"
     "T"
     "NIL"
     "&OPTIONAL"
     "&REST"
     "&KEY"
     "&AUX"
     "&BODY"
     "&WHOLE"
     "&ALLOW-OTHER-KEYWORDS"
     "&ENVIRONMENT"
     "FUNCTION"
     "LAMBDA"
     "*FEATURES*"
     "VALUES"

     "PROG1"
     "PROG2"
     "CASE"
     "RETURN"

     "AND"
     "OR"
     "NOT"
     "EQ"
     "EQL"
     "EQUAL"

     ;; Types
     "DEFTYPE"
     "TYPEP"
     "TYPECASE"
     "SUBTYPEP"
     "SATISFIES"
     "NULL"
     "SYMBOL"
     "SYMBOLP"
     "ATOM"
     "CONS"
     "CONSP"
     "LIST"
     "LISTP"
     "NUMBER"
     "NUMBERP"
     "FIXNUM"
     "FIXNUMP"
     "INTEGER"
     "INTEGERP"
     "BIGNUM"
     "FLOAT"
     "DOUBLE-FLOAT"
     "FLOATP"
     "CHARACTER"
     "STRING-CHAR"			; for CLtL1 compatibility
     "CHARACTERP"
     "SIMPLE-VECTOR"
     "SIMPLE-VECTOR-P"
     "SIMPLE-ARRAY"
     "ARRAY"
     "VECTOR"
     "UNSIGNED-BYTE"
     "STRING"
     "STRINGP"
     "SIMPLE-STRING"
     "SIMPLE-STRING-P"
     "PACKAGE"
     "PACKAGEP"
     "COMPILED-FUNCTION"
     "COMPILED-FUNCTION-P"
     "STREAM"
     "STREAMP"
     "STRING-STREAM"
     "FILE-STREAM"

     ;; CL functions supported in TL.
     "MAKE-SYMBOL"
     "GENSYM"
     "*GENSYM-COUNTER*"
     "CONSTANTP"				; at compile time only

     "WHEN"
     "UNLESS"
     "COND"
     "FUNCALL"
     "FUNCALL-SIMPLE-COMPILED-FUNCTION"
     "FUNCALL-SIMPLE-MULTI-VALUED-COMPILED-FUNCTION"
     "FUNCALL-SIMPLE-FUNCTION-SYMBOL"
     "APPLY"
     "IDENTITY"

     ;; Looping
     "DOTIMES"
     "DOLIST"
     "DO"
     "DO*"

     "LOOP"
     "LOOP-FINISH"
     "DEFINE-LOOP-PATH"
     "DEFINE-LOOP-SEQUENCE-PATH"
     "FOR"
     "IN"
     "ON"
     "WITH"
     "AS"
     "REPEAT"
     "BEING"
     "EACH"
     "NAMED"
     "INITIALLY"
     "FINALLY"
     "NODECLARE"
     "DOING"
     "COLLECT"
     "COLLECTING"
     "APPEND"
     "APPENDING"
     "NCONCING"
     "COUNT"
     "COUNTING"
     "SUM"
     "SUMMING"
     "MAXIMIZE"
     "MINIMIZE"
     "ALWAYS"
     "NEVER"
     "THEREIS"
     "WHILE"
     "UNTIL"
     "FROM"
     "DOWNFROM"
     "UPFROM"
     "BELOW"
     "TO"

     ;; Symbols
     "SET"
     "GET"
     "GETF"
     "GETF-MACRO"
     "SXHASH-STRING"
     "SYMBOL-NAME"
     "SYMBOL-VALUE"
     "SYMBOL-FUNCTION"
     "SYMBOL-PLIST"
     "SYMBOL-PACKAGE"
     "BOUNDP"
     "KEYWORDP"
     "INTERN"
     "FBOUNDP"				; only at macro time

     ;; Packages
     "FIND-PACKAGE"
     "PACKAGE-NAME"
     "PACKAGE-USE-LIST"
     "LIST-ALL-PACKAGES"
     "MAKE-PACKAGE"
     "USE-PACKAGE"

     ;; Managed-floats

     ;; Managed-floats are being turned off for now.  The problem I've not
     ;; solved is how to make code-constants out of them.  -jallard 12/9/97
;     "MANAGED-FLOAT"
;     "MAKE-MANAGED-FLOAT"
;     "MANAGED-FLOAT-VALUE"
;     "MANAGED-FLOAT-NEXT-OBJECT"
;     "MANAGED-FLOAT-P"

     ;; Variables
     "DEFVAR"
     "DEFPARAMETER"
     "DEFCONSTANT"

     ;; Arrays
     "SVREF"
     "LENGTH"
     "FILL-POINTER"
     "ARRAY-DIMENSION"
     "AREF"
     "MAKE-ARRAY"
     "MAKE-STRING"
     "UPGRADED-ARRAY-ELEMENT-TYPE"
     "ARRAY-ELEMENT-TYPE"

     ;; Strings
     "SCHAR"
     "CHAR"
     "CHAR-CODE"
     "CODE-CHAR"
     "INT-CHAR"
     "CHAR-INT"
     "CHAR-NAME"
     "CHAR="
     "CHAR/="
     "CHAR<"
     "CHAR<="
     "CHAR>"
     "CHAR>="
     "DIGIT-CHAR-P"
     "LOWER-CASE-P"
     "UPPER-CASE-P"
     "BOTH-CASE-P"
     "ALPHA-CHAR-P"
     "ALPHANUMERICP"
     "CHAR-UPCASE"
     "CHAR-DOWNCASE"

     "STRING="
     "STRING/="
     "STRING<"
     "STRING<="
     "STRING>"
     "STRING>="
     "REPLACE-STRINGS"
     "REPLACE-SIMPLE-VECTORS"
     "REPLACE-UINT16-ARRAYS"
     "FILL-STRING"
     "SEARCH-STRING"

     ;; Conses
     "MAPCAR"
     "MAKE-LIST"
     "LIST*"
     "COPY-LIST"
     "SUBST"
     "MAPC"
     "LAST"
     "BUTLAST"
     "REVERSE"
     "NREVERSE"
     "PAIRLIS"
     "ASSOC"
     "ASSQ"
     "MEMBER"
     "MEMQ"
     "DELETE"
     "DELQ"
     "NCONC"
     "NRECONC"
     "APPPEND"
     "CAR"
     "CAR-OF-CONS"
     "RPLACA"
     "CDR"
     "CDR-OF-CONS"
     "RPLACD"
     "CAAR"
     "CAAR-OF-CONSES"
     "CADR"
     "CADR-OF-CONSES"
     "CDAR"
     "CDAR-OF-CONSES"
     "CDDR"
     "CDDR-OF-CONSES"
     "CAAAR"
     "CAAAR-OF-CONSES"
     "CAADR"
     "CAADR-OF-CONSES"
     "CADAR"
     "CADAR-OF-CONSES"
     "CADDR"
     "CADDR-OF-CONSES"
     "CDAAR"
     "CDAAR-OF-CONSES"
     "CDADR"
     "CDADR-OF-CONSES"
     "CDDAR"
     "CDDAR-OF-CONSES"
     "CDDDR"
     "CDDDR-OF-CONSES"
     "CAAAAR"
     "CAAAAR-OF-CONSES"
     "CAAADR"
     "CAAADR-OF-CONSES"
     "CAADAR"
     "CAADAR-OF-CONSES"
     "CAADDR"
     "CAADDR-OF-CONSES"
     "CADAAR"
     "CADAAR-OF-CONSES"
     "CADADR"
     "CADADR-OF-CONSES"
     "CADDAR"
     "CADDAR-OF-CONSES"
     "CADDDR"
     "CADDDR-OF-CONSES"
     "CDAAAR"
     "CDAAAR-OF-CONSES"
     "CDAADR"
     "CDAADR-OF-CONSES"
     "CDADAR"
     "CDADAR-OF-CONSES"
     "CDADDR"
     "CDADDR-OF-CONSES"
     "CDDAAR"
     "CDDAAR-OF-CONSES"
     "CDDADR"
     "CDDADR-OF-CONSES"
     "CDDDAR"
     "CDDDAR-OF-CONSES"
     "CDDDDR"
     "CDDDDR-OF-CONSES"
     "FIRST"
     "FIRST-OF-CONSES"
     "FIRST-OF-LONG-ENOUGH-LIST"
     "REST"
     "REST-OF-CONSES"
     "SECOND"
     "SECOND-OF-CONSES"
     "SECOND-OF-LONG-ENOUGH-LIST"
     "THIRD"
     "THIRD-OF-CONSES"
     "THIRD-OF-LONG-ENOUGH-LIST"
     "FOURTH"
     "FOURTH-OF-CONSES"
     "FOURTH-OF-LONG-ENOUGH-LIST"
     "FIFTH"
     "FIFTH-OF-CONSES"
     "FIFTH-OF-LONG-ENOUGH-LIST"
     "SIXTH"
     "SIXTH-OF-CONSES"
     "SIXTH-OF-LONG-ENOUGH-LIST"
     "SEVENTH"
     "SEVENTH-OF-CONSES"
     "SEVENTH-OF-LONG-ENOUGH-LIST"
     "EIGHTH"
     "EIGHTH-OF-CONSES"
     "EIGHTH-OF-LONG-ENOUGH-LIST"
     "NINTH"
     "NINTH-OF-CONSES"
     "NINTH-OF-LONG-ENOUGH-LIST"
     "TENTH"
     "TENTH-OF-CONSES"
     "TENTH-OF-LONG-ENOUGH-LIST"
     "PUSH"
     "PUSHNEW"
     "POP"

     ;; Numbers
     "FAT-AND-SLOW"
     "-" "/"
     "<" ">" "<=" ">="
     "=" "/=" "1+" "1-"
     "INCF" "DECF" "ZEROP"
     "MAX" "MIN" "ASH" 

     "LOGBITP"
     "LOGIOR"
     "LOGXOR"
     "LOGAND"
     "LOGNOT"
     "LOGCOUNT"

     "FLOOR"
     "MOD"

     "MOST-POSITIVE-FIXNUM"
     "MOST-NEGATIVE-FIXNUM"
     
     "=E" ">=E" "<E" "-E" "+E" "<=E" ">E" "/=E" "/E" "*E"
     "FFLOORE-FIRST"
     "FCEILINGE-FIRST"
     "FLOORE-FIRST"
     "ABSE"
     "MINE"
     "MAXE"
     "EXPE"
     "SQRTE"
     "EXPTE"
     "ATANE"
     "FFLOORE"
     "FTRUNCATEE"
     "LOGE"
     "FCEILINGE"
     "1-E" "1+E"
     "FTRUNCATEE-UP"
     "FROUND"
     "FROUNDE"
     "COSE"
     "PLUSPE"
     "MINUSPE"
     "SINE"
     "ATANE"
     "TANE"
     "TAN"
     
     "=F" "1-F" ">F" "*F" "-F" "<=F"
     "MODF"
     "INCFF"
     "DECFF"
     "ASHF"
     "MAXF"
     "MINF"
     "MINUSPF"
     "ABSF"
     "LEFT-SHIFTF"
     "RIGHT-SHIFTF"
     "ROTATEF"
     "SHIFTF"
     "LOGNOTF"
     "TWICEF"
     "TRUNCATEF-FIRST"
     "FTRUNCATEF-FIRST"
     
     ;; Printing
     "MAKE-STRING-OUTPUT-STREAM"
     "GET-OUTPUT-STREAM-STRING"
     "WITH-OUTPUT-TO-STREAM"
     "WITH-OUTPUT-TO-STRING"
     "PRIN1"
     "PRINT"
     "PRINC"
     "WRITE-CHAR"
     "WRITE-CHAR-TO-FILE-STREAM"
     "WRITE-STRING"
     "WRITE-STRING-TO-FILE-STREAM"
     "WRITE-LINE"
     "TERPRI"
     "FRESH-LINE"
     "FORMAT"
;     "*STANDARD-INPUT*"
;     "*STANDARD-OUTPUT*"
;     "*ERROR-OUTPUT*"
;     "*QUERY-IO*"
;     "*DEBUG-IO*"
;     "*TERMINAL-IO*"
;     "*TRACE-OUTPUT*"

     ;; Areas and consing
     "CONSER"
     "CONSING-AREA"
     "PERMANENT"
     "TEMPORARY"
     "EITHER"
     "WITH-PERMANENT-AREA"
     "WITH-TEMPORARY-AREA"
     "EXPAND-DEVELOPMENT-MEMORY"

     ;; System Versions
     "SYSTEM-VERSION"
     "PROTOTYPE-RELEASE-QUALITY"
     "ALPHA-RELEASE-QUALITY"
     "BETA-RELEASE-QUALITY"
     "RELEASE-QUALITY"
     "MAKE-SYSTEM-VERSION"
     "SYSTEM-VERSION-GREATER-P"
     "ALPHA-OR-BETA-OF-SYSTEM-VERSION"
     "SYSTEM-REVISION-GREATER-P"
     "GET-QUALITY-AND-REVISION-OF-SYSTEM-VERSION"
     "BRIEF-DESCRIPTION-OF-SYSTEM-VERSION"
     "WRITE-SYSTEM-VERSION"
     "WRITE-SYSTEM-VERSION-TO-STRING"
     "SET-SYSTEM-VERSION"
     "GET-SYSTEM-MAJOR-VERSION"
     "GET-SYSTEM-MINOR-VERSION"

     ;; Platform and Operating System Identification
     "G2-MACHINE-TYPE"
     "G2-OPERATING-SYSTEM"
     "MACHINE-MODEL"
     "MACHINE-MODEL-VAR"

     ;; Pointers for printing.
     "%POINTER"

     ;; Forward References
     "DECLARE-FORWARD-REFERENCE"
     "DECLARE-FORWARD-REFERENCES"
     "FIND-DEAD-FORWARD-REFERENCES"
     "VARIABLE"

     ;; Sequence predicates
     "SOME"
     "EVERY"
     "NOTANY"
     "NOTEVERY"

     ;; Internal time operations.
     "GET-INTERNAL-REAL-TIME"
     "GET-INTERNAL-RUN-TIME"
     "INTERNAL-TIME-UNITS-PER-SECOND"

     ;; GSI size reduction macros, to be eliminated later.  -jallard 2/12/97
     "DEFVAR-EXCLUDING-GSI"
     "DEFVAR-EXCLUDING-GSI-NO-UTF-G"
     "DEFPARAMETER-EXCLUDING-GSI"
     "DEFPARAMETER-EXCLUDING-NO-MACROS-GSI"
     "DEFVAR-EXCLUDING-NO-MACROS-GSI"
     "DEFCONSTANT-EXCLUDING-GSI"
     "ELIMINATE-FOR-GSI-NO-UTF-G"

     ;; Macro-time and debugging-time only operations which we have decided not
     ;; to translate.
     "GETHASH"
     "FMAKUNBOUND"
     "REMOVE"
     "REMOVE-IF"
     "SUBSTITUTE"
     "TRACE"
     "PPRINT"
     "DESCRIBE"
     "ENCODE-UNIVERSAL-TIME"
     "DECODE-UNIVERSAL-TIME"
     "GET-UNIVERSAL-TIME"
     "ASSERT"
     "DO-SYMBOLS"
     "DO-ALL-SYMBOLS"
     "SPECIAL-VARIABLE-P"
     
     "BUILD-AB-SYMBOL"
     "COUNT-IF"
     "FILL"
     "FILL-LIST"
     "FILL-SIMPLE-VECTOR"
     "FILL-ARRAY-UNSIGNED-BYTE-8"
     "FILL-ARRAY-UNSIGNED-BYTE-16"
     "FILL-ARRAY-DOUBLE-FLOAT"
     "SEARCH"
     "MAKE-HASH-TABLE"
     "SQRT"
     "ABS"
     "ODDP"
     "EVENP"
     "MINUSP"
     "PLUSP"
     "FCEILING"
     "FFLOOR"
     "FTRUNCATE"
     "CEILING"
     "SORT"
     "SORT-LIST"
     "EXP"
     "EXPT"
     "POSITION"
     "POSITION-STRING"
     "POSITION-LIST"
     "POSITION-ARRAY"
     "FIND"
     "NTH"
     "NTHCDR"
     "INTERSECTION"
     "MAPHASH"
     "PRINTING-RANDOM-OBJECT"
     "DEFSTRUCT"
     "DEF-CONCEPT"
     "LOG"
     "LOG-10"
     "FLOORF"
     ">=F"
     "1+F"
     "/=F"
     "NEQ"
     "<F"
     "STRING-EQUAL"
     "ARRAYP"
     "VECTORP"
     "PARSE-INTEGER"
     "READ-CHAR"
     "READ-BYTE-FROM-FILE-STREAM"
     "READ-CHAR-FROM-FILE-STREAM"
     "READ-CHAR-FROM-STRING-STREAM"
     "MAKE-STRING-INPUT-STREAM"
     "CHAR-EQUAL"
     "LDIFF"
     "COPY-TREE"
     "BREAK"
     "+F"
     "SECONDS-FROM-1900-TO-1990"
     "TYPE-OF"
     "FUNCTIONP"
     "SUBSEQ"
     "CONCATENATE"
     "REMOVE-DUPLICATES"
     "SET-DIFFERENCE"
     "ARRAY-RANK"
     "WRITE"
     "COMPILE"
     "DISASSEMBLE"
     "INSPECT"
     "PATHNAME-NAME"
     "READ"
     "PROBE-FILE"
     "DELETE-FILE"
     "TRUNCATE"
     "SLEEP"
     "ARRAY-ELEMENT-TYPE"
     "OUTPUT-RECORDING-GET-OBJECT"
     "ELIMINATE-FOR-NO-MACROS-GSI"
     "ELIMINATE-FOR-GSI"
     "NO-OP-FOR-NO-MACROS-GSI"
     "NO-OP-FOR-GSI"
     "ARRAY-TOTAL-SIZE"
     "DEFUN-FOR-TOP-LEVEL"
     "CURRENT-SYSTEM-BEING-LOADED"
     "ALL-SYSTEMS"
     "INTEGER-LENGTH"
     "ISQRT"
     "DEFUN-SIMPLE"
     "DECLARE-FUNCALLABLE-SYMBOL"
     "DEFUN-ALLOWING-UNWIND"
     "DEFUN-VOID"
     "HALFF"
     "NOTE-FUNCTION-CALL-ACCESSOR-MACRO"
     "GETFQ"
     "AS-ATOMIC-OPERATION"
     "ROUND"
     "ELT"
     "GET-DECODED-TIME"
     "MAKE-PATHNAME"
     "WITH-OPEN-FILE"
     "WITH-OPEN-STREAM"
     "OPEN"
     "CLOSE"
     "DIGIT-CHAR"
     "CURRENT-SYSTEM-CASE"
     "FUNCALL-SYMBOL"
     "DECLARE-SIDE-EFFECT-FREE-FUNCTION"
     "WITH-DYNAMIC-CREATION"
     "WRITE-TO-STRING"
     "KEYWORD-SYMBOL-P"
     "READ-CHAR-NO-HANG"
     "FORCE-OUTPUT"
     "COERCE-FIXNUM-TO-DOUBLE-FLOAT"
     "COERCE-TO-DOUBLE-FLOAT"
     "DEF-FIXNUM-ARITHMETIC-SYSTEM"
     "OPTIMIZE-CONSTANT"
     "COPY-OPTIMIZED-CONSTANT"
     "LOGANDF"
     "ARRAY-HAS-FILL-POINTER-P"
     "MEMBERP"
     "LOGIORF"
     "READ-LINE"
     "READ-LINE-FROM-FILE-STREAM"
     "READ-LINE-FROM-STRING-STREAM"
     "LOGXORF"
     "DECLARE-SIMPLE-FUNCTIONS"
     "DECLARE-SIDE-EFFECT-FREE-FUNCTIONS"
     "NTHCDR-MACRO"
     "SET-LIST-CONTENTS"
     "ENDP"
     "LIST-LENGTH"
     "READ-FROM-STRING"
     "DEFUN-ALLOWING-KEYWORDS"
     "COMPILED-FUNCTION-IN-PLACE"
     "DEFUN-INTO-PLACE"
     "WITH-FASTER-STANDARD-OUTPUT"
     "FUNCALL-COMPILED-FUNCTION"
     "SXHASH"
     "DWARN"
     "SUBLIS"
     "DEF-INLINED-PSEUDO-FUNCTION-WITH-SIDE-EFFECTS"
     "DEF-INLINED-PSEUDO-FUNCTION"
     "SIMPLE-COMPILED-FUNCTION-P"
     "FIND-SYMBOL"
     "DOUBLE-FLOAT-P"
     "DECLARE-FUNCTION-TYPE"
     "BUILD-AB-SYMBOL"
     "TREE-EQUAL"
     "REM"
     "DEFUN-FUNCALLABLE"
     "LISP-PACKAGE-1"
     "KEYWORD-PACKAGE-1"
     "COPY-SEQ"
     "NTH-VALUE"
     "REMOVE-IF"
     "MEMQ-P-MACRO"
     "STABLE-SORT"
     "REMF"
     "DECLARE-SYMBOL-VALUE-PRESERVATION"
     "RANDOM"
     "NOTE-DEFUN-RESUMABLE-ICP-FUNCTION"
     "PLUSPF"
     "SUBSTITUTE-ARGS"
     "SUBSTITITION-FUNCTION-P"
     "ECASE"
     "FUNCTION-CALL-MACRO-P"
     "FUNCTION-CALL-ACCESSOR-MACRO-P"
     "WITH-IGNORED-FORWARD-REFERENCES"
     "DEFUN-SIMPLE"
     "SPLIT-DEFUN-BODY"
     "IF-CHESTNUT"
     "IF-CHESTNUT-GSI"
     "LOGBITPF"
     "ROUNDF"
     "VECTOR"
     "PSETF"
     "CLEAR-INPUT"
     "GETFQ-MACRO"
     "PRETEND-TO-USE-VALUE"
     "CEILINGF"
     "TRUNCATEF"
     "LOGANDC2F"
     "MULTIPLE-VALUE-SETQ-SOME"
     "LOGANDC1"
     "LOGANDC2"
     "EQUALP"
     "READ-BYTE"
     "STRING-TRIM"
     "TRUENAME"
     "PATHNAME"
     "NAMESTRING"
     "RENAME-FILE"
     "MERGE-PATHNAMES"
     "PATHNAMEP"
     "FIXNUM-VECTOR-DISTANCE"
     "ATAN"
     "DEFCONSTANT-FOR-MACRO"
     "COERCE"
     "TYPED-OPERATOR-FOR-TYPE"
     "COUNT"
     "LISP-IMPLEMENTATION-VERSION"
     "LISP-IMPLEMENTATION-TYPE"
     "MULTIPLE-VALUE-LIST"
     "DMESG"
     "ABBREV-OF-INTERNAL-NUMBER"
     "ASSQ-MACRO"
     "REMPROP"
     "UNREAD-CHAR"
     "ASSOC-EQUAL"
     "ASSOC-EQL"
     "TRUE-NON-EMPTY-LIST-P"
     "MEMQ-MACRO"
     "DEFUN-SIMPLE-INTO-PLACE"
     "LOGTEST"
     "DEF-CONCEPT"
     "NSUBST"
     "LOAD"
     "COMPILE-FILE"
     "*LIST-OF-SYMBOLS-FOR-SYMBOL-VALUE*"
     "CEILINGE-FIRST"
     "PIN-IN-RANGEF"
     "SCALE-FLOAT"
     "INLINE-TREE-EQ"
     "DEFUN-VOID-INTO-PLACE"
     "DESTRUCTURING-SETQ"
     "MEMBER-EQUAL"
     "SIN"
     "COS"
     "WRITE-BYTE"
     "REM-FIXNUMS"
     "PROG"
     "PROG*"
     "REVAPPEND"
     "UNION"
     "STRING-GREATERP"
     "FILE-WRITE-DATE"
     "DIRECTORY"
     "MAKE-BROADCAST-STREAMS"
     "WITHIN-MANAGED-OBJECT-SCOPE"
     
     ;; ThinLisp-specific numeric operations.
     "FLOORF-POSITIVE"
     "FLOORF-POSITIVE-2"
     "MODF-POSITIVE"
     "MOD-FIXNUMS"
     "MOD-FLOAT"
     "MOD-FLOAT-POSITIVE"
     "CEILINGF-POSITIVE"

     ;; CLOS required symbols
     "FUNCTION-KEYWORDS"
     "STANDARD-CLASS"
     "BUILT-IN-CLASS"
     "STRUCTURE-CLASS"
     "STRUCTURE"
     "DEFCLASS"
     "STANDARD-OBJECT"
     "UPDATE-INSTANCE-FOR-REDEFINED-CLASS"
     "SHARED-INITIALIZE"
     "SLOT-VALUE"
     "CHANGE-CLASS"
     "DEFMETHOD"
     "DEFGENERIC"
     "CLASS"
     "METHOD"
     "STANDARD-METHOD"
     "METHOD-COMBINATION"
     "GENERIC-FUNCTION,"
     "STANDARD-GENERIC-FUNCTION"
     "FUNCTION-KEYWORDS"
     "ENSURE-GENERIC-FUNCTION"
     "ALLOCATE-INSTANCE"
     "REINITIALIZE-INSTANCE"
     "SHARED-INITIALIZE"
     "UPDATE-INSTANCE-FOR-DIFFERENT-CLASS"
     "UPDATE-INSTANCE-FOR-REDEFINED-CLASS"
     "CHANGE-CLASS"
     "SLOT-BOUNDP"
     "SLOT-EXISTS-P"
     "SLOT-MAKUNBOUND"
     "SLOT-MISSING"
     "SLOT-UNBOUND"
     "SLOT-VALUE"
     "NO-APPLICABLE-METHOD"
     "DETERMINE-EFFECTIVE-METHOD"
     "PRECEDENCE-ORDER-SORT"
     "APPLY-METHOD-COMBINATION"
     "CALL-NEXT-METHOD"
     "NO-NEXT-METHOD"
     "NEXT-METHOD-P"
     ))




;;; The following call actually interns the print names into TL and then exports
;;; those symbols.

(export (intern-in-package
	  "TL"
	  (exported-tl-print-names))
	(find-package "TL"))
