;; Cyclone Scheme
;; Copyright (c) 2014, Justin Ethier
;; All rights reserved.
;;
;; This module contains the s-expression parser and supporting functions.
;;

;; TODO: need to modify parse to work with read. that is, read a single object and
;;       return once a scheme object is read, instead of trying to read the next one
;;
;; TODO: kill cyc-read-all and replace with read-all?
;;       at minimum, do not want to call into cyc-read-all from any of the parser code
;;
;; TODO: if this was a module/library, would probably only want to export
;;       read and read-all
;;

;; Helper functions
(define (add-tok tok toks quotes)
  (define (loop i)
    (if (= quotes i)
      tok
      (cons 'quote (cons (loop (+ i 1)) '()))))
  (if quotes
     (cons
       (loop 0)
       toks)
     (cons tok toks)))

;; Get completed list of tokens
(define (get-toks tok toks quotes)
  (if (null? tok)
    toks
    (add-tok (->tok tok) toks quotes)))

;; Add a token to the list, quoting it if necessary
(define (->tok lst)
  (parse-atom (reverse lst)))

;; Did we read a dotted list
(define (dotted? lst) 
  (and (> (length lst) 2)
       (equal? (cadr (reverse lst)) (string->symbol "."))))

;; Convert a list read by the reader into an improper list
(define (->dotted-list lst)
  (cond
    ((null? lst) '())
    ((equal? (car lst) (string->symbol "."))
     (cadr lst))
    (else
      (cons (car lst) (->dotted-list (cdr lst))))))

(define (parse-error msg lnum cnum)
  (error
    (string-append
      "Error (line "
      (number->string lnum)
      ", char "
      (number->string cnum)
      "): "
      msg)))

;; TODO: would be best if these did not have to be global
(define *line-num* 1)
(define *char-num* 0)

;; Main lexer/parser
;(define (cyc-read-all fp)
;  (set! *line-num* 1)
;  (set! *char-num* 0)
;  (_cyc-read-all fp 0))

;; TODO: do we need a concept of a 'read multiple' flag to handle
;; fact that read should only return one object, but reading a list
;; necessitates reading all objects within that list?
(define (read fp)
  (parse fp '() '() #f #f #f 0))

(define (read-all fp)
  (set! *line-num* 1)
  (set! *char-num* 0)
  (define (loop fp result)
    (let ((obj (read fp)))
      (if (eof-object? obj)
        (reverse result)
        (loop fp (cons obj result)))))
  (loop fp '()))


;; Add finished token, if there is one, and continue parsing
(define (parse/tok fp tok toks all? comment? quotes parens)
  (cond
   ((null? tok)
    (parse fp '() toks all? comment? quotes parens))
   (all?
    (parse fp '() 
           (add-tok (->tok tok) toks quotes) 
           all?
           comment? 
           #f  ; read tok, no more quote
           parens))
   (else
     (reverse toks))))

;; Parse input from stream
(define (parse fp tok toks all? comment? quotes parens)
;; TODO: peek-char, if it is start of a comment and we have any toks,
;; need to return those toks (if we are in a read). otherwise can get
;; into a situation where the ; is lost
  (set! *char-num* (+ 1 *char-num*))
  (let ((c (read-char fp)))
;; DEBUGGING
(write `(DEBUG read ,c))
(write (newline))
;; END DEBUG
    (cond
      ((eof-object? c) 
       (if (> parens 0)
           (parse-error "missing closing parenthesis" *line-num* *char-num*))
       (reverse (get-toks tok toks quotes)))
      (comment?
       (if (eq? c #\newline)
           (begin
              (set! *line-num* (+ 1 *line-num*))
              (set! *char-num* 0)
              (if all?
                (parse fp '() toks all? #f quotes parens)
                (reverse toks)))
           (parse fp '() toks all? #t quotes parens)))
      ((char-whitespace? c)
       (if (equal? c #\newline) (set! *line-num* (+ 1 *line-num*)))
       (if (equal? c #\newline) (set! *char-num* 0))
       (parse/tok fp tok toks all? #f quotes parens))
      ((eq? c #\;)
       (parse/tok fp tok toks all? #t quotes parens))
      ((eq? c #\')
       (let ((quote-level (if quotes
                              (+ quotes 1)
                              1)))
         (if (null? tok)
             (parse fp '() toks all? comment? quote-level parens)
;; TODO: is this what we want to do if !all? or do we need to peek
;;       for the quote and return, instead of trying to read a second obj??
             (parse fp '() (add-tok (->tok tok) toks quotes) 
                           all? comment? quote-level parens))))
      ((eq? c #\()
       (let ((sub ;(_cyc-read-all fp (+ parens 1)))
                  (parse fp '() '() #t #f #f (+ parens 1)))
             (toks* (get-toks tok toks quotes)))
         (define new-toks (add-tok 
                            (if (dotted? sub)
                                (->dotted-list sub)
                                sub)
                            toks* 
                            quotes)) 
         (if all?
          (parse fp '() new-toks all? #f #f parens)
          (reverse new-toks))))
      ((eq? c #\))
       (if (= parens 0)
           (parse-error "unexpected closing parenthesis" *line-num* *char-num*))
       (reverse (get-toks tok toks quotes)))
      ((eq? c #\")
       (let ((str (read-str fp '()))
             (toks* (get-toks tok toks quotes)))
         (define new-toks (add-tok str toks* quotes))
         (if all?
          (parse fp '() new-toks all? #f #f parens)
          (reverse new-toks))))
      ((eq? c #\#)
       (if (null? tok)
         ;; # reader
         (let ((next-c (read-char fp)))
            (set! *char-num* (+ 1 *char-num*))
            (cond
              ;; Do not use add-tok below, no need to quote a bool
              ((eq? #\t next-c) (parse fp '() (cons #t toks) all? #f #f parens))
              ((eq? #\f next-c) (parse fp '() (cons #f toks) all? #f #f parens))
              ((eq? #\\ next-c)
               (let ((new-toks (cons (read-pound fp) toks)))
                 (if all?
                   (parse fp '() new-toks all? #f #f parens)
                   (reverse new-toks))))
              (else
                (parse-error "Unhandled input sequence" *line-num* *char-num*))))
         ;; just another char...
         (parse fp (cons c tok) toks all? #f quotes parens)))
      (else
        (parse fp (cons c tok) toks all? #f quotes parens)))))

;(define (_cyc-read-all fp parens)
;   (parse fp '() '() #f #f parens))

;; Read chars past a leading #\
(define (read-pound fp)
  (define (done raw-buf)
    (let ((buf (reverse raw-buf)))
      (cond 
        ((= 0 (length buf))
         (parse-error "missing character" *line-num* *char-num*))
        ((= 1 (length buf))
         (car buf))
        ((equal? buf '(#\a #\l #\a #\r #\m))
         (integer->char 7))
        ((equal? buf '(#\b #\a #\c #\k #\s #\p #\a #\c #\e))
         (integer->char 8))
        ((equal? buf '(#\d #\e #\l #\e #\t #\e))
         (integer->char 127))
        ((equal? buf '(#\e #\s #\c #\a #\p #\e))
         (integer->char 27))
        ((equal? buf '(#\n #\e #\w #\l #\i #\n #\e))
         (integer->char 10))
        ((equal? buf '(#\n #\u #\l #\l))
         (integer->char 0))
        ((equal? buf '(#\r #\e #\t #\u #\r #\n))
         (integer->char 13))
        ((equal? buf '(#\s #\p #\a #\c #\e))
         (integer->char 32))
        ((equal? buf '(#\t #\a #\b))
         (integer->char 9))
        (else
         (parse-error (string-append 
                        "unable to parse character: "
                        (list->string buf))
                      *line-num* *char-num*)))))
  (define (loop buf)
    (let ((c (peek-char fp)))
      (if (or (eof-object? c)
              (char-whitespace? c)
              (and (> (length buf) 0)
                   (equal? c #\))))
         (done buf)
         (loop (cons (read-char fp) buf)))))
  (loop '()))

(define (read-str fp buf)
  (let ((c (read-char fp)))
    ;; TODO: for now, end on raw double-quote. real scheme
    ;; strings are not quite this simple - see spec.
    (cond
      ((eof-object? c)
       (parse-error "missing closing double-quote" *line-num* *char-num*))
      ((equal? #\" c)
       (list->string (reverse buf)))
      (else
        (read-str fp (cons c buf))))))

(define (sign? c)
  (or
    (equal? c #\+)
    (equal? c #\-)))

;; parse-atom -> [chars] -> literal
(define (parse-atom a)
  (cond 
    ((or
        (char-numeric? (car a))
        (and (> (length a) 1)
             (char-numeric? (cadr a))
             (sign? (car a))))
     (string->number  ;; TODO: this is cheating! need to do this, too.
                      ;; but, it could be done by a library function
                      ;; exposed as string->number... so, ok here
       (list->string a)))
    (else
     (string->symbol
       (list->string a)))))

;(let ((fp (open-input-file "tests/begin.scm")))
;(let ((fp (open-input-file "tests/strings.scm")))
(let ((fp (open-input-file "dev.scm")))
  (write (read fp)))
;  (write (cyc-read-all fp)))
;(let ((fp (current-input-port)))
; (write (cyc-read-all fp)))


;(define (display-file filename)
;  (call-with-input-file filename
;    (lambda (port)
;      (let loop ()
;    (let ((thing (read-char port)))
;      (if (not (eof-object? thing))
;          (begin
;        (write-char thing)
;        (loop))))))))
;
