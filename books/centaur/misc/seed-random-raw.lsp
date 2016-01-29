; Centaur Miscellaneous Books
; Copyright (C) 2008-2011 Centaur Technology
;
; Contact:
;   Centaur Technology Formal Verification Group
;   7600-C N. Capital of Texas Highway, Suite 300, Austin, TX 78731, USA.
;   http://www.centtech.com/
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
;
; Original authors: Sol Swords <sswords@centtech.com>
;                   Jared Davis <jared@centtech.com>

(defparameter *random-seeds* nil)

(defun seed-random$-fn (name freshp)
  (let ((look (assoc-equal name *random-seeds*)))
    (cond (look
           ;;(format t "Restoring *random-state* to ~a.~%" (cdr look))
           (setq *random-state* (make-random-state (cdr look))))
          (freshp
           (let* ((new-st (make-random-state t)))
             ;;(format t "Fresh seed ~a: ~a.~%" name new-st)
             (setq *random-seeds* (acons name new-st *random-seeds*))
             (setq *random-state* (make-random-state new-st))))
          (t
           (let ((new-st (make-random-state nil)))
             ;;(format t "Copy seed to ~a: ~a.~%" name new-st)
             (setq *random-seeds* (acons name new-st *random-seeds*))))))
  nil)
