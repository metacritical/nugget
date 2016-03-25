;;; SIMPLEX -- Simplex algorithm.
  
#; (import (scheme base)
        (scheme read)
        (scheme write)
        (scheme time))

(define (matrix-rows a) (vector-length a))
(define (matrix-columns a) (vector-length (vector-ref a 0)))
(define (matrix-ref a i j) (vector-ref (vector-ref a i) j))
(define (matrix-set! a i j x) (vector-set! (vector-ref a i) j x))

(define (complain)
  (error #f "This shouldn't happen"))

(define (simplex a m1 m2 m3)
  ;(define *epsilon* 1e-6)
  (define *epsilon* 0.000001)
  (if (not (and (>= m1 0)
                (>= m2 0)
                (>= m3 0)
                (= (matrix-rows a) (+ m1 m2 m3 2))))
      (complain))
  (let* ((m12 (+ m1 m2 1))
         (m (- (matrix-rows a) 2))
         (n (- (matrix-columns a) 1))
         (l1 (make-vector n))
         (l2 (make-vector m))
         (l3 (make-vector m2))
         (nl1 n)
         (iposv (make-vector m))
         (izrov (make-vector n))
         (ip 0)
         (kp 0)
         (bmax 0.0)
         (one? #f)
         (pass2? #t))
    (define (simp1 mm abs?)
      (set! kp (vector-ref l1 0))
      (set! bmax (matrix-ref a mm kp))
      (do ((k 1 (+ k 1))) ((>= k nl1))
        (if (positive?
            (if abs?
                (- (abs (matrix-ref a mm (vector-ref l1 k)))
                   (abs bmax))
                (- (matrix-ref a mm (vector-ref l1 k)) bmax)))
            (begin
             (set! kp (vector-ref l1 k))
             (set! bmax (matrix-ref a mm (vector-ref l1 k)))))))
    (define (simp2)
      (set! ip 0)
      (let ((q1 0.0)
            (flag? #f))
        (do ((i 0 (+ i 1))) ((= i m))
          (if flag?
              (if (< (matrix-ref a (vector-ref l2 i) kp) (- *epsilon*))
                  (begin
                   (let ((q (/ (- (matrix-ref a (vector-ref l2 i) 0))
                               (matrix-ref a (vector-ref l2 i) kp))))
                     (cond
                      ((< q q1)
                       (set! ip (vector-ref l2 i))
                       (set! q1 q))
                      ((= q q1)
                       (let ((qp 0.0)
                             (q0 0.0))
                         (let loop ((k 1))
                           (if (<= k n)
                               (begin
                                (set! qp
                                      (/ (- (matrix-ref a ip k))
                                         (matrix-ref a ip kp)))
                                (set! q0
                                      (/
                                       (-
                                        (matrix-ref a (vector-ref l2 i) k))
                                        (matrix-ref a (vector-ref l2 i) kp)))
                                (if (= q0 qp)
                                    (loop (+ k 1))))))
                         (if (< q0 qp)
                             (set! ip (vector-ref l2 i)))))))))
              (if (< (matrix-ref a (vector-ref l2 i) kp) (- *epsilon*))
                  (begin
                   (set! q1 (/ (- (matrix-ref a (vector-ref l2 i) 0))
                               (matrix-ref a (vector-ref l2 i) kp)))
                   (set! ip (vector-ref l2 i))
                   (set! flag? #t)))))))
    (define (simp3 one?)
      (let ((piv (/ (matrix-ref a ip kp))))
        (do ((ii 0 (+ ii 1))) ((= ii (+ m (if one? 2 1))))
          (if (not (= ii ip))
              (begin
               (matrix-set! a ii kp (* piv (matrix-ref a ii kp)))
               (do ((kk 0 (+ kk 1))) ((= kk (+ n 1)))
                 (if (not (= kk kp))
                     (matrix-set!
                      a ii kk (- (matrix-ref a ii kk)
                                 (* (matrix-ref a ip kk)
                                    (matrix-ref a ii kp)))))))))
        (do ((kk 0 (+ kk 1))) ((= kk (+ n 1)))
          (if (not (= kk kp))
              (matrix-set! a ip kk (* (- piv) (matrix-ref a ip kk)))))
        (matrix-set! a ip kp piv)))
    (do ((k 0 (+ k 1))) ((= k n))
      (vector-set! l1 k (+ k 1))
      (vector-set! izrov k k))
    (do ((i 0 (+ i 1))) ((= i m))
      (if (negative? (matrix-ref a (+ i 1) 0))
          (complain))
      (vector-set! l2 i (+ i 1))
      (vector-set! iposv i (+ n i)))
    (do ((i 0 (+ i 1))) ((= i m2)) (vector-set! l3 i #t))
    (if (positive? (+ m2 m3))
        (begin
         (do ((k 0 (+ k 1))) ((= k (+ n 1)))
           (do ((i (+ m1 1) (+ i 1)) (sum 0.0 (+ sum (matrix-ref a i k))))
               ((> i m) (matrix-set! a (+ m 1) k (- sum)))))
         (let loop ()
           (simp1 (+ m 1) #f)
           (cond
            ((<= bmax *epsilon*)
             (cond ((< (matrix-ref a (+ m 1) 0) (- *epsilon*))
                    (set! pass2? #f))
                   ((<= (matrix-ref a (+ m 1) 0) *epsilon*)
                    (let loop ((ip1 m12))
                      (if (<= ip1 m)
                          (cond ((= (vector-ref iposv (- ip1 1)) (+ ip n -1))
                                 (simp1 ip1 #t)
                                 (cond ((positive? bmax)
                                        (set! ip ip1)
                                        (set! one? #t))
                                       (else
                                        (loop (+ ip1 1)))))
                                (else
                                 (loop (+ ip1 1))))
                          (do ((i (+ m1 1) (+ i 1))) ((>= i m12))
                            (if (vector-ref l3 (- i (+ m1 1)))
                                (do ((k 0 (+ k 1))) ((= k (+ n 1)))
                                  (matrix-set!
                                   a i k (- (matrix-ref a i k)))))))))
                   (else
                    (simp2)
                    (if (zero? ip) (set! pass2? #f) (set! one? #t)))))
            (else (simp2) (if (zero? ip) (set! pass2? #f) (set! one? #t))))
           (if one?
               (begin
                (set! one? #f)
                (simp3 #t)
                (cond
                 ((>= (vector-ref iposv (- ip 1)) (+ n m12 -1))
                  (let loop ((k 0))
                    (cond
                     ((and (< k nl1) (not (= kp (vector-ref l1 k))))
                      (loop (+ k 1)))
                     (else
                      (set! nl1 (- nl1 1))
                      (do ((is k (+ is 1))) ((>= is nl1))
                        (vector-set! l1 is (vector-ref l1 (+ is 1))))
                       (matrix-set!
                        a (+ m 1) kp (+ (matrix-ref a (+ m 1) kp) 1.0))
                       (do ((i 0 (+ i 1))) ((= i (+ m 2)))
                         (matrix-set! a i kp (- (matrix-ref a i kp))))))))
                 ((and (>= (vector-ref iposv (- ip 1)) (+ n m1))
                       (vector-ref l3
                                   (- (vector-ref iposv (- ip 1)) (+ m1 n))))
                  (vector-set! l3 (- (vector-ref iposv (- ip 1)) (+ m1 n)) #f)
                  (matrix-set!
                   a (+ m 1) kp (+ (matrix-ref a (+ m 1) kp) 1.0))
                  (do ((i 0 (+ i 1))) ((= i (+ m 2)))
                    (matrix-set! a i kp (- (matrix-ref a i kp))))))
                (let ((t (vector-ref izrov (- kp 1))))
                  (vector-set! izrov (- kp 1) (vector-ref iposv (- ip 1)))
                  (vector-set! iposv (- ip 1) t))
                 (loop))))))
    (and pass2?
         (let loop ()
           (simp1 0 #f)
           (cond
            ((positive? bmax)
             (simp2)
             (cond ((zero? ip) #t)
                    (else (simp3 #f)
                          (let ((t (vector-ref izrov (- kp 1))))
                            (vector-set! izrov
                                         (- kp 1) (vector-ref iposv (- ip 1)))
                            (vector-set! iposv (- ip 1) t))
                           (loop))))
            (else (list iposv izrov)))))))

(define (test input)
 (simplex (vector (vector 0.0 1.0 1.0 3.0 -0.5)
                  (vector 740.0 -1.0 0.0 -2.0 0.0)
                  (vector 0.0 0.0 -2.0 0.0 7.0)
                  (vector 0.5 0.0 -1.0 1.0 -2.0)
                  (vector 9.0 -1.0 -1.0 -1.0 -1.0)
                  (vector 0.0 0.0 0.0 0.0 0.0))
          2 1 1))

(define (main)
  (let* ((count (read))
         (input1 (read))
         (output (read))
         (s2 (number->string count))
         (s1 "")
         (name "simplex"))
    (run-r7rs-benchmark
     (string-append name ":" s2)
     count
     (lambda () (test (hide count input1)))
     (lambda (result) (equal? result output)))))

;;; The following code is appended to all benchmarks.

;;; Given an integer and an object, returns the object
;;; without making it too easy for compilers to tell
;;; the object will be returned.

(define (hide r x)
  (call-with-values
   (lambda ()
     (values (vector values (lambda (x) x))
             (if (< r 100) 0 1)))
   (lambda (v i)
     ((vector-ref v i) x))))

;;; Given the name of a benchmark,
;;; the number of times it should be executed,
;;; a thunk that runs the benchmark once,
;;; and a unary predicate that is true of the
;;; correct results the thunk may return,
;;; runs the benchmark for the number of specified iterations.

(define (run-r7rs-benchmark name count thunk ok?)

  ;; Rounds to thousandths.
  (define (rounded x)
    (/ (round (* 1000 x)) 1000))

  (display "Running ")
  (display name)
  (newline)
  ;(flush-output-port)
  (let* ((j/s 1 #;(jiffies-per-second))
         (t0 1 #;(current-second))
         (j0 1 #;(current-jiffy)))
    (let loop ((i 0)
               (result (if #f #f)))
      (cond ((< i count)
             (loop (+ i 1) (thunk)))
            ((ok? result)
             (let* ((j1 1 #;(current-jiffy))
                    (t1 1 #;(current-second))
                    (jifs (- j1 j0))
                    (secs (exact->inexact (/ jifs j/s)))
                    (secs2 (rounded (- t1 t0))))
               (display "Elapsed time: ")
               (write secs)
               (display " seconds (")
               (write secs2)
               (display ") for ")
               (display name)
               (newline))
             result)
            (else
             (display "ERROR: returned incorrect result: ")
             (write result)
             (newline)
             result)))))

(main)
