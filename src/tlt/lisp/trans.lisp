(in-package "GLI")

;;;; Module TRANS

;;; Copyright (c) 1995 Gensym Corporation.
;;; All rights reserved.

;;; Jim Allard






;;;; Loading, Compiling, and Translating Systems




;;; This file contains functions for operating on systems: loading, compiling,
;;; and translating.

;;; The function `gl:translate-system' takes a symbol naming a system and
;;; translates it into C code.  First this operation loads any systems used by
;;; this system.  Next, it compiles and loads any files in this system that are
;;; not compiled or loaded up to date.  Next it translates each file where the
;;; translation data file is out of date with the Lisp file, where the C file or
;;; the H file do not exist, or where the translation data is not consistent
;;; with the data currently in the glt data file.  Note that we do not verify
;;; that the file write dates of the C and H files are up to date with their
;;; Lisp file, since translations that produce the exact same C and H files will
;;; not overwrite those files.  However, the translation data file is always
;;; written when attempting a translate of a Lisp file, so comparing that file's
;;; date is adequate.

(defun gl:translate-system
    (system &key (verbose t)
	    (recompile nil) (from nil) (to nil)
	    (compile-used-systems t)
	    (recompile-used-systems nil)
	    (retranslate-used-systems nil)
	    (retranslate nil)
	    (print nil))
  (when from
    (setq from (normalize-module-name from)))
  (when to
    (setq to (normalize-module-name to)))
  (let* ((system-name (if (symbolp system)
			  (normalize-system-name system)
			  (system-name system)))
	 (system-struct (gl:find-system system-name))
	 (used-system-names (system-all-used-systems system-struct)))
    ;; First, compile or load the used systems, then run translations.
    (loop for used-system-name in used-system-names do
      (if (eq used-system-name system-name)
	  (compile-system-1
	    used-system-name :verbose verbose :print print
	    :recompile recompile :from from :to to)
	  (if (or compile-used-systems recompile-used-systems)
	      (compile-system-1
		used-system-name :verbose verbose :print print
		:recompile recompile-used-systems)
	      (load-system-1 used-system-name verbose print nil))))
    ;; Next, bind global environments needed for translation, and translate.
    (let ((*global-c-namespace* (make-c-namespace *reserved-c-namespace*))
	  (*global-symbol-registry* (make-hash-table :test #'eq))
	  (*global-compiled-function-registry* (make-hash-table :test #'eq))
	  (*global-package-registry*
	    (list *gl-package* *gl-user-package* *keyword-package*)))
      (unwind-protect
	   (progn
	     (reserve-foreign-function-identifiers)
	     (loop for used-system-name in used-system-names do
	       (reserve-function-and-global-variable-identifiers
		 used-system-name)
	       (if (eq used-system-name system-name)
		   (translate-system-1
		     used-system-name :verbose verbose :print print
		     :from from :to to
		     :retranslate (or recompile recompile-used-systems
				      retranslate retranslate-used-systems))
		   (translate-system-1
		     used-system-name :verbose verbose :print print
		     :retranslate (or recompile-used-systems
				      retranslate-used-systems)))))
	(clear-c-name-declarations)))))

(defun translate-system-1
    (system &key (verbose t) (print nil) (from nil) (to nil) (retranslate nil))
  (when (symbolp system)
    (setq system (gl:find-system system)))
  (when from
    (setq from (normalize-module-name from)))
  (when to
    (setq to (normalize-module-name to)))
  (when verbose
    (if retranslate
	(if from
	    (format t "~%Retranslating System ~a from ~a"
		    (system-name system) from)
	    (format t "~%Retranslating System ~a" (system-name system)))
	(format t "~%Translating System ~a" (system-name system))))
  (when retranslate
    (with-faster-standard-output 
      (loop for module in (system-modules system)
	    do
	(when (or (null from) (eq from module))
	  (setq from nil)
	  (let ((trans-data (system-trans-data-file system module)))
	    (when (probe-file trans-data)
	      (when verbose
		(format t "~%Deleting ~a" trans-data))
	      (delete-file trans-data))))
	    until (eq module to))))
  (let ((*system-top-level-c-file* nil
;	  (if (system-is-library-p system) (make-top-level-c-file system) nil)
	  ))
    (unwind-protect
	 (progn
	   (pushnew :translator *features*)
	   (pushnew :no-macros *features*)
	   (loop with module-list
		   = (loop for module in (system-modules system)
			   when (system-module-included-p system module)
			     collect module)
		 with total-modules = (length module-list)
		 for module in module-list
		 for module-number from 1
		 for lisp-file = (system-lisp-file system module)
		 for lisp-write-date = (file-write-date lisp-file)
		 do
	     (when (or (null (probe-file (system-c-file system module)))
		       (null (probe-file (system-h-file system module)))
		       (generated-file-out-of-date-p
			 (system-trans-data-file system module) lisp-write-date)
		       (trans-data-indicates-retranslate-p
			 system module verbose))
	       (translate-module
		 system module :verbose verbose :print print
		 :total-modules total-modules :module-number module-number)
	       (gc-a-little))
		 until (eq module to))
	   (dump-makefile-information system))
      (setq *features* (delete :translator *features*))
      (setq *features* (delete :no-macros *features*)))))

(defun generated-file-out-of-date-p (file source-write-date)
  (let ((write-date? (file-write-date file)))
    (or (null write-date?)
	(<= write-date? source-write-date)
	(and user::exports-file-write-date
	     (<= write-date? user::exports-file-write-date)))))





;;; The function `translate-module' takes a system, a module, and an optional
;;; keyword controlling whether or not the translation should be verbose.  This
;;; function will read the Lisp file for this module, translate it into C, and
;;; write out C, H, and GLT files.  If this module is part of a library system,
;;; or part of a submodule (see gl:declare-system for details) then its toplevel
;;; forms and constants will be written out into the existing *top-level-file*
;;; or into a new top-level-file if none exists.  Otherwise, the constants and
;;; top-level function will be written into the C file for this module.

(defun translate-module (system module &key (verbose t) (print nil)
				(module-number 0) (total-modules 0))
  (when verbose
    (format t "~%TRANSLATING ~14a  [~3d/~3d]"
	    module module-number total-modules))
  (let ((*package* *package*)
	(*readtable* *readtable*)
	(*current-system-name* (system-name system))
	(*current-module-name* module)
	(compile-time-too-mode nil)
	(error-seen nil)
	(eof-seen nil)
	(eof-value (gensym)))
    (with-open-c-file (c-file system module)
      (with-open-file (lisp-input (system-lisp-file system module))
	(loop with within-translation-catcher = t
	      until eof-seen
	      do
	  (catch :translation-error
	    (loop for top-level-form = (read lisp-input nil eof-value)
		  until (eq top-level-form eof-value)
		  do
	      (when print
		(format t "~%Translating ~a~%" top-level-form))
	      (let ((current-translation-context top-level-form))
		(translate-top-level-lisp-form top-level-form c-file))
		  finally (setq eof-seen t)))
	  ;; If we get here without having seen an EOF, then there was a
	  ;; translation error, and we must eventually return out of the
	  ;; with-open-c-file in order to guarantee we are aborting this C
	  ;; file's translation.
	  (unless eof-seen
	    (setq error-seen t))))
      (when error-seen
	(return-from translate-module :error)))))

(defun package-used-by-package-p (used-package using-package)
  (loop for subpackage in (package-use-list using-package)
	thereis (or (eq used-package subpackage)
		    (package-used-by-package-p used-package subpackage))))




;;; The function `dump-makefile-information' is used to print out data files
;;; that will be used by the makefile generators.

(defun dump-makefile-information (system)
  (unless (system-is-library-p system)
    (with-open-c-file (c-file system 'main)
      (let* ((main-body (make-c-compound-statement nil nil nil nil))
	     (main-func (make-c-func
			  nil 'int "main" nil
			  '("argc" "argv") '(int (pointer char-pointer))
			  '(nil nil)
			  main-body (c-file-namespace c-file) c-file))
	     (lisp-argv (lexical-c-variable-identifier
			  'lisp-argv main-func 'obj nil))
	     (string-temp (lexical-c-variable-identifier
			    'string-temp main-func 'obj nil))
	     (index-var (lexical-c-variable-identifier
			   'index main-func 'sint32 nil)))
	;; We will eventually want to have some form of tunable initial memory
	;; allocation happen here, probably associated with declarations about
	;; the system or the sum of what is requested for each system..  For
	;; now, get one 64K block for each of the regions.  -jra 5/29/96
	;; Allocate 64K bytes to standard region.
	(emit-expr-to-compound-statement
	  (make-c-function-call-expr
	    (make-c-name-expr "malloc_block_into_region")
	    (list (make-c-literal-expr 0) (make-c-literal-expr 65536)
		  (make-c-literal-expr 1)))
	  main-body)
	;; Allocate 64K bytes to symbol region.
	(emit-expr-to-compound-statement
	  (make-c-function-call-expr
	    (make-c-name-expr "malloc_block_into_region")
	    (list (make-c-literal-expr 1) (make-c-literal-expr 65536)
		  (make-c-literal-expr 1)))
	  main-body)
	;; Allocate 64K bytes to temporary region.
	(emit-expr-to-compound-statement
	  (make-c-function-call-expr
	    (make-c-name-expr "malloc_block_into_region")
	    (list (make-c-literal-expr 2) (make-c-literal-expr 65536)
		  (make-c-literal-expr 1)))
	  main-body)

	;; Initialize All-packages and make the default packages GL, GL-USER,
	;; and Keyword.
	(register-needed-variable-extern
	  c-file '("extern") 'obj "all_packages")
	(emit-expr-to-compound-statement
	  (make-c-infix-expr
	    "all_packages" "="
	    (make-c-cast-expr 'obj (make-c-name-expr "NULL")))
	  main-body)
	(register-needed-function-extern
	  c-file '("extern") 'obj "make_package_1" '((pointer unsigned-char) obj))
	(register-needed-function-extern
	  c-file '("extern") 'obj "init_symbol_into_package" '(obj obj sint32 obj))
	(emit-expr-to-compound-statement
	  (make-c-function-call-expr
	    (make-c-name-expr "make_package_1")
	    (list (translate-l-expr-into-c
		    (prepare-l-expr-for-translation 
		      (make-quoted-constant-l-expr "KEYWORD" nil nil)
		      'string '(pointer unsigned-char))
		    main-func main-body :c-expr)
		  (make-c-cast-expr 'obj (make-c-name-expr "NULL"))))
	  main-body)

	;; Specially handle the symbol T while making the GL package.
	(emit-expr-to-compound-statement
	  (make-c-function-call-expr
	    (make-c-name-expr "init_symbol_into_package")
	    (list
	      (make-c-cast-expr
		'obj (make-c-unary-expr #\& (make-c-name-expr "T")))
	      (translate-string-constant-into-c
		"T" 'obj c-file nil main-func main-body :c-expr)
	      ;; The result of gl:sxhash-string for a one character string is
	      ;; equal to the char-code of the character.  Since
	      ;; gl:sxhash-string isn't defined yet, we'll avoid the forward
	      ;; reference by making use of that fact.  -jallard 12/5/97
	      (make-c-literal-expr
		(char-code #\T))		; (gl:sxhash-string "T")
	      (make-c-function-call-expr
		(make-c-name-expr "make_package_1")
		(list (translate-l-expr-into-c
			(prepare-l-expr-for-translation 
			  (make-quoted-constant-l-expr "GL" nil nil)
			  'string '(pointer unsigned-char))
			main-func main-body :c-expr)
		      (make-c-cast-expr 'obj (make-c-name-expr "NULL"))))))
	  main-body)
        (emit-expr-to-compound-statement
          (make-c-infix-expr
	    (make-c-direct-selection-expr (make-c-name-expr "T") "symbol_value")
	    "=" (make-c-unary-expr #\& (make-c-name-expr "T")))
	  main-body)
	(emit-expr-to-compound-statement
          (make-c-infix-expr
	    (make-c-direct-selection-expr (make-c-name-expr "T") "external")
	    "=" (make-c-literal-expr 1))
	  main-body)

	(emit-expr-to-compound-statement
	  (make-c-function-call-expr
	    (make-c-name-expr "make_package_1")
	    (list (translate-l-expr-into-c
		    (prepare-l-expr-for-translation 
		      (make-quoted-constant-l-expr "GL-USER" nil nil)
		      'string '(pointer unsigned-char))
		    main-func main-body :c-expr)
		  (make-c-function-call-expr
		    (make-c-name-expr "alloc_cons")
		    (list (translate-l-expr-into-c
			    (prepare-l-expr-for-translation 
			      (make-quoted-constant-l-expr "GL" nil nil)
			      't 'obj)
			    main-func main-body :c-expr)
			  (make-c-cast-expr 'obj (make-c-name-expr "NULL"))
			  (make-c-literal-expr
			    (region-number-for-type-and-area
			      'cons (declared-area-name nil 'cons)))))))
	  main-body)

	;; Make the rest of the packages needed for symbol constants.
	(loop for package
		  in (sort (remove
			     *keyword-package*
			     (remove
			       *gl-package*
			       (remove *gl-user-package*
				       *global-package-registry*)))
			   #'package-used-by-package-p)
	      for used-package-c-expr
		  = (loop with accumulating-c-expr
			    = (make-c-cast-expr 'obj (make-c-name-expr "NULL"))
			  for used-package in (reverse (package-use-list package))
			  for used-name = (package-name used-package)
			  do
		      (setq accumulating-c-expr
			    (make-c-function-call-expr
			      (make-c-name-expr "alloc_cons")
			      (list
				(translate-l-expr-into-c
				  (prepare-l-expr-for-translation
				    (make-quoted-constant-l-expr
				      used-name nil nil)
				    't 'obj)
				  main-func main-body :c-expr)
				accumulating-c-expr
				(make-c-literal-expr
				  (region-number-for-type-and-area
				    'cons (declared-area-name nil 'cons))))))
			  finally (return accumulating-c-expr))
	      do
	  (emit-expr-to-compound-statement
	    (make-c-function-call-expr
	      (make-c-name-expr "make_package_1")
	      (list
		(translate-l-expr-into-c
		  (prepare-l-expr-for-translation
		    (make-quoted-constant-l-expr (package-name package) nil nil)
		    'string '(pointer unsigned-char))
		  main-func main-body :c-expr)
		used-package-c-expr))
	    main-body))
					   
	;; Call the top level functions for each module of each used system.
	(emit-top-level-function-calls system c-file main-func main-body "SYMS")
	(emit-top-level-function-calls system c-file main-func main-body "INIT")

	;; Make a Lisp list of the string arguments to this invocation of this
	;; program.
	(emit-initialize-lisp-argv lisp-argv string-temp index-var main-body)

	;; Call the top level function of this system.
	(let* ((system-main (system-main-function system))
	       (c-identifier (c-identifier-for-function
			       system-main *global-c-namespace*
			       (c-func-namespace main-func))))
	  (register-needed-function-extern
	    c-file '("extern") 'void c-identifier (list 'obj))
	  (emit-expr-to-compound-statement
	    (make-c-function-call-expr
	      (make-c-name-expr c-identifier)
	      (list (make-c-name-expr lisp-argv)))
	    main-body))

	;; Issue a default return 0.
	(emit-statement-to-compound-statement
	  (make-c-return-statement (make-c-literal-expr 0))
	  main-body)

	;; Emit the main function to the file.
	(emit-function-to-c-file main-func c-file))))
  ;; Finally, dump a list of C file names for the makefile generator to use.
  (with-open-file (output (system-makefile-info-file system) :direction :output)
    (unless (system-is-library-p system)
      (glt-write-string "main" output)
      (glt-write-char #\newline output))
    (loop for file-name in (system-extra-c-files system)
	  do
      (glt-write-string file-name output)
      (glt-write-char #\newline output))
    (loop for module in (system-modules system)
	  do
      (when (system-module-included-p system module)
	(glt-write-string (module-file-name-string module) output)
	(glt-write-char #\newline output)))))

(defun emit-top-level-function-calls (system c-file main-func main-body prefix)
  (loop for subsystem-name in (system-all-used-systems system)
	for subsystem = (gl:find-system subsystem-name)
	do
    (unless (eq subsystem system)
      (emit-top-level-function-calls subsystem c-file main-func main-body prefix)))
  (loop for module in (system-modules system)
	do
    (when (system-module-included-p system module)
      (let* ((func-name
	       (intern (format nil "~a-~a-~a" prefix (system-name system) module)
		       *gli-package*))
	     (c-identifier
	       (c-identifier-for-function
		 func-name *global-c-namespace*
		 (c-func-namespace main-func))))
	(register-needed-function-extern
	  c-file '("extern") 'void c-identifier nil)
	(emit-expr-to-compound-statement
	  (make-c-function-call-expr (make-c-name-expr c-identifier) nil)
	  main-body)))))

(defun emit-initialize-lisp-argv (lisp-argv string-temp index main-body)
  (let ((loop-body (make-c-compound-statement nil nil nil nil)))
    (emit-expr-to-compound-statement
      (make-c-infix-expr (make-c-name-expr lisp-argv)
			 "=" (make-c-cast-expr 'obj (make-c-name-expr "NULL")))
      main-body)
    (emit-expr-to-compound-statement
      (make-c-infix-expr
	(make-c-name-expr string-temp)
	"=" (make-c-function-call-expr
	      (make-c-name-expr "alloc_string")
	      (list (make-c-function-call-expr
		      (make-c-name-expr "strlen")
		      (list (make-c-subscript-expr
			      (make-c-name-expr "argv")
			      (make-c-name-expr index))))
		    (make-c-literal-expr
		      (region-number-for-type-and-area
			'string
			(declared-area-name nil 'string)))
		    (make-c-literal-expr (c-type-tag 'str)))))
      loop-body)
    (emit-expr-to-compound-statement
      (make-c-function-call-expr
	(make-c-name-expr "strcpy")
	(list (make-c-cast-expr
		'(pointer char)
		(make-c-indirect-selection-expr
		  (make-c-cast-expr
		    '(pointer str) (make-c-name-expr string-temp))
		  "body"))
	      (make-c-subscript-expr
		(make-c-name-expr "argv")
		(make-c-name-expr index))))
      loop-body)
    (emit-expr-to-compound-statement
      (make-c-infix-expr
	(make-c-name-expr lisp-argv)
	"=" (make-c-function-call-expr
	      (make-c-name-expr "alloc_cons")
	      (list
		(make-c-name-expr string-temp)
		(make-c-name-expr lisp-argv)
		(make-c-literal-expr
		  (region-number-for-type-and-area
		    'cons (declared-area-name nil 'cons))))))
      loop-body)
    (emit-statement-to-compound-statement
      (make-c-for-statement
	(make-c-infix-expr
	  (make-c-name-expr index)
	  "=" (make-c-infix-expr
		(make-c-name-expr "argc") "-" (make-c-literal-expr 1)))
	(make-c-infix-expr
	  (make-c-name-expr index) ">=" (make-c-literal-expr 0))
	(make-c-postfix-dec-expr (make-c-name-expr index))
	loop-body)
      main-body)))






;;; The functions `init-newly-opened-c-file' and `close-c-file' are used by
;;; with-open-c-file to initialize and to clean up on exit.  To resolve forward
;;; reference to macro problems, they have been moved here.

(defun init-newly-opened-c-file (c-file)
  (let* ((system (c-file-system c-file))
	 (module (c-file-module c-file))
	 (current-year
	   (sixth (multiple-value-list
		      (decode-universal-time (get-universal-time)))))
	 (file-namespace (make-c-namespace *global-c-namespace*))
	 (symbols-func-namespace (make-c-namespace file-namespace))
	 (symbols-func-name
	   (intern
	     (format nil "SYMS-~a-~a" (system-name system) module)
	     *gli-package*))
	 (symbols-function-c-identifier
	   (c-identifier-for-function
	     symbols-func-name *global-c-namespace* symbols-func-namespace))
	 (init-func-namespace (make-c-namespace file-namespace))
	 (init-func-name
	   (intern
	     (format nil "INIT-~a-~a" (system-name system) module)
	     *gli-package*))
	 (init-function-c-identifier
	   (c-identifier-for-function
	     init-func-name *global-c-namespace* init-func-namespace))
	 (c-temporary-pathname (system-temporary-c-file system module))
	 (c-final-pathname (system-c-file system module))
	 (h-temporary-pathname (system-temporary-h-file system module))
	 (h-final-pathname (system-h-file system module))
	 (glt-final-pathname (system-trans-data-file system module)))
    (setf (c-file-temporary-pathname c-file) c-temporary-pathname)
    (setf (c-file-final-pathname c-file) c-final-pathname)
    (setf (c-file-c-stream c-file)
	  (open c-temporary-pathname :direction :output))
    (unless debugging-translate
      (format (c-file-c-stream c-file)
	      "/*+++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
 +
 + Module:      ~a
 +
 + Copyright (c) ~a Gensym Corporation.  All Rights Reserved.
 +
 + Author(s):   GLT Translator
 +
 + Description: Translation of ~a.
 +
 +++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++*/~%~%"
	      (system-c-file system module)
	      current-year
	      (system-lisp-file system module)))
    ;; Emit includes for extra H files from all used systems, and then the H
    ;; file for this particular module.
    (loop for subsystem-name in (system-all-used-systems system)
	  for subsystem = (gl:find-system subsystem-name)
	  do
      (loop for h-file in (system-extra-h-files subsystem) do
	(format (c-file-c-stream c-file) "#include \"~a.h\"~%" h-file)))
    (format (c-file-c-stream c-file)
	    "#include \"~a\"~%~%"
	    (system-h-file-name system module))
	  
    (setf (c-file-h-file c-file)
	  (make-c-file
	    :c-stream (open h-temporary-pathname :direction :output)
	    :temporary-pathname h-temporary-pathname
	    :final-pathname h-final-pathname))
    (unless debugging-translate
      (format (c-file-c-stream (c-file-h-file c-file))
	      "/*+++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
 +
 + Module:      ~a
 +
 + Copyright (c) ~a Gensym Corporation.  All Rights Reserved.
 +
 + Author(s):   GLT Translator
 +
 + Description: Translated include file for ~a.
 +
 +++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++*/~%~%"
	      (system-h-file system module)
	      current-year
	      (system-lisp-file system module)))
    (setf (c-file-trans-data-final-pathname c-file)
	  glt-final-pathname)
    (setf (c-file-trans-data-stream c-file) nil)
    (setf (c-file-namespace c-file) file-namespace)
    (setf (c-file-defined-functions c-file) (make-hash-table :test #'eq))
    (setf (c-file-defined-variables c-file) (make-hash-table :test #'eq))
    (setf (c-file-used-functions c-file) (make-hash-table :test #'eq))
    (setf (c-file-used-variables c-file) (make-hash-table :test #'eq))
    (setf (c-file-used-constants c-file) (make-hash-table :test #'equal))
    (setf (c-file-used-symbols c-file) (make-hash-table :test #'eq))
    (setf (c-file-used-compiled-functions c-file) (make-hash-table :test #'eq))
    (setf (c-file-needed-function-externs c-file)
	  (make-hash-table :test #'equal))
    (setf (c-file-needed-variable-externs c-file)
	  (make-hash-table :test #'equal))
    (setf (c-file-top-level-function c-file)
	  (make-c-func
	    nil 'void init-function-c-identifier (list init-func-name nil 'void)
	    nil nil nil (make-c-compound-statement nil nil nil nil)
	    init-func-namespace (or *system-top-level-c-file* c-file)))
    (setf (c-file-top-level-compound-statement c-file)
	  (make-c-compound-statement nil nil nil nil))
    (setf (c-file-top-level-symbols-compound-statement c-file)
	  (make-c-compound-statement nil nil nil nil))
    (setf (c-file-top-level-symbols-function c-file)
	  (make-c-func
	    nil 'void symbols-function-c-identifier
	    (list symbols-func-name nil 'void)
	    nil nil nil (c-file-top-level-symbols-compound-statement c-file)
	    symbols-func-namespace (or *system-top-level-c-file* c-file)))
    (setf (c-file-top-level-c-file? c-file)
	  *system-top-level-c-file*)))

(defun close-c-file (c-file &key abort)
  (let ((variable-decls nil)
	(function-decls nil))
    (unless abort
      (loop for last-emitted-symbol-definition = nil then last-definition
	    for last-definition = (c-file-last-symbol-definition? c-file)
	    until (eq last-emitted-symbol-definition last-definition)
	    for symbol-array-name = (cons-car last-definition)
	    do
	(emit-symbol-array-initialization
	  c-file symbol-array-name
	  (loop with reversed-list = nil
		repeat (- (cons-cdr last-definition)
			  (if last-emitted-symbol-definition
			      (cons-cdr last-emitted-symbol-definition)
			      -1))
		for symbol in (c-file-symbols-defined c-file)
		do
	    (push symbol reversed-list)
		finally (return reversed-list))
	  (if last-emitted-symbol-definition
	      (1+ (cons-cdr last-emitted-symbol-definition))
	      0)))
      (when (c-file-symbols-defined c-file)
	(let* ((last-definition (c-file-last-symbol-definition? c-file))
	       (symbol-array-name (cons-car last-definition)))
	  (register-needed-function-extern
	    c-file '("extern") 'obj "init_symbol_into_package"
	    '(obj obj sint32 obj))
	  (emit-declaration-to-c-file
	    (make-c-var-decl
	      nil (list 'array 'sym (1+ (cons-cdr last-definition)))
	      symbol-array-name nil)
	    c-file 0)))
      (when (c-file-compiled-functions-defined c-file)
	(let* ((last-definition (c-file-last-compiled-function-definition?
				  c-file)))
	  (emit-declaration-to-c-file
	    (make-c-var-decl
	      nil (list 'array 'func (1+ (cons-cdr last-definition)))
	      (cons-car last-definition) nil)
	    c-file 0)))

      (when (c-file-top-level-symbols-function c-file)
	(emit-statement-to-compound-statement
	  (make-c-return-statement nil)
	  (c-file-top-level-symbols-compound-statement c-file))
	(emit-function-to-c-file
	  (c-file-top-level-symbols-function c-file)
	  c-file)
	(emit-newline-to-c-file c-file))
      
      (when (c-file-top-level-function c-file)
	;; The top-level-compound-statement has been filled within any
	;; initializations needed by top level forms, defvar initializations, and
	;; quoted constants.  This must be included in the top level function
	;; after the symbol initializations, which were just performed above.
	(let* ((top-level-file? (c-file-top-level-c-file? c-file))
	       (top-level-function (c-file-top-level-function c-file))
	       (top-level-c-body (c-file-top-level-compound-statement c-file))
	       (body-statement (c-func-body-statement top-level-function)))
	  (emit-statement-to-compound-statement
	    top-level-c-body body-statement)
	  (emit-statement-to-compound-statement
	    (make-c-return-statement nil)
	    body-statement)
	  (emit-function-to-c-file
	    top-level-function
	    (or top-level-file? c-file)))
	(emit-newline-to-c-file c-file)))
    (when (c-file-c-stream c-file)
      (close (c-file-c-stream c-file) :abort abort)
      (unless abort
	(let* ((c-path (c-file-final-pathname c-file))
	       (tmp-path (c-file-temporary-pathname c-file)))
	  (if (or (not (probe-file c-path))
		  (not (file-contents-equal c-path tmp-path)))
	      ;; The following assumes that the tmp-path and final-path point to
	      ;; the same directory.  Rename insists on taking its defaults from
	      ;; the first argument, messing the relative pathname we give as the
	      ;; second argument.  So, just pull the name and type out of the
	      ;; target path and make a new pathname containing only those
	      ;; elements.  -jallard 7/23/97
	      (rename-file
		tmp-path
		(make-pathname
		  :name (pathname-name c-path)
		  :type (pathname-type c-path)))
	      (delete-file tmp-path)))))
    (when (c-file-h-file c-file)
      (let ((h-file (c-file-h-file c-file))
	    (last-symbol-defn? (c-file-last-symbol-definition? c-file))
	    (last-func-defn? (c-file-last-compiled-function-definition? c-file)))
	(unless abort
	  (when last-symbol-defn?
	    (emit-declaration-to-c-file
	      (make-c-var-decl
		'("extern") (list 'array 'sym (1+ (cons-cdr last-symbol-defn?)))
		(cons-car last-symbol-defn?) nil)
	      h-file 0))
	  (when last-func-defn?
	    (emit-declaration-to-c-file
	      (make-c-var-decl
		'("extern") (list 'array 'func (1+ (cons-cdr last-func-defn?)))
		(cons-car last-func-defn?) nil)
	      h-file 0))
	  ;; Dontcha love lexical closures?  -jra 11/16/95
	  (maphash #'(lambda (id decl) (push (cons id decl) variable-decls))
		   (c-file-needed-variable-externs c-file))
	  (maphash #'(lambda (id decl) (push (cons id decl) function-decls))
		   (c-file-needed-function-externs c-file))
	  (setq variable-decls (sort variable-decls #'string< :key #'car))
	  (setq function-decls (sort function-decls #'string< :key #'car))
	  (loop for (nil . decl) in variable-decls
		do
	    (emit-declaration-to-c-file decl h-file 0))
	  (emit-newline-to-c-file h-file)
	  (loop for (nil . decl) in function-decls
		do
	    (emit-declaration-to-c-file decl h-file 0)))
	(close-c-file h-file :abort abort)))
    (if (c-file-trans-data-final-pathname c-file)
	(if abort
	    (when (probe-file (c-file-trans-data-final-pathname c-file))
	      (delete-file (c-file-trans-data-final-pathname c-file)))
	    (write-trans-data-file c-file)))
  nil))






;;;; Debugging Translations




;;; The following section implements debugging translations of single forms.

(gl:declare-system (debug :library t :c-dir "/tmp/")
  debug)

(defmacro gl:trans (form &optional (output '*standard-output*))
  `(gl:debug-translate-form ,form ,output))

(defun gl:ilisp-translate-form (form package filename)
  (declare (ignore filename))
  (let ((*package* (find-package package)))
    (gl:trans form)))




;;; The function `debug-translate-form' takes a Lisp form and an optional output
;;; stream.  This function will translate that form to C, then print the output
;;; onto the output stream.

(defun gl:debug-translate-form (lisp-form &optional (output *standard-output*))
  (let ((*global-c-namespace* (make-c-namespace *reserved-c-namespace*))
	(*global-symbol-registry* (make-hash-table :test #'eq))
	(*global-compiled-function-registry* (make-hash-table :test #'eq))
	(*global-package-registry*
	  (list *gl-package* *gl-user-package* *keyword-package*))
	(*system-top-level-c-file* nil)
	(system (gl:find-system 'debug))
	(*package* *package*)
	(*readtable* *readtable*)
	(compile-time-too-mode nil)
	(debugging-translate t))
    (unwind-protect
	 (progn
	   (pushnew :translator *features*)
	   (pushnew :no-macros *features*)
	   (with-open-c-file (c-file system 'debug)
	     (let ((current-translation-context lisp-form)
		   (within-translation-catcher t))
	       (catch :translation-error
		 (translate-top-level-lisp-form lisp-form c-file)))))
      (setq *features* (delete :translator *features*))
      (setq *features* (delete :no-macros *features*)))

    ;; Print the results and remove the files.
    (loop for file in (list (system-c-file system 'debug)
			    (system-h-file system 'debug)
			    (system-trans-data-file system 'debug))
	  do
      (when (file-not-empty-p file)
	(format t "--------------------~%~a~%--------------------~%" file)
	(with-open-file (input file)
	  (loop for line = (read-line input nil :eof)
		until (eq line :eof)
		do
	    (write-line line output)))
	(delete-file file)
	(terpri output)))))

(defun file-not-empty-p (file)
  (with-open-file (input file :if-does-not-exist nil)
    (and input
	 (loop for line = (read-line input nil nil)
	       while line
	       do
	   (when (> (length line) 0)
	     (return t))))))