; Theorems about Typed Lists
;
; Copyright (C) 2018 Kestrel Institute (http://www.kestrel.edu)
;
; License: A 3-clause BSD license. See the LICENSE file distributed with ACL2.
;
; Author: Alessandro Coglio (coglio@kestrel.edu)

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

(in-package "ACL2")

(include-book "centaur/fty/baselists" :dir :system)
(include-book "std/typed-lists/unsigned-byte-listp" :dir :system)
(include-book "std/util/defrule" :dir :system)

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

(defsection theorems-about-nat-lists

  :parents (theorems-about-non-kestrel-books)

  :short "Theorems about lists of natural numbers."

  (defrule cdr-of-nat-list-fix
    (equal (cdr (nat-list-fix x))
           (nat-list-fix (cdr x))))

  (defrule car-of-nat-list-fix-when-consp
    (implies (consp x)
             (equal (car (nat-list-fix x))
                    (nfix (car x)))))

  (defrule car-of-nat-list-fix-iff-consp
    (iff (car (nat-list-fix x))
         (consp x)))

  (defrule rev-of-nat-list-fix
    (equal (rev (nat-list-fix x))
           (nat-list-fix (rev x)))
    :enable nat-list-fix)

  (defrule nat-list-fix-of-list-fix
    (equal (nat-list-fix (list-fix x))
           (nat-list-fix x))
    :enable nat-list-fix))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

(defsection theorems-about-string-lists

  :parents (theorems-about-non-kestrel-books unsigned-byte-listp)

  :short "Theorems about lists of strings."

  (defrule string-listp-of-remove-duplicates-equal
    (implies (string-listp x)
             (string-listp (remove-duplicates-equal x)))))
