; CUTIL - Centaur Basic Utilities
; Copyright (C) 2008-2011 Centaur Technology
;
; Contact:
;   Centaur Technology Formal Verification Group
;   7600-C N. Capital of Texas Highway, Suite 300, Austin, TX 78731, USA.
;   http://www.centtech.com/
;
; This program is free software; you can redistribute it and/or modify it under
; the terms of the GNU General Public License as published by the Free Software
; Foundation; either version 2 of the License, or (at your option) any later
; version.  This program is distributed in the hope that it will be useful but
; WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or
; FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public License for
; more details.  You should have received a copy of the GNU General Public
; License along with this program; if not, write to the Free Software
; Foundation, Inc., 51 Franklin Street, Suite 500, Boston, MA 02110-1335, USA.
;
; Original author: Jared Davis <jared@centtech.com>
;
; Additional copyright notice:
;
; This file is adapted from Milawa, which is also released under the GPL.

(in-package "STD")
(include-book "da-base")
(include-book "formals")
(include-book "xdoc/fmt-to-str" :dir :system)
(include-book "tools/rulesets" :dir :system)
(include-book "xdoc/names" :dir :system)
(include-book "str/cat" :dir :system)
(set-state-ok t)

(program)

(def-ruleset tag-reasoning nil)

(defxdoc defaggregate
  :parents (std/util)
  :short "Introduce a record structure, like a @('struct') in C."

  :long "<h3>Introduction</h3>

<p>Defaggregate introduces a recognizer, constructor, and accessors for a new
record-like structure.  It is similar to @('struct') in C or @('defstruct') in
Lisp.</p>

<p>Basic example:</p>

@({
 (defaggregate employee     ;; structure name
   (name salary position)   ;; fields
   :tag :employee           ;; options
   )
})

<p>This example would produce:</p>

<ul>
 <li>A recognizer, @('(employee-p x)'),</li>
 <li>A constructor, @('(employee name salary position)'),</li>
 <li>An accessor for each field, e.g., @('(employee->name x)'),</li>
 <li>An extension of @(see b*) to easily destructure these aggregates,</li>
 <li>Macros for making and changing aggregates,
   <ul>
    <li>@('(make-employee :name ... :salary ...)')</li>
    <li>@('(change-employee x :salary ...)')</li>
   </ul></li>
 <li>Basic theorems relating these new functions.</li>
</ul>

<p>General form:</p>

@({
 (defaggregate name
   Fields
   [Option]*              ;; i.e., :keyword value
   [/// other-events])    ;; optional, starts with the symbol ///
})

<p>The @('name') acts like a prefix the function and theorem names we generate
will be based on this name.</p>

<p>The @('Fields') describe what fields each instance of the structure will
have.  The example above shows only the very simplest syntax, but fields can
also have well-formedness requirements, documentation, etc.; see below.</p>

<p>The @('Option')s control various settings on the structure, and many options
are described below.</p>

<p>The @('other-events') is just a place for arbitrary other events to be put,
as in @(see define).  This is mainly intended as a book structuring device, to
allow you to keep related theorems near your aggregate.</p>

<p>Note that the general form is not really quite expressive enough.  We
actually allow the options and fields to come in any order.  That is, you can
put the :tag and other options before the fields, etc.</p>


<h3>Structure Tags</h3>

<p>The @(':tag') of every aggregate must either be:</p>

<ul>

<li>A keyword symbol that typically shares its name with the name of the
aggregate, e.g., in the \"employee\" aggregate the tag is @(':employee');
or</li>

<li><tt>nil</tt>, to indicate that you want a <b>tagless</b> aggregate.</li>

</ul>

<p>How are tags used?  Each instance of a tagged aggregate will be a cons tree
whose car is the tag.  This requires some overhead&mdash;one cons for every
instance of the aggregate&mdash;but allows us to compare tags to differentiate
between different kinds of aggregates.  A tagless aggregate avoids this
overhead, but you give up the ability to easily distinguish different kinds of
tagless aggregates from one another.</p>

<p>To avoid introducing many theorems about @('car'), we use an alias named
@(see tag).  Each tagged @('defaggregate') results in three tag-related
theorems:</p>

<ol>
<li>Tag of constructor:
@({
 (defthm tag-of-example
   (equal (tag (example field1 ... fieldN))
          :example))
})</li>

<li>Tag when recognized:
@({
 (defthm tag-when-example-p
   (implies (example-p x)
            (equal (tag x) :example))
   :rule-classes ((:rewrite :backchain-limit-lst 0)
                  (:forward-chaining)))
})</li>

<li>Not recognized when tag is wrong:
@({
 (defthm example-p-when-wrong-tag
   (implies (not (equal (tag x) :example))
            (equal (example-p x)
                   nil))
   :rule-classes ((:rewrite :backchain-limit-lst 1)))
})</li>
</ol>

<p>These theorems seem to perform well and settle most questions regarding the
disjointness of different kinds of aggregates.  In case the latter rules become
expensive, we always add them to the @('tag-ruleset'), so you can disable this
<see topic='@(url acl2::rulesets)'>ruleset</see> to turn off almost all
tag-related reasoning.</p>


<h3>Syntax of Fields</h3>

<p>To describe the aggregate's fields, you can make use of @(see
extended-formals) syntax.  This syntax means that fields can be optional and
use keyword/value options.  One can also use this syntax to describe a
particular field of an aggregate -- by providing documentation or specifying a
predicate that the field must satisfy.  Here is an example:</p>

@({
 (defaggregate employee
   ((name   \"Should be in Lastname, Firstname format\"
            stringp :rule-classes :type-prescription)
    (salary \"Annual salary in dollars, nil for hourly employees\"
            (or (not salary) (natp salary))
            :rule-classes :type-prescription)
    (rank \"Employee rank.  Can be empty.\"
          (implies rank (and (characterp rank)
                             (alpha-char-p rank))))
    (position (and (position-p position)
                   (salary-in-range-for-position-p salary position))
              :default :peon))
   :tag :employee)
})

<p>The \"guard\" for each field plays three roles:</p>
<ul>
<li>It is a guard on the constructor</li>
<li>It is a well-formedness requirement enforced by the recognizer</li>
<li>It is a theorem about the return type of the accessor.</li>
</ul>

<p>The return-type theorem requires some special attention.  By default, the
return-type theorem is an ordinary @(see acl2::rewrite) rule.  When this is not
appropriate, e.g., for @('name') above, you may wish to use a different
@(':rule-classes') option.</p>

<p>The embedded @(see xdoc) documentation gets incorporated into the
documentation for the aggregate in a sensible way.</p>

<p>The @(':default') value only affects the Make macro (see below).</p>

<h3>Options</h3>

<h4>Legibility</h4>

<p>By default, an aggregate is represented in a <i>legible</i> way, which means
the fields of each instance are laid out in an alist.  When such an object is
printed, it is easy to see what the value of each field is.</p>

<p>However, the structure can be made <i>illegible</i>, which means it will be
packed into a cons tree of minimum depth.  For instance, a structure whose
fields are @('(foo bar baz)') might be laid out as @('((tag . foo) . (bar
. baz))').  This can be more efficient because the structure has fewer
conses.</p>

<p>We prefer to use legible structures because they can be easier to understand
when they arise in debugging and proofs.  For instance, compare:</p>

<ul>
 <li>Legible: @('(:point3d (x . 5) (y . 6) (z . 7))')</li>
 <li>Illegible: @('(:point3d 5 6 . 7)')</li>
</ul>

<p>On the other hand, illegible structures have a more consistent structure,
which can occasionally be useful.  It's usually best to avoid reasoning about
the underlying structure of an aggregate.  But, sometimes there are exceptions
to this rule.  With illegible structures, you know exactly how each object will
be laid out, and for instance you can prove that two @('point3d') structures
will be equal exactly when their components are equal (which is not a theorem
for legible structures.)</p>

<h4>Honsed Aggregates</h4>

<p>By default, @(':hons') is nil and the constructor for an aggregate will
build the object using ordinary conses.  However, when @(':hons') is set to
@('t'), we instead always use @(see hons) when building these aggregates.</p>

<p>Honsing is only appropriate for some structures.  It is a bit slower than
consing, and should typically not be used for aggregates that will be
constructed and used in an ephemeral manner.</p>

<p>Because honsing is somewhat at odds with the memory-inefficiency of legible
structures, @(':hons t') implies @(':legiblep nil').</p>

<h4>Other Options</h4>

<dl>

<dt>:mode</dt>

<dd>Mode for the introduced functions -- must be either @(':program') or
@(':logic').  Defaults to the current @(see acl2::defun-mode).</dd>

<dt>:already-definedp</dt>

<dd>Advanced option that may be useful for mutually-recursive recognizers.
This means: generate all ordinary @('defaggregate') functions and theorems
<i>except</i> for the recognizer.  For this to work, you have to have already
defined a \"compatible\" recognizer.</dd>

<dt>:parents, :short, :long</dt>

<dd>These options are as in @(see xdoc).  Whatever you supply for @(':long')
will follow some automatically generated documentation that describes the
fields of the aggregate.</dd>

<dt>:extra-field-keywords</dt>

<dd>Advanced option for people who are writing extensions of @('defaggregate').
This tells defaggregate to tolerate (and ignore) certain additional keywords in
its fields.  The very advanced user can then inspect these fields after
submitting the aggregate, and perhaps use them to generate additional
events.</dd>

<dt>:require</dt>

<dd>This option is deprecated.  Please use the new fields syntax, instead.</dd>

<dt>:rest</dt>

<dd>This option is deprecated.  Please use the new @('///') syntax, instead.</dd>

</dl>


<h3>Make and Change Macros</h3>

<p>Direct use of the constructor is discouraged.  Instead, we introduce two
macros with every aggregate.  The @('make') macro constructs a fresh aggregate
when given values for its fields:</p>

@({
 (make-example :field1 val1 :field2 val2 ...)
    -->
 (example val1 val2 ...)
})

<p>The @('change') macro is similar, but is given an existing object as a
starting point.  It may be thought of as:</p>

@({
 (change-example x :field2 val2)
    -->
 (make-example :field1 (example->field1 x)
               :field2 val2
               :field3 (example->field3 x)
               ...)
})

<p>There are some strong advantages to using these macros instead of calling
the constructor directly.</p>

<ul>

<li>The person writing the code does not need to remember the order of the
fields</li>

<li>The person reading the code can see what values are being given to which
fields.</li>

<li>Fields whose value should be @('nil') (or some other @(':default') may be
omitted from the <i>make</i> macro.</li>

<li>Fields whose value should be left alone can be omitted from the
<i>change</i> macro.</li>

</ul>

<p>These features make it easier to add new fields to the aggregate later on,
or to rearrange fields, etc.</p>


<h3>Integration with @(see b*)</h3>

<p>Defaggregate automatically introduces a pattern binder that integrates into
@('b*').  This provides a concise syntax for destructuring aggregates.  For
instance:</p>

@({
 (b* ((bonus-percent 1/10)
      ((employee x)  (find-employee name db))
      (bonus         (+ (* x.salary bonus-percent)
                        (if (equal x.position :sysadmin)
                            ;; early christmas for me, har har...
                            (* x.salary 2)
                          0))))
   bonus)
})

<p>Can loosely be thought of as:</p>

@({
 (b* ((bonus-percent 1/10)
      (temp          (find-employee name db))
      (x.name        (employee->name temp))
      (x.salary      (employee->salary temp))
      (x.position    (employee->position temp))
      (bonus         (+ (* x.salary bonus-percent)
                        (if (equal x.position :sysadmin)
                            ;; early christmas for me, har har...
                            (* x.salary 2)
                          0))))
   bonus)
})

<p>For greater efficiency in the resulting code, we avoid binding components
which do not appear to be used, e.g., we will not actually bind @('x.name')
above.</p>

<p>Detecting whether a variable is needed at macro-expansion time is inherently
broken because we can't truly distinguish between function names, macro names,
variable names, and so forth.  It is possible to trick the binder into
including extra, unneeded variables, or into optimizing away bindings that are
necessary.  In such cases, the ACL2 user will be presented with either \"unused
variable\" or \"unbound variable\" error.  If you can come up with a
non-contrived example where this is really a problem, we might consider
developing some workaround, perhaps extended syntax that lets you suppress the
optimization altogether.</p>")

;; <h4>Debug-mode (@(':debugp') parameter)</h4>

;; <p>When set, adds calls of @('cw') that print the aggregate's data members that
;; fail the predicate test.  This can be used to help debug executions whose
;; guards were defined using predicates defined with defaggregate.  Note that the
;; defined predicate can be called many times, even during proofs, so the use of
;; @(':debugp') can result in a large amount of extra output.</p>

;; The remainder of this file just introduces the defaggregate macro.  We never
;; care about reasoning about these functions, so we go ahead and implement
;; them in program mode.


; AGGREGATES TABLE ------------------------------------------------------------
;
; We save some information about each aggregate that is defined into the table
; below.  A sufficiently advanced user can exploit this table to do various
; kinds of macro magic.

(def-primitive-aggregate agginfo
  (tag     ;; The :tag for the aggregate, a symbol
   name    ;; The base name for the aggregate
   fields  ;; The field names with no extra info, a symbol-list
   efields ;; The parsed formallist-p that has basic type requirements.
   ;; It'd be easy to add additional fields later on.
   )
  :tag :agginfo)

(table defaggregate)
(table defaggregate 'aggregates) ;; Alist of NAME -> AGGINFO structures

(defun get-aggregates (world)
  "Look up the current alist of defined aggregates."
  (cdr (assoc 'aggregates (table-alist 'defaggregate world))))

(defun get-aggregate (name world)
  "NAME is the name of the aggregate, e.g., FOO for (defaggregate foo ...).
   Look up its AGGINFO or return NIL if no such aggregate is defined."
  (cdr (assoc name (get-aggregates world))))

(defmacro da-extend-agginfo-table (agginfo)
  `(table defaggregate 'aggregates
          (cons (cons (agginfo->name ,agginfo) ,agginfo)
                (get-aggregates world))))

#||

(da-extend-agginfo-table 'buffalo
                         (make-agginfo :tag :buffalo
                                       :name 'buffalo
                                       :fields '(horns face body legs hooves)))

(da-extend-agginfo-table 'cat
                         (make-agginfo :tag :cat
                                       :name 'cat
                                       :fields '(eyes ears teeth claws fur)))

(get-aggregate 'buffalo (w state))
(get-aggregate 'cat     (w state))
(get-aggregate 'lizard  (w state))

||#



;; Format for the :require field.
;;
;; Old style requirements:
;;     (thmname term)
;;  OR (thmname term :rule-classes classes)
;;
;; We still support :require fields for compatibility with legacy code.  At
;; present our strategy is to keep most of our defaggregate processing code the
;; same and just use requirements.  That is, we convert the extended-formal
;; fields into requirements, then merge that with the :require field, then use
;; the existing code base.

(defun da-require-p (x)
  (or (and (true-listp x)
           (symbolp (car x))
           (or (= (len x) 2)
               (and (= (len x) 4)
                    (equal (third x) :rule-classes)))
           (consp (second x))
           (pseudo-termp (second x)))
      (er hard? 'da-require-p "Ill-formed requirement: ~x0.~%" x)))

(defun da-requirelist-p (x)
  (if (atom x)
      (or (not x)
          (er hard? 'da-requirelist-p
              "Requirements must be a true list."))
    (and (da-require-p (car x))
         (da-requirelist-p (cdr x)))))

(defun da-formal-to-requires (basename x)
  ;; Convert a parsed formal into old-style requirements
  (declare (xargs :guard (formal-p x)))
  (b* (((formal x) x)
       ((when (equal x.guard t))
        ;; No requirements
        nil)
       (rule-classes (or (cdr (assoc :rule-classes x.opts))
                         :rewrite))
       (thmname (intern-in-package-of-symbol
                 (concatenate 'string "RETURN-TYPE-OF-"
                              (symbol-name basename)
                              "->"
                              (symbol-name x.name))
                 basename))
       (req (list thmname x.guard :rule-classes rule-classes)))
    (list req)))

(defun da-formals-to-requires (basename x)
  ;; Turns parsed formals into require fields
  (declare (xargs :guard (formallist-p x)))
  (if (atom x)
      nil
    (append (da-formal-to-requires basename (car x))
            (da-formals-to-requires basename (cdr x)))))

(defun da-make-constructor
  ;; Careful if you change this, see gl/defagg.lisp
  (basename
   tag
   plain-fields ; just names, not extended formals
   require      ; requirements list
   honsp
   legiblep)
  (da-make-constructor-raw basename tag plain-fields
                           `(and ,@(strip-cadrs require))
                           honsp legiblep))

(defun da-make-honsed-constructor
  (basename
   tag
   plain-fields
   require
   legiblep)
  (da-make-honsed-constructor-raw basename tag plain-fields
                                  `(and ,@(strip-cadrs require))
                                  legiblep))

#||
(da-make-constructor 'taco :taco '(shell meat cheese lettuce sauce)
                   '((shell-p-of-taco->shell (shellp shell)))
                  nil nil)

;; (DEFUND TACO (SHELL MEAT CHEESE LETTUCE SAUCE)
;;         (DECLARE (XARGS :GUARD (AND (SHELLP SHELL))))
;;         (CONS :TACO (CONS (CONS SHELL MEAT)
;;                           (CONS CHEESE (CONS LETTUCE SAUCE)))))


(da-make-honsed-constructor 'taco :taco '(shell meat cheese lettuce sauce)
                            '((shell-p-of-taco->shell (shellp shell)))
                            nil)

;; (DEFUN HONSED-TACO
;;        (SHELL MEAT CHEESE LETTUCE SAUCE)
;;        (DECLARE (XARGS :GUARD (AND (SHELLP SHELL))
;;                        :GUARD-HINTS (("Goal" :IN-THEORY (ENABLE TACO)))))
;;        (MBE :LOGIC (TACO SHELL MEAT CHEESE LETTUCE SAUCE)
;;             :EXEC (HONS :TACO (HONS (HONS SHELL MEAT)
;;                                     (HONS CHEESE (HONS LETTUCE SAUCE))))))

||#

;; ;; As discussed in the user-level docomentation, if the :debugp flag is used,
;; ;; the user can see a lot of extra output that can be distracting.  It would be
;; ;; better to make this output dynamically enabled/disabled, either via a table
;; ;; flag or some other trick.  However, time is valuable, and we leave this
;; ;; improvement as future work.  Anyone who wishes to enable the defaggregate
;; ;; user to dynamically toggle this debugging output should feel free to do so.
;; ;; It would be nice to avoid the use of a trust tag, and the defined predicate
;; ;; should continue to not require the ACL2 state or world as an argument.

;; (defun da-insert-debugging-statements-into-require (require)
;;   (cond ((atom require)
;;          nil)
;;         (t (cons `(or ,(car require)

;; ;; We use output locks, because this cw output can show up during proofs
;; ;; because of executable counterparts (and we've seen it occur regularly).

;;                       (with-output-lock
;;                        (cw "Check ~x0 failed~%"
;;                            ',(car require))))
;;                  (da-insert-debugging-statements-into-require (cdr require))))))

;; bozo removed debugp for now
(defun da-make-recognizer (basename tag plain-fields require legiblep)
  (da-make-recognizer-raw basename tag plain-fields
                          `(and ,@(strip-cadrs require))
                          legiblep))

#||
(da-make-recognizer 'taco :taco '(shell meat cheese lettuce sauce)
                 '((shell-p-of-taco->shell (shellp shell)))
                   t)

;; (DEFUND TACO-P (X)
;;         (DECLARE (XARGS :GUARD T))
;;         (AND (CONSP X)
;;              (EQ (CAR X) :TACO)
;;              (ALISTP (CDR X))
;;              (CONSP (CDR X))
;;              (LET ((SHELL (CDR (ASSOC 'SHELL (CDR X))))
;;                    (MEAT (CDR (ASSOC 'MEAT (CDR X))))
;;                    (CHEESE (CDR (ASSOC 'CHEESE (CDR X))))
;;                    (LETTUCE (CDR (ASSOC 'LETTUCE (CDR X))))
;;                    (SAUCE (CDR (ASSOC 'SAUCE (CDR X)))))
;;                   (DECLARE (IGNORABLE SHELL MEAT CHEESE LETTUCE SAUCE))
;;                   (AND (SHELLP SHELL)))))

||#


(defun da-fields-recognizer-map (basename fields)
  ;; Maps each field to (foo->field x)
  (if (consp fields)
      (cons (cons (car fields) (list (da-accessor-name basename (car fields))
                                     (da-x basename)))
            (da-fields-recognizer-map basename (cdr fields)))
    nil))

(defun da-accessor-names (basename fields)
  (if (consp fields)
      (cons (da-accessor-name basename (car fields))
            (da-accessor-names basename (cdr fields)))
    nil))

(defun da-make-requirement-of-recognizer (name require map accnames)
  (let ((rule-classes (if (eq (third require) :rule-classes)
                          (fourth require)
                        :rewrite)))
    `(defthm ,(first require)
       (implies (force (,(da-recognizer-name name) ,(da-x name)))
                ,(ACL2::sublis map (second require)))
       :rule-classes ,rule-classes
       :hints(("Goal"
               :in-theory
               (union-theories
                '(,(da-recognizer-name name) . ,accnames)
                (theory 'defaggregate-basic-theory)))))))

(defun da-make-requirements-of-recognizer-aux (name require map accnames)
  (if (consp require)
      (cons (da-make-requirement-of-recognizer name (car require) map accnames)
            (da-make-requirements-of-recognizer-aux name (cdr require) map accnames))
    nil))

(defun da-make-requirements-of-recognizer (name require fields)
  (da-make-requirements-of-recognizer-aux name require
                                          (da-fields-recognizer-map name fields)
                                          (da-accessor-names name fields)))


(defun da-field-doc (x acc base-pkg state)
  (declare (xargs :guard (formal-p x)))
  (b* (((formal x) x)

       (acc (str::revappend-chars "<li>" acc))
       ((mv name-str state) (xdoc::fmt-to-str x.name base-pkg state))
       (acc (str::revappend-chars "<tt>" acc))
       (acc (xdoc::simple-html-encode-str name-str 0 (length name-str) acc))
       (acc (str::revappend-chars "</tt>" acc))

       ((when (and (eq x.guard t)
                   (equal x.doc "")))
        ;; Nothing more to say, just a plain field
        (b* ((acc (str::revappend-chars "</li>" acc))
             (acc (cons #\Newline acc)))
          (mv acc state)))

       (acc (str::revappend-chars " &mdash; " acc))

       (acc (if (equal x.doc "")
                acc
              (b* ((acc (str::revappend-chars x.doc acc))
                   (acc (if (ends-with-period-p x.doc)
                            acc
                          (cons #\. acc))))
                acc)))

       ((when (eq x.guard t))
        (b* ((acc (str::revappend-chars "</li>" acc))
             (acc (cons #\Newline acc)))
          (mv acc state)))

       (acc (if (equal x.doc "")
                acc
              (str::revappend-chars "<br/>&nbsp;&nbsp;&nbsp;&nbsp;" acc)))
       (acc (str::revappend-chars "<color rgb='#606060'>" acc))
       ((mv guard-str state) (xdoc::fmt-to-str x.guard base-pkg state))
       ;; Using @('...') here isn't necessarily correct.  If the sexpr has
       ;; something in it that can lead to '), we are hosed.  BOZO eventually
       ;; check for this and make sure we use <code> tags instead, if it
       ;; happens.
       (acc (str::revappend-chars "Invariant @('" acc))
       (acc (str::revappend-chars guard-str acc))
       (acc (str::revappend-chars "').</color></li>" acc))
       (acc (cons #\Newline acc)))
    (mv acc state)))

(defun da-fields-doc-aux (x acc base-pkg state)
  (declare (xargs :guard (formallist-p x)))
  (b* (((when (atom x))
        (mv acc state))
       ((mv acc state)
        (da-field-doc (car x) acc base-pkg state)))
    (da-fields-doc-aux (cdr x) acc base-pkg state)))

(defun da-fields-doc (x acc base-pkg state)
  (declare (xargs :guard (formallist-p x)))
  (b* ((acc (str::revappend-chars "<ul>" acc))
       ((mv acc state) (da-fields-doc-aux x acc base-pkg state))
       (acc (str::revappend-chars "</ul>" acc)))
    (mv acc state)))

(defun da-main-autodoc (name fields parents short long base-pkg state)
  (b* ( ;; We begin by constructing the :long string
       (acc  nil)
       (foop (da-recognizer-name name))
       (acc  (str::revappend-chars "<p>@(call " acc))
       ;; This isn't right, in general.  Need to properly get the name
       ;; into escaped format.
       (acc  (str::revappend-chars (symbol-package-name foop) acc))
       (acc  (str::revappend-chars "::" acc))
       (acc  (str::revappend-chars (symbol-name foop) acc))
       (acc  (str::revappend-chars ") is a @(see std::defaggregate) of the following fields.</p>" acc))
       ((mv acc state) (da-fields-doc fields acc base-pkg state))
       (acc  (str::revappend-chars "<p>Source link: @(srclink " acc))
       (acc  (str::revappend-chars (string-downcase (symbol-name name)) acc))
       (acc  (str::revappend-chars ")</p>" acc))
       (acc  (str::revappend-chars (or long "") acc))
       (long (str::rchars-to-string acc)))
    (mv `(defxdoc ,foop
           :parents ,parents
           :short ,short
           :long ,long)
        state)))

(defun da-field-autodoc (name field)
  (declare (xargs :guard (formal-p field)))
  (b* (((formal field) field)
       (foop     (da-recognizer-name name))
       (accessor (da-accessor-name name field.name))
       ;; bozo escaping issues...
       (short    (str::cat "Access the <tt>" (string-downcase (symbol-name field.name))
                           "</tt> field of a @(see "
                           (symbol-package-name foop) "::" (symbol-name foop)
                           ") structure.")))
    `(defxdoc ,accessor
       :parents (,foop)
       :short ,short)))

(defun da-fields-autodoc (name fields)
  (declare (xargs :guard (formallist-p fields)))
  (if (consp fields)
      (cons (da-field-autodoc name (car fields))
            (da-fields-autodoc name (cdr fields)))
    nil))

(defun da-ctor-optional-fields (fields)
  (declare (xargs :guard (formallist-p fields)))
  (b* (((when (atom fields))
        nil)
       (name1 (xdoc::name-low (symbol-name (formal->name (car fields)))))
       (len1  (length name1))
       (acc   nil)
       (acc   (str::revappend-chars "[:" acc))
       (acc   (xdoc::simple-html-encode-str name1 0 len1 acc))
       (acc   (str::revappend-chars " &lt;" acc))
       (acc   (xdoc::simple-html-encode-str name1 0 len1 acc))
       (acc   (str::revappend-chars "&gt;]" acc)))
    (cons (str::rchars-to-string acc)
          (da-ctor-optional-fields (cdr fields)))))

(defconst *nl* (str::implode (list #\Newline)))

(defun da-ctor-optional-call (name        ; e.g., make-honsed-foo
                              field-strs  ; e.g., ("[:field1 <field1>]" "[field2 <field2>"])
                              )
  (declare (xargs :guard (and (symbolp name)
                              (string-listp field-strs))))
  (b* ((ctor-name (xdoc::name-low (symbol-name name)))
       ;; +2 to account for the leading paren and trailing space after ctor-name 
       (len       (+ 2 (length ctor-name)))
       (pad       (str::implode (cons #\Newline (repeat #\Space len))))
       (args      (str::join field-strs pad)))
    (str::cat "<code>" *nl* "(" ctor-name " " args ")" *nl* "</code>")))

#||

(da-ctor-optional-call 'make-honsed-foo
                       '("[:lettuce <lettuce>]"
                         "[:cheese <cheese>]"
                         "[:meat <meat>]"))

(da-ctor-optional-call 'change-honsed-foo
                       '("x"
                         "[:lettuce <lettuce>]"
                         "[:cheese <cheese>]"
                         "[:meat <meat>]"))
||#

(defun da-ctor-autodoc (name fields honsp)
  (declare (xargs :guard (and (symbolp name)
                              (formallist-p fields))))
  (b* ((foo                (da-constructor-name name))
       (foo-p              (da-recognizer-name name))
       (honsed-foo         (da-honsed-constructor-name name))
       (make-foo-fn        (da-maker-fn-name name))
       (make-foo           (da-maker-name name))
       (make-honsed-foo    (da-honsed-maker-name name))
       (make-honsed-foo-fn (da-honsed-maker-fn-name name))
       (change-foo-fn      (da-changer-fn-name name))
       (change-foo         (da-changer-name name))

       (see-foo-p           (xdoc::see foo-p))
       (plain-foo-p         (str::cat "<tt>" (xdoc::name-low (symbol-name foo-p)) "</tt>"))
       (see-foo             (xdoc::see foo))
       (see-honsed-foo      (xdoc::see honsed-foo))
       (see-make-foo        (xdoc::see make-foo))
       (see-make-honsed-foo (xdoc::see make-honsed-foo))
       (see-change-foo      (xdoc::see change-foo))

       (pkg               (symbol-package-name name))
       (call-foo          (str::cat "@(ccall " pkg "::" (symbol-name foo) ")"))
       (call-honsed-foo   (str::cat "@(ccall " pkg "::" (symbol-name honsed-foo) ")"))

       ;; For make-foo, change-foo, etc., it's nicer to present a list of [:fld <fld>] options
       ;; rather than just saying &rest args, which is what @(call ...) would do.
       (opt-fields           (da-ctor-optional-fields fields))
       (call-make-foo        (da-ctor-optional-call make-foo opt-fields))
       (call-make-honsed-foo (da-ctor-optional-call make-honsed-foo opt-fields))
       (call-change-foo      (da-ctor-optional-call change-foo (cons "x" opt-fields)))

       (def-foo           (str::cat "@(def " pkg "::" (symbol-name foo) ")"))
       (def-honsed-foo    (str::cat "@(def " pkg "::" (symbol-name honsed-foo) ")"))
       (def-make-foo-fn   (str::cat "@(def " pkg "::" (symbol-name make-foo-fn) ")"))
       (def-make-foo      (str::cat "@(def " pkg "::" (symbol-name make-foo) ")"))
       (def-make-honsed-foo-fn (str::cat "@(def " pkg "::" (symbol-name make-honsed-foo-fn) ")"))
       (def-make-honsed-foo    (str::cat "@(def " pkg "::" (symbol-name make-honsed-foo) ")"))
       (def-change-foo-fn (str::cat "@(def " pkg "::" (symbol-name change-foo-fn) ")"))
       (def-change-foo    (str::cat "@(def " pkg "::" (symbol-name change-foo) ")")))

    (list
     `(defxdoc ,foo
        :parents (,foo-p)
        :short ,(str::cat "Raw constructor for " see-foo-p " structures.")
        :long ,(str::cat
                "<p>Syntax:</p>" call-foo

                "<p>This is the lowest-level constructor for " see-foo-p
                " structures.  It simply conses together a structure with the
                specified fields.</p>

                <p><b>Note:</b> It's generally better to use macros like "
                see-make-foo " or " see-change-foo " instead.  These macros
                lead to more readable and robust code, because you don't have
                to remember the order of the fields.</p>"

                (if honsp
                    (str::cat "<p>Note that we always use @(see acl2::hons) when
                               creating " plain-foo-p " structures.</p>")
                  (str::cat "<p>The " plain-foo-p " structures we create here
                             are just constructed with ordinary @(see acl2::cons).
                             If you want to create @(see acl2::hons)ed structures,
                             see " see-honsed-foo " instead.</p>"))

                "<h3>Definition</h3>

                <p>This is an ordinary constructor function introduced by @(see
                std::defaggregate).</p>"

                def-foo))

     `(defxdoc ,honsed-foo
        :parents (,foo-p)
        :short ,(str::cat "Raw constructor for @(see acl2::hons)ed " see-foo-p
                          " structures.")
        :long ,(str::cat
                "<p>Syntax:</p> " call-honsed-foo

                (if honsp
                    (str::cat "<p>Since " see-foo-p " structures are always
                              honsed, this is identical to " see-foo ".  We
                              introduce it mainly for consistency with other
                              @(see std::defaggregate) style structures.</p>")
                  (str::cat "<p>This is identical to " see-foo ", except that
                            we @(see acl2::hons) the structure we are
                            creating.</p>"))

                "<h3>Definition</h3>

                <p>This is an ordinary honsing constructor introduced by @(see
                std::defaggregate).</p>"

                def-honsed-foo))

     `(defxdoc ,make-foo
        :parents (,foo-p)
        :short ,(str::cat "Constructor macro for " see-foo-p " structures.")
        :long ,(str::cat
                "<p>Syntax:</p>" call-make-foo

                "<p>This is our preferred way to construct " see-foo-p
                " structures.  It simply conses together a structure with the
                specified fields.</p>

                <p>This macro generates a new " plain-foo-p " structure from
                scratch.  See also " see-change-foo ", which can \"change\" an
                existing structure, instead.</p>"

                (if honsp
                    (str::cat "<p>Note that we always use @(see acl2::hons) when
                               creating " plain-foo-p " structures.</p>")
                  (str::cat "<p>The " plain-foo-p " structures we create here
                             are just constructed with ordinary @(see acl2::cons).
                             If you want to create @(see acl2::hons)ed structures,
                             see " see-make-honsed-foo " instead.</p>"))

                "<h3>Definition</h3>

                <p>This is an ordinary @('make-') macro introduced by @(see
                std::defaggregate).</p>"

                def-make-foo
                def-make-foo-fn))

     `(defxdoc ,make-honsed-foo
        :parents (,foo-p)
        :short ,(str::cat "Constructor macro for @(see acl2::hons)ed " see-foo-p
                          " structures.")
        :long ,(str::cat
                "<p>Syntax:</p>" call-make-honsed-foo

                (if honsp
                    (str::cat "<p>Since " see-foo-p " structures are always
                              honsed, this is identical to " see-make-foo ".
                              We introduce it mainly for consistency with other
                              @(see std::defaggregate)s.</p>")
                  (str::cat "<p>This is identical to " see-make-foo ", except
                            that we @(see acl2::hons) the structure we are
                            creating.</p>"))

                "<h3>Definition</h3>

                <p>This is an ordinary honsing @('make-') macro introduced by
                @(see std::defaggregate).</p>"

                def-make-honsed-foo
                def-make-honsed-foo-fn))

     `(defxdoc ,change-foo
        :parents (,foo-p)
        :short ,(str::cat "A copying macro that lets you create new "
                          see-foo-p " structures, based on existing structures.")
        :long ,(str::cat
                "<p>Syntax:</p>" call-change-foo

                "<p>This is a sometimes useful alternative to " see-make-foo ".
                It constructs a new " see-foo-p " structure that is a copy of
                @('x'), except that you can explicitly change some particular
                fields.  Any fields you don't mention just keep their values
                from @('x').</p>

                <h3>Definition</h3>

                <p>This is an ordinary @('change-') macro introduced by @(see
                std::defaggregate).</p>"

                def-change-foo
                def-change-foo-fn)))))

(defun da-autodoc (name fields honsp parents short long base-pkg state)
  (declare (xargs :guard (formallist-p fields)))
  (b* (((mv main state)
        (da-main-autodoc name fields parents short long base-pkg state))
       (ctors     (da-ctor-autodoc name fields honsp))
       (accessors (da-fields-autodoc name fields)))
    (mv (cons main (append ctors accessors)) state)))

(defconst *da-valid-keywords*
  '(:tag
    :legiblep
    :hons
    :mode
    :parents
    :short
    :long
    :already-definedp
    :extra-field-keywords
    ;; deprecated options
    :require
    :rest))

(defun formal->default (x)
  (declare (xargs :guard (formal-p x)))
  (cdr (assoc :default (formal->opts x))))

(defun formallist->defaults (x)
  (declare (xargs :guard (formallist-p x)))
  (if (atom x)
      nil
    (cons (formal->default (car x))
          (formallist->defaults (cdr x)))))


#!STD
(defun defaggregate-fn (name rest state)
  (b* ((__function__ 'defaggregate)

       (current-defun-mode (default-defun-mode (w state)))
       (base-pkg (pkg-witness (acl2::f-get-global 'acl2::current-package state)))

       ((unless (symbolp name))
        (mv (raise "Name must be a symbol.") state))
       (ctx (list 'defaggregate name))
       ((mv main-stuff other-events) (split-/// ctx rest))
       ((mv kwd-alist field-specs)
        (extract-keywords ctx *da-valid-keywords* main-stuff nil))

       (extra-field-keywords (cdr (assoc :extra-field-keywords kwd-alist)))
       ((unless (consp field-specs))
        (mv (raise "~x0: No fields given." name) state))
       ((unless (tuplep 1 field-specs))
        (mv (raise "~x0: Too many field specifiers: ~x1" name field-specs) state))
       (efields     (parse-formals ctx (car field-specs)
                                   (append '(:rule-classes :default)
                                           extra-field-keywords)))
       (field-names (formallist->names efields))
       (field-defaults (formallist->defaults efields))
       ((unless (no-duplicatesp field-names))
        (mv (raise "~x0: field names must be unique." name) state))
       ((unless (consp field-names))
        (mv (raise "~x0: there must be at least one field." name) state))

       ;; legacy support for :rest, eventually remove this.
       (legacy-rest (cdr (assoc :rest kwd-alist)))
       ((unless (true-listp legacy-rest))
        (mv (raise "~x0: :rest must be a true-listp." name) state))
       (other-events (append legacy-rest other-events))

       (tag (cdr (assoc :tag kwd-alist)))
       ((unless (or (not tag)
                    (and (symbolp tag)
                         (equal (symbol-package-name tag) "KEYWORD"))))
        (mv (raise "~x0: Tag must be a keyword symbol or NIL, found ~x1" name tag) state))

       (parents (or (cdr (assoc :parents kwd-alist)) '(acl2::undocumented)))
       ((unless (symbol-listp parents))
        (mv (raise "~x0: :parents must be a list of symbols." name) state))

       (short (cdr (assoc :short kwd-alist)))
       ((unless (or (stringp short) (not short)))
        (mv (raise "~x0: :short must be a string (or nil)" name) state))

       (long (cdr (assoc :long kwd-alist)))
       ((unless (or (stringp long) (not long)))
        (mv (raise "~x0: :long must be a string (or nil)" name) state))

       (mode (or (cdr (assoc :mode kwd-alist)) current-defun-mode))
       ((unless (member mode '(:logic :program)))
        (mv (raise "~x0: :mode must be :logic or :program" name) state))

       (already-definedp (cdr (assoc :already-definedp kwd-alist)))
       ((unless (booleanp already-definedp))
        (mv (raise "~x0: :already-definedp should be a boolean." name) state))

       (legiblep (if (assoc :legiblep kwd-alist)
                     (cdr (assoc :legiblep kwd-alist))
                   t))
       ((unless (booleanp legiblep))
        (mv (raise "~x0: :legiblep should be a boolean." name) state))

       (honsp (cdr (assoc :hons kwd-alist)))
       ((unless (booleanp honsp))
        (mv (raise "~x0: :hons should be a boolean." name) state))

       ;; Expand requirements to include stuff from the field specifiers.
       (old-reqs   (cdr (assoc :require kwd-alist)))
       (field-reqs (da-formals-to-requires name efields))
       (require    (append field-reqs old-reqs))
       ((unless (da-requirelist-p require))
        (mv (raise "~x0: malformed :require field" name) state))
       ((unless (no-duplicatesp (strip-cars require)))
        (mv (raise "~x0: The names given to :require must be unique." name) state))

       (x        (da-x name))
       (foop     (da-recognizer-name name))
       (make-foo (da-constructor-name name))
       (legiblep (and legiblep (not honsp)))

       (foop-of-make-foo
        (intern-in-package-of-symbol (str::cat (symbol-name foop)
                                               "-OF-"
                                               (symbol-name make-foo))
                                     name))
       ((mv doc-events state)
        (da-autodoc name efields honsp parents short long base-pkg state))

       (agginfo (make-agginfo :name    name
                              :tag     tag
                              :fields  field-names
                              :efields efields))

       (booleanp-of-foop (intern-in-package-of-symbol
                          (concatenate 'string "BOOLEANP-OF-" (symbol-name foop))
                          name))

       (event
        `(progn

; Note: the theory stuff here a bit ugly for performance.  Using progn instead
; of encapsulate means we don't have a local scope to work with.  Just using
; encapsulate instead slowed down vl/parsetree by 4 seconds, and when I added
; ordinary, local theory forms, it slowed down the book from 40 seconds to 70
; seconds!  So that was pretty horrible.  At any rate, the union-theory stuff
; here is ugly, but at least it's fast.

           (set-inhibit-warnings "theory") ;; implicitly local
           (da-extend-agginfo-table ',agginfo)
           ,@doc-events

           ,(if (eq mode :logic)
                '(logic)
              '(program))

           ,@(if already-definedp
                 nil
               (list (da-make-recognizer name tag field-names require legiblep)))
           ,(da-make-constructor name tag field-names require honsp legiblep)
           ,(da-make-honsed-constructor name tag field-names require legiblep)
           ,@(da-make-accessors name tag field-names legiblep)

           ,@(and
              (eq mode :logic)
              `(
                ;; (defthm ,(intern-in-package-of-symbol
                ;;           (concatenate 'string (symbol-name make-foo) "-UNDER-IFF")
                ;;           name)
                ;;   (iff (,make-foo ,@field-names)
                ;;        t)
                ;;   :hints(("Goal" :in-theory (enable ,make-foo))))

                (defthm ,(intern-in-package-of-symbol
                          ;; This seems like a stronger replacement for the above?
                          (concatenate 'string "CONSP-OF-" (symbol-name make-foo))
                          name)
                  (consp (,make-foo ,@field-names))
                  :rule-classes :type-prescription
                  :hints(("Goal" :in-theory (enable ,make-foo))))

                (defthm ,booleanp-of-foop
                  (booleanp (,foop ,x))
                  :rule-classes :type-prescription
                  :hints(("Goal" :in-theory (enable ,foop))))

                (defthm ,foop-of-make-foo
                  ,(if (consp require)
                       `(implies (force (and ,@(strip-cadrs require)))
                                 (equal (,foop (,make-foo ,@field-names))
                                        t))
                     `(equal (,foop (,make-foo ,@field-names))
                             t))
                  :hints(("Goal"
                          :in-theory
                          (union-theories
                           '(,foop ,make-foo)
                           (theory 'defaggregate-basic-theory))
                          :use ((:instance ,booleanp-of-foop
                                           (,x (,make-foo ,@field-names)))))))

                ,@(and tag
                       `((defthm ,(intern-in-package-of-symbol
                                   (str::cat "TAG-OF-" (symbol-name make-foo))
                                   name)
                           (equal (tag (,make-foo ,@field-names))
                                  ,tag)
                           :hints(("Goal"
                                   :in-theory
                                   (union-theories
                                    '(,make-foo)
                                    (theory 'defaggregate-basic-theory)))))

                         (defthm ,(intern-in-package-of-symbol
                                   (str::cat "TAG-WHEN-" (symbol-name foop))
                                   name)
                           (implies (,foop ,x)
                                    (equal (tag ,x)
                                           ,tag))
                           :rule-classes ((:rewrite :backchain-limit-lst 0)
                                          (:forward-chaining))
                           :hints(("Goal"
                                   :in-theory
                                   (union-theories
                                    '(,foop)
                                    (theory 'defaggregate-basic-theory)))))

                         (defthm ,(intern-in-package-of-symbol
                                   (str::cat (symbol-name foop) "-WHEN-WRONG-TAG")
                                   name)
                           (implies (not (equal (tag ,x) ,tag))
                                    (equal (,foop ,x)
                                           nil))
                           :rule-classes ((:rewrite :backchain-limit-lst 1))
                           :hints(("Goal"
                                   :in-theory
                                   (union-theories
                                    '(,foop)
                                    (theory 'defaggregate-basic-theory)))))

                         (add-to-ruleset tag-reasoning
                                         '(,(intern-in-package-of-symbol
                                             (str::cat "TAG-WHEN-" (symbol-name foop))
                                             name)
                                           ,(intern-in-package-of-symbol
                                             (str::cat (symbol-name foop) "-WHEN-WRONG-TAG")
                                             name)))))

                (defthm ,(intern-in-package-of-symbol
                          (concatenate 'string "CONSP-WHEN-" (symbol-name foop))
                          name)
                  (implies (,foop ,x)
                           (consp ,x))
                  :rule-classes :compound-recognizer
                  :hints(("Goal"
                          :in-theory
                          (union-theories '(,foop)
                                          (theory 'defaggregate-basic-theory)))))

                ,@(da-make-accessors-of-constructor name field-names)
                ,@(da-make-requirements-of-recognizer name require field-names)))

           ,(da-make-binder name field-names)

           ,(da-make-changer-fn name field-names)
           ,(da-make-changer name field-names)

           ,(da-make-maker-fn name field-names field-defaults)
           ,(da-make-maker name field-names)

           ,(da-make-honsed-maker-fn name field-names field-defaults)
           ,(da-make-honsed-maker name field-names)

           (with-output :stack :pop
             (progn . ,other-events))

           (value-triple '(defaggregate ,name)))))
    (mv `(with-output
           :stack :push
           :gag-mode t
           :off (acl2::summary acl2::observation acl2::prove acl2::proof-tree
                               acl2::event)
           ,event)
        state)))

(defmacro defaggregate (name &rest args)
  `(make-event
    (b* (((mv event state)
          (defaggregate-fn ',name ',args state)))
      (value event))))