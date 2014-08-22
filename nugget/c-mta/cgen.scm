;; TODO: switch to the MTA runtime:

;; Compilation routines.

; c-compile-program : exp -> string
(define (c-compile-program exp)
  (let* ((preamble "")
         (append-preamble (lambda (s)
                            (set! preamble (string-append preamble "  " s "\n"))))
         (body (c-compile-exp exp append-preamble)))
    (string-append 
     "int main (int argc, char* argv[]) {\n"
     preamble 
     "  __sum         = MakePrimitive(__prim_sum) ;\n" 
     "  __product     = MakePrimitive(__prim_product) ;\n" 
     "  __difference  = MakePrimitive(__prim_difference) ;\n" 
     "  __halt        = MakePrimitive(__prim_halt) ;\n" 
     "  __display     = MakePrimitive(__prim_display) ;\n" 
     "  __numEqual    = MakePrimitive(__prim_numEqual) ;\n"      
     "  " body " ;\n"
     "  return 0;\n"
     " }\n")))


; c-compile-exp : exp (string -> void) -> string
(define (c-compile-exp exp append-preamble)
  (cond
    ; Core forms:
    ((const? exp)       (c-compile-const exp))
    ((prim?  exp)       (c-compile-prim exp))
    ((ref?   exp)       (c-compile-ref exp))
    ((if? exp)          (c-compile-if exp append-preamble))

    ; IR (1):
    ((cell? exp)        (c-compile-cell exp append-preamble))
    ((cell-get? exp)    (c-compile-cell-get exp append-preamble))
    ((set-cell!? exp)   (c-compile-set-cell! exp append-preamble))
    
    ; IR (2):
    ((closure? exp)     (c-compile-closure exp append-preamble))
    ((env-make? exp)    (c-compile-env-make exp append-preamble))
    ((env-get? exp)     (c-compile-env-get exp append-preamble))
    
    ; Application:      
    ((app? exp)         (c-compile-app exp append-preamble))
    (else               (error "unknown exp in c-compile-exp: " exp))))

; c-compile-const : const-exp -> string
(define (c-compile-const exp)
  (cond
    ((integer? exp) (string-append 
                     "MakeInt(" (number->string exp) ")"))
    ((boolean? exp) (string-append
                     "MakeBoolean(" (if exp "1" "0") ")"))
    (else           (error "unknown constant: " exp))))

; c-compile-prim : prim-exp -> string
(define (c-compile-prim p)
  (cond
    ((eq? '+ p)       "__sum")
    ((eq? '- p)       "__difference")
    ((eq? '* p)       "__product")
    ((eq? '= p)       "__numEqual")
    ((eq? '%halt p)   "__halt")
    ((eq? 'display p) "__display")
    (else             (error "unhandled primitive: " p))))

; c-compile-ref : ref-exp -> string
(define (c-compile-ref exp)
  (mangle exp))
  
; c-compile-args : list[exp] (string -> void) -> string
(define (c-compile-args args append-preamble)
  (if (not (pair? args))
      ""
      (string-append
       (c-compile-exp (car args) append-preamble)
       (if (pair? (cdr args))
           (string-append ", " (c-compile-args (cdr args) append-preamble))
           ""))))

; c-compile-app : app-exp (string -> void) -> string
(define (c-compile-app exp append-preamble)
  (let (($tmp (mangle (gensym 'tmp))))
    
    (append-preamble (string-append
                      "Value " $tmp " ; "))
    
    (let* ((args     (app->args exp))
           (fun      (app->fun exp)))
      (string-append
       "("  $tmp " = " (c-compile-exp fun append-preamble) 
       ","
       $tmp ".clo.lam("
       "MakeEnv(" $tmp ".clo.env)"
       (if (null? args) "" ",")
       (c-compile-args args append-preamble) "))"))))
  
; c-compile-if : if-exp -> string
(define (c-compile-if exp append-preamble)
  (string-append
   "(" (c-compile-exp (if->condition exp) append-preamble) ").b.value ? "
   "(" (c-compile-exp (if->then exp) append-preamble)      ") : "
   "(" (c-compile-exp (if->else exp) append-preamble)      ")"))

; c-compile-set-cell! : set-cell!-exp (string -> void) -> string 
(define (c-compile-set-cell! exp append-preamble)
  (string-append
   "(*"
   "(" (c-compile-exp (set-cell!->cell exp) append-preamble) ".cell.addr)" " = "
   (c-compile-exp (set-cell!->value exp) append-preamble)
   ")"))

; c-compile-cell-get : cell-get-exp (string -> void) -> string 
(define (c-compile-cell-get exp append-preamble)
  (string-append
   "(*("
   (c-compile-exp (cell-get->cell exp) append-preamble)
   ".cell.addr"
   "))"))

; c-compile-cell : cell-exp (string -> void) -> string
(define (c-compile-cell exp append-preamble)
  (string-append
   "NewCell(" (c-compile-exp (cell->value exp) append-preamble) ")"))

; c-compile-env-make : env-make-exp (string -> void) -> string
(define (c-compile-env-make exp append-preamble)
  (string-append
   "MakeEnv(__alloc_env" (number->string (env-make->id exp))
   "(" 
   (c-compile-args (env-make->values exp) append-preamble)
   "))"))

; c-compile-env-get : env-get (string -> void) -> string
(define (c-compile-env-get exp append-preamble)
  (string-append
   "((struct __env_"
   (number->string (env-get->id exp)) "*)" 
   (c-compile-exp (env-get->env exp) append-preamble) ".env.env)->" 
   (mangle (env-get->field exp))))




;; Lambda compilation.

;; Lambdas get compiled into procedures that, 
;; once given a C name, produce a C function
;; definition with that name.

;; These procedures are stored up an eventually 
;; emitted.

; type lambda-id = natural

; num-lambdas : natural
(define num-lambdas 0)

; lambdas : alist[lambda-id,string -> string]
(define lambdas '())

; allocate-lambda : (string -> string) -> lambda-id
(define (allocate-lambda lam)
  (let ((id num-lambdas))
    (set! num-lambdas (+ 1 num-lambdas))
    (set! lambdas (cons (list id lam) lambdas))
    id))

; get-lambda : lambda-id -> (symbol -> string)
(define (get-lambda id)
  (cdr (assv id lambdas)))

; c-compile-closure : closure-exp (string -> void) -> string
(define (c-compile-closure exp append-preamble)
  (let* ((lam (closure->lam exp))
         (env (closure->env exp))
         (lid (allocate-lambda (c-compile-lambda lam))))
    (string-append
     "MakeClosure("
     "__lambda_" (number->string lid)
     ","
     (c-compile-exp env append-preamble)
     ")")))

; c-compile-formals : list[symbol] -> string
(define (c-compile-formals formals)
  (if (not (pair? formals))
      ""
      (string-append
       "Value "
       (mangle (car formals))
       (if (pair? (cdr formals))
           (string-append ", " (c-compile-formals (cdr formals)))
           ""))))

; c-compile-lambda : lamda-exp (string -> void) -> (string -> string)
(define (c-compile-lambda exp)
  (let* ((preamble "")
         (append-preamble (lambda (s)
                            (set! preamble (string-append preamble "  " s "\n")))))
    (let ((formals (c-compile-formals (lambda->formals exp)))
          (body    (c-compile-exp     (car (lambda->exp exp)) append-preamble))) ;; car ==> assume single expr in lambda body after CPS
      (lambda (name)
        (string-append "Value " name "(" formals ") {\n"
                       preamble
                       "  return " body " ;\n"
                       "}\n")))))
  
; c-compile-env-struct : list[symbol] -> string
(define (c-compile-env-struct env)
  (let* ((id     (car env))
         (fields (cdr env))
         (sid    (number->string id))
         (tyname (string-append "struct __env_" sid)))
    (string-append 
     "struct __env_" (number->string id) " {\n" 
     (apply string-append (map (lambda (f)
                                 (string-append
                                  " Value "
                                  (mangle f) 
                                  " ; \n"))
                               fields))
     "} ;\n\n"
     tyname "*" " __alloc_env" sid 
     "(" (c-compile-formals fields) ")" "{\n"
     "  " tyname "*" " t = malloc(sizeof(" tyname "))" ";\n"
     (apply string-append 
            (map (lambda (f)
                   (string-append "  t->" (mangle f) " = " (mangle f) ";\n"))
                 fields))
     "  return t;\n"
     "}\n\n"
     )))
    
(define (c-matt-might:code-gen input-program)
  (define compiled-program "")

  (emit "#include <stdlib.h>")
  (emit "#include <stdio.h>")
  (emit "#include \"c-matt-might/scheme.h\"")
  
  (emit "")
  
  ; Create storage for primitives:
  (emit "
Value __sum ;
Value __difference ;
Value __product ;
Value __halt ;
Value __display ;
Value __numEqual ;
")
  
  (for-each 
   (lambda (env)
     (emit (c-compile-env-struct env)))
   environments)

  (set! compiled-program  (c-compile-program input-program))

  ;; Emit primitive procedures:
  (emit 
   "Value __prim_sum(Value e, Value a, Value b) {
  return MakeInt(a.z.value + b.z.value) ;
}")
  
  (emit 
   "Value __prim_product(Value e, Value a, Value b) {
  return MakeInt(a.z.value * b.z.value) ;
}")
  
  (emit 
   "Value __prim_difference(Value e, Value a, Value b) {
  return MakeInt(a.z.value - b.z.value) ;
}")
  
  (emit
   "Value __prim_halt(Value e, Value v) {
  exit(0);
}")
  
  (emit
   "Value __prim_display(Value e, Value v) {
  printf(\"%i\\n\",v.z.value) ;
  return v ;
}")
  
  (emit
   "Value __prim_numEqual(Value e, Value a, Value b) {
  return MakeBoolean(a.z.value == b.z.value) ;
}")
  
  ;; Emit lambdas:
  ; Print the prototypes:
  (for-each
   (lambda (l)
     (emit (string-append "Value __lambda_" (number->string (car l)) "() ;")))
   lambdas)
  
  (emit "")
  
  ; Print the definitions:
  (for-each
   (lambda (l)
     (emit ((cadr l) (string-append "__lambda_" (number->string (car l))))))
   lambdas)
  
  (emit compiled-program))


