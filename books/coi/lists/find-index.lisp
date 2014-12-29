; Computational Object Inference
; Copyright (C) 2005-2014 Kookamara LLC
;
; Contact:
;
;   Kookamara LLC
;   11410 Windermere Meadows
;   Austin, TX 78759, USA
;   http://www.kookamara.com/
;
; License: (An MIT/X11-style license)
;
;   Permission is hereby granted, free of charge, to any person obtaining a
;   copy of this software and associated documentation files (the "Software"),
;   to deal in the Software without restriction, including without limitation
;   the rights to use, copy, modify, merge, publish, distribute, sublicense,
;   and/or sell copies of the Software, and to permit persons to whom the
;   Software is furnished to do so, subject to the following conditions:
;
;   The above copyright notice and this permission notice shall be included in
;   all copies or substantial portions of the Software.
;
;   THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
;   IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
;   FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
;   AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
;   LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING
;   FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER
;   DEALINGS IN THE SOFTWARE.

(in-package "LIST")

(include-book "nth-and-update-nth")
(include-book "memberp")
(local (include-book "../util/iff"))

;does something like this function exist elsewhere?
(defun find-index (key lst)
  (if (endp lst)
      0
    (if (equal key (car lst))
        0
    (+ 1 (find-index key (cdr lst))))))


(defthm find-index-nth-0
  (equal (find-index (nth 0 x) x)
         0))


;bzo gen the 0 somehow?
(defthm memberp-nth-0-self
  (equal (memberp (nth 0 x) x)
         (consp x))
  :hints (("Goal" :in-theory (enable nth))))

;other way too?
(defthm len-cdr-compare-to-n-minus-one
  (implies (syntaxp (not (quotep n))) ;otherwise, this will match on (< '-1 (LEN (CDR x))).  disgusting.
           (equal (< (+ -1 n) (len (cdr x)))
                  (if (consp x)
                      (< n (len x))
                    (< n 1)))))

;; (thm
;;  (implies (bag::memberp key key-names)
;;           (equal (find-index key (cdr key-names))
;;                  (if (consp (cdr key-names))
;;                      (+ -1 (find-index key key-names))
;;                    0)))
;;  :hints (("Goal" :induct t
;;           :do-not '(generalize eliminate-destructors))))

(defthm find-index-when-not-memberp
  (implies (not (memberp key lst))
           (equal (find-index key lst)
                  (len lst))))


(in-theory (disable find-index))





(defthm memberp-nth
 (implies (< (nfix n) (len lst))
          (memberp (nth n lst) lst))
 :hints (("Goal" :do-not '(generalize eliminate-destructors)
          :in-theory (enable nth ;bag::unique
                             MEMBERP-OF-CDR-CHEAP
                             ))))

(defthm find-index-of-car
  (equal (find-index (car key-names) key-names)
         0)
  :hints (("Goal" :do-not '(generalize eliminate-destructors)
           :in-theory (e/d (find-index nth)
                           (;find-index-of-cdr
                            )))))

(defthm find-index-of-cons-same
  (equal (find-index item (cons item res))
         0)
  :hints (("Goal" :in-theory (e/d (find-index) (;FIND-INDEX-OF-CDR
                                                )))))

(defthm find-index-of-cons-diff
  (implies (not (equal item1 item2))
           (equal (find-index item1 (cons item2 res))
                  (+ 1 (find-index item1 res))))
  :hints (("Goal" :in-theory (e/d (find-index) (;FIND-INDEX-OF-CDR
                                                )))))

(defthm nth-of-find-index-of-car
  (implies (consp lst)
           (equal (nth (find-index (car lst) lst) lst)
                  (car lst)))
  :hints (("Goal" :in-theory (e/d (find-index) (;find-index-of-cdr
                                                      )))))

(defthm find-index-less-than-len
  (equal (< (find-index val lst) (len lst))
         (memberp val lst))
  :hints (("Goal" :in-theory (enable find-index))))

(defthm nth-of-find-index
  (implies (list::memberp val lst)
           (equal (nth (list::find-index val lst) lst)
                  val))
  :hints (("Goal" :in-theory (enable list::find-index))))