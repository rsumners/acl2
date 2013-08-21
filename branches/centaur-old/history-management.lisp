; ACL2 Version 4.2 -- A Computational Logic for Applicative Common Lisp
; Copyright (C) 2011  University of Texas at Austin

; This version of ACL2 is a descendent of ACL2 Version 1.9, Copyright
; (C) 1997 Computational Logic, Inc.  See the documentation topic NOTE-2-0.

; This program is free software; you can redistribute it and/or modify
; it under the terms of the GNU General Public License as published by
; the Free Software Foundation; either version 2 of the License, or
; (at your option) any later version.

; This program is distributed in the hope that it will be useful,
; but WITHOUT ANY WARRANTY; without even the implied warranty of
; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
; GNU General Public License for more details.

; You should have received a copy of the GNU General Public License
; along with this program; if not, write to the Free Software
; Foundation, Inc., 675 Mass Ave, Cambridge, MA 02139, USA.

; Written by:  Matt Kaufmann               and J Strother Moore
; email:       Kaufmann@cs.utexas.edu      and Moore@cs.utexas.edu
; Department of Computer Science
; University of Texas at Austin
; Austin, TX 78701 U.S.A.

(in-package "ACL2")

; Section:  Proof Trees

; We develop proof trees in this file, rather than in prove.lisp, because
; print-summary calls print-proof-tree.

; A goal tree is a structure of the following form, with the fields indicated
; below.  We put the two non-changing fields at the end; note:

; ACL2 p>:sbt 4
; 
; The Binary Trees with Four Tips
; 2.000  ((2 . 2) 2 . 2)
; 2.250  (1 2 3 . 3)

(defrec goal-tree (children processor cl-id . fanout) nil)

; Cl-id is a clause-id record for the name of the goal.

; Children is a list of goal trees whose final cdr is either nil or a positive
; integer.  In the latter case, this positive integer indicates the remaining
; number of children for which to build goal trees.

; Fanout is the original number of children.

; Processor is one of the processors from *preprocess-clause-ledge* (except for
; settled-down-clause, which has no use here), except that we have two special
; annotations and two "fictitious" processors.

; Instead of push-clause, we use (push-clause cl-id), where cl-id is the
; clause-id of the clause pushed (e.g., the clause-id corresponding to "*1").
; Except: (push-clause cl-id :REVERT) is used when we are reverting to the
; original goal, and in this case, cl-id always corresponds to *1; also,
; (push-clause cl-id :ABORT) is used when the proof is aborted by push-clause.

; Instead of a processor pr, we may have (pr :forced), which indicates that
; this processor forced assumptions (but remember, some of those might get
; proved during the final clean-up phase).  When we enter the next forcing
; round, we will "decorate" the above "processor" by adding a list of new goals
; created by that forcing: (pr :forced clause-id_1 ... clause-id_n).  As we go
; along we may prune away some of those new clause ids.

; Finally, occasionally the top-level node in a goal-tree is "fictitious", such
; as the one for "[1]Goal" if the first forcing round presented more than one
; forced goal, and such as any goal to be proved by induction.  In that case,
; the "processor" is one of the keyword labels :INDUCT or :FORCING-ROUND or a
; list headed by such keywords, e.g. if we want to say what induction scheme is
; being used.

; A proof tree is simply a non-empty list of goal trees.  The "current" goal
; tree is the CAR of the current proof tree; it's the one for the current
; forcing round or proof by induction.

; There is always a current proof tree, (@ proof-tree), except when we are
; inhibiting proof-tree output or are not yet in a proof.  The current goal in
; a proof is always the first one associated with the first subtree of the
; current goal-tree that has a non-nil final CDR, via a left-to-right
; depth-first traversal of that tree.  We keep the proof tree pruned, trimming
; away proved subgoals and their children.

; The proof tree is printed to the screen, enclosed in #\n\<0 ... #\n\>.  We
; start with # because that seems like a rare character, and we want to leave
; emacs as unburdened as possible in its use of string-matching.  And, we put a
; newline in front of \ because in ordinary PRINT-like (as opposed to
; PRINC-like) printing, as done by the prover, \ is always quoted and hence
; would not appear in a sequence such as <newline>\?, where ? is any character
; besides \.  Naturally, this output can be inhibited, simply by putting
; 'proof-tree on the state global variable inhibit-output-lst.  Mike Smith has
; built, and we have modified, a "filter" tool for redirecting such output in a
; nice form to appropriate emacs buffers.  People who do not want to use the
; emacs facility (or some other display utility) should probably inhibit
; proof-tree output using :stop-proof-tree.

(deflabel proof-tree
  :doc
  ":Doc-Section Proof-tree

  proof tree displays~/

  A view of ACL2 proofs may be obtained by way of ``proof tree displays.''  The
  emacs environment is easily customized to provide window-based proof tree
  displays that assist in traversing and making sense of the proof transcript;
  ~pl[proof-tree-emacs].  Proof tree displays may be turned on with the command
  ~c[:]~ilc[start-proof-tree] and may be turned off with the command
  ~c[:]~ilc[stop-proof-tree]; ~pl[start-proof-tree] and ~pl[stop-proof-tree].~/

  Here is an example of a proof tree display, with comments.  Lines marked with
  ``c'' are considered ``checkpoints,'' i.e., goals whose scrutiny may be of
  particular value.
  ~bv[]
  ( DEFTHM PLUS-TREE-DEL ...)    ;currently proving PLUS-TREE-DEL
     1 Goal preprocess   ;\"Goal\" creates 1 subgoal by preprocessing
     2 |  Goal' simp     ;\"Goal'\" creates 2 subgoals by simplification
  c  0 |  |  Subgoal 2 PUSH *1   ;\"Subgoal 2\" pushes \"*1\" for INDUCT
  ++++++++++++++++++++++++++++++ ;first pass thru waterfall completed
  c  6 *1 INDUCT                 ;Proof by induction of \"*1\" has
       |  <5 more subgoals>      ; created 6 top-level subgoals.  At
                                 ; this point, one of those 6 has been
                                 ; proved, and 5 remain to be proved.
                                 ; We are currently working on the
                                 ; first of those 5 remaining goals.
  ~ev[]
  ~l[proof-tree-examples] for many examples that contain proof tree displays.
  But first, we summarize the kinds of lines that may appear in a proof tree
  display.  The simplest form of a proof tree display is a header showing the
  current event, followed by list of lines, each having one of the following
  forms.
  ~bv[]
      n <goal> <process> ...
  ~ev[]
  Says that the indicated goal created ~c[n] subgoals using the indicated
  process.  Here ``...'' refers to possible additional information.
  ~bv[]
  c   n <goal> <process> ...
  ~ev[]
  As above, but calls attention to the fact that this goal is a ``checkpoint''
  in the sense that it may be of particular interest.  Some displays may
  overwrite ``c'' with ``>'' to indicate the current checkpoint being shown in
  the proof transcript.
  ~bv[]
       |  <goal> ...
       |  |  <k subgoals>
  ~ev[]
  Indicates that the goal just above this line, which is pointed to by the
  rightmost vertical bar (``|''), has ~c[k] subgoals, none of which have yet
  been processed.
  ~bv[]
       |  <goal> ...
       |  |  <k more subgoals>
  ~ev[]
  As above, except that some subgoals have already been processed.
  ~bv[]
  ++++++++++++++++++++++++++++++
  ~ev[]
  Separates successive passes through the ``waterfall''.  Thus, this
  ``fencepost'' mark indicates the start of a new proof by induction or of a
  new forcing round.

  ~l[proof-tree-examples] for detailed examples.  To learn how to turn off
  proof tree displays or to turn them back on again, ~pl[stop-proof-tree] and
  ~pl[start-proof-tree], respectively. ~l[checkpoint-forced-goals] to learn how
  to mark goals as checkpoints that ~il[force] the creation of goals in forcing
  rounds.  Finally, ~pl[proof-tree-details] for some points not covered
  elsewhere.")

(deflabel proof-tree-emacs
  :doc
  ":Doc-Section Proof-tree

  using emacs with proof trees~/

  Within emacs, proof trees provide a sort of structure for the linear proof
  transcript output by the ACL2 prover.  Below we explain how to get proof
  trees set up in your emacs environment.~/

  To get started, it suffices to load the distributed ACL2 emacs file, which
  has lots more than just proof tree support (documented near the top of that
  file), as follows.  Thus, you can put the following form in your
  ~c[~~/.emacs] file, where ~c[DIR] refers to your ACL2 source directory
  (typically called ~c[acl2-sources/]).
  ~bv[]
  (load \"DIR/emacs/emacs-acl2.el\")
  ~ev[]
  Then you can start the proof tree display by issuing the following emacs
  command:  ~c[M-x start-proof-tree].

  If you prefer not to load the ACL2 emacs file as shown above, you can instead
  put the following forms in your ~c[~~/.emacs] file (where ~c[DIR] is as
  above) and then issue the above ~c[M-x] command.
  ~bv[]
  (setq *acl2-interface-dir*
        \"DIR/interface/emacs/\")

  (autoload 'start-proof-tree
    (concat *acl2-interface-dir* \"top-start-shell-acl2\")
    \"Enable proof tree logging in a prooftree buffer.\"
    t)
  ~ev[]
  Once the above is taken care of, then to start using proof trees you
  do two things.  In emacs, start a shell (~c[meta-x shell]) and evaluate:
  ~bv[]
     M-x start-proof-tree
  ~ev[]
  Also, in your ACL2, evaluate
  ~bv[]
    :start-proof-tree
  ~ev[]
  If you want to turn off proof trees, evaluate this in emacs
  ~bv[]
     M-x stop-proof-tree
  ~ev[]
  and evaluate this in your ACL2 session:
  ~bv[]
    :stop-proof-tree
  ~ev[]
  When you do ~c[M-x start-proof-tree] for the first time in your emacs
  session, you will be prompted for some information.  You can avoid the
  prompt by putting the following in your ~c[.emacs] file.  The defaults are
  as shown, but you can of course change them.
  ~bv[]
    (setq *acl2-proof-tree-height* 17)
    (setq *checkpoint-recenter-line* 3)
    (setq *mfm-buffer* \"*shell*\")
  ~ev[]
  Alternatively, you can put the following in your ~c[~~/.emacs file] in order
  to start proof trees without any queries.
  ~bv[]
    (start-proof-tree-noninteractive \"*shell*\")
  ~ev[]

  Once you start proof trees (meta-x start-proof-tree), you will have defined
  the key bindings shown by executing ~c[C-z h] in emacs.  Also
  ~pl[proof-tree-bindings] for that additional documentation.

  If you want ~il[proof-tree]s to be displayed in a separate emacs frame to the
  side, then you can put the following forms in your ~c[.emacs] file above the
  load of ~c[emacs-acl2.el] described above.  But you may wish to edit the
  second form, in particular the number 2048.
  ~bv[]
  (start-proof-tree-noninteractive \"*shell*\")
  (cond ((and (eq window-system 'x)
              (fboundp 'x-display-pixel-width)
              (= (x-display-pixel-width) 2048) ; for a wide monitor
              )
         (delete-other-windows)
         (if (boundp 'emacs-startup-hook) ; false in xemacs
             (push 'new-prooftree-frame emacs-startup-hook))))
  ~ev[]

  The file ~c[interface/emacs/README-mouse.doc] discusses an extension of ACL2
  proof trees that allows the mouse to be used with menus.  That extension may
  well work, but it is no longer supported.  The basic proof tree interface,
  however, is supported and is what is described in detail elsewhere;
  ~pl[proof-tree].  Thanks to Mike Smith for his major role in providing emacs
  support for proof trees.")

(deflabel proof-tree-bindings
  :doc
  ":Doc-Section Proof-tree-emacs

  using emacs with proof trees~/

  The key bindings set up when you start proof trees are shown below.
  ~l[proof-tree-emacs] for how to get started with proof trees.~/

  ~bv[]
     C-z h               help
     C-z ?               help
  ~ev[]
  Provides information about proof-tree/checkpoint tool.
  Use `C-h d' to get more detailed information for specific functions.

  ~bv[]
     C-z c               Go to checkpoint
  ~ev[]
  Go to a checkpoint, as displayed in the \"prooftree\" buffer with the
  character ~c[c] in the first column.  With non-zero prefix argument: move the
  point in the ACL2 buffer (emacs variable ~c[*mfm-buffer*]) to the first
  checkpoint displayed in the \"prooftree\" buffer, suspend the proof tree (see
  ~c[suspend-proof-tree]), and move the cursor below that checkpoint in the
  \"prooftree\" buffer.  Without a prefix argument, go to the first checkpoint
  named below the point in the \"prooftree\" buffer (or if there is none, to
  the first checkpoint).  Note however that unless the proof tree is suspended
  or the ACL2 proof is complete or interrupted, the cursor will be generally be
  at the bottom of the \"prooftree\" buffer each time it is modified, which
  causes the first checkpoint to be the one that is found.

  If the prefix argument is 0, move to the first checkpoint but do not keep
  suspended.

  ~bv[]
     C-z g               Goto subgoal
  ~ev[]
  Go to the specified subgoal in the ACL2 buffer (emacs variable
  ~c[*mfm-buffer*]) that lies closest to the end of that buffer -- except if
  the current buffer is \"prooftree\" when this command is invoked, the subgoal
  is the one from the proof whose tree is displayed in that buffer.  A default
  is obtained, when possible, from the current line of the current buffer.

  ~bv[]
     C-z r               Resume proof tree
  ~ev[]
  Resume original proof tree display, re-creating buffer \"prooftree\" if
  necessary.  See also ~c[suspend-proof-tree].  With prefix argument: push the
  mark, do not modify the windows, and move point to end of ~c[*mfm-buffer*].

  ~bv[]
     C-z s               Suspend proof tree
  ~ev[]
  Freeze the contents of the \"prooftree\" buffer, until ~c[resume-proof-tree]
  is invoked.  Unlike ~c[stop-proof-tree], the only effect of
  ~c[suspend-proof-tree] is to stop putting characters into the \"prooftree\"
  buffer; in particular, strings destined for that buffer continue ~sc[not] to
  be put into the primary buffer, which is the value of the emacs variable
  ~c[*mfm-buffer*].

  ~bv[]
    C-z o                Select other frame
    C-z b                Switch to \"prooftree\" buffer
    C-z B                Switch to frame called \"prooftree-frame\"
  ~ev[]
  These commands move between buffers and frames, as indicated.  The first of
  these has nothing specifically to do with proof trees, but is handy if you
  have at least two emacs frames displayed.  The second takes you to the
  \"prooftree\" buffer (in the current frame), while the third takes you to the
  frame called \"prooftree-frame\", creating it if it does not already exist.")

(deflabel proof-tree-examples
  :doc
  ":Doc-Section Proof-tree

  proof tree example~/

  ~l[proof-tree] for an introduction to proof trees, and for a list of related
  topics.  Here we present a detailed example followed by a shorter example
  that illustrates proof by induction.~/

  Consider the ~il[guard] proof for the definition of a function
  ~c[cancel_equal_plus]; the body of this definition is of no importance
  here.  The first proof tree display is:
  ~bv[]
  ( DEFUN CANCEL_EQUAL_PLUS ...)
    18 Goal preprocess
       |  <18 subgoals>
  ~ev[]
  This is to be read as follows.
  ~bq[]
   At this stage of the proof we have encountered the top-level goal,
   named \"Goal\", which generated 18 subgoals using the
   ``preprocess'' process.  We have not yet begun to work on those
   subgoals.
  ~eq[]
  The corresponding message from the ordinary prover output is:
  ~bq[]
   By case analysis we reduce the conjecture to the following 18
   conjectures.
  ~eq[]
  Note that the field just before the name of the goal (~c[\"Goal\"]), which
  here contains the number 18, indicates the number of cases (children) created
  by the goal using the indicated process.  This number will remain unchanged
  as long as this goal is displayed.

  The next proof tree display is:
  ~bv[]
  ( DEFUN CANCEL_EQUAL_PLUS ...)
    18 Goal preprocess
     1 |  Subgoal 18 simp
       |  |  <1 subgoal>
       |  <17 more subgoals>
  ~ev[]
  which indicates that at this point, the prover has used the simplification
  (``simp'') process on Subgoal 18 to create one subgoal (``<1 subgoal>'').
  The vertical bar (``|'') below ``Subgoal 18'', accompanied by the line below
  it, signifies that there are 17 siblings of Subgoal 18 that remain to be
  processed.

  The next proof tree displayed is:
  ~bv[]
  ( DEFUN CANCEL_EQUAL_PLUS ...)
    18 Goal preprocess
     1 |  Subgoal 18 simp
  c  2 |  |  Subgoal 18' ELIM
       |  |  |  <2 subgoals>
       |  <17 more subgoals>
  ~ev[]
  Let us focus on the fourth line of this display:
  ~bv[]
  c  2 |  |  Subgoal 18' ELIM
  ~ev[]

  The ``c'' field marks this goal as a ``checkpoint'', i.e., a goal worthy of
  careful scrutiny.  In fact, any goal that creates children by a process other
  than ``preprocess'' or ``simp'' is marked as a checkpoint.  In this case, the
  destructor-elimination (``~il[ELIM]'') process has been used to create
  subgoals of this goal.  The indentation shows that this goal, Subgoal 18', is
  a child of Subgoal 18.  The number ``2'' indicates that 2 subgoals have been
  created (by ~il[ELIM]).  Note that this information is consistent with the
  line just below it, which says ``<2 subgoals>''.

  Finally, the last line of this proof tree display,
  ~bv[]
       |  <17 more subgoals>
  ~ev[]
  is connected by vertical bars (``|'') up to the string ~c[\"Subgoal 18\"],
  which suggests that there are 17 immediate subgoals of Goal remaining to
  process after Subgoal 18.  Note that this line is indented one level from the
  second line, which is the line for the goal named ~c[\"Goal\"].  The display
  is intended to suggest that the subgoals of Goal that remain to be proved
  consist of Subgoal 18 together with 17 more subgoals.

  The next proof tree display differs from the previous one only in that now,
  Subgoal 18' has only one more subgoal to be processed.
  ~bv[]
  ( DEFUN CANCEL_EQUAL_PLUS ...)
    18 Goal preprocess
     1 |  Subgoal 18 simp
  c  2 |  |  Subgoal 18' ELIM
       |  |  |  <1 more subgoal>
       |  <17 more subgoals>
  ~ev[]
  Note that the word ``more'' in ``<1 more subgoal>'' tells us that there was
  originally more than one subgoal of Subgoal 18.  In fact that information
  already follows from the line above, which (as previously explained) says
  that Subgoal 18' originally created 2 subgoals.

  The next proof tree display occurs when the prover completes the proof of
  that ``1 more subgoal'' referred to above.
  ~bv[]
  ( DEFUN CANCEL_EQUAL_PLUS ...)
    18 Goal preprocess
       |  <17 more subgoals>
  ~ev[]
  Then, Subgoal 17 is processed and creates one subgoal, by simplification:
  ~bv[]
  ( DEFUN CANCEL_EQUAL_PLUS ...)
    18 Goal preprocess
     1 |  Subgoal 17 simp
       |  |  <1 subgoal>
       |  <16 more subgoals>
  ~ev[]
  ... and so on.

  Later in the proof one might find the following successive proof tree
  displays.
  ~bv[]
  ( DEFUN CANCEL_EQUAL_PLUS ...)
    18 Goal preprocess
       |  <9 more subgoals>

  ( DEFUN CANCEL_EQUAL_PLUS ...)

    18 Goal preprocess
     0 |  Subgoal 9 simp (FORCED)
       |  <8 more subgoals>
  ~ev[]
  These displays tell us that Subgoal 9 simplified to ~c[t] (note that the
  ``0'' shows clearly that no subgoals were created), but that some rule's
  hypotheses were ~il[force]d.  Although this goal is not checkpointed (i.e.,
  no ``c'' appears on the left margin), one can cause such goals to be
  checkpointed; ~pl[checkpoint-forced-goals].

  In fact, the proof tree displayed at the end of the ``main proof''(the 0-th
  forcing round) is as follows.
  ~bv[]
  ( DEFUN CANCEL_EQUAL_PLUS ...)
    18 Goal preprocess
     0 |  Subgoal 9 simp (FORCED)
     0 |  Subgoal 8 simp (FORCED)
     0 |  Subgoal 7 simp (FORCED)
     0 |  Subgoal 6 simp (FORCED)
     0 |  Subgoal 4 simp (FORCED)
     0 |  Subgoal 3 simp (FORCED)
  ~ev[]
  This is followed by the following proof tree display at the start
  of the forcing round.
  ~bv[]
    18 Goal preprocess
     0 |  Subgoal 9 simp (FORCED [1]Subgoal 4)
     0 |  Subgoal 8 simp (FORCED [1]Subgoal 6)
     0 |  Subgoal 7 simp (FORCED [1]Subgoal 1)
     0 |  Subgoal 6 simp (FORCED [1]Subgoal 3)
     0 |  Subgoal 4 simp (FORCED [1]Subgoal 5)
     0 |  Subgoal 3 simp (FORCED [1]Subgoal 2)
  ++++++++++++++++++++++++++++++
     6 [1]Goal FORCING-ROUND
     2 |  [1]Subgoal 6 preprocess
       |  |  <2 subgoals>
       |  <5 more subgoals>
  ~ev[]
  This display shows which goals to ``blame'' for the existence of each goal in
  the forcing round.  For example, Subgoal 9 is to blame for the creation of
  [1]Subgoal 4.

  Actually, there is no real goal named ~c[\"[1~]Goal\"].  However, the line
  ~bv[]
     6 [1]Goal FORCING-ROUND
  ~ev[]
  appears in the proof tree display to suggest a ``parent'' of the six
  top-level goals in that forcing round.  As usual, the numeric field before
  the goal name contains the original number of children of that (virtual, in
  this case) goal ~-[] in this case, 6.

  In our example proof, Subgoal 6 eventually gets proved, without doing any
  further forcing.  At that point, the proof tree display looks as follows.
  ~bv[]
  ( DEFUN CANCEL_EQUAL_PLUS ...)
    18 Goal preprocess
     0 |  Subgoal 9 simp (FORCED [1]Subgoal 4)
     0 |  Subgoal 7 simp (FORCED [1]Subgoal 1)
     0 |  Subgoal 6 simp (FORCED [1]Subgoal 3)
     0 |  Subgoal 4 simp (FORCED [1]Subgoal 5)
     0 |  Subgoal 3 simp (FORCED [1]Subgoal 2)
  ++++++++++++++++++++++++++++++
     6 [1]Goal FORCING-ROUND
       |  <5 more subgoals>
  ~ev[]
  Notice that the line for Subgoal 8,
  ~bv[]
     0 |  Subgoal 8 simp (FORCED [1]Subgoal 6)
  ~ev[]
  no longer appears.  That is because the goal [1]Subgoal 6 has been proved,
  along with all its children; and hence, the proof of Subgoal 8 no longer
  depends on any further reasoning.

  The final two proof tree displays in our example are as follows.
  ~bv[]
  ( DEFUN CANCEL_EQUAL_PLUS ...)
    18 Goal preprocess
     0 |  Subgoal 7 simp (FORCED [1]Subgoal 1)
  ++++++++++++++++++++++++++++++
     6 [1]Goal FORCING-ROUND
     2 |  [1]Subgoal 1 preprocess
     1 |  |  [1]Subgoal 1.1 preprocess
     1 |  |  |  [1]Subgoal 1.1' simp
  c  3 |  |  |  |  [1]Subgoal 1.1'' ELIM
       |  |  |  |  |  <1 more subgoal>

  ( DEFUN CANCEL_EQUAL_PLUS ...)
  <<PROOF TREE IS EMPTY>>
  ~ev[]
  The explanation for the empty proof tree is simple: once [1]Subgoal 1.1.1 was
  proved, nothing further remained to be proved.  In fact, the much
  sought-after ``Q.E.D.'' appeared shortly after the final proof tree was
  displayed.

  Let us conclude with a final, brief example that illustrates proof by
  induction.  Partway through the proof one might come across the following
  proof tree display.
  ~bv[]
  ( DEFTHM PLUS-TREE-DEL ...)
     1 Goal preprocess
     2 |  Goal' simp
  c  0 |  |  Subgoal 2 PUSH *1
       |  |  <1 more subgoal>
  ~ev[]
  This display says that in the attempt to prove a theorem called
  ~c[plus-tree-del], preprocessing created the only child Goal' from Goal, and
  Goal' simplified to two subgoals.  Subgoal 2 is immediately pushed for proof
  by induction, under the name ``*1''.  In fact if Subgoal 1 simplifies to
  ~c[t], then we see the following successive proof tree displays after the one
  shown above.
  ~bv[]
  ( DEFTHM PLUS-TREE-DEL ...)
     1 Goal preprocess
     2 |  Goal' simp
  c  0 |  |  Subgoal 2 PUSH *1

  ( DEFTHM PLUS-TREE-DEL ...)
     1 Goal preprocess
     2 |  Goal' simp
  c  0 |  |  Subgoal 2 PUSH *1
  ++++++++++++++++++++++++++++++
  c  6 *1 INDUCT
       |  <5 more subgoals>
  ~ev[]
  The separator ``+++++...'' says that we are beginning another trip through
  the waterfall.  In fact this trip is for a proof by induction (as opposed to
  a forcing round), as indicated by the word ``INDUCT''.  Apparently *1.6 was
  proved immediately, because it was not even displayed; a goal is only
  displayed when there is some work left to do either on it or on some goal
  that it brought (perhaps indirectly) into existence.

  Once a proof by induction is completed, the ``PUSH'' line that refers to that
  proof is eliminated (``pruned'').  So for example, when the present proof by
  induction is completed, the line
  ~bv[]
  c  0 |  |  Subgoal 2 PUSH *1
  ~ev[]
  is eliminated, which in fact causes the lines above it to be eliminated
  (since they no longer refer to unproved children).  Hence, at that point one
  might expect to see:
  ~bv[]
  ( DEFTHM PLUS-TREE-DEL ...)
  <<PROOF TREE IS EMPTY>>
  ~ev[]
  However, if the proof by induction of *1 necessitates further proofs by
  induction or a forcing round, then this ``pruning'' will not yet be done.")

(defun start-proof-tree-fn (remove-inhibit-p state)

; Note that we do not override existing values of the indicated state global
; variables.

  (if remove-inhibit-p
      (f-put-global 'inhibit-output-lst 
                    (remove1-eq 'proof-tree
                                (f-get-global 'inhibit-output-lst state))
                    state)
    state))

#+acl2-loop-only
(defmacro start-proof-tree ()

  ":Doc-Section Proof-tree

  start displaying proof trees during proofs~/

  Also ~pl[proof-tree] and ~pl[stop-proof-tree].  Note that
  ~c[:start-proof-tree] works by removing ~c[']~ilc[proof-tree] from the
  ~c[inhibit-output-lst]; ~pl[set-inhibit-output-lst].~/

  Explanations of proof tree displays, including emacs support, may be found
  elsewhere; ~pl[proof-tree] and ~pl[proof-tree-emacs].  In a nutshell:
  ~c[:start-proof-tree] causes proof tree display to be turned on, once it has
  been turned off by ~c[:]~ilc[stop-proof-tree].

  Do not attempt to invoke ~c[start-proof-tree] during an interrupt in the
  middle of a proof."

  '(pprogn (start-proof-tree-fn t state)
           (fms "Proof tree output is now enabled.  Note that ~
                 :START-PROOF-TREE works by removing 'proof-tree from ~
                 the inhibit-output-lst; see :DOC ~
                 set-inhibit-output-lst.~%"
                nil
                (standard-co state)
                state
                nil)
           (value :invisible)))

#-acl2-loop-only
(defmacro start-proof-tree ()
  '(let ((state *the-live-state*))
     (fms "IT IS ILLEGAL to invoke (START-PROOF-TREE) from raw Lisp.  Please ~
           first enter the ACL2 command loop with (LP)."
          nil
          (proofs-co state)
          state
          nil)
     (values)))

(defmacro checkpoint-forced-goals (val)

  ":Doc-Section Proof-tree

  Cause forcing goals to be checkpointed in proof trees~/
  ~bv[]
  Example forms:
  (checkpoint-forced-goals t)
  (checkpoint-forced-goals nil)
  ~ev[]
  Also ~pl[proof-tree].~/

  By default, goals are not marked as checkpoints by a proof tree display (as
  described elsewhere; ~pl[proof-tree]) merely because they ~il[force] some
  hypotheses, thus possibly contributing to a forcing round.  However, some
  users may want such behavior, which will occur once the command
  ~c[(checkpoint-forced-goals] ~c[t]) has been executed.  To return to the
  default behavior, use the command ~c[(checkpoint-forced-goals nil)]."

  `(pprogn (f-put-global 'checkpoint-forced-goals ',val state)
           (value ',val)))

(defun stop-proof-tree-fn (state)
  (f-put-global 'inhibit-output-lst 
                (add-to-set-eq 'proof-tree
                               (f-get-global 'inhibit-output-lst state))
                state))

(defmacro stop-proof-tree ()

  ":Doc-Section Proof-tree

  stop displaying proof trees during proofs~/

  Also ~pl[proof-tree] and ~pl[start-proof-tree].  Note that
  ~c[:stop-proof-tree] works by adding ~c[']~ilc[proof-tree] to the
  ~c[inhibit-output-lst]; ~pl[set-inhibit-output-lst].~/

  Proof tree displays are explained in the documentation for ~il[proof-tree].
  ~c[:Stop-proof-tree] causes proof tree display to be turned off.

  It is permissible to submit the form ~c[(stop-proof-tree)] during a break.
  Thus, you can actually turn off proof tree display in the middle of a proof
  by interrupting ACL2 and submitting the form ~c[(stop-proof-tree)] in raw
  Lisp."

  '(pprogn (stop-proof-tree-fn state)
           (fms "Proof tree output is now inhibited.  Note that ~
                 :STOP-PROOF-TREE works by adding 'proof-tree to the ~
                 inhibit-output-lst; see :DOC set-inhibit-output-lst.~%"
                nil
                (standard-co state)
                state
                nil)
           (value :invisible)))

(deflabel proof-tree-details
  :doc
  ":Doc-Section Proof-tree

  proof tree details not covered elsewhere~/

  ~l[proof-tree] for an introduction to proof trees, and for a list of related
  topics.  Here we present some details not covered elsewhere.~/

  1.  When proof tree display is enabled (because the command
  ~c[:]~ilc[stop-proof-tree] has not been executed, or has been superseded by a
  later ~c[:]~ilc[start-proof-tree] command), then time summaries will include
  the time for proof tree display.  This time includes the time spent computing
  with proof trees, such as the pruning process described briefly above.  Even
  when proof trees are not displayed, such as when their display is turned off
  in the middle of a proof, this time will be printed if it is not 0.

  2.  When a goal is given a ~c[:bye] in a proof (~pl[hints]), it is treated
  for the purpose of proof tree display just as though it had been proved.

  3.  Several ~il[state] global variables affect proof tree display.
  ~c[(@ proof-tree-indent)] is initially the string ~c[\"| \"]:  it is
  the string that is laid down the appropriate number of times to effect
  indentation.  ~c[(@ proof-tree-buffer-width)] is initially the value of
  ~c[(fmt-soft-right-margin state)], and is used to prevent printing of the
  annotation ``(~il[force]d ...)'' in any greater column than this value.
  However, ~c[(assign proof-tree-buffer-width nil)] to avoid any such
  suppression.  Finally, ~c[(@ checkpoint-processors)] is a list of processors
  from the constant list ~c[*preprocess-clause-ledge*], together with
  ~c[:induct].  You may remove elements of ~c[(@ checkpoint-processors)] to
  limit which processes are considered checkpoints, but note that this can
  affect what is printed by gag-mode (~pl[set-gag-mode]).

  4.  When ~c[:]~ilc[otf-flg] is not set to ~c[t] in a proof, and the prover
  then decides to revert to the original goal and prove it by induction, the
  proof tree display will reflect this fact as shown here:
  ~bv[]
  c  0 |  |  Subgoal 2 PUSH (reverting)
  ~ev[]

  5. The usual ~il[failure] message is printed as part of the prooftree display
  when a proof has failed.")

(mutual-recursion

(defun insert-into-goal-tree-rec (cl-id processor n goal-tree)
  (let ((new-children (insert-into-goal-tree-lst
                       cl-id processor n
                       (access goal-tree goal-tree :children))))
    (and new-children
         (change goal-tree goal-tree
                 :children new-children))))

(defun insert-into-goal-tree-lst (cl-id processor n goal-tree-lst)
  (cond
   ((consp goal-tree-lst)
    (let ((new-child (insert-into-goal-tree-rec
                      cl-id processor n (car goal-tree-lst))))
      (if new-child
          (cons new-child (cdr goal-tree-lst))
        (let ((rest-children (insert-into-goal-tree-lst
                              cl-id processor n (cdr goal-tree-lst))))
          (if rest-children
              (cons (car goal-tree-lst) rest-children)
            nil)))))
   ((integerp goal-tree-lst)
    (cons (make goal-tree
                :cl-id cl-id
                :processor processor
                :children n
                :fanout (or n 0))
          (if (eql goal-tree-lst 1)
              nil
            (1- goal-tree-lst))))
   (t nil)))
)

(defun insert-into-goal-tree (cl-id processor n goal-tree)

; This function updates the indicated goal-tree by adding a new goal tree built
; from cl-id, processor, and n, in place of the first integer "children" field
; of a subgoal in a left-to-right depth-first traversal of the goal-tree.
; (Recall that an integer represents the number of unproved children remaining;
; hence the first integer found corresponds to the goal that corresponds to the
; parameters of this function.)  However, we return nil if no integer
; "children" field is found; similarly for the -rec and -lst versions, above.

; Note that n should be nil or a (strictly) positive integer.  Also note that
; when cl-id is *initial-clause-id*, then goal-tree doesn't matter (for
; example, it may be nil).

  (cond
   ((equal cl-id *initial-clause-id*)
    (make goal-tree
          :cl-id cl-id
          :processor processor
          :children n
          :fanout (or n 0)))
   (t (insert-into-goal-tree-rec cl-id processor n goal-tree))))

(defun set-difference-equal-changedp (l1 l2)

; Like set-difference-equal, but returns (mv changedp lst) where lst is the set
; difference and changedp is t iff the set difference is not equal to l1.

  (declare (xargs :guard (and (true-listp l1)
                              (true-listp l2))))
  (cond ((endp l1) (mv nil nil))
        (t (mv-let (changedp lst)
                   (set-difference-equal-changedp (cdr l1) l2)
                   (cond
                    ((member-equal (car l1) l2)
                     (mv t lst))
                    (changedp (mv t (cons (car l1) lst)))
                    (t (mv nil l1)))))))

(mutual-recursion

(defun prune-goal-tree (forcing-round dead-clause-ids goal-tree)

; Removes all proved goals from a goal tree, where all dead-clause-ids are
; considered proved.  Actually returns two values:  a new goal tree (or nil),
; and a new (extended) list of dead-clause-ids.

; Goals with processor (push-clause id . x) are handled similarly to forced
; goals, except that we know that there is a unique child.

; Note that a non-nil final cdr prevents a goal from being considered proved
; (unless its clause-id is dead, which shouldn't happen), which is appropriate.

  (let* ((processor (access goal-tree goal-tree :processor))
         (cl-id (access goal-tree goal-tree :cl-id))
         (goal-forcing-round (access clause-id cl-id :forcing-round)))
    (cond ((member-equal cl-id dead-clause-ids)
           (mv (er hard 'prune-goal-tree
                   "Surprise!  We didn't think this case could occur.")
               dead-clause-ids))
          ((and (not (= forcing-round goal-forcing-round))

; So, current goal is from a previous forcing round.

                (consp processor)
                (eq (cadr processor) :forced))

; So, processor is of the form (pr :forced clause-id_1 ... clause-id_n).

           (mv-let
            (changedp forced-clause-ids) 
            (set-difference-equal-changedp (cddr processor) dead-clause-ids)
            (cond
             ((null forced-clause-ids)
              (mv nil (cons cl-id dead-clause-ids)))

; Notice that goal-tree may have children, even though it comes from an earlier
; forcing round, because it may have generated children that themselves did
; some forcing.

             (t
              (mv-let
               (children new-dead-clause-ids)
               (prune-goal-tree-lst
                forcing-round
                dead-clause-ids
                (access goal-tree goal-tree :children))
               (cond
                (changedp
                 (mv (change goal-tree goal-tree
                             :processor
                             (list* (car processor) :forced forced-clause-ids)
                             :children children)
                     new-dead-clause-ids))
                (t (mv (change goal-tree goal-tree
                               :children children)
                       new-dead-clause-ids))))))))
          ((and (consp processor)
                (eq (car processor) 'push-clause))
           (assert$
            (null (access goal-tree goal-tree :children))

; It is tempting also to assert (null (cddr processor)), i.e., that we have not
; reverted or aborted.  But that can fail for a branch of a disjunctive (:or)
; split.

            (if (member-equal (cadr processor) dead-clause-ids)
                (mv nil (cons cl-id dead-clause-ids))
              (mv goal-tree dead-clause-ids))))
          (t
           (mv-let (children new-dead-clause-ids)
                   (prune-goal-tree-lst forcing-round
                                        dead-clause-ids
                                        (access goal-tree goal-tree :children))
                   (cond
                    ((or children

; Note that the following test implies that we're in the current forcing round,
; and hence "decoration" (adding a list of new goals created by that forcing)
; has not yet been done.

                         (and (consp processor)
                              (eq (cadr processor) :forced)))
                     (mv (change goal-tree goal-tree
                                 :children children)
                         new-dead-clause-ids))
                    (t (mv nil (cons cl-id new-dead-clause-ids)))))))))

(defun prune-goal-tree-lst (forcing-round dead-clause-ids goal-tree-lst)
  (cond
   ((consp goal-tree-lst)
    (mv-let (x new-dead-clause-ids)
            (prune-goal-tree forcing-round dead-clause-ids (car goal-tree-lst))
            (if x
                (mv-let (rst newer-dead-clause-ids)
                        (prune-goal-tree-lst
                         forcing-round new-dead-clause-ids (cdr goal-tree-lst))
                        (mv (cons x rst)
                            newer-dead-clause-ids))
              (prune-goal-tree-lst
               forcing-round new-dead-clause-ids (cdr goal-tree-lst)))))
   (t (mv goal-tree-lst dead-clause-ids))))

)

(defun prune-proof-tree (forcing-round dead-clause-ids proof-tree)
  (if (null proof-tree)
      nil
    (mv-let (new-goal-tree new-dead-clause-ids)
            (prune-goal-tree forcing-round dead-clause-ids (car proof-tree))
            (if new-goal-tree
                (cons new-goal-tree
                      (prune-proof-tree forcing-round
                                        new-dead-clause-ids
                                        (cdr proof-tree)))
              (prune-proof-tree forcing-round
                                new-dead-clause-ids
                                (cdr proof-tree))))))

(defun print-string-repeat (increment level col channel state)
  (declare (type (signed-byte 30) col level))
  (the2s
   (signed-byte 30)
   (if (= level 0)
       (mv col state)
     (mv-letc (col state)
              (fmt1 "~s0"
                    (list (cons #\0 increment))
                    col channel state nil)
              (print-string-repeat increment (1-f level) col channel state)))))

(defconst *format-proc-alist*
  '((apply-top-hints-clause-or-hit . ":OR")
    (apply-top-hints-clause . "top-level-hints")
    (preprocess-clause . "preprocess")
    (simplify-clause . "simp")
    ;;settled-down-clause
    (eliminate-destructors-clause . "ELIM")
    (fertilize-clause . "FERT")
    (generalize-clause . "GEN")
    (eliminate-irrelevance-clause . "IRREL")
    ;;push-clause
    ))

(defun format-forced-subgoals (clause-ids col max-col channel state)

; Print the "(FORCED ...)" annotation, e.g., the part after "(FORCED" on this
; line:

;   0 |  Subgoal 3 simp (FORCED [1]Subgoal 1)

  (cond
   ((null clause-ids)
    (princ$ ")" channel state))
   (t (let ((goal-name (string-for-tilde-@-clause-id-phrase (car clause-ids))))
        (if (or (null max-col)

; We must leave room for final " ...)" if there are more goals, in addition to
; the space, the goal name, and the comma.  Otherwise, we need room for the
; space and the right paren.

                (if (null (cdr clause-ids))
                    (<= (+ 2 col (length goal-name)) max-col)
                  (<= (+ 7 col (length goal-name)) max-col)))
            (mv-let (col state)
                    (fmt1 " ~s0~#1~[~/,~]"
                          (list (cons #\0 goal-name)
                                (cons #\1 clause-ids))
                          col channel state nil)
                    (format-forced-subgoals
                     (cdr clause-ids) col max-col channel state))
          (princ$ " ...)" channel state))))))

(defun format-processor (col goal-tree channel state)
  (let ((proc (access goal-tree goal-tree :processor)))
    (cond
     ((consp proc)
      (cond
       ((eq (car proc) 'push-clause)
        (mv-let
         (col state)
         (fmt1 "~s0 ~@1"
               (list (cons #\0 "PUSH")
                     (cons #\1
                           (cond
                            ((eq (caddr proc) :REVERT)
                             "(reverting)")
                            ((eq (caddr proc) :ABORT)
                             "*ABORTING*")
                            (t
                             (tilde-@-pool-name-phrase
                              (access clause-id
                                      (cadr proc) 
                                      :forcing-round)
                              (access clause-id
                                      (cadr proc) 
                                      :pool-lst))))))
               col channel state nil)
         (declare (ignore col))
         state))
       ((eq (cadr proc) :forced)
        (mv-let (col state)
                (fmt1 "~s0 (FORCED"

; Note that (car proc) is in *format-proc-alist*, because neither push-clause
; nor either of the "fake" processors (:INDUCT, :FORCING-ROUND) forces in the
; creation of subgoals.

                      (list (cons #\0 (cdr (assoc-eq (car proc)
                                                     *format-proc-alist*))))
                      col channel state nil)
                (format-forced-subgoals
                 (cddr proc) col
                 (f-get-global 'proof-tree-buffer-width state)
                 channel state)))
       (t (let ((err (er hard 'format-processor
                         "Unexpected shape for goal-tree processor, ~x0"
                         proc)))
            (declare (ignore err))
            state))))
     (t (princ$ (or (cdr (assoc-eq proc *format-proc-alist*))
                    proc)
                channel state)))))

(mutual-recursion

(defun format-goal-tree-lst
  (goal-tree-lst level fanout increment checkpoints
                 checkpoint-forced-goals channel state)
  (cond
   ((null goal-tree-lst)
    state)
   ((atom goal-tree-lst)
    (mv-let (col state)
            (pprogn (princ$ "     " channel state)
                    (print-string-repeat
                     increment
                     (the-fixnum! level 'format-goal-tree-lst)
                     5 channel state))
            (mv-let (col state)
                    (fmt1 "<~x0 ~#1~[~/more ~]subgoal~#2~[~/s~]>~%"
                          (list (cons #\0 goal-tree-lst)
                                (cons #\1 (if (= fanout goal-tree-lst) 0 1))
                                (cons #\2 (if (eql goal-tree-lst 1)
                                              0
                                            1)))
                          col channel state nil)
                    (declare (ignore col))
                    state)))
   (t
    (pprogn
     (format-goal-tree
      (car goal-tree-lst) level increment checkpoints
      checkpoint-forced-goals channel state)
     (format-goal-tree-lst
      (cdr goal-tree-lst) level fanout increment checkpoints
      checkpoint-forced-goals channel state)))))

(defun format-goal-tree (goal-tree level increment checkpoints
                                   checkpoint-forced-goals channel state)
  (let* ((cl-id (access goal-tree goal-tree :cl-id))
         (pool-lst (access clause-id cl-id :pool-lst))
         (fanout (access goal-tree goal-tree :fanout))
         (raw-processor (access goal-tree goal-tree :processor))
         (processor (if (atom raw-processor)
                        raw-processor
                      (car raw-processor))))
    (mv-letc
     (col state)
     (pprogn (mv-letc
              (col state)
              (fmt1 "~#0~[c~/ ~]~c1 "
                    (list (cons #\0 (if (or (member-eq processor checkpoints)
                                            (and checkpoint-forced-goals
                                                 (consp raw-processor)
                                                 (eq (cadr raw-processor)
                                                     :forced)))
                                        0
                                      1))
                          (cons #\1 (cons fanout 3)))
                    0 channel state nil)
              (print-string-repeat increment
                                   (the-fixnum! level 'format-goal-tree)
                                   col channel state)))
     (mv-letc
      (col state)
      (if (and (null (access clause-id cl-id :case-lst))
               (= (access clause-id cl-id :primes) 0)
               pool-lst)
          (fmt1 "~@0 "
                (list (cons #\0 (tilde-@-pool-name-phrase
                                 (access clause-id cl-id :forcing-round)
                                 pool-lst)))
                col channel state nil)
        (fmt1 "~@0 "
              (list (cons #\0 (tilde-@-clause-id-phrase cl-id)))
              col channel state nil))
      (pprogn
       (format-processor col goal-tree channel state)
       (pprogn
        (newline channel state)
        (format-goal-tree-lst
         (access goal-tree goal-tree :children)
         (1+ level) fanout increment checkpoints checkpoint-forced-goals
         channel state)))))))

)

(defun format-proof-tree (proof-tree-rev increment checkpoints
                                         checkpoint-forced-goals channel state)

; Recall that most recent forcing rounds correspond to the goal-trees closest
; to the front of a proof-tree.  But here, proof-tree-rev is the reverse of a
; proof-tree.

  (if (null proof-tree-rev)
      state
    (pprogn (format-goal-tree
             (car proof-tree-rev) 0 increment checkpoints
             checkpoint-forced-goals channel state)
            (if (null (cdr proof-tree-rev))
                state
              (mv-let (col state)
                      (fmt1 "++++++++++++++++++++++++++++++~%"
                            (list (cons #\0 increment))
                            0 channel state nil)
                      (declare (ignore col))
                      state))
            (format-proof-tree
             (cdr proof-tree-rev) increment checkpoints
             checkpoint-forced-goals channel state))))

(defun print-proof-tree1 (ctx channel state)
  (let ((proof-tree (f-get-global 'proof-tree state)))
    (if (null proof-tree)
        (if (and (consp ctx) (eq (car ctx) :failed))
            state
          (princ$ "Q.E.D." channel state))
      (format-proof-tree (reverse proof-tree)
                         (f-get-global 'proof-tree-indent state)
                         (f-get-global 'checkpoint-processors state)
                         (f-get-global 'checkpoint-forced-goals state)
                         channel
                         state))))

(defconst *proof-failure-string*
  "******** FAILED ********~|")

(defun print-proof-tree-ctx (ctx channel state)
  (let* ((failed-p (and (consp ctx) (eq (car ctx) :failed)))
         (actual-ctx (if failed-p (cdr ctx) ctx)))
    (mv-let
     (erp val state)
     (state-global-let*
      ((fmt-hard-right-margin 1000 set-fmt-hard-right-margin)
       (fmt-soft-right-margin 1000 set-fmt-soft-right-margin))

; We need the event name to fit on a single line, hence the state-global-let*
; above.

      (mv-let (col state)
              (fmt-ctx actual-ctx 0 channel state)
              (mv-let
               (col state)
               (fmt1 "~|~@0"
                     (list (cons #\0
                                 (if failed-p *proof-failure-string* "")))
                     col channel state nil)
               (declare (ignore col))
               (value nil))))
     (declare (ignore erp val))
     state)))

(defconst *proof-tree-start-delimiter* "#<\\<0")

(defconst *proof-tree-end-delimiter* "#>\\>")

(defun print-proof-tree-finish (state)
  (if (f-get-global 'proof-tree-start-printed state)
      (pprogn (mv-let (col state)
                      (fmt1! "~s0"
                             (list (cons #\0 *proof-tree-end-delimiter*))
                             0 (proofs-co state) state nil)
                      (declare (ignore col))
                      (f-put-global 'proof-tree-start-printed nil state)))
    state))

(defun print-proof-tree (state)

; WARNING: Every call of print-proof-tree should be underneath some call of the
; form (io? ...).  We thus avoid enclosing the body below with (io? proof-tree
; ...).

  (let ((chan (proofs-co state))
        (ctx (f-get-global 'proof-tree-ctx state)))
    (pprogn
     (if (f-get-global 'window-interfacep state)
         state
       (pprogn
        (f-put-global 'proof-tree-start-printed t state)
        (mv-let (col state)
                (fmt1 "~s0"
                      (list (cons #\0 *proof-tree-start-delimiter*))
                      0 chan state nil)
                (declare (ignore col)) ;print-proof-tree-ctx starts with newline
                state)))
     (print-proof-tree-ctx ctx chan state)
     (print-proof-tree1 ctx chan state)
     (print-proof-tree-finish state))))

(mutual-recursion

(defun decorate-forced-goals-1 (goal-tree clause-id-list forced-clause-id)
  (let ((cl-id (access goal-tree goal-tree :cl-id))
        (new-children (decorate-forced-goals-1-lst
                       (access goal-tree goal-tree :children)
                       clause-id-list
                       forced-clause-id)))
    (cond
     ((member-equal cl-id clause-id-list)
      (let ((processor (access goal-tree goal-tree :processor)))
        (change goal-tree goal-tree
                :processor
                (list* (car processor) :forced forced-clause-id (cddr processor))
                :children new-children)))
     (t
      (change goal-tree goal-tree
              :children new-children)))))

(defun decorate-forced-goals-1-lst
  (goal-tree-lst clause-id-list forced-clause-id)
  (cond
   ((null goal-tree-lst)
    nil)
   ((atom goal-tree-lst)

; By the time we've gotten this far, we've gotten to the next forcing round,
; and hence there shouldn't be any children remaining to process.  Of course, a
; forced goal can generate forced subgoals, so we can't say that there are no
; children -- but we CAN say that there are none remaining to process.

    (er hard 'decorate-forced-goals-1-lst
        "Unexpected goal-tree in call ~x0"
        (list 'decorate-forced-goals-1-lst
              goal-tree-lst
              clause-id-list
              forced-clause-id)))
   (t (cons (decorate-forced-goals-1
             (car goal-tree-lst) clause-id-list forced-clause-id)
            (decorate-forced-goals-1-lst
             (cdr goal-tree-lst) clause-id-list forced-clause-id)))))

)

(defun decorate-forced-goals (forcing-round goal-tree clause-id-list-list n)

; See decorate-forced-goals-in-proof-tree.

  (if (null clause-id-list-list)
      goal-tree
    (decorate-forced-goals
     forcing-round
     (decorate-forced-goals-1 goal-tree
                              (car clause-id-list-list)
                              (make clause-id
                                    :forcing-round forcing-round
                                    :pool-lst nil
                                    :case-lst (and n (list n))
                                    :primes 0))
     (cdr clause-id-list-list)
     (and n (1- n)))))

(defun decorate-forced-goals-in-proof-tree
  (forcing-round proof-tree clause-id-list-list n)

; This function decorates the goal trees in proof-tree so that the appropriate
; previous forcing round's goals are "blamed" for the new forcing round goals.
; See also extend-proof-tree-for-forcing-round.

; At the top level, n is either an integer greater than 1 or else is nil.  This
; corresponds respectively to whether or not there is more than one goal
; produced by the forcing round.

  (if (null proof-tree)
      nil
    (cons (decorate-forced-goals
           forcing-round (car proof-tree) clause-id-list-list n)
          (decorate-forced-goals-in-proof-tree
           forcing-round (cdr proof-tree) clause-id-list-list n))))

(defun assumnote-list-to-clause-id-list (assumnote-list)
  (if (null assumnote-list)
      nil
    (cons (access assumnote (car assumnote-list) :cl-id)
          (assumnote-list-to-clause-id-list (cdr assumnote-list)))))

(defun assumnote-list-list-to-clause-id-list-list (assumnote-list-list)
  (if (null assumnote-list-list)
      nil
    (cons (assumnote-list-to-clause-id-list (car assumnote-list-list))
          (assumnote-list-list-to-clause-id-list-list (cdr assumnote-list-list)))))

(defun extend-proof-tree-for-forcing-round
  (forcing-round parent-clause-id clause-id-list-list state)

; This function pushes a new goal tree onto the global proof-tree.  However, it
; decorates the existing goal trees so that the appropriate previous forcing
; round's goals are "blamed" for the new forcing round goals.  Specifically, a
; previous goal with clause id in a member of clause-id-list-list is blamed for
; creating the appropriate newly-forced goal, with (car clause-id-list-list)
; associated with the highest-numbered (first) forced goal, etc.

  (cond
   ((null clause-id-list-list)

; then the proof is complete!

    state)
   (t
    (let ((n (length clause-id-list-list))) ;note n>0
      (f-put-global
       'proof-tree
       (cons (make goal-tree
                   :cl-id parent-clause-id
                   :processor :FORCING-ROUND
                   :children n
                   :fanout n)
             (decorate-forced-goals-in-proof-tree
              forcing-round
              (f-get-global 'proof-tree state)
              clause-id-list-list
              (if (null (cdr clause-id-list-list))
                  nil
                (length clause-id-list-list))))
       state)))))

(defun initialize-proof-tree1 (parent-clause-id x pool-lst forcing-round ctx
                                                state)

; X is from the "x" argument of waterfall.  Thus, if we are starting a forcing
; round then x is list of pairs (assumnote-lst . clause) where the clause-ids
; from the assumnotes are the names of goals from the preceding forcing round
; to "blame" for the creation of that clause.

  (pprogn

; The user might have started up proof trees with something like (assign
; inhibit-output-lst nil).  In that case we need to ensure that appropriate
; state globals are initialized.  Note that start-proof-tree-fn does not
; override existing bindings of those state globals (which the user may have
; deliberately set).

   (start-proof-tree-fn nil state)
   (f-put-global 'proof-tree-ctx ctx state)
   (cond
    ((and (null pool-lst)
          (eql forcing-round 0))
     (f-put-global 'proof-tree nil state))
    (pool-lst
     (f-put-global 'proof-tree
                   (cons (let ((n (length x)))
                           (make goal-tree
                                 :cl-id parent-clause-id
                                 :processor :INDUCT
                                 :children (if (= n 0) nil n)
                                 :fanout n))
                         (f-get-global 'proof-tree state))
                   state))
    (t
     (extend-proof-tree-for-forcing-round
      forcing-round parent-clause-id
      (assumnote-list-list-to-clause-id-list-list (strip-cars x))
      state)))))

(defun initialize-proof-tree (parent-clause-id x ctx state)

; X is from the "x" argument of waterfall.  See initialize-proof-tree1.

; We assume (not (output-ignored-p 'proof-tree state)).

  (let ((pool-lst (access clause-id parent-clause-id :pool-lst))
        (forcing-round (access clause-id parent-clause-id
                               :forcing-round)))
    (pprogn
     (io? proof-tree nil state
          (ctx forcing-round pool-lst x parent-clause-id)
          (initialize-proof-tree1 parent-clause-id x pool-lst forcing-round ctx
                                  state))
     (io? prove nil state
          (forcing-round pool-lst)
          (cond ((intersectp-eq '(prove proof-tree)
                                (f-get-global 'inhibit-output-lst state))
                 state)
                ((and (null pool-lst)
                      (eql forcing-round 0))
                 (fms "<< Starting proof tree logging >>~|"
                      nil (proofs-co state) state nil))
                (t state))))))

(defconst *star-1-clause-id*
  (make clause-id
        :forcing-round 0
        :pool-lst '(1)
        :case-lst nil
        :primes 0))

(mutual-recursion

(defun revert-goal-tree-rec (cl-id revertp goal-tree)

; See revert-goal-tree.  This nest also returns a value cl-id-foundp, which is
; nil if the given cl-id was not found in goal-tree or any subsidiary goal
; trees, else :or-found if cl-id is found under a disjunctive split, else t.

  (let ((processor (access goal-tree goal-tree :processor)))
    (cond
     ((and (consp processor)
           (eq (car processor) 'push-clause))
      (mv (equal cl-id (access goal-tree goal-tree :cl-id))
          (if revertp
              (change goal-tree goal-tree
                      :processor
                      (list 'push-clause *star-1-clause-id* :REVERT))
            goal-tree)))
     (t (mv-let (cl-id-foundp new-children)
                (revert-goal-tree-lst (eq processor
                                          'apply-top-hints-clause-or-hit)
                                      cl-id
                                      revertp
                                      (access goal-tree goal-tree :children))
                (mv cl-id-foundp
                    (change goal-tree goal-tree :children new-children)))))))

(defun revert-goal-tree-lst (or-p cl-id revertp goal-tree-lst)

; Or-p is true if we want to limit changes to the member of goal-tree-lst that
; is, or has a subsidiary, goal-tree for cl-id.

  (cond
   ((atom goal-tree-lst)
    (mv nil nil))
   (t (mv-let (cl-id-foundp new-goal-tree)
              (revert-goal-tree-rec cl-id revertp (car goal-tree-lst))
              (cond ((or (eq cl-id-foundp :or-found)
                         (and cl-id-foundp or-p))
                     (mv :or-found
                         (cons new-goal-tree (cdr goal-tree-lst))))
                    (t (mv-let (cl-id-foundp2 new-goal-tree-lst)
                               (revert-goal-tree-lst or-p
                                                     cl-id
                                                     revertp
                                                     (cdr goal-tree-lst))
                               (mv (or cl-id-foundp2 cl-id-foundp)
                                   (cons (if (eq cl-id-foundp2 :or-found)
                                             (car goal-tree-lst)
                                           new-goal-tree)
                                         new-goal-tree-lst)))))))))

)

(defun revert-goal-tree (cl-id revertp goal-tree)

; If there are no disjunctive (:or) splits, this function replaces every final
; cdr of any :children field of each subsidiary goal tree (including goal-tree)
; by nil, for other than push-clause processors, indicating that there are no
; children left to consider proving.  If revertp is true, it also replaces each
; (push-clause *n) with (push-clause *star-1-clause-id* :REVERT), meaning that
; we are reverting.

; The spec in the case of disjunctive splits is similar, except that if cl-id
; is under such a split, then the changes described above are limited to the
; innermost disjunct containing cl-id.

  (mv-let (cl-id-foundp new-goal-tree)
          (revert-goal-tree-rec cl-id revertp goal-tree)
          (assert$ cl-id-foundp
                   new-goal-tree)))

; The pool is a list of pool-elements, as shown below.  We explain
; in push-clause.

(defrec pool-element (tag clause-set . hint-settings) t)

(defun pool-lst1 (pool n ans)
  (cond ((null pool) (cons n ans))
        ((eq (access pool-element (car pool) :tag)
             'to-be-proved-by-induction)
         (pool-lst1 (cdr pool) (1+ n) ans))
        (t (pool-lst1 (cdr pool) 1 (cons n ans)))))

(defun pool-lst (pool)

; Pool is a pool as constructed by push-clause.  That is, it is a list
; of pool-elements and the tag of each is either 'to-be-proved-by-
; induction or 'being-proved-by-induction.  Generally when we refer to
; a pool-lst we mean the output of this function, which is a list of
; natural numbers.  For example, '(3 2 1) is a pool-lst and *3.2.1 is
; its printed representation.

; If one thinks of the pool being divided into gaps by the
; 'being-proved-by-inductions (with gaps at both ends) then the lst
; has as many elements as there are gaps and the ith element, k, in
; the lst tells us there are k-1 'to-be-proved-by-inductions in the
; ith gap.

; Warning: It is assumed that the value of this function is always
; non-nil.  See the use of "jppl-flg" in the waterfall and in
; pop-clause.

  (pool-lst1 pool 1 nil))

(defun increment-proof-tree
  (cl-id ttree processor clause-count new-hist signal pspv state)

; Modifies the global proof-tree so that it incorporates the given cl-id, which
; creates n child goals via processor.  Also prints out the proof tree.

  (if (or (eq processor 'settled-down-clause)
          (and (consp new-hist)
               (consp (access history-entry (car new-hist)
                              :processor))))
      state
    (let* ((forcing-round (access clause-id cl-id :forcing-round))
           (aborting-p (and (eq signal 'abort)
                            (not (eq (cdr (tagged-object 'abort-cause ttree))
                                     'revert))))
           (clause-count
            (cond ((eq signal 'or-hit)
                   (assert$
                    (eq processor 'apply-top-hints-clause)
                    (length (nth 2 (cdr (tagged-object :or ttree))))))
                  (t clause-count)))
           (processor
            (cond
             ((tagged-object 'assumption ttree)
              (assert$ (and (not (eq processor 'push-clause))
                            (not (eq signal 'or-hit)))
                       (list processor :forced)))
             ((eq processor 'push-clause)
              (list* 'push-clause
                     (make clause-id
                           :forcing-round forcing-round
                           :pool-lst
                           (pool-lst
                            (cdr (access prove-spec-var pspv
                                         :pool)))
                           :case-lst nil
                           :primes 0)
                     (if aborting-p '(:ABORT) nil)))
             ((eq signal 'or-hit)
              'apply-top-hints-clause-or-hit)
             (t processor)))
           (starting-proof-tree (f-get-global 'proof-tree state))
           (new-goal-tree
            (insert-into-goal-tree cl-id
                                   processor
                                   (if (eql clause-count 0)
                                       nil
                                     clause-count)
                                   (car starting-proof-tree))))
      (pprogn
       (if new-goal-tree
           (f-put-global 'proof-tree
                         (if (and (consp processor)
                                  (eq (car processor) 'push-clause)
                                  (eq signal 'abort)
                                  (not aborting-p))
                             (if (and (= forcing-round 0)
                                      (null (cdr starting-proof-tree)))
                                 (list (revert-goal-tree cl-id t new-goal-tree))
                               (er hard 'increment-proof-tree
                                   "Internal Error: Attempted to ``revert'' ~
                                    the proof tree with forcing round ~x0 and ~
                                    proof tree of length ~x1.  This reversion ~
                                    should only have been tried with forcing ~
                                    round 0 and proof tree of length 1.  ~
                                    Please contact the ACL2 implementors."
                                   forcing-round
                                   (length starting-proof-tree)))
                           (prune-proof-tree
                            forcing-round nil
                            (cons (if (eq signal 'abort)
                                      (revert-goal-tree cl-id
                                                        nil
                                                        new-goal-tree)
                                    new-goal-tree)
                                  (cdr starting-proof-tree))))
                         state)
         (prog2$ (er hard 'increment-proof-tree
                     "Found empty goal tree from call ~x0"
                     (list 'insert-into-goal-tree
                           cl-id
                           processor
                           (if (= clause-count 0)
                               nil
                             clause-count)
                           (car starting-proof-tree)))
                 state))
       (print-proof-tree state)))))

(defun goal-tree-with-cl-id (cl-id goal-tree-lst)
  (cond ((atom goal-tree-lst)
         nil)
        ((equal cl-id (access goal-tree (car goal-tree-lst) :cl-id))
         (car goal-tree-lst))
        (t (goal-tree-with-cl-id cl-id (cdr goal-tree-lst)))))

(mutual-recursion

(defun goal-tree-choose-disjunct-rec (cl-id disjunct-cl-id goal-tree)

; This is the recursive version of goal-tree-choose-disjunct.  It either
; returns (mv nil goal-tree) without any change to the given goal-tree, or else
; it returns (mv t new-goal-tree) where new-goal-tree is not equal to
; goal-tree.

  (let ((children (access goal-tree goal-tree :children)))
    (cond
     ((equal cl-id (access goal-tree goal-tree :cl-id))
      (assert$
       (eq (access goal-tree goal-tree :processor)
           'apply-top-hints-clause-or-hit)
       (let ((child (goal-tree-with-cl-id disjunct-cl-id children)))
         (mv t
             (cond (child
                    (change goal-tree goal-tree
                            :children (list child)))
                   (t ; child was proved
                    (change goal-tree goal-tree
                            :children nil)))))))
     ((atom children) (mv nil goal-tree)) ; optimization
     (t (mv-let
         (found new-children)
         (goal-tree-choose-disjunct-lst cl-id disjunct-cl-id children)
         (cond (found (mv t (change goal-tree goal-tree
                                    :children new-children)))
               (t (mv nil goal-tree))))))))

(defun goal-tree-choose-disjunct-lst (cl-id disjunct-cl-id goal-tree-lst)
  (cond ((consp goal-tree-lst)
         (mv-let (found new-goal-tree)
                 (goal-tree-choose-disjunct-rec
                  cl-id disjunct-cl-id (car goal-tree-lst))
                 (cond (found (mv t (cons new-goal-tree (cdr goal-tree-lst))))
                       (t (mv-let (found new-goal-tree-lst)
                                  (goal-tree-choose-disjunct-lst
                                   cl-id disjunct-cl-id (cdr goal-tree-lst))
                                  (cond (found (mv t (cons (car goal-tree-lst)
                                                           new-goal-tree-lst)))
                                        (t (mv nil goal-tree-lst))))))))
        (t (mv nil goal-tree-lst))))
)

(defun goal-tree-choose-disjunct (cl-id disjunct-cl-id goal-tree)

; Replace the subtree at the goal-tree with the given cl-id with the subtree at
; its child having the given disjunct-cl-id, but eliminating the extra "D" case
; from every clause id in that subtree.

  (mv-let (foundp new-goal-tree)
          (goal-tree-choose-disjunct-rec cl-id disjunct-cl-id goal-tree)
          (assert$ foundp
                   new-goal-tree)))

(defun install-disjunct-into-proof-tree (cl-id disjunct-cl-id state)

; Replace disjunct-cl-id by cl-id in the global proof tree, discarding the
; other disjunctive cases under cl-id.

  (let ((proof-tree (f-get-global 'proof-tree state)))
    (assert$
     (consp proof-tree)
     (pprogn (f-put-global
              'proof-tree
              (prune-proof-tree
               (access clause-id cl-id :forcing-round)
               nil
               (cons (goal-tree-choose-disjunct cl-id disjunct-cl-id (car proof-tree))
                     (cdr proof-tree)))
              state)
             (print-proof-tree state)))))

; Logical Names

; Logical names are names introduced by the event macros listed in
; primitive-event-macros, e.g., they are the names of functions,
; macros, theorems, packages, etc.  Logical names have two main uses
; in this system.  The first is in theory expressions, where logical
; names are used to denote times in the past, i.e., "Give me the list
; of all rules enabled when nm was introduced."  The second is in the
; various keyword commands available to the user to enquire about his
; current state, i.e., "Show me the history around the time nmwas
; introduced."

; The latter use involves the much more sophisticated notion of
; commands as well as that of events.  We will deal with it later.

; We make special provisions to support the mapping from a logical
; name to the world at the time that name was introduced.  At the
; conclusion of the processing of an event, we set the 'global-value
; of 'event-landmark to an "event tuple."  This happens in stop-event.
; Among other things, an event tuple lists the names introduced by the
; event.  The successive settings of 'event-landmark are all visible
; on the world and thus effectively divide the world up into "event
; blocks."  Because the setting of 'event-landmark is the last thing
; we do for an event, the world at the termination of a given event is
; the world whose car is the appropriate event tuple.  So one way to
; find the world is scan down the current world, looking for the
; appropriate event landmark.

; This however is slow, because often the world is not in physical
; memory and must be paged in.  We therefore have worked out a scheme
; to support the faster lookup of names.  We could have stored the
; appropriate world on the property list of each symbolic name.  We
; did not want to do this because it might cause consternation when a
; user looked at the properties.  So we instead associate a unique
; nonnegative integer with each event and provide a mapping from those
; "absolute event numbers" to worlds.  We store the absolute event
; number of each symbolic name on the property list of the name (in
; stop-event).  The only other logical names are the strings that name
; packages.  We find them by searching through the world.

(defun logical-namep (name wrld)

; Returns non-nil if name is a logical name, i.e., a symbolic or
; string name introduced by an event, or the keyword :here meaning the
; most recent event.

  (cond ((symbolp name)
         (cond ((eq name :here) (not (null wrld)))
               (t (getprop name 'absolute-event-number nil
                           'current-acl2-world wrld))))
        ((and (stringp name)
              (find-non-hidden-package-entry
               name (global-val 'known-package-alist wrld)))
         t)
        (t nil)))

; Logical-name-type has been moved up to translate.lisp in support of
; chk-all-but-new-name, which supports handling of flet by translate11.

(defun logical-name-type-string (typ)
  (case typ
        (package "package")
        (function "function")
        (macro "macro")
        (const "constant")
        (stobj "single-threaded object")
        (stobj-live-var "single-threaded object holder")
        (theorem "theorem")
        (theory "theory")
        (label "label")
        (t (symbol-name typ))))

; Event Tuples

; Every time an event occurs we store a new 'global-value for the
; variable 'event-landmark in stop-event.  The value of
; 'event-landmark is an "event tuple."  Abstractly, an event tuple
; contains the following fields:

; n:     the absolute event number
; d:     the embedded event depth (the number of events containing the event)
; form:  the form evaluated that created the event.  (This is often a form
;        typed by the user but might have been a form generated by a macro.
;        The form may be a call of a primitive event macro, e.g., defthm, 
;        or may be itself a macro call, e.g., prove-lemma.)
; type:  the name of the primitive event macro we normally use, e.g., 
;        defthm, defuns, etc.
; namex: the name or names of the functions, rules, etc., introduced by
;        the event.  This may be a single object, e.g., 'APP, or "MY-PKG",
;        or may be a true list of objects, e.g., '(F1 F2 F3) as in the case
;        of a mutually recursive clique.  0 (zero) denotes the empty list of
;        names.  The unusual event enter-boot-strap-mode has a namex containing
;        both symbols and strings.
; symbol-class:
;        One of nil, :program, :ideal, or :compliant-common-lisp, indicating
;        the symbol-class of the namex.  (All names in the namex have the same
;        symbol-class.)

; All event tuples are constructed by make-event-tuple, below.  By searching
; for all calls of that function you will ascertain all possible event types
; and namex combinations.  You will find the main call in add-event-landmark,
; which is used to store an event landmark in the world.  There is another call
; in primordial-world-globals, where the bogus initial value of the
; 'event-landmark 'global-value is created with namex 0 and event type nil.
; Add-event-landmark is called in install-event, which is the standard (only)
; way to finish off an ACL2 event.  If you search for calls of install-event
; you will find the normal combinations of event types and namex.  There are
; two other calls of add-event-landmark.  One, in in primordial-world where it
; is called to create the enter-boot-strap-mode event type landmark with namex
; consisting of the primitive functions and known packages.  The other, in
; end-prehistoric-world, creates the exit-boot-strap-mode event type landmark
; with namex 0.

; As of this writing the complete list of type and namex pairs
; is shown below, but the algorithm described above will generate
; it for you if you wish to verify this.

;               type                namex
;           enter-boot-strap-mode    *see below
;           verify-guards            0 (no names introduced)
;           defun                    fn
;           defuns                   (fn1 ... fnk)
;           defaxiom                 name
;           defthm                   name
;           defconst                 name
;           defstobj                 (name the-live-var fn1 ... fnk)
;           defmacro                 name
;           defpkg                   "name"
;           deflabel                 name
;           deftheory                name
;           in-theory                0 (no name introduced)
;           in-arithmetic-theory     0 (no name introduced)
;           push-untouchable         0
;           remove-untouchable       0
;           reset-prehistory         0
;           set-body                 0 (no name introduced)
;           table                    0 (no name introduced)
;           encapsulate              (fn1 ... fnk) - constrained fns
;           include-book             "name"
;           exit-boot-strap-mode     0

; *Enter-boot-strap-mode introduces the names in *primitive-formals-
; and-guards* and *initial-known-package-alist*.  So its namex is a
; proper list containing both symbols and strings.

; To save space we do not actually represent each event tuple as a 6-tuple but
; have several different forms.  The design of our forms makes the following
; assumptions, aimed at minimizing the number of conses in average usage.  (1)
; Most events are not inside other events, i.e., d is often 0.  (2) Most events
; use the standard ACL2 event macros, e.g., defun and defthm rather than user
; macros, e.g., DEFN and PROVE-LEMMA.  (3) Most events are introduced with the
; :program symbol-class.  This last assumption is just the simple observation
; that until ACL2 is reclassified from :program to :logic, the ACL2
; system code will outweigh any application.

(defun signature-fns (signatures)

; Assuming that signatures has been approved by chk-signatures, we
; return a list of the functions signed.  Before we added signatures
; of the form ((fn * * STATE) => *) this was just strip-cars.
; Signatures is a list of elements, each of which is either of the
; form ((fn ...) => val) or of the form (fn ...).

  (cond ((endp signatures) nil)
        ((consp (car (car signatures)))
         (cons (car (car (car signatures)))
               (signature-fns (cdr signatures))))
        (t (cons (car (car signatures))
                 (signature-fns (cdr signatures))))))

(defun make-event-tuple (n d form ev-type namex symbol-class)

; An event tuple is always a cons.  Except in the initial case created by
; primordial-world-globals, the car is always either a natural (denoting n and
; implying d=0) or a cons of two naturals, n and d.  Its cadr is either a
; symbol, denoting its type and signalling that the cdr is the form, the
; symbol-class is :program and that the namex can be recovered from the form,
; or else the cadr is the pair (ev-type namex . symbol-class) signalling that
; the form is the cddr.

; Generally, the val encodes:
;  n - absolute event number
;  d - embedded event depth
;  form - form that created the event
;  ev-type - name of the primitive event macro we use, e.g., defun, defthm, defuns
;  namex - name or names introduced (0 is none)
;  symbol-class - of names (or nil)

; In what we expect is the normal case, where d is 0 and the form is one of our
; standard ACL2 event macros, this concrete representation costs one cons.  If
; d is 0 but the user has his own event macros, it costs 3 conses.

; Warning: If we change the convention that n is the car of a concrete event
; tuple if the car is an integer, then change the default value given getprop
; in max-absolute-event-number.

  (cons (if (= d 0) n (cons n d))
        (if (and (eq symbol-class :program)
                 (consp form)
                 (or (eq (car form) ev-type)
                     (and (eq ev-type 'defuns)
                          (eq (car form) 'mutual-recursion)))
                 (equal namex
                        (case (car form)
                              (defuns (strip-cars (cdr form)))
                              (mutual-recursion (strip-cadrs (cdr form)))
                              ((verify-guards in-theory
                                              in-arithmetic-theory
                                              push-untouchable
                                              remove-untouchable
                                              reset-prehistory
                                              set-body
                                              table)
                               0)
                              (encapsulate (signature-fns (cadr form)))
                              (otherwise (cadr form)))))
            form
          (cons (cons ev-type
                      (cons namex symbol-class))
                form))))

(defun access-event-tuple-depth (x)
  (if (integerp (car x)) 0 (cdar x)))

(defun access-event-tuple-type (x)
  (cond ((symbolp (cdr x)) ;eviscerated event
         nil)
        ((symbolp (cadr x))
         (if (eq (cadr x) 'mutual-recursion)
             'defuns
           (cadr x)))
        (t (caadr x))))

(defun access-event-tuple-namex (x)

; Note that namex might be 0, a single name, or a list of names.  Included in
; the last case is the possibility of the list being nil (as from an
; encapsulate event introducing no constrained functions).

  (cond
   ((symbolp (cdr x)) ;eviscerated event
    nil)
   ((symbolp (cadr x))
    (case (cadr x)
          (defuns (strip-cars (cddr x)))
          (mutual-recursion (strip-cadrs (cddr x)))
          ((verify-guards in-theory
                          in-arithmetic-theory
                          push-untouchable remove-untouchable reset-prehistory
                          set-body table)
           0)
          (encapsulate (signature-fns (caddr x)))
          (t (caddr x))))
   (t (cadadr x))))

(defun access-event-tuple-form (x)
  (if (symbolp (cadr x))
      (cdr x)
    (cddr x)))

(defun access-event-tuple-symbol-class (x)
  (if (symbolp (cadr x))
      :program
    (cddadr x)))

; Command Tuples

; When LD has executed a world-changing form, it stores a "command tuple" as
; the new 'global-value of 'command-landmark.  These landmarks divide the world
; up into "command blocks" and each command block contains one or or event
; blocks.  Command blocks are important when the user queries the system about
; his current state, wishes to undo, etc.  Commands are enumerated sequentially
; from 0 with "absolute command numbers."

; We define command tuples in a way analogous to event tuples, although
; commands are perhaps simpler because most of their characteristics are
; inherited from the event tuples in the block.  We must store the current
; default-defun-mode so that we can offer to redo :program functions after ubt.
; (A function is offered for redoing if its defun-mode is :program.  But the
; function is redone by executing the command that created it.  The command may
; recreate many functions and specify a :mode for each.  We must re-execute the
; command with the same default-defun-mode we did last to be sure that the
; functions it creates have the same defun-mode as last time.)

(defrec command-tuple

; Warning: Keep this in sync with the definitions of
; safe-access-command-tuple-number and pseudo-command-landmarkp in
; books/system/pseudo-good-worldp.lisp.

; See make-command-tuple for a discussion of defun-mode/form.

; If form is an embedded event form, then last-make-event-expansion is nil
; unless form contains a call of make-event whose :check-expansion field is not
; a cons, in which case last-make-event-expansion is the result of removing all
; make-event calls from form.

  (number defun-mode/form cbd . last-make-event-expansion)
  t)

(defun make-command-tuple (n defun-mode form cbd last-make-event-expansion)

; Defun-Mode is generally the default-defun-mode of the world in which this
; command is being executed.  But there are two possible exceptions.  See
; add-command-tuple.

; We assume that most commands are executed with defun-mode :program.  So we
; optimize our representation of command tuples accordingly.  No form that
; creates a function can have a keyword as its car.

  (make command-tuple
        :number n
        :defun-mode/form (if (eq defun-mode :program)
                             form
                           (cons defun-mode form))
        :cbd cbd
        :last-make-event-expansion last-make-event-expansion))

(defun access-command-tuple-number (x)
  (access command-tuple x :number))

(defun access-command-tuple-defun-mode (x)
  (let ((tmp (access command-tuple x :defun-mode/form)))
    (if (keywordp (car tmp))
        (car tmp)
      :program)))

(defun access-command-tuple-form (x)
  (let ((tmp (access command-tuple x :defun-mode/form)))
    (if (keywordp (car tmp))
        (cdr tmp)
      tmp)))

(defun access-command-tuple-last-make-event-expansion (x)
  (access command-tuple x :last-make-event-expansion))

(defun access-command-tuple-cbd (x)
  (access command-tuple x :cbd))

(defun access-event-tuple-number (x)

; Warning: If we change the convention that n is (car x) when (car x)
; is an integerp, then change the default value given getprop in
; max-absolute-event-number.

  (if (integerp (car x)) (car x) (caar x)))

; Absolute Event and Command Numbers

(defun max-absolute-event-number (wrld)

; This is the maximum absolute event number in use at the moment.  It
; is just the number found in the most recently completed event
; landmark.  We initialize the event-landmark with number -1 (see
; primordial-world-globals) so that next-absolute-event-number returns
; 0 the first time.

  (access-event-tuple-number (global-val 'event-landmark wrld)))

(defun next-absolute-event-number (wrld)
  (1+ (max-absolute-event-number wrld)))

(defun max-absolute-command-number (wrld)

; This is the largest absolute command number in use in wrld.  We
; initialize it to -1 (see primordial-world-globals) so that
; next-absolute-command-number works.

  (access-command-tuple-number (global-val 'command-landmark wrld)))

(defun next-absolute-command-number (wrld)
  (1+ (max-absolute-command-number wrld)))

; Scanning to find Landmarks

(defun scan-to-event (wrld)

; We roll back wrld to the first (list order traversal) event landmark
; on it.

  (cond ((null wrld) wrld)
        ((and (eq (caar wrld) 'event-landmark)
              (eq (cadar wrld) 'global-value))
         wrld)
        (t (scan-to-event (cdr wrld)))))

(defun scan-to-command (wrld)

; Scan to the next binding of 'command-landmark.

  (cond ((null wrld) nil)
        ((and (eq (caar wrld) 'command-landmark)
              (eq (cadar wrld) 'global-value))
         wrld)
        (t (scan-to-command (cdr wrld)))))

(defun scan-to-landmark-number (flg n wrld)

; We scan down wrld looking for a binding of 'event-landmark with n as
; its number or 'command-landmark with n as its number, depending on
; whether flg is 'event-landmark or 'command-landmark.

  #+acl2-metering
  (setq meter-maid-cnt (1+ meter-maid-cnt))
  (cond ((null wrld)
         (er hard 'scan-to-landmark-number
             "We have scanned the world looking for absolute ~
              ~#0~[event~/command~] number ~x1 and failed to find it. ~
               There are two likely errors.  Either ~#0~[an event~/a ~
              command~] with that number was never stored or the ~
              index has somehow given us a tail in the past rather ~
              than the future of the target world."
             (if (equal flg 'event-landmark) 0 1)
             n))
        ((and (eq (caar wrld) flg)
              (eq (cadar wrld) 'global-value)
              (= n (if (eq flg 'event-landmark)
                       (access-event-tuple-number (cddar wrld))
                       (access-command-tuple-number (cddar wrld)))))
         #+acl2-metering
         (meter-maid 'scan-to-landmark-number 500 flg n)
         wrld)
        (t (scan-to-landmark-number flg n (cdr wrld)))))

; The Event and Command Indices

; How do we convert an absolute event number into the world created by
; that event?  The direct way to do this is to search the world for
; the appropriate binding of 'event-landmark.  To avoid much of this
; search, we keep a map from some absolute event numbers to the
; corresponding tails of world.

; Rather than store an entry for each event number we will store one
; for every 10th.  Actually, *event-index-interval* determines the
; frequency.  This is a completely arbitrary decision.  A typical :ppe
; or :ubt will request a tail within 5 event of a saved one, on the
; average.  At 8 properties per event (the bootstrap right now is
; running 7.4 properties per event), that's about 40 tuples, each of
; the form (name prop . val).  We will always look at name and
; sometimes (1/8 of the time) look at prop and the car of val, which
; says we'll need to swap in about 40+40+1/8(40 + 40) = 90 conses.  We
; have no idea how much this costs (and without arguments about
; locality, it might be as bad as 90 pages!), but it seems little
; enough.  In any case, this analysis suggests that the decision to
; save every nth world will lead to swapping in only 9n conses.

; Assuming that a big proof development costs 3000 events (that's
; about the size of the Piton proof) and that the initial bootstrap is
; about 2000 (right now it is around 1700), we imagine that we will be
; dealing with 5000 events.  So our map from event numbers to
; tails of world will contain about 500 entries.  Of interest here is
; the choice of representation for that map.

; The requirement is that it be a map from the consecutive positive
; integers to tails of world (or nil for integers not yet claimed).
; It should operate comfortably with 500 entries.  It will be the
; value of the world global, 'event-index, and every time we add a
; new entry (i.e., every 10 events), we will rebind that global.
; Thus, by the time the table has 500 entries we will also be holding
; onto the 499 old versions of the table as well.

; Three representations came immediately to mind: a linear array, an
; association list, and a balanced binary tree.  A fourth was invented
; to solve the problem.  We discuss all four here.

; Linear Array.  If the event-index is an array then it will be
; extremely efficient to "search".  We will have to grow the array as
; we go, as we do in load-theory-into-enabled-structure.  So by the
; time the array has 500 entries the underlying Common Lisp array will
; probably contain around 750 words.  The alist version of the array
; will be of length 500 (ignoring the :HEADER) and consume 1000
; conses.  So in all we'll have about 1750 words tied up in this
; structure.  Old versions of the table will share the alist
; representation and cost little.  However, we imagine keeping only
; one Common Lisp array object and it will always hold the compressed
; version of the latest index.  So old versions of the index will be
; "out of date" and will have to be recompressed upon recovery from a
; :ubt, as done by recompress-global-enabled-structure.  This
; complicates the array representation and we have decided to dismiss
; it.

; Alist.  If the event-index is an alist it will typically be 500
; long and contain 1000 conses which are all perfectly shared with old
; copies.  Adding new entries is very fast, i.e., 2 conses.  Lookup is
; relatively slow: .004 seconds, average with an alist of size 500.
; For comparison purposes, we imagine the following scenario: The user
; starts with a world containing 2000 bootstrap events.  He adds
; another 3000 events of his own.  Every event, however, provokes
; him to do 10 :ppes to look at old definitions.  (We are purposefully
; biasing the scenario toward fast lookup times.)  Given the
; convention of saving every 10th tail of world in the index, the
; scenario becomes: The user starts with a index containing 200
; entries.  He grows it to 500 entries.  However, between each growth
; step he inspects 100 entries spread more or less evenly throughout
; the interval.  If the index is represented by an alist, how long
; does this scenario take?  Answer: 77 seconds (running AKCL on a Sun
; 360 with 20Mb).

; Balanced Binary Tree.  We have done an extensive study of the use of
; balanced binary trees (bbts) for this application.  Using bbts, the
; scenario above requires only 13 seconds.  However, bbts use a lot
; more space.  In particular, the bbt for 500 entries consumes 2000
; conses (compared to the alist's 1000 conses).  Worse, the bbt for
; 500 shares little of the structure for 499, while the alist shares
; it all.  (We did our best with structure sharing between successive
; bbts, it's just that rebalancing the tree after an addition
; frequently destroys the possibility for sharing.  Of the 2000 conses
; in the 500 entry bbt, 1028 are new and the rest are shared with the
; 499 bbt.)  In particular, to keep all 500 of the bbts will cost us
; 156,000 conses.  By contrast, the entire world after a bootstrap
; currently costs about 418,000 conses.

; So we need a representation that shares structure and yet is
; efficiently accessed.  Why are alists so slow?  Because we have to
; stop at every entry and ask "is this the one?"  But that is silly
; because we know that if we're looking for 2453 and we see 3000 then
; we have to skip down 547.  That is, our values are all associated
; with consecutive integer indices and the alist is ordered.  But we
; could just use a positional indexing scheme.

; Zap Table.  A zap table is a linear list of values indexed by
; 0-based positions STARTING FROM THE RIGHT.  To enable us to count
; from the right we include, as the first element in the list, the
; maximum index.  For example, the zap table that maps each of the
; integers from 0 to 9 to itself is: (9 9 8 7 6 5 4 3 2 1 0).  To add
; a new (10th) value to the table, we increment the car by 1 and cons
; the new value to the cdr.  Thus, we spend two conses per entry and
; share all other structure.  To fetch the ith entry we compute how
; far down the list it is with arithmetic and then retrieve it with
; nth.  To our great delight this scheme carries out our scenario in
; 13 seconds, as fast as balanced binary trees, but shares as much
; structure as alists.  This is the method we use.

(defun add-to-zap-table (val zt)

; Given a zap table, zt, that associates values to the indices
; 0 to n, we extend the table to associate val to n+1.

  (cond ((null zt) (list 0 val))
        (t (cons (1+ (car zt)) (cons val (cdr zt))))))

(defun fetch-from-zap-table (n zt)

; Retrieve the value associated with n in the zap table zt, or
; nil if there is no such association.

  (cond ((null zt) nil)
        ((> n (car zt)) nil)
        (t (nth (- (car zt) n) (cdr zt)))))

; These 7 lines of code took 3 days to write -- because we first
; implemented balanced binary trees and did the experiments described
; above.

; Using zap tables we'll keep an index mapping absolute event numbers
; to tails of world.  We'll also keep such an index for commands typed
; by the user at the top-level of the ld loop.  The following two
; constants determine how often we save events and commands in their
; respective indices.

(defconst *event-index-interval* 10)
(defconst *command-index-interval* 10)

(defun update-world-index (flg wrld)

; Flg is either 'COMMAND or 'EVENT and indicates which of the two
; indices we are to update.

; In the comments below, we assume flg is 'EVENT.

; This function is called every time we successfully complete the
; processing of an event.  We here decide if it is appropriate
; to save a pointer to the resulting world, wrld.  If so, we update
; the event-index.  If not, we do nothing.  Our current algorithm
; is to save every *event-index-interval*th world.  That is, if
; *event-index-interval* is 10 then we save the worlds whose
; max-absolute-event-numbers are 0, 10, 20, etc., into slots 0, 1, 2,
; etc. of the index.

  (cond
   ((eq flg 'EVENT)
    (let ((n (max-absolute-event-number wrld)))
      (cond ((= (mod n *event-index-interval*) 0)
             (let ((event-index (global-val 'event-index wrld)))

; Things will get very confused if we ever miss a multiple of "10."
; For example, if some bug in the system causes us never to call this
; function on a world with absolute-event-number 10, say, then the
; next multiple we do call it on, e.g., 20, will be stored in the
; slot for 10 and things will be royally screwed.  So just to be
; rugged we will confirm the correspondence between what we think
; we're adding and where it will go.

               (cond ((= (floor n *event-index-interval*)
                         (if (null event-index)
                             0
                             (1+ (car event-index))))
                      (global-set 'event-index
                                  (add-to-zap-table wrld event-index)
                                  wrld))
                     (t (er hard 'update-world-index
                            "The event-index and the maximum absolute ~
                             event number have gotten out of sync!  ~
                             In particular, the next available index ~
                             is ~x0 but the world has event number ~
                             ~x1, which requires index ~x2."
                            (if (null event-index)
                                0
                                (1+ (car event-index)))
                            n
                            (floor n *event-index-interval*))))))
            (t wrld))))
   (t
    (let ((n (max-absolute-command-number wrld)))
      (cond ((= (mod n *command-index-interval*) 0)
             (let ((command-index (global-val 'command-index wrld)))
               (cond ((= (floor n *command-index-interval*)
                         (if (null command-index)
                             0
                             (1+ (car command-index))))
                      (global-set 'command-index
                                  (add-to-zap-table wrld command-index)
                                  wrld))
                     (t (er hard 'update-world-index
                            "The command-index and the maximum ~
                             absolute command number have gotten out ~
                             of sync!  In particular, the next ~
                             available index is ~x0 but the world has ~
                             command number ~x1, which requires index ~
                             ~x2."
                            (if (null command-index)
                                0
                                (1+ (car command-index)))
                            n
                            (floor n *command-index-interval*))))))
            (t wrld))))))

(defun lookup-world-index1 (n interval index wrld)

; Let index be a zap table that maps the integers 0 to k to worlds.
; Instead of numbering those worlds 0, 1, 2, ..., number them 0,
; 1*interval, 2*interval, etc.  So for example, if interval is 10 then
; the worlds are effectively numbered 0, 10, 20, ...  Now n is some
; world number (but not necessarily a multiple of interval).  We wish
; to find the nearest world in the index that is in the future of the
; world numbered by n.  

; For example, if n is 2543 and interval is 10, then we will look for
; world 2550, which will be found in the table at 255.  Of course, the
; table might not contain an entry for 255 yet, in which case we return
; wrld.

  (let ((i (floor (+ n (1- interval))
                  interval)))
    (cond ((or (null index)
               (> i (car index)))
           wrld)
          (t (fetch-from-zap-table i index)))))

(defun lookup-world-index (flg n wrld)

; This is the general-purpose function that takes an arbitrary
; absolute command or event number (flg is 'COMMAND or 'EVENT) and
; returns the world that starts with the indicated number.

  (cond ((eq flg 'event)
         (let ((n (min (max-absolute-event-number wrld)
                       (max n 0))))
           (scan-to-landmark-number 'event-landmark
                                    n
                                    (lookup-world-index1
                                     n
                                     *event-index-interval*
                                     (global-val 'event-index wrld)
                                     wrld))))
        (t
         (let ((n (min (max-absolute-command-number wrld)
                       (max n 0))))
           (scan-to-landmark-number 'command-landmark
                                    n
                                    (lookup-world-index1
                                     n
                                     *command-index-interval*
                                     (global-val 'command-index wrld)
                                     wrld))))))

; Maintaining the Invariants Associated with Logical Names and Events

(defun store-absolute-event-number (namex n wrld boot-strap-flg)

; Associated with each symbolic logical name is the
; 'absolute-event-number.  This function is responsible for storing
; that property.  Namex is either 0, denoting the empty set, an atom,
; denoting the singleton set containing that atom, or a true-list of
; atoms denoting the corresponding set.

; It is convenient to store the 'predefined property here as well.

  (cond ((equal namex 0)
         wrld)
        ((atom namex)

; If namex is "MY-PKG" we act as though it were the empty list.

         (cond ((symbolp namex)
                (putprop namex 'absolute-event-number n
                         (cond (boot-strap-flg
                                (putprop namex 'predefined t wrld))
                               (t wrld))))
               (t wrld)))
        (t (store-absolute-event-number
            (or (cdr namex) 0)
            n
            (if (stringp (car namex))
                wrld
              (putprop (car namex) 'absolute-event-number n
                       (cond (boot-strap-flg
                              (putprop (car namex) 'predefined t wrld))
                             (t wrld))))
            boot-strap-flg))))

(defun the-namex-symbol-class1 (lst wrld symbol-class1)
  (cond ((null lst) symbol-class1)
        ((stringp (car lst))
         (the-namex-symbol-class1 (cdr lst) wrld symbol-class1))
        (t (let ((symbol-class2 (symbol-class (car lst) wrld)))
             (cond ((eq symbol-class1 nil)
                    (the-namex-symbol-class1 (cdr lst) wrld symbol-class2))
                   ((eq symbol-class2 nil)
                    (the-namex-symbol-class1 (cdr lst) wrld symbol-class1))
                   ((eq symbol-class1 symbol-class2)
                    (the-namex-symbol-class1 (cdr lst) wrld symbol-class1))
                   (t (er hard 'the-namex-symbol-class
                          "The symbolp elements of the namex argument ~
                           to add-event-landmark are all supposed to ~
                           have the same symbol-class, but the first ~
                           one we found with a symbol-class had class ~
                           ~x0 and now we've found another with ~
                           symbol-class ~x1.  The list of elements, ~
                           starting with the one that has ~
                           symbol-class ~x0 is ~x2."
                          symbol-class2 symbol-class1 lst)))))))

(defun the-namex-symbol-class (namex wrld)
  (cond ((equal namex 0) nil)
        ((atom namex)
         (cond ((symbolp namex)
                (symbol-class namex wrld))
               (t nil)))
        (t (the-namex-symbol-class1 namex wrld nil))))

(defun add-event-landmark (form ev-type namex wrld boot-strap-flg)

; We use a let* below and a succession of worlds just to make clear
; the order in which we store the various properties.  We update the
; world index before putting the current landmark on it.  This
; effectively adds the previous landmark to the index if it was a
; multiple of our interval.  We do this just so that the
; event-landmark we are about to lay down is truly the last thing we
; do.  Reflection on this issue leads to the conclusion that it is not
; really important whether the index entry is inside or outside of the
; landmark, in the case of event-landmarks.

  (let* ((n (next-absolute-event-number wrld))
         (wrld1 (store-absolute-event-number namex n wrld boot-strap-flg))
         (wrld2 (update-world-index 'event wrld1))
         (wrld3 
           (global-set 'event-landmark
                       (make-event-tuple n
                                         (length (global-val
                                                  'embedded-event-lst
                                                  wrld))
                                         form
                                         ev-type
                                         namex
                                         (the-namex-symbol-class namex wrld2))
                       wrld2)))
    wrld3))

; Decoding Logical Names

(defun scan-to-defpkg (name wrld)

; We wish to give meaning to stringp logical names such as "MY-PKG".  We do it
; in an inefficient way: we scan the whole world looking for an event tuple of
; type DEFPKG and namex name.  We know that name is a known package and that it
; is not one in *initial-known-package-alist*.

  (cond ((null wrld) nil)
        ((and (eq (caar wrld) 'event-landmark)
              (eq (cadar wrld) 'global-value)
              (eq (access-event-tuple-type (cddar wrld)) 'DEFPKG)
              (equal name (access-event-tuple-namex (cddar wrld))))
         wrld)
        (t (scan-to-defpkg name (cdr wrld)))))

(defun scan-to-include-book (full-book-name wrld)

; We wish to give meaning to stringp logical names such as "arith".  We
; do it in an inefficient way: we scan the whole world looking for an event
; tuple of type INCLUDE-BOOK and namex full-book-name.

  (cond ((null wrld) nil)
        ((and (eq (caar wrld) 'event-landmark)
              (eq (cadar wrld) 'global-value)
              (eq (access-event-tuple-type (cddar wrld)) 'include-book)
              (equal full-book-name (access-event-tuple-namex (cddar wrld))))
         wrld)
        (t (scan-to-include-book full-book-name (cdr wrld)))))

(defun assoc-equal-cadr (x alist)
  (cond ((null alist) nil)
        ((equal x (cadr (car alist))) (car alist))
        (t (assoc-equal-cadr x (cdr alist)))))

(defun multiple-assoc-terminal-substringp1 (x i alist)
  (cond ((null alist) nil)
        ((terminal-substringp x (caar alist) i (1- (length (caar alist))))
         (cons (car alist) (multiple-assoc-terminal-substringp1 x i (cdr alist))))
        (t (multiple-assoc-terminal-substringp1 x i (cdr alist)))))

(defun multiple-assoc-terminal-substringp (x alist)

; X and the keys of the alist are presumed to be strings.  This function
; compares x to the successive keys in the alist, succeeding on any key that
; contains x as a terminal substring.  Unlike assoc, we return the list of all
; pairs in the alist with matching keys.

  (multiple-assoc-terminal-substringp1 x (1- (length x)) alist))

(defun possibly-add-lisp-extension (str)

; String is a string.  If str ends in .lisp, return it.  Otherwise, tack .lisp
; onto the end and return that.

  (let ((len (length str)))
    (cond
     ((and (> len 5)
           (eql (char str (- len 5)) #\.)
           (eql (char str (- len 4)) #\l)
           (eql (char str (- len 3)) #\i)
           (eql (char str (- len 2)) #\s)
           (eql (char str (- len 1)) #\p))
      str)
     (t (string-append str ".lisp")))))

(defun decode-logical-name (name wrld)

; Given a logical name, i.e., a symbol with an 'absolute-event-number property
; or a string naming a defpkg or include-book, we return the tail of wrld
; starting with the introductory event.  We return nil if name is illegal.

  (cond
   ((symbolp name)
    (cond ((eq name :here)
           (scan-to-event wrld))
          (t
           (let ((n (getprop name 'absolute-event-number nil
                             'current-acl2-world wrld)))
             (cond ((null n) nil)
                   (t (lookup-world-index 'event n wrld)))))))
   ((stringp name)

; Name may be a package name or a book name.

    (cond
     ((find-non-hidden-package-entry name
                                     (global-val 'known-package-alist wrld))
      (cond ((find-package-entry name *initial-known-package-alist*)

; These names are not DEFPKGd and so won't be found in a scan.  They
; are introduced by absolute event number 0.

             (lookup-world-index 'event 0 wrld))
            (t (scan-to-defpkg name wrld))))
     (t (let ((hits (multiple-assoc-terminal-substringp
                     (possibly-add-lisp-extension name)
                     (global-val 'include-book-alist wrld))))

; Hits is a subset of the include-book-alist.  The form of each
; element is (full-book-name user-book-name familiar-name
; cert-annotations . ev-lst-chk-sum).

          (cond
           ((and hits (null (cdr hits)))
            (scan-to-include-book (car (car hits)) wrld))
           (t nil))))))
   (t nil)))

(defun er-decode-logical-name (name wrld ctx state)

; Like decode-logical-name but causes an error rather than returning nil.

  (let ((wrld1 (decode-logical-name name wrld)))
    (cond
     ((null wrld1)
      (let ((hits (and (stringp name)
                       (not (find-non-hidden-package-entry
                             name
                             (global-val 'known-package-alist wrld)))
                       (multiple-assoc-terminal-substringp
                        (possibly-add-lisp-extension name)
                        (global-val 'include-book-alist wrld)))))

; Hits is a subset of the include-book-alist.  The form of each
; element is (full-book-name user-book-name familiar-name
; cert-annotations . ev-lst-chk-sum).

        (cond
         ((and hits (cdr hits))
          (er soft ctx
              "More than one book matches the name ~x0, in particular ~&1.  We ~
               therefore consider ~x0 not to be a logical name and insist ~
               that you use an unambiguous form of it.  See :DOC logical-name."
              name
              (strip-cars hits)))
         (t (er soft ctx
                "The object ~x0 is not a logical name.  See :DOC logical-name."
                name)))))
     (t (value wrld1)))))

(defun renew-lemmas (fn lemmas)

; We copy lemmas, which is a list of rewrite rules, deleting those whose
; runes have fn as their base symbol.  These are, we believe, all and only
; the rules stored by the event which introduced fn.

  (cond ((null lemmas) nil)
        ((eq (base-symbol (access rewrite-rule (car lemmas) :rune)) fn)
         (renew-lemmas fn (cdr lemmas)))
        (t (cons (car lemmas) (renew-lemmas fn (cdr lemmas))))))

(defun renew-name/erase (name old-getprops wrld)

; Name is a symbol, old-getprops is the list returned by getprops on name,
; i.e., an alist dotting properties to values.  We map over that list and
; "unbind" every property of name in wrld.  We do not touch 'GLOBAL-VALUE
; because that is not a property affected by an event (consider what would
; happen if the user defined and then redefined COMMAND-LANDMARK).  Similarly,
; we do not touch 'table-alist or 'table-guard.  See the list of properties
; specially excepted by new-namep.

  (cond
   ((null old-getprops) wrld)
   (t (renew-name/erase
       name
       (cdr old-getprops)
       (if (member-eq (caar old-getprops)
                      '(global-value table-alist table-guard))
           wrld
           (putprop name
                    (caar old-getprops)
                    *acl2-property-unbound*
                    wrld))))))

;; RAG - Hmmm, this code assumes it knows all of the properties stored
;; on a function symbol.  Sad.  I added 'CLASSICALP to the list.

(defun renew-name/overwrite (name old-getprops wrld)

; Name is a function symbol, old-getprops is the list returned by getprops
; on name, i.e., an alist dotting properties to values.  We map over that
; list and "unbind" those properties of name in wrld that were stored by
; the event introducing name.

; Note: Even when the ld-redefinition-action specifies :overwrite we
; sometimes change it to :erase (see maybe-coerce-overwrite-to-erase).
; Thus, this function is actually only called on function symbols, not
; constants or stobjs or stobj-live-vars.  The erase version, above,
; is called on those redefinable non-functions.

  (cond
   ((null old-getprops) wrld)
   ((eq (caar old-getprops) 'redefined)
    (renew-name/overwrite
     name
     (cdr old-getprops)
     wrld))
   ((member-eq (caar old-getprops)
               '(FORMALS
                 STOBJS-IN
                 STOBJS-OUT
                 SYMBOL-CLASS
                 NON-EXECUTABLEP
                 SIBLINGS
                 LEVEL-NO
                 QUICK-BLOCK-INFO
                 PRIMITIVE-RECURSIVE-DEFUNP
                 CONSTRAINEDP
                 HEREDITARILY-CONSTRAINED-FNNAMES
                 #+:non-standard-analysis CLASSICALP
                 DEF-BODIES
                 NTH-UPDATE-REWRITER-TARGETP
                 INDUCTION-MACHINE
                 JUSTIFICATION
                 UNNORMALIZED-BODY
                 CONSTRAINT-LST
                 RECURSIVEP
                 TYPE-PRESCRIPTIONS
                 GUARD
                 ABSOLUTE-EVENT-NUMBER

; Note: If you delete RUNIC-MAPPING-PAIRS from this list you must reconsider
; functions like current-theory-fn which assume that if a name has the
; REDEFINED property then its runic-mapping-pairs has been set to
; *acl2-property-unbound*.

                 RUNIC-MAPPING-PAIRS

; This property is stored by defstobj on all supporting functions.

                 STOBJ-FUNCTION))

; The properties above are stored by the defun, constrain or defstobj
; that introduced name and we erase them.

    (renew-name/overwrite
     name
     (cdr old-getprops)
     (putprop name
              (caar old-getprops)
              *acl2-property-unbound*
              wrld)))
   ((eq (caar old-getprops) 'lemmas)

; We erase from the lemmas property just those rules stored by the introductory event.

    (renew-name/overwrite
     name
     (cdr old-getprops)
     (putprop name
              'lemmas
              (renew-lemmas name
                            (getprop name 'lemmas nil 'current-acl2-world wrld))
              wrld)))
   ((member-eq (caar old-getprops)

; As of this writing, the property in question must be one of the following:

               '(GLOBAL-VALUE
                 LABEL
                 LINEAR-LEMMAS
                 FORWARD-CHAINING-RULES
                 ELIMINATE-DESTRUCTORS-RULE
                 COARSENINGS
                 CONGRUENCES
                 INDUCTION-RULES
                 THEOREM
                 DEFCHOOSE-AXIOM
                 UNTRANSLATED-THEOREM
                 CLASSES
                 CONST
                 THEORY
                 TABLE-GUARD
                 TABLE-ALIST
                 MACRO-BODY
                 MACRO-ARGS
                 PREDEFINED
                 DEFAXIOM-SUPPORTER
                 ATTACHMENT ; see Essay on Defattach re: :ATTACHMENT-DISALLOWED
                 CLAUSE-PROCESSOR))

; and these are not created by the introductory event of name (which must have
; been a defun or constrain) and hence are left untouched here.

   (renew-name/overwrite
    name
    (cdr old-getprops)
    wrld))
  (t
   (illegal 'renew-name/overwrite
            "We thought we knew all the properties stored by events ~
             introducing redefinable function names, but we don't know about ~
             the property ~x0."
            (list (cons #\0 (caar old-getprops)))))))

(defun renew-name (name renewal-mode wrld)

; We make it sort of appear as though name is sort of new in wrld.  Ah, to be
; young again...  We possibly erase all properties of name (depending on the
; renewal-mode, which must be :erase, :overwrite or :reclassifying-overwrite),
; and we put a 'redefined property on name.  Note that we always put the
; 'redefined property, even if name already has that property with that value,
; because one of our interests in this property is in stop-event, which uses it
; to identify which names have been redefined in this event.

; The value of the 'redefined property is (renewal-mode . old-sig),
; where old-sig is either the internal form signature of name if name
; is function and is otherwise nil.

; By storing the renewal-mode we make it possible to recover exactly how the
; final world was obtained from the initial one.  For purposes of renewal, we
; treat renewal-mode :reclassifying-overwrite as :overwrite; the only
; difference is that we store the :reclassifying-overwrite in the 'redefined
; property.  The only time :reclassifying-overwrite is the renewal-mode is when
; a :program function is being reclassified to an identical-defp :logic
; function.

  (putprop name 'redefined
           (cons renewal-mode
                 (cond ((and (symbolp name)
                             (function-symbolp name wrld))
                        (list name
                              (formals name wrld)
                              (stobjs-in name wrld)
                              (stobjs-out name wrld)))
                       (t nil)))
           (cond
            ((eq renewal-mode :erase)
             (renew-name/erase name
                               (getprops name 'current-acl2-world wrld)
                               wrld))
            ((or (eq renewal-mode :overwrite)
                 (eq renewal-mode :reclassifying-overwrite))
             (renew-name/overwrite name
                                   (getprops name 'current-acl2-world wrld)
                                   wrld))
            (t wrld))))

(defun renew-names (names renewal-mode wrld)
  (cond ((endp names) wrld)
        (t (renew-names (cdr names)
                        renewal-mode
                        (renew-name (car names) renewal-mode wrld)))))

(defun collect-redefined (wrld ans)

; We return a list of all redefined names down to the next event-landmark
; except those redefined in the :reclassifying-overwrite mode.  (Quoting from a
; comment in renew-name: The only time :reclassifying-overwrite is the
; renewal-mode is when a :program function is being reclassified to an
; identical-defp :logic function.)

  (cond ((or (null wrld)
             (and (eq (caar wrld) 'event-landmark)
                  (eq (cadar wrld) 'global-value)))
         ans)
        ((and (eq (cadar wrld) 'redefined)
              (consp (cddar wrld))
              (not (eq (car (cddar wrld)) :reclassifying-overwrite)))
         (collect-redefined
          (cdr wrld)
          (cons (caar wrld) ans)))
        (t (collect-redefined (cdr wrld) ans))))

(defun scrunch-eq (lst)
  (cond ((null lst) nil)
        ((member-eq (car lst) (cdr lst)) (scrunch-eq (cdr lst)))
        (t (cons (car lst) (scrunch-eq (cdr lst))))))

(defun print-redefinition-warning (wrld ctx state)

; If the 'ld-redefinition-action of state says we should :warn and some names
; were redefined, then we print a warning.  See :DOC ld-redefinition-action.
; Note that if the action specifies :warn and a system function is
; redefined, then a query is made.  Provided the user approves, the system
; function is redefined and then this warning is printed because the action
; says :warn.  This is a bit odd since we try, in general, to avoid warning
; if we have querried.  But we don't want to have to determine now if the
; redefined names are system functions, so we warn regardless.

  (cond
   ((warning-disabled-p "Redef")
    state)
   ((let ((act (f-get-global 'ld-redefinition-action state)))
      (and (consp act)
           (or (eq (car act) :warn)
               (eq (car act) :warn!))))
    (let ((redefs
           (scrunch-eq
            (reverse
             (collect-redefined
              (cond ((and (consp wrld)
                          (eq (caar wrld) 'event-landmark)
                          (eq (cadar wrld) 'global-value))
                     (cdr wrld))
                    (t (er hard 'print-redefinition-warning
                           "This function is supposed to be called on a world ~
                             that starts at an event landmark, but this world ~
                             starts with (~x0 ~x1 . val)."
                           (caar wrld)
                           (cadar wrld))))
              nil)))))
      (cond (redefs
             (warning$ ctx ("Redef") "~&0 redefined.~%" redefs))
            (t state))))
   (t state)))

(defun initialize-summary-accumulators (state)

; This function is the standard way to start an ACL2 event.  We push a 0 onto
; each of the timers, thus protecting the times accumulated by any superior
; (e.g., an encapsulate) and initializing an accumulator for this event.  The
; accumulated times AND warnings are printed by print-time-summary.

; Note that some state globals also need to be initialized when starting an
; event, but that is accomplished using the macro save-event-state-globals.

  #+(and (not acl2-loop-only) acl2-rewrite-meter) ; for stats on rewriter depth
  (setq *rewrite-depth-max* 0)

  (pprogn (push-timer 'other-time 0 state)
          (push-timer 'prove-time 0 state)
          (push-timer 'print-time 0 state)
          (push-timer 'proof-tree-time 0 state)
          (push-warning-frame state)
          (mv-let (x state)
                  (main-timer state)
                  (declare (ignore x))
                  state)))

(defun print-warnings-summary (state)
  (mv-let
   (warnings state)
   (pop-warning-frame t state)
   (io? summary nil state
        (warnings)
        (cond ((member-eq 'warnings
                          (f-get-global 'inhibited-summary-types
                                        state))
               state)
              ((null warnings)
               state)
              (t
               (let ((channel (proofs-co state)))
                 (mv-let
                  (col state)
                  (fmt1 "Warnings:  ~*0~%"
                        (list (cons #\0
                                    (list "None" "~s*" "~s* and " "~s*, "
                                          warnings)))
                        0 channel state nil)
                  (declare (ignore col))
                  state)))))))

(defun print-time-summary (state)

; Print the time line, e.g.,

;Time:  0.15 seconds (prove: 0.00, print: 0.02, other: 0.13)

; assuming that the cursor is at the left margin.

; Once upon a time we considered extending fmt so that it knew how to
; print timers.  However, fmt needs to know which column it is left in
; and returns that to the user.  Thus, if fmt printed a timer (at
; least in the most convenient way) the user could detect the number
; of digits in it.  So we are doing it this way.

  (let ((skip-proof-tree-time

; Note that get-timer is untouchable, and :pso calls trans-eval, hence
; translate1; so we must bind skip-proof-tree-time up here, not under the io?
; call below.

         (and (member-eq 'proof-tree (f-get-global 'inhibit-output-lst state))
              (= (car (get-timer 'proof-tree-time state)) 0))))
    (io? summary nil state
         (skip-proof-tree-time)
         (pprogn
          (cond
           ((member-eq 'time
                       (f-get-global 'inhibited-summary-types
                                     state))
            state)
           (t
            (let ((channel (proofs-co state)))
              (pprogn
               (princ$ "Time:  " channel state)
               (push-timer 'total-time 0 state)
               (add-timers 'total-time 'prove-time state)
               (add-timers 'total-time 'print-time state)
               (add-timers 'total-time 'proof-tree-time state)
               (add-timers 'total-time 'other-time state)
               (print-timer 'total-time channel state)
               (pop-timer 'total-time nil state)
               (princ$ " seconds (prove: " channel state)
               (print-timer 'prove-time channel state)
               (princ$ ", print: " channel state)
               (print-timer 'print-time channel state)
               (if skip-proof-tree-time
                   state
                 (pprogn (princ$ ", proof tree: " channel state)
                         (print-timer 'proof-tree-time channel state)))
               (princ$ ", other: " channel state)
               (print-timer 'other-time channel state)
               (princ$ ")" channel state)
               (newline channel state)))))
          (pop-timer 'prove-time t state)
          (pop-timer 'print-time t state)
          (pop-timer 'proof-tree-time t state)
          (pop-timer 'other-time t state)))))

(defun print-steps-summary (state)
  (io? summary nil state
       ()
       (cond
        ((member-eq 'steps
                    (f-get-global 'inhibited-summary-types
                                  state))
         state)
        (t (let* ((channel (proofs-co state))
                  (limit (f-get-global 'step-limit-start state))
                  (last-limit (and limit
                                   (f-get-global 'last-step-limit state))))
             (cond ((and last-limit
                         (not (int= limit last-limit)))
                    (pprogn (princ$ "Prover steps counted:  " channel state)
                            (cond ((eql last-limit -1)
                                   (pprogn
                                    (princ$ "More than " channel state)
                                    (princ$ limit channel state)))
                                  (t (princ$ (- limit last-limit) channel state)))
                            (newline channel state)))
                   (t state)))))))

(defun print-rules-summary (state)
  (let ((acc-ttree (f-get-global 'accumulated-ttree state)))
    (mv-let
     (col state)
     (io? summary nil (mv col state)
          (acc-ttree)
          (let ((channel (proofs-co state)))
            (cond ((member-eq 'rules
                              (f-get-global 'inhibited-summary-types
                                            state))
                   (mv 0 state))
                  (t
                   (let ((runes (merge-sort-runes
                                 (all-runes-in-ttree acc-ttree nil))))
                     (fmt1 "Rules: ~y0~|"
                           (list (cons #\0 runes))
                           0 channel state nil)))))
          :default-bindings ((col 0)))
     (declare (ignore col))
     (pprogn (f-put-global 'accumulated-ttree nil state)

; Since we've already printed the appropriate rules, there is no need to print
; them again the next time we want to print rules.  That is why we set the
; accumulated-ttree to nil here.  If we ever want certify-book, say, to be able
; to print rules when it fails, then we should use a stack of ttrees rather
; than a single accumulated-ttree.

             state))))

#+acl2-rewrite-meter
(defun merge-cdr-> (l1 l2)
  (cond ((null l1) l2)
        ((null l2) l1)
        ((> (cdr (car l1)) (cdr (car l2)))
         (cons (car l1) (merge-cdr-> (cdr l1) l2)))
        (t (cons (car l2) (merge-cdr-> l1 (cdr l2))))))

#+acl2-rewrite-meter
(defun merge-sort-cdr-> (l)
  (cond ((null (cdr l)) l)
        (t (merge-cdr-> (merge-sort-cdr-> (evens l))
                        (merge-sort-cdr-> (odds l))))))

(defconst *gag-prefix* "([ ")
(defconst *gag-suffix* (msg "])~|"))

(defun gag-start-msg (cl-id pool-name)
  (msg "~@0A key checkpoint~#1~[ while proving ~@2 ~
        (descended from ~@3)~/~]:"
       *gag-prefix*
       (if cl-id 0 1)
       pool-name
       (and cl-id (tilde-@-clause-id-phrase cl-id))))

(defun print-gag-info (info state)
  (fms "~@0~%~Q12~|"
       (list (cons #\0 (tilde-@-clause-id-phrase
                        (access gag-info info :clause-id)))
             (cons #\1 (prettyify-clause
                        (access gag-info info :clause)
                        (let*-abstractionp state)
                        (w state)))
             (cons #\2 (term-evisc-tuple nil state)))
       (proofs-co state) state nil))

(defun set-checkpoint-summary-limit-fn (val state)
  (if (or (eq val nil)
          (eq val t)
          (natp val)
          (and (consp val)
               (or (null (car val))
                   (natp (car val)))
               (or (null (cdr val))
                   (natp (cdr val)))))
      (let ((val (if (natp val)
                     (cons val val)
                   val)))
        (pprogn (f-put-global 'checkpoint-summary-limit val state)
                (value val)))
    (er soft 'set-checkpoint-summary-limit
        "Illegal value, ~x0, for checkpoint-summary-limit; see :DOC ~
         set-checkpoint-summary-limit."
        val)))

(defmacro set-checkpoint-summary-limit (val)

  ":Doc-Section switches-parameters-and-modes

  control printing of key checkpoints upon a proof's failure~/

  ~l[set-gag-mode] for a discussion of key checkpoints.

  ~bv[]
  Examples:

  ; (Default) When a proof fails, print all key checkpoints before
  ; induction but at most 3 key checkpoints after induction:
  (set-checkpoint-summary-limit (nil . 3))

  ; When a proof fails, print at most 3 key checkpoints before
  ; induction but all 3 key checkpoints after induction:
  (set-checkpoint-summary-limit (3 . nil))

  ; When a proof fails, print at most 3 key checkpoints before
  ; induction and at most 5 key checkpoints after induction:
  (set-checkpoint-summary-limit (3 . 5))

  ; When a proof fails, print at most 3 key checkpoints before
  ; induction and at most 3 key checkpoints after induction:
  (set-checkpoint-summary-limit (3 . 3))
  ; or equivalently,
  (set-checkpoint-summary-limit 3)

  ; When a proof fails, print all key checkpoints:
  (set-checkpoint-summary-limit (nil . nil))
  ; or equivalently,
  (set-checkpoint-summary-limit nil)

  ; When a proof fails, print no information at all about key checkpoints:
  (set-checkpoint-summary-limit t)~/

  General Forms:
  (set-checkpoint-summary-limit (n1 . n2))
  (set-checkpoint-summary-limit n)
  (set-checkpoint-summary-limit t)
  ~ev[]
  where each of ~c[n1] and ~c[n2] is a natural number or ~c[nil].  For the
  second form, ~c[n] can be a natural number or ~c[nil] and is treated as
  ~c[(n . n)].  The value ~c[t] inhibits all printing of checkpoint summary
  information.  The values ~c[n1] and ~c[n2] determine printing of key
  checkpoints generated before the first induction and generated after the
  first induction, respectively, where at most ~c[n1] or ~c[n2] (respectively)
  such key checkpoints are printed unless the value is ~c[nil], in which case
  there is no limitation.

  The argument ~c[x] for ~c[set-checkpoint-summary-limit], as described above,
  may be quoted, i.e. supplied as ~c['x] or ~c[(quote x)].  Thus, you may use
  the keyword form (~pl[keyword-commands]) if you prefer, for example:
  ~bv[]
  :set-checkpoint-summary-limit (nil . 3)
  ~ev[]"

  (let ((x (if (and (consp val)
                    (eq (car val) 'quote))
               val
             (list 'quote val))))
    `(set-checkpoint-summary-limit-fn ,x state)))

(defun print-gag-stack-rev (lst limit orig-limit msg chan state)

; Lst is the reverse of the :abort-stack, :top-stack, or :sub-stack field of a
; gag-state.

  (cond ((endp lst) state)
        ((eql limit 0)
         (fms "Note: ~#2~[Not shown~/There~] ~#0~[is~#2~[ the~/~] ~n1~#2~[~/ ~
               additional~] key checkpoint~/are~#2~[ the~/~] ~n1~#2~[~/ ~
               additional~] key checkpoints~] ~@3.  See :DOC ~
               set-checkpoint-summary-limit to ~#4~[change the number ~
               printed~/print this key checkpoint~/print some or all of these ~
               key checkpoints~].~|"
              (list (cons #\0 lst)
                    (cons #\1 (length lst))
                    (cons #\2 (if (eql orig-limit 0) 0 1))
                    (cons #\3 msg)
                    (cons #\4 (cond ((not (eql orig-limit 0)) 0)
                                    ((null (cdr lst)) 1)
                                    (t 2))))
              chan state nil))
        (t (pprogn (print-gag-info (car lst) state)
                   (print-gag-stack-rev (cdr lst) (and limit (1- limit))
                                        orig-limit msg chan state)))))

(defun print-gag-state1 (gag-state state)
  (cond
   ((eq (f-get-global 'checkpoint-summary-limit state) t)
    state)
   (gag-state
    (let* ((chan (proofs-co state))
           (abort-stack
            (access gag-state gag-state :abort-stack))
           (top-stack0 (access gag-state gag-state :top-stack))
           (top-stack (or abort-stack top-stack0))
           (sub-stack (access gag-state gag-state :sub-stack))
           (some-stack (or sub-stack

; We use top-stack0 here instead of top-stack because if the only non-empty
; stack is the :abort-stack, then presumably the proof completed modulo :by
; hints that generated :bye tags in the ttree.

                           top-stack0))
           (forcing-round-p
            (and some-stack
                 (let ((cl-id (access gag-info (car some-stack)
                                      :clause-id)))
                   (not (eql 0 (access clause-id cl-id
                                       :forcing-round)))))))
      (cond
       (some-stack
        (pprogn
         (fms "---~|The key checkpoint goal~#0~[~/s~], below, may help you to ~
               debug this failure.  See :DOC failure and see :DOC ~
               set-checkpoint-summary-limit.~@1~|---~|"
              (list (cons #\0
                          (if (or (and top-stack sub-stack)
                                  (cdr top-stack)
                                  (cdr sub-stack))
                              1
                            0))
                    (cons #\1
                          (if forcing-round-p
                              "  Note that at least one checkpoint is in a ~
                               forcing round, so you may want to see a full ~
                               proof."
                            "")))
              chan state nil)
         (cond (top-stack
                (let ((limit (car (f-get-global
                                   'checkpoint-summary-limit
                                   state))))
                  (pprogn
                   (fms "*** Key checkpoint~#0~[~/s~] ~#1~[before reverting ~
                         to proof by induction~/at the top level~]: ***~|"
                        (list (cons #\0 top-stack)
                              (cons #\1 (if abort-stack 0 1)))
                        chan state nil)
                   (print-gag-stack-rev
                    (reverse top-stack)
                    limit limit "before induction" chan
                    state))))
               (t state))
         (cond (sub-stack
                (let ((limit (cdr (f-get-global
                                   'checkpoint-summary-limit
                                   state))))
                  (pprogn
                   (fms "*** Key checkpoint~#0~[~/s~] under a top-level ~
                         induction: ***~|"
                        (list (cons #\0 sub-stack))
                        chan state nil)
                   (print-gag-stack-rev
                    (reverse sub-stack)
                    limit
                    limit
                    "under a top-level induction"
                    chan
                    state))))
               (t state))))
       (t ; no checkpoints; aborted
        (fms "*** Note: No checkpoints to print. ***~|"
             nil chan state nil)))))
   (t ; no checkpoints; proof never started
    state)))

(defun erase-gag-state (state)

; Avoid repeated printing of the gag state, e.g. for a theorem under several
; levels of encapsulate or under certify-book.  We set 'gag-state here rather
; than directly inside print-gag-state because gag-state is untouchable and
; translate11 is called on in the process of running :psog.

  (pprogn (f-put-global 'gag-state-saved (f-get-global 'gag-state state) state)
          (f-put-global 'gag-state nil state)))

(defun print-gag-state (state)
  (io? error nil state
       ()
       (let ((gag-state (f-get-global 'gag-state state)))
         (pprogn (erase-gag-state state)
                 (print-gag-state1 gag-state state)))))

(defun print-failure (ctx state)
  (pprogn (print-gag-state state)
          (io? error nil state
               (ctx)
               (let ((channel (proofs-co state)))
                 (pprogn
                  (error-fms-channel nil ctx "See :DOC failure." nil channel
                                     state)
                  (newline channel state)
                  (fms *proof-failure-string* nil channel state nil))))))

(defun print-summary (erp noop-flg ctx state)

; This function prints the Summary paragraph.  Part of that paragraph includes
; the timers.  Time accumulated before entry to this function is charged to
; 'other-time.  We then pop the timers, adding their accumulations to the newly
; exposed time.  This has the effect of charging superior events for the time
; used by their inferiors.

; For simplicity, we do the above and all other computations even if we are not
; to print the summary or parts of it.  For example, we handle
; pop-warning-frame regardless of whether or not we print the warning summary.

; If erp is t, the "event" caused an error and we do not scan for redefined
; names but we do print the failure string.  If noop-flg is t then the
; installed world did not get changed by the "event" (e.g., the "event" was
; redundant or was not really an event but was something like a call of (thm
; ...)) and we do not scan the most recent event block for redefined names.

  #+(and (not acl2-loop-only) acl2-rewrite-meter) ; for stats on rewriter depth
  (cond ((atom ctx))
        ((symbolp (cdr ctx))
         (cond ((not (eql *rewrite-depth-max* 0))
                (setq *rewrite-depth-alist*
                      (cons (cons (intern (symbol-name (cdr ctx)) "ACL2")

; We intern into the ACL2 package so that our tools can read this alist back in
; without needing a DEFPKG to be executed first.  The name is really all we
; care about here anyhow; all we would do with it is to search for it in the
; indicated file.

                                  *rewrite-depth-max*)
                            *rewrite-depth-alist*))
                (setq *rewrite-depth-max* 0))))
        ((eq (car ctx) 'certify-book)
         (let* ((bookname (extend-pathname
                           (f-get-global 'connected-book-directory state)
                           (cdr ctx)
                           state))
                (filename (concatenate 'string bookname ".lisp")))
           (with-open-file (str filename
                                :direction :output
                                :if-exists :rename-and-delete)
                           (format str
                                   "~s~%"
                                   (cons filename
                                         (merge-sort-cdr-> *rewrite-depth-alist*)))))
         (setq *rewrite-depth-alist* nil)))

  #-acl2-loop-only (dmr-flush)

  (let ((wrld (w state)))
    (cond
     ((or (ld-skip-proofsp state)
          (output-ignored-p 'summary state))
      (pprogn (increment-timer 'other-time state)
              (if (or erp noop-flg)
                  state
                (print-redefinition-warning wrld ctx state))
              (pop-timer 'prove-time t state)
              (pop-timer 'print-time t state)
              (pop-timer 'proof-tree-time t state)
              (pop-timer 'other-time t state)
              (mv-let (warnings state)
                      (pop-warning-frame nil state)
                      (declare (ignore warnings))
                      state)))
     (t

; Even if 'summary is inhibited, we still use io? below, and inside some
; functions below, because of its window hacking and saved-output functions.

      (pprogn
       (increment-timer 'other-time state)
       (if (or erp noop-flg)
           state
         (print-redefinition-warning wrld ctx state))
       (pprogn
        (io? summary nil state
             ()
             (let ((channel (proofs-co state)))
               (cond ((member-eq 'header
                                 (f-get-global 'inhibited-summary-types state))
                      state)
                     (t
                      (pprogn (newline channel state)
                              (princ$ "Summary" channel state)
                              (newline channel state))))))
        (io? summary nil state
             (ctx)
             (let ((channel (proofs-co state)))
               (cond ((member-eq 'form
                                 (f-get-global 'inhibited-summary-types state))
                      state)
                     (t
                      (mv-let
                       (col state)
                       (fmt1 "Form:  " nil 0 channel state nil)
                       (mv-let
                        (col state)
                        (fmt-ctx ctx col channel state)
                        (declare (ignore col))
                        (newline channel state))))))))
       (print-rules-summary state) ; Call of io? is inside
       (pprogn (print-warnings-summary state)
               (print-time-summary state)
               (print-steps-summary state))
       (cond (erp
              (pprogn
               (print-failure ctx state)
               (cond
                ((f-get-global 'proof-tree state)
                 (io? proof-tree nil state
                      (ctx)
                      (pprogn (f-put-global 'proof-tree-ctx
                                            (cons :failed ctx)
                                            state)
                              (print-proof-tree state))))
                (t state))))
             (t state))
       (f-put-global 'proof-tree nil state))))))

(defun with-prover-step-limit-fn (limit form)
  `(mv-let
    (with-prover-step-limit-initial-step-limit
     with-prover-step-limit-limit)
    (let ((limit ,limit)
          (initial-step-limit (initial-step-limit (w state) state)))
      (mv initial-step-limit
          (cond ((null limit)
                 *default-step-limit*)
                ((and (natp limit)
                      (<= limit *default-step-limit*))
                 limit)
                ((eq limit :start)
                 initial-step-limit)
                (t (er hard 'with-prover-step-limit
                       "Illegal value for ~x0, ~x1.  See :DOC ~
                         with-prover-step-limit."
                       'with-prover-step-limit
                       limit)))))
    (pprogn
     (f-put-global 'last-step-limit with-prover-step-limit-limit state)
     (er-let* ((val (state-global-let*
                     ((step-limit-start with-prover-step-limit-limit))
                     (check-vars-not-free (with-prover-step-limit-initial-step-limit
                                           with-prover-step-limit-limit)
                                          ,form))))
       (let ((new-step-limit
              (cond
               ((eql (f-get-global 'last-step-limit state) -1)

; We reached the limit, but didn't cause an error.  We must have used up the
; maximum possible number of steps.

                (assert$ (eql with-prover-step-limit-limit
                              *default-step-limit*)
                         -1))
               (t
                (let ((steps-taken
                       (- with-prover-step-limit-limit
                          (f-get-global 'last-step-limit state))))
                  (cond
                   ((< with-prover-step-limit-initial-step-limit
                       steps-taken)
                    -1)
                   (t (- with-prover-step-limit-initial-step-limit
                         steps-taken))))))))
         (pprogn
          (f-put-global 'last-step-limit new-step-limit state)
          (cond

; Here we handle the case that the step-limit is exceeded after a sub-event of
; a compound event, for example, between the two defthm events below.

; (set-prover-step-limit 100)
; (encapsulate
;  ()
;  (with-prover-step-limit 500
;                          (defthm foo
;                            (equal (append (append x y) z)
;                                   (append x y z))))
;  (defthm bar (equal (car (cons x y)) x)))

           ((and (eql new-step-limit -1)

; If state global 'step-limit-start has value nil, then we are at the
; top-level; no context has been entered.

                 (f-get-global 'step-limit-start state)
                 (not (eql (f-get-global 'step-limit-start state)
                           *default-step-limit*)))
            (step-limit-error t))
           (t (value val)))))))))

(defmacro with-prover-step-limit (limit form)

; Form should evaluate to an error triple.  A value of :start for limit says
; that we use the current limit, i.e., the value of state global
; 'last-step-limit if the value of state global 'step-limit-start is not nil,
; else the value from the acl2-defaults-table; see initial-step-limit.

  ":Doc-Section Other

  limit the number of steps for proofs~/

  ~bv[]
  Examples:

  ; Limit (mini-proveall) to 100,000 prover steps (which is enough to complete)
  (with-prover-step-limit 100000 (mini-proveall))

  ; Same as above for the inner call of with-prover-step-limit; so the
  ; mini-proveall call completes, but then we get an error because the second
  ; argument of the outer with-prover-step-limit call took more than 200
  ; steps.
  (with-prover-step-limit 200 (with-prover-step-limit 100000 (mini-proveall)))

  ; The inner call limit (mini-proveall) to 200 prover steps, which fails
  ; almost immediately. 
  (with-prover-step-limit 100000 (with-prover-step-limit 200 (mini-proveall)))

  ; Do not limit the number of prover steps, regardless of such a limit imposed
  ; globally or by the surrounding context.
  (with-prover-step-limit nil (mini-proveall))

  ; Limit the indicated theorem to 100 steps, and if the proof does not
  ; complete or it fails, then put down a label instead.
  (mv-let (erp val state)
          (with-prover-step-limit
           100
           (thm (equal (append (append x x) x)
                       (append x x x))))
          (if erp
              (deflabel foo :doc \"Attempt failed.\")
            (value (list :succeeded-with val))))~/

  General Form:
  (with-prover-step-limit expr form)
  ~ev[]
  where ~c[form] is arbitrary, and ~c[expr] evaluates either to ~c[nil] or else
  to a natural number not exceeding the value of ~c[*default-step-limit*].
  (A special value, ~c[:start], is also legal but is only used internally by
  ACL2, so we do not document it here.)  If the value of ~c[expr] is ~c[nil] or
  is the value of ~c[*default-step-limit*], then no limit is placed on the
  number of prover steps during processing of ~c[form].  Otherwise, that value
  is the maximum number of prover steps permitted during evaluation of ~c[form]
  before an error occurs.

  ~l[set-prover-step-limit] for a related utility that sets the limit on prover
  steps globally instead of setting it for just one form, and for a discussion
  of the notion of ``prover steps'', which could change in future ACL2
  releases.  For a related utility based on time instead of prover steps,
  ~pl[with-prover-time-limit].

  Depending on the machine you are using, you may have only (very roughly) a
  half-hour of time before the number of prover steps exceeds the maximum
  step-limit, which is one less than the value of ~c[*default-step-limit*].
  Note however the exception stated above: if the value of ~c[expr] is ~c[nil]
  or is the value of ~c[*default-step-limit*], then no limit is placed on the
  number of prover steps during processing of ~c[form].

  Logically, ~c[(with-prover-step-limit expr form)] is equivalent to ~c[form],
  except that if the number of prover steps during evaluation of ~c[form]
  exceeds the value specified by the value of ~c[expr] (other than the
  exceptional case noted just above), then that proof will abort.

  Although ~c[with-prover-step-limit] behaves like an ACL2 function in the
  sense that it evaluates both its arguments, it is however actually a macro
  that behaves as follows.  (1) The value of its first (step limit) argument
  affects the evaluation of its second argument (by causing an error during
  that evaluation if too many prover steps are needed).  (2) The second
  argument can return multiple values (~pl[mv]), which are then returned by the
  call of ~c[with-prover-step-limit].  (3) Thus, there is not a fixed output
  ~il[signature] for ~c[with-prover-step-limit] (not surprisingly, since it is
  a macro).~/"

  (with-prover-step-limit-fn limit form))

(defmacro save-event-state-globals (form)

; Form should evaluate to an error triple.

; We assign to saved-output-reversed, rather than binding it, so that saved
; output for gag-mode reply (using pso or psog) is available outside the scope
; of with-ctx-summarized.

  `(state-global-let*
    ((accumulated-ttree nil)
     (gag-state nil)
     (print-base 10 set-print-base)
     (proof-tree-ctx nil)
     (saved-output-p t))
    (pprogn (f-put-global 'saved-output-reversed nil state)
            (with-prover-step-limit :start ,form))))

(defmacro with-ctx-summarized (ctx body)

; A typical use of this macro by an event creating function is:
; (with-ctx-summarized (cons 'defun name)
;   (er-progn ... 
;             (er-let* (... (v form) ...)
;             (install-event ...))))

; If body changes the installed world then the new world must end with an
; event-landmark (we cause an error otherwise).  The segment of the new world
; back to the previous event-landmark is scanned for redefined names and an
; appropriate warning message is printed, as per ld-redefinition-action.

; The most obvious way to satisfy this restriction on world is for each
; branch through body to (a) stop with stop-redundant-event, (b) signal an
; error, or (c) conclude with install-event.  Two of our current uses of this
; macro do not follow so simple a paradigm.  In include-book-fn we add many
; events (in process-embedded-events) but we do conclude with an install-event
; which couldn't possibly redefine any names because no names are defined in
; the segment from the last embedded event to the landmark for the include-book
; itself.  In certify-book-fn we conclude with an include-book-fn.  So in both
; of those cases the scan for redefined names ends quickly (without going into
; the names possibly redefined in the embedded events) and finds nothing to
; report.

; This macro initializes the timers for an event and then executes the supplied
; body, which should return an error triple.  Whether an error is signalled or
; not, the macro prints the summary and then pass the error triple on up.  The
; stats must be available from the state.  In particular, we print redefinition
; warnings that are recovered from the currently installed world in state and
; we print the runes from 'accumulated-ttree.

  `(let ((ctx ,ctx)
         (wrld0 (w state)))
     (pprogn (initialize-summary-accumulators state)
             (mv-let
              (erp val state)
              (save-event-state-globals
               (mv-let (erp val state)
                       (pprogn
                        (push-io-record
                         :ctx
                         (list 'mv-let
                               '(col state)
                               '(fmt "Output replay for: "
                                     nil (standard-co state) state nil)
                               (list 'mv-let
                                     '(col state)
                                     (list 'fmt-ctx
                                           (list 'quote ,ctx)
                                           'col
                                           '(standard-co state)
                                           'state)
                                     '(declare (ignore col))
                                     '(newline (standard-co state) state)))
                         state)
                        ,body)
                       (pprogn (print-summary erp
                                              (equal wrld0 (w state))
                                              ctx state)
                               (mv erp val state))))

; In the case of a compound event such as encapsulate, we do not want to save
; io? forms for proof replay that were generated after a failed proof attempt.
; Otherwise, if we do not set the value of 'saved-output-p below to nil, then
; replay from an encapsulate with a failed defthm will pop warnings more often
; than pushing them (resulting in an error from pop-warning-frame).  This
; failure (without setting 'saved-output-p below) happens because the pushes
; are only from io? forms saved inside the defthm, yet we were saving the
; pops from the enclosing encapsulate.

              (pprogn (f-put-global 'saved-output-p nil state)
                      (mv erp val state))))))

; Essay on the proved-functional-instances-alist

; The world global 'proved-functional-instances-alist caches information about
; theorems proved on behalf of functional instantiation, in order to avoid the
; cost of re-proving such theorems.  In this Essay we track the flow of
; information to and from that world global.

; The above world global is a list of the following records.

(defrec proved-functional-instances-alist-entry

; Constraint-event-name is the name of an event such that the functional
; instance of that event's constraint (i.e., function's constraint or axiom's
; 'theorem property) by restricted-alist was proved on behalf of the event
; named behalf-of-event-name.  Note that behalf-of-event-name could be 0, e.g.,
; for a verify-guards event.  We arrange that restricted-alist is sorted; see
; the comment in event-responsible-for-proved-constraint.

  (constraint-event-name restricted-alist . behalf-of-event-name)
  t)

; In a nutshell, these records have the following life cycle:
; (1) They are created by hint translation, appealing to the existing value of
;     world global 'proved-functional-instances-alist to prune the list.
; (2) They go into tag-trees when hints are applied; see calls of
;     add-to-tag-tree with tags :use and :by in apply-use-hint-clauses and
;     apply-top-hints-clause1, respectively.
; (3) They are extracted from those tag-trees when events are installed.

; We focus now on (1).  Hint translation creates these records with functions
; translate-use-hint and translate-by-hint.  Translate-use-hint returns an
; object of the form

; (lmi-lst (hyp1 ... hypn) cl k event-names new-entries)

; while translate-by-hint returns an object of the form
;
; (lmi-lst thm-cl-set constraint-cl k event-names new-entries).

; In each case, new-entries is a list of
; proved-functional-instances-alist-entry records created by
; translate-lmi/functional-instance; just follow the call tree down from
; translate-use-hint or translate-by-hint to translate-lmi and then
; translate-lmi/functional-instance.  But following the call tree further, we
; see that new-entries ultimately comes from relevant-constraints, which in
; turn passes along the new-entries created by relevant-constraints1-axioms and
; relevant-constraints1.  These two functions use the already-existing records
; from world global 'proved-functional-instances-alist to prune the set of
; generated constraints (and save the behalf-of-event-name fields justifying
; such pruning for a suitable message -- see the call of tilde-@-lmi-phrase in
; apply-top-hints-clause-msg1).  These same two functions
; (relevant-constraints1-axioms and relevant-constraints1) also return a list
; of new proved-functional-instances-alist-entry records.

; The records created as above are missing the :behalf-of-event-name field
; (i.e., its value is nil), and that is how they go into tag-trees as
; components of values associated with :use and :by tags.  That missing field
; is eventually filled in by
; supply-name-for-proved-functional-instances-alist-entry in
; proved-functional-instances-from-tagged-objects, which is called by
; install-event in order to update world global
; 'proved-functional-instances-alist.

; End of Essay on the proved-functional-instances-alist

(defun supply-name-for-proved-functional-instances-alist-entry (name lst)
  (cond
   ((endp lst) nil)
   (t (cons (change proved-functional-instances-alist-entry (car lst)
                    :behalf-of-event-name name)
            (supply-name-for-proved-functional-instances-alist-entry name (cdr lst))))))

(defun proved-functional-instances-from-tagged-objects (name lst)

; For context, see the Essay on the proved-functional-instances-alist.

; Returns a list of proved-functional-instances-alist-entry records.  Lst is a
; list of values generated by calls

; (cdr (assoc-eq key (access prove-spec-var pspv :hint-settings)))

; where key is :use or :by, and where each member of lst is a value returned by
; translate-use-hint and translate-by-hint,

; (list x0 x1 x2 x3 x4 new-entries)

; -- although in the case of :by, this value could be an atom.

  (cond
   ((null lst) nil)
   ((atom (cdr (car lst)))
    (proved-functional-instances-from-tagged-objects name (cdr lst)))
   (t (append (supply-name-for-proved-functional-instances-alist-entry
               name (nth 5 (car lst)))
              (proved-functional-instances-from-tagged-objects
               name (cdr lst))))))

; Statistical and related information related to image size.
; 
; Here is some information collected while first creating a small version near
; the completion of Version 1.8.
; 
; At one point we had the following size statistic, using GCL 2.0:
; 
; -rwxrwxr-x  1 kaufmann 13473876 May  1 11:27 small-saved_acl2
; 
; We were able to account for nearly all of this 13.5 megabytes by the following
; reckoning.  Some associated code follows.
; 
;  3.2    Raw GCL 2.0
;  2.9    Additional space from loading ACL2 object files
;         [note:  not much more than Nqthm, less than Pc-Nqthm!]
;  3.7    Conses (327648) from (count-objects (w state)), less those that
;         are from constants: (* 12 (- 327648 (- 21040 145))).  Note:
;         36,236 = (length (w state))
;  0.9    Extra conses (72888) generated by (get sym *CURRENT-ACL2-WORLD-KEY*);
;         see code below.  The first few such numbers, in order, are:
;         ((4207 . EVENT-LANDMARK) (3806 . COMMAND-LANDMARK)
;          (3734 . CLTL-COMMAND) (424 . EVENT-INDEX) (384 . COMMAND-INDEX)
;          (103 . PC-COMMAND-TABLE) (76 . PRIN1-WITH-SLASHES1) (75 . NTH)
;          (74 . NONCONSTRUCTIVE-AXIOM-NAMES) (72 . UPDATE-NTH))
;  0.3    Extra conses (23380) generated on symbol-plists; see code below
;  0.9    Mystery conses, (- 5.8 (+ 3.7 0.9 0.3)).  Where does 5.8 come from?
;         It's (* SYSTEM:LISP-PAGESIZE (- 1617 200)), where 1617 is the number
;         of cons pages in the ACL2 image and 200 is the number in an image
;         obtained by loading the .o files.
;  0.7    Extra cell space, other than cons, over the image obtained from .o
;         files only (including string, fixnum, ..., arrays for enabled
;         structures and type-set tables, ...):
;         (* SYSTEM:LISP-PAGESIZE
;            (- (+ 34 162 1 2 73 6 20)
;               (+  3  74 1 1 27 6 18)))
;  0.4    Other extra space, which is probably NOT related to TMP1.o space
;         (because presumably that space doesn't show up in (room)):
;         (* SYSTEM:LISP-PAGESIZE
;            (- (+ 6 107)
;               (+ 1 11)))
;  0.4    TMP1.o size calculated by:  (- 12195924 11823188), the difference
;         in sizes of two images built using (acl2::load-acl2 t) followed by
;         (initialize-acl2 nil nil t), but using a patch the second time that
;         avoided loading TMP1.o.
; ---
; 13.4    Total
; 
; NOTE:  From
; 
; ACL2>(length (w state))
; 36351
; 
; we suspect that it would not be easy to significantly reduce the figure from
; (count-objects (w state)) above.
; 
; Some relevant code:
; 
; ;;;;;;;;;;;;;;; count.lisp
; 
; (eval-when (load)
;            (si::allocate 'fixnum 100)))
; 
; (defvar *monitor-count* nil)
; 
; (defvar *string-count*
;   (make-array$ '(1) :initial-element (the fixnum 0) :element-type 'fixnum))
; 
; (defvar *cons-count*
;   (make-array$ '(1) :initial-element (the fixnum 0) :element-type 'fixnum))
; 
; (defvar *count-hash-table*
;   (make-hash-table :test 'eq :size 500000))
; 
; (defun increment-string-count (len)
;   (declare (type fixnum len))
;   (cond ((and *monitor-count*
;               (= (the fixnum
;                    (logand (the fixnum (aref *string-count* 0))
;                            (the fixnum 4095)))
;                  0))
;          (format t "String count: ~s" (aref *string-count* 0))))
;   (setf (aref (the (array fixnum (1)) *string-count*)
;               0)
;         (the fixnum (1+ (the fixnum
;                              (+ (the fixnum len)
;                                 (the fixnum (aref *string-count* 0)))))))
;   t)
; 
; (defun increment-cons-count ()
;   (cond ((and *monitor-count*
;               (= (the fixnum
;                    (logand (the fixnum (aref *cons-count* 0))
;                            (the fixnum 4095)))
;                  0))
;          (format t "Cons count: ~s" (aref *cons-count* 0))))
;   (setf (aref (the (array fixnum (1)) *cons-count*)
;               0)
;         (the fixnum (+ 1 (the fixnum (aref *cons-count* 0)))))
;   t)
; 
; (defvar *acl2-strings*)
; 
; (defun count-objects1 (x)
;   (cond
;    ((consp x)
;     (cond
;      ((gethash x *count-hash-table*)
;       nil)
;      (t
;       (increment-cons-count)
;       (setf (gethash x *count-hash-table*) t)
;       (count-objects1 (car x))
;       (count-objects1 (cdr x)))))
;    ((stringp x)
;     (or (gethash x *count-hash-table*)
;         (progn (increment-string-count (the fixnum (length x)))
;                (setq *acl2-strings* (cons x *acl2-strings*))
;                (setf (gethash x *count-hash-table*) t))))))
; 
; (defun count-objects (x &optional clear)
;   (setq *acl2-strings* nil)
;   (setf (aref *cons-count* 0) 0)
;   (setf (aref *string-count* 0) 0)
;   (when clear
;     (clrhash *count-hash-table*))
;   (count-objects1 x)
;   (list 'cons-count (aref *cons-count* 0)
;         'string-count (aref *string-count* 0)))
; 
; ;;;;;;;;;;;;;;; end of count.lisp
; 
; (compile
;  (defun extra-count (&aux ans)
;    ;;  (count-objects (w state)) already done
;    (do-symbols (sym "ACL2")
;      (let ((temp (get sym *CURRENT-ACL2-WORLD-KEY*)))
;        (cond (temp
;               (let ((count (count-objects temp)))
;                 (cond
;                  (count (push (cons sym count) ans))))))))
;    ans))
; 
; (progn (setq new-alist
;              (stable-sort
;               (loop for x in (extra-count)
;                     collect (cons (caddr x) (car x)))
;               (function (lambda (x y) (> (car x) (car y))))))
;        17)
; 
; (loop for x in new-alist
;       sum (car x))
; 
; ACL2>(take 10 new-alist)
; ((4207 . EVENT-LANDMARK) (3806 . COMMAND-LANDMARK)
;  (3734 . CLTL-COMMAND) (424 . EVENT-INDEX) (384 . COMMAND-INDEX)
;  (103 . PC-COMMAND-TABLE) (76 . PRIN1-WITH-SLASHES1) (75 . NTH)
;  (74 . NONCONSTRUCTIVE-AXIOM-NAMES) (72 . UPDATE-NTH))
; 
; ACL2>(length new-alist)
; 3835
; 
; Note that the symbol-plists also take up space.
; 
; (compile
;  (defun more-count (&aux ans)
;    ;;  (count-objects (w state)) already done
;    (do-symbols (sym "ACL2")
;      (let ((temp (symbol-plist sym)))
;        (cond (temp
;               (let ((count (count-objects temp)))
;                 (cond
;                  (count (push (cons (cadr count) sym) ans))))))))
;    ans))
; 
; (progn (setq more-alist
;              (stable-sort
;               (more-count)
;               (function (lambda (x y) (> (car x) (car y))))))
;        17)
; 
; ACL2>(car more-alist)
; (180 . AREF)
; 
; ACL2>(loop for x in more-alist sum (car x))
; [lots of GCs]
; 38657
; [Note:  Was 7607 using LISP package in raw GCL.]
; 
; Note:  There are 3835 symbols for which ACL2 causes at least two conses on
; their symbol-plist, in the following sense.
; 
; (let ((temp 0))
;        (do-symbols (x "ACL2")
;          (when (get x *CURRENT-ACL2-WORLD-KEY*)
;            (setq temp (1+ temp))))
;        temp)
; 
; But that still leaves (- 38657 (+ 7607 (* 2 3835))) = 23380 conses not
; accounted for.  That's 281K of memory for "phantom" symbol-plist conses?
; 
; Consider just those conses in (w state) other than 'const conses, since (except
; for the cell used to extend (w state)) these are part of the load image.
; 
; (compile (defun foo ()
;            (let ((temp (loop for trip in (w state)
;                              when (eq (cadr trip) 'const)
;                              collect trip)))
;              (list (length temp) (count-objects temp)))))
; (foo)
; -->
; (145 (CONS-COUNT 21040 STRING-COUNT 5468))
; 
; End of statistical and related information related to image size.

(defun add-command-landmark (defun-mode form cbd last-make-event-expansion
                              wrld)

; As with add-event-landmark above, we first update the world index
; and then add the command-landmark.  However, here it is crucial that
; the index be inside the landmark, i.e., that the landmark happen
; last.  Suppose we put the landmark down first and then added the
; index for that landmark.  If we later did a :ubt of the subsequent
; command, we would kill the index entry.  No harm would come then.
; But n commands later we would find the index out of sync with the
; maximum command number.  The problem is that :ubt keys on
; 'command-landmark and we ought to keep them outside everything else.

; The function maybe-add-command-landmark, which ld-loop uses to add
; command-landmarks in response to user commands, relies upon the fact
; that well-formed worlds always contain a command-landmark as their
; first element.

; Defun-Mode is generally the default-defun-mode of the world in which this
; form is being executed.  But there are two possible exceptions.  When we add
; the command landmarks for enter-boot-strap-mode and exit-boot-strap-mode we
; just use the defun-mode :logic.  That happens to be correct for
; exit-boot-strap-mode, but is wrong for enter-boot-strap-mode, which today is
; being executed with default-defun-mode :program.  But it is irrelevant
; because neither of those two commands are sensitive to the
; default-defun-mode.

  (global-set 'command-landmark
              (make-command-tuple
               (next-absolute-command-number wrld)
               defun-mode
               form
               cbd
               last-make-event-expansion)
              (update-world-index 'command wrld)))

(defun find-longest-common-retraction1 (wrld1 wrld2)
  (cond ((equal wrld1 wrld2) wrld1)
        (t (find-longest-common-retraction1
            (scan-to-command (cdr wrld1))
            (scan-to-command (cdr wrld2))))))

(defun find-longest-common-retraction1-event (wrld1 wrld2)
  (cond ((equal wrld1 wrld2) wrld1)
        (t (find-longest-common-retraction1
            (scan-to-event (cdr wrld1))
            (scan-to-event (cdr wrld2))))))

(defun find-longest-common-retraction (event-p wrld1 wrld2)

; Wrld1 and wrld2 are two worlds.  We find and return a wrld3 that
; concludes with a command-landmark such that both wrld1 and wrld2 are
; extensions of wrld3.  Of course, nil would do, but we find the
; longest.

  (cond
   (event-p
    (let* ((n (min (max-absolute-event-number wrld1)
                   (max-absolute-event-number wrld2))))
      (find-longest-common-retraction1-event
       (scan-to-landmark-number 'event-landmark n wrld1)
       (scan-to-landmark-number 'event-landmark n wrld2))))
   (t
    (let* ((n (min (max-absolute-command-number wrld1)
                   (max-absolute-command-number wrld2))))
      (find-longest-common-retraction1
       (scan-to-landmark-number 'command-landmark n wrld1)
       (scan-to-landmark-number 'command-landmark n wrld2))))))

(defun install-global-enabled-structure (wrld state)
  (cond
   ((null wrld) ; see initial call of set-w in enter-boot-strap-mode
    state)
   (t
    (let* ((augmented-theory (global-val 'current-theory-augmented wrld))
           (ens (f-get-global 'global-enabled-structure state))
           (theory-array (access enabled-structure ens :theory-array))
           (current-theory-index (global-val 'current-theory-index wrld))
           (eq-theories (equal augmented-theory (cdr theory-array))))
      (cond ((and eq-theories
                  (eql current-theory-index
                       (access enabled-structure ens :index-of-last-enabling)))
             state)
            ((and eq-theories
                  (< current-theory-index
                     (car (dimensions (access enabled-structure ens
                                              :array-name)
                                      theory-array))))
             (f-put-global 'global-enabled-structure
                           (change enabled-structure ens
                                   :index-of-last-enabling
                                   current-theory-index)
                           state))
            (t
             (mv-let (erp new-ens state)
                     (load-theory-into-enabled-structure
                      :no-check augmented-theory t
                      ens nil current-theory-index wrld
                      'irrelevant-ctx state)
                     (assert$ (null erp)
                              (f-put-global 'global-enabled-structure
                                            new-ens
                                            state)))))))))

#+(and (not acl2-loop-only) hons)
(defvar *defattach-fns*)

(defun set-w (flg wrld state)

; Ctx is ignored unless we are extending the current ACL2 world, in which case
; if ctx is not nil, there will be a check on the new theory from a call of
; maybe-warn-about-theory.

; This is the only way in ACL2 (as opposed to raw Common Lisp) to
; install wrld as the current-acl2-world.  Flg must be either
; 'extension or 'retraction.  Logically speaking, all this function
; does is set the state global value of 'current-acl2-world in state
; to be wrld and possibly set current-package to "ACL2".  Practically,
; speaking however, it installs wrld on the symbol-plists in Common
; Lisp.  However, wrld must be an extension or retraction, as
; indicated, of the currently installed ACL2 world.

; Statement of Policy regarding Erroneous Events and 
; Current ACL2 World Installation:

; Any event which causes an error must leave the current-acl2-world of
; state unchanged.  That is, if you extend the world in an event, you
; must revert on error back to the original world.  Once upon a time
; we enforced this rule in LD, simply by reverting the world on every
; erroneous command.  But then we made that behavior conditional on
; the LD special ld-error-triples.  If ld-error-triples is nil, then
; (mv t nil state) is not treated as an error by LD.  Hence, an
; erroneous DEFUN, say, evaluated with ld-error-triples nil, does not
; cause LD to revert.  Therefore, DEFUN must manage the reversion
; itself.

  #+acl2-loop-only
  (declare (xargs :guard
                  (and (or (eq flg 'extension)
                           (eq flg 'retraction))
                       (plist-worldp wrld)
                       (known-package-alistp
                        (getprop 'known-package-alist 'global-value nil
                                 'current-acl2-world
                                 wrld))
                       (symbol-alistp
                        (getprop 'acl2-defaults-table 'table-alist nil
                                 'current-acl2-world
                                 wrld))
                       (state-p state))))

  #+acl2-loop-only
  (pprogn
   (f-put-global 'current-acl2-world

; Here comes a slimy trick to avoid compiler warnings.

                 (prog2$ flg wrld)
                 state)
   (install-global-enabled-structure wrld state)
   (cond ((find-non-hidden-package-entry (current-package state)
                                         (known-package-alist state))
          state)
         (t (f-put-global 'current-package "ACL2" state))))
  #-acl2-loop-only
  (cond ((live-state-p state)
         (cond ((and *wormholep*
                     (not (eq wrld (w *the-live-state*))))
                (push-wormhole-undo-formi 'cloaked-set-w! (w *the-live-state*)
                                          nil)))
         (let (#+hons (*defattach-fns* nil))
           (cond ((eq flg 'extension)
                  (extend-world1 'current-acl2-world wrld)
                  state)
                 (t
                  (retract-world1 'current-acl2-world wrld)
                  state))))
        (t (f-put-global 'current-acl2-world wrld state)
           (install-global-enabled-structure wrld state)
           (cond ((find-non-hidden-package-entry (current-package state)
                                                 (known-package-alist state))
                  state)
                 (t (f-put-global 'current-package "ACL2" state))))))

(defun set-w! (wrld state)

; This function makes wrld the current-acl2-world, but doesn't require
; that wrld be either an 'extension or a 'retraction of the current
; one.  Note that any two worlds, wrld1 and wrld2, can be related by a
; retraction followed by an extension: retract wrld1 back to the first
; point at which it is a tail of wrld2, and then extend that world to
; wrld2.  That is what we do.

  (let ((w (w state)))
    (cond ((equal wrld w)
           state)
          (t
           (pprogn (set-w 'retraction
                          (find-longest-common-retraction

; It is important to use events rather than commands here when certifying or
; including a book.  Otherwise, when make-event expansion extends the world, we
; will have to revert back to the beginning of the most recent top-level
; command and install the world from there.  With a large number of such
; make-event forms, such quadratic behavior could be unfortunate.  And, the
; file books/make-event/stobj-test.lisp illustrates that if after make-event
; expansion we revert to the beginning of the book being certified, we could
; lose the setting of a stobj in that expansion.

; But really, there seems no point in using command landmarks here (as we
; always did until adding this use of event landmarks in Version_3.1).  After
; all, why back up all the way to a command landmark?  (With a different scheme
; we can imagine a reason; we'll get to that at the end of this long comment.)
; Moreover, if installation of an event were to consult the installed world, it
; would be important that all previous events have already been installed.  For
; example, in the hons version of v3-6-1, the following example caused a hard
; error, as shown and explained below.

; (defun foo (x)
;   (declare (xargs :guard t))
;   (cons x x))
; 
; (progn
;   (defun foo-cond (x)
;     (declare (ignore x)
;              (xargs :guard 't))
;     nil)
;   (memoize 'foo :condition-fn 'foo-cond)
;   (progn
;     (deflabel some-label)
;     (defthm non-thm (equal x y))))

; HARD ACL2 ERROR in SCAN-TO-LANDMARK-NUMBER:  We have scanned the world
; looking for absolute event number 6463 and failed to find it....

; How could this have happened?  First note that the cltl-command for memoize
; invoked function cltl-def-from-name, which was looking in the installed world
; for the definition of foo-cond.  But the world containing that 'cltl-command
; had not yet been installed in the state, because extend-world1 only installs
; the world after processing all the new trips.  So when the defthm failed, its
; revert-world-on-error first retracted the world all the way back to just
; after the command for foo (not to just after the deflabel).  The above error
; occurred because the attempt to fetch the cltl definition of foo-cond was
; passed the installed world: the world just after the introduction of foo.
; Now we don't get that error: instead we only roll back to the event landmark
; for the deflabel, and then we back out gracefully.  Actually, we have also
; changed the implementation of memoize to avoid looking in the installed world
; for the cltl definition.  But we still like using event landmarks, which can
; result in a lot less processing of world triples since we are not backing up
; all the way to a command landmark.

; Finally we address the "different scheme" promised above for the use of
; comman landmarks.  In a chat with Sol Swords we came to realize that it would
; likely be more efficient to pop all the way back to the last command, and not
; extend that command world at all.  (Recall that each command is protected by
; ld-read-eval-print.)  For example, with the failure of non-thm above, its
; revert-world-on-error puts us at just after the deflabel; then the
; revert-world-on-error for the inner progn puts us at just after the memoize;
; and finally, the revert-world-on-error of the outer progn puts us just after
; the command introducing foo.  Why not just revert directly to that final
; world?  We could, but the current scheme has stood the test of time as being
; robust and efficient, albeit using command landmarks instead of event
; landmarks (and the latter should help performance rather than hurt it).  But
; here is a more compelling reason not to try such a scheme.  At the time a
; form fails, it is hard to know whether the error really cannot be tolerated
; and should pop us out to the start of the command.  Consider for example
; something like:

;    (progn
;      (defun h1 (x) x)
;      (make-event (mv-let (erp val state) 
;                          (defthm my-bad (equal t nil))
;                          (declare (ignore erp val))
;                          (value '(value-triple nil))))
;      (defun h2 (x) (h1 x)))

; This event succeeds, and we want that to continue to be the case.  It is hard
; to see how that could work if we were left in the world before h1 when the
; make-event failed.

; Old code, using event landmarks (rather than command landmarks) only in the
; indicated situations:

;                          (or (f-get-global 'certify-book-info state)
;                              (global-val 'include-book-path w))

                           t ; always use event landmarks (see comments above)
                           wrld
                           w)
                          state)
                   (set-w 'extension
                          wrld
                          state))))))

(defmacro revert-world-on-error (form)

; With this macro we can write (revert-world-on-error &) and if &
; causes an error the world will appear unchanged (because we revert
; back to the world of the initial state).  The local variable used to
; save the old world is a long ugly name only because we prohibit its
; use in ,form.  (Historical Note: Before the introduction of
; acl2-unwind-protect we had to use raw lisp to handle this and the
; handling of that special variable was very subtle.  Now it is just
; an ordinary local of the let.)

  `(let ((revert-world-on-error-temp (w state)))
     (acl2-unwind-protect
      "revert-world-on-error"
      (check-vars-not-free (revert-world-on-error-temp) ,form)
      (set-w! revert-world-on-error-temp state)
      state)))

(defun chk-theory-expr-value1 (lst wrld expr macro-aliases ctx state)

; A theory expression must evaluate to a common theory, i.e., a
; truelist of rule name designators.  A rule name designator, recall,
; is something we can interpret as a set of runes and includes runes
; themselves and the base symbols of runes, such as APP and
; ASSOC-OF-APP.  We already have a predicate for this concept:
; theoryp.  This checker checks for theoryp but with better error
; reporting.

  (cond ((atom lst)
         (cond ((null lst)
                (value nil))
               (t (er soft ctx
                      "The value of the alleged theory expression ~x0 ~
                       is not a true list and, hence, is not a legal ~
                       theory value.  In particular, the final ~
                       non-consp cdr is the atom ~x1.  See :DOC theories."
                      expr lst))))
        ((rule-name-designatorp (car lst) macro-aliases wrld)
         (chk-theory-expr-value1 (cdr lst) wrld expr macro-aliases ctx
                                 state))
        (t (er soft ctx
               "The value of the alleged theory expression ~x0 ~
                includes the element ~x1, which we do not know how to ~
                interpret as a rule name.  See :DOC theories and :DOC ~
                rune."
               expr (car lst)))))

(defun chk-theory-expr-value (lst wrld expr ctx state)

; This checker ensures that expr, whose value is lst, evaluated to a theoryp.
; Starting after Version_3.0.1 we no longer check the theory-invariant table,
; because the ens is not yet available at this point.

  (chk-theory-expr-value1 lst wrld expr (macro-aliases wrld) ctx state))

(defun theory-fn-translated-callp (x)

; We return t or nil.  If t, then we know that the term x evaluates to a runic
; theory.  See also theory-fn-callp.

  (and (nvariablep x)
       (not (fquotep x))
       (member-eq (car x)
                  '(current-theory-fn
                    e/d-fn
                    executable-counterpart-theory-fn
                    function-theory-fn
                    intersection-theories-fn
                    set-difference-theories-fn
                    theory-fn
                    union-theories-fn
                    universal-theory-fn))
       t))

(defun eval-theory-expr (expr ctx wrld state)

; returns a runic theory

  (cond ((equal expr '(current-theory :here))
         (mv-let (erp val latches)
                 (ev '(current-theory-fn ':here world)
                     (list (cons 'world wrld))
                     state nil nil t)
                 (declare (ignore latches))
                 (mv erp val state)))
        (t (er-let*
            ((trans-ans
              (state-global-let*
               ((guard-checking-on t) ; see the Essay on Guard Checking
                ;;; (safe-mode t) ; !! experimental deletion
                )
               (simple-translate-and-eval
                expr
                (list (cons 'world wrld))
                nil
                "A theory expression" ctx wrld state t))))

; Trans-ans is (term . val).

            (cond ((theory-fn-translated-callp (car trans-ans))
                   (value (cdr trans-ans)))
                  (t
                   (er-progn
                    (chk-theory-expr-value (cdr trans-ans) wrld expr ctx state)
                    (value (runic-theory (cdr trans-ans) wrld)))))))))

(defun append-strip-cdrs (x y)

; This is (append (strip-cdrs x) y).

  (cond ((null x) y)
        (t (cons (cdr (car x)) (append-strip-cdrs (cdr x) y)))))

(defun no-rune-based-on (runes symbols)
  (cond ((null runes) t)
        ((member-eq (base-symbol (car runes)) symbols)
         nil)
        (t (no-rune-based-on (cdr runes) symbols))))

(defun revappend-delete-runes-based-on-symbols1 (runes symbols ans)

; We delete from runes all those with base-symbols listed in symbols
; and accumulate them in reverse order onto ans.

  (cond ((null runes) ans)
        ((member-eq (base-symbol (car runes)) symbols)
         (revappend-delete-runes-based-on-symbols1 (cdr runes) symbols ans))
        (t (revappend-delete-runes-based-on-symbols1 (cdr runes)
                                                     symbols
                                                     (cons (car runes) ans)))))

(defun revappend-delete-runes-based-on-symbols (runes symbols ans)

; In computing the useful theories we will make use of previously stored values
; of those theories.  However, those stored values might contain "runes" that
; are no longer runes because of redefinition.  The following function is used
; to delete from those non-runes, based on the redefined base symbols.

; This function returns the result of appending the reverse of ans to the
; result of removing runes based on symbols from the given list of runes.  It
; should return a runic theory.

  (cond ((or (null symbols) (no-rune-based-on runes symbols))

; This case is not only a time optimization, but it also allows sharing.  For
; example, runes could be the 'current-theory, and in this case we will just be
; extending that theory.

         (revappend ans runes))
        (t (reverse
            (revappend-delete-runes-based-on-symbols1 runes symbols ans)))))

(defun current-theory1 (lst ans redefined)

; Lst is a cdr of wrld.  We wish to return the enabled theory as of the time
; lst was wrld.  When in-theory is executed it stores the newly enabled theory
; under the 'global-value of the variable 'current-theory.  When new rule names
; are introduced, they are automatically considered enabled.  Thus, the enabled
; theory at any point is the union of the current value of 'current-theory and
; the names introduced since that value was set.  However, :REDEF complicates
; matters.  See universal-theory-fn1.

  (cond ((null lst)
         #+acl2-metering (meter-maid 'current-theory1 500)
         (reverse ans)) ; unexpected, but correct
        ((eq (cadr (car lst)) 'runic-mapping-pairs)
         #+acl2-metering (setq meter-maid-cnt (1+ meter-maid-cnt))
         (cond
          ((eq (cddr (car lst)) *acl2-property-unbound*)
           (current-theory1 (cdr lst) ans
                            (add-to-set-eq (car (car lst)) redefined)))
          ((member-eq (car (car lst)) redefined)
           (current-theory1 (cdr lst) ans redefined))
          (t 
           (current-theory1 (cdr lst)
                            (append-strip-cdrs (cddr (car lst)) ans)
                            redefined))))
        ((and (eq (car (car lst)) 'current-theory)
              (eq (cadr (car lst)) 'global-value))

; We append the reverse of our accumulated ans to the appropriate standard
; theory, but deleting all the redefined runes.

         #+acl2-metering (meter-maid 'current-theory1 500)
         (revappend-delete-runes-based-on-symbols (cddr (car lst))
                                                  redefined ans))
        (t
         #+acl2-metering (setq meter-maid-cnt (1+ meter-maid-cnt))
         (current-theory1 (cdr lst) ans redefined))))

(defun first-n-ac-rev (i l ac)

; This is the same as first-n-ac, except that it reverses the accumulated
; result and traffics in fixnums -- more efficient if you want the reversed
; result.

  (declare (type (unsigned-byte 29) i)
           (xargs :guard (and (true-listp l)
                              (true-listp ac))))
  (cond ((zpf i)
         ac)
        (t (first-n-ac-rev (the (unsigned-byte 29)
                                (1- (the (unsigned-byte 29) i)))
                           (cdr l)
                           (cons (car l) ac)))))

(defun longest-common-tail-length-rec (old new acc)
  (declare (type (signed-byte 30) acc))
  #-acl2-loop-only
  (when (eq old new)
    (return-from longest-common-tail-length-rec (+ (length old) acc)))
  (cond ((endp old)
         (assert$ (null new)
                  acc))
        (t (longest-common-tail-length-rec (cdr old)
                                           (cdr new)
                                           (if (equal (car old) (car new))
                                               (1+f acc)
                                             0)))))

(defun longest-common-tail-length (old new)

; We separate out this wrapper function so that we don't need to be concerned
; about missing the #-acl2-loop-only case in the recursive computation, which
; could perhaps happen if we are in safe-mode and oneification prevents escape
; into Common Lisp.

  (longest-common-tail-length-rec old new 0))

(defun extend-current-theory (old-th new-th old-aug-th wrld)

; Logically this function just returns new-th.  However, the copy of new-th
; that is returned shares a maximal tail with old-th.  A second value similarly
; extends old-aug-th, under the assumption that old-aug-th is the
; augmented-theory corresponding to old-th; except, if old-aug-th is :none then
; the second value is undefined.

  (let* ((len-old (length old-th))
         (len-new (length new-th))
         (len-common
          (cond ((int= len-old len-new)
                 (longest-common-tail-length old-th new-th))
                ((< len-old len-new)
                 (longest-common-tail-length
                  old-th
                  (nthcdr (- len-new len-old) new-th)))
                (t
                 (longest-common-tail-length
                  (nthcdr (- len-old len-new) old-th)
                  new-th))))
         (take-new (- len-new len-common))
         (nthcdr-old (- len-old len-common))
         (new-part-of-new-rev
          (first-n-ac-rev (the-unsigned-byte! 29 take-new
                                              'extend-current-theory)
                          new-th
                          nil)))
    (mv (append (reverse new-part-of-new-rev)
                (nthcdr nthcdr-old old-th))
        (if (eq old-aug-th :none)
            :none
          (append (augment-runic-theory1 new-part-of-new-rev nil wrld nil)
                  (nthcdr nthcdr-old old-aug-th))))))

(defun update-current-theory (theory0 wrld)
  (mv-let (theory theory-augmented)
          (extend-current-theory

; It's not necessarily reasonable to assume that theory0 shares a lot of
; structure with the most recent value of 'current-theory.  But it could
; happen, so we take the opportunity to save space.  Consider the not uncommon
; case that theory0 is the value of (current-theory :here).  Theory0 may be eq
; to the value of 'current-theory, in which case this extend-current-theory
; call below will be cheap because it will just do a single eq test.  However,
; theory0 could be a copy of the most recent 'current-theory that doesn't share
; much structure with it, in which case it's a good thing that we are here
; calling extend-current-theory.

           (global-val 'current-theory wrld)
           theory0
           (global-val 'current-theory-augmented wrld)
           wrld)
          (global-set 'current-theory theory
                      (global-set 'current-theory-augmented theory-augmented
                                  (global-set 'current-theory-index
                                              (1- (get-next-nume wrld))
                                              wrld)))))

(defun put-cltl-command (cltl-cmd wrld wrld0)

; We extend wrld by noting cltl-cmd.  Wrld0 is supplied because it may more
; efficient for property lookup than wrld; it is critical therefore that wrld0
; and wrld have the same values of 'include-book-path,
; 'top-level-cltl-command-stack, and 'boot-strap-flg.

  (let ((wrld (if (or (global-val 'include-book-path wrld0)
                      (global-val 'boot-strap-flg wrld0))
                  wrld
                (global-set 'top-level-cltl-command-stack
                            (cons cltl-cmd
                                  (global-val 'top-level-cltl-command-stack
                                              wrld0))
                            wrld))))
    (global-set 'cltl-command cltl-cmd wrld)))

(defun install-event (val form ev-type namex ttree cltl-cmd
                          chk-theory-inv-p ctx wrld state)

; This function is the way to finish off an ACL2 event.  Val is the value to be
; returned by the event (in the standard error flag/val/state three-valued
; result).  Namex is either 0, standing for the empty set of names, an atom,
; standing for the singleton set of names containing that atom, or a true list
; of symbols, standing for the set of names in the list.  Each symbol among
; these names will be given an 'absolute-event-number property.  In addition,
; we set 'event-landmark 'global-value to an appropriate event tuple, thus
; marking the world for this event.  Cltl-cmd is the desired value of the
; 'global-value for 'cltl-command (see below).  Chk-theory-inv-p is generally
; nil, but is non-nil if we are to check theory invariants, and is :PROTECT if
; the call is not already in the scope of a revert-world-on-error.  Wrld is the
; world produced by the ACL2 event and state is the current state, and before
; extending it as indicated above, we extend it if necessary by an appropriate
; record of the proof obligations discharged in support of functional
; instantiation, in order to avoid such proofs in later events.

; Ttree is the final ttree of the event.  We install it as 'accumulated-ttree
; so that the runes reported in the summary are guaranteed to be those of the
; carefully tracked ttree passed along through the proof.  It is possible that
; the 'accumulated-ttree already in state contains junk, e.g., perhaps we
; accumulated some runes from a branch of the proof we have since abandoned.
; We try to avoid this mistake, but just to be sure that a successful proof
; reports the runes that we really believe got used, we do it this way.

; We store the 'absolute-event-number property for each name.  We set
; 'event-landmark.  We store the cltl-cmd as the value of the variable
; 'cltl-command (if cltl-cmd is non-nil).  We update the event index.  We
; install the new world as the current ACL2 world in state.  Non-logical code
; in set-w notes the 'cltl-command requests in the world and executes
; appropriate raw Common Lisp for effect.  This function returns the triple
; indicating a non-erroneous return of val.

; The installation of the world into state causes "secret" side-effects on the
; underlying lisp state, as controlled by 'cltl-command.  Generally, the value
; is a raw lisp form to execute, e.g., (defconst name val).  But when the car
; of the form is DEFUNS the general form is (DEFUNS defun-mode-flg ignorep def1
; ...  defn).  The raw lisp form to execute is actually (DEFUNS def1'
; ... defn'), where the defi' are computed from the defi depending on
; defun-mode-flg and ignorep.  Defun-Mode-flg is either nil (meaning the
; function is :non-executable or the parent event is an encapsulate which is
; trying to define the executable counterparts of the constrained functions) or
; a defun-mode (meaning the parent event is an executable DEFUNS and the
; defun-mode is the defun-mode of the defined functions).  Ignorep is
; 'reclassifying, '(defstobj . stobj-name), or nil.  If ignorep is nil, we add
; each def and its *1* counterpart, after pushing the old bodies on the undo
; stack.  If ignorep is 'reclassifying (which means we are reclassifying a
; :program fn to a :logic fn without changing its definition -- which is
; probably hand coded ACL2 source), we define only the *1* counterparts after
; pushing only the *1* counterparts on the undo stack.  If ignorep is
; '(defstobj . stobj-name) we do not add the def or its *1* counterpart, but we
; do push both the main name and the *1* name.  This is because we know
; defstobj will supply a symbol-function for the main name and its *1*
; counterpart in a moment.  We use the stobj-name in the *1* body to compute
; the stobjs-in of the function.  See the comment in add-trip.

; One might ask why we make add-trip do the oneify to produce the *1* bodies,
; instead of compute them when we generate the CLTL-COMMAND.  The reason is
; that we use the 'cltl-command of a DEFUN as the only place we can recover the
; exact ACL2 defun command that got executed.  (Exception: in the case that the
; :defun-mode is nil, i.e., the definition is non-executable, we have replaced
; the body with a throw-raw-ev-fncall.)

  (let ((currently-installed-wrld (w state)))
    (mv-let
     (chk-theory-inv-p theory-invariant-table)
     (cond ((member-eq (ld-skip-proofsp state)
                       '(include-book include-book-with-locals))
            (mv nil nil))
           (t (let ((tbl (table-alist 'theory-invariant-table
                                      currently-installed-wrld)))
                (cond ((null tbl) ; avoid work of checking theory invariant
                       (mv nil nil))
                      (t (mv chk-theory-inv-p tbl))))))
     (let* ((new-proved-fnl-insts
             (proved-functional-instances-from-tagged-objects
              (cond ((atom namex)

; We deliberately include the case namex = 0 here.

                     namex)
                    (t (car namex)))
              (append (strip-cars (tagged-objects :use ttree nil))
                      (tagged-objects :by ttree nil))))
            (wrld1 (if new-proved-fnl-insts
                       (global-set
                        'proved-functional-instances-alist
                        (append new-proved-fnl-insts
                                (global-val 'proved-functional-instances-alist
                                            wrld)) 
                        wrld)
                     wrld))

; We set world global 'skip-proofs-seen or 'redef-seen if ld-skip-proofsp or
; ld-redefinition-action (respectively) is non-nil and the world global is not
; already true.  This information is important for vetting a proposed
; certification world.  See the Essay on Soundness Threats.

            (wrld2 (cond
                    ((and (ld-skip-proofsp state)
                          (not (member-eq ev-type

; Comment on irrelevance of skip-proofs:

; The following event types do not generate any proof obligations, so for these
; it is irrelevant whether or not proofs are skipped.  Do not include defaxiom,
; or any other event that can have a :corollary rule class, since that can
; generate a proof obligation.  Also do not include encapsulate; even though it
; takes responsibility for setting skip-proofs-seen based on its first pass,
; nevertheless it does not account for a skip-proofs surrounding the
; encapsulate.

                                          '(include-book
                                            defchoose
                                            defconst
                                            defdoc
                                            deflabel
                                            defmacro
                                            defpkg
                                            defstobj
                                            deftheory
                                            in-arithmetic-theory
                                            in-theory
                                            push-untouchable
                                            remove-untouchable
                                            reset-prehistory
                                            set-body
                                            table)))

; We include the following test so that we can distinguish between the
; user-specified skipping of proofs and legitimate skipping of proofs by the
; system, such as including a book.

                          (not (f-get-global 'skip-proofs-by-system state))
                          (let ((old (global-val 'skip-proofs-seen wrld)))
                            (or (not old)

; In certify-book-fn we find a comment stating that "we are trying to record
; whether there was a skip-proofs form in the present book, not merely on
; behalf of an included book".  That is why here, we replace value
; (:include-book ...) for 'skip-proofs-seen.

                                (eq (car old) :include-book))))
                     (global-set 'skip-proofs-seen form wrld1))
                    (t wrld1)))
            (wrld3 (cond
                    ((and (ld-redefinition-action state)

; We tolerate redefinition inside a book, because there must have been a trust
; tag that allowed it.  We are only trying to protect against redefinition
; without a trust tag, especially in the certification world.  (Without a trust
; tag there cannot be any redefinition in a certified book anyhow.)

                          (not (global-val 'include-book-path wrld))
                          (not (global-val 'redef-seen wrld)))
                     (global-set 'redef-seen form wrld2))
                    (t wrld2)))
            (wrld4 (if cltl-cmd
                       (put-cltl-command cltl-cmd wrld3
                                         currently-installed-wrld)
                     wrld3))

; WARNING: Do not put down any properties here!  The cltl-command should be the
; last property laid down before the call of add-event-landmark.  We rely on
; this invariant when looking for 'redefined tuples in
; compile-uncompiled-defuns and compile-uncompiled-*1*-defuns.

            (wrld5 (add-event-landmark form ev-type namex wrld4
                                       (global-val 'boot-strap-flg
                                                   currently-installed-wrld))))
       (pprogn
        (f-put-global 'accumulated-ttree ttree state)
        (cond
         ((eq chk-theory-inv-p :protect)
          (revert-world-on-error
           (let ((state (set-w 'extension wrld5 state)))
             (er-progn
              (chk-theory-invariant1 :install
                                     (ens state)
                                     theory-invariant-table
                                     nil ctx state)
              (value val)))))
         (t (let ((state (set-w 'extension wrld5 state)))
              (cond (chk-theory-inv-p
                     (er-progn
                      (chk-theory-invariant1 :install
                                             (ens state)
                                             theory-invariant-table
                                             nil ctx state)
                      (value val)))
                    (t (value val)))))))))))

(deflabel redundant-events
  :doc
  ":Doc-Section Miscellaneous

  allowing a name to be introduced ``twice''~/

  Sometimes an event will announce that it is ``redundant''.  When
  this happens, no change to the logical ~il[world] has occurred.  This
  happens when the logical name being defined is already defined and
  has exactly the same definition, from the logical point of view.
  This feature permits two independent ~il[books], each of which defines
  some name, to be included sequentially provided they use exactly the
  same definition.~/

  When are two ~il[logical-name] definitions considered exactly the same?
  It depends upon the kind of name being defined.  See also the Notes below.

  A ~ilc[deflabel] event is never redundant.  This means that if you have a
  ~ilc[deflabel] in a book and that book has been included (without error),
  then references to that label denote the point in ~il[history] at which
  the book introduced the label.  See the note about shifting logical
  names, below.

  A ~ilc[defun] or ~ilc[mutual-recursion] (or ~ilc[defuns]) event is redundant
  if for each function to be introduced, there has already been introduced a
  function with the same name, the same formals, and syntactically identical
  ~c[:]~ilc[guard], ~c[:measure], type declarations, ~ilc[stobj]~c[s]
  declarations and ~c[body] (before macroexpansion), and an appropriate
  ~c[mode] (see the discussion of ``appropriate ~c[mode]s'' below).  Moreover,
  the order of the combined ~c[:]~ilc[guard] and type declarations must be the
  same in both cases.  Exceptions:~nl[]
  (1) If either definition is declared
  ~c[:non-executable] (~pl[defun-nx]), then the two events must be
  identical.~nl[]
  (2) It is permissible for one definition to have a ~c[:]~il[guard] of ~c[t]
  and the other to have no explicit guard (hence, the guard is implicitly
  ~c[t]).~nl[]
  (3) The ~c[:measure] check is avoided if we are skipping proofs (for example,
  during ~ilc[include-book]), and otherwise, the new definition may have a
  ~c[:measure] of ~c[(:? v1 ... vk)], where ~c[(v1 ... vk)] enumerates the
  variables occurring in the measure stored for the old definition.~nl[]
  (4) If either the old or new event is a ~ilc[mutual-recursion] event, then
  redundancy requires that both are ~ilc[mutual-recursion] events that define
  the same set of function symbols.

  A ~ilc[verify-guards] event is redundant if the function has already had
  its ~il[guard]s verified.

  A ~ilc[defaxiom] or ~ilc[defthm] event is redundant if there is already an axiom
  or theorem of the given name and both the formula (after
  macroexpansion) and the ~il[rule-classes] are syntactically identical.
  Note that a ~ilc[defaxiom] can make a subsequent ~ilc[defthm] redundant, and a
  ~ilc[defthm] can make a subsequent ~ilc[defaxiom] redundant as well.

  A ~ilc[defconst] is redundant if the name is already defined either with a
  syntactically identical ~c[defconst] event or one that defines it to have the
  same value.

  A ~ilc[defstobj] is redundant if there is already a ~c[defstobj] event with
  the same name that has exactly the same field descriptors (~pl[defstobj]), in
  the same order, and with the same ~c[:renaming] value if ~c[:renaming] is
  supplied for either event.

  A ~ilc[defmacro] is redundant if there is already a macro defined with the
  same name and syntactically identical arguments, ~il[guard], and body.

  A ~ilc[defpkg] is redundant if a package of the same name with exactly the
  same imports has been defined.

  A ~ilc[deftheory] is never redundant.  The ``natural'' notion of
  equivalent ~ilc[deftheory] forms is that the names and values of the two
  theory expressions are the same.  But since most theory expressions are
  sensitive to the context in which they occur, it seems unlikely to
  us that two ~ilc[deftheory]s coming from two sequentially included ~il[books]
  will ever have the same values.  So we prohibit redundant theory
  definitions.  If you try to define the same theory name twice, you
  will get a ``name in use'' error.

  An ~ilc[in-theory] event or ~ilc[defattach] event is never redundant because
  it doesn't define any name.

  A ~ilc[push-untouchable] event is redundant if every name supplied is
  already a member of the corresponding list of untouchable symbols.

  A ~ilc[remove-untouchable] event is redundant if no name supplied is
  a member of the corresponding list of untouchable symbols.

  A ~ilc[reset-prehistory] event is redundant if it does not cause any change.

  A ~ilc[set-body] event is redundant if the indicated body is already the
  current body.

  ~ilc[Defdoc] ~il[events] are never redundant because they don't define any
  name.  A ~ilc[table] event also does not define any name, but it is redundant
  when it sets the value already associated with a key of the table, or when
  it sets an entire table (using keyword ~c[:clear]) to its existing value;
  ~pl[table].

  An ~ilc[encapsulate] event is redundant if and only if a syntactically
  identical ~ilc[encapsulate] has already been executed under the same
  ~ilc[default-defun-mode], ~ilc[default-ruler-extenders], and
  ~ilc[default-verify-guards-eagerness].

  An ~ilc[include-book] is redundant if the book has already been included.

  ~em[Note About Built-in (Predefined) Functions and Macros:]

  Redundancy is restricted for built-in macros and functions that have special
  raw Lisp code.  Such redundancy is only legal in the context of ~ilc[LOCAL].
  This restriction is needed for soundness, for technical reasons omitted here
  (details may be found in a long comment about redundant-events in source
  function ~c[chk-acceptable-defuns-redundancy]).

  ~em[Note About Appropriate Modes:]

  Suppose a function is being redefined and that the formals, guards, types,
  stobjs, and bodies are identical.  When are the modes (~c[:]~ilc[program]
  or ~c[:]~ilc[logic]) ``appropriate?''  Identical modes are appropriate.
  But what if the old mode was ~c[:program] and the new mode is ~c[:logic]?
  This is appropriate, provided the definition meets the requirements of the
  logical definitional principle.  That is, you may redefine ``redundantly''
  a ~c[:program] mode function as a ~c[:logic] mode function provide the
  measure conjectures can be proved.  This is what ~ilc[verify-termination]
  does.  Now consider the reverse style of redefinition.  Suppose the
  function was defined in ~c[:logic] mode and is being identically redefined
  in ~c[:program] mode.  ACL2 will treat the redefinition as redundant,
  provided the appropriate criteria are met (as though it were in :logic
  mode).

  ~em[Note About Shifting Logical Names:]

  Suppose a book defines a function ~c[fn] and later uses ~c[fn] as a logical
  name in a theory expression.  Consider the value of that theory
  expression in two different sessions.  In session A, the book is
  included in a ~il[world] in which ~c[fn] is not already defined, i.e., in a
  ~il[world] in which the book's definition of ~c[fn] is not redundant.  In
  session B, the book is included in a ~il[world] in which ~c[fn] is already
  identically defined.  In session B, the book's definition of ~c[fn] is
  redundant.  When ~c[fn] is used as a logical name in a theory
  expression, it denotes the point in ~il[history] at which ~c[fn] was
  introduced.  Observe that those points are different in the two
  sessions.  Hence, it is likely that theory expressions involving ~c[fn]
  will have different values in session A than in session B.

  This may adversely affect the user of your book.  For example,
  suppose your book creates a theory via ~ilc[deftheory] that is advertised
  just to contain the names generated by the book.  But suppose you
  compute the theory as the very last event in the book using:
  ~bv[]
  (set-difference-theories (universal-theory :here) 
                           (universal-theory fn))
  ~ev[]
  where ~c[fn] is the very first event in the book and happens to be a
  ~ilc[defun] event.  This expression returns the advertised set if ~c[fn] is
  not already defined when the book is included.  But if ~c[fn] were
  previously (identically) defined, the theory is larger than
  advertised.

  The moral of this is simple: when building ~il[books] that other people
  will use, it is best to describe your ~il[theories] in terms of logical
  names that will not shift around when the ~il[books] are included.  The
  best such names are those created by ~ilc[deflabel].

  ~em[Note About Unfortunate Redundancies:]

  Notice that our syntactic criterion for redundancy of ~ilc[defun] ~il[events]
  does not allow redefinition to take effect unless there is a syntactic change
  in the definition.  The following example shows how an attempt to redefine a
  function can fail to make any change.
  ~bv[]
  (set-ld-redefinition-action '(:warn . :overwrite) state)
  (defmacro mac (x) x)
  (defun foo (x) (mac x))
  (defmacro mac (x) (list 'car x))
  (defun foo (x) (mac x)) ; redundant, unfortunately; foo does not change
  (thm (equal (foo 3) 3)) ; succeeds, showing that redef of foo didn't happen
  ~ev[]
  The call of macro ~c[mac] was expanded away when the first definition of
  ~c[foo] was processed, so the new definition of ~c[mac] is not seen in
  ~c[foo] unless ~c[foo] is redefined; yet our attempt at redefinition failed!
  An easy workaround is first to supply a different definition of ~c[foo], just
  before the last definition of ~c[foo] above.  Then that final definition will
  no longer be redundant.

  The phenomenon illustrated above can occur even without macros.  Here is a
  more complex example, based on one supplied by Grant Passmore.
  ~bv[]
  (defun n3 () 0)
  (defun n4 () 1)
  (defun n5 () (> (n3) (n4))) ; body is normalized to nil
  (thm (equal (n5) nil)) ; succeeds, trivially
  (set-ld-redefinition-action '(:warn . :overwrite) state)
  (defun n3 () 2)
  ~ev[]
  If now we execute ~c[(thm (equal (n5) nil))], it still succeeds even though
  we expect ~c[(n5)] = ~c[(> (n3) (n4))] = ~c[(> 2 1)] = ~c[t].  That is
  because the body of ~c[n5] was normalized to ~c[nil].  (Such normalization
  can be avoided; see the brief discussion of ~c[:normalize] in the
  documentation for ~ilc[defun].)  So, given this unfortunate situation, one
  might expect at this point simply to redefine ~c[n5] using the same
  definition as before, in order to pick up the new definition of ~c[n3].  Such
  ``redefinition'' would, however, be redundant, for the same reason as in the
  previous example:  no syntactic change was made to the definition.  The same
  workaround applies as before: redefine ~c[n5] to be something different, and
  then redefine ~c[n5] again to be as desired.

  A related phenomenon can occur for ~ilc[encapsulate].  As explained above, an
  ~c[encapsulate] event is redundant if it is identical to one already in the
  database.  Consider then the following contrived example.
  ~bv[]
  (encapsulate () (defun foo (x) x))
  (set-ld-redefinition-action '(:warn . :overwrite) state)
  (defun foo (x) (cons x x))
  (encapsulate () (defun foo (x) x)) ; redundant!
  ~ev[]
  The last ~c[encapsulate] event is redundant because it meets the criterion
  for redundancy: it is identical to the earlier ~c[encapsulate] event.  A
  workaround can be to add something trivial to the ~c[encapsulate], for
  example:
  ~bv[]
  (encapsulate () 
    (deflabel try2) ; ``Increment'' to try3 next time, and so on.
    (defun foo (x) x))
  ~ev[]

  The examples above are suggestive but by no means exhaustive.  Consider the
  following example.
  ~bv[]
  (defstub f1 () => *)
  (set-ld-redefinition-action '(:warn . :overwrite) state)
  (defun f1 () 3)
  (defstub f1 () => *) ; redundant -- has no effect
  ~ev[]
  The reason that the final ~ilc[defstub] is redundant is that ~c[defstub] is
  a macro that expands to a call of ~c[encapsulate]; so this is very similar to
  the immediately preceding example.

  ")

(defun stop-redundant-event (ctx state)
  (let ((chan (proofs-co state)))
    (pprogn
     (cond ((ld-skip-proofsp state) state)
           (t
            (io? event nil state
                 (chan ctx)
                 (mv-let (col state)
                         (fmt "The event "
                              nil
                              chan
                              state
                              nil)
                         (mv-let (col state)
                                 (fmt-ctx ctx col chan state)
                                 (mv-let (col state)
                                         (fmt1 " is redundant.  See :DOC ~
                                                redundant-events.~%"
                                               nil
                                               col
                                               chan
                                               state
                                               nil)
                                         (declare (ignore col))
                                         state)))
                 :default-bindings ((col 0)))))
     (value :redundant))))

; Examining the World

; The user must be given facilities for poking around the world.  To describe
; where in the world he wishes to look, we provide "landmark descriptors."
; A landmark descriptor, lmd, identifies a given landmark in the world.
; It does this by "decoding" to either (COMMAND-LANDMARK . n) or
; (EVENT-LANDMARK . n), where n is an absolute command or event number, as
; appropriate.  Then, using lookup-world-index, one can obtain the
; relevant world.  The language of lmds is designed to let the user
; poke conveniently given the way we have chosen to display worlds.
; Below is a typical display:

; d    1 (DEFUN APP (X Y) ...)
; d    2 (DEFUN REV (X) ...)
;      3 (ENCAPSULATE (((HD *) => *)) ...)
; D       (DEFTHM HD-CONS ...)
; D       (DEFTHM HD-ATOM ...)
;      4 (IN-THEORY #)

; Observe firstly that the commands are always displayed in chronological
; order.

; Observe secondly that user commands are numbered consecutively.  We
; adopt the policy that the commands are numbered from 1 starting with
; the first command after the boot-strap.  Negative integers number
; the commands in "pre-history."  These command numbers are not our
; absolute command numbers.  Indeed, until we have completed the
; boot-strapping we don't know what "relative" command number to
; assign to the chronologically first command in the boot-strap.  We
; therefore internally maintain only absolute command numbers and just
; artificially offset them by a certain baseline when we display them
; to the user.

(defrec command-number-baseline-info
  (current permanent-p . original)
  nil)

(defun absolute-to-relative-command-number (n wrld)
  (- n (access command-number-baseline-info
               (global-val 'command-number-baseline-info wrld)
               :current)))

(defun relative-to-absolute-command-number (n wrld)
  (+ n (access command-number-baseline-info
               (global-val 'command-number-baseline-info wrld)
               :current)))

(defun normalize-absolute-command-number (n wrld)

; We have arranged that the first value of this function is a flag, which is
; set iff n exceeds the maximum absolute command number in the current world.
; Our intention is to prevent expressions like
; :ubt (:here +1)
; from executing.

  (let ((m (max-absolute-command-number wrld)))
    (cond ((> n m) (mv t m))
          ((< n 0) (mv nil 0))
          (t (mv nil n)))))

; Observe thirdly that events that are not commands are unnumbered.
; They must be referred to by logical name. 

; Command Descriptors (CD)

; The basic facilities for poking around the world will operate at the
; command level.  We will define a class of objects called "command
; descriptors" which denote command landmarks in the current world.
; We will provide a function for displaying an event and its command
; block, but that will come later.

; The legal command descriptors and their meaning are shown below.  N
; is an integer, name is a logical name, and cd is a command descriptor.

; :min   -- the chronologically first command of the boot

; :start -- 0 at startup, but always refers to (exit-boot-strap-mode), even
;           after a reset-prehistory command

; :max   -- the most recently executed command -- synonymous with :x

; n      -- the nth command landmark, as enumerated by relative command
;           numbers

; name   -- the command containing the event that introduced name

; (cd n) -- the command n removed from the one described by cd

; (:search pat cd1 cd2) -- search the interval from cd1 to cd2 for the first
;           command whose form (or one of whose event forms) matches pat.
;           By "match" we mean "contains all of the elements listed".
;           We search FROM cd1 TO cd2, which will search backwards
;           if cd2 > cd1.  The special case (:search pat) means
;           (:search pat :max 1).

; The search cd is implemented as follows:

(defun tree-occur (x y)

; Does x occur in the cons tree y?

  (cond ((equal x y) t)
        ((atom y) nil)
        (t (or (tree-occur x (car y))
               (tree-occur x (cdr y))))))

(defun cd-form-matchp (pat form)

; We determine whether the form matches pat.  We support only a
; rudimentary notion of matching right now: pat is a true list of
; objects and each must occur in form.

  (cond ((symbolp form) ;eviscerated
         nil)
        ((null pat) t)
        ((tree-occur (car pat) form)
         (cd-form-matchp (cdr pat) form))
        (t nil)))

(defun cd-some-event-matchp (pat wrld)

; This is an odd function.  At first, it was as simple predicate that
; determined whether some event form in the current command block
; matched pat.  It returned t or nil.  But then we changed it so that
; if it fails it returns the world as of the next command block.  So
; if it returns t, it succeeded; non-t means failure and tells where
; to start looking next.

  (cond ((null wrld) nil)
        ((and (eq (caar wrld) 'command-landmark)
              (eq (cadar wrld) 'global-value))
         wrld)
        ((and (eq (caar wrld) 'event-landmark)
              (eq (cadar wrld) 'global-value)
              (cd-form-matchp pat (access-event-tuple-form (cddar wrld))))
         t)
        (t (cd-some-event-matchp pat (cdr wrld)))))

(defun cd-search (pat earliestp start-wrld end-wrld)

; Start-wrld is a world containing end-wrld as a predecessor.  Both
; worlds start on a command landmark.  Pat is a true list of objects.
; Earliestp it t or nil initially, but in general is either nil, t, or
; the last successfully matched world seen.

; We search from start-wrld through end-wrld looking for a command
; world that matches pat in the sense that either the command form
; itself or one of the event forms in the command block contains all
; the elements of pat.  If earliestp is non-nil we return the
; chronologically earliest matching command world.  If earliestp is
; nil we return the chronologically latest matching command world.

  (cond ((equal start-wrld end-wrld)
         (cond
          ((or (cd-form-matchp pat
                               (access-command-tuple-form (cddar start-wrld)))
               (eq t (cd-some-event-matchp pat (cdr start-wrld))))
           start-wrld)
          ((eq earliestp t) nil)
          (t earliestp)))
        ((cd-form-matchp pat
                         (access-command-tuple-form (cddar start-wrld)))
         (cond
          (earliestp
           (cd-search pat
                      start-wrld
                      (scan-to-command (cdr start-wrld))
                      end-wrld))
          (t start-wrld)))
        (t (let ((wrld1 (cd-some-event-matchp pat (cdr start-wrld))))
             (cond ((eq wrld1 t)
                    (cond (earliestp
                           (cd-search pat
                                      start-wrld
                                      (scan-to-command (cdr start-wrld))
                                      end-wrld))
                          (t start-wrld)))
                   (t (cd-search pat earliestp wrld1 end-wrld)))))))

(defun superior-command-world (wrld1 wrld ctx state)

; Given a world, wrld1, and the current ACL2 world, we return the
; world as of the command that gave rise to wrld1.  We do this by
; scanning down wrld1 for the command landmark that occurred
; chronologically before it, increment the absolute command number
; found there by 1, and look that world up in the index.  If no such
; world exists then this function has been called in a peculiar way,
; such as (progn (defun fn1 nil 1) (pc 'fn1)) at the top-level.
; Observe that when pc is called, there is not yet a command superior
; to the event fn1.  Hence, when we scan down wrld1 (which starts at
; the event for fn1) we'll find the previous command number, and
; increment it to obtain a number that is too big.  When this happens,
; we cause a soft error.

  (let ((prev-cmd-wrld (scan-to-command wrld1)))
    (cond
     ((<= (1+ (access-command-tuple-number (cddar prev-cmd-wrld)))
          (max-absolute-command-number wrld))
      (value
       (lookup-world-index 'command
                           (if prev-cmd-wrld
                               (1+ (access-command-tuple-number
                                    (cddar prev-cmd-wrld)))
                               0)
                           wrld)))
     (t (er soft ctx
            "We have been asked to find the about-to-be-most-recent ~
             command landmark.  We cannot do that because that ~
             landmark hasn't been laid down yet!")))))

(defun er-decode-cd (cd wrld ctx state)
  (let ((msg "The object ~x0 is not a legal command descriptor.  See ~
              :DOC command-descriptor."))
    (cond
     ((or (symbolp cd)
          (stringp cd))
      (cond
       ((or (eq cd :max)
            (eq cd :x))
        (value (scan-to-command wrld)))
       ((eq cd :min) (value (lookup-world-index 'command 0 wrld)))
       ((eq cd :start)
        (value (lookup-world-index
                'command
                (access command-number-baseline-info
                        (global-val 'command-number-baseline-info wrld)
                        :original)
                wrld)))
       ((and (keywordp cd)
             (let ((str (symbol-name cd)))
               (and (eql (char str 0) #\X)
                    (eql (char str 1) #\-)
                    (mv-let (k pos)
                            (parse-natural nil str 2 (length str))
                            (and k
                                 (= pos (length str)))))))

; This little piece of code parses :x-123 into (:max -123).

        (er-decode-cd (list :max
                            (- (mv-let
                                (k pos)
                                (parse-natural nil (symbol-name cd) 2
                                               (length (symbol-name cd)))
                                (declare (ignore pos))
                                k)))
                      wrld ctx state))
       (t (er-let* ((ev-wrld (er-decode-logical-name cd wrld ctx state)))
                   (superior-command-world ev-wrld wrld ctx state)))))
     ((integerp cd)
      (mv-let (flg n)
              (normalize-absolute-command-number
               (relative-to-absolute-command-number cd wrld)
               wrld)
              (cond (flg (er soft ctx
                             "The object ~x0 is not a legal command descriptor ~
                              because it exceeds the current maximum command ~
                              number, ~x1."
                             cd
                             (absolute-to-relative-command-number n wrld)))
                    (t (value
                        (lookup-world-index 'command n wrld))))))
     ((and (consp cd)
           (true-listp cd))
      (case
       (car cd)
       (:SEARCH
        (cond
         ((and (or (= (length cd) 4)
                   (= (length cd) 2))
               (or (atom (cadr cd))
                   (true-listp (cadr cd))))
          (let* ((pat (if (atom (cadr cd))
                          (list (cadr cd))
                          (cadr cd))))
            (er-let* ((wrld1 (er-decode-cd (cond ((null (cddr cd)) :max)
                                                 (t (caddr cd)))
                                           wrld ctx state))
                      (wrld2 (er-decode-cd (cond ((null (cddr cd)) 0)
                                                 (t (cadddr cd)))
                                           wrld ctx state)))
                     (let ((ans
                            (cond
                             ((>= (access-command-tuple-number (cddar wrld1))
                                  (access-command-tuple-number (cddar wrld2)))
                              (cd-search pat nil wrld1 wrld2))
                             (t
                              (cd-search pat t wrld2 wrld1)))))
                       (cond
                        ((null ans)
                         (er soft ctx
                             "No command or event in the region from ~
                              ~x0 to ~x1 contains ~&2.  See :MORE-DOC ~
                              command-descriptor."
                             (cond ((null (cddr cd)) :x)
                                   (t (caddr cd)))
                             (cond ((null (cddr cd)) 0)
                                   (t (cadddr cd)))
                             pat
                             cd))
                        (t (value ans)))))))
         (t (er soft ctx msg cd))))
       (otherwise
        (cond
         ((and (consp (cdr cd))
               (integerp (cadr cd))
               (null (cddr cd)))
          (er-let* ((wrld1 (er-decode-cd (car cd) wrld ctx state)))
                   (mv-let (flg n)
                           (normalize-absolute-command-number
                            (+ (access-command-tuple-number
                                (cddar wrld1))
                               (cadr cd))
                            wrld)
                           (cond (flg (er soft ctx
                                          "The object ~x0 is not a legal ~
                                           command descriptor because it ~
                                           represents command number ~x1,  ~
                                           which exceeds the current maximum ~
                                           command number, ~x2."
                                          cd
                                          (absolute-to-relative-command-number
                                           (+ (access-command-tuple-number
                                               (cddar wrld1))
                                              (cadr cd))
                                           wrld)
                                          (absolute-to-relative-command-number
                                           n
                                           wrld)))
                                 (t (value (lookup-world-index 'command
                                                               n
                                                               wrld)))))))
         (t (er soft ctx msg cd))))))
     (t (er soft ctx msg cd)))))

; Displaying Events and Commands

; When we display an event we will also show the "context" in which
; it occurs, by showing the command block.  The rationale is that
; the user cannot undo back to any random event -- he must always
; undo an entire command block -- and thus our convention serves to
; remind him of what will fall should he undo the displayed event.
; Similarly, when we display a command we will sketch the events in
; its block, to remind him of all the effects of that command.

; The commands in the display will be numbered sequentially.  Command 
; 1 will be the first command typed by the user after bootstrap.  Negative
; command numbers refer to prehistoric commands.

; Commands will be displayed in chronological order.  This means we
; must print them in the reverse of the order in which we encounter
; them in the world.  Actually, it is not exactly the reverse, because
; we wish to print commands, encapsulates, and include-books before
; their events, but they are stored on the world after their events.

; Because some events include others it is possible for the user to
; accidentally ask us to print out large blocks, even though the
; interval specified, e.g., commands 1 through 3, is small.  This
; means that a tail recursive implementation is desirable.  (We could
; print in reverse order by printing on the way out of the recursion.)

; Because of all these complications, we have adopted a two pass
; approach to printing out segments of the world.  Both passes are
; tail recursive.  During the first, we collect a list of "landmark
; display directives" (ldd's) and during the second we interpret those
; directives to display the landmarks.  Roughly speaking, each ldd
; corresponds to one line of the display.

; Note to Software Archaeologists of the Future:

; As you study this code, you may wonder why the authors are so
; persistent in inventing long, pompous sounding names, e.g.,
; "landmark display directives" or "prove spec var" and then
; shortening them to unpronounceable letter sequences, e.g., "ldd" and
; "pspv".  This certainly goes against the grain of some software
; scientists who rail against unpronounceable names, acronyms, and
; unnecessary terminology in general.  For the record, we are not
; unsympathetic to their pleas.  However, by adopting these
; conventions we make it easy to use Emacs to find out where these
; objects are documented and manipulated.  Until this code was added
; to the system, the character string "ldd" did not occur in it.  Big
; surprise!  Had we used some perfectly reasonable English word, e.g.,
; "line" (as we might have had we described this code in isolation
; from all other) there would be many false matches.  Of course, we
; could adopt an ordinary word, e.g., "item" that just happened not to
; occur in our sources.  But unfortunately this suffers not only from
; giving a very technical meaning to an ordinary word, but offers no
; protection against the accidental use of the word later in a
; confusing way.  Better, we thought, to come up with the damn
; acronyms which one pretty much has to know about to use.

; In addition to telling us the form to print, an ldd must tell us the
; form to print, whether it is a command or an event, the command
; number, whether it is to be printed in full or only sketched,
; whether it is to be marked, whether it is fully, partially, or not
; disabled, and how far to indent it.

(defrec ldd-status
  (defun-mode-pair disabled memoized)
  nil) ; could change to t after awhile; this new record was created April 2011

(defun make-ldd-flags (class markp status fullp)

; Class is 'COMMAND or 'EVENT, markp is t or nil indicating whether we are to
; print the ">" beside the line, status is a record containing characters that
; indicate the defun-mode and disabled status (also memoized status for the
; HONS version), and fullp is t or nil indicating whether we are to print the
; form in full or just sketch it.  Once upon a time this fn didn't do any
; consing because there were only a small number of combinations and they were
; all built in.  But with the introduction of colors (which became defun-modes)
; that strategy lost its allure.

 (cons (cons class markp) (cons status fullp)))

(defun make-ldd (class markp status n fullp form)

; Class is 'command or 'event.
; Markp is t or nil, indicating whether we are to print a ">".
; Status is a an ldd-status record indicating defun-mode, disabled, and
;   (for the HONS version) memoized status.
; n is a natural number whose interpretation depends on class:
;   if class is 'command, n is the command number; otherwise,
;   n is how far we are to indent, where 1 means indent one
;   space in from the command column.
; fullp is t or nil, indicating whether we are to print the form
;   in full or only sketch it.
; form is the form to print.

  (cons (make-ldd-flags class markp status fullp)
        (cons n form)))

(defun access-ldd-class  (ldd) (caaar ldd))
(defun access-ldd-markp  (ldd) (cdaar ldd))
(defun access-ldd-status (ldd) (cadar ldd))
(defun access-ldd-fullp  (ldd) (cddar ldd))
(defun access-ldd-n      (ldd) (cadr ldd))
(defun access-ldd-form   (ldd) (cddr ldd))

(defun big-d-little-d-name1 (lst ens ans)

; Lst is a list of runic-mapping-pairs.  The car of each pair is a nume.  We
; are considering the enabled status of the runes (numes) in lst.  If all
; members of the list are enabled, we return #\E.  If all are disabled, we
; return #\D.  If some are enabled and some are disabled, we return #\d.  Ans
; is #\E or #\D signifying that we have seen some runes so far and they are all
; enabled or disabled as indicated.

  (cond ((null lst) ans)
        ((equal ans (if (enabled-numep (caar lst) ens) #\E #\D))
         (big-d-little-d-name1 (cdr lst) ens ans))
        (t #\d)))

(defun big-d-little-d-name (name ens wrld)

; Name is a symbol.  If it is the basic symbol of some nonempty set of runes,
; then we return either #\D, #\d, or #\E, depending on whether all, some, or
; none of the runes based on name are disabled.  If name is not the basic
; symbol of any rune, we return #\Space.

  (let ((temp (getprop name 'runic-mapping-pairs nil 'current-acl2-world wrld)))
    (cond ((null temp) #\Space)
          (t (big-d-little-d-name1 (cdr temp) ens
                                   (if (enabled-numep (caar temp) ens)
                                       #\E
                                       #\D))))))

(defun big-d-little-d-clique1 (names ens wrld ans)

; Same drill, one level higher.  Names is a clique of function symbols.  Ans is
; #\E or #\D indicating that all the previously seen names in the clique
; are enabled or disabled as appropriate.  We return #\E, #\D or #\d.

  (cond ((null names) ans)
        (t (let ((ans1 (big-d-little-d-name (car names) ens wrld)))
             (cond ((eql ans1 #\d) #\d)
                   ((eql ans1 ans)
                    (big-d-little-d-clique1 (cdr names) ens wrld ans))
                   (t #\d))))))

(defun big-d-little-d-clique (names ens wrld)

; Names is a list of function symbols.  As such, each symbol in it is the basic
; symbol of a set of runes.  If all of the runes are enabled, we return
; #\E, if all are disabled, we return #\D, and otherwise we return #\d.  We
; assume names is non-nil.

  (let ((ans (big-d-little-d-name (car names) ens wrld)))
    (cond ((eql ans #\d) #\d)
          (t (big-d-little-d-clique1 (cdr names) ens wrld ans)))))

(defun big-d-little-d-event (ev-tuple ens wrld)

; This function determines the enabled/disabled status of an event.  Ev-Tuple
; is an event tuple.  Wrld is the current ACL2 world.

; We return #\D, #\d, #\E or #\Space, with the following interpretation:
; #\D - at least one rule was added by this event and all rules added
;       are currently disabled;
; #\d - at least one rule was added by this event and at least one rule added
;       is currently disabled and at least one rule added is currently enabled.
; #\E - at least one rule was added by this event and all rules added
;       are currently enabled.
; #\Space - no rules were added by this event.

; Note that we do not usually print #\E and we mash it together with #\Space to
; mean all rules added, if any, are enabled.  But we need the stronger
; condition to implement our handling of blocks of events.

  (let ((namex (access-event-tuple-namex ev-tuple)))
    (case (access-event-tuple-type ev-tuple)
          ((defun defthm defaxiom)
           (big-d-little-d-name namex ens wrld))
          (defuns (big-d-little-d-clique namex ens wrld))
          (defstobj (big-d-little-d-clique (cddr namex) ens wrld))
          (otherwise #\Space))))

(defun big-d-little-d-command-block (wrld1 ens wrld s)

; Same drill, one level higher.  We scan down wrld1 to the next command
; landmark inspecting each of the event landmarks in the current command block.
; (Therefore, initially wrld1 ought to be just past the command landmark for
; the block in question.)  We determine whether this command ought to have a
; #\D, #\E, #\d, or #\Space printed beside it, by collecting that information for
; each event in the block.  Wrld is the current ACL2 world and is used to
; obtain both the current global enabled structure and the numes of the runes
; involved.

; The interpretation of the character is as described in big-d-little-d-event.

; We sweep through the events accumulating our final answer in s, which we
; think of as a "state" (but not STATE).  The interpretation of s is:
; #\D - we have seen at least one event with status #\D and all the
;       events we've seen have status #\D or status #\Space.
; #\E - we have seen at least one event with status #\E and all the
;       events we've seen have status #\E or status #\Space
; #\Space - all events seen so far (if any) have status #\Space

  (cond ((or (null wrld1)
             (and (eq (caar wrld1) 'command-landmark)
                  (eq (cadar wrld1) 'global-value)))
         s)
        ((and (eq (caar wrld1) 'event-landmark)
              (eq (cadar wrld1) 'global-value))
         (let ((s1 (big-d-little-d-event (cddar wrld1) ens wrld)))
; S1 = #\D, #\E, #\d, or #\Space
           (cond
            ((or (eql s s1)
                 (eql s1 #\Space))
             (big-d-little-d-command-block (cdr wrld1) ens wrld s))
            ((or (eql s1 #\d)
                 (and (eql s #\E)
                      (eql s1 #\D))
                 (and (eql s #\D)
                      (eql s1 #\E)))
             #\d)
            (t ; s must be #\Space
             (big-d-little-d-command-block (cdr wrld1) ens wrld s1)))))
        (t (big-d-little-d-command-block (cdr wrld1) ens wrld s))))

(defun big-m-little-m-name (name wrld)

; This function, which supports the printing of the memoization status, is
; analogous to function big-d-little-d-name, which supports the printing of the
; disabled status.

  (cond ((and (function-symbolp name wrld)
              (not (getprop name 'constrainedp nil 'current-acl2-world wrld)))
         (if (memoizedp-world name wrld)
             #\M
           #\E))
        (t #\Space)))

(defun big-m-little-m-clique1 (names wrld ans)

; This function, which supports the printing of the memoization status, is
; analogous to function big-d-little-d-clique1, which supports the printing of
; the disabled status.

  (cond ((null names) ans)
        (t (let ((ans1 (big-m-little-m-name (car names) wrld)))
             (cond ((eql ans1 #\m) #\m)
                   ((eql ans1 ans)
                    (big-m-little-m-clique1 (cdr names) wrld ans))
                   (t #\m))))))

(defun big-m-little-m-clique (names wrld)

; This function, which supports the printing of the memoization status, is
; analogous to function big-d-little-d-clique, which supports the printing of
; the disabled status.

  (let ((ans (big-m-little-m-name (car names) wrld)))
    (cond ((eql ans #\m) #\m)
          (t (big-m-little-m-clique1 (cdr names) wrld ans)))))

(defun big-m-little-m-event (ev-tuple wrld)

; This function, which supports the printing of the memoization status, is
; analogous to function big-d-little-d-event, which supports the printing of
; the disabled status.

  (let ((namex (access-event-tuple-namex ev-tuple)))
    (case (access-event-tuple-type ev-tuple)
          ((defun)
           (big-m-little-m-name namex wrld))
          (defuns (big-m-little-m-clique namex wrld))
          (defstobj (big-m-little-m-clique (cddr namex) wrld))
          (otherwise #\Space))))

(defun big-m-little-m-command-block (wrld1 wrld s)

; This function, which supports the printing of the memoization status, is
; analogous to function big-d-little-d-command-block, which supports the
; printing of the disabled status.

  (cond ((or (null wrld1)
             (and (eq (caar wrld1) 'command-landmark)
                  (eq (cadar wrld1) 'global-value)))
         s)
        ((and (eq (caar wrld1) 'event-landmark)
              (eq (cadar wrld1) 'global-value))
         (let ((s1 (big-m-little-m-event (cddar wrld1) wrld)))
; S1 = #\M, #\E, #\m, or #\Space
           (cond
            ((or (eql s s1)
                 (eql s1 #\Space))
             (big-m-little-m-command-block (cdr wrld1) wrld s))
            ((or (eql s1 #\m)
                 (and (eql s #\E)
                      (eql s1 #\M))
                 (and (eql s #\M)
                      (eql s1 #\E)))
             #\m)
            (t ; s must be #\Space
             (big-m-little-m-command-block (cdr wrld1) wrld s1)))))
        (t (big-m-little-m-command-block (cdr wrld1) wrld s))))

(defun symbol-class-char (symbol-class)

; Note: If you change the chars used below, recall that big-c-little-c-event
; knows that #\v is the symbol-class char for encapsulated fns.

  (case symbol-class
        (:program #\P)
        (:ideal #\L)
        (:common-lisp-compliant #\V)
        (otherwise #\Space)))

(defun defun-mode-string (defun-mode)
  (case defun-mode
        (:logic ":logic")
        (:program ":program")
        (otherwise (er hard 'defun-mode-string
                       "Unrecognized defun-mode, ~x0."
                       defun-mode))))

(defun big-c-little-c-event (ev-tuple wrld)

; The big-c-little-c of an event tuple with non-0 namex is a pair of
; characters, (c1 . c2), where each indicates a symbol-class.  C1 indicates the
; introductory symbol-class of the namex.  C2 indicates the current
; symbol-class.  However, if the current class is the same as the introductory
; one, c2 is #\Space.  Note that all elements of namex have the same
; symbol-class forever.  (Only defuns and encapsulate events introduce more
; than one name, and those cliques of functions are in the same class forever.)
; If an event tuple introduces no names, we return (#\Space . #\Space).

; Note: The name big-c-little-c-event is a misnomer from an earlier age.

  (case
    (access-event-tuple-type ev-tuple)
    ((defuns defun defstobj)
     (let ((c1 (symbol-class-char (access-event-tuple-symbol-class ev-tuple)))
           (c2 (symbol-class-char
                (let ((namex (access-event-tuple-namex ev-tuple)))
                  (cond ((symbolp namex) (symbol-class namex wrld))
                        (t (symbol-class (car namex) wrld)))))))
       (cond ((eql c1 c2)
              (cons c1 #\Space))
             (t (cons c1 c2)))))
    (encapsulate '(#\v . #\Space))
    (otherwise '(#\Space . #\Space))))

(defun big-c-little-c-command-block (wrld1 wrld s)

; This function determines the big-c-little-c pair of a block of events.  If
; the block contains more than one event, its pair is (#\Space . #\Space)
; because we expect the individual events in the block to have their own
; pairs printed.  If the block contains only one event, its pair is
; the pair of the block, because we generally print such blocks as the
; event.

; We scan down wrld1 to the next command landmark inspecting each of the event
; landmarks in the current command block.  (Therefore, initially wrld1 ought to
; be just past the command landmark for the block in question.) S is initially
; nil and is set to the pair of the first event we find.  Upon finding a
; second event we return (#\Space . #\Space), but if we get to the end of the
; block, we return s.

  (cond ((or (null wrld1)
             (and (eq (caar wrld1) 'command-landmark)
                  (eq (cadar wrld1) 'global-value)))

; Can a block contain no events?  I don't know anymore.  But if so, its
; defun-mode is '(#\Space . #\Space).

         (or s '(#\Space . #\Space)))
        ((and (eq (caar wrld1) 'event-landmark)
              (eq (cadar wrld1) 'global-value))
         (cond (s '(#\Space . #\Space))
               (t (big-c-little-c-command-block
                   (cdr wrld1) wrld
                   (big-c-little-c-event (cddar wrld1) wrld)))))
        (t (big-c-little-c-command-block (cdr wrld1) wrld s))))

; Now we turn to the problem of printing according to some ldd.  We first
; develop the functions for sketching a command or event form.  This is
; like evisceration (indeed, it uses the same mechanisms) but we handle
; commonly occurring event and command forms specially so that we see
; what we often want to see and no more.

(defun print-ldd-full-or-sketch/mutual-recursion (lst)

; See print-ldd-full-or-sketch.

  (cond ((null lst) nil)
        (t (cons (list 'defun (cadr (car lst)) (caddr (car lst))
                       *evisceration-ellipsis-mark*)
                 (print-ldd-full-or-sketch/mutual-recursion (cdr lst))))))

(defun print-ldd-full-or-sketch/encapsulate (lst)

; See print-ldd-full-or-sketch.

  (cond ((null lst) nil)
        (t (cons (list (car (car lst)) *evisceration-ellipsis-mark*)
                 (print-ldd-full-or-sketch/encapsulate (cdr lst))))))

; If a form has a documentation string in the data base, we avoid printing
; the string.  We'll develop the general handling of doc strings soon.  But
; for now we have to define the function that recognizes when the user 
; intends his string to be inserted into the data base.

(defun normalize-char (c hyphen-is-spacep)
  (if (or (eql c #\Newline)
          (and hyphen-is-spacep (eql c #\-)))
      #\Space
      (char-upcase c)))

(defun normalize-string1 (str hyphen-is-spacep j ans)
  (cond ((< j 0) ans)
        (t (let ((c (normalize-char (char str j)
                                    hyphen-is-spacep)))
             (normalize-string1 str
                                hyphen-is-spacep
                                (1- j)
                                (cond ((and (eql c #\Space)
                                            (eql c (car ans)))
                                       ans)
                                      (t (cons c ans))))))))

(defun normalize-string (str hyphen-is-spacep)

; Str is a string for which we wish to search.  A normalized pattern
; is a list of the chars in the string, all of which are upper cased
; with #\Newline converted to #\Space and adjacent #\Spaces collapsed
; to one #\Space.  If hyphen-is-spacep is t, #\- is normalized to
; #\Space too.

  (normalize-string1 str hyphen-is-spacep (1- (length str)) nil))

(defun string-matchp (pat-lst str j jmax normp skippingp)

; Pat-lst is a list of characters.  Str is a string of length jmax.
; 0<=j<jmax.  If normp is non-nil we are to see str as though it had
; been normalized.  Normp should be either nil, t or
; 'hyphen-is-space.  If Skippingp is t then we are skipping
; whitespace in the str.

  (cond
   ((null pat-lst) t)
   ((>= j jmax) nil)
   (t (let ((c (if normp
                   (normalize-char (char str j)
                                   (eq normp 'hyphen-is-space))
                   (char str j))))
        (cond
         ((and skippingp (eql c #\Space))
          (string-matchp pat-lst str (1+ j) jmax normp t))
         (t (and (eql c (car pat-lst))
                 (string-matchp (cdr pat-lst)
                                str (1+ j) jmax
                                normp
                                (if normp
                                    (eql c #\Space)
                                    nil)))))))))

(defun string-search1 (pat-lst str j j-max normp)
  (cond ((< j j-max)
         (if (string-matchp pat-lst str j j-max normp nil)
             j
             (string-search1 pat-lst str (1+ j) j-max normp)))
        (t nil)))

(defun string-search (pat str normp)

; We ask whether pat occurs in str, normalizing both according to
; normp, which is either nil, t, or 'hyphen-is-space.  If pat is
; a consp, we assume it is already normalized appropriately.

  (string-search1 (if (consp pat)
                      pat
                      (if normp
                          (normalize-string pat
                                            (eq normp 'hyphen-is-space))
                          (coerce pat 'list)))
                  str
                  0
                  (length str)
                  normp))

(defun doc-stringp (str)

; If this function returns t then the first character (if any) after
; the matching #\Space in the string is at index 13.

  (and (stringp str)
       (<= 13 (length str))
       (string-matchp '(#\: #\D #\O #\C #\- #\S #\E #\C #\T #\I #\O #\N
                        #\Space)
                      str
                      0
                      13
                      t
                      nil)))

; So now we continue with the development of printing event forms.

(defconst *zapped-doc-string*
  "Documentation available via :doc")

(defun zap-doc-string-from-event-form/all-but-last (lst)
  (cond ((null lst) nil)
        ((null (cdr lst)) lst)
        ((doc-stringp (car lst))
         (cons *zapped-doc-string*
               (zap-doc-string-from-event-form/all-but-last (cdr lst))))
        (t (cons (car lst)
                 (zap-doc-string-from-event-form/all-but-last (cdr lst))))))

(defun zap-doc-string-from-event-form/second-arg (form)

; Zap a doc string if it occurs in the second arg, e.g.,
; (defdoc x doc).

  (cond ((doc-stringp (third form))
         (list (first form) (second form)
               *zapped-doc-string*))
        (t form)))

(defun zap-doc-string-from-event-form/third-arg (form)

; Zap a doc string if it occurs in the third arg, e.g.,
; (defconst x y doc).  But form may only be
; (defconst x y).

  (cond ((doc-stringp (fourth form))
         (list (first form) (second form) (third form)
               *zapped-doc-string*))
        (t form)))

(defun zap-doc-string-from-event-form/mutual-recursion (lst)
  (cond ((null lst) nil)
        (t (cons (zap-doc-string-from-event-form/all-but-last (car lst))
                 (zap-doc-string-from-event-form/mutual-recursion (cdr lst))))))

(defun zap-doc-string-from-event-form/doc-keyword (lst)

; This function is supposed to zap out a doc string if it occurs in
; :doc keyword slot.  But study the recursion and you'll find that it
; will zap a doc string str that occurs as in: (fn :key1 :doc str).
; Now is that in the :doc keyword slot or not?  If the first arg is
; normal, then it is.  If the first arg is a : keyword then the :doc
; is a value, BUT then str is in a string in another keyword position.
; So I think this function is actually correct.  It doesn't really
; matter since it is just for informative purposes.

  (cond ((null lst) nil)
        ((null (cdr lst)) lst)
        ((and (eq (car lst) :doc)
              (doc-stringp (cadr lst)))
         (cons :doc
               (cons *zapped-doc-string*
                     (zap-doc-string-from-event-form/doc-keyword (cddr lst)))))
        (t (cons (car lst)
                 (zap-doc-string-from-event-form/doc-keyword (cdr lst))))))

(defun zap-doc-string-from-event-form (form)
  (case (car form)
    ((defun defmacro)
     (zap-doc-string-from-event-form/all-but-last form))
    (mutual-recursion
     (cons 'mutual-recursion
           (zap-doc-string-from-event-form/mutual-recursion (cdr form))))
    ((defthm defaxiom deflabel deftheory include-book defchoose)
     (zap-doc-string-from-event-form/doc-keyword form))
    ((defdoc)
     (zap-doc-string-from-event-form/second-arg form))
    ((defconst defpkg)
     (zap-doc-string-from-event-form/third-arg form))
    ((verify-guards in-theory
                    in-arithmetic-theory
                    push-untouchable remove-untouchable reset-prehistory
                    table encapsulate defstobj) form)
    (otherwise form)))

(defun print-ldd-full-or-sketch (fullp form)

; When fullp is nil, this function is like eviscerate with print-level
; 2 and print-length 3, except that we here recognize several special
; cases.  We return the eviscerated form.

; Forms with the cars shown below are always eviscerated as
; shown:

; (defun name args ...)
; (defmacro name args ...)
; (defthm name ...)
; (mutual-recursion (defun name1 args1 ...) etc)
; (encapsulate ((name1 ...) etc) ...)    ; which is also:
; (encapsulate (((P * *) ...) etc) ...)

; When fullp is t we zap the documentation strings out of event
; forms.

; It is assumed that form is well-formed.  In particular, that it has
; been evaluated without error.  Thus, if its car is defun, for
; example, it really is of the form (defun name args dcls* body).

; Technically, we should eviscerate the name and args to ensure that
; any occurrence of the *evisceration-mark* in them is properly protected.
; But the mark is a keyword and inspection of the special forms above
; reveals that there are no keywords among the uneviscerated parts.

  (cond
   ((atom form) form)
   (fullp (zap-doc-string-from-event-form form))
   (t
    (case
     (car form)
     ((defun defund defmacro)
      (list (car form) (cadr form) (caddr form) *evisceration-ellipsis-mark*))
     ((defthm defthmd)
       (list (car form) (cadr form) *evisceration-ellipsis-mark*))
     (defdoc
       (list 'defdoc (cadr form) *evisceration-ellipsis-mark*))
     (mutual-recursion
      (cons 'mutual-recursion
            (print-ldd-full-or-sketch/mutual-recursion (cdr form))))
     (encapsulate
      (list 'encapsulate
            (print-ldd-full-or-sketch/encapsulate (cadr form))
            *evisceration-ellipsis-mark*))
     (t (eviscerate-simple form 2 3 nil nil nil))))))

(defmacro with-base-10 (form)

; Form evaluates to state.  Here, we want to evaluate form with the print base
; set to 10.

  `(mv-let (erp val state)
     (state-global-let* ((print-base 10 set-print-base))
                        (pprogn ,form (value nil)))
     (declare (ignore erp val))
     state))

(defun print-ldd-formula-column (state)
  (cond ((hons-enabledp state) ; extra column for the memoization status
         14)
        (t 13)))

(defun print-ldd (ldd channel state)

; This is the general purpose function for printing out an ldd.

  (with-base-10
   (let ((formula-col
          (if (eq (access-ldd-class ldd) 'command)
              (print-ldd-formula-column state)
            (+ (print-ldd-formula-column state)
               (access-ldd-n ldd))))
         (status (access-ldd-status ldd)))
     (declare (type (signed-byte 30) formula-col))
     (pprogn
      (princ$ (if (access-ldd-markp ldd)
                  (access-ldd-markp ldd)
                #\Space)
              channel state)
      (let ((defun-mode-pair (access ldd-status status :defun-mode-pair)))
        (pprogn
         (princ$ (car defun-mode-pair) channel state)
         (princ$ (cdr defun-mode-pair) channel state)))
      (let ((disabled (access ldd-status status :disabled)))
        (princ$ (if (eql disabled #\E) #\Space disabled)
                channel state))
      (if (hons-enabledp state)
          (let ((memoized (access ldd-status status :memoized)))
            (princ$ (if (eql memoized #\E) #\Space memoized)
                    channel state))
        state)
      (let ((cur-col (if (hons-enabledp state) 5 4)))
        (if (eq (access-ldd-class ldd) 'command)
            (mv-let
             (col state)
             (fmt1 "~c0~s1"
                   (list
                    (cons #\0 (cons (access-ldd-n ldd) 7))
                    (cons #\1 (cond
                               ((= (access-ldd-n ldd)
                                   (absolute-to-relative-command-number
                                    (max-absolute-command-number (w state))
                                    (w state)))
                                ":x")
                               (t "  "))))
                   cur-col channel state nil)
             (declare (ignore col))
             state)
          (spaces (- formula-col cur-col) cur-col channel state)))
      (fmt-ppr
       (print-ldd-full-or-sketch (access-ldd-fullp ldd)
                                 (access-ldd-form ldd))
       t
       (+f (fmt-hard-right-margin state) (-f formula-col))
       0
       formula-col channel state
       (not (access-ldd-fullp ldd)))
      (newline channel state)))))

(defun print-ldds (ldds channel state)
  (cond ((null ldds) state)
        (t (pprogn (print-ldd (car ldds) channel state)
                   (print-ldds (cdr ldds) channel state)))))

; Now we turn to the problem of assembling lists of ldds.  There are
; currently three different situations in which we do this and rather
; than try to unify them, we write a special-purpose function for
; each.  The three situations are:

; (1) When we wish to print out a sequence of commands:  We print only the
;     commands, not their events, and we only sketch each command.  We
;     mark the endpoints. 

; (2) When we wish to print out an entire command block, meaning the
;     command and each of its events: We will print the command in
;     full and marked, and we will only sketch each event.  We will
;     not show any events in the special case that there is only one
;     event and it has the same form as the command.  This function,
;     make-ldd-command-block, is the simplest of our functions that
;     deals with a mixture of commands and events.  It has to crawl
;     over the world, reversing the order (more or less) of the events
;     and taking the command in at the end.

; (3) When we wish to print out an event and its context: This is like
;     case (2) above in that we print a command and its block.  But we
;     only sketch the forms involved, except for the event requested,
;     which we print marked and in full.  To make things monumentally
;     more difficult, we also elide away irrelevant events in the
;     block.

(defun make-command-ldd (markp fullp cmd-wrld ens wrld)
  (make-ldd 'command
            markp
            (make ldd-status
                  :defun-mode-pair
                  (big-c-little-c-command-block (cdr cmd-wrld) wrld nil)
                  :disabled
                  (big-d-little-d-command-block (cdr cmd-wrld) ens wrld
                                                #\Space)
                  :memoized
                  (and (global-val 'hons-enabled wrld) ; else don't care
                       (big-m-little-m-command-block (cdr cmd-wrld) wrld
                                                     #\Space)))
            (absolute-to-relative-command-number
             (access-command-tuple-number (cddar cmd-wrld))
             wrld)
            fullp
            (access-command-tuple-form (cddar cmd-wrld))))

(defun make-event-ldd (markp indent fullp ev-tuple ens wrld)
  (make-ldd 'event
            markp
            (make ldd-status
                  :defun-mode-pair
                  (big-c-little-c-event ev-tuple wrld)
                  :disabled
                  (big-d-little-d-event ev-tuple ens wrld)
                  :memoized
                  (and (global-val 'hons-enabled wrld) ; else don't care
                       (big-m-little-m-event ev-tuple wrld)))
            indent
            fullp
            (access-event-tuple-form ev-tuple)))

(defun make-ldds-command-sequence (cmd-wrld1 cmd2 ens wrld markp ans)

; Cmd-wrld1 is a world that starts on a command landmark.  Cmd2 is a command
; tuple somewhere in cmd-wrld1 (that is, cmd1 occurred chronologically after
; cmd2).  We assemble onto ans the ldds for sketching each command between the
; two.  We mark the two endpoints provided markp is t.  If we mark, we use / as
; the mark for the earliest command and \ as the mark for the latest, so that
; when printed chronologically the marks resemble the ends of a large brace.
; If only one command is in the region, we mark it with the pointer character,
; >.

  (cond ((equal (cddar cmd-wrld1) cmd2)
         (cons (make-command-ldd (and markp (cond ((null ans) #\>) (t #\/)))
                                 nil cmd-wrld1 ens wrld)
               ans))
        (t (make-ldds-command-sequence
            (scan-to-command (cdr cmd-wrld1))
            cmd2
            ens wrld
            markp
            (cons (make-command-ldd (and markp (cond ((null ans) #\\)(t nil)))
                                    nil cmd-wrld1 ens wrld)
                  ans)))))

(defun make-ldds-command-block1 (wrld1 cmd-ldd indent fullp super-stk ens wrld
                                       ans)

; Wrld1 is a world created by the command tuple described by cmd-ldd.
; Indent is the current indent value for the ldds we create.
; Super-stk is a list of event tuples, each of which is a currently
; open superior event (e.g., encapsulation or include-book).  We wish
; to make a list of ldds for printing out that command and every event
; in its block.  We print the command marked and in full.  We only
; sketch the events, but we sketch each of them.  This is the simplest
; function that shows how to crawl down a world and produce
; print-order ldds that suggest the structure of a block.

  (cond
   ((or (null wrld1)
        (and (eq (caar wrld1) 'command-landmark)
             (eq (cadar wrld1) 'global-value)))
    (cond
     (super-stk
      (make-ldds-command-block1
       wrld1
       cmd-ldd
       (1- indent)
       fullp
       (cdr super-stk)
       ens wrld
       (cons (make-event-ldd nil (1- indent) fullp (car super-stk) ens wrld)
             ans)))
     (t (cons cmd-ldd ans))))
   ((and (eq (caar wrld1) 'event-landmark)
         (eq (cadar wrld1) 'global-value))
    (cond
     ((and super-stk
           (<= (access-event-tuple-depth (cddar wrld1))
               (access-event-tuple-depth (car super-stk))))
      (make-ldds-command-block1
       wrld1
       cmd-ldd
       (1- indent)
       fullp
       (cdr super-stk)
       ens wrld
       (cons (make-event-ldd nil (1- indent) fullp (car super-stk) ens wrld)
             ans)))
     ((or (eq (access-event-tuple-type (cddar wrld1)) 'encapsulate)
          (eq (access-event-tuple-type (cddar wrld1)) 'include-book))
      (make-ldds-command-block1
       (cdr wrld1)
       cmd-ldd
       (1+ indent)
       fullp
       (cons (cddar wrld1) super-stk)
       ens wrld
       ans))
     (t (make-ldds-command-block1
         (cdr wrld1)
         cmd-ldd
         indent
         fullp
         super-stk
         ens wrld
         (cons (make-event-ldd nil indent fullp (cddar wrld1) ens wrld)
               ans)))))
   (t (make-ldds-command-block1 (cdr wrld1)
                                cmd-ldd
                                indent
                                fullp
                                super-stk
                                ens wrld
                                ans))))

(defun make-ldds-command-block (cmd-wrld ens wrld fullp ans)

; Cmd-wrld is a world starting with a command landmark.  We make a list of ldds
; to describe the entire command block, sketching the command and sketching
; each of the events contained within the block.

  (let ((cmd-ldd (make-command-ldd nil fullp cmd-wrld ens wrld))
        (wrld1 (scan-to-event (cdr cmd-wrld))))
    (cond
     ((equal (access-event-tuple-form (cddar wrld1))
             (access-command-tuple-form (cddar cmd-wrld)))

; If the command form is the same as the event form of the
; chronologically last event then that event is to be skipped.

      (make-ldds-command-block1 (cdr wrld1) cmd-ldd 1 fullp nil ens wrld ans))
     (t (make-ldds-command-block1 wrld1 cmd-ldd 1 fullp nil ens wrld ans)))))

(defun pcb-pcb!-fn (cd fullp state)
  (io? temporary nil (mv erp val state)
       (cd fullp)
       (let ((wrld (w state))
             (ens (ens state)))
         (er-let* ((cmd-wrld (er-decode-cd cd wrld :pcb state)))
                  (pprogn
                   (print-ldds
                    (make-ldds-command-block cmd-wrld ens wrld fullp nil)
                    (standard-co state)
                    state)
                   (value :invisible))))))

(defun pcb!-fn (cd state)
  (pcb-pcb!-fn cd t state))

(defun pcb-fn (cd state)
  (pcb-pcb!-fn cd nil state))

(defmacro pcb! (cd)

  ":Doc-Section History

  print in full the ~il[command] block described by a ~il[command] descriptor~/
  ~bv[]
  Examples:
  :pcb! :max ; print the most recent command block
  :pcb! :x   ; print the most recent command block
  :pcb! fn   ; print the command block that introduced fn
  :pcb! 5    ; print the fifth command block
  ~ev[]
  ~l[command-descriptor].~/

  ~c[Pcb!] takes one argument, a ~il[command] descriptor, and prints the
  ~il[command] block of the ~il[command] described.  Unlike ~ilc[pcb], ~c[pcb!] prints the
  event forms in full; ~pl[pcb] for details.~/"

  (list 'pcb!-fn cd 'state))

(defun pc-fn (cd state)
  (io? temporary nil (mv erp val state)
       (cd)
       (let ((wrld (w state)))
         (er-let* ((cmd-wrld (er-decode-cd cd wrld :pc state)))
                  (pprogn
                   (print-ldd
                    (make-command-ldd nil t cmd-wrld (ens state) wrld)
                    (standard-co state)
                    state)
                   (value :invisible))))))

(defmacro pc (cd)

  ":Doc-Section History

  print the ~il[command] described by a ~il[command] descriptor~/

  ~bv[]
  Examples:
  :pc 3    ; print the third command executed
  :pc :max ; print the most recent command
  :pc :x   ; print the most recent command
  :pc fn   ; print the command that introduced fn
  ~ev[]
  ~l[command-descriptor].~/

  ~c[Pc] takes one argument, a ~il[command] descriptor, and prints the ~il[command]
  identified by that descriptor.  ~l[command-descriptor].  For
  example
  ~bv[]
  ACL2 !>:pc foo
   LVd     52 (DEFUN FOO (X) X)
  ~ev[]
  ~c[Pc] always prints a space first, followed by three (possibly blank)
  ~il[characters] (``LVd'' above) explained below (four, in the experimental
  HONS version; ~pl[hons-and-memoization]).  Then ~c[pc] prints the
  ~il[command] number, a number uniquely identifying the ~il[command]'s
  position in the sequence of ~il[command]s since the beginning of the user's
  session.  Finally, the ~il[command] itself is printed.

  While ~c[pc] always prints a space first, some ~il[history] ~il[command]s, for
  example ~c[:]~ilc[pcs] and ~c[:]~ilc[pe], use the first column of output to delimit a
  region of ~il[command]s or to point to a particular event within a
  ~il[command].

  For example, ~c[:pcs 52 54] will print something like
  ~bv[]
  /LVd     52 (DEFUN FOO (X) X)
   LV      53 (DEFUN BAR (X) (CONS X X))
  \\        54 (DEFTHM FOO-BAR (EQUAL (CAR (BAR X)) (FOO X)))
            : ...
          127 (DEFUN LATEST (X) X)
  ~ev[]
  Here, the two slash ~il[characters] in the first column are intended to
  suggest a bracket delimiting ~il[command]s 52 through 54.  The last
  ~il[command] printed by ~ilc[pcs] is always the most recent ~il[command], i.e., the
  ~il[command] at ~c[:here], and is separated from the rest of the display by
  an elipsis if some ~il[command]s are omitted.

  Similarly, the ~c[:]~ilc[pe] ~il[command] will print a particular event within a
  ~il[command] block and will indicate that event by printing a ``~ilc[>]'' in
  the first column.  The symbol is intended to be an arrow pointing at
  the event in question.

  For example, ~c[:]~ilc[pe] ~c[true-listp-app] might print:
  ~bv[]
           1 (INCLUDE-BOOK \"list-book\")
              \\
  >           (DEFTHM TRUE-LISTP-APP
                      (EQUAL (TRUE-LISTP (APP A B)) (TRUE-LISTP B)))
  ~ev[]
  using the arrow to indicate the event itself.  The slash printed
  to connect the ~il[command], ~ilc[include-book], with the event, ~ilc[defthm], is
  intended to suggest a tree branch indicating that the event is
  inferior to (and part of) the ~il[command].

  The mysterious ~il[characters] sometimes preceding a ~il[command] have the
  following interpretations.  The first two have to do with the function
  symbols introduced by the ~il[command] and are blank if no symbols were
  introduced.

  At any time we can classify our function symbols into disjoint sets, which we
  will here name with ~il[characters].  The ``~c[P]'' functions are those in
  ~c[:]~ilc[program] mode.  The ``~c[L]'' functions are those in
  ~c[:]~ilc[logic] mode whose ~il[guard]s have not been verified.  The
  ``~c[V]'' functions are those in ~c[:]~ilc[logic] mode whose ~il[guard]s have
  been verified.  You may also see the use of (lower-case) ``~c[v]'' to
  indicate functions introduced by ~ilc[encapsulate].  Note that
  ~ilc[verify-termination] and ~ilc[verify-guards] cause function symbols to be
  reclassified.  If a ~il[command] introduces function symbols then the first
  mysterious character indicates the class of the symbols at the time of
  introduction and the second character indicates the current class of the
  symbols (if the current class is different from the introductory class).

  Thus, the display
  ~bv[]
   PLd     52 (DEFUN FOO (X) X)
  ~ev[]
  tells us that ~il[command] 52 introduced a ~c[:]~ilc[program] function but that
  some ~il[command] after 52 changed its mode to ~c[:]~ilc[logic] and that the
  ~il[guard]s of ~c[foo] have not been verified.  That is, ~c[foo]'s
  termination has been verified even though it was not verified as
  part of the ~il[command] that introduced ~c[foo].  Had a subsequent
  ~il[command] verified the ~il[guard]s of ~c[foo], the display would contain a
  ~c[V] where the ~c[L] is.

  The display
  ~bv[]
   P d     52 (DEFUN FOO (X) X)
  ~ev[]
  indicates that ~c[foo] was introduced in ~c[:]~ilc[program] mode and still
  is in that mode.

  The third character indicates the enabled/disabled status of the
  ~il[rune]s introduced by the ~il[command].  If the status character is blank
  then all the ~il[rune]s (if any) introduced are ~il[enable]d.  If the status
  character is ``~c[D]'' then some ~il[rune]s were introduced and they are
  all ~il[disable]d.  If the status character is ``~c[d]'' then at least
  one, but not all, of the ~il[rune]s introduced is ~il[disable]d.  Thus, in the
  display
  ~bv[]
   L d     52 (DEFUN FOO (X) X)
  ~ev[]
  we see that some ~il[rune] introduced by ~il[command] 52 is ~il[disable]d.  As
  noted in the documentation for ~il[rune], a ~ilc[defun] ~il[command]
  introduces many ~il[rune]s, e.g., the axiomatic definition rule,
  ~c[(:definition fn)], the executable counterpart rule,
  ~c[(:executable-counterpart fn)], and ~il[type-prescription]s,
  ~c[(:type-prescription fn)].  The display above does not say which of
  the ~il[rune]s based on ~c[foo] is ~il[disable]d, but it does tell us one of
  them is; ~pl[disabledp] for how to obtain the disabled runes for
  a given function symbol.

  Finally, for the experimental HONS version only (~pl[hons-and-memoization]),
  a fourth character is printed, indicating whether functions are memoized.
  A symbol may be memoized if it is a function symbol that is not constrained
  (i.e., introduced by ~ilc[defchoose] or in the ~il[signature] of an
  ~ilc[encapsulate] event).  If the command introduces no symbol that may be
  memoized, then a space is printed.  Otherwise, if every memoizable symbol is
  memoized, an ``~c[M]'' is printed.  Otherwise, an ``~c[m]'' is printed.~/"

  (list 'pc-fn cd 'state))

(defun pcs-fn (cd1 cd2 markp state)

; We print the commands between cd1 and cd2 (relative order of these two cds is
; irrelevant).  We always print the most recent command here, possibly elided
; into the cd1-cd2 region.  We mark the end points of the region if markp is t.

  (io? temporary nil (mv erp val state)
       (cd1 markp cd2)
       (let ((wrld (w state))
             (ens (ens state)))
         (er-let*
          ((cmd-wrld1 (er-decode-cd cd1 wrld :ps state))
           (cmd-wrld2 (er-decode-cd cd2 wrld :ps state)))
          (let ((later-wrld
                 (if (>= (access-command-tuple-number (cddar cmd-wrld1))
                         (access-command-tuple-number (cddar cmd-wrld2)))
                     cmd-wrld1
                   cmd-wrld2))
                (earlier-wrld
                 (if (>= (access-command-tuple-number (cddar cmd-wrld1))
                         (access-command-tuple-number (cddar cmd-wrld2)))
                     cmd-wrld2
                   cmd-wrld1)))
            (pprogn
             (print-ldds (make-ldds-command-sequence later-wrld
                                                     (cddar earlier-wrld)
                                                     ens
                                                     wrld
                                                     markp
                                                     nil)
                         (standard-co state)
                         state)
             (cond
              ((= (access-command-tuple-number (cddar later-wrld))
                  (max-absolute-command-number wrld))
               state)
              ((= (1+ (access-command-tuple-number (cddar later-wrld)))
                  (max-absolute-command-number wrld))
               (print-ldd (make-command-ldd nil nil wrld ens wrld)
                          (standard-co state)
                          state))
              (t (pprogn (mv-let
                          (col state)
                          (fmt1 "~t0: ...~%"
                                (list (cons #\0
                                            (- (print-ldd-formula-column state)
                                               2)))
                                0 (standard-co state) state nil)
                          (declare (ignore col))
                          state)
                         (print-ldd (make-command-ldd nil nil wrld ens wrld)
                                    (standard-co state)
                                    state))))
             (value :invisible)))))))

(defmacro pcs (cd1 cd2)

  ":Doc-Section History

  print the sequence of ~il[command]s between two ~il[command] descriptors~/
  ~bv[]
  Examples:
  :pcs 1 5              ; print commands 1 through 5
  :pcs 5 1              ; same as above
  :pcs :x (:x -3)       ; print the 3 most recently executed commands
  :pcs fn assoc-of-fn   ; print the commands between the one that introduced
                        ; fn and the one that introduced assoc-of-fn
  ~ev[]~/

  ~c[Pcs] takes two arguments, both of which are ~il[command] descriptors, and
  prints the ~il[command]s between them with ~ilc[pc].  The order of the two
  descriptors is irrelevant.  ~l[command-descriptor] for a
  description of ~il[command] descriptors.  ~l[pc] for a description
  of the format in which ~il[command]s are displayed.~/"

  (list 'pcs-fn cd1 cd2 t 'state))

(defmacro pbt (cd1)

  ":Doc-Section History

  print the ~il[command]s back through a ~il[command] descriptor~/
  ~bv[]
  Examples:
  :pbt :max      ; print back through the most recent command
  :pbt :x        ; print back through the most recent command
  :pbt fn        ; print back through the introduction of fn
  :pbt 5         ; print back through the fifth command executed
  :pbt (:x -4)   ; print back through the most recent five commands
  ~ev[]
  ~l[command-descriptor].~/

  ~c[Pbt] takes one argument, a ~il[command] descriptor, and prints the
  ~il[command]s from ~c[:max] (aka ~c[:x]) through the one described.
  ~l[command-descriptor] for a description of what a ~il[command]
  descriptor is.  ~l[pc] for a description of the format used to
  display ~il[command]s.  ~c[Pbt] will print the ~il[command]s that ~ilc[ubt] will
  undo.~/"

  (list 'pcs-fn cd1 :x nil 'state))

(defmacro pcb (cd)

  ":Doc-Section History

  print the ~il[command] block described by a ~il[command] descriptor~/
  ~bv[]
  Examples:
  :pcb :max ; print the most recent command block
  :pcb :x   ; print the most recent command block
  :pcb fn   ; print the command block that introduced fn
  :pcb 5    ; print the fifth command block
  ~ev[]
  ~l[command-descriptor].~/

  ~c[Pcb] takes one argument, a ~il[command] descriptor, and prints the ~il[command]
  block of the ~il[command] described.  ~l[command-descriptor] for
  details of ~il[command] descriptors.  ~l[pc] for description of the
  format in which ~il[command]s are displayed.  The ~il[command] block of a
  ~il[command] consists of the ~il[command] itself and all of the ~il[events] it
  created.  If the ~il[command] created a single event and that event is in
  fact the ~il[command] (i.e., if the ~il[command] typed was just an event such
  as a ~ilc[defun] or ~ilc[defthm] rather than a macro that expanded to some event
  forms), then ~c[pcb] just prints the ~il[command].  ~c[Pcb] sketches ~il[command] and
  all of the ~il[events] it created, rather than printing them fully.  If
  you wish to see just the ~il[command], in its entirety, use ~ilc[pc].  If you
  wish to see one of the ~il[events] within the block, in its entirety, use
  ~ilc[pe].  If you wish to see the ~il[command] sketched and all of the ~il[events]
  it created, in their entirety, use ~ilc[pcb!].~/"

  (list 'pcb-fn cd 'state))

(defun print-indented-list-msg (objects indent final-string)

; Indents the indicated number of spaces, then prints the first object, then
; prints a newline; then, recurs.  Finally, prints the string final-string.  If
; final-string is punctuation as represented by fmt directive ~y, then it will
; be printed just after the last object.

  (cond
   ((null objects) "")
   ((and final-string (null (cdr objects)))
    (msg (concatenate 'string "~_0~y1" final-string)
         indent
         (car objects)))
   (t
    (msg "~_0~y1~@2"
         indent
         (car objects)
         (print-indented-list-msg (cdr objects) indent final-string)))))

(defun print-indented-list (objects indent last-col channel evisc-tuple state)
  (cond ((null objects)
         (mv last-col state))
        (t (fmt1 "~@0"
                 (list (cons #\0 (print-indented-list-msg objects indent nil)))
                 0 channel state evisc-tuple))))

(defun print-book-path (book-path indent channel state)
  (assert$
   book-path
   (mv-let (col state)
     (fmt1 "~_0[Included books, outermost to innermost:~|"
           (list (cons #\0 indent))
           0 channel state nil)
     (declare (ignore col))
     (mv-let (col state)
       (print-indented-list book-path (1+ indent) 0 channel nil state)
       (pprogn (if (eql col 0)
                   (spaces indent col channel state)
                 state)
               (princ$ #\] channel state))))))
  
(defun pe-fn1 (wrld channel ev-wrld cmd-wrld state)
  (cond
   ((equal (access-event-tuple-form (cddar ev-wrld))
           (access-command-tuple-form (cddar cmd-wrld)))
    (print-ldd
     (make-command-ldd nil t cmd-wrld (ens state) wrld)
     channel state))
   (t
    (let ((indent (print-ldd-formula-column state))
          (ens (ens state)))
      (pprogn
       (print-ldd
        (make-command-ldd nil nil cmd-wrld ens wrld)
        channel state)
       (mv-let (col state)
         (fmt1 "~_0\\~%" (list (cons #\0 indent)) 0 channel state nil)
         (declare (ignore col))
         state)
       (let ((book-path (global-val 'include-book-path ev-wrld)))
         (cond (book-path
                (pprogn
                 (print-book-path (reverse book-path)
                                  indent channel state)
                 (fms "~_0\\~%" (list (cons #\0 indent)) channel state nil)))
               (t state)))
       (print-ldd
        (make-event-ldd #\> 1 t (cddar ev-wrld) ens wrld)
        channel
        state))))))

(defun pe-fn2 (logical-name wrld channel ev-wrld state)
  (er-let* ((cmd-wrld (superior-command-world ev-wrld wrld :pe state)))
           (pprogn (pe-fn1 wrld channel ev-wrld cmd-wrld state)
                   (let ((new-ev-wrld (decode-logical-name
                                       logical-name
                                       (scan-to-event (cdr ev-wrld)))))
                     (if new-ev-wrld
                         (pe-fn2 logical-name wrld channel new-ev-wrld state)
                       (value :invisible))))))

(defun pe-fn (logical-name state)
  (io? temporary nil (mv erp val state)
       (logical-name)
       (let ((wrld (w state))
             (channel (standard-co state)))
         (er-let* ((ev-wrld (er-decode-logical-name logical-name wrld :pe
                                                    state))
                   (cmd-wrld (superior-command-world ev-wrld wrld :pe state)))
                  (pprogn
                   (pe-fn1 wrld channel ev-wrld cmd-wrld state)
                   (let ((new-ev-wrld (and (not (eq logical-name :here))
                                           (decode-logical-name
                                            logical-name
                                            (scan-to-event (cdr ev-wrld))))))
                     (if (null new-ev-wrld)
                         (value :invisible)
                       (pprogn
                        (fms "Additional events for the logical name ~x0:~%"
                             (list (cons #\0 logical-name))
                             channel
                             state
                             nil)
                        (pe-fn2 logical-name wrld channel new-ev-wrld
                                state)))))))))

(defmacro pe (logical-name)

  ":Doc-Section History

  print the events named by a logical name~/
  ~bv[]
  Example:
  :pe fn   ; sketches the command that introduced fn and
           ; prints in full the event within it that created fn.
  ~ev[]
  ~l[logical-name].~/

  ~c[Pe] takes one argument, a logical name, and prints in full the event
  corresponding to the name.  ~c[Pe] also sketches the ~il[command] responsible
  for that event if the ~il[command] is different from the event itself.
  ~l[pc] for a description of the format used to display a ~il[command].  To
  remind you that the event is inferior to the ~il[command], i.e., you can only
  undo the entire ~il[command], not just the event, the event is indented
  slightly from the ~il[command] and a slash (meant to suggest a tree branch)
  connects them.

  If the given logical name corresponds to more than one event, then ~c[:pe]
  will print the above information for every such event.  Here is an
  example of such behavior.
  ~bv[]
  ACL2 !>:pe nth
        -4270  (ENCAPSULATE NIL ...)
               \\
  >V            (VERIFY-TERMINATION NTH)

  Additional events for the logical name NTH:
   PV   -4949  (DEFUN NTH (N L)
                      \"Documentation available via :doc\"
                      (DECLARE (XARGS :GUARD (AND (INTEGERP N)
                                                  (>= N 0)
                                                  (TRUE-LISTP L))))
                      (IF (ENDP L)
                          NIL
                          (IF (ZP N)
                              (CAR L)
                              (NTH (- N 1) (CDR L)))))
  ACL2 !>
  ~ev[]
  If you prefer to see only the formula for the given name, for example if it
  is part of a large ~ilc[mutual-recursion], ~pl[pf].~/"

  (list 'pe-fn logical-name 'state))

(defmacro pe! (logical-name)

  ":Doc-Section History

  deprecated (~pl[pe])~/

  Please ~pl[pe].  ~c[:Pe] now has the functionality formerly provided by
  ~c[:pe!].~/~/"

  (declare (ignore logical-name))
  `(er hard 'pe!
       "Pe! has been deprecated.  Please use :pe, which now has the ~
        functionality formerly provided by :pe!; or consider :pcb or :pcb!.  ~
        See :DOC history."))

(defun command-block-names1 (wrld ans symbol-classes)

; Symbol-Classes is a list of symbol-classes or else is t.  We scan down world
; to the next command landmark unioning into ans all the names whose
; introduction-time symbol-class is contained in symbol-classes, where
; symbol-classes t denotes the set of everything (!).  Note that symbol-classes
; t is different from symbol-classes (:program :ideal :common-lisp-compliant)
; because some names, e.g., label names, don't have symbol-classes (i.e., have
; access-event-tuple-symbol-class nil).  We return the final ans and the wrld
; starting with the next command landmark.  Note also that we use the
; symbol-class at introduction, not the current one.

  (cond
   ((or (null wrld)
        (and (eq (caar wrld) 'command-landmark)
             (eq (cadar wrld) 'global-value)))
    (mv ans wrld))
   ((and (eq (caar wrld) 'event-landmark)
         (eq (cadar wrld) 'global-value))
    (cond
     ((or (eq symbol-classes t)
          (member-eq (access-event-tuple-symbol-class (cddar wrld))
                     symbol-classes))
      (let ((namex (access-event-tuple-namex (cddar wrld))))
        (command-block-names1 (cdr wrld)
                              (cond ((equal namex 0) ans)
                                    ((equal namex nil) ans)
                                    ((atom namex)
; Might be symbolp or stringp.
                                     (add-to-set-equal namex ans))
                                    (t (union-equal namex ans)))
                              symbol-classes)))
     (t (command-block-names1 (cdr wrld) ans symbol-classes))))
   (t (command-block-names1 (cdr wrld) ans symbol-classes))))

(defun command-block-names (wrld symbol-classes)

; Wrld is a world that begins with a command landmark.  We collect all the
; names introduced in the symbol-classes listed.  Symbol-Classes = t means all
; (including nil).  We return the collection of names and the world starting
; with the next command landmark.

  (command-block-names1 (cdr wrld) nil symbol-classes))

(defun symbol-name-lst (lst)
  (cond ((null lst) nil)
        (t (cons (symbol-name (car lst))
                 (symbol-name-lst (cdr lst))))))

(defun acl2-query-simulate-interaction (msg alist controlledp ans state)
  (cond ((and (atom ans)
              (or controlledp
                  (and (not (f-get-global 'window-interfacep state))

; If a special window is devoted to queries, then there is no way to
; pretend to answer, so we don't.  We just go on.  Imagine that we
; answered and the window disappeared so quickly you couldn't see the
; answer.

                       (not (eq (standard-co state) *standard-co*)))))
         (pprogn
          (fms msg alist (standard-co state) state (ld-evisc-tuple state))
          (princ$ ans (standard-co state) state)
          (newline (standard-co state) state)
          state))
        (t state)))

(defun acl2-query1 (id qt alist state)

; This is the function actually responsible for printing the query
; and getting the answer, for the current level in the query tree qt.
; See acl2-query for the context.

  (let ((dv (cdr-assoc-query-id id (ld-query-control-alist state)))
        (msg "ACL2 Query (~x0):  ~@1  (~*2):  ")
        (alist1 (list (cons #\0 id)
                      (cons #\1 (cons (car qt) alist))
                      (cons #\2
                            (list "" "~s*" "~s* or " "~s*, "
                                  (symbol-name-lst (evens (cdr qt))))))))
    (cond
     ((null dv)
      (pprogn
       (io? query nil state
            (alist1 msg)
            (fms msg alist1 *standard-co* state (ld-evisc-tuple state)))
       (er-let*
        ((ans (state-global-let*
               ((infixp nil))
               (read-object *standard-oi* state))))
        (let ((temp (and (symbolp ans)
                         (assoc-keyword
                          (intern (symbol-name ans) "KEYWORD")
                          (cdr qt)))))
          (cond (temp
                 (pprogn
                  (acl2-query-simulate-interaction msg alist1 nil ans state)
                  (value (cadr temp))))
                (t (acl2-query1 id qt alist state)))))))
     ((eq dv t)
      (pprogn
       (acl2-query-simulate-interaction msg alist1 t (cadr qt) state)
       (value (caddr qt))))
     (t (let ((temp (assoc-keyword (if (consp dv) (car dv) dv) (cdr qt))))
          (cond
           ((null temp)
            (er soft 'acl2-query
                "The default response, ~x0, supplied in ~
                 ld-query-control-alist for the ~x1 query, is not one ~
                 of the expected responses.  The ~x1 query ~
                 is~%~%~@2~%~%Note the expected responses above.  See ~
                 :DOC ld-query-control-alist."
                (if (consp dv) (car dv) dv)
                id
                (cons msg alist1)))
           (t
            (pprogn
             (acl2-query-simulate-interaction msg alist1 t dv state)
             (value (cadr temp))))))))))

(defun acl2-query (id qt alist state)

; A query-tree qt is either an atom or a cons of the form
;   (str :k1 qt1 ... :kn qtn)
; where str is a string suitable for printing with ~@, each :ki is a
; keyword, and each qti is a query tree.  If qt is an atom, it is
; returned.  Otherwise, str is printed and the user is prompted for
; one of the keys.  When ki is typed, we recur on the corresponding
; qti.  Note that the user need not type a keyword, just a symbol
; whose symbol-name is that of one of the keywords.

; Thus, '("Do you want to redefine ~x0?" :y t :n nil) will print
; the question and require a simple y or n answer, returning t or nil
; as appropriate.

; Warning: We don't always actually read an answer!  We sometimes
; default.  Our behavior depends on the LD specials standard-co,
; standard-oi, and ld-query-control-alist, as follows.

; Let x be (cdr (assoc-eq id (ld-query-control-alist state))).  X must
; be either nil, a keyword, or a singleton list containing a keyword.
; If it is a keyword, then it must be one of the keys in (cdr qt) or
; else we cause an error.  If x is a keyword or a one-element list
; containing a keyword, we act as though we read that keyword as the
; answer to our query.  If x is nil, we read *standard-oi* for an
; answer.

; Now what about printing?  Where does the query actually appear?  If
; we get the answer from the control alist, then we print both the
; query and the answer to standard-co, making it simulate an
; interaction -- except, if the control alist gave us a singleton
; list, then we do not do any printing.  If we get the answer from
; *standard-oi* then we print the query to *standard-co*.  In
; addition, if we get the answer from *standard-oi* but *standard-co*
; is not standard-co, we simulate the interaction on standard-co.

  (cond ((atom qt) (value qt))
        ((not (and (or (stringp (car qt))
                       (and (consp (car qt))
                            (stringp (caar qt))))
                   (consp (cdr qt))
                   (keyword-value-listp (cdr qt))))
         (er soft 'acl2-query
             "The object ~x0 is not a query tree!  See the comment in ~
              acl2-query."
             qt))
        (t
         (er-let* ((qt1 (acl2-query1 id qt alist state)))
                  (acl2-query id qt1 alist state)))))

(defun collect-names-in-defun-modes (names defun-modes wrld)

; Collect the elements of names (all of which are fn symbols) whose current
; defun-mode is in the given set.

  (cond ((null names) nil)
        ((member-eq (fdefun-mode (car names) wrld) defun-modes)
         (cons (car names)
               (collect-names-in-defun-modes (cdr names) defun-modes wrld)))
        (t (collect-names-in-defun-modes (cdr names) defun-modes wrld))))

(defun ubt-ubu-query (kwd wrld1 wrld0 seen kept-commands wrld state banger)

; Wrld0 is a predecessor world of wrld1 which starts with a command landmark.
; We scan down wrld1 until we get to wrld0.  For each command encountered we
; ask the user if he wants us to preserve the :program names introduced.
; If so, we add the command to kept-commands.  We only ask about the latest
; definition of any name (the accumulator seen contains all the names we've
; asked about).  We return the list of commands to be re-executed (in
; chronological -- not reverse chronological -- order).  Of course, this is an
; error/value/state function.

; Kwd is :ubt, :ubu, or :ubt-prehistory.

; Note: The kept-commands, when non-nil, always starts with a defun-mode
; keyword command, i.e., :logic or :program.  This is the
; default-defun-mode in which the next command on the list, the first "real
; command," was executed.  When we grow the kept-command list, we remove
; redundant mode changes.  So for example, if kept-commands were
; '(:program cmd2 ...) and we then wished to add cmd1, then if the mode in
; which cmd1 was executed was :program the result is '(:program cmd1
; cmd2 ...)  while if cmd1's mode is :logic the result is '(:logic cmd1
; :program cmd2 ...).  Note that the mode may indeed be :logic, even
; though cmd1 introduces a :program function, because the mode of the
; introduced function may not be the default-defun-mode.  The commands are kept
; because the functions they introduce are :program, not because they were
; executed in :program mode.  But we must make sure the default mode is
; the same as it was when the command was last executed, just in case the mode
; of the functions is the default one.

  (cond
   ((or (null wrld1)
        (equal wrld1 wrld0))
    (pprogn (if (and seen
                     (not (f-get-global 'window-interfacep state)))
                (newline (standard-co state) state)
              state)
            (value kept-commands)))
   (t (mv-let
       (names wrld2)
       (command-block-names wrld1 '(:program))

; Names is the list of all names in the current command block whose
; introduction-time symbol-class was :program.

       (cond
        ((and names (set-difference-eq names seen))
         (er-let*
          ((ans (if banger
                    (value banger)
                    (let ((logic-names
                           (collect-names-in-defun-modes names '(:logic) wrld)))
                      (acl2-query
                       kwd
                       '("The command ~X01 introduced the :program ~
                          name~#2~[~/s~] ~&2.~#5~[~/  ~&3 ~#4~[has~/have~] ~
                          since been made logical.~]  Do you wish to ~
                          re-execute this command after the ~xi?"
                         :y t :n nil :y! :all :n! :none :q :q
                         :? ("We are undoing some commands.  We have ~
                              encountered a command, printed above, that ~
                              introduced a :program function symbol.  It is ~
                              unusual to use ~xi while defining :program ~
                              functions, since redefinition is permitted.  ~
                              Therefore, we suspect that you are mixing ~
                              :program and :logic definitions, as when one is ~
                              developing utilities for the prover.  When ~
                              undoing through such a mixed session, it is ~
                              often intended that the :logic functions be ~
                              undone while the :program ones not be, since the ~
                              latter ones are just utilities.  While we cannot ~
                              selectively undo commands, we do offer to redo ~
                              selected commands when we have finished undoing. ~
                               The situation is complicated by the fact that ~
                              :programs can become :logic functions after the ~
                              introductory event and that the same name can be ~
                              redefined several times.  Unless noted in the ~
                              question above, the functions discussed are all ~
                              still :program. The commands we offer for ~
                              re-execution are those responsible for ~
                              introducing the most recent definitions of ~
                              :program names, whether the names are still ~
                              :program or not.  That is, if in the region ~
                              undone there is more than one :program ~
                              definition of a name, we will offer to redo the ~
                              chronologically latest one.~%~%If you answer Y, ~
                              the command printed above will be re-executed.  ~
                              If you answer N, it will not be.  The answer Y! ~
                              means the same thing as answering Y to this and ~
                              all subsequent queries in this ~xi  The answer ~
                              N! is analogous.  Finally, Q means to abort the ~
                              ~xi without undoing anything."
                             :y t :n nil :y! :all :n! :none :q :q))
                       (list (cons #\i kwd)
                             (cons #\0
                                   (access-command-tuple-form (cddar wrld1)))
                             (cons #\1 (term-evisc-tuple t state))
                             (cons #\2 names)
                             (cons #\3 logic-names)
                             (cons #\4 (if (cdr logic-names) 1 0))
                             (cons #\5 (if (null logic-names) 0 1)))
                       state)))))
          (cond
           ((eq ans :q) (mv t nil state))
           (t
            (ubt-ubu-query
             kwd wrld2 wrld0
             (union-eq names seen)
             (if (or (eq ans t) (eq ans :all))
                 (cons (access-command-tuple-defun-mode (cddar wrld1))
                       (cons (access-command-tuple-form (cddar wrld1))
                             (cond
                              ((eq (access-command-tuple-defun-mode
                                    (cddar wrld1))
                                   (car kept-commands))
                               (cdr kept-commands))
                              (t kept-commands))))
               kept-commands)
             wrld state
             (or banger
                 (if (eq ans :all) :all nil)
                 (if (eq ans :none) :none nil)))))))
        (t (ubt-ubu-query kwd wrld2 wrld0 seen kept-commands wrld state
                          banger)))))))

; We can't define ubt-ubu-fn until we define LD, because it uses LD to replay
; selected commands.  So we proceed as though we had defined ubt-ubu-fn.

(defmacro ubt (cd)

  ":Doc-Section History

  undo the ~il[command]s back through a ~il[command] descriptor~/
  ~bv[]
  Examples:
  :ubt :max      ; undo back through the most recent command
                 ; (which just means undo the most recent command)
  :ubt :x        ; same as :ubt :max
  :u             ; same as :ubt :max with no questions asked
  :ubt fn        ; undo back through the introduction of fn
                 ; (including all the other events in fn's block)
  :ubt 5         ; undo back through the fifth command executed
  :ubt (:max -4) ; undo back through the most recent five commands
  :ubt (:x -4)   ; undo back through the most recent five commands
  ~ev[]
  ~l[command-descriptor].~/

  ~c[Ubt] takes one argument, a ~il[command] descriptor, and undoes the
  ~il[command]s from ~c[:]~ilc[max] (aka ~c[:x]) through the one described.
  ~l[command-descriptor].  ~ilc[Pbt] will print the ~il[command]s that ~c[ubt]
  will undo.  ~c[:]~ilc[Oops] will undo the undo.  ~l[oops].

  ~c[Ubt] can cause errors or queries.  To avoid these, ~pl[ubt!].

  It is important to remember that a ~il[command] may create several
  ~il[events].  That is, the ~il[command] that introduces ~c[fn1] may also introduce
  ~c[fn2].  Undoing the ~il[command] that created either of these will undo
  them both.  The ~il[events] created by a ~il[command] constitute the ~il[command]'s
  ``block'' and we can only undo entire blocks.  Use ~ilc[pcb] to print the
  ~il[command] block of a ~il[command] if you wish to see what will be lost by
  undoing the ~il[command].

  ~c[Ubt] will not undo into ``prehistory''.  ~c[:Ubt 1] will undo all of your
  ~il[command]s.  But ~c[:ubt -5] will cause an error, warning you that ~c[:ubt]
  cannot undo system initialization.

  ~l[u] for how to undo just the latest command, and ~pl[ubu] and ~pl[ubu!] for
  how to undo back up to, but not including, the current command.~/"

  (list 'ubt-ubu-fn :ubt cd 'state))

(defmacro ubt! (cd)

  ":Doc-Section History

  undo ~il[command]s, without a query or an error~/
  ~bv[]
  Example:
  :ubt! :x-4
  ~ev[]~/

  The keyword ~il[command] ~c[:ubt!] is the same as ~c[:]~ilc[ubt], but with related
  queries suppressed appropriately, and with a guarantee that it is
  ``error-free.''  More precisely, the error triple returned by ~c[:ubt!]
  will always have a first component of ~c[nil].  ~c[:]~ilc[Oops] will undo the last
  ~c[:ubt!].  ~l[ubt], ~pl[ubu], and ~pl[u].~/"

  (list 'ubt!-ubu!-fn :ubt cd 'state))

(defmacro ubu (cd)

  ":Doc-Section History

  undo the ~il[command]s back up to (not including) a ~il[command] descriptor~/
  ~bv[]
  Examples:
  :ubu :x-3      ; undo the last three commands (same as :ubt :x-2)
  :ubu (:x -3)   ; same as above
  :ubu fn        ; undo back up to, but not including the introduction of fn
                 ; (so fn will continue to be defined)
  :ubu 5         ; undo back up to, but not including, the fifth command
                 ; executed (leaving the first five commands in place)
  ~ev[]
  ~l[command-descriptor].~/

  ~c[Ubu] takes one argument, a ~il[command] descriptor, and undoes the
  ~il[command]s from ~c[:]~ilc[max] (aka ~c[:x]) up to, but not including, the
  indicated command.  ~l[command-descriptor].

  ~c[Ubu] can cause errors or queries.  To avoid these, ~pl[ubu!].

  Also ~pl[ubt], which is similar but also undoes the indicated command.  As
  for ~c[:]~ilc[ubt], ~c[:]~ilc[oops] will undo the undo (~pl[oops]) and
  ~ilc[ubu] will not undo into ``prehistory''.

  ~l[u] for how to undo just the latest command, and ~pl[ubt] and ~pl[ubt!] for
  how to undo back through (that is, including) the current command.~/"

  (list 'ubt-ubu-fn :ubu cd 'state))

(defmacro ubu! (cd)

  ":Doc-Section History

  undo ~il[command]s, without a query or an error~/
  ~bv[]
  Example:
  :ubu! :x-4
  ~ev[]~/

  The keyword ~il[command] ~c[:ubu!] is the same as ~c[:]~ilc[ubu], but with
  related queries suppressed appropriately, and with a guarantee that it is
  ``error-free.''  More precisely, the error triple returned by ~c[:ubu!]  will
  always have a first component of ~c[nil].  ~c[:]~ilc[Oops] will undo the last
  ~c[:ubu!].  Also ~pl[ubu], ~pl[ubt], and ~pl[u].~/"

  (list 'ubt!-ubu!-fn :ubu cd 'state))

(defmacro u nil

  ":Doc-Section History

  undo last ~il[command], without a query~/
  ~bv[]
  Example:
  :u
  ~ev[]~/

  The keyword ~il[command] ~c[:u] is the same as ~c[:]~ilc[ubt] ~c[:]~ilc[max],
  but with related queries suppressed appropriately.  ~c[:]~ilc[Oops] will undo
  the last ~c[:u].  ~l[ubt], ~pl[ubu], ~pl[ubt!], and ~pl[ubu!].~/"

  '(ubt! :x))

; We now develop the most trivial event we have: deflabel.  It
; illustrates the basic structure of our event code and we need it for
; all other events because any event with a documentation string uses
; the processing defined here.  (Actually defdoc is a bit simpler, and
; we deal with it just after deflabel.)

(defun chk-virgin (name new-type wrld)

; Although this function axiomatically always returns the
; value t, it sometimes causes an error.


  #+acl2-loop-only
  (declare (ignore name new-type wrld))
  #-acl2-loop-only
  (chk-virgin2 name new-type wrld) 
  t)

(deflabel name
  :doc
  ":Doc-Section Miscellaneous

  syntactic rules on logical names~/
  ~bv[]
  Examples                 Counter-Examples

  PRIMEP               91         (not a symbolp)
  F-AC-23              :CHK-LIST  (in KEYWORD package)
  1AX                  *PACKAGE*  (in the Lisp Package)
  |Prime Number|       1E3        (not a symbolp)
  ~ev[]~/

  Many different ACL2 entities have names, e.g., functions, macros,
  variables, constants, packages, theorems, ~il[theories], etc.
  Package names are strings.  All other names are symbols and may not
  be in the ~c[\"KEYWORD\"] package.  Moreover, names of functions,
  macros, constrained functions, and constants, other than those that
  are predefined, must not be in the ``main Lisp package'' (which is
  (~c[\"LISP\"] or ~c[\"COMMON-LISP\"], according to whether we are
  following CLTL1 or CLTL2).  An analogous restriction on variables
  is given below.

  ~c[T], ~c[nil], and all names above except those that begin with ampersand
  (&) are names of variables or constants.  ~c[T], ~c[nil], and those names
  beginning and ending with star (*) are constants.  All other such
  names are variables.

  Note that names that start with ampersand, such as ~c[&rest], may be
  lambda list keywords and are reserved for such use whether or not
  they are in the CLTL constant ~c[lambda-list-keywords].  (See pg 82
  of CLTL2.)  That is, these may not be used as variables.  Unlike
  constants, variables may be in the main Lisp package as long as they
  are in the original list of imports from that package to ACL2, the
  list ~c[*common-lisp-symbols-from-main-lisp-package*], and do not
  belong to a list of symbols that are potentially ``global.''  This
  latter list is the value of ~c[*common-lisp-specials-and-constants*].

  Our restrictions pertaining to the main Lisp package take into
  account that some symbols, e.g., ~c[lambda-list-keywords] and
  ~c[boole-c2], are ``special.''  Permitting them to be bound could
  have harmful effects.  In addition, the Common Lisp language does
  not allow certain manipulations with many symbols of that package.
  So, we stay away from them, except for allowing certain variables as
  indicated above.")

(defun chk-boot-strap-redefineable-namep (name ctx wrld state)
  (cond ((global-val 'boot-strap-pass-2 wrld)
         (value nil))
        ((not (member-eq name (global-val 'chk-new-name-lst wrld)))
         (er soft ctx
             "The name ~x0 is already in use and is not among those ~
              expected by chk-boot-strap-redefineable-namep to be redundantly defined ~
              during initialization. If you wish it to be, add ~x0 to ~
              the global-val setting of 'chk-new-name-lst in ~
              primordial-world-globals."
             name))
        ((not (chk-virgin name t wrld))
         (er soft ctx
             "Not a virgin name:  ~x0." name))
        (t (value nil))))

(defun maybe-coerce-overwrite-to-erase (old-type new-type mode)
  (cond ((and (eq old-type 'function)
              (eq new-type 'function))
         mode)
        (t :erase)))

(defun attachment-alist (fn wrld)
  (let ((prop (getprop fn 'attachment nil 'current-acl2-world wrld)))
    (and prop
         (cond ((symbolp prop)
                (getprop prop 'attachment nil 'current-acl2-world wrld))
               ((eq (car prop) :attachment-disallowed)
                prop) ; (cdr prop) follows "because", e.g., (msg "it is bad")
               (t prop)))))

(defun redefinition-renewal-mode (name old-type new-type reclassifyingp ctx
                                       wrld state)

; We use 'ld-redefinition-action to determine whether the redefinition of name,
; currently of old-type in wrld, is to be :erase, :overwrite or
; :reclassifying-overwrite.  New-type is the new type name will have and
; reclassifyingp is a non-nil, non-cons value only if this is a :program
; function to identical-defp :logic function redefinition.  If this
; redefinition is not permitted, we cause an error, in which case if
; reclassifyingp is a cons then it is an explanatory message to be printed in
; the error message, in the context "Note that <msg>".

; The only time we permit a redefinition when ld-redefinition-action prohibits
; it is when we return :reclassifying-overwrite, except for the case of
; updating non-executable :program mode ("proxy") functions; see :DOC
; defproxy.  In the latter case we have some concern about redefining inlined
; functions, so we proclaim them notinline; see install-defs-for-add-trip.

; This function interacts with the user if necessary.  See :DOC
; ld-redefinition-action.

  (let ((act (f-get-global 'ld-redefinition-action state))
        (proxy-upgrade-p
         (and (eq old-type 'function)
              (consp new-type)

; New-type is (function stobjs-in . stobjs-out); see chk-signature.

              (eq (car new-type) 'function)
              (eq (getprop name 'non-executablep nil 'current-acl2-world
                           wrld)
                  :program)

; A non-executable :program-mode function has no logical content, so it is
; logically safe to redefine it.  We check however that the signature hasn't
; changed, for the practical reason that we don't want to break existing
; calls.

              (equal (stobjs-in name wrld) (cadr new-type))
              (equal (stobjs-out name wrld) (cddr new-type))))
        (attachment-alist (attachment-alist name wrld)))
    (cond
     ((and reclassifyingp
           (not (consp reclassifyingp)))
      (cond ((member-eq name
                        (f-get-global 'program-fns-with-raw-code state))
             (er soft ctx
                 "The function ~x0 must remain in :PROGRAM mode, because it ~
                  has been marked as a function that has special raw Lisp ~
                  code."
                 name))
            (t (value :reclassifying-overwrite))))
     ((and attachment-alist
           (not (eq (car attachment-alist) :ATTACHMENT-DISALLOWED))

; During the boot-strap, we may replace non-executable :program mode
; definitions (from defproxy) without removing attachments, so that system
; functions implemented using attachments will not be disrupted.

           (not (global-val 'boot-strap-flg wrld)))
      (er soft ctx
          "The name ~x0 is in use as a ~@1, and it has an attachment.  Before ~
           redefining it you must remove its attachment, for example by ~
           executing the form ~x2.  We hope that this is not a significant ~
           inconvenience; it seemed potentially too complex to execute such a ~
           defattach form safely on your behalf."
          name
          (logical-name-type-string old-type)
          (cond ((programp name wrld)
                 `(defattach (,name nil) :skip-checks t))
                (t
                 `(defattach ,name nil)))))
     ((and (null act)
           (not proxy-upgrade-p))

; We cause an error, with rather extensive code below designed to print a
; helpful error message.

      (mv-let
       (erp val state)
       (er soft ctx
           "The name ~x0 is in use as a ~@1.~#2~[  ~/  (This name is used in ~
            the implementation of single-threaded objects.)  ~/  Note that ~
            ~@3~|~]The redefinition feature is currently off.  See :DOC ~
            ld-redefinition-action.~@4"
           name
           (logical-name-type-string old-type)
           (cond ((eq new-type 'stobj-live-var) 1)
                 ((consp reclassifyingp) 2)
                 (t 0))
           reclassifyingp
           (cond ((eq (getprop name 'non-executablep nil 'current-acl2-world
                               wrld)
                      :program)
                  (msg "  Note that you are attempting to upgrade a proxy, ~
                        which is only legal using an encapsulate signature ~
                        that matches the original signature of the function; ~
                        see :DOC defproxy."))
                 (t "")))
       (declare (ignore erp val))
       (er-let*
        ((ev-wrld (er-decode-logical-name name wrld ctx state)))
        (pprogn
         (let ((book-path-rev (reverse (global-val 'include-book-path
                                                   ev-wrld)))
               (current-path-rev (reverse (global-val 'include-book-path
                                                      wrld))))
           (io? error nil state
                (name book-path-rev current-path-rev)
                (pprogn
                 (cond ((null book-path-rev)
                        (fms "Note: ~x0 was previously defined at the top ~
                              level~#1~[~/ of the book being certified~].~|~%"
                             (list (cons #\0 name)
                                   (cons #\1
                                         (if (f-get-global 'certify-book-info
                                                           state)
                                             1
                                           0)))
                             (standard-co state) state nil))
                       (t (pprogn
                           (fms "Note: ~x0 was previously defined in the last ~
                                 of the following books.~|~%"
                                (list (cons #\0 name))
                                (standard-co state) state nil)
                           (print-book-path
                            book-path-rev
                            3 (standard-co state) state)
                           (newline (standard-co state) state))))
                 (cond ((null current-path-rev)
                        state)
                       (t (pprogn
                           (fms "Note: the current attempt to define ~x0 is ~
                                 being made in the last of the following ~
                                 books.~|~%"
                                (list (cons #\0 name))
                                (standard-co state) state nil)
                           (print-book-path
                            current-path-rev
                            3 (standard-co state) state)
                           (newline (standard-co state) state)))))))
         (silent-error state)))))
     ((and (hons-enabledp state) ; presumably an optimization
           (cdr (assoc-eq name (table-alist 'memoize-table wrld))))
      (er soft ctx
          "The name ~x0 is in use as a ~@1, and it is currently memoized.  ~
           You must execute ~x2 before attempting to redefine it."
          name
          (logical-name-type-string old-type)
          (list 'unmemoize (kwote name))))
     ((eq new-type 'package)

; Some symbols seen by this fn have new-type package, namely the base
; symbol of the rune naming the rules added by defpkg, q.v.  Old-type
; can't be 'package.  If this error message is eliminated and
; redefinition is ever permitted, then revisit the call of
; chk-just-new-name in chk-acceptable-defpkg and arrange for it to use
; the resulting world.

      (er soft ctx
          "When a package is introduced, a rule is added describing the ~
           result produced by (symbol-package-name (intern x pkg)).  That ~
           rule has a name, i.e., a rune, based on some symbol which must ~
           be new.  In the case of the current package definition the base ~
           symbol for the rune in question is ~x0.  The symbol is not new. ~
            Furthermore, the redefinition facility makes no provision for ~
           packages.  Please rename the package or :ubt ~x0.  Sorry."
          name))
     ((null (getprop name 'absolute-event-number nil 'current-acl2-world wrld))

; One might think that (a) this function is only called on old names and (b)
; every old name has an absolute event number.  Therefore, why do we ask the
; question above?  Because we could have a name introduced by the signature in
; encapsulate that is intended to be local, but was not embedded in a local
; form.

      (er soft ctx
          "The name ~x0 appears to have been introduced in the signature list ~
           of an encapsulate, yet is being defined non-locally."
          name))

; We do not permit any supporter of a single-threaded object implementation to
; be redefined, except by redefining the single-threaded object itself.  The
; main reason is that even though the functions like the recognizers appear as
; ordinary predicates, the types are really built in across the whole
; implementation.  So it's all or nothing.  Besides, I don't really want to
; think about the weird combinations of changing a defstobj supporter to an
; unrelated function, even if the user thinks he knows what he is doing.

     ((and (defstobj-supporterp name wrld)
           (not (and (eq new-type 'stobj) 
                     (eq old-type 'stobj))))

; I sweated over the logic above.  How do we get here?  Name is a defstobj
; supporter.  Under what conditions do we permit a defstobj supporter to be
; redefined?  Only by redefining the object name itself -- not by redefining
; individual functions.  So we want to avoid causing an error if the new and
; old types are both 'stobj (i.e., name is the name of the single-threaded
; object both in the old and the new worlds).

; WARNING: If this function does not cause an error, we proceed, in
; chk-redefineable-namep, to renew name.  In the case of stobj names, that
; function renews all the supporting names as well.  Thus, it is important to
; maintain the invariant: if this function does not cause an error and name is
; a defstobj supporter, then name is the stobj name.

      (er soft ctx
          "The name ~x0 is in use supporting the implementation of ~
           the single-threaded object ~x1.  We do not permit such ~
           names to be redefined except by redefining ~x1 itself with ~
           a new DEFSTOBJ."
          name
          (defstobj-supporterp name wrld)))

; If we get here, we know that either name is not currently a defstobj
; supporter of any kind or else that it is the old defstobj name and is being
; redefined as a defstobj.
        
     (t
      (let ((sysdefp (acl2-system-namep name wrld)))
        (cond
         ((and sysdefp
               (not (ttag (w state)))
               (not (and proxy-upgrade-p
                         (global-val 'boot-strap-flg wrld))))
          (er soft ctx
              "Redefinition of system names is not permitted unless there ~
               is an active trust tag (ttag).  See :DOC defttag."))
         (proxy-upgrade-p

; We erase all vestiges of the old function.  It may well be safe to return
; :overwrite instead.  But at one time we tried that while also leaving the
; 'attachment property unchanged by renew-name/overwrite (rather than making it
; unbound), and we then got an error from the following sequence of events,
; "HARD ACL2 ERROR in LOGICAL-NAME-TYPE: FOO is evidently a logical name but of
; undetermined type."

;  (defproxy foo (*) => *)
;  (defttag t)
;  (defun g (x) x)
;  (defattach (foo g) :skip-checks t)
;  (defattach (foo nil) :skip-checks t)
;  (defstub foo (x) t)

; When we promote boot-strap functions from non-executable :program mode
; ("proxy") functions to encapsulated functions, we thus lose the 'attachment
; property.  Outside the boot-strap, where we disallow all redefinition when
; there is an attachment, this is not a restriction.  But in the boot-strap, we
; will lose the 'attachment property even though the appropriate Lisp global
; (the attachment-symbol) remains set.  This doesn't present a problem,
; however; system functions are special, in that they can very temporarily have
; attachments without an 'attachment property, until the redefinition in
; progress (by an encapsulate) is complete.

          (cond ((eq (car attachment-alist) :ATTACHMENT-DISALLOWED)
                 (er soft ctx
                     "Implementation error: It is surprising to see ~
                      attachments disallowed for a non-executable :program ~
                      mode function (a proxy).  See ~
                      redefinition-renewal-mode."))
                (t (value :erase))))
         ((eq (car act) :doit!)
          (value
           (maybe-coerce-overwrite-to-erase old-type new-type (cdr act))))
         ((or (eq (car act) :query)
              (and sysdefp
                   (or (eq (car act) :warn)
                       (eq (car act) :doit))))
          (er-let*
           ((ans (acl2-query
                  :redef
                  '("~#0~[~x1 is an ACL2 system~/The name ~x1 is in use as ~
                     a~] ~@2.~#3~[~/  Its current defun-mode is ~@4.~] Do you ~
                     ~#0~[really ~/~]want to redefine it?~#6~[~/  Note: if ~
                     you redefine it we will first erase its supporters, ~
                     ~&7.~]"

                    :n nil :y t :e erase :o overwrite
                    :? ("N means ``no'' and answering that way will abort the ~
                         attempted redefinition.  All other responses allow ~
                         the redefinition and may render ACL2 unsafe and/or ~
                         unsound.  Y in the current context is the same as ~
                         ~#5~[E~/O~].  E means ``erase the property list of ~
                         ~x1 before redefining it.''  O means ``Overwrite ~
                         existing properties of ~x1 while redefining it'' but ~
                         is different from erasure only when a function is ~
                         being redefined as another function.   Neither ~
                         alternative is guaranteed to produce a sensible ACL2 ~
                         state.  If you are unsure of what all this means, ~
                         abort with N and see :DOC ld-redefinition-action for ~
                         details."
                        :n nil :y t :e erase :o overwrite))
                  (list (cons #\0 (if sysdefp 0 1))
                        (cons #\1 name)
                        (cons #\2 (logical-name-type-string old-type))
                        (cons #\3 (if (eq old-type 'function) 1 0))
                        (cons #\4 (if (eq old-type 'function)
                                      (defun-mode-string
                                        (fdefun-mode name wrld))
                                    nil))
                        (cons #\5 (if (eq (cdr act)
                                          :erase)
                                      0 1))
                        (cons #\6 (if (defstobj-supporterp name wrld)
                                      1 0))
                        (cons #\7 (getprop (defstobj-supporterp name wrld)
                                           'stobj
                                           nil
                                           'current-acl2-world
                                           wrld)))
                  state)))
           (cond
            ((null ans) (mv t nil state))
            ((eq ans t)
             (value
              (maybe-coerce-overwrite-to-erase old-type new-type (cdr act))))
            ((eq ans 'erase) (value :erase))
            (t (value
                (maybe-coerce-overwrite-to-erase old-type new-type
                                                 :overwrite))))))
         (t

; If name is a system name, then the car of 'ld-redefinition-action must be
; :warn!  If name is not a system name, the car of 'ld-redefinition-action may
; be :warn!, :doit, or :warn.  In all cases, we are to proceed with the
; redefinition without any interaction here.

          (value
           (maybe-coerce-overwrite-to-erase old-type new-type
                                            (cdr act))))))))))

(defun redefined-names1 (wrld ans)
  (cond ((null wrld) ans)
        ((eq (cadar wrld) 'redefined)
         (cond
          ((eq (car (cddar wrld)) :reclassifying-overwrite)
           (redefined-names1 (cdr wrld) ans))
          (t (redefined-names1 (cdr wrld)
                               (add-to-set-eq (caar wrld) ans)))))
        (t (redefined-names1 (cdr wrld) ans))))

(defun redefined-names (state)

  ":Doc-Section Miscellaneous

  to collect the names that have been redefined~/
  ~bv[]
  Example and General Forms:
  (redefined-names state)
  ~ev[]~/

  This function collects names that have been redefined in the current ACL2
  ~il[state].  ~c[:]~ilc[Program] mode functions that were reclassified to
  ~c[:]~ilc[logic] functions are not collected, since such reclassification
  cannot imperil soundness because it is allowed only when the new and old
  definitions are identical.

  Thus, if ~c[(redefined-names state)] returns ~c[nil] then no unsafe
  definitions have been made, regardless of ~ilc[ld-redefinition-action].
  ~l[ld-redefinition-action].

  WARNING: This function does not report names that are not explicitly
  redefined in the current logical ~il[world].  Consider for example:
  ~bv[]
  (encapsulate
   ()
   (defun foo () t)
   (local (defun foo () nil))
   (defthm foo-prop
     (equal (foo) nil)
     :rule-classes nil))
  ~ev[]
  If you attempt to call ~ilc[certify-book] in the resulting world, ACL2 will
  appropriately refuse to do the certification:
  ~bv[]
  ACL2 Error in (CERTIFY-BOOK \"foo\" ...):  At least one command in the
  current ACL2 world was executed while the value of state global variable
  'LD-REDEFINITION-ACTION was not nil:

    (DEFUN FOO NIL T)

  Certification is therefore not allowed in this world.  You can use
  :ubt to undo back through this command; see :DOC ubt.
  ~ev[]
  However, since the local redefinition of ~c[foo] is gone in the certification
  world, ~c[(redefined-names state)] will return ~c[nil].  (Technical aside,
  to be ignored except for those interested in implementation details: ACL2
  inhibits ~c[certify-book] in this example because the definition of ~c[foo]
  is the value of ~c[(global-val 'redef-seen (w state))].)"

  (redefined-names1 (w state) nil))

(defun chk-redefineable-namep (name new-type reclassifyingp ctx wrld state)

; Name is a non-new name in wrld.  We are about to redefine it and make its
; logical-name-type be new-type.  If reclassifyingp is non-nil and not a consp
; message (see redundant-or-reclassifying-defunp) then we know that in fact
; this new definition is just a conversion of the existing definition.
; Redefinition is permitted if the value of 'ld-redefinition-action is not nil,
; or if we are defining a function to replace a non-executable :program mode
; function (such as is introduced by defproxy).  In all these non-erroneous
; cases, we renew name appropriately and return the resulting world.

; The LD special 'ld-redefinition-action determines how we react to
; redefinition attempts.  See :DOC ld-redefinition-action.

; It must be understood that if 'ld-redefinition-action is non-nil then no
; logical sense is maintained, all bets are off, the system is unsound and
; liable to cause all manner of hard lisp errors, etc.

  (let ((old-type (logical-name-type name wrld nil)))
    (cond
     ((and (global-val 'boot-strap-flg wrld)
           (not (global-val 'boot-strap-pass-2 wrld))
           (or (not reclassifyingp)
               (consp reclassifyingp)))

; If we are in the first pass of booting and name is one of those we know is
; used before it is defined, we act as though it were actually new.

      (er-progn
       (chk-boot-strap-redefineable-namep name ctx wrld state)
       (value wrld)))
     (t

; In obtaining the renewal mode, :erase or :overwrite, we might cause an error
; that aborts because name is not to be redefined.

      (er-let*
       ((renewal-mode
         (redefinition-renewal-mode name
                                    old-type new-type reclassifyingp
                                    ctx wrld state)))
       (cond
        ((defstobj-supporterp name wrld)

; Because of the checks in redefinition-renewal-mode, we know the
; defstobj-supporterp above returns name itself.  But to be rugged I
; will code it this way.  If name is a defstobj supporter of any kind,
; we renew all the supporters!

         (value
          (renew-names (cons name
                             (getprop (defstobj-supporterp name wrld)
                                      'stobj
                                      nil
                                      'current-acl2-world
                                      wrld))
                       renewal-mode wrld)))
        (t (value (renew-name name renewal-mode wrld)))))))))

(defun chk-just-new-name (name new-type reclassifyingp ctx w state)

; Assuming that name has survived chk-all-but-new-name, we check that it is in
; fact new.  If it is, we return the world, w.  If it is not new, then what we
; do depends on various state variables such as whether we are in boot-strap
; and whether redefinition is allowed.  But unless we cause an error we will
; always return the world extending w in which the redefinition is to occur.

; Name is being considered for introduction with logical-name-type new-type.
; Reclassifyingp, when not nil and not a consp, means that this redefinition is
; known to be identical to the existing definition except that it has been
; given the new defun-mode :logic.  This will allow us to permit the
; redefinition of system functions.  See the comment in
; redundant-or-reclassifying-defunp for more about reclassifyingp.

; Observe that it is difficult for the caller to tell whether redefinition is
; occurring.  In fact, inspection of the returned world will reveal the answer:
; sweep down the world to the next event-landmark and see whether any
; 'redefined property is stored.  All names with such a property are being
; redefined by this event (possibly soundly by reclassifying :program names).
; This sweep is actually done by collect-redefined on behalf of stop-event
; which prints a suitable warning message.

  (cond        
   ((new-namep name w)

; If name has no properties in w, then we next check that it is not
; defined in raw Common Lisp.

    (let ((actual-new-type
           (cond ((and (consp new-type)
                       (eq (car new-type) 'function))
                  'function)
                 (t new-type))))
      (cond ((not (chk-virgin name actual-new-type w))
             (er soft ctx
                 "Not a virgin name for type ~x0:  ~x1." new-type name))
            (t (value w)))))
   ((and (global-val 'boot-strap-flg w)
         (not (global-val 'boot-strap-pass-2 w))
         (or (not reclassifyingp)
             (consp reclassifyingp)))

; If we are in the first pass of booting and name is one of those we know is
; used before it is defined, we act as though it were actually new.

    (er-progn
     (chk-boot-strap-redefineable-namep name ctx w state)
     (value w)))
   (t
    (chk-redefineable-namep name new-type reclassifyingp ctx w state))))

(defun no-new-namesp (lst wrld)

; Lst is a true list of symbols.  We return t if every name in it
; is old.

  (cond ((null lst) t)
        ((new-namep (car lst) wrld) nil)
        (t (no-new-namesp (cdr lst) wrld))))

(defun chk-just-new-names (names new-type reclassifyingp ctx w state)

; Assuming that names has survived chk-all-but-new-names, we check that they
; are in fact all new.  We either cause an error or return the world, we are to
; use in the coming definition.  Observe that it is difficult for the caller to
; tell whether redefinition is occuring.  In fact, inspection of world will
; reveal the answer: sweep down world to the next event-landmark and see
; whether any 'redefined property is stored.  All names with such a property
; are being redefined by this event.  This sweep is actually done by
; collect-redefined on behalf of stop-event which prints a suitable warning
; message.

; Reclassifyingp is as explained in redundant-or-reclassifying-defunp.  In
; particular, it can be a message (a cons pair suitable for printing with ~@).

  (cond
   ((null names) (value w))
   (t (er-let*
        ((wrld1 (chk-just-new-name (car names) new-type reclassifyingp
                                   ctx w state)))
        (chk-just-new-names (cdr names) new-type reclassifyingp
                            ctx wrld1 state)))))

; We now develop the code for checking that a documentation string
; is well formed.

(defconst *return-character* (code-char 13))

(defun read-symbol-from-string1 (str i len ans)
  (cond ((< i len)
         (let ((c (char str i)))
           (cond ((or (eql c #\Space)
                      (eql c #\Newline)

; The following modification is useful for avoiding CR characters in Windows
; systems that use CR/LF for line breaks.

                      (eql c *return-character*))
                  (mv (reverse ans) i))
                 (t (read-symbol-from-string1 str (1+ i) len
                                              (cons (char-upcase c) ans))))))
        (t (mv (reverse ans) i))))

(defun read-symbol-from-string2 (str i len ans)
  (cond ((< i len)
         (let ((c (char str i)))
           (cond ((eql c #\|)
                  (mv (reverse ans) i))
                 (t (read-symbol-from-string2 str (1+ i) len
                                              (cons c ans))))))
        (t (mv (reverse ans) i))))

(defun read-symbol-from-string (str i pkg-witness)

; Reads one symbol from str, starting at index i.  The symbol will
; either be in the pkg of pkg-witness (which is a symbol) or else
; will be in "KEYWORD" or in "ACL2" if its print representation so
; specifies.  Leading whitespace is ignored.  Two values are returned:
; the symbol read and the index of the first whitespace character
; after the symbol read.  If there is no non-whitespace after i,
; two nils are returned.

; Warning:  This is a cheap imitation of the CLTL READ.  We put the symbol in
; the keyword package if the first non-whitespace char is a colon.  Then we
; read to a certain delimiter, either vertical bar or space/newline, depending
; on whether the next char is a vertical bar.  Then we make a symbol out of
; that, even if it has the syntax of a number.  And we put it in pkg-witness's
; package unless the first chars of it are ACL2::.  Known Discrepancy:  We read
; |ACL2::Foo| as ACL2::|Foo| while CLTL reads it as pkg::|ACL2::Foo|.

  (let* ((len (length str))
         (i (scan-past-whitespace str i len)))
    (cond ((< i len)
           (mv-let (char-lst j)
                   (cond
                    ((and (eql (char str i) #\:)
                          (< (1+ i) len))
                     (cond
                      ((eql (char str (1+ i)) #\|)
                       (read-symbol-from-string2 str (+ i 2) len nil))
                      (t (read-symbol-from-string1 str (1+ i) len nil))))
                    ((eql (char str i) #\|)
                     (read-symbol-from-string2 str (1+ i) len nil))
                    (t (read-symbol-from-string1 str i len nil)))
                   (mv
                    (cond
                     ((eql (char str i) #\:)
                      (intern (coerce char-lst 'string)
                              "KEYWORD"))
                     ((and (<= 6 (length char-lst))
                           (eql #\A (car char-lst))
                           (eql #\C (cadr char-lst))
                           (eql #\L (caddr char-lst))
                           (eql #\2 (cadddr char-lst))
                           (eql #\: (car (cddddr char-lst)))
                           (eql #\: (cadr (cddddr char-lst))))
                      (intern (coerce (cddr (cddddr char-lst)) 'string)
                              "ACL2"))
                     (t (intern-in-package-of-symbol (coerce char-lst 'string)
                                                     pkg-witness)))
                    j)))
          (t (mv nil nil)))))

(defun scan-past-newline (str i maximum)
  (cond ((< i maximum)
         (cond ((eql (char str i) #\Newline)
                (1+ i))
               (t (scan-past-newline str (1+ i) maximum))))
        (t maximum)))

(defun scan-past-newlines (str i maximum)
  (cond ((< i maximum)
         (cond ((eql (char str i) #\Newline)
                (scan-past-newlines str (1+ i) maximum))
               (t i)))
        (t maximum)))

(defun scan-past-tilde-slash (str i maximum)
  (cond ((< i maximum)
         (cond ((eql (char str i) #\~)
                (cond ((and (< (1+ i) maximum)
                            (eql (char str (1+ i)) #\/))
                       (cond ((or (= i 0) (not (eql (char str (1- i)) #\~)))
                              (+ 2 i))
                             (t (scan-past-tilde-slash str (+ 2 i) maximum))))
                      (t (scan-past-tilde-slash str (+ 2 i) maximum))))
               (t (scan-past-tilde-slash str (1+ i) maximum))))
        (t maximum)))

(defun scan-to-doc-string-part1 (parti str i maximum)
  (cond ((= parti 0) i)
        (t (scan-to-doc-string-part1
            (1- parti)
            str
            (scan-past-whitespace
             str
             (scan-past-tilde-slash str i maximum)
             maximum)
            maximum))))

(defun scan-to-doc-string-part (i str)

; We assume str is a doc-stringp.  Thus, it has the form:
; ":Doc-Section <sym><cr><part0>~/ <part1>~/ <part2>~/ <part3>"
; where the first space above is one or more #\Spaces, the <cr> is
; arbitrary whitespace but including at least one #\Newline, and the
; remaining spaces are arbitrary whitespace.  It is possible that
; the string terminates after any parti.  We return the index of
; the ith part.

  (let ((len (length str)))
    (scan-to-doc-string-part1 i
                              str
                              (scan-past-whitespace
                               str
                               (scan-past-newline str 0 len)
                               len)
                              len)))

(defun get-one-liner-as-string1 (str i j acc)
  (cond ((<= i j)
         (get-one-liner-as-string1 str i (1- j) (cons (char str j) acc)))
        (t (coerce acc 'string))))

(defun get-one-liner-as-string (str)
  (let ((i (scan-to-doc-string-part 0 str))
        (max (length str)))
    (get-one-liner-as-string1 str
                              i
                              (- (scan-past-tilde-slash str i max) 3)
                              nil)))
                            
(defun read-doc-string-citations1 (name str i)
  (mv-let (sym1 i)
          (read-symbol-from-string str i name)
          (cond
           ((null i) nil)
           (t (mv-let (sym2 i)
                      (read-symbol-from-string str i name)
                      (cond
                       ((null i)
                        (cons (cons sym1 0) nil))
                       (t
                        (cons (cons sym1 sym2)
                              (read-doc-string-citations1 name str i)))))))))

(defun read-doc-string-citations (name str)

; This function reads the contents of the citations section of a doc
; string, expecting it to be an even number of symbols and returning
; them as a list of pairs.  I.e., ":cite a :cited-by b :cite c" is
; read as ((:cite . a) (:cited-by . b) (:cite . c)).  If there are an
; odd number of symbols, a 0 replaces the unsupplied one.  Since we
; can't possibly read a 0 as a number (our stupid reader makes
; symbols) this is an unambiguous signal that the string does not
; parse.  This function doesn't care whether the symbols in the odd
; positions are :cite and :cited-by or not.  I.e., "A B C D" reads as
; ((A . B) (C . D)).

  (let ((i (scan-to-doc-string-part 3 str)))
    (read-doc-string-citations1 name str i)))

(defun doc-topicp (name wrld)
  (assoc-equal name (global-val 'documentation-alist wrld)))

(defun ignore-doc-string-error (wrld)
  (cdr (assoc-eq :ignore-doc-string-error
                 (table-alist 'acl2-defaults-table wrld))))

(defmacro er-doc (ctx str &rest str-args)
  `(let ((er-doc-ign (ignore-doc-string-error (w state))))
     (cond ((eq er-doc-ign t)
            (value nil))
           ((eq er-doc-ign :warn)
            (pprogn (warning$ ,ctx "Documentation"
                              "No :doc string will be stored.  ~@0"
                              (check-vars-not-free (er-doc-ign)
                                                   (msg ,str ,@str-args)))
                    (value nil)))
           (t (er soft ,ctx "~@0"
                  (check-vars-not-free (er-doc-ign)
                                       (msg ,str ,@str-args)))))))

(defun chk-doc-string-citations (str citations wrld)

; We know that citations is a list of pairs of symbols, by construction -- it
; was produced by read-doc-string-citations.  We check that the car of each
; pair is either :cite or :cited-by and the cdr is a previously documented
; topic symbol, returning an error message or nil.

  (cond
   ((null citations) nil)
   ((or (eq (caar citations) :cite)
        (eq (caar citations) :cited-by))
    (cond ((equal (cdar citations) 0)
           (msg "The citations section of a formatted documentation string ~
                 must contain an even number of tokens.  The citations below ~
                 do not.  See :DOC doc-string.~|~%~x0.~%"
                str))
          ((doc-topicp (cdar citations) wrld)
           (chk-doc-string-citations str (cdr citations) wrld))
          (t (msg "The symbols cited in the citations section of a formatted ~
                   documentation string must be previously documented topics. ~
                    ~x0 is not and, hence, the string below is ill-formed.  ~
                   See :DOC doc-string.~|~%~x1.~%"
                  (cdar citations)
                  str))))
   (t (msg "The citations section of a formatted documentation string must ~
            contain an even number of tokens.  Each token in an odd numbered ~
            position must be either :CITE or :CITED-BY.  But in the string ~
            below ~x0 occurs in an odd numbered position.  See :DOC ~
            doc-string.~|~%~x1.~%"
           (caar citations)
           str))))

(defun chk-well-formed-doc-string (name doc ctx state)

; This function checks that doc is a well-formed doc string.
; It either causes an error or returns (as the value component of
; an error triple) a pair (section-symbol . citations) obtained
; by parsing the doc string.  If doc does not even appear to
; be one of our formatted doc strings, we return nil.

  (let ((wrld (w state)))
    (cond
     ((doc-stringp doc)
      (let ((len (length doc))
            (old-doc-tuple
             (assoc-equal name (global-val 'documentation-alist wrld))))
        (cond

; We used to print a warning here when a system DEFLABEL is redefined, which
; advised that the documentation would remain unchanged.  Probably we had this
; code as an aid towards proving our way through axioms.lisp, but now we don't
; seem to need it.

         ((= (scan-past-tilde-slash
              doc
              (scan-past-tilde-slash
               doc
               (scan-past-newline doc 0 len)
               len)
              len)
             len)
          (er-doc ctx
                  "Formatted documentation strings must contain at least two ~
                   occurrences of tilde slash after the first newline so as ~
                   to delimit the three required parts:  the one-liner, the ~
                   notes, and the details.  While the notes section may be ~
                   empty, the details section may not.  The string below ~
                   violates this requirement.  See :DOC doc-string.~|~%~x0.~%"
                  doc))
         (t
          (mv-let (section-sym i)
                  (read-symbol-from-string doc 13
                                           (if (stringp name)
                                               'chk-well-formed-doc-string
                                             name))

; If we're documenting a package or book name, i.e., a stringp, then we can't
; use it to provide the default package in which read-symbol-from-string
; interns its symbols.  We use the "ACL2" package.

                  (cond
                   ((null i)
                    (er-doc ctx
                            "Formatted documentation strings must specify a ~
                             section symbol after the :Doc-Section header and ~
                             before the first newline character.  The string ~
                             below does not specify a section symbol.  See ~
                             :DOC doc-string.~|~%~y0.~%"
                            doc))
                   ((and old-doc-tuple
                         (not (equal section-sym (cadr old-doc-tuple))))
                    (er-doc ctx
                            "The documentation string already in place for ~
                             the name ~x0 is stored under section name ~x1, ~
                             but you are trying to store it under a new ~
                             section name, ~x2.  This is not allowed.  See ~
                             :DOC defdoc."
                            name (cadr old-doc-tuple) section-sym))
                   ((or (equal section-sym name)
                        (doc-topicp section-sym wrld))
                    (let ((citations
                           (read-doc-string-citations section-sym doc)))
                      (let ((msg
                             (chk-doc-string-citations doc citations wrld)))
                        (cond
                         (msg (er-doc ctx "~@0" msg))
                         (t
                          (pprogn
                           (if old-doc-tuple
                               (warning$ ctx "Documentation"
                                         "The name ~x0 is currently ~
                                          documented.  That documentation is ~
                                          about to be replaced."
                                         name)
                             state)
                           (value (cons section-sym citations))))))))
                   (t (er-doc ctx
                              "The section symbol of a formatted ~
                               documentation string must be either the name ~
                               being documented or a previously documented ~
                               name.  ~x1 is neither.  Thus, the string below ~
                               is an ill-formed documentation string.  See ~
                               :DOC doc-string.~|~%~x2.~%"
                              name section-sym doc))))))))
     (t (value nil)))))

(defun translate-doc (name doc ctx state)

; If this function does not cause an error, it returns a pair of the form
; (section-symbol . citations) parsed from the doc string, or nil if the
; doc string is unformatted.

  (cond ((and doc (not (stringp doc)))
         (er soft ctx
             "When a documentation string is supplied the value must ~
              be a string, but ~x0 is not.  See :DOC doc-string."
             doc))
        ((null name)
         (cond ((doc-stringp doc)
                (er soft ctx
                    "Events that introduce no names (e.g., in-theory ~
                     and verify-guards) are not permitted to have ~
                     documentation strings that begin with the ~
                     characters ``:Doc-Section''.  See :DOC ~
                     doc-string."))
               (t (value nil))))
        (t (chk-well-formed-doc-string name doc ctx state))))

(defun translate-doc-lst (names docs ctx state)
  (cond
   ((null names) (value nil))
   (t (er-let* ((pair (translate-doc (car names) (car docs) ctx state))
                (rst (translate-doc-lst (cdr names) (cdr docs) ctx state)))
               (value (cons pair rst))))))

(defun get-cites (citations)

; This function collects all the symbols that are paired with
; :cite in the citations alist.

  (cond ((null citations) nil)
        ((eq (caar citations) :cite)
         (add-to-set-equal (cdar citations)
                           (get-cites (cdr citations))))
        (t (get-cites (cdr citations)))))

(defun alpha-< (x y)

; X and y are symbols or strings.  We return t iff x comes before y in
; an alphabetic ordering of their print names.  We are somewhat free
; to decide how to handle packages and strings v. symbols.  We choose
; to put 'ABC before "ABC" and we use package-names only to break
; ties among two symbols with the same symbol-name.

  (let ((xstr (if (symbolp x) (symbol-name x) x))
        (ystr (if (symbolp y) (symbol-name y) y)))
    (cond ((string< xstr ystr) t)
          ((equal xstr ystr)
           (if (symbolp x)
               (if (symbolp y)
                   (string< (symbol-package-name x)
                            (symbol-package-name y))
                   t)
               nil))
          (t nil))))

(defun merge-alpha-< (l1 l2)
  (cond ((null l1) l2)
        ((null l2) l1)
        ((alpha-< (car l1) (car l2))
         (cons (car l1) (merge-alpha-< (cdr l1) l2)))
        (t (cons (car l2) (merge-alpha-< l1 (cdr l2))))))

(defun merge-sort-alpha-< (l)
  (cond ((null (cdr l)) l)
        (t (merge-alpha-< (merge-sort-alpha-< (evens l))
                          (merge-sort-alpha-< (odds l))))))

(defun update-alpha-<-alist (key val alist)

; Alist is an alist whose keys are either symbols or strings and
; ordered by alpha-<.  We bind key to val.  Key may already be
; present.

  (cond ((null alist) (list (cons key val)))
        ((equal key (caar alist)) (cons (cons key val) (cdr alist)))
        ((alpha-< (caar alist) key)
         (cons (car alist) (update-alpha-<-alist key val (cdr alist))))
        (t (cons (cons key val) alist))))

(defun put-cited-bys (name citations alist)

; This function visits every symbol paired with :cited-by in the
; citations alist and puts name in the citations field of the symbol,
; unless name is either the symbol itself or name already occurs in
; the citations.  Alist is the 'documentation-alist.

  (cond
   ((null citations) alist)
   (t (put-cited-bys
       name
       (cdr citations)
       (if (and (eq (caar citations) :cited-by)
                (not (equal name (cdar citations))))
           (let ((doc-tuple (assoc-equal (cdar citations) alist)))
             (cond ((member-equal name (caddr doc-tuple))
                    alist)
                   (t (update-alpha-<-alist
                       (cdar citations)
                       (list (cadr doc-tuple)
                             (cons name (caddr doc-tuple))
                             (cadddr doc-tuple))
                       alist))))
           alist)))))

(defun update-doc-data-base (name doc pair wrld)

; Name is a documented name, i.e., a symbol or a string (package name).
; Pair is the (section-symbol . citations) pair parsed from the doc
; string, or nil if doc is unformatted.  If pair is non-nil we add a
; new entry to the documentation data base.  Each entry has the form
; (name section-symbol cites doc), where cites is the list of all x
; such that (:cite x) occurs citations.  Entries are ordered
; alphabetically by name.  In addition, add name to the cites list of
; every x such that (:cited-by x) occurs in citations.

  (cond (pair
         (global-set 'documentation-alist
                     (put-cited-bys
                      name
                      (cons (cons :cited-by (car pair)) (cdr pair))
                      (update-alpha-<-alist
                       name
                       (list (car pair)
                             (get-cites (cdr pair))
                             doc)
                       (global-val 'documentation-alist wrld)))
                     wrld))
        (t wrld)))

(defun update-doc-data-base-lst (names docs pairs wrld)
  (cond ((null names) wrld)
        (t (update-doc-data-base-lst
            (cdr names)
            (cdr docs)
            (cdr pairs)
            (update-doc-data-base (car names) (car docs) (car pairs) wrld)))))

(defun putprop-unless (sym key val exception wrld)

; We do (putprop sym key val wrld) unless val is exception, in
; which case we do nothing.  We return the possibly modified wrld.

  (cond ((equal val exception) wrld)
        (t (putprop sym key val wrld))))

(defun redefined-warning (redef ctx state)

; Redef is either nil, a true-list of symbols, a single symbol, or a
; single string.  In the latter two cases we think of redef denoting a
; singleton list.  If the list denoted by redef is non-nil we print a
; warning that every name in that list has been redefined.

  (if redef
      (warning$ ctx "Redef"
               "~&0 redefined.~%~%"
               (if (atom redef) (list redef) redef))
      state))

(defun get-event (name wrld)

; This function has undefined behavior when name was not introduced by an ACL2
; event.

  (access-event-tuple-form
   (cddr
    (car
     (lookup-world-index 'event
                         (getprop name 'absolute-event-number 0
                                  'current-acl2-world wrld)
                         wrld)))))

(defun redundant-labelp (name event-form wrld)

; The only time a label is considered redundant is during the second pass of
; initialization and only then if it was already defined with the same
; event-form.

  (and (global-val 'boot-strap-pass-2 wrld)
       (getprop name 'label nil 'current-acl2-world wrld)
       (equal event-form (get-event name wrld))))

(defun deflabel-fn (name state doc event-form)

; Warning: If this event ever generates proof obligations, remove it from the
; list of exceptions in install-event just below its "Comment on irrelevance of
; skip-proofs".

  (with-ctx-summarized
   (if (output-in-infixp state) event-form (cons 'deflabel name))
   (let ((wrld1 (w state))
         (event-form (or event-form
                         (list* 'deflabel name
                                (if doc
                                    (list :doc doc)
                                  nil)))))
     (cond
      ((redundant-labelp name event-form wrld1)
       (stop-redundant-event ctx state))
      (t
       (er-progn
        (chk-all-but-new-name name ctx 'label wrld1 state)
        (er-let*
         ((wrld2 (chk-just-new-name name 'label nil ctx wrld1 state))
          (doc-pair (translate-doc name doc ctx state)))
         (let ((wrld3 (update-doc-data-base
                       name doc doc-pair
                       (putprop name 'label t wrld2))))

; The only reason we store the 'label property is so that name-introduced
; recognizes this name.

; Note:  We do not permit DEFLABEL to be made redundant.  If this
; is changed, change the text of the :DOC for redundant-events.

           (install-event name
                          event-form
                          'deflabel
                          name
                          nil
                          nil
                          nil
                          nil
                          wrld3
                          state)))))))))

; That completes the development of deflabel.  But now there is the
; considerable task of printing out documentation strings and help
; info based on the documentation data base.  First, let us get
; defdoc out of the way.

(defun defdoc-fn (name state doc event-form)

; Warning: If this event ever generates proof obligations, remove it from the
; list of exceptions in install-event just below its "Comment on irrelevance of
; skip-proofs".

  (with-ctx-summarized
   (if (output-in-infixp state) event-form (cons 'defdoc name))
   (let ((wrld1 (w state))
         (event-form (or event-form
                         (list* 'defdoc name doc))))
     (er-progn
      (if (or (and (symbolp name) name) (stringp name))
          (value nil)
        (er soft ctx
            "Names to be documented must be strings or non-nil symbols and ~x0 ~
             is not."
            name))
      (cond
       ((global-val 'boot-strap-pass-2 (w state))

; When the documentation for topic BDD was moved to axioms.lisp, we had the
; following problem:  evaluation of (defdoc bdd ...) in the second pass of
; boot-strap was setting the "cites" (subtopics) field to nil.  So, now we skip
; defdoc events on the second pass of the boot-strap.

        (value :skipped))
       (t
        (er-let*
         ((doc-pair (translate-doc name doc ctx state)))
         (cond
          (doc-pair
           (let ((wrld2 (update-doc-data-base
                         name doc doc-pair wrld1)))
             (install-event name
                            event-form
                            'defdoc
                            0
                            nil
                            nil
                            nil
                            nil
                            wrld2
                            state)))
          (t (er soft ctx
                 "The doc string supplied for ~x0 is not a valid ACL2 ~
                  documentation string.  See :DOC doc-string."
                 name))))))))))

#+acl2-loop-only
(defmacro defdoc (&whole event-form name doc) ;See note

; Warning: See the Important Boot-Strapping Invariants before modifying!

; Warning: If this event ever generates proof obligations, remove it from the
; list of exceptions in install-event just below its "Comment on irrelevance of
; skip-proofs".

  ":Doc-Section Events

  add a ~il[documentation] topic~/
  ~bv[]
  Examples:
  (defdoc interp-section
     \":Doc-Section ...\")~/

  General Form:
  (defdoc name doc-string)
  ~ev[]
  where ~c[name] is a symbol or string to be documented and
  ~ilc[doc-string] is a ~il[documentation] string (~pl[doc-string]).  This
  event adds the ~il[documentation] string for symbol ~c[name] to the
  ~c[:]~ilc[doc] data base.  It may also be used to change the ~il[documentation]
  for ~c[name] if ~c[name] already has ~il[documentation].  The difference
  between this event and ~ilc[deflabel] is that, unlike ~ilc[deflabel] (but
  like ~ilc[table]), it does not mark the current ~il[history] with the
  ~c[name].  But like ~ilc[deflabel], ~c[defdoc] ~il[events] are never
  considered redundant (~pl[redundant-events]).

  ~l[deflabel] for a means of attaching a ~il[documentation] string to
  a name that marks the current ~il[history] with that name.  We now
  elaborate further on how ~c[defdoc] may be useful in place of ~ilc[deflabel].

  It is usually sufficient to use ~ilc[deflabel] when you might be tempted
  to use ~c[defdoc].  However, unlike ~ilc[deflabel], ~c[defdoc] does not mark
  the current ~il[history] with ~c[name].  Thus, ~c[defdoc] is useful for
  introducing the ~il[documentation] for a ~ilc[defun] or ~ilc[deftheory] event,
  for example, several ~il[events] before the function or theory is
  actually defined.

  For example, suppose you want to define a theory (using ~ilc[deftheory]).
  You need to prove the lemmas in that theory before executing the
  ~ilc[deftheory] event.  However, it is quite natural to define a
  ~c[:doc-section] (~pl[doc-string]) whose name is the name of the
  theory to be defined, and put the ~il[documentation] for that theory's
  lemmas into that ~c[:doc-section].  ~c[Defdoc] is ideal for this purpose,
  since it can be used to introduce the ~c[:doc-section], followed by the
  lemmas referring to that ~c[:doc-section], and finally concluded with a
  ~ilc[deftheory] event of the same name.  If ~ilc[deflabel] were used
  instead of ~c[defdoc], for example, then the ~ilc[deftheory] event would
  be disallowed because the name is already in use by the ~ilc[deflabel]
  event.

  We also imagine that some users will want to use ~c[defdoc] to insert
  the ~il[documentation] for a function under development.  This ~c[defdoc]
  event would be followed by definitions of all the subroutines of
  that function, followed in turn by the function definition itself.

  Any time ~c[defdoc] is used to attach ~il[documentation] to an
  already-documented name, the name must not be attached to a new
  ~c[:doc-section].  We make this requirement as a way of avoiding
  loops in the ~il[documentation] tree.  When ~il[documentation] is redefined, a
  warning will be printed to the terminal.~/"

; Warning: See the Important Boot-Strapping Invariants before modifying!

  (list 'defdoc-fn
        (list 'quote name)
        'state
        (list 'quote doc)
        (list 'quote event-form)))

(defun access-doc-string-data-base (name state) 

; Name is a symbol or a string.  This function would be just
; (assoc-equal name documentation-alist) but for one twist: if name is
; a symbol and not in the data base, we try acl2::name instead.  We
; return (name section-symbol cites doc), or nil if there is no entry
; for either name.  The reason we go to ACL2::name after name fails is
; that:

; MY-PKG !>:doc defthm

; will read as MY-PKG::DEFTHM and we assume that most of the time
; the documentation topics the user is interested in are ours.

  (cond
   ((symbolp name)
    (let ((doc-tuple
           (assoc-equal name
                        (global-val 'documentation-alist (w state)))))
      (cond (doc-tuple doc-tuple)
            ((not (equal (symbol-package-name name)
                         "ACL2"))
             (assoc-equal
              (intern-in-package-of-symbol
               (symbol-name name)
               'get-doc-string)
              (global-val 'documentation-alist (w state))))
            (t nil))))
   ((stringp name)
    (assoc-equal name
                 (global-val 'documentation-alist (w state))))
   (t nil)))

(defun get-doc-string (name state)

; This function is provided simply to let the user see what
; doc strings really look like.

  (cadddr (access-doc-string-data-base name state)))

(defun get-doc-string-de-indent1 (str i)
  (cond ((eql (char str i) #\Newline) 0)
        (t (1+ (get-doc-string-de-indent1 str (1- i))))))

(defun get-doc-string-de-indent (str)

; The text in a doc string is assumed to be indented some to
; avoid screwing up the Emacs formatting commands and to make their
; appearance in source files more pleasant.  We de-indent them as we
; print, stripping off a fixed number of #\Spaces after every newline,
; when possible.  We compute the de-indent number by looking at the
; indentation of the one-liner part.

  (get-doc-string-de-indent1 str
                             (1- (scan-to-doc-string-part 0 str))))

(defun use-doc-string-de-indent (d str i maximum)

; If there are d spaces in str starting at i, return i+d; else nil.

  (cond ((= d 0) i)
        ((< i maximum)
         (cond ((eql (char str i) #\Space)
                (use-doc-string-de-indent (1- d) str (1+ i) maximum))
               (t nil)))
        (t nil)))

(defun doc-prefix (state)
  (if (f-boundp-global 'doc-prefix state)
      (f-get-global 'doc-prefix state)
      "| "))

(defun princ-prefix (prefix channel state)
  (cond ((consp prefix)
         (pprogn (princ$ (car prefix) channel state)
                 (spaces (cdr prefix) (length (car prefix)) channel state)))
        (t (princ$ prefix channel state))))

(defun length-prefix (prefix)
  (cond ((consp prefix) (+ (length (car prefix)) (cdr prefix)))
        (t (length prefix))))

(defun save-more-doc-state (str i maximum de-indent prefix state)
  (cond ((or (>= i maximum)
         (and (int= (+ i 2) maximum)
              (eql (char str i) #\~) (eql (char str (1+ i)) #\/)))
         (f-put-global 'more-doc-state nil state))
        (t (f-put-global 'more-doc-state
                         (list str i maximum de-indent prefix)
                         state))))

(defun doc-char-subst-table-p (x)

; See comment in terminal-markup-table.

  (cond
   ((consp x)
    (and (consp (car x))
         (not (eql (caar x) #\~))
         (not (eql (caar x) #\Newline))
         (character-listp (car x))
         (doc-char-subst-table-p (cdr x))))
   (t (null x))))

(defun set-doc-char-subst-table (x state)
  (if (doc-char-subst-table-p x)
      (pprogn (f-put-global 'doc-char-subst-table x state)
              (value :invisible))
    (er soft 'set-doc-char-subst-table
        "The character substitution table must be an alistp whose keys are ~
         all characters other than ~~ and values are all strings.  The object ~
         ~x0 does not have this property."
        x)))

(defun doc-char-subst-table (state)

; See comment in terminal-markup-table.

  (f-get-global 'doc-char-subst-table state))

(defun doc-fmt-alist (state)
  (f-get-global 'doc-fmt-alist state))

(defconst *terminal-markup-table*

; Examples of links are as follows.

; ~L (ordinary link)
; ~L[arg] prints ``See :DOC arg'' to the terminal, and something
;     analogous in other settings (but possibly with a link established,
;     or in the case of printed text, with a reference to a page number
;     and a section).
; Example:  ~l[program] for how to do rapid prototyping.
; -- Prints to the terminal as
;     See :DOC program for how to do rapid prototyping.
; -- A printed version might look more like:
;     See :DOC program, Section 1.3, page 92 for how to do rapid prototyping.
; -- Could print to emacs info as something like:
;     *See program:: for how to do rapid prototyping.

; ~PL (parenthetical link)
; ~pl[arg] prints ``see :DOC arg'' (just like ~l, but with lower-case ``see'')
;      to the terminal; as with ~l, it may establish a link in other settings.
;      The name ``parenthetical'' is taken from texinfo, which claims to
;      require that, unlike the other kind of link, commas and periods may not
;      appear immediately afterwards.  For now, we ignore this issue,
;      considering that ~pl is distinguished from ~l mainly by the case of
;      ``see''.

; ~IL (invisible link):  use the word normally and do not draw any special
;                        attention to the fact that it is a link.
; ~IL[arg] prints ``arg''

; The following association list maps each such directive (as a
; case-insensitive string) to a flag and fmt message, i.e., to a string
; followed by an association list appropriate for that string.  The flag
; determines whether the first part of arg is to be read as a symbol as when it
; represents the name of a link.  When flag=t, we split the arg into two parts,
; the symbol and the text.  A flag of t is used on those keys which translate
; into HREF links in HTML so that the first of the two args is treated as the
; doc topic identifying the link and the rest is treated as the mouse-sensitive
; button text highlighted by HTML.  (Note that even in the terminal and tex
; markup tables we must use flag t on those keys so that those commands get
; only the first doc topic part of the arg.)  The string corresponding to key
; will ultimately be printed in place of the ~key[arg] expression, except that
; the corresponding alist will first be extended by mapping #\a to the (first
; part of the) string arg, and mapping #\A to the upper-casing of that string,
; and #\t to the second part of the string arg (provided flag=t).  Note also
; that the (doc-char-subst-table state) is used to control the substitution of
; sequences of characters for single characters, both in the arg portion of
; ~key[arg] and in characters not part of such expressions, but *not* in the
; key.  To escape a character from substitution by that table, precede it by a
; ~.

; Finally, note that in ~key[arg] we do not allow newline characters.  That is
; because they will not get printed appropriately to the terminal.  Thus, ~c
; may have to be used more than we'd like.  If we really want to include a
; newline for some reason, it should be escaped with ~.

  `(("-"   nil . "--")
    ("B"   nil . "~st")   ;bold font
    ("BF"  nil . "")      ;begin format --
                         ; -- like verbatim, but if possible don't change font
    ("BID" nil . "")      ;begin implementation dependent
    ("BQ"  nil . "")      ;begin quotation
    ("BV"  nil . "")      ;begin verbatim
    ("C"   nil . "~st")   ;code, often preferred even if we have invisible link
    ("EF"  nil . "")      ;end format
    ("EID" nil . "")      ;end implementation dependent
    ("EM"  nil . "~st")   ;emphasis (presumably italics if fonts are available)
    ("EQ"  nil . "")      ;end quotation
    ("EV"  nil . "")      ;end verbatim
    ("GIF" nil . "")      ;gif file (currently only for HTML)
;   ("GIF" nil . "gif file ~st omitted")   ;alternate possibility for ~gif
    ("I"   nil . "~st")   ;italics font
    ("ID"  nil . "")       ;implementation dependent
    ("IL"  t   . "~st")   ;invisible link, for true hypertext environments
    ("ILC" t   . "~st")   ;invisible link, but use code if such links don't show
    ("L"   t   . "See :DOC ~ss") ;link at beginning of sentence
    ("NL"  nil . "~%")    ;newline
    ("PAR" nil . "")      ;paragraph mark, of no significance at the terminal
    ("PL"  t   . "see :DOC ~ss");parenthetical link, i.e., link
;                                  not at beginning of sentence
    ("SC"  nil . "~sT")   ;(small, if possible) caps
    ("ST"  nil . "~sT")   ;strong emphasis (presumably bold if fonts are available)
    ("T"   nil . "~st")   ;typewriter font
    ("TERMINAL" nil . "~st") ;terminal only; otherwise argument is ignored
    ("WARN" nil . "<>")
    ("CLICK-HERE" t . "See :DOC ~ss")
    ("PCLICK-HERE" t . "see :DOC ~ss")
    ("FLY" t . "Flying Tour: see :DOC ~ss")
    ("WALK" t . "Walking Tour: see :DOC ~ss")
    ("LARGE-WALK" t . "Walking Tour: see :DOC ~ss")
    ("URL"  nil . "~st")   ;print as HTML hyperlink (when possible)
    )

  ":Doc-Section Documentation

  a ~il[markup] table used for printing to the terminal~/

  The value of the ACL2 constant ~c[*terminal-markup-table*] is an association
  list pairing ~il[markup] keys with strings, to be used for printing to the
  terminal.  ~l[markup] for a description of the ACL2 ~il[markup] language.~/

  The entries in ~c[*terminal-markup-table*] are of the form
  ~bv[]
  (key flag . fmt-string)
  ~ev[]
  where ~c[key] is one of the ~il[doc-string] tilde directives (~pl[markup]),
  ~c[flag] is a Boolean as described below, and ~c[fmt-string] is a string as
  expected by the ACL2 printing function ~ilc[fmt].  The system arranges that
  for any ~c[arg], when an expression ~~key[arg] is encountered by the
  ~il[documentation] printer, ~ilc[fmt] will print ~c[fmt-string] in an
  association list, binding keys based on ~c[arg] as follows.
  ~bv[]
  #\\p ~-[] the `pointer'     ; only used if flag is t
  #\\s ~-[] the print name version of the pointer, e.g., |abc| or ABC
  #\\c ~-[] the parent file   ; only used if flag is t
  #\\t ~-[] the displayed text
  #\\T ~-[] uppercased displayed text
  ~ev[]
  The first three entries are used only when the ~c[flag] associated with
  ~c[key] is ~c[t], indicating that the argument ~c[arg] of ~c[~~key] is to be
  parsed as starting with a symbol; for example, ~c[~~key[foo bar~]] will bind
  ~c[#\\\p] to the symbol ~c[FOO].

  The discussion of the above association list for printing ~c[fmt-string]
  applies when printing ~il[documentation] to other than the terminal as well.
  Such tools exist for Texinfo and for HTML; see files
  ~c[doc/write-acl2-html.lisp] and ~c[doc/write-acl2-texinfo.lisp] distributed
  with ACL2.")

(defun doc-markup-table (state)
  (or (and (f-boundp-global 'doc-markup-table state)
           (f-get-global 'doc-markup-table state))
      *terminal-markup-table*))

(defun doc-scan-past-tilde-key (name orig-position posn str maximum acc state)

; Posn is the position just after the first opening bracket ([) that is at or
; after position posn in the string str, and acc accumulates the characters
; found in the interim.  The function returns (mv erp posn key state), where
; key is built from the accumulated characters so that we can view the string
; from the original position as "key[".  Note that we deliberately do *not* use
; a char-subst-table here; key is taken literally.

  (cond
   ((not (< posn maximum))
    (mv-let (erp val state)
            (er soft "printing documentation string"
                "In the process of processing the tilde (~~) directive at ~
                 position ~x0 in the documentation string for ~x1, ~
                 no opening bracket ([) was found between that tilde ~
                 and before the end of the string."
                orig-position name)
            (declare (ignore erp val))
            (mv t nil nil state)))
   (t
    (let ((ch (char str posn)))
      (cond
       ((eql ch #\[)
        (mv nil (1+ posn) (coerce (reverse acc) 'string) state))
       (t (doc-scan-past-tilde-key
           name orig-position (1+ posn) str maximum (cons ch acc) state)))))))

(defun doc-scan-past-tilde-arg
  (name orig-position posn str maximum acc state)

; Posn is the position just after the first non-escaped closing bracket (]) at
; or after position posn in the string str, and acc accumulates the characters
; found in the interim.  The function returns (mv erp posn arg state), where
; arg is built from the accumulated characters so that we can view the string
; from the original position as "arg]".

  (cond
   ((not (< posn maximum))
    (mv-let (erp val state)
            (er soft "printing documentation string"
                "In the process of processing the tilde (~~) directive whose ~
                 argument begins at position ~x0 in the documentation string ~
                 for ~x1, no closing bracket (]) was found corresponding to ~
                 the preceding opening bracket."
                orig-position name)
            (declare (ignore erp val))
            (mv t nil nil state)))
   (t
    (let ((ch (char str posn)))
      (cond
       ((eql ch #\])
        (mv nil (1+ posn) (coerce (reverse acc) 'string) state))
       ((eql ch #\Newline)

; Why do we have this annoying newline check, which so often bites us when
; writing out the :doc for html or texinfo?  A quick answer is that a newline
; could indicate that we are missing a closing bracket in ~key[...], and
; perhaps that's a sufficient answer.  But another answer is that otherwise,
; our printing to the terminal is ugly.  Without this check we get the
; following after:

;   (defdoc foo
;     ":Doc-Section Miscellaneous
;   
;     my one-liner~/
;   
;     Here we insert a linebreak: ~c[(fn
;     arg)].~/~/")

; Notice the missing `|' at the beginning of a line.

;   ACL2 !>:doc! foo
;   | FOO          my one-liner
;   | 
;   | Here we insert a linebreak: (fn
;     arg).
;   | 
;   *-
;   ACL2 !>

        (mv-let (erp val state)
                (er soft "printing documentation string"
                    "In the process of processing the tilde (~~) directive ~
                     whose argument begins at position ~x0 in the ~
                     documentation string for ~x1, a newline was encountered.  ~
                     This is illegal.  Consider breaking this tilde directive ~
                     into several separate ones, each occurring on its own ~
                     line."
                    orig-position name)
                (declare (ignore erp val))
                (mv t nil nil state)))
       ((and (eql ch #\~)
             (< (1+ posn) maximum))
        (doc-scan-past-tilde-arg name orig-position (+ 2 posn) str maximum
                                 (cons (char str (1+ posn)) acc) state))
       (t (doc-scan-past-tilde-arg name orig-position (1+ posn) str maximum
                                   (cons ch acc)
                                   state)))))))

(defun doc-scan-past-tilde
  (name posn str maximum markup-table state)

; Posn is the position of the first character after a tilde in str,
; in the following sense:
;   ....~key[arg]....
;        ^
; We return (mv erp posn entry arg state), where
;
; erp = nil iff the `parse' succeeds;
; posn = new position, after the closing right bracket (]);
; entry = the entry in markup-table associated with k (which is non-empty if
;         erp is nil);
; arg = the string enclosed in brackets after the key, as shown above.

  (mv-let (erp posn key state)
          (doc-scan-past-tilde-key name posn posn str maximum nil state)
          (cond
           (erp (mv erp nil nil nil state))
           (t (let ((entry (assoc-string-equal key markup-table)))
                (cond ((null entry)
                       (mv-let (erp val state)
                               (er soft "printing documentation string"
                                   "~|Failed to find key ~x0 in current ~
                                    markup table,~|~%  ~x1,~|~%when printing ~
                                    documentation for ~x2.~|"
                                   key markup-table name)
                               (declare (ignore erp val))
                               (mv t nil nil nil state)))
                      (t
                       (mv-let (erp posn arg state)
                               (doc-scan-past-tilde-arg name
                                                        posn posn str maximum
                                                        nil state)
                               (cond
                                (erp (mv erp nil nil nil state))
                                (t (mv nil posn entry arg state)))))))))))

(defun assoc-char-alist-stringp (char-alist str len)

; Warning:  Just like member-char-stringp, len must be strictly less than the
; length of string!

  (cond
   ((null char-alist) nil)
   (t (or (member-char-stringp (caar char-alist) str len)
          (assoc-char-alist-stringp (cdr char-alist) str len)))))

(defun apply-char-subst-table1 (char-lst acc char-subst-table)

; Consider the result of replacing each character in char-lst with its value in
; char-subst-table when it is bound there, else leaving it unchanged, and then
; appending the result to the front of the list acc of characters.  A symbol is
; then returned with that name that resides in the package of orig-symbol if
; orig-symbol is non-nil; otherwise, the string is returned.

  (cond
   ((null char-lst)
    (coerce (reverse acc) 'string))
   (t
    (let ((temp (assoc (car char-lst) char-subst-table)))
      (cond
       (temp
        (apply-char-subst-table1 (cdr char-lst) (revappend (cdr temp) acc)
                                 char-subst-table))
       (t (apply-char-subst-table1 (cdr char-lst)
                                   (cons (car char-lst) acc)
                                   char-subst-table)))))))

(defun apply-char-subst-table (s char-subst-table spack)

; Consider the result of replacing each character in char-lst with its value in
; char-subst-table when it is bound there, else leaving it unchanged, and then
; appending the result to the front of the list acc of characters.  A symbol is
; then returned with that name that resides in the package of orig-symbol if
; orig-symbol is non-nil; otherwise, the string is returned.

  (cond
   ((symbolp s)
    (let ((n (symbol-name s)))
      (cond
       ((assoc-char-alist-stringp char-subst-table n (1- (length n)))
        (intern-in-package-of-symbol
         (apply-char-subst-table1 (coerce n 'list) nil char-subst-table)
         spack))
       (t s))))
   ((stringp s)
    (cond
     ((assoc-char-alist-stringp char-subst-table s (1- (length s)))
      (apply-char-subst-table1 (coerce s 'list) nil char-subst-table))
     (t s)))
   (t (er hard 'apply-char-subst-table
          "Attempted to apply character substitution table to non-symbol, ~
           non-string:  ~x0"
          s))))

(defun read-pointer-and-text1 (lst pacc sacc)
  (cond ((null lst)
         (mv (er hard 'read-pointer-and-text
                 "Unbalanced vertical bars, ~x0"
                 (coerce (reverse sacc) 'string))
             nil
             nil))
        ((eql (car lst) #\|)
         (cond ((cdr lst)
                (cond ((eql (cadr lst) #\Space)
                       (mv (coerce (reverse pacc) 'string)
                           (coerce (reverse (cons #\| sacc)) 'string)
                           (coerce (cddr lst) 'string)))
                      (t (mv (coerce (reverse pacc) 'string)
                             (coerce (reverse (cons #\| sacc)) 'string)
                             (coerce (cdr lst) 'string)))))
               (t (let ((temp (coerce (reverse pacc) 'string)))
                    (mv temp
                        (coerce (reverse (cons #\| sacc)) 'string)
                        temp)))))
        (t (read-pointer-and-text1 (cdr lst)
                                   (cons (car lst) pacc)
                                   (cons (car lst) sacc)))))

(defun read-pointer-and-text2 (lst acc)
  (cond ((eql (car lst) #\Space)
         (let ((temp (coerce (reverse acc) 'string)))
           (mv temp
               temp
               (coerce (cdr lst) 'string))))
        (t (read-pointer-and-text2 (cdr lst)
                                   (cons (char-upcase (car lst)) acc)))))

(defun read-pointer-and-text-raw (str)

; See the comment in lookup-fmt-alist, especially the table showing
; how we ``read'' a symbol from str.

  (cond
   ((eql (char str 0) #\|)
    (read-pointer-and-text1 (cdr (coerce str 'list)) nil '(#\|)))
   ((string-search '(#\Space) str nil)
    (read-pointer-and-text2 (coerce str 'list) nil))
   (t (let ((temp (string-upcase str)))
        (mv temp temp str)))))

(defun posn-char-stringp (chr str i)
  (cond ((zp i)
         (if (eql chr (char str i))
             0
           nil))
        ((eql chr (char str i))
         i)
        (t
         (posn-char-stringp chr str (1- i)))))

(defun replace-colons (p)
  (let ((posn (posn-char-stringp #\: p (1- (length p)))))
    (if (or (null posn)
            (eql posn 0))
        p
      (concatenate 'string
                   (subseq p 0
                           (if (eql (char p (1- posn)) #\:)
                               (1- posn)
                             posn))
                   "||"
                   (subseq p (1+ posn) (length p))))))

(defun read-pointer-and-text (str bar-sep-p)
  (if bar-sep-p
      (mv-let
       (p s text)
       (read-pointer-and-text-raw str)
       (mv (replace-colons p) (replace-colons s) text))
    (read-pointer-and-text-raw str)))

(defun lookup-fmt-alist (str flag fmt-alist char-subst-table bar-sep-p)

; Warning: Keep this in sync with missing-fmt-alist-chars.

; Consider a tilde-directive ~?[str].  From str we create a fmt alist that is
; used while we print the string associated with ? in the markup table.  This
; function creates that fmt alist from str and the flag which indicates whether
; the first part of str is to be read as a symbol, as in ~il[defun Definition],
; or not as in ~c[this Definition].

; What are the symbols in the fmt alist we need?  To find the answer, look in
; the markup table and collect all the fmt vars used.  They are:

; #\p -- the "pointer"     ; only used if flag is t
; #\s -- the print name version of the pointer, e.g., |abc| or ABC
; #\c -- the parent file   ; only used if flag is t
; #\t -- the displayed text
; #\T -- uppercased displayed text
; #\w -- the html anchor for the warning message ; only used on ~WARN[]

; The entries marked "only used if flag is t" are not necessarily used if flag
; is t.  For example, the entries in *terminal-markup-table* do not refer to
; #\c, since terminal documentation has no reason to refer to a "parent file".

; If flag is nil, then we bind just the last three.  In this case, the
; displayed text is all of str.

; If flag is t, then we first ``read'' a symbol from str, effectively splitting
; str into two parts, sym and text.  The split is indicated below.  Note that
; sym is a string, not really a symbol.  The "pointer" is the symbol-name of
; sym.  The "print name of the pointer" is the symbol-name of sym possibly
; surrounded by vertical bars.

;    str             #\p    #\s     #\t

; ~?[abc]           "ABC"  "ABC"    "abc"
; ~?[abc ]          "ABC"  "ABC"    ""
; ~?[abc def ghi]   "ABC"  "ABC"    "def ghi"
; ~?[|abc|]         "abc"  "|abc|"  "abc"
; ~?[|abc| ]        "abc"  "|abc|"  ""
; ~?[|abc| def ghi] "abc"  "|abc|"  "def ghi"
; ~?[|abc|def ghi]  "abc"  "|abc|"  "def ghi"

; Parameter bar-sep-p says that symbols with :: in them, but not starting with
; :, are to be converted to strings with || in place of the colons.

; To find #\c we lookup sym in the fmt-alist provided.  Then we bind #\p to sym
; and process text as in the flag=nil case.

  (cond
   ((null flag)
    (cond ((equal str "")

; We don't know that we are in the ~warn[] case so we might need #\t and #\T in
; the alist.  We add them.

           (list* (cons #\t "")
                  (cons #\T "")
                  (cdr (assoc-string-equal "" fmt-alist))))
          (t (list (cons #\t (apply-char-subst-table str
                                                     char-subst-table
                                                     nil))
                   (cons #\T (apply-char-subst-table (string-upcase str)
                                                     char-subst-table
                                                     nil))))))
   (t (mv-let
       (p s text)
       (read-pointer-and-text str bar-sep-p)
       (let ((alist0
              (list* (cons #\t (apply-char-subst-table text
                                                       char-subst-table
                                                       nil))
                     (cons #\T (apply-char-subst-table (string-upcase text)
                                                       char-subst-table
                                                       nil))

; Note that it is NOT necessarily an error if the assoc-string-equal returns
; nil in the next line.  This may be the case for forms of documentation where
; extra fmt-alist information is not required.  For example, terminal
; documentation doesn't require the #\c "parent file" information that HTML
; documentation does, so for "links" produced by markup like ~il[x] and ~ilc[x]
; there may still be no fmt-alist entry for x.

                     (cdr (assoc-string-equal p fmt-alist)))))
         (if (assoc #\p alist0)
             alist0
           (list* (cons #\p (apply-char-subst-table p char-subst-table nil))
                  (cons #\s (apply-char-subst-table s char-subst-table nil))
                  alist0)))))))

(defun bar-sep-p (state)
  (and (f-boundp-global 'bar-sep-p state)
       (f-get-global 'bar-sep-p state)))

(defun missing-fmt-alist-chars1 (str char-to-tilde-s-string-alist fmt-alist)

; See documentation for missing-fmt-alist-chars.

  (cond ((endp char-to-tilde-s-string-alist)
         nil)
        (t
         (let ((fmt-char  (caar char-to-tilde-s-string-alist))
               (tilde-str (cdar char-to-tilde-s-string-alist))
               (rest
                (missing-fmt-alist-chars1 str
                                          (cdr char-to-tilde-s-string-alist)
                                          fmt-alist)))
           (cond ((and (not (assoc fmt-char fmt-alist))
                       (search tilde-str str))
                  (cons fmt-char rest))
                 (t rest))))))

(defun missing-fmt-alist-chars (str fmt-alist)

; Warning: Keep the characters bound below with the documentation for
; lookup-fmt-alist.  (NOTE: As of Oct. 2009 I do not really understand why
; other than #\p and #\c should get any attention here.  Note that #\c and #\p
; are used for links in doc/write-acl2-html.lisp and
; doc/write-acl2-texinfo.lisp, respectively.)

; Return a list of characters C for which the given fmt-alist is incomplete for
; the fmt string, str, in the sense that (1) C is one of the characters listed
; below, (2) str contains the substring "~sC", and (3) C is not bound in
; fmt-alist.  By calling this function, we can cause a nice error if such a
; character C is found, or even avoid an error by pointing to a special
; "undocumented" topic.

  (missing-fmt-alist-chars1 str
                            '((#\p . "~sp")
                              (#\s . "~ss")
                              (#\c . "~sc")
                              (#\t . "~st")
                              (#\T . "~sT")
                              (#\w . "~sw"))
                            fmt-alist))

(defun complete-fmt-alist (topic-name fmt-alist undocumented-file
                                      char-subst-table)

; Warning: Keep this in sync with the comment about complete-fmt-alist in
; print-doc-string-part1.

; Return an extension of fmt-alist so that ~sc will refer to an undocumented
; topic if #\c is not already bound in fmt-alist (thus supporting the use of
; ~sc by doc/write-acl2-html.lisp at least through Oct. 2009), and similarly
; for ~sp and #\p (thus supporting the use of ~sp by
; doc/write-acl2-texinfo.lisp at least through Oct. 2009).  Some day we may
; want to complete with other characters as well.

  (let* ((c-missing-p (not (assoc #\c fmt-alist)))
         (p-missing-p (not (assoc #\p fmt-alist)))
         (fmt-alist
          (cond (c-missing-p (acons #\c undocumented-file fmt-alist))
                (t fmt-alist)))
         (fmt-alist
          (cond (p-missing-p (acons #\p
                                    (apply-char-subst-table topic-name
                                                            char-subst-table
                                                            nil)
                                    fmt-alist))
                (t fmt-alist))))
    fmt-alist))

(defmacro mv-to-state (n form)

; Form should evaluate to an mv of two or more values, all non-stobjs except
; the, which should be state.  We return that state, discarding the other
; values.

  (declare (xargs :guard (and (integerp n)
                              (< 1 n))))
  (let ((vars (make-var-lst 'x (1- n))))
    `(mv-let (,@vars state)
             ,form
             (declare (ignore ,@vars))
             state)))

(defun print-par-entry (entry fmt-alist char-subst-table channel state)
  (mv-to-state
   2
   (fmt1 (cddr entry)
         (lookup-fmt-alist "" nil fmt-alist char-subst-table
                           (bar-sep-p state))
         0 channel state nil)))

(defun print-doc-string-part1 (str i maximum de-indent prefix
                                   markup-table char-subst-table
                                   fmt-alist channel name state ln
                                   undocumented-file vp)

; Parameter ln is a bit complicated, so we describe it in some detail.

; First suppose that ln is a number, in which case it is the number of lines
; printed so far.  In this case, we do :more processing until we hit the line
; maximum (at which point we save the more-doc-state to continue) or the
; tilde-slash (at which point we set the more-doc-state to nil).

; When ln is nil, we do not bother to track the number of lines printed and we
; print them all up to the tilde-slash, but we then initialize the
; more-doc-state.  The nil setting should be used when you are printing out
; parts 0 or 1 of the doc string.

; When ln is t we behave as for nil, except that we set the more-doc-state to
; nil (as we would for numeric ln) when we hit the tilde-slash.  This setting
; is used when we want to dump the entire part 2.

; When ln is :par, then two consecutive newlines, together with all consecutive
; whitespace characters following them, are handled by printing using the entry
; for EPAR in markup-table, if there is one; else, by using the entry for PAR
; if there is one; else, without such special paragraph treatment.  In the case
; that EPAR's entry is used, then if there are any remaining characters after
; the block of newlines, the entry for BPAR is then printed.

; The final legal value of ln is :par-off, whose purpose is to avoid printing
; paragraph markers when inside certain preformatted (verbatim) environments,
; typically ~bv/~ev and ~bf/~ev for printing to html and the like (but not the
; terminal or texinfo).  Thus, :par-off is treated like :par except that there
; is no special treatment in the case of consecutive newlines.  Thus :par-off
; is really treated lke t, except that ln becomes :par in recursive calls when
; the end of a preformatted environment is encountered.  The argument vp
; (verbatim pair) never changes, and is nil when ln is not :par or :par-off.
; But vp is a pair (begin-markers . end-markers), for example, (("BV" "BF")
; . ("EV" "EF")), where begin-markers tell us to change ln from :par to
; :par-off and end-markers tell us to change ln from :par-off to :par.

; A precondition for this function is that if ln is :par or :par-off and if
; "EPAR" is bound in markup-table (and hence so is "BPAR"), then the
; begin-paragraph marker (as per "BPAR") has already been printed and the
; end-paragraph marker (as per "EPAR") will be printed.  Informatlly, then, it
; is an invariant of this function that at every call in the case that ln is
; :par or :par-off, an end-paragraph marker is pending.

  (cond ((< i maximum)
         (let ((c (char str i)))
           (cond
            ((eql c #\~)
             (cond
              ((< (1+ i) maximum)
               (let ((c (char str (1+ i))))
                 (cond
                  ((eql c #\/)
                   (pprogn
                    (newline channel state)
                    (save-more-doc-state
                     str
                     (cond ((null ln)
                            (scan-past-whitespace str (+ 2 i) maximum))
                           (t maximum))
                     maximum de-indent prefix state)
                    (mv ln state)))
                  ((eql c #\])

; This directive, ~], in a documentation string is effective only during the
; processing of part 2, the details, and controls how much we show on each
; round of :more processing.  If ln is not a number we are not doing :more
; processing and we act as though the ~] were not present.  Otherwise, we put
; out a newline and save the :more state, positioning the string after the ~]
; (or the newlines following it).

                   (cond ((not (integerp ln))
                          (print-doc-string-part1
                           str (+ 2 i) maximum de-indent prefix markup-table
                           char-subst-table fmt-alist
                           channel name state ln undocumented-file vp))
                         (t (pprogn (newline channel state)
                                    (save-more-doc-state
                                     str
                                     (scan-past-newline str (+ 2 i) maximum)
                                     maximum de-indent prefix state)
                                    (mv ln state)))))
                  ((eq c #\~)
                   (pprogn (princ$ c channel state)
                           (print-doc-string-part1 str (+ 2 i) maximum
                                                   de-indent
                                                   prefix
                                                   markup-table
                                                   char-subst-table
                                                   fmt-alist
                                                   channel name state ln
                                                   undocumented-file vp)))
                  (t
                   (mv-let
                    (erp posn entry arg state)
                    (doc-scan-past-tilde
                     name (1+ i) str maximum markup-table state)
                    (cond
                     (erp (pprogn (save-more-doc-state str maximum maximum
                                                       de-indent prefix
                                                       state)
                                  (mv ln state)))
                     (t (let* ((fmt-alist-for-fmt1
                                (lookup-fmt-alist arg (cadr entry) fmt-alist
                                                  char-subst-table
                                                  (bar-sep-p state))) 
                               (missing-fmt-alist-chars
                                (missing-fmt-alist-chars (cddr entry)
                                                         fmt-alist-for-fmt1))
                               (complete-alist-p
                                (and undocumented-file
                                     missing-fmt-alist-chars))
                               (fmt-alist-for-fmt1
                                (if complete-alist-p
                                    (complete-fmt-alist
                                     name
                                     fmt-alist-for-fmt1
                                     undocumented-file
                                     char-subst-table)
                                  fmt-alist-for-fmt1)))
                          (prog2$
                           (cond
                            ((set-difference-eq missing-fmt-alist-chars

; Keep the list below in sync with complete-fmt-alist.  In this case it is
; irrelevant whether or not undocumented-file is specified (non-nil); we will
; get an error either way.

                                                '(#\c #\p))
                             (er hard 'print-doc-string-part1

; The use of ~| below guarantees reasonable line breaks even if the margins are
; set to very large numbers.

                                 "~|Fatal error printing the :DOC string for ~
                                  topic ~x0,~|due to substring:~|  ~~~s1[~s2]."
                                 name
                                 (string-downcase (car entry))
                                 arg))
                            (missing-fmt-alist-chars
; Jared patch: warn about broken links even if undocumented-file is supplied.
                             (if undocumented-file
                                 (cw "~|; Note: Broken link in :doc ~x0: ~~~s1[~s2].~%"
                                     name (string-downcase (car entry)) arg)
                               (er hard 'print-doc-string-part1
                                   "~|Error printing the :DOC string for topic ~
                                  ~x0,~|due to substring:~|  ~~~s1[~s2].~|If ~
                                  this error is not due to a typo, then it ~
                                  can probably be resolved either by:~|-- ~
                                  adding a :DOC string for ~x2,~|OR~|-- ~
                                  passing an UNDOCUMENTED-FILE argument to ~
                                  the appropriate~|   translator (e.g., ~
                                  function acl2::write-html-file in~|~ ~ ~ ~
                                  distributed file doc/write-html)."
                                   name
                                   (string-downcase (car entry))
                                   arg)))
                            (t nil))
                           (pprogn
                            (cond (missing-fmt-alist-chars
                                   (assert$
                                    undocumented-file ; see error above
                                    (warning$ 'print-doc-string-part1
                                              "Documentation"

; Add a newline just below, since we may be in a context where the margins have
; been made essentially infinite.

                                              "~|Broken link in :doc ~x0: ~
                                               ~~~s1[~s2].~%"
                                              name
                                              (string-downcase (car entry))
                                              arg)))
                                  (t state))
                            (mv-let (col state)
                                    (fmt1 (cddr entry)
                                          fmt-alist-for-fmt1
                                          0 channel state nil)
                                    (declare (ignore col))
                                    (print-doc-string-part1
                                     str posn maximum de-indent prefix
                                     markup-table char-subst-table fmt-alist
                                     channel name state
                                     (cond ((not vp) ln)
                                           ((eq ln :par)
                                            (if (member-string-equal (car entry)
                                                                     (car vp))
                                                :par-off
                                              :par))
                                           ((eq ln :par-off)
                                            (if (member-string-equal (car entry)
                                                                     (cdr vp))
                                                :par
                                              :par-off))
                                           (t ln))
                                     undocumented-file vp))))))))))))
              (t (pprogn (princ$ c channel state)
                         (newline channel state)
                         (save-more-doc-state str (+ 1 i) maximum
                                              de-indent prefix
                                              state)
                         (mv ln state)))))
            ((eql c #\Newline)
             (mv-let
              (epar-p entry)
              (cond
               ((and (eq ln :par)
                     (< (1+ i) maximum)
                     (eql (char str (1+ i)) #\Newline))
                (let ((temp (assoc-string-equal "EPAR" markup-table)))
                  (cond (temp (mv t temp))
                        (t (let ((temp (assoc-string-equal "PAR"
                                                           markup-table)))
                             (mv nil temp))))))
               (t (mv nil nil)))
              (cond
               (entry
                (let ((next-i (scan-past-whitespace str (+ 2 i) maximum)))
                  (cond
                   ((eql next-i maximum)
                    (pprogn (save-more-doc-state str next-i maximum de-indent
                                                 prefix state)
                            (mv ln state)))
                   (t
                    (pprogn
                     (print-par-entry entry fmt-alist char-subst-table
                                      channel state)
                     (cond
                      ((not epar-p) state)
                      (t (let ((entry2
                                (assoc-string-equal "BPAR" markup-table)))
                           (prog2$ (or entry2
                                       (er hard 'print-doc-string-part1
                                           "Found EPAR but not BPAR in ~
                                            markup-table,~|~x0."
                                           markup-table))
                                   (print-par-entry entry2 fmt-alist
                                                    char-subst-table
                                                    channel state)))))
                     (print-doc-string-part1
                      str
                      next-i
                      maximum
                      de-indent
                      prefix
                      markup-table
                      char-subst-table
                      fmt-alist
                      channel name state
                      ln undocumented-file vp))))))
               ((and (integerp ln)
                     (< (1+ i) maximum)
                     (eql (char str (1+ i)) #\Newline)
                     (<= (f-get-global 'more-doc-min-lines state) (+ 2 ln)))
                (pprogn
                 (newline channel state)
                 (newline channel state)
                 (save-more-doc-state str
                                      (or (use-doc-string-de-indent
                                           de-indent
                                           str
                                           (+ 2 i)
                                           maximum)
                                          (+ 2 i))
                                      maximum de-indent prefix
                                      state)
                 (mv ln state)))
               ((and (integerp ln)
                     (<= (f-get-global 'more-doc-max-lines state) (1+ ln)))
                (pprogn
                 (newline channel state)
                 (save-more-doc-state str
                                      (or (use-doc-string-de-indent
                                           de-indent
                                           str
                                           (+ 1 i)
                                           maximum)
                                          (+ 1 i))
                                      maximum de-indent prefix
                                      state)
                 (mv ln state)))
               (t
                (pprogn (newline channel state)
                        (princ-prefix prefix channel state)
                        (print-doc-string-part1
                         str
                         (or (use-doc-string-de-indent de-indent
                                                       str (1+ i) maximum)
                             (1+ i))
                         maximum
                         de-indent
                         prefix
                         markup-table
                         char-subst-table
                         fmt-alist
                         channel name state
                         (if (integerp ln) (1+ ln) ln)
                         undocumented-file vp))))))
            (t (pprogn (princ$ (let ((temp (assoc c char-subst-table)))
                                 (if temp
                                     (coerce (cdr temp) 'string)
                                   c))
                               channel state)
                       (print-doc-string-part1 str (+ 1 i) maximum
                                               de-indent
                                               prefix markup-table
                                               char-subst-table
                                               fmt-alist
                                               channel name state ln
                                               undocumented-file vp))))))
        (t (pprogn
            (newline channel state)
            (save-more-doc-state str i maximum de-indent prefix state)
            (mv ln state)))))

(defun print-doc-string-part-mv
  (i str prefix markup-table char-subst-table fmt-alist
     channel name ln undocumented-file vp state)

; Str is a doc string and i is a part number, 0, 1, or 2.  We print the ith
; part of the string to channel.  We embed non-empty part 1's between a pair of
; newlines.

; When ln is :par, we interpret two consecutive blank lines as calling for a
; paragraph marker, in the sense described in the comments in
; print-doc-string-part1.  When ln is t, we print the entire part; see
; print-doc-string-part1.  Note that ln is ignored when i is 0.

; We return (mv new-ln state), where new-ln is the final value of ln.  Normally
; we will not need new-ln, but it is useful when printing part 1 followed by
; part 2 in the case that a preformatted environment spans the two parts, e.g.,
; "~bv[]...~/...~ev[]".  Typically we find this with "Example Forms" followed
; by "General Form".  We use the new-ln value in file doc/write-acl2-html.lisp,
; function write-a-doc-section (as of 1/12/2011).

  (let ((b-entry (assoc-string-equal "BPAR" markup-table))
        (e-entry (assoc-string-equal "EPAR" markup-table)))
    (pprogn
     (prog2$ (or (iff b-entry e-entry)
                 (er hard 'print-doc-string-part
                     "Found ~x0 but not ~x1 in markup-table,~|~x2."
                     (if b-entry "BPAR" "EPAR")
                     (if b-entry "EPAR" "BPAR")
                     markup-table))
             (cond ((and (not (eql i 0))
                         b-entry
                         (not (eq ln :par-off)))
                    (print-par-entry b-entry fmt-alist char-subst-table channel
                                     state))
                   (t state)))
     (mv-let
      (new-ln state)
      (let ((k (scan-to-doc-string-part i str))
            (maximum (length str)))
        (cond ((= i 1)
               (if (or (= k maximum)
                       (and (eql (char str k) #\~)
                            (< (1+ k) maximum)
                            (eql (char str (1+ k)) #\/)))

; If the part we are trying to print is empty, then don't do anything.
; except save the more doc state.

                   (pprogn (save-more-doc-state
                            str
                            (scan-past-whitespace str (+ 2 k) maximum) 
                            maximum
                            (get-doc-string-de-indent str)
                            prefix
                            state)
                           (mv ln state))

; Otherwise, put out a newline first and then do it.  This elaborate
; code is here to prevent us from putting out an unnecessary newline.

                 (pprogn (princ-prefix prefix channel state)
                         (newline channel state)
                         (princ-prefix prefix channel state)
                         (print-doc-string-part1 str
                                                 k
                                                 maximum
                                                 (get-doc-string-de-indent str)
                                                 prefix
                                                 markup-table
                                                 char-subst-table
                                                 fmt-alist
                                                 channel
                                                 name
                                                 state
                                                 ln
                                                 undocumented-file vp))))
              (t (print-doc-string-part1 str
                                         k
                                         maximum
                                         (get-doc-string-de-indent str)
                                         prefix
                                         markup-table
                                         char-subst-table
                                         fmt-alist
                                         channel
                                         name
                                         state
                                         (if (= i 0) nil ln)
                                         undocumented-file vp))))
      (pprogn (cond ((and (not (eql i 0))
                          e-entry
                          (not (eq new-ln :par-off)))
                     (print-par-entry e-entry fmt-alist char-subst-table
                                      channel state))
                    (t state))
              (mv new-ln state))))))

(defun print-doc-string-part
  (i str prefix markup-table char-subst-table fmt-alist
     channel name ln undocumented-file vp state)
  (mv-to-state
   2
   (print-doc-string-part-mv i str prefix markup-table char-subst-table
                             fmt-alist channel name ln undocumented-file vp
                             state)))

(defun get-doc-section (section alist)
  (cond ((null alist) nil)
        ((and (equal section (cadar alist))
              (not (equal section (caar alist))))
         (cons (car alist)
               (get-doc-section section (cdr alist))))
        (t (get-doc-section section (cdr alist)))))

(defmacro pstate-global-let* (bindings body)

; This macro is useful when you want the effect of state-global-let*
; but you are in a situation in which you are working only with state
; and not with error/val/state triples.

  `(mv-let (erp val state)
           (state-global-let* ,bindings
                              (pprogn ,body (value nil)))
           (declare (ignore erp val))
           state))

(mutual-recursion

(defun print-doc (name n prefix
                       markup-table char-subst-table fmt-alist
                       channel state)

; Name is either an atom (in which case we look it up in the documentation
; alist) -- it must be there -- or it is a doc-tuple from the alist.
; N should be either 0, 1, or 2.  We print the level 0, 1, or 2 for
; doc-tuple.  We assume that we are printing into col 0.  We always
; end at col 0.

  (let ((doc-tuple
         (cond
          ((atom name)
           (assoc-equal name (global-val 'documentation-alist (w state))))
          (t name)))
        (start-column (f-get-global 'print-doc-start-column state)))
    (cond
     ((= n 0)
      (pprogn
       (princ-prefix prefix channel state)
       (mv-let (col state)
               (splat-atom (cond
                            ((symbolp (car doc-tuple))
                             (apply-char-subst-table
                              (car doc-tuple)
                              char-subst-table
                              (car doc-tuple)))
                            ((stringp (car doc-tuple))
                             (apply-char-subst-table
                              (car doc-tuple)
                              char-subst-table
                              nil))
                            (t (car doc-tuple)))
                           (print-base)
                           2
                           (length-prefix prefix)
                           channel state)
               (pprogn
                (cond ((and start-column (>= col start-column))
                       (let ((length-prefix (length-prefix prefix)))
                         (pprogn
                          (newline channel state)
                          (princ-prefix prefix channel state)
                          (spaces (- start-column length-prefix)
                                  length-prefix channel state))))
                      (t (spaces (if start-column (- start-column col) 2)
                                 col channel state)))
                (print-doc-string-part 0 (cadddr doc-tuple)
                                       prefix
                                       markup-table
                                       char-subst-table
                                       fmt-alist
                                       channel
                                       name
                                       nil
                                       nil
                                       nil
                                       state)))))
     ((= n 1)
      (pprogn
       (print-doc-string-part 1 (cadddr doc-tuple)
                              prefix
                              markup-table
                              char-subst-table
                              fmt-alist
                              channel name nil nil nil state)
       (cond
        ((caddr doc-tuple)
         (pprogn
          (princ-prefix prefix channel state)
          (newline channel state)
          (princ-prefix prefix channel state)
          (princ$ "Subtopics (listed alphabetically):" channel state) 
          (newline channel state)
          (pstate-global-let*
           ((more-doc-state (f-get-global 'more-doc-state state)))
           (print-doc-lst (merge-sort-alpha-< (caddr doc-tuple))
                          (cons prefix 1)
                          markup-table
                          char-subst-table
                          fmt-alist
                          channel state))
          (princ-prefix prefix channel state)
          (princ$ "[end of subtopics]" channel state) 
          (newline channel state)))
        (t state))))
     (t (pprogn
         (princ-prefix prefix channel state)
         (print-doc-string-part 2 (cadddr doc-tuple)
                                prefix markup-table char-subst-table
                                fmt-alist
                                channel name nil nil nil state))))))

(defun print-doc-lst (lst prefix
                          markup-table char-subst-table fmt-alist
                          channel state)
  (cond ((null lst) state)
        (t (pprogn (print-doc (car lst) 0 prefix markup-table char-subst-table
                              fmt-alist
                              channel state)
                   (print-doc-lst (cdr lst) prefix markup-table
                                  char-subst-table
                                  fmt-alist
                                  channel state)))))

)

; Now we implement the DWIM feature of doc, which prints out the
; near-misses for an alleged (but erroneous) documentation topic.

(defun degree-of-match2 (ch1 ch2 str i maximum)
  (cond ((< (1+ i) maximum)
         (if (and (eql ch1 (normalize-char (char str i) nil))
                  (eql ch2 (normalize-char (char str (1+ i)) nil)))
             1
             (degree-of-match2 ch1 ch2 str (1+ i) maximum)))
        (t 0)))

(defun degree-of-match1 (pat-lst str maximum)
  (cond ((null pat-lst) 0)
        ((null (cdr pat-lst)) 0)
        (t (+ (degree-of-match2 (car pat-lst) (cadr pat-lst) str 0 maximum)
              (degree-of-match1 (cdr pat-lst) str maximum)))))

(defun degree-of-match (pat-lst str)

; Pat-lst is a normalized string (with hyphen-is-space nil).  We
; normalize str similarly and compute the degree of match between
; them.  The answer is a rational between 0 and 1.  The number is just
; n divided by (length pat)-1, where n is the number of adjacent
; character pairs in pat that occur adjacently in str.  This is just
; a Royal Kludge that seems to work.

  (if (< (length pat-lst) 2)
      0
      (/ (degree-of-match1 pat-lst str (length str))
         (1- (length pat-lst)))))

(defun find-likely-near-misses (pat-lst alist)

; Alist is the documentation-alist.  Pat-lst is a normalized string
; (with hyphen-is-space nil).  We collect the cars of the pairs in
; alist that have a degree of match of more than one half.  Again, an
; utter kludge.

  (cond ((null alist) nil)
        (t (let ((d (degree-of-match pat-lst
                                     (if (stringp (caar alist))
                                         (caar alist)
                                         (symbol-name (caar alist))))))
             (cond ((<= d 1/2)
                    (find-likely-near-misses pat-lst (cdr alist)))
                   (t (cons (cons d (caar alist))
                            (find-likely-near-misses pat-lst
                                                     (cdr alist)))))))))

(defun print-doc-dwim (name ctx state)
  (let ((lst (merge-sort-car->
              (find-likely-near-misses
               (normalize-string
                (if (stringp name)
                    name
                    (symbol-name name))
                nil)
               (global-val 'documentation-alist (w state))))))
    (cond ((null lst) (value nil))
          (t (er soft ctx
                 "There is no documentation for ~x0.  ~#1~[A similar ~
                  documented name is~/Similar documented names are~] ~
                  ~&1.  See also :DOC apropos."
                 name
                 (strip-cdrs lst))))))

(defun end-doc (channel state)
  (cond
   ((f-get-global 'more-doc-state state)
    (pprogn (princ$ "(type :more for more, :more! for the rest)" channel state)
            (newline channel state)
            (value :invisible)))
   (t (pprogn (princ$
               (if (hons-enabledp state)
                   "  " ; Boyer preference
                 "*-")
               channel state)
              (newline channel state)
              (value :invisible)))))

(defun doc-fn (name state)
  (cond
   ((not (symbolp name))
    (er soft :doc
        ":DOC requires a symbol"))
   (t
    (io? temporary nil (mv erp val state)
         (name)
         (let ((channel (standard-co state))
               (temp (if (keywordp name)
                         (assoc-eq name
                                   (f-get-global 'ld-keyword-aliases state))
                       nil))
               (doc-tuple (access-doc-string-data-base name state)))
           (cond
            ((or temp
                 (null doc-tuple))
             (let ((temp (cond
                          ((symbolp name)
                           (assoc-eq (intern (symbol-name name) "KEYWORD")
                                     (f-get-global 'ld-keyword-aliases state)))
                          ((stringp name)
                           (assoc-eq (intern name "KEYWORD")
                                     (f-get-global 'ld-keyword-aliases state)))
                          (t nil))))
               (cond
                ((null temp)
                 (print-doc-dwim name :doc state))
                (t
                 (mv-let
                  (col state)
                  (fmt1 "~@0~x1 is ~#2~[a~/an~] ~n3 input alias for ~x4.~%~%"
                        (list (cons #\0 (doc-prefix state))
                              (cons #\1 (car temp))
                              (cons #\2 (if (member (cadr temp) '(8 18)) 1 0))
                              (cons #\3 (cadr temp))
                              (cons #\4 (caddr temp)))
                        0 channel state nil)
                  (declare (ignore col))
                  (cond ((and (symbolp (caddr temp))
                              (access-doc-string-data-base (caddr temp) state))
                         (doc-fn (caddr temp) state))
                        (t (value :invisible))))))))
            (t (pprogn (print-doc doc-tuple 0 (doc-prefix state)
                                  (doc-markup-table state)
                                  (doc-char-subst-table state)
                                  (doc-fmt-alist state)
                                  channel state)
                       (print-doc doc-tuple 1 (doc-prefix state)
                                  (doc-markup-table state)
                                  (doc-char-subst-table state)
                                  (doc-fmt-alist state)
                                  channel state)
                       (newline channel state)
                       (end-doc channel state)))))))))

(defun more-fn (ln state)
  (io? temporary nil (mv erp val state)
       (ln)
       (let ((more-doc-state (f-get-global 'more-doc-state state))
             (channel (standard-co state)))
         (cond
          (more-doc-state
           (pprogn
            (princ-prefix (car (cddddr more-doc-state)) channel state)
            (mv-to-state
             2
             (print-doc-string-part1 (car more-doc-state)
                                     (cadr more-doc-state)
                                     (caddr more-doc-state)
                                     (cadddr more-doc-state)
                                     (car (cddddr more-doc-state))
                                     (doc-markup-table state)
                                     (doc-char-subst-table state)
                                     (doc-fmt-alist state)
                                     channel "the current item" state ln nil
                                     nil))
            (end-doc channel state)))
          (t (end-doc channel state))))))

(defun doc!-fn (name state)
  (cond
   ((not (symbolp name))
    (er soft :doc!
        ":DOC! requires a symbol"))
   (t
    (io? temporary nil (mv erp val state)
         (name)
         (let ((channel (standard-co state))
               (doc-tuple (access-doc-string-data-base name state)))
           (cond ((null doc-tuple)
                  (print-doc-dwim name :doc state))
                 (t (pprogn (print-doc doc-tuple 0 (doc-prefix state)
                                       (doc-markup-table state)
                                       (doc-char-subst-table state)
                                       (doc-fmt-alist state)
                                       channel state)
                            (print-doc doc-tuple 1 (doc-prefix state)
                                       (doc-markup-table state)
                                       (doc-char-subst-table state)
                                       (doc-fmt-alist state)
                                       channel state)
                            (princ-prefix (doc-prefix state) channel state)
                            (newline channel state)
                            (more-fn t state)))))))))

(defmacro more nil

  ":Doc-Section Documentation

  your response to ~c[:]~ilc[doc] or ~c[:]~ilc[more]'s ``~c[(type :more...)]''~/

  NOTE:  The command ~c[:more] only makes sense at the terminal.
  ~bv[]
  Example:
  ACL2 !>:more
  ~ev[]
  will continue printing whatever ~il[documentation] was started by ~c[:]~ilc[doc]
  or ~c[:]~ilc[more-doc].~/

  When you type ~c[:doc name], for some documented ~c[name], the system
  responds by typing the one-liner and the notes sections of the
  ~il[documentation] for ~c[name].  It then types
``~c[(type :more for more, :more! for the rest)]''.  If you then type
  ~bv[]
  ACL2 !>:more
  ~ev[]
  the system will start to print the details section of ~c[name].  The
  same thing could be achieved by typing ~c[:more-doc name], but that
  requires you to type name again.

  Similarly, if you have typed ~c[:]~ilc[more-doc] name, the system will print
  the first ``block'' of the details section and then print
  ``~c[(type :more for more, :more! for the rest)]''.  Typing ~c[:more] at that
  point will cause the next block of the details section to be printed.
  Eventually ~c[:more] will conclude by printing ``~c[*-]'' which is the
  indicator that the text has been exhausted.

  What is a ``block'' of text?  ~c[:More] looks for the end of a paragraph
  (two adjacent newlines) after printing ~c[n] lines.  If it doesn't find
  one before it has printed ~c[k] lines, it just stops there.  ~c[N] and ~c[k]
  here are the values of the two ~il[state] global variables
  ~c['more-doc-min-lines] and ~c['more-doc-max-lines].  You may use ~ilc[@] and
  ~ilc[assign] to inspect and set these variables, e.g.,
  ~c[(@ more-doc-max-lines)] will return the current maximum number of
  lines printed by ~c[:more] and ~c[(assign more-doc-max-lines 19)] will
  set it to 19.  On terminals having only 24 lines, we find min and
  max settings of 12 and 19 the most pleasant.

  If you want ~c[:more] to print all of the details instead of feeding
  them to you one block at a time, type ~c[:]~ilc[more!] instead."

 '(more-fn 0 state))

(defmacro more! nil

  ":Doc-Section Documentation

  another response to ``(type :more for more, :more! for the rest)''~/

  NOTE:  The command ~c[:more!] only makes sense at the terminal.
  ~bv[]
  Example:
  ACL2 !>:more!
  ~ev[]
  will print all of the remaining ~il[documentation] started by the last
  ~c[:]~ilc[doc] or ~c[:]~ilc[more-doc].~/

  ~l[more] for some background.  Typing ~c[:more!] will print all
  remaining blocks of ~il[documentation].

  ~c[:More!] is like ~c[:]~ilc[more] except that it prints all the text at once.
  For example, if you type ~c[:]~ilc[doc] name you will see some text followed
  by ``~c[(type :more for more, :more! for the rest)]''.  If you then type
  simply ~c[:more!] you will see all of the details, while if you type
  ~c[:]~ilc[more] you will be fed the next block of details."

  '(more-fn t state))

(defun print-doc-outline
  (name prefix markup-table char-subst-table fmt-alist
        channel state)

; Name is either an atom (in which case it must be a topic in the
; documentation alist) or else is a doc-tuple from the alist.
; This function is sort of like (doc-fn name state) except
; that it just prints the one-liner for name and then the related
; topics, while doc-fn would print the notes section too.

  (let ((doc-tuple
         (cond
          ((atom name)
           (assoc-equal name (global-val 'documentation-alist (w state))))
          (t name))))
    (pprogn (print-doc doc-tuple 0 prefix
                       markup-table char-subst-table fmt-alist
                       channel state)
            (print-doc-lst
             (merge-sort-alpha-< (caddr doc-tuple))
             (cons prefix 1)
             markup-table
             char-subst-table
             fmt-alist
             channel state)
            (princ-prefix prefix channel state)
            (princ$ " See also :MORE-DOC " channel state)
            (princ$ (car doc-tuple) channel state)
            (newline channel state))))

(defun print-doc-outline-lst (name-lst prefix
                                       markup-table char-subst-table
                                       fmt-alist
                                       channel state)
  (cond ((null name-lst) state)
        (t (pprogn (print-doc-outline (car name-lst) prefix markup-table
                                      char-subst-table
                                      fmt-alist
                                      channel state)
                   (print-doc-outline-lst (cdr name-lst)
                                          prefix markup-table char-subst-table
                                          fmt-alist
                                          channel state)))))

(deflabel apropos

; WARNING: Do not attempt to define apropos as a macro.  This symbol is
; imported from Common Lisp and might already have a definition.

  :doc
  ":Doc-Section acl2::Miscellaneous

  searching the documentation online~/

  The ~c[:]~ilc[docs] command allows you to search the ~il[documentation] at
  the terminal.  ~l[docs].~/~/")

(deflabel markup
  :doc
  ":Doc-Section Documentation

  the markup language for ACL2 ~il[documentation] strings~/

  ACL2 ~il[documentation] strings make special use of the tilde character
  (~~).  In particular, we describe here a ``markup language'' for
  which the tilde character plays a special role.  The markup language
  is valuable if you want to write ~il[documentation] that is to be
  displayed outside your ACL2 session.  If you are not writing such
  ~il[documentation], and if also you do not use the character `~~', then
  there is no need to read on.~/

  Three uses of the tilde character (~~) in ~il[documentation] strings are
  as follows.  Below we explain the uses that constitute the ACL2
  markup language.
  ~bq[]
  ~c[~~/]~nl[]
  Indicates the end of a documentation ~st[section];
  ~pl[doc-string].

  ~c[~~~~]~nl[]
  Indicates the literal insertion of a tilde character (~~).

  ~c[~~~]]~nl[]
  This directive in a documentation string is effective only during
  the processing of part 2, the details (~pl[doc-string]), and
  controls how much is shown on each round of ~c[:]~ilc[more] processing when
  printing to the terminal.  If the system is not doing ~c[:]~ilc[more]
  processing, then it acts as though the ~~] is not present.
  Otherwise, the system put out a newline and halts documentation
  printing on the present topic, which can be resumed if the user
  types ~c[:]~ilc[more] at the terminal.
  ~eq[]
  The other uses of the tilde character are of the following form.
  ~bv[]
    ~~key[arg]
  ~ev[]
  Before launching into an explanation of how this works in detail,
  let us consider some small examples.

  Here is a word that is code:
  ~bv[]
    ~~c[function-name].
  ~ev[]
  Here is a phrase with an ``emphasized'' word, ``not'':
  ~bv[]
    Do ~~em[not] do that.
  ~ev[]
  Here is the same phrase, but where ``not'' receives stronger
  emphasis (presumably boldface in a printed version):
  ~bv[]
    Do ~~st[not] do that.
  ~ev[]
  Here is a passage that is set off as a display, in a fixed-width
  font:
  ~bv[]
    ~~bv[]
    This passage has been set off as ``verbatim''.
    The present line starts just after a line break.  Normally, printed
    text is formatted, but inside ~~bv[]...~~ev[], line breaks are taken
    literally.
    ~~ev[]
  ~ev[]
  In general, the idea is to provide a ``markup language'' that can be
  reasonably interpreted not only at the terminal (via ~c[:]~ilc[doc]), but
  also via translators into other languages.  In fact, translators
  have been written into Texinfo and HTML.

  Let us turn to a more systematic consideration of how to mark text
  in ~il[documentation] strings using expressions of the form
  ~c[~~key[arg~]], which we will call ``~il[doc-string] tilde directives.''
  The idea is that ~c[key] informs the ~il[documentation] printer (which
  could be the terminal, a hardcopy printer, or some hypertext tool)
  about the ``style'' used to display ~c[arg].  The intention is that
  each such printer should do the best it can.  For example, we have
  seen above that ~c[~~em[arg~]] tells the printer to ~i[emphasize]
  ~c[arg] if possible, using an appropriate display to indicate
  emphasis (italics, or perhaps surrounding ~c[arg] with some character
  like ~c[_], or ...).  For another example, the directive for bold
  font, ~c[~~b[arg~]], says that printed text for ~c[arg] should be in
  bold if possible, but if there is no bold font available (such as at
  the terminal), then the argument should be printed in some other
  reasonable manner (for example, as ordinary text).  The ~c[key] part
  is case-insensitive; for example, you can use ~~BV[] or ~~Bv[] or ~~bV[] in
  place of ~~bv[].

  Every form below may have any string as the argument (inside
  ~c[[..~]]), as long as it does not contain a newline (more on that
  below).  However, when an argument does not make much sense to us,
  we show it below as the empty string, e.g., ``~c[~~bv[~]]'' rather
  than ``~c[~~bv[arg~]]''.
  ~bv[]
  ~~-[]      Print the equivalent of a dash

  ~~b[arg]   Print the argument in bold font, if available

  ~~bid[arg]   ``Begin implementation dependent'' -- Ignores argument at
            terminal.

  ~~bf[]     Begin formatted text (respecting spaces and line breaks),
            but in ordinary font (rather than, say, fixed-width font)
            if possible

  ~~bq[]     Begin quotation (indented text, if possible)

  ~~bv[]     Begin verbatim (print in fixed-width font, respecting
            spaces and line breaks)

  ~~c[arg]   Print arg as ``code'', such as in a fixed-width font

  ~~ef[]     End format; balances ~~bf[]

  ~~eid[arg]   ``End implementation dependent'' -- Ignores argument at
            terminal.

  ~~em[arg]  Emphasize arg, perhaps using italics

  ~~eq[]     End quotation; balances ~~bq[]

  ~~ev[]     End verbatim; balances ~~bv[]

  ~~i[arg]   Print arg in italics font

  ~~id[arg]   ``Implementation dependent'' -- Ignores argument at
            terminal.

  ~~il[arg]  Print argument as is, but make it a link to another doc
            topic (for true hypertext environments).  Note that the
            link argument must match the package name for the desired
            topic unless the package name is ``ACL2''.  That is, to
            link to documentation on ``foo::topic'', one needs to use
            the full name for ``foo::topic'', including its package
            name.

  ~~ilc[arg] Same as ~~il[arg], except that arg should be printed as
            with ~~c[arg]

  ~~l[arg]   Ordinary link to another doc topic; prints as ``See :DOC
            arg'' at the terminal (but also see ~~pl below, which puts
            ``see'' in lower case)

  ~~nl[]     Print a newline

  ~~par[]    Paragraph mark, of no significance at the terminal
            (can be safely ignored; see also notes below)

  ~~pl[arg]  Parenthetical link (borrowing from Texinfo):  same as
            ~~l[arg], except that ``see'' is in lower case.  This is
            typically used at other than the beginning of a sentence.

  ~~sc[arg]  Print arg in (small, if possible) capital letters

  ~~st[arg]  Strongly emphasize arg, perhaps using a bold font

  ~~t[arg]   Typewriter font; similar to ~~c[arg], but leaves less
            doubt about the font that will be used.

  ~~terminal[arg]  Terminal only; arg is to be ignored except when
            reading documentation at the terminal, using :DOC.

  ~~url[arg]  Print arg as HTML hyperlink if possible (else print like ~c[~~c])
  ~ev[]

  ~em[Style notes and further details]

  It is not a good idea to put ~il[doc-string] tilde directives inside
  verbatim environments, ~c[~~bv[~] ... ~~ev[~]].

  Do not nest ~il[doc-string] tilde directives; that is, do not write
  ~bv[]
    The ~~c[~~il[append~]] function ...
  ~ev[]
  but note that the ``equivalent'' expression
  ~bv[]
    The ~~ilc[append] function ...
  ~ev[]
  is fine.  The following phrase is also acceptable:
  ~bf[]
    ~~bf[]This is
    ~~em[formatted] text.
    ~~ef[]
  ~ef[]
  because the nesting is only conceptual, not literal.

  We recommend that for displayed text, ~c[~~bv[~]] and ~c[~~ev[~]]
  should usually each be on lines by themselves.  That way, printed
  text may be less encumbered with excessive blank lines.  Here is an
  example.
  ~bf[]
    Here is some normal text.  Now start a display:
    ~~bv[]
      2 + 2 = 4
    ~~ev[]
    And here is the end of that paragraph.

    Here is the start of the next paragraph.
  ~ef[]
  The analogous consideration applies to ~c[~~bf[~]] and ~c[~~ef[~]] as
  well as ~c[~~bq[~]] and ~c[~~eq[~]].

  You may ``quote'' ~il[characters] inside the ~c[arg] part of
  ~c[~~key[arg~]], by preceding them with ~~.  This is, in fact, the
  only legal way to use a newline character or a right bracket (])
  inside the argument to a ~il[doc-string] tilde directive.

  Write your ~il[documentation] strings without hyphens.  Otherwise, you
  may find your text printed on paper (via TeX, for example) like
  this ~-[]
  ~bf[]
    Here is a hyphe- nated word.
  ~ef[]
  even if what you had in mind was:
  ~bf[]
    Here is a hyphe-
    nated word.
  ~ef[]
  When you want to use a dash (as opposed to a hyphen), consider using
  ~~-[], which is intended to be interpreted as a ``dash.''  For
  example:
  ~bf[]
    This sentence ~~-[] which is broken with dashes ~~-[] is boring.
  ~ef[]
  would be written to the terminal (using ~c[:]~ilc[doc]) by replacing
  ~c[~~-[~]] with two hyphen ~il[characters], but would presumably be
  printed on paper with a dash.

  Be careful to balance the ``begin'' and ``end'' pairs, such as
  ~c[~~bv[~]] and ~c[~~ev[~]].  Also, do not use two ``begin''
  directives (~c[~~bf[~]], ~c[~~bq[~]], or ~c[~~bv[~]]) without an
  intervening ``end'' directive.  It is permissible (and perhaps this
  is not surprising) to use the ~il[doc-string] part separator ~c[~~/] while
  between such a begin-end pair.

  Because of a bug in texinfo (as of this writing), you may wish to
  avoid beginning a line with (any number of spaces followed by) the
  ~ilc[-] character or ~c[~~-[~]].

  The ``paragraph'' directive, ~c[~~par[~]], is rarely if ever used.
  There is a low-level capability, not presently documented, that
  interprets two successive newlines as though they were ~c[~~par[~]].
  This is useful for the HTML driver.  For further details, see the
  authors of ACL2.

  Emacs code is available for manipulating ~il[documentation] strings that
  contain ~il[doc-string] tilde-directives (for example, for doing a
  reasonable job filling such ~il[documentation] strings).  See the authors
  if you are interested.

  We tend to use ~c[~~em[arg~]] for ``section headers,'' such as
  ``Style notes and further details'' above.  We tend to use
  ~c[~~st[arg~]] for emphasis of words inside text.  This division
  seems to work well for our Texinfo driver.  Note that ~c[~~st[arg~]]
  causes ~c[arg] to be printed in upper-case at the terminal (using
  ~c[:]~ilc[doc]), while ~c[~~em[arg~]] causes ~c[arg] to be printed at the
  terminal as though ~c[arg] were not marked for emphasis.

  Our Texinfo and HTML drivers both take advantage of capabilities for
  indicating which ~il[characters] need to be ``escaped,'' and how.  Unless
  you intend to write your own driver, you probably do not need to
  know more about this issue; otherwise, contact the ACL2 authors.  We
  should probably mention, however, that Texinfo makes the following
  requirement:  when using ~c[~~l[arg~]], where ~c[arg] contains
  one of the special ~il[characters] ~ilc[@], ~c[{], or ~c[}], you must
  immediately follow this use with a period or comma.  Also, the Emacs
  ``info'' ~il[documentation] that we generate by using our Texinfo driver
  has the property that in node names, ~c[:] has been replaced by ~c[|]
  (because of quirks in info); so for example, the ``~il[proof-checker]''
  simplification command, ~c[s], is documented under ~c[acl2-pc||s]
  rather than under ~c[acl2-pc::s].

  We have tried to keep this markup language fairly simple; in
  particular, there is no way to refer to a link by other than the
  actual name.  So for example, when we want to make ~c[:]~ilc[doc] an
  invisible link in ``code'' font, we write the following form, which
  indicates that ~c[:] should be in that font and then ~ilc[doc] should
  both be in that font and be an invisible link.
  ~bv[]
    ~~c[:]~~ilc[doc]
  ~ev[]
  ")

(deflabel doc-string
  :doc
  ":Doc-Section Documentation

  formatted ~il[documentation] strings~/
  ~bv[]
  Examples:
  \":Doc-Section name
  one-liner~~/notes~~/details\"

  \":Doc-Section name
  one-liner~~/
  notes~~/
  details~~/
  :cite old-name1
  :cited-by old-name2\"
  ~ev[]
  Use ~c[(get-doc-string 'name state)] to see other examples.

  ~il[Documentation] strings not beginning with ``~c[:Doc-Section]'' (case is
  irrelevant) are ignored.  ~l[markup] for how to supply
  formatting information (such as fonts and displayed text) in
  ~il[documentation] strings.~/

  ACL2 attaches special importance to ~il[documentation] strings beginning
  with the header ``~c[:Doc-Section]'' (or any variant thereof obtained by
  changing case).  Any ~il[documentation] string that does not begin with
  such a header is considered unformatted and is ignored.  For the
  rest of this discussion, we use the phrase ``~il[documentation] string''
  as though it read ``formatted ~il[documentation] string.''

  ~il[Documentation] strings are always processed in the context of some
  symbol, ~c[name], being defined.  (Indeed, if an event defines no
  symbol, e.g., ~ilc[verify-guards] or ~ilc[in-theory], then it is not permitted
  to have a formatted ~il[documentation] string.)  The string will be
  associated with name in the ``~il[documentation] data base.'' The data
  base is divided into ``sections'' and each section is named by a
  symbol.  Among the sections are ~ilc[events], ~ilc[documentation], ~ilc[history],
  ~ilc[other], and ~ilc[miscellaneous].  A complete list of the sections may be
  obtained by typing ~c[:docs *] at the terminal.  You can create new
  sections.  The main purpose of sections is simply to partition the
  large set of names into smaller subsets whose contents can be
  enumerated separately.  The idea is that the user may remember (or
  recognize) the relevant section name and then read its contents to
  find interesting items.

  Within a section are ``~il[documentation] tuples'' which associate with
  each documented name its ~il[documentation] string and a list of related
  documented names, called the ``related names'' of the name.  When
  ~c[:]~ilc[doc] prints the ~il[documentation] for name, it always lists the related
  names.

  When a formatted ~il[documentation] string is submitted with the defining
  event of some name, the section name and an initial set of related
  names are parsed from the string.  In addition, the formatted string
  contains various ``levels'' of detail that are printed out at
  different times.  Finally, it is possible for a string to cause the
  newly documented name to be added to the related names of any
  previously documented name.  Thus, as new names are introduced they
  can be grouped with old ones.

  The general form of an ACL2 formatted ~il[documentation] string is
  ~bv[]
  \":DOC-SECTION <section-name>
    <one-liner>~~/
    <notes>~~/
    <details>~~/
    :CITE <n1>
    ...
    :CITE <nn>
    :CITED-BY <m1>
    ...
    :CITED-BY <mm>\"
  ~ev[]
  Before we explain this, let it be noted that
  ~c[(get-doc-string name state)] will return the ~il[documentation] string
  associated with ~c[name] in the ~il[documentation] data base.  You may
  want to call ~c[get-doc-string] on ~c[']~ilc[pe] and ~c[']~ilc[union-theories] just
  to see some concrete ~il[documentation] strings.  This ~il[documentation]
  string, which is rather long, is under ~c['doc-string].

  A formatted ~il[documentation] string has five parts: the header and
  section-name (terminating in the first ~c[#\\Newline]), the ~c[<one-liner>],
  ~c[<notes>], and ~c[<details>] (each terminating in a tilde-slash (``~c[~~/]'')
  pair), and a citation part.  These five parts are parsed into six
  components.  ~c[<section-name>] is read as the name of a symbol,
  section-name.  ~c[<one-liner>], ~c[<notes>], and ~c[<details>] are arbitrary
  sequences of ~il[characters] (ignoring initial white space and not
  including the tilde-slash pairs which terminate them).  The ~c[<ni>] are
  read as symbols and assembled into a list called the ``cite''
  symbols.  The ~c[<mi>] are read as symbols and assembled into a list
  called the ``cited-by'' symbols.  See the warning below regarding
  the hackish nature of our symbol reader.

  ~c[Section-name] must either be a previously documented symbol or else
  be ~c[name], the symbol being documented.  To open a new section of the
  data base, named ~c[section-name], you should define the logical name
  section-name (as by ~ilc[deflabel] or any other event; also
  ~pl[defdoc]) and attach to it a ~il[documentation] string for section
  section-name.  You might wish to print out the ~il[documentation] string
  we use for some of our section names, e.g.,
  ~c[(get-doc-string 'events state)].  By forcing section names to be
  documented symbols, we permit sections themselves to have one line
  descriptions and discussions, presented by the standard
  ~il[documentation] facilities like the facilities ~c[:]~ilc[doc] and ~c[:]~ilc[more-doc] that
  may be used at the terminal.

  Each of the ~c[ni]'s and ~c[mi]'s must be previously documented symbols.

  Both ~c[<one-liner>] and ~c[<details>] must be non-empty, i.e., must contain
  some non-whitespace ~il[characters].  ~c[<notes>] may be empty.  The ~c[:cite]s
  and ~c[:cited-by]s pairs may be intermingled and may be separated by
  either newlines or spaces.  The citation part may be empty.  When
  the citation part is empty, the tilde-slash pair terminating the
  ~c[<details>] part may be omitted.  Thus, the simplest form of a
  formatted ~il[documentation] string is:
  ~bv[]
  \":Doc-Section <section-name>
   <one-liner>~~/~~/
   <details>\"
  ~ev[]
  Since white space at the front of ~c[<one-liner>], ~c[<notes>] and
  ~c[<details>] is ignored, we often precede those parts by ~c[#\\Newline]s to
  make the strings easier to read in our source files.  We also
  typically indent all of the text in the string by starting each line
  with a few spaces.  (The Emacs commands for formatting Lisp get
  confused if you have arbitrary ~il[characters] on the left margin.)  We
  assume that every line in ~c[<one-liner>], ~c[<notes>], and ~c[<details>] starts
  with at least as many spaces as ~c[<one-liner>] does, i.e., we assume
  they are all indented the same amount (or more).  Let ~c[d] be the
  number of spaces separating ~c[<one-liner>] from the ~c[#\\Newline]
  preceding it.  When the various parts are printed, we ``de-indent''
  by stripping out the first d spaces following each ~c[#\\Newline].

  However, we find that when ~il[documentation] is printed flush against
  the left margin it is difficult to distinguish the ~il[documentation]
  text from previous output.  We therefore prefix each line we print
  by a special pad of ~il[characters].  By default, this pad is ``~c[| ]'' so
  that ~il[documentation] text has a vertical bar running down the left
  margin.  But the pad is just the value of the global variable
  ~c[doc-prefix] and you may ~ilc[assign] it any string you wish.

  To add such a string to the data base under the symbol ~c[name] we make
  a new entry in the section-name section of the data base.  The entry
  associates ~c[name] with the string and uses the string's cites list as
  the initial value of the related names field.  In addition, we add
  ~c[name] to the related names field of each of the names listed in the
  string's cited-by list.  We also add ~c[name] to the related names field
  of its section-name.  Observe that the cites list in a string is
  only the initial value of the related names of the names.  Future
  ~il[documentation] strings may add to it via ~c[:cited-by] or ~c[:doc-section].
  Indeed, this is generally the case.  We discuss this further below.

  When a brief description of ~c[name] is required (as by ~c[:docs **]), ~c[name]
  and ~c[<one-liner>] are printed.  ~c[<one-liner>] is usually printed
  starting in column 15 (however ~pl[print-doc-start-column]).
  Despite its name, ~c[<one-liner>] need not be one line.  It usually is
  one line, however.

  When you type ~c[:]~ilc[doc] name at the terminal, the first response will be
  to print ~c[name] and ~c[<one-liner>].  Then ~c[:]~ilc[doc] prints ~c[<notes>], if any.
  Then, if ~c[name] is the name of a section, it prints the ~c[<one-liner>]s
  for each of its related names.  For example, try ~c[:doc events].  If
  ~c[name] is not a section name but does have some related names, they
  are merely listed but not explained.  Try ~c[:doc theory-functions].
  ~c[:more-doc name] prints ~c[<details>].

  Our style is to let each new concept add itself to the related names
  of old concepts.  To do otherwise increases the chances that
  ~il[documentation] gets outdated because one often forgets to update
  supposedly complete lists of the relevant topics when new topics are
  invented.  For example, ~c[:doc theory-functions] lists each available
  theory function.  But ~c[get-doc-string] of ~c[']~ilc[theory-functions] just
  shows a few examples and has an empty cites list.  From where do we
  get the names of the theory functions listed by ~c[:]~ilc[doc]?  The answer is
  that each theory function has its own ~il[documentation] string and those
  strings each specify ~c[:cited-by] ~il[theory-functions].  See for example
  ~c[get-doc-string] of ~c[']~ilc[union-theories].  So by the time the entire system
  is assembled, the related names of ~c[']~ilc[theory-functions] contains all
  the (documented) theory functions.  This makes it easy to add new
  theory functions without changing the general discussion in
  ~c[']~ilc[theory-functions].

  When an event or ~il[command] form is printed, as by ~c[:]~ilc[pe] or ~c[:]~ilc[pc], that
  contains a formatted ~il[documentation] string, we do not print the
  actual ~il[documentation] string (since they are usually large and
  distracting).  Instead we print the string:
  ~bv[]
    \"Documentation available via :doc\"
  ~ev[]
  inviting you to use ~c[:]~ilc[doc] and ~c[:]~ilc[more-doc] (or ~c[get-doc-string]) if you
  wish to see the ~il[documentation] at the terminal.

  ~em[Warning on Reading Symbols from Strings:] When we read a symbol, such
  as the section-symbol, from a ~il[documentation] string, we use a quick
  and dirty imitation of the much more powerful CLTL ~c[read] program.  In
  particular, we scan past any whitespace, collect all the ~il[characters]
  we see until we get to more whitespace or the end of the string,
  convert the ~il[characters] to upper case, make a string out of them, and
  ~ilc[intern] that string.  Thus, if you typed ~c[\":Doc-Section 123 ...\"] we
  would read the ~c[123] as the symbol ~c[|123|].  Observe that special
  ~il[characters], such as parentheses and escape ~il[characters], are not
  afforded their usual reverence by our hack.  Furthermore, the
  question arises: in which package do we ~ilc[intern] the symbol?  The
  answer is, usually, the package containing the name being defined.
  I.e., if you are documenting ~c[my-pkg::name] and you attach a
  ~il[documentation] string that begins ~c[\":Doc-Section: Machines ...\"] then
  the section-symbol will be ~c[my-pkg::machines].  We recognize two
  special cases. If the first character read is a colon, we use the
  ~c[keyword] package.  If the first five ~il[characters] read are ~c[acl2::] then
  we ~il[intern] in the ~c[\"ACL2\"] package.  Our own section names, e.g.,
  ~ilc[events], are in the ~c[\"ACL2\"] package.

  In a related area, when you ask for the ~il[documentation] of a name,
  e.g., when you type ~c[:doc name] at the terminal, that name is read
  with the full ACL2 reader, not the hack just described.  That name
  is read into the current package.  Thus, if you are operating
  ~ilc[in-package] ~c[\"MY-PKG\"] and type ~c[:doc events], what is read is
  ~c[my-pkg::events].  The data base may not contain an entry for this
  symbol.  Before reporting that no ~il[documentation] exists, we try
  ~c[acl2::events].

  One last note: ~ilc[defpkg] permits a formatted ~il[documentation] string,
  which is associated in the data base with the name of the package.
  But the name of the package is a string, not a symbol.  It is
  permitted to access the ~il[documentation] of a string (i.e., package
  name).  But there are no facilities for getting such a ~ilc[stringp] name
  into the related names of another name nor of making such ~il[stringp]
  names be section names.  That is because we always read symbols from
  strings and never read strings from strings.  I.e., if you did write
  ~c[\"Doc-Section \\\"MY-PKG\\\" ...\"] it would read in as a weird
  symbol.~/")

(deflabel print-doc-start-column
  :doc
  ":Doc-Section Miscellaneous

  printing the one-liner~/
  ~bv[]
  Examples:
  (assign print-doc-start-column nil)
  (assign print-doc-start-column 17)
  ~ev[]~/

  This ~il[state] global variable controls the column in which the
  ``one-liner'' of a formatted ~il[documentation] string is printed.
  Generally, when ~c[:]~ilc[doc] is used to print a ~il[documentation] string, the
  name of the documented concept is printed and then ~c[:]~ilc[doc] tabs over to
  ~c[print-doc-start-column] and prints the one-liner.  If the name
  extends past the desired column, ~c[:]~ilc[doc] outputs a carriage return and
  then tabs over to the column.  If ~c[print-doc-start-column] is ~c[nil],
  ~c[:]~ilc[doc] just starts the one-liner two spaces from the end of the name,
  on the same line.  The initial value of ~c[print-doc-start-column] is
  15.")

(defmacro doc (name)

  ":Doc-Section Documentation

  brief ~il[documentation] (type ~c[:doc name])~/

  NOTE:  The ~c[:doc] command only makes sense at the terminal.
  Furthermore it only works at the terminal when a ``full-size'' image
  has been built.  Most users will probably access the ACL2
  documentation in other ways, as explained in the file ~c[\"doc/README\"]
  that comes with the ACL2 distribution.
  ~bv[]
  Examples:
  ACL2 !>:doc DEFTHM          ; print documentation of DEFTHM
  ACL2 !>:doc logical-name    ; print documentation of LOGICAL-NAME
  ACL2 !>:doc \"MY-PKG\"      ; print documentation of \"MY-PKG\"

  Related Topics:
  :more                      ; continues last :doc or :more-doc text
  :more-doc name             ; prints more documentation for name
  :docs **                   ; lists all documented symbols
  :docs \"compil\"             ; documented symbols apropos \"compil\"
  :DOC documentation         ; describes how documentation works~/

  General Form:
  ACL2>:doc logical-name
  ~ev[]
  where ~ilc[logical-name] is a logical name (~pl[logical-name]) for
  which you hope there is ~il[documentation].  Chances are there is no
  ~il[documentation] at the moment, but we are working on adding
  ~il[documentation] strings for all the user level ACL2 functions.

  For a general discussion of our treatment of documentation strings,
  ~pl[documentation].

  This is the first cut at online ~il[documentation].  Users can be
  particularly helpful by sending mail on the inadequacies of the
  system.  Address it just to Moore and put ~il[Documentation] in the
  subject line.  There are several things that trouble me about what
  I've done here.

  First, many concepts aren't documented.  Ultimately, I'd like to
.  document (a) every CLTL primitive (e.g., ~ilc[case] and ~ilc[coerce]) and (b)
  every ACL2 extension (e.g., ~ilc[aref1] and ~c[getprop]).  But so far I have
  focussed on documenting (c) the ACL2 system primitives (e.g., ~ilc[defthm]
  and what ~ilc[hints] look like).  My priorities are (c), then (b), and
  then (a), following the philosophy that the most unstable features
  should get online ~il[documentation] in these early releases.  Having
  gotten the basic ~il[documentation] in place, I'll document new things as
  they are added, and in response to your pleas I'll try to add
  ~il[documentation] to old things that are widely regarded as important.

  Second, I worry that the existing ~il[documentation] is unhelpful because
  it provides too much or too little detail, or it provides the detail
  too far away from where it is needed.  Please be on the lookout for
  this.  Did you get what you needed when you appealed to ~c[:doc] or
  ~c[:]~ilc[more-doc]?  If not, what was it you needed?  Would more
  cross-references ~il[help]?  Did you get lost in maze of
  cross-references?"

  (list 'doc-fn name 'state))

(defmacro doc! (name)

  ":Doc-Section Documentation

  all the ~il[documentation] for a name (type ~c[:doc! name])~/

  NOTE:  The ~c[:doc!] command only makes sense at the terminal.
  ~bv[]
  Examples:
  ACL2 !>:doc! defthm
  ACL2 !>:doc! certificate
  ~ev[]~/

  This command is like ~c[:doc name] followed by ~c[:]~ilc[more!].  It prints all
  the ~il[documentation] of ~c[name]."

  (list 'doc!-fn name 'state))

(defun more-doc-fn (name state)
  (cond
   ((not (symbolp name))
    (er soft :more-doc
        ":MORE-DOC requires a symbol"))
   (t
    (io? temporary nil (mv erp val state)
         (name)
         (let ((channel (standard-co state))
               (doc-tuple (access-doc-string-data-base name state)))
           (cond ((null doc-tuple)
                  (print-doc-dwim name :more-doc state))
                 (t (pprogn (print-doc doc-tuple 2 (doc-prefix state)
                                       (doc-markup-table state)
                                       (doc-char-subst-table state)
                                       (doc-fmt-alist state)
                                       channel state)
                            (end-doc channel state)))))))))

(defmacro more-doc (name)

  ":Doc-Section Documentation

  a continuation of the ~c[:]~ilc[doc] ~il[documentation]~/

  NOTE:  The ~c[:more-doc] command only makes sense at the terminal.
  ~bv[]
  Examples:
  ACL2 !>:more-doc DEFTHM
  ACL2 !>:more-doc logical-name
  ~ev[]
  Often it is assumed in the text provided by ~c[:more-doc] name that
  you have read the text provided by ~c[:doc name].~/

  ~c[:More-doc] just continues spewing out at you the ~il[documentation] string
  provided with a definition.  If the user has done his job, ~c[:]~ilc[doc] will
  probably remind you of the basics and ~c[:more-doc], if read after ~c[:]~ilc[doc],
  will address obscure details that are nevertheless worth noting.

  When ~c[:more-doc] types ``~c[(type :more for more, :more! for the rest)]''
  you can get the next block of the continuation by typing ~c[:]~ilc[more] or
  all of the remaining blocks by typing ~c[:]~ilc[more!].  ~l[more].~/"

  (list 'more-doc-fn name 'state))

(defun get-doc-section-symbols (alist ans)
  (cond ((null alist) ans)
        (t (get-doc-section-symbols (cdr alist)
                                    (add-to-set-eq (cadar alist) ans)))))

(defun get-docs-apropos1 (pat-lst alist ans)
  (cond ((null alist) ans)
        ((string-search pat-lst (cadddr (car alist)) 'hyphen-is-space)
         (get-docs-apropos1 pat-lst (cdr alist) (cons (car alist) ans)))
        (t (get-docs-apropos1 pat-lst (cdr alist) ans))))

(defun get-docs-apropos (pat alist)
  (reverse (get-docs-apropos1 (normalize-string pat t) alist nil)))

(defun docs-fn (x state)
  (io? temporary nil (mv erp val state)
       (x)
       (let ((channel (standard-co state)))
         (cond
          ((eq x '*)
           (pprogn
            (fms "Documentation Sections~%~*0:DOC sect lists the contents of ~
                  section sect.~%"
                 (list
                  (cons #\0
                        (list "" "~ ~F*~%" "~ ~F*~%" "~ ~F*~%"
                              (merge-sort-alpha-<
                               (get-doc-section-symbols
                                (global-val 'documentation-alist (w state))
                                nil)))))
                 channel state nil)
            (f-put-global 'more-doc-state nil state)
            (end-doc channel state)))
          ((eq x '**)
           (pprogn
            (print-doc-outline-lst
             (merge-sort-alpha-<
              (get-doc-section-symbols
               (global-val 'documentation-alist (w state))
               nil))
             (doc-prefix state)
             (doc-markup-table state)
             (doc-char-subst-table state)
             (doc-fmt-alist state)
             channel
             state)
            (f-put-global 'more-doc-state nil state)
            (end-doc channel state)))
          ((symbolp x)
           (doc-fn x state))
          ((stringp x)
           (let ((doc-tuples
                  (get-docs-apropos x
                                    (global-val 'documentation-alist
                                                (w state)))))
             (pprogn
              (fms "Documentation Topics Apropos ~y0~%"
                   (list (cons #\0 x))
                   channel state nil)
              (print-doc-lst doc-tuples (doc-prefix state)
                             (doc-markup-table state)
                             (doc-char-subst-table state)
                             (doc-fmt-alist state)
                             channel state)
              (newline (standard-co state) state)
              (f-put-global 'more-doc-state nil state)
              (end-doc channel state))))
          (t (er soft :docs "Unrecognized argument, ~x0." x))))))

(defmacro docs (x)

  ":Doc-Section Documentation

  available ~il[documentation] topics (by section)~/

  NOTE:  The ~c[:docs] command only makes sense at the terminal.

  When the ~c[:docs] command is given a ~ilc[stringp] argument it searches the
  text produced by ~c[:]~ilc[doc] and ~c[:]~ilc[more-doc] and lists all the
  documented topics whose text contains the given string.  For purposes of this
  string matching we ignore distinctions of case and the amount and kind (but
  not presence) of white space.  We also treat hyphen as whitespace.

  However, the following examples show how ~c[:docs] can be used on other than
  string patterns.

  ~bv[]
  Examples:
  ACL2 !>:docs *           ; lists documentation sections
  ACL2 !>:docs **          ; lists all documented topics within all sections
  ACL2 !>:docs events      ; lists all topics in section EVENTS
  ACL2 !>:docs \"compil\"    ; lists topics ``apropos''
  ~ev[]~/

  The data base of formatted ~il[documentation] strings is structured into
  sections.  Within a section are topics.  Each topic has a one-liner,
  some notes, and some detailed discussions.  The ~c[:docs] command
  provides a view of the entire data base.

  ~c[:docs] takes one argument, as described below:
  ~bv[]
  arg               effect

  *                 list all section headings in the data base
  **                list all section headings and all topics within
                    each section
  name              list all topics in the section named name (where
                    name is some symbol other than * and **).  This
                    is always the same as :doc name.
  pattern           list all topics whose :doc or :more-doc text
                    mentions the string pattern.  For purposes of this
                    string matching we ignore distinctions of case and
                    the amount and kind (but not presence) of white
                    space.  We also treat hyphen as whitespace.
  ~ev[]~/"

  (list 'docs-fn x 'state))

(defun print-top-doc-topics (doc-alist channel state)
  (cond
   ((endp doc-alist)
    (newline channel state))
   ((eq (car (car doc-alist))
        (cadr (car doc-alist)))
    (pprogn (newline channel state)
            (princ-prefix (doc-prefix state) channel state)
            (princ$ (car (car doc-alist)) channel state)
            (print-top-doc-topics (cdr doc-alist) channel state)))
   (t (print-top-doc-topics (cdr doc-alist) channel state))))

(defun help-fn (state)
  (io? temporary nil (mv erp val state)
       nil
       (let ((channel (standard-co state)))
         (pprogn
          (princ-prefix (doc-prefix state) channel state)
          (princ$ (f-get-global 'acl2-version state) channel state)
          (princ$ " Help.  See also :MORE-DOC help." channel state)
          (newline channel state)

; At one time we printed an outline, and we may choose to do so again some day.
; But for now, we simply print the topics, and a message about them.

;      (print-doc-outline-lst '(events documentation history other)
;                             (doc-prefix state)
;                             (doc-markup-table state)
;                             (doc-char-subst-table state)
;                             (doc-fmt-alist state)
;                             channel state)

          (f-put-global 'more-doc-state nil state)
          (princ-prefix (doc-prefix state) channel state)
          (newline channel state)
          (princ-prefix (doc-prefix state) channel state)
          (princ$
           "For information about name, type :DOC name.  For an introduction"
           channel
           state)
          (newline channel state)
          (princ-prefix (doc-prefix state) channel state)
          (princ$
           "to the ACL2 online documentation, type :DOC documentation.  For"
           channel state)
          (newline channel state)
          (princ-prefix (doc-prefix state) channel state)
          (princ$ "release notes, type :DOC release-notes." channel state)
          (newline channel state)
          (princ-prefix (doc-prefix state) channel state)
          (newline channel state)
          (princ-prefix (doc-prefix state) channel state)
          (princ$ "Type (a!) to abort to the ACL2 top-level from anywhere."
                  channel state)
          (newline channel state)
          (princ-prefix (doc-prefix state) channel state)
          (princ$ "Type (p!) to pop up one ACL2 LD level from anywhere."
                  channel state)
          (newline channel state)
          (princ-prefix (doc-prefix state) channel state)
          (princ$ "The top-level topics in the documentatation are:"
                  channel state)
          (newline channel state)
          (princ-prefix (doc-prefix state) channel state)
          (print-top-doc-topics (global-val 'documentation-alist (w state))
                                channel state)
          (princ$ "*-" channel state)
          (newline channel state)
          (value :invisible)))))

(deflabel q 
  :doc
  ":Doc-Section Other

  quit ACL2 (type ~c[:q]) ~-[] reenter with ~c[(lp)]~/
  ~bv[]
  Example:
  ACL2 !>:Q
  ~ev[]~/

  The keyword command ~c[:q] typed at the top-level of the ACL2 loop will
  terminate the loop and return control to the Common Lisp top-level
  (or, more precisely, to whatever program invoked ~ilc[lp]).  To reenter
  the ACL2 loop, execute ~c[(acl2::lp)] in Common Lisp.  You will be in
  the same state as you were when you exited with ~c[:q], unless during
  your stay in Common Lisp you messed the data structures
  representating the ACL2 ~il[state] (including files, property lists,
  and single-threaded objects).

  Unlike all other keyword commands, typing ~c[:q] is not equivalent to
  invoking the function ~c[q].  There is no function ~c[q].~/")

(defmacro help nil

  ":Doc-Section Documentation

  brief survey of ACL2 features~/
  ~bv[]
  Example:
  ACL2 !>:help
  ~ev[]~/

  ~l[lp] for general information about the top-level ~il[command]
  environment for ACL2."

  '(help-fn state))

(deflabel logical-name
  :doc
  ":Doc-Section Miscellaneous

  a name created by a logical event~/
  ~bv[]
  Examples:
  assoc
  caddr
  +
  \"ACL2-USER\"
  \"arith\"
  \"project/task-1/arith.lisp\"
  :here
  ~ev[]~/

  A logical name is either a name introduced by some event, such as
  ~ilc[defun], ~ilc[defthm], or ~ilc[include-book], or else is the keyword ~c[:here], which
  refers to the most recent such event.  ~l[events].  Every
  logical name is either a symbol or a string.  For the syntactic
  rules on names, ~pl[name].  The symbols name functions, macros,
  constants, axioms, theorems, labels, and ~il[theories].  The strings name
  packages or ~il[books].  We permit the keyword symbol ~c[:here] to be used as
  a logical name denoting the most recently completed event.

  The logical name introduced by an ~il[include-book] is the full book name
  string for the book (~pl[full-book-name]).  Thus, under the
  appropriate setting for the current book directory (~pl[cbd])
  the event ~c[(include-book \"arith\")] may introduce the logical name
  ~bv[]
  \"/usr/home/smith/project/task-1/arith.lisp\" .
  ~ev[]
  Under a different ~ilc[cbd] setting, it may introduce a different
  logical name, perhaps
  ~bv[]
  \"/local/src/acl2/library/arith.lisp\" .
  ~ev[]
  It is possible that identical ~ilc[include-book] events forms in a
  session introduce two different logical names because of the current
  book directory.

  A logical name that is a string is either a package name or a book
  name.  If it is not a package name, we support various conventions
  to interpret it as a book name.  If it does not end with the string
  ~c[\".lisp\"] we extend it appropriately.  Then, we search for any book
  name that has the given logical name as a terminal substring.
  Suppose ~c[(include-book \"arith\")] is the only ~il[include-book] so far and
  that ~c[\"/usr/home/smith/project/task-1/arith.lisp\"] is the source
  file it processed.  Then ~c[\"arith\"], ~c[\"arith.lisp\"] and
  ~c[\"task-1/arith.lisp\"] are all logical names identifying that
  ~ilc[include-book] event (unless they are package names).  Now suppose a
  second ~c[(include-book \"arith\")] is executed and processes
  ~c[\"/local/src/acl2/library/arith.lisp\"].  Then ~c[\"arith\"] is no longer
  a logical name, because it is ambiguous.  However, ~c[\"task-1/arith\"]
  is a logical name for the first ~ilc[include-book] and ~c[\"library/arith\"]
  is a logical name for the second.  Indeed, the first can be named by
  ~c[\"1/arith\"] and the second by ~c[\"y/arith\"].

  Logical names are used primarily in the theory manipulation
  functions, e.g., ~ilc[universal-theory] and ~ilc[current-theory] with which you
  may obtain some standard ~il[theories] as of some point in the historical
  past.  The reference points are the introductions of logical names,
  i.e., the past is determined by the ~il[events] it contains.  One might
  ask, ``Why not discuss the past with the much more flexible language
  of ~il[command] descriptors?'' (~l[command-descriptor].)  The reason
  is that inside of such ~il[events] as ~ilc[encapsulate] or macro ~il[command]s that
  expand to ~ilc[progn]s of ~il[events], ~il[command] descriptors provide too coarse a
  grain.

  When logical names are used as referents in theory expressions used
  in ~il[books], one must consider the possibility that the defining event
  within the book in question becomes redundant by the definition of
  the name prior to the assumption of the book.
  ~l[redundant-events].~/")

(deflabel command
  :doc
  ":Doc-Section Miscellaneous

  forms you type at the top-level, but...~/

  ...the word ``command'' usually refers to a top-level form whose
  evaluation produces a new logical ~il[world].
  ~bv[]
  Typical commands are:
  (defun foo (x) (cons x x))
  (defthm consp-foo (consp (foo x)))
  (defrec pair (hd . tl) nil)
  ~ev[]
  The first two forms are examples of commands that are in fact
  primitive ~il[events].  ~l[events].  ~c[Defrec], on the other hand, is a
  macro that expands into a ~ilc[progn] of several primitive ~il[events].  In
  general, a ~il[world] extending command generates one or more ~il[events].~/

  Both ~il[events] and commands leave landmarks on the ~il[world] that enable us
  to determine how the given ~il[world] was created from the previous one.
  Most of your interactions will occur at the command level, i.e., you
  type commands, you print previous commands, and you undo back
  through commands.  Commands are denoted by command descriptors.
  ~l[command-descriptor].~/")

(deflabel command-descriptor
  :doc
  ":Doc-Section Miscellaneous

  an object describing a particular ~il[command] typed by the user~/
  ~bv[]
  Examples:

  :max      ; the command most recently typed by the user
  :x        ; synonymous with :max
  (:x -1)   ; the command before the most recent one
  (:x -2)   ; the command before that
  :x-2      ; synonymous with (:x -2)
  5         ; the fifth command typed by the user
  1         ; the first command typed by the user
  0         ; the last command of the system initialization
  -1        ; the next-to-last initialization command
  :min      ; the first command of the initialization
  :start    ; the last command of the initial ACL2 logical world
  fn        ; the command that introduced the logical name fn
  (:search (defmacro foo-bar))
            ; the first command encountered in a search from :max to
            ; 0 that either contains defmacro and foo-bar in the 
            ; command form or contains defmacro and foo-bar in some 
            ; event within its block.
  ~ev[]~/

  The recorded ~il[history] of your interactions with the top-level ACL2
  ~il[command] loop is marked by the ~il[command]s you typed that changed the
  logical ~il[world].  Each such ~il[command] generated one or more ~il[events],
  since the only way for you to change the logical ~il[world] is to execute
  an event function.  ~l[command] and ~pl[events].  We divide
  ~il[history] into ``~il[command] blocks,'' grouping together each ~il[world]
  changing ~il[command] and its ~il[events].  A ``~il[command] descriptor'' is an
  object that can be used to describe a particular ~il[command] in the
  ~il[history] of the ongoing session.

  Each ~il[command] is assigned a unique integer called its ``~il[command]
  number'' which indicates the ~il[command]'s position in the chronological
  ordering of all of the ~il[command]s ever executed in this session
  (including those executed to initialize the system).  We assign the
  number 1 to the first ~il[command] you type to ACL2.  We assign 2 to the
  second and so on.  The non-positive integers are assigned to
  ``prehistoric'' ~il[command]s, i.e., the ~il[command]s used to initialize the
  ACL2 system: 0 is the last ~il[command] of the initialization, -1 is the
  one before that, etc.

  The legal ~il[command] descriptors are described below.  We use ~c[n] to
  denote any integer, ~c[sym] to denote any logical name
  (~pl[logical-name]), and ~c[cd] to denote, recursively, any ~il[command]
  descriptor.
  ~bv[]
   command                   command
  descriptor                described

  :max   -- the most recently executed command (i.e., the one with
            the largest command number)
  :x     -- synonymous with :max
  :x-k   -- synonymous with (:x -k), if k is an integer and k>0
  :min   -- the earliest command (i.e., the one with the smallest
            command number and hence the first command of the system
            initialization)
  :start -- the last command when ACL2 starts up
  n      -- command number n  (If n is not in the
            range :min<=n<=:max, n is replaced by the nearest of :min
            and :max.)
  sym    -- the command that introduced the logical name sym
  (cd n) -- the command whose number is n plus the command number of
            the command described by cd
  (:search pat cd1 cd2)
            In this command descriptor, pat must be either an atom or
            a true list of atoms and cd1 and cd2 must be command
            descriptors.  We search the interval from cd1 through cd2
            for the first command that matches pat.  Note that if cd1
            occurs chronologically after cd2, the search is
            ``backwards'' through history while if cd1 occurs
            chronologically before cd2, the search is ``forwards''.  A
            backwards search will find the most recent match; a
            forward search will find the chronologically earliest
            match.  A command matches pat if either the command form
            itself or one of the events in the block contains pat (or
            all of the atoms in pat if pat is a list).
  (:search pat)
            the command found by (:search pat :max 0), i.e., the most
            recent command matching pat that was part of the user's
            session, not part of the system initialization.
  ~ev[]")

(defun trans-fn (form state)
  (io? temporary nil (mv erp val state)
       (form)
       (let ((wrld (w state))
             (channel (standard-co state)))
         (mv-let (flg val bindings state)
                 (translate1 form
                             :stobjs-out
                             '((:stobjs-out . :stobjs-out))
                             t ;;; known-stobjs = t (user interface)
                             'top-level wrld state)
                 (cond ((null flg)
                        (pprogn
                         (fms "~Y01~%=> ~y2~|~%"
                              (list
                               (cons #\0 val)
                               (cons #\1 (term-evisc-tuple nil state))
                               (cons #\2
                                     (prettyify-stobjs-out
                                      (translate-deref :stobjs-out bindings))))
                              channel state nil)
                         (value :invisible)))
                       (t
                        (er soft 'trans
                            ":Trans has failed.  Consider trying :trans! ~
                             instead; see :DOC trans!.")))))))

(defun trans!-fn (form state)
  (io? temporary nil (mv erp val state)
       (form)
       (let ((wrld (w state))
             (channel (standard-co state)))
         (mv-let (flg val bindings state)
                 (translate1 form
                             t
                             nil
                             t ;;; known-stobjs = t (user interface)
                             'top-level wrld state)
                 (declare (ignore bindings))
                 (cond ((null flg)
                        (pprogn
                         (fms "~Y01~|~%"
                              (list (cons #\0 val)
                                    (cons #\1 (term-evisc-tuple nil state)))
                              channel state nil)
                         (value :invisible)))
                       (t (value :invisible)))))))

(defmacro trans (form)

  ":Doc-Section Other

  print the macroexpansion of a form~/
  ~bv[]
  Examples:
  :trans (list a b c)
  :trans (caddr x)
  :trans (cond (p q) (r))
  ~ev[]~/

  This function takes one argument, an alleged term, and translates
  it, expanding the macros in it completely.  Either an error is
  caused or the formal meaning of the term is printed.  We also print
  the ``output signature'' which indicates how many results are returned
  and which are single-threaded objects.  For example,
  a term that returns one ordinary object (e.g., an object other than
  ~ilc[STATE] or a user-defined single-threaded object (~pl[defstobj]))
  has the output signature 
  ~bv[]
  => *
  ~ev[]
  A term that returns the single-threaded object ~c[STATE] has the
  output signature
  ~bv[]
  => STATE
  ~ev[]
  and a term that returns four results might have the output signature
  ~bv[]
  => (MV $MEM * * STATE)
  ~ev[]
  This signature indicates that the first result is the (user defined)
  single-threaded object ~c[$MEM], that the next two results are ordinary,
  and that the last result is ~c[STATE].

  ~l[trans!] for a corresponding command that does not enforce restrictions of
  single-threaded objects.

  It is sometimes more convenient to use ~ilc[trans1] which is like trans
  but which only does top-level macroexpansion.

  For more, ~pl[term].~/"

  (list 'trans-fn form 'state))

(defmacro trans! (form)

  ":Doc-Section Other

  print the macroexpansion of a form without single-threadedness concerns~/
  ~bv[]
  Examples:
  :trans! (list a b c)
  :trans! (append x state)
  ~ev[]~/

  ~c[:Trans!] is identical to ~c[:]~ilc[trans], except that unlike ~c[:trans],
  ~c[:trans!] ignores single-threadedness restrictions.  Thus, the second form
  above is legal for ~c[:trans!].  Also ~pl[trans] and ~pl[trans1].~/"

  (list 'trans!-fn form 'state))

(defun trans1-fn (form state)
  (if (and (consp form)
           (true-listp form)
           (symbolp (car form))
           (getprop (car form) 'macro-body nil 'current-acl2-world (w state)))
      (macroexpand1 form 'top-level state)
    (er soft 'top-level
        "TRANS1 may only be applied to a non-atom form that begins with a ~
         symbol with a 'macro-body property.")))

(defmacro trans1 (form)

  ":Doc-Section Other

  print the one-step macroexpansion of a form~/
  ~bv[]
  Examples:
  :trans1 (list a b c)
  :trans1 (caddr x)
  :trans1 (cond (p q) (r))
  ~ev[]~/

  This function takes one argument, an alleged term, and expands the
  top-level macro in it for one step only.  Either an error is caused,
  which happens when the form is not a call of a macro, or the result
  is printed.  Also ~pl[trans], which translates the given form
  completely.~/"

  `(trans1-fn ,form state))

(defun tilde-*-props-fn-phrase1 (alist)
  (cond ((null alist) nil)
        (t (cons (msg "~y0~|~ ~y1~|"
                      (caar alist)
                      (cdar alist))
                 (tilde-*-props-fn-phrase1 (cdr alist))))))

(defun tilde-*-props-fn-phrase (alist)
  (list "none" "~@*" "~@*" "~@*"
        (tilde-*-props-fn-phrase1 alist)))

(defun props-fn (sym state)
  (cond ((symbolp sym)
         (io? temporary nil (mv erp val state)
              (sym)
              (pprogn
               (fms "ACL2 Properties of ~y0:~%~*1~%"
                    (list (cons #\0 sym)
                          (cons #\1
                                (tilde-*-props-fn-phrase
                                 (getprops sym
                                           'current-acl2-world
                                           (w
                                            state)))))
                    (standard-co state)
                    state
                    (ld-evisc-tuple state))
               (value :invisible))))
        (t (er soft :props
               "~x0 is not a symbol."
               sym))))

(defmacro props (sym)

  ":Doc-Section Other

  print the ACL2 properties on a symbol~/
  ~bv[]
  Example:
  :props assoc-eq
  ~ev[]~/

  ~c[Props] takes one argument, a symbol, and prints all of the properties
  that are on that symbol in the ACL2 ~il[world].~/"

  (list 'props-fn sym 'state))

(deflabel enter-boot-strap-mode

; WARNING: There is an interface-raw.lisp function of the same name!
; We document this label because the user poking around with :pc will
; come across this name.

  :doc
  ":Doc-Section Miscellaneous

  The first millisecond of the Big Bang~/

  ACL2 functions, e.g., ~ilc[if], that show ~c[enter-boot-strap-mode] as their
  defining ~il[command] are in fact primitives.  It is impossible for the
  system to display defining axioms about these symbols.~/

  ~c[Enter-boot-strap-mode] is a Common Lisp function but not an ACL2
  function.  It magically creates from ~c[nil] an ACL2 property list ~il[world]
  that lets us start the boot-strapping process.  That is, once
  ~c[enter-boot-strap-mode] has created its ~il[world], it is possible to
  process the ~ilc[defconst]s, ~ilc[defun]s, and ~ilc[defaxiom]s, necessary to bring up
  the rest of the system.  Before that ~il[world] is created, the attempt
  by ACL2 even to translate a ~ilc[defun] form, say, would produce an error
  because ~ilc[defun] is undefined.

  Several ACL2 functions show ~c[enter-boot-strap-mode] as their defining
  ~il[command].  Among them are ~ilc[if], ~ilc[cons], ~ilc[car], and ~ilc[cdr].  These functions
  are characterized by axioms rather than definitional equations ~-[]
  axioms that in most cases are built into our code and hence do not
  have any explicit representation among the rules and formulas in the
  system.")

(deflabel exit-boot-strap-mode

; WARNING: There is an interface-raw.lisp function of the same name!
; We document this label because the user poking around with :pc will
; come across this name.

  :doc
  ":Doc-Section Miscellaneous

  the end of pre-history~/

  ~c[Exit-boot-strap-mode] is the last step in creating the ACL2 ~il[world] in
  which the user lives.  It has ~il[command] number ~c[0].  ~il[Command]s before it
  are part of the system initialization and extend all the way back to
  ~c[:]~ilc[min].  ~il[Command]s after it are those of the user.~/

  ~c[Exit-boot-strap-mode] is a Common Lisp function but not an ACL2
  function.  It is called when every ~ilc[defconst], ~ilc[defun], etc., in our
  source code has been processed under ACL2 and the ~il[world] is all but
  complete.  ~c[exit-boot-strap-mode] has only one job: to signal the
  completion of the boot-strapping.")

; We now develop walkabout, an extremely useful tool for exploring 

(defun walkabout-nth (i x)

; Enumerate the elements of the print representation of the list x,
; from 0.  Include the possible dot as an element.

;      Example x                  Example x
;      (a b c . d)                (a b c d)
; i     0 1 2 3 4                  0 1 2 3

; We fetch the ith element.  But how do we return the dot?  We
; actually return two values (mv dotp xi).  If dotp is true, we're
; really returning the dot.  In this case xi is the character #\.,
; just in case we want to pretend there was a dot there and try
; to go into it or return it.  If dotp is false, then xi is the
; corresponding element of x.

  (cond ((int= i 0)
         (cond ((atom x)
                (mv t #\.))
               (t (mv nil (car x)))))
        ((atom x) (mv nil x))
        (t (walkabout-nth (1- i) (cdr x)))))

(defun walkabout-ip (i x)

; See the examples above showing how we enumerate the elements of the
; print representation of x.  We return t if i is a legal index
; and nil otherwise.

  (cond ((null x) nil)
        ((atom x) (or (int= i 0) (int= i 1)))
        ((int= i 0) t)
        (t (walkabout-ip (1- i) (cdr x)))))

(defun walkabout-huh (state)
  (pprogn (princ$ "Huh?" *standard-co* state)
          (newline *standard-co* state)
          (mv 'continue nil state)))

(defun walkabout1 (i x state intern-flg evisc-tuple alt-evisc-tuple)

; X is a list and we are at position i within it.  This function
; reads commands from *standard-oi* and moves us around in x.  This
; function is inefficient in that it computes the current object,
; xi, from i and x each time.  It would be better to maintain the
; current tail of x so nx could be fast.

  (mv-let
   (dotp xi)
   (walkabout-nth i x)
   (pprogn
    (mv-let (col state)
            (fmt1 (if dotp ".~%:" "~y0~|:")
                  (list (cons #\0 xi))
                  0
                  *standard-co* state
                  (if (eq alt-evisc-tuple :none)
                      evisc-tuple
                    alt-evisc-tuple))
            (declare (ignore col))
            state)
    (mv-let
     (signal val state)
     (mv-let
      (erp obj state)
      (state-global-let*
       ((infixp nil))
       (read-object *standard-oi* state))
      (cond
       (erp (mv 'exit nil state))
       (t (case (if intern-flg
                    (intern (symbol-name obj) "ACL2")
                    obj)
                (nx (if (walkabout-ip (1+ i) x)
                        (mv 'continue (1+ i) state)
                        (walkabout-huh state)))
                (bk (if (= i 0)
                        (walkabout-huh state)
                        (mv 'continue (1- i) state)))
                (0 (mv 'up nil state))
                (pp (mv 'continue-fullp nil state))
                (= (mv 'exit xi state))
                (q (mv 'exit :invisible state))
                (otherwise
                 (cond
                  ((and (integerp obj) (> obj 0))
                   (cond
                    ((atom xi)
                     (walkabout-huh state))
                    ((walkabout-ip (1- obj) xi)
                     (walkabout1 (1- obj) xi state intern-flg evisc-tuple
                                 :none))
                    (t (walkabout-huh state))))
                  ((and (consp obj)
                        (eq (car obj) 'pp))
                   (mv-let (print-level print-length)
                           (let ((args (cdr obj)))
                             (case-match args
                               ((print-level print-length)
                                (mv print-level print-length))
                               ((n) (mv n n))
                               (& (mv :bad nil))))
                           (cond ((and (or (natp print-level)
                                           (null print-level))
                                       (or (natp print-length)
                                           (null print-length)))
                                  (mv 'continue-fullp
                                      (evisc-tuple print-level print-length
                                                   nil nil)
                                      state))
                                 (t (walkabout-huh state)))))
                  ((and (consp obj)
                        (eq (car obj) '=)
                        (consp (cdr obj))
                        (symbolp (cadr obj))
                        (null (cddr obj)))
                   (pprogn
                    (f-put-global 'walkabout-alist
                                  (cons (cons (cadr obj) xi)
                                        (f-get-global 'walkabout-alist
                                                      state))
                                  state)
                    (mv-let (col state)
                            (fmt1 "(walkabout= ~x0) is~%"
                                  (list (cons #\0 (cadr obj)))
                                  0 *standard-co* state (ld-evisc-tuple state))
                            (declare (ignore col))
                            (mv 'continue nil state))))
                  (t (walkabout-huh state))))))))
     (cond
      ((eq signal 'continue)
       (walkabout1 (or val i) x state intern-flg evisc-tuple :none))
      ((eq signal 'up)
       (mv 'continue nil state))
      ((eq signal 'continue-fullp)
       (walkabout1 i x state intern-flg evisc-tuple val))
      (t (mv 'exit val state)))))))

(defun walkabout (x state)

  ":Doc-Section Other

  explore an ACL2 cons tree~/

  By typing ~c[(walkabout x state)] for an ACL2 term ~c[x] whose value is a
  ~ilc[cons] tree, you can walk around that tree.  For example, ACL2 developers
  often use this utility to explore the ACL2 logical ~il[world].~/

  When you issue a ~c[walkabout] command, a summary of commands will be printed
  before you enter an interactive loop.
  ~bv[]
  Commands:
  0, 1, 2, ..., nx, bk, pp, (pp n), (pp lev len), =, (= symb), and q.
  ~ev[]
  In the interactive ~c[walkabout] loop, a positive integer n takes you to the
  nth position, while 0 takes you up a level.  The commands ~c[nx] and ~c[bk]
  take you to the next and previous position, respectively, at the same level.
  The command ~c[pp] prints the current object in full, while
  ~c[(pp level length)] hides sub-objects below the indicated level and past
  the indicated length, if non-~c[nil]; ~pl[evisc-tuple].  The command
  ~c[(pp n)] abbreviates ~c[(pp n n)], so in particular ~c[(pp nil)] is
  equivalent to ~c[pp].

  The following example illustrates the commands described above.
  ~bv[]
  ACL2 !>(walkabout (append '(a (b1 b2 b3)) '(c d e f)) state)

  Commands:
  0, 1, 2, ..., nx, bk, pp, (pp n), (pp lev len), =, (= symb), and q.

  (A (B1 B2 B3) C ...)
  :2
  (B1 B2 B3)
  :3
  B3
  :0
  (B1 B2 B3)
  :nx
  C
  :nx
  D
  :0
  (A (B1 B2 B3) C ...)
  :pp
  (A (B1 B2 B3) C D E F)
  :(pp 4)
  (A (B1 B2 B3) C D ...)
  :(pp 1 4)
  (A # C D ...)
  :(pp nil 2)
  (A (B1 B2 ...) ...)
  :q
  ACL2 !>
  ~ev[]

  Finally we describe the commands ~c[q], ~c[=], and ~c[(= symb)], where
  ~c[symb] is a symbol.  The command ~c[q] simply causes an exit from the
  ~c[walkabout] loop.  The command ~c[=] also exits, but causes the current
  object to be printed in full.  The command ~c[(= symb)] saves an association
  of ~c[symb] with the current object, which can be retrieved outside the
  ~c[walkabout] loop using the macro ~c[walkabout=], as illustrated below.
  ~bv[]
  :2
  (B1 B2 B3)
  :(= my-list)
  (walkabout= MY-LIST) is
  (B1 B2 B3)
  :q
  ACL2 !>(walkabout= MY-LIST)
  (B1 B2 B3)
  ACL2 !>
  ~ev[]

  Finally, we remark that for trees that are not true-lists, ~c[walkabout]
  treats the dot as an object that can be ``walked about''.  The following
  example illustrates this point.
  ~bv[]
  ACL2 !>(walkabout '(c d e . f) state)

  Commands:
  0, 1, 2, ..., nx, bk, pp, (pp n), (pp lev len), =, (= symb), and q.

  (C D E . F)
  :3
  E
  :nx
  .
  :nx
  F
  :0
  (C D E . F)
  :4
  .
  :0
  (C D E . F)
  :5
  F
  :
  ~ev[]~/"

  (pprogn
   (fms "Commands:~|0, 1, 2, ..., nx, bk, pp, (pp n), (pp lev len), =, (= ~
         symb), and q.~%~%"
        nil *standard-co* state nil)
   (mv-let (signal val state)
           (walkabout1 0 (list x)
                       state
                       (not (equal (current-package state) "ACL2"))
                       (evisc-tuple 2 3 nil nil)
                       :none)
           (declare (ignore signal))
           (value val))))

(defun walkabout=-fn (var state)
  (cond ((symbolp var)
         (cdr (assoc-eq var (f-get-global 'walkabout-alist state))))
        (t nil)))

(defmacro walkabout= (var)
  `(walkabout=-fn ',var state))

; Here we develop the code for inspecting the results of using OBDDs.

(defun lookup-bddnote (cl-id bddnotes)
  (cond
   ((endp bddnotes) nil)
   ((equal cl-id (access bddnote (car bddnotes) :cl-id))
    (car bddnotes))
   (t (lookup-bddnote cl-id (cdr bddnotes)))))

(defun update-bddnote-with-term (cl-id term bddnotes)
  (cond
   ((endp bddnotes)
    (er hard 'update-bddnote-with-term
        "Expected to find clause with name ~@0, but did not!"
        (tilde-@-clause-id-phrase cl-id)))
   ((equal cl-id (access bddnote (car bddnotes) :cl-id))
    (cons (change bddnote (car bddnotes)
                  :term term)
          (cdr bddnotes)))
   (t (cons (car bddnotes)
            (update-bddnote-with-term cl-id term (cdr bddnotes))))))

(defmacro show-bdd (&optional str
                              goal-query-response
                              counterex-query-response
                              term-query-response)

; Not documented below is our use of evisc-tuples that hardwire the print-level
; and print-length, rather than using say the abbrev-evisc-tuple.  That seems
; reasonable given the design of show-bdd, which allows printing terms in full
; after the user sees their abbreviated versions.  It could add more confusion
; than clarity for us to add such documentation below, but if anyone complains,
; then we should probably do so.

  ":Doc-Section Bdd

  inspect failed BDD proof attempts~/

  Attempts to use BDDs (~pl[bdd]), using ~c[:]~ilc[bdd] ~il[hints],
  can fail for various reasons.  Sometimes it is useful to explore
  such failures.  To do so, one may simply execute the form
  ~bv[]
  (show-bdd)
  ~ev[]
  inside the ACL2 loop.  The system's response is generally
  self-explanatory.  Perhaps you have already seen ~c[show-bdd] used in
  some examples (~pl[bdd-introduction] and ~pl[if*]).  Here we
  give some details about ~c[show-bdd].~/

  ~c[(Show-bdd)] prints the goal to which the BDD procedure was applied
  and reports the number of nodes created during the ~il[BDD]
  computation, followed by additional information depending on whether
  or not the computation ran to completion or aborted (for reasons
  explained elsewhere; ~pl[bdd-algorithm]).  If the computation
  did abort, a backtrace is printed that should be useful in
  understanding where the problem lies.  Otherwise, ~c[(show-bdd)]
  prints out ``falsifying constraints.''  This list of pairs
  associates ~il[term]s with values and suggests how to construct a
  binding list for the variables in the conjecture that will falsify
  the conjecture.  It also prints out the ~il[term] that is the result
  of simplifying the input ~il[term].  In each of these cases, parts
  of the object may be hidden during printing, in order to avoid
  creating reams of uninteresting output.  If so, the user will be
  queried about whether he wishes to see the entire object (alist or
  ~il[term]), which may be quite large.  The following responses are
  legal:
  ~bq[]
  ~c[  w] ~-[] Walk around the object with a structure editor

  ~c[  t] ~-[] Print the object in full

  ~c[nil] ~-[] Do not print any more of the object
  ~eq[]

  ~c[Show-bdd] actually has four optional arguments, probably rarely
  used.  The general form is
  ~bv[]
  (show-bdd goal-name goal-ans falsifying-ans term-ans)
  ~ev[]
  where ~c[goal-name] is the name of the goal on which the ~c[:]~ilc[bdd]
  hint was used (or, ~c[nil] if the system should find such a goal),
  ~c[goal-ans] is the answer to be used in place of the query for
  whether to print the input goal in full, ~c[falsifying-ans] is the
  answer to be used in place of the query for whether to print the
  falsifying constraints in full, and ~c[term-ans] is the answer to be
  used in place of the query for whether to print the resulting
  ~il[term] in full."

  (cond
   ((not (symbolp goal-query-response))
    `(er soft 'show-bdd
         "The optional second argument of show-bdd must be a symbol, but ~x0 ~
          is not."
         ',goal-query-response))
   ((not (symbolp counterex-query-response))
    `(er soft 'show-bdd
         "The optional third argument of show-bdd must be a symbol, but ~x0 ~
          is not."
         ',counterex-query-response))
   ((not (symbolp term-query-response))
    `(er soft 'show-bdd
         "The optional fourth argument of show-bdd must be a symbol, but ~x0 ~
          is not."
         ',term-query-response))
   (t
    `(show-bdd-fn ,str
                  ',goal-query-response
                  ',counterex-query-response
                  ',term-query-response
                  state))))

(defun show-bdd-goal (query-response bddnote chan state)
  (let* ((goal (untranslate (access bddnote bddnote :goal-term) t (w state))))
    (pprogn
     (fms "BDD input term (derived from ~@1):~|"
          (list (cons #\1 (tilde-@-clause-id-phrase
                           (access bddnote bddnote :cl-id))))
          (standard-co state) state nil)
     (cond
      (query-response
       state)
      (t
       (fms "~q2~|"
            (list (cons #\2 goal))
            (standard-co state) state (evisc-tuple 5 7 nil nil))))
     (cond
      ((equal goal (eviscerate-simple goal 5 7 nil
                                      (table-alist 'evisc-table (w state))
                                      nil))
       state)
      (t
       (mv-let (erp ans state)
               (if query-response
                   (let ((query-response
                          (intern (symbol-name query-response) "KEYWORD")))
                     (value (case query-response
                                  (:w :w)
                                  (:nil nil)
                                  (otherwise t))))
                 (acl2-query
                  :show-bdd
                  '("Print the goal in full?"
                    :n nil :y t :w :w
                    :? ("Y will print the goal in full.  W will put you in a ~
                         structural display editor that lets you type a ~
                         positive integer N to dive to the Nth element of the ~
                         current list, 0 to go up a level, PP to print the ~
                         current object in full, and Q to quit."
                        :n nil :y t :w :w))
                  nil
                  state))
               (declare (ignore erp))
               (cond ((eq ans :w)
                      (mv-let (erp ans state)
                              (walkabout goal state)
                              (declare (ignore erp ans))
                              state))
                     (ans (fms "~x0~|"
                               (list (cons #\0 goal))
                               chan state nil))
                     (t state))))))))

(defun merge-car-term-order (l1 l2)
  (cond ((null l1) l2)
        ((null l2) l1)
        ((term-order (car (car l1)) (car (car l2)))
         (cons (car l1) (merge-car-term-order (cdr l1) l2)))
        (t (cons (car l2) (merge-car-term-order l1 (cdr l2))))))

(defun merge-sort-car-term-order (l)
  (cond ((null (cdr l)) l)
        (t (merge-car-term-order (merge-sort-car-term-order (evens l))
                                 (merge-sort-car-term-order (odds l))))))

(defun falsifying-pair-p (term val asst)
  (cond
   ((endp asst) nil)
   ((equal term (caar asst))
    (or (and (null val) (equal (cadar asst) *some-non-nil-value*))
        (and (null (cadar asst)) (equal val *some-non-nil-value*))
        (falsifying-pair-p term val (cdr asst))))
   (t nil)))

(defun bogus-falsifying-assignment-var (asst)

; Asst is assumed to be sorted by car.

  (cond
   ((endp asst) nil)
   ((falsifying-pair-p (caar asst) (cadar asst) (cdr asst))
    (caar asst))
   (t
    (bogus-falsifying-assignment-var (cdr asst)))))

(defun show-falsifying-assignment (query-response bddnote chan state)
  (let ((cst (access bddnote bddnote :cst)))
    (cond
     ((cst-tp cst)
      (fms "There is no falsifying assignment, since ~@0 was proved."
           (list (cons #\0 (tilde-@-clause-id-phrase
                            (access bddnote bddnote :cl-id))))
           chan state nil))
     (t
      (let ((asst (falsifying-assignment
                   cst
                   (access bddnote bddnote :mx-id))))
        (pprogn (let ((var (bogus-falsifying-assignment-var
                            (merge-sort-car-term-order asst))))
                  (cond (var (fms "WARNING:  The term ~p0 is assigned both to ~
                                   nil and a non-nil value in the following ~
                                   assignment.  This generally occurs because ~
                                   the term is not known to be Boolean.  ~
                                   Consider adding appropriate booleanp or ~
                                   boolean-listp hypotheses. See :DOC ~
                                   bdd-introduction."
                                  (list (cons #\0 var))
                                  (standard-co state) state
                                  (evisc-tuple 5 7 nil nil)))
                        (t state)))
                (fms "Falsifying constraints:~%"
                     nil chan state nil)
                (cond
                 (query-response
                  state)
                 (t
                  (fms "~x0~|"
                       (list (cons #\0 asst))
                       chan state
                       (evisc-tuple 5 (max 7 (length asst)) nil nil))))
                (cond
                 ((equal asst
                         (eviscerate-simple
                          asst 5 (max 7 (length asst)) nil
                          (table-alist 'evisc-table (w state))
                          nil))
                  state)
                 (t
                  (mv-let
                   (erp ans state)
                   (if query-response
                       (let ((query-response
                              (intern (symbol-name query-response) "KEYWORD")))
                         (value (case query-response
                                      (:w :w)
                                      (:nil nil)
                                      (otherwise t))))
                     (acl2-query
                      :show-bdd
                      '("Print the falsifying constraints in full?"
                        :n nil :y t :w :w
                        :? ("Y will print the constraints in full.  W will put ~
                             you in a structural display editor that lets you ~
                             type a positive integer N to dive to the Nth ~
                             element of the current list, 0 to go up a level, ~
                             PP to print the current object in full, and Q to ~
                             quit."
                            :n nil :y t :w :w))
                      nil
                      state))
                   (declare (ignore erp))
                   (cond ((eq ans :w)
                          (mv-let (erp ans state)
                                  (walkabout asst state)
                                  (declare (ignore erp ans))
                                  state))
                         (ans (fms "~x0~|"
                                   (list (cons #\0 asst))
                                   chan state nil))
                         (t state)))))))))))

(defun show-bdd-term (query-response bddnote chan state)
  (let* ((orig-term (access bddnote bddnote :term))
         (term (if orig-term
                   orig-term
                 (mv-let (term cst-array)
                         (decode-cst (access bddnote bddnote
                                             :cst)
                                     (leaf-cst-list-array
                                      (access bddnote bddnote
                                              :mx-id)))
                         (declare (ignore cst-array))
                         term))))
    (pprogn
     (cond ((null orig-term)
            (f-put-global 'bddnotes
                          (update-bddnote-with-term
                           (access bddnote bddnote :cl-id)
                           term
                           (f-get-global 'bddnotes state))
                          state))
           (t state))
     (fms "Term obtained from BDD computation on ~@1:~|"
          (list (cons #\1 (tilde-@-clause-id-phrase
                           (access bddnote bddnote :cl-id))))
          (standard-co state) state nil)
     (cond
      (query-response
       state)
      (t
       (fms "~x2~|"
            (list (cons #\2 term))
            (standard-co state) state (evisc-tuple 5 7 nil nil))))
     (cond
      ((equal term (eviscerate-simple term 5 7 nil
                                      (table-alist 'evisc-table (w state))
                                      nil))
       state)
      (t
       (mv-let (erp ans state)
               (if query-response
                   (let ((query-response
                          (intern (symbol-name query-response) "KEYWORD")))
                     (value (case query-response
                                  (:w :w)
                                  (:nil nil)
                                  (otherwise t))))
                 (acl2-query
                  :show-bdd
                  '("Print the term in full?"
                    :n nil :y t :w :w
                    :? ("Y will print the term in full.  W will put you in a ~
                         structural display editor that lets you type a ~
                         positive integer N to dive to the Nth element of the ~
                         current list, 0 to go up a level, PP to print the ~
                         current object in full, and Q to quit."
                        :n nil :y t :w :w))
                  nil
                  state))
               (declare (ignore erp))
               (cond ((eq ans :w)
                      (mv-let (erp ans state)
                              (walkabout term state)
                              (declare (ignore erp ans))
                              state))
                     (ans (fms "~x0~|"
                               (list (cons #\0 term))
                               chan state nil))
                     (t state))))))))

(defun tilde-*-substitution-phrase1 (alist is-replaced-by-str evisc-tuple wrld)
  (cond ((null alist) nil)
        (t (cons (msg "~P01 ~s2 ~P31"
                      (untranslate (caar alist) nil wrld)
                      evisc-tuple
                      is-replaced-by-str
                      (untranslate (cdar alist) nil wrld))
                 (tilde-*-substitution-phrase1 (cdr alist)
                                               is-replaced-by-str
                                               evisc-tuple wrld)))))

(defun tilde-*-substitution-phrase (alist is-replaced-by-str evisc-tuple wrld)
  (list* "" "~@*" "~@* and " "~@*, "
         (tilde-*-substitution-phrase1 alist is-replaced-by-str evisc-tuple
                                       wrld)
         nil))

(defun show-bdd-backtrace (call-stack cst-array chan state)
  (cond
   ((endp call-stack)
    state)
   (t (mv-let
       (term-list cst-array)
       (decode-cst-lst
        (strip-cdrs (cdar call-stack))
        cst-array)
       (let ((term (untranslate (caar call-stack) nil (w state)))
             (alist (pairlis$ (strip-cars (cdar call-stack))

; Once upon a time we untranslate term-list below, but
; tilde-*-substitution-phrase does an untranslate.

                              term-list)))
         (pprogn
          (fms "~X02~|  alist: ~*1~|"
               (list (cons #\0 term)
                     (cons #\1 (tilde-*-substitution-phrase
                                alist
                                ":="
                                (evisc-tuple 5 (max 7 (length alist))
                                             nil nil)
                                (w state)))
                     (cons #\2 (evisc-tuple 5 7 nil nil)))
               chan state nil)
          (show-bdd-backtrace (cdr call-stack) cst-array chan state)))))))

(defun show-bdd-fn (str goal-query-response
                        counterex-query-response
                        term-query-response
                        state)
  (let ((bddnotes (f-get-global 'bddnotes state))
        (cl-id (parse-clause-id str))
        (separator "==============================~%"))
    (cond
     ((and str (null cl-id))
      (er soft 'show-bdd
          "The string ~x0 does not have the syntax of a goal name.  See :DOC ~
           goal-spec."
          str))
     (t
      (let ((bddnote (if cl-id ;equivalently, if str
                         (lookup-bddnote cl-id bddnotes)
                       (car bddnotes)))
            (chan (standard-co state)))
        (cond
         ((null bddnote)
          (er soft 'show-bdd
              "There is no recent record of applying BDDs~#0~[~/ to ~s1~]."
              (if str 1 0)
              (if (eq str t) "Goal" str)))
         (t
          (pprogn
            (show-bdd-goal goal-query-response
                           bddnote chan state)
            (fms "~@0" (list (cons #\0 separator)) chan state nil)
            (fms "BDD computation on ~@0 yielded ~x1 nodes.~|~@2"
                (list (cons #\0 (tilde-@-clause-id-phrase
                                 (access bddnote bddnote :cl-id)))
                      (cons #\1 (access bddnote bddnote :mx-id))
                      (cons #\2 separator))
                chan state nil)
            (cond
             ((access bddnote bddnote :err-string)
              (pprogn (fms
                       "BDD computation was aborted on ~@0, and hence there is ~
                        no falsifying assignment that can be constructed.  ~
                        Here is a backtrace of calls, starting with the ~
                        top-level call and ending with the one that led to the ~
                        abort.  See :DOC show-bdd.~|"
                       (list (cons #\0 (tilde-@-clause-id-phrase
                                        (access bddnote bddnote :cl-id))))
                       chan state nil)
                      (show-bdd-backtrace (access bddnote bddnote
                                                  :bdd-call-stack)

; Note that we will probably be building the same array as the one just below
; for show-bdd-term, but that seems a small price to pay for modularity here.

                                          (leaf-cst-list-array
                                           (access bddnote bddnote :mx-id))
                                          chan state)
                      (value :invisible)))
             (t (pprogn (show-falsifying-assignment counterex-query-response
                                                    bddnote chan state)
                        (fms "~@0" (list (cons #\0 separator)) chan state nil)
                        (show-bdd-term term-query-response bddnote chan state)
                        (value :invisible))))))))))))

(defun get-docs (lst)

; Each element of lst is a 5-tuple (name args doc edcls body).  We
; return a list in 1:1 correspondence with lst containing the docs
; (each of which is either a stringp or nil).

  (cond ((null lst) nil)
        (t (cons (third (car lst))
                 (get-docs (cdr lst))))))

(defun rev-union-equal (x y)
  (declare (xargs :guard (and (true-listp x)
                              (true-listp y))))
  (cond ((endp x) y)
        ((member-equal (car x) y)
         (rev-union-equal (cdr x) y))
        (t
         (rev-union-equal (cdr x) (cons (car x) y)))))

; Rockwell Addition:  Now when you declare a fn to traffic in the stobj st
; the guard is automatically extended with a (stp st).

(defun get-guards2 (edcls wrld acc)

; See get-guards for an example of what edcls looks like.

; We are careful to preserve the order, except that within a given declaration
; we consider :stobjs as going before :guard.  (An example is (defun load-qs
; ...) in books/defexec/other-apps/qsort/programs.lisp.)  Before Version_3.5,
; Jared Davis sent us the following example, for which guard verification
; failed on the guard of the guard, because the :guard conjuncts were unioned
; into the :type contribution to the guard, leaving a guard of (and (natp n) (=
; (length x) n) (stringp x)).  It seems reasonable to accumulate the guard
; conjuncts in the order presented by the user.

; (defun f (x n)
;   (declare (xargs :guard (and (stringp x)
;                               (natp n)
;                               (= (length x) n)))
;            (type string x)
;            (ignore x n))
;   t)

  (cond ((null edcls) (reverse acc))
        ((eq (caar edcls) 'xargs)

; We know (from chk-dcl-lst) that (cdar edcls) is a "keyword list"
; and so we can assoc-keyword up it looking for :GUARD.  We also know
; that there is at most one :GUARD entry.

         (let* ((temp1 (assoc-keyword :GUARD (cdar edcls)))
                (guard-conjuncts
                 (if temp1
                     (if (and (true-listp (cadr temp1))
                              (eq (car (cadr temp1)) 'AND))
                         (or (cdr (cadr temp1))
; The following (list t) avoids ignoring :guard (and).
                             (list t))
                       (list (cadr temp1)))
                   nil))
                (temp2 (assoc-keyword :STOBJS (cdar edcls)))
                (stobj-conjuncts
                 (if temp2
                     (stobj-recognizer-terms
                      (cond
                       ((symbol-listp (cadr temp2))
                        (cadr temp2))
                       ((and (cadr temp2)
                             (symbolp (cadr temp2)))
                        (list (cadr temp2)))
                       (t nil))
                      wrld)
                   nil)))
           (get-guards2 (cdr edcls)
                        wrld
                        (rev-union-equal
                         guard-conjuncts
                         (rev-union-equal stobj-conjuncts
                                          acc)))))
        ((eq (caar edcls) 'type)
         (get-guards2 (cdr edcls)
                      wrld
                      (rev-union-equal (translate-declaration-to-guard-var-lst
                                        (cadr (car edcls))
                                        (cddr (car edcls))
                                        wrld)
                                       acc)))
        (t (get-guards2 (cdr edcls) wrld acc))))

(defun get-guards1 (edcls wrld)
  (get-guards2 edcls wrld nil))

(defun get-guards (lst wrld)

; Each element of lst is a 5-tuple (name args doc edcls body).  We return
; a list in 1:1 correspondence with lst.  Each element is the
; untranslated guard expression extracted from the edcls of the
; corresponding element of lst.  A typical value of edcls might be

; '((IGNORE X Y)
;   (XARGS :GUARD g1 :MEASURE m1 :HINTS ((id :USE ... :IN-THEORY ...)))
;   (TYPE ...)
;   (XARGS :GUARD g2 :MEASURE m2))

; The guard extracted from such an edcls is the conjunction of all the
; guards mentioned, where we also translate TYPE declarations to guard
; terms.

  (cond ((null lst) nil)
        (t (cons (conjoin-untranslated-terms (get-guards1 (fourth (car lst))
                                                          wrld))
                 (get-guards (cdr lst) wrld)))))

(defun get-guardsp (lst wrld)

; Note that get-guards, above, always returns a list of untranslated terms as
; long as lst and that if a guard is not specified (via either a :GUARD xarg or
; TYPE declaration) then *t* is used by virtue of the empty conjoin.  But in
; order to default the verify-guards flag in defuns we must be able to decide
; whether no guards were specified.  That is the role of this function.  It
; returns t or nil according to whether at least one of the 5-tuples in lst
; specifies a guard.

  (cond ((null lst) nil)
        ((get-guards1 (fourth (car lst)) wrld) t)
        (t (get-guardsp (cdr lst) wrld))))

(defconst *no-measure*
  *nil*)

(defun get-measures1 (m edcls ctx state)

; A typical edcls is given above, in the comment for get-guards.  Note that the
; :MEASURE entry is found in an XARGS declaration.  By the check in chk-dcl-lst
; we know there is at most one :MEASURE entry in each XARGS declaration.  But
; there may be more than one declaration.  If more than one measure is
; specified by this edcls, we'll cause an error.  Otherwise, we return the
; measure or the term *no-measure*, which is taken as a signal that no measure
; was specified.

; Our first argument, m, is the measure term found so far, or *no-measure* if
; none has been found.  We map down edcls and ensure that each XARGS either
; says nothing about :MEASURE or specifies m.

  (cond ((null edcls) (value m))
        ((eq (caar edcls) 'xargs)
         (let ((temp (assoc-keyword :MEASURE (cdar edcls))))
           (cond ((null temp)
                  (get-measures1 m (cdr edcls) ctx state))
                 ((equal m *no-measure*)
                  (get-measures1 (cadr temp) (cdr edcls) ctx state))
                 ((equal m (cadr temp))
                  (get-measures1 m (cdr edcls) ctx state))
                 (t (er soft ctx
                        "It is illegal to declare two different ~
                         measures for the admission of a single ~
                         function.  But you have specified :MEASURE ~
                         ~x0 and :MEASURE ~x1."
                        m (cadr temp))))))
        (t (get-measures1 m (cdr edcls) ctx state))))

(defun get-measures2 (lst ctx state)
  (cond ((null lst) (value nil))
        (t (er-let* ((m (get-measures1 *no-measure* (fourth (car lst)) ctx
                                       state))
                     (rst (get-measures2 (cdr lst) ctx state)))
                    (value (cons m rst))))))


(defun get-measures (symbol-class lst ctx state)

; This function returns a list in 1:1 correspondence with lst containing the
; user's specified :MEASUREs (or *no-measure* if no measure is specified).  We
; cause an error if more than one :MEASURE is specified within the edcls of a
; given element of lst.

; If symbol-class is program, we ignore the contents of lst and simply return
; all *no-measure*s.  See the comment in chk-acceptable-defuns where
; get-measures is called.

  (cond
   ((eq symbol-class :program)
    (value (make-list (length lst) :initial-element *no-measure*)))
   (t (get-measures2 lst ctx state))))

(defconst *no-ruler-extenders*
  :none)

(defconst *basic-ruler-extenders*
  '(mv-list return-last))

(defun get-ruler-extenders1 (r edcls default ctx wrld state)

; This function is analogous to get-measures1, but for obtaining the
; :ruler-extenders xarg.

  (cond ((null edcls) (value (if (eq r *no-ruler-extenders*)
                                 default
                               r)))
        ((eq (caar edcls) 'xargs)
         (let ((temp (assoc-keyword :RULER-EXTENDERS (cdar edcls))))
           (cond ((null temp)
                  (get-ruler-extenders1 r (cdr edcls) default ctx wrld state))
                 (t
                  (let ((r0 (cadr temp)))
                    (cond
                     ((eq r *no-ruler-extenders*)
                      (er-let*
                       ((r1

; If keywords other than :ALL, :BASIC, and :LAMBDAS are supported, then also
; change set-ruler-extenders.

                         (cond ((eq r0 :BASIC)
                                (value *basic-ruler-extenders*))
                               ((eq r0 :LAMBDAS)
                                (value (cons :lambdas
                                             *basic-ruler-extenders*)))
                               ((eq r0 :ALL)
                                (value :ALL))
                               (t (er-progn
                                   (chk-ruler-extenders r0 soft ctx wrld)
                                   (value r0))))))
                       (get-ruler-extenders1 r1 (cdr edcls) default ctx
                                             wrld state)))
                     ((equal r r0)
                      (get-ruler-extenders1 r (cdr edcls) default ctx wrld
                                            state))
                     (t (er soft ctx
                            "It is illegal to declare two different ~
                             ruler-extenders for the admission of a single ~
                             function.  But you have specified ~
                             :RULER-EXTENDERS ~x0 and :RULER-EXTENDERS ~x1."
                            r r0))))))))
        (t (get-ruler-extenders1 r (cdr edcls) default ctx wrld state))))

(defun get-ruler-extenders2 (lst default ctx wrld state)
  (cond ((null lst) (value nil))
        (t (er-let* ((r (get-ruler-extenders1
                         *no-ruler-extenders* (fourth (car lst)) default ctx
                         wrld state))
                     (rst (get-ruler-extenders2 (cdr lst) default ctx wrld
                                                state)))
                    (value (cons r rst))))))

(defmacro default-ruler-extenders-from-table (alist)
  `(let ((pair (assoc-eq :ruler-extenders ,alist)))
     (cond ((null pair)
            *basic-ruler-extenders*)
           (t (cdr pair)))))

(defun default-ruler-extenders (wrld)

  ":Doc-Section Miscellaneous

  the default ~il[ruler-extenders] for ~ilc[defun]'d functions~/

  When a ~ilc[defun] is processed and no ~c[:ruler-extenders] ~c[xarg] is
  supplied, the function ~c[default-ruler-extenders] is used to obtain the
  current ruler-extenders; ~pl[ruler-extenders].  To find the default
  ~il[ruler-extenders] of the current ACL2 ~il[world], type
  ~c[(default-ruler-extenders (w state))].~/

  While ~il[events] that change the default ~il[ruler-extenders] are permitted
  within an ~ilc[encapsulate] or the text of a book, their effects are
  ~ilc[local] in scope to the duration of the encapsulation or inclusion.
  ~l[default-defun-mode] for an analogous discussion for defun-modes.~/"

  (default-ruler-extenders-from-table (table-alist 'acl2-defaults-table wrld)))

(defun get-ruler-extenders-lst (symbol-class lst ctx state)

; This function returns a list in 1:1 correspondence with lst containing the
; user's specified :RULER-EXTENDERS (or *no-ruler-extenders* if no
; ruler-extenders is specified).  We cause an error if more than one
; :RULER-EXTENDERS is specified within the edcls of a given element of lst.

; If symbol-class is program, we ignore the contents of lst and simply return
; all *no-ruler-extenders.  See the comment in chk-acceptable-defuns where
; get-ruler-extenders is called.

  (cond
   ((eq symbol-class :program)
    (value (make-list (length lst) :initial-element *no-ruler-extenders*)))
   (t (let ((wrld (w state)))
        (get-ruler-extenders2 lst (default-ruler-extenders wrld) ctx wrld
                              state)))))

(defun get-hints1 (edcls)

; A typical edcls might be

; '((IGNORE X Y)
;   (XARGS :GUARD g1 :MEASURE m1 :HINTS ((id :USE ... :IN-THEORY ...)))
;   (TYPE ...)
;   (XARGS :GUARD g2 :MEASURE m2))

; We find all the :HINTS and append them together.

  (cond ((null edcls) nil)
        ((eq (caar edcls) 'xargs)

; We know there is at most one occurrence of :HINTS in this XARGS entry.

         (let ((temp (assoc-keyword :HINTS (cdar edcls))))
           (cond ((null temp) (get-hints1 (cdr edcls)))
                 ((true-listp (cadr temp))
                  (append (cadr temp) (get-hints1 (cdr edcls))))
                 (t (er hard 'get-hints
                        "The value of :HINTS must satisfy the predicate ~x0.  ~
                         The value ~x1 is thus illegal.  See :DOC hints."
                        'true-listp
                        (cadr temp))))))
        (t (get-hints1 (cdr edcls)))))

(defun get-hints (lst)

; Lst is a list of tuples of the form (name args doc edcls body).  We
; scan the edcls in each tuple and collect all of the hints together
; into one list of hints.

  (cond ((null lst) nil)
        (t (append (get-hints1 (fourth (car lst)))
                   (get-hints (cdr lst))))))

(defun get-guard-hints1 (edcls)

; A typical edcls might be

; '((IGNORE X Y)
;   (XARGS :GUARD g1 :MEASURE m1 :GUARD-HINTS ((id :USE ... :IN-THEORY ...)))
;   (TYPE ...)
;   (XARGS :GUARD g2 :MEASURE m2))

; We find all the :GUARD-HINTS and append them together.

  (cond ((null edcls) nil)
        ((eq (caar edcls) 'xargs)

; We know there is at most one occurrence of :GUARD-HINTS in this
; XARGS entry.

         (let ((temp (assoc-keyword :GUARD-HINTS (cdar edcls))))
           (cond ((null temp) (get-guard-hints1 (cdr edcls)))
                 ((true-listp (cadr temp))
                  (append (cadr temp) (get-guard-hints1 (cdr edcls))))
                 (t (er hard 'get-guard-hints
                        "The value of :GUARD-HINTS must satisfy the predicate ~
                         ~x0.  The value ~x1 is thus illegal.  See :DOC hints."
                        'true-listp
                        (cadr temp))))))
        (t (get-guard-hints1 (cdr edcls)))))

(defun get-guard-hints (lst)

; Lst is a list of tuples of the form (name args doc edcls body).  We
; scan the edcls in each tuple and collect all of the guard-hints together
; into one list of hints.

  (cond ((null lst) nil)
        (t (append (get-guard-hints1 (fourth (car lst)))
                   (get-guard-hints (cdr lst))))))

#+:non-standard-analysis
(defun get-std-hints1 (edcls)

; A typical edcls might be

; '((IGNORE X Y)
;   (XARGS :STD-HINTS ((id :USE ... :IN-THEORY ...)))
;   (TYPE ...)
;   (XARGS :GUARD g2 :MEASURE m2))

; We find all the :STD-HINTS and append them together.

  (cond ((null edcls) nil)
        ((eq (caar edcls) 'xargs)

; We know there is at most one occurrence of :STD-HINTS in this
; XARGS entry.

         (let ((temp (assoc-keyword :STD-HINTS (cdar edcls))))
           (cond ((null temp) (get-std-hints1 (cdr edcls)))
                 ((true-listp (cadr temp))
                  (append (cadr temp) (get-std-hints1 (cdr edcls))))
                 (t (er hard 'get-std-hints
                        "The value of :STD-HINTS must satisfy the predicate ~
                         ~x0.  The value ~x1 is thus illegal.  See :DOC hints."
                        'true-listp
                        (cadr temp))))))
        (t (get-std-hints1 (cdr edcls)))))

#+:non-standard-analysis
(defun get-std-hints (lst)

; Lst is a list of tuples of the form (name args doc edcls body).  We
; scan the edcls in each tuple and collect all of the std-hints together
; into one list of hints.

  (cond ((null lst) nil)
        (t (append (get-std-hints1 (fourth (car lst)))
                   (get-std-hints (cdr lst))))))

(defun get-normalizep (edcls ans ctx state)

; A typical edcls might be

; '((IGNORE X Y)
;   (XARGS :GUARD g1 :MEASURE m1 :HINTS ((id :USE ... :IN-THEORY ...)))
;   (TYPE ...)
;   (XARGS :GUARD g2 :MEASURE m2))

; We find the first :NORMALIZE, if there is one.  But we check that there is
; not more than one.

  (cond ((null edcls)
         (value (if (eq ans :absent)
                    t ; default
                  ans)))
        ((eq (caar edcls) 'xargs)

; We know there is at most one occurrence of :NORMALIZE in this XARGS entry,
; but we are concerned about the possibility of other XARGS entries (from other
; declare forms).  Perhaps we should be concerned in other cases too, e.g.,
; :HINTS.

         (let ((temp (assoc-keyword :NORMALIZE (cdar edcls))))
           (cond
            ((null temp)
             (get-normalizep (cdr edcls) ans ctx state))
            ((not (member-eq (cadr temp) '(t nil)))
             (er soft ctx
                 "The :NORMALIZE keyword specified by XARGS must have value t ~
                  or nil, but the following has been supplied: ~p0."
                 (cadr temp)))
            ((eq ans :absent)
             (get-normalizep (cdr edcls) (cadr temp) ctx state))
            (t
             (er soft ctx
                 "Only one :NORMALIZE keyword may be specified by XARGS.")))))
        (t (get-normalizep (cdr edcls) ans ctx state))))

(defun get-normalizeps (lst acc ctx state)

; Lst is a list of tuples of the form (name args doc edcls body).  We
; scan the edcls in each tuple and collect all of the normalizeps together
; into one list, checking that each is Boolean.

  (cond ((null lst) (value (reverse acc)))
        (t (er-let* ((normalizep (get-normalizep (fourth (car lst)) :absent
                                                 ctx state)))
             (get-normalizeps (cdr lst) (cons normalizep acc) ctx state)))))

(defun get-unambiguous-xargs-flg1/edcls (key v edcls ctx state)

; V is the value specified so far for key in the XARSGs of this or previous
; edcls, or else the consp '(unspecified) if no value has been specified yet.
; We cause an error if any non-symbol is used for the value of key or if a
; value different from that specified so far is specified.  We return either
; the consp '(unspecified) or the uniformly agreed upon value.

  (cond
   ((null edcls) (value v))
   ((eq (caar edcls) 'xargs)
    (let ((temp (assoc-keyword key (cdar edcls))))
      (cond ((null temp)
             (get-unambiguous-xargs-flg1/edcls key v (cdr edcls) ctx state))
            ((not (symbolp (cadr temp)))
             (er soft ctx
                 "It is illegal to specify ~x0 to be ~x1.  The value must be a ~
                  symbol."
                 key
                 (cadr temp)))
            ((or (consp v)
                 (eq v (cadr temp)))
             (get-unambiguous-xargs-flg1/edcls key (cadr temp) (cdr edcls)
                                              ctx state))
            (t
             (er soft ctx
                 "It is illegal to specify ~x0 ~x1 in one place and ~
                  ~x2 in another within the same definition.  The ~
                  functionality controlled by that flag operates on ~
                  the entire event or not at all."
                 key v (cadr temp))))))
   (t (get-unambiguous-xargs-flg1/edcls key v (cdr edcls) ctx state))))

(defun get-unambiguous-xargs-flg1 (key lst ctx state)

; We scan the edcls of lst and either extract a single uniformly agreed
; upon value for key among the XARGS and return that value, or else no
; value is specified and we return the consp '(unspecified) or else two or
; more values are specified and we cause an error.  We also cause an error
; if any edcls specifies a non-symbol for the value of key.  Thus, if we
; return a symbol it is the uniformly agreed upon value and if we return
; a consp there was no value specified.

  (cond ((null lst) (value '(unspecified)))
        (t (er-let*
            ((v (get-unambiguous-xargs-flg1 key (cdr lst) ctx state))
             (ans (get-unambiguous-xargs-flg1/edcls key v (fourth (car lst))
                                                    ctx state)))
            (value ans)))))

(defun get-unambiguous-xargs-flg (key lst default ctx state)

; Lst is a list of mutually recursive defun tuples of the form (name args doc
; edcls body).  We scan the edcls for the settings of the XARGS keyword key.
; If at least one entry specifies a setting, x, and all entries that specify a
; setting specify x, we return x.  If no entry specifies a setting, we return
; default.  If two or more entries specify different settings, we cause an
; error.

; We assume every legal value of key is a symbol.  If you supply a consp
; default and the default is returned, then no value was specified for key.

; Just to be concrete, suppose key is :mode and default is :logic.  The
; user has the opportunity to specify :mode in each element of lst, i.e., he
; may say to make the first fn :logic and the second fn :program.  But
; that is nonsense.  We have to process the whole clique or none at all.
; Therefore, we have to meld all of his various :mode specs together to come
; up with a setting for the DEFUNS event.  This function explores lst and
; either comes up with an unambiguous :mode or else causes an error.

  (er-let* ((x (get-unambiguous-xargs-flg1 key lst ctx state)))
           (cond ((consp x) (value default))
                 (t (value x)))))

(defun chk-xargs-keywords1 (edcls keywords ctx state)
  (cond ((null edcls) (value nil))
        ((eq (caar edcls) 'xargs)
         (cond ((null keywords)
                (er soft ctx
                    "No XARGS declaration is legal in this context."))
               ((subsetp-eq (evens (cdar edcls)) keywords)
                (chk-xargs-keywords1 (cdr edcls) keywords ctx state))
               (t (er soft ctx
                      "The only acceptable XARGS keyword~#0~[ in this ~
                       context is~/s in this context are~] ~&0.  Thus, ~
                       the keyword~#1~[ ~&1 is~/s ~&1 are~] illegal."
                      keywords
                      (set-difference-eq (evens (cdar edcls))
                                         keywords)))))
        (t (chk-xargs-keywords1 (cdr edcls) keywords ctx state))))

(defun chk-xargs-keywords (lst keywords ctx state)

; Lst is a list of 5-tuples of the form (name args doc edcls body).  The
; edcls contain XARGS keyword lists, e.g., a typical edcls might be

; '((IGNORE X Y)
;   (XARGS :GUARD g1 :MEASURE m1 :HINTS ((id :USE ... :IN-THEORY ...)))
;   (TYPE ...)
;   (XARGS :GUARD g2 :MEASURE m2))

; We check that the only keywords mentioned in the list are those of
; keywords.  We once put this check into translate itself, when it
; was producing the edcls.  But the keywords allowed by DEFUN are
; different from those allowed by DEFMACRO, and so we've moved this
; check into the specific event file.

  (cond
   ((null lst) (value nil))
   (t (er-progn (chk-xargs-keywords1 (fourth (car lst)) keywords ctx state)
                (chk-xargs-keywords (cdr lst) keywords ctx state)))))

(defun get-names (lst)
  (cond ((null lst) nil)
        (t (cons (caar lst)
                 (get-names (cdr lst))))))

(defun get-bodies (lst)
  (cond ((null lst) nil)
        (t (cons (fifth (car lst))
                 (get-bodies (cdr lst))))))

(mutual-recursion

(defun find-nontrivial-rulers (var term)

; Returns a non-empty list of rulers governing an occurrence of var in term, if
; such exists.  Otherwise returns :none if var occurs in term and nil if var
; does not occur in term.

  (cond ((variablep term)
         (if (eq var term) :none nil))
        ((fquotep term)
         nil)
        ((eq (ffn-symb term) 'if)
         (let ((x (find-nontrivial-rulers var (fargn term 2))))
           (cond (x (cons (fargn term 1)
                          (if (eq x :none)
                              nil
                            x)))
                 (t (let ((x (find-nontrivial-rulers var (fargn term 3))))
                      (cond (x (cons (dumb-negate-lit (fargn term 1))
                                     (if (eq x :none)
                                         nil
                                       x)))
                            (t
                             (find-nontrivial-rulers var (fargn term 1)))))))))
        (t (find-nontrivial-rulers-lst var (fargs term) nil))))

(defun find-nontrivial-rulers-lst (var termlist flg)
  (cond ((endp termlist) flg)
        (t (let ((x (find-nontrivial-rulers var (car termlist))))
             (cond ((or (null x)
                        (eq x :none))
                    (find-nontrivial-rulers-lst var (cdr termlist) (or flg x)))
                   (t x))))))
)

(defun tilde-@-free-vars-phrase (vars term wrld)
  (declare (xargs :guard (and (symbol-listp vars)
                              (pseudo-termp term)
                              (nvariablep term)
                              (not (fquotep term))
                              (plist-worldp wrld))))
  (cond ((endp vars) "")
        (t (let ((rulers (find-nontrivial-rulers (car vars) term)))
             (assert$
              rulers ; (car vars) occurs in term, so expect :none if no rulers
              (cond ((eq rulers :none)
                     (tilde-@-free-vars-phrase (cdr vars) term wrld))
                    ((null (cdr rulers))
                     (msg "  Note that ~x0 occurs in the context of condition ~
                           ~x1 from a surrounding IF test."
                          (car vars)
                          (untranslate (car rulers) t wrld)))
                    (t
                     (msg "  Note that ~x0 occurs in the following context, ~
                           i.e., governed by these conditions from ~
                           surrounding IF tests.~|~%  (AND~|~@1"
                          (car vars)
                          (print-indented-list-msg
                           (untranslate-lst rulers t wrld)
                           3
                           ")")))))))))

(defun chk-free-vars (name formals term loc-str ctx state)
  (declare (xargs :guard (and (symbol-listp formals)
                              (pseudo-termp term))))
  (cond ((subsetp (all-vars term) formals) (value nil))
        ((variablep term)
         (er soft ctx
             "The ~@0 ~x1 is a free variable occurrence."
             loc-str name))
        (t (assert$
            (not (fquotep term))
            (let ((vars (set-difference-eq (all-vars term) formals)))
              (er soft ctx
                  "The ~@0 ~x1 contains ~#2~[a free occurrence of the ~
                   variable symbol~/free occurrences of the variable ~
                   symbols~] ~&2.~@3"
                  loc-str name 
                  (set-difference-eq vars formals)
                  (tilde-@-free-vars-phrase vars term (w state))))))))

(defun chk-declared-ignores (name ignores term loc-str ctx state)
  (declare (xargs :guard (and (symbol-listp ignores)
                              (pseudo-termp term))))
  (cond ((intersectp-eq (all-vars term) ignores)
         (er soft ctx
             "The ~@0 ~x1 uses the variable symbol~#2~[~/s~] ~&2, ~
              contrary to the declaration that ~#2~[it is~/they are~] ~
              IGNOREd."
             loc-str name 
             (intersection-eq (all-vars term) ignores)))
        (t (value nil))))

(defun chk-free-and-ignored-vars
  (name formals guard measure ignores ignorables body ctx state)
  (er-progn
   (chk-free-vars name formals guard "guard for" ctx state)
   (chk-free-vars name formals measure "measure supplied with" ctx state)
   (chk-free-vars name formals (cons 'list ignores)
                  "list of variables declared IGNOREd in" ctx state)
   (chk-free-vars name formals (cons 'list ignorables)
                  "list of variables declared IGNORABLE in" ctx state)
   (chk-free-vars name formals body "body of" ctx state)

; Once upon a time we considered a variable used if it occurred in the
; guard or the measure of a function.  Thus, we signaled an error
; if it was declared ignored but used in the guard or measure.
; Now we don't.  Why?  Because this meant that one was not allowed to
; declare ignored a variable used only in (say) the guard.  But when
; the defun is compiled by Allegro, it would complain that the variable
; should have been declared ignored.  We simply are not free to give
; semantics to IGNORE.  CLTL does that and it only cares about the
; body.

   (chk-declared-ignores name ignores body "body of" ctx state)
   (let* ((ignore-ok (cdr (assoc-eq 
                           :ignore-ok
                           (table-alist 'acl2-defaults-table (w state)))))
          (undeclared-ignores ; first conjunct is an optimization
           (cond ((or (eq ignore-ok t)
                      (and (not (eq ignore-ok nil))
                           (warning-disabled-p "Ignored-variables")))
                  nil)
                 (t (set-difference-eq 
                     formals
                     (union-eq (all-vars body)
                               (union-eq ignorables ignores)))))))
     (cond ((and undeclared-ignores
                 (eq ignore-ok nil))
            (er soft ctx
                "The formal variable~#0~[ ~&0 is~/s ~&0 are~] not used in the ~
                 definition of ~x1 but ~#0~[is~/are~] not DECLAREd IGNOREd or ~
                 IGNORABLE.  Any formal variable not used in the body of a ~
                 definition must be so declared.  To remove this requirement, ~
                 see :DOC set-ignore-ok."
                undeclared-ignores name))
           (undeclared-ignores ; :warn
            (pprogn
             (warning$ ctx ("Ignored-variables")
                      "The formal variable~#0~[ ~&0 is~/s ~&0 are~] not used ~
                       in the definition of ~x1 but ~#0~[is~/are~] not ~
                       DECLAREd IGNOREd or IGNORABLE.  See :DOC set-ignore-ok ~
                       for how to either remove this warning or to enforce it ~
                       by causing an error."
                      undeclared-ignores name)
             (value nil)))
           (t (value nil))))))

(defun chk-free-and-ignored-vars-lsts
  (names arglists guards measures ignores ignorables bodies ctx state)

; This function does all of the defun checking related to the use of free vars
; and ignored/ignorable vars.  We package it all up here to simplify the
; appearance (and post-macro-expansion size) of the caller,
; chk-acceptable-defuns.  The first 6 args are in 1:1 correspondence.

  (declare (xargs :guard (and (symbol-listp names)
                              (symbol-list-listp arglists)
                              (pseudo-term-listp guards)
                              (pseudo-term-listp measures)
                              (pseudo-term-listp bodies)
                              (symbol-list-listp ignores)
                              (symbol-list-listp ignorables))))
  (cond ((null names) (value nil))
        (t (er-progn (chk-free-and-ignored-vars (car names)
                                                (car arglists)
                                                (car guards)
                                                (car measures)
                                                (car ignores)
                                                (car ignorables)
                                                (car bodies)
                                                ctx state)
                     (chk-free-and-ignored-vars-lsts (cdr names)
                                                     (cdr arglists)
                                                     (cdr guards)
                                                     (cdr measures)
                                                     (cdr ignores)
                                                     (cdr ignorables)
                                                     (cdr bodies)
                                                     ctx state)))))

(defun putprop-x-lst1 (symbols key value wrld)

; For every sym in symbols, (putprop sym key value).

  (cond ((null symbols) wrld)
        (t (putprop-x-lst1 (cdr symbols)
                           key
                           value
                           (putprop (car symbols) key value wrld)))))

(defun putprop-x-lst2 (symbols key vals wrld)

; For corresponding symi,vali pairs in symbols x vals,
; (putprop symi key vali).

  (cond ((null symbols) wrld)
        (t (putprop-x-lst2 (cdr symbols)
                           key
                           (cdr vals)
                           (putprop (car symbols) key (car vals) wrld)))))

(defun putprop-x-lst2-unless (symbols key vals exception wrld)

; For corresponding symi,vali pairs in symbols x vals, (putprop symi
; key vali), unless vali is exception, in which case we do nothing.

  (cond ((null symbols) wrld)
        (t (putprop-x-lst2-unless (cdr symbols)
                                  key
                                  (cdr vals)
                                  exception
                                  (putprop-unless (car symbols)
                                                  key
                                                  (car vals)
                                                  exception
                                                  wrld)))))

(defun translate-term-lst (terms stobjs-out logic-modep known-stobjs-lst
                                 ctx wrld state)

; WARNING: Keep this in sync with translate-measures.

; This function translates each of the terms in terms and returns the
; list of translations or causes an error.  It uses the given
; stobjs-out and logic-modep on each term.  As it maps over terms it
; maps over known-stobjs-lst and uses the corresponding element for
; the known-stobjs of each translation.  However, if known-stobjs-lst
; is t it uses t for each.  Note the difference between the treatment
; of stobjs-out and logic-modep, on the one hand, and known-stobjs-lst
; on the other.  The former are ``fixed'' in the sense that the same
; setting is used for EACH term in terms, whereas the latter allows a
; different setting for each term in terms.

; Call this function with stobjs-out t if you want
; merely the logical meaning of the terms.  Call this function with
; stobjs-out '(nil state nil), for example, if you want to ensure that
; each term has the output signature given.

  (cond ((null terms) (value nil))
        (t (er-let*
            ((term (translate (car terms) stobjs-out logic-modep
                              (if (eq known-stobjs-lst t)
                                  t
                                (car known-stobjs-lst))
                              ctx wrld state))
             (rst (translate-term-lst (cdr terms) stobjs-out logic-modep
                                      (if (eq known-stobjs-lst t)
                                          t
                                        (cdr known-stobjs-lst))
                                      ctx wrld state)))
            (value (cons term rst))))))

; We now turn to the major question of translating user typed hints into
; their internal form.  We combine this translation process with the
; checking that ensures that the hints are legal.  While our immediate
; interest is in the hints for defuns, we in fact handle all the hints
; supported by the system.

; Defthm takes a keyword argument, :HINTS, whose expected value is a
; "hints" of the form ((str1 . hints1) ... (strn . hintsn)) where
; each stri is a string that parses to a clause-id and each hintsi is
; a keyword/value list of the form :key1 val1 ... :keyk valk, where a
; typical :keyi might be :USE, :DO-NOT-INDUCT, :IN-THEORY, etc.  Thus,
; a typical defthm event might be:

; (defthm foo (equal x x)
;   :hints (("Goal''" :use assoc-of-append :in-theory *bar*)))

; Defun, the other event most commonly given hints, does not have room
; in its arg list for :HINTS since defun is a CLTL primitive.  So we have
; implemented the notion of the XARGS of DEFUN and permit it to have as its
; value a keyword/value list exactly like a keyword/value list in macro
; calls.  Thus, to pass the hint above into a defun event you would write

; (defun foo (x)
;   (declare (xargs :hints (("Goal''" :use assoc-of-append :in-theory *bar*))))
;   body)

; Making matters somewhat more complicated are the facts that defuns may
; take more than one defun tuple, i.e., one might be defining a clique of
; functions

;  (defuns
;    (fn1 (x) (DECLARE ...) ... body1)
;    ...
;    (fnn (x) (DECLARE ...) ... bodyn))

; and each such tuple may have zero or more DECLARE forms (or, in
; general, arbitrary forms which macroexpand into DECLARE forms).
; Each of those DECLAREs may have zero or more XARGS and we somehow
; have to extract a single list of hints from them collectively.  What
; we do is just concatenate the hints from each DECLARE form.  Thus,
; it is possible that fn1 will say to use hint settings hs1 on
; "Goal''" and fn2 will say to use hs2 on it.  Because we concatenate
; in the presented order, the clause-id's specified by fn1 have the
; first shot.

; The basic function we define below is translate-hints which takes a
; list of the alleged form ((str1 . hint-settings1) ...) and
; translates the strings and processes the keyword/value pairs
; appropriately.

; Just for the record, the complete list of hint keywords that might
; be used in a given hint-settings may be found in *hint-keywords*.

; For each hint keyword, :x, we have a function,
; translate-x-hint-value, that checks the form.  Each of these
; functions gets as its arg argument the object that was supplied as
; the value of the keyword.  We cause an error or return a translated
; value.  Of course, "translate" here means more than just apply the
; function translate; it means "convert to internal form", e.g.,
; in-theory hints are evaluated into theories.

(defun find-named-lemma (sym lst top-level)

; Sym is a symbol and lst is a list of lemmas, and top-level is initially t.
; We return a lemma in lst whose rune has base-symbol sym, if such a lemma is
; unique and top-level is t.  Otherwise we return nil, except we return
; :several if top-level is nil.

  (cond ((null lst) nil)
        ((equal sym
                (base-symbol (access rewrite-rule (car lst) :rune)))
         (cond ((and top-level
                     (null (find-named-lemma sym (cdr lst) nil)))
                (car lst))
               (top-level nil)
               (t :several)))
        (t (find-named-lemma sym (cdr lst) top-level))))

(defun find-runed-lemma (rune lst)

; Lst must be a list of lemmas.  We find the first one with :rune rune (but we
; make no assumptions on the form of rune).

  (cond ((null lst) nil)
        ((equal rune
                (access rewrite-rule (car lst) :rune))
         (car lst))
        (t (find-runed-lemma rune (cdr lst)))))

(mutual-recursion

(defun free-varsp-member (term vars)

; Like free-varsp, but takes a list of variables instead of an alist.

  (cond ((variablep term) (not (member-eq term vars)))
        ((fquotep term) nil)
        (t (free-varsp-member-lst (fargs term) vars))))

(defun free-varsp-member-lst (args vars)
  (cond ((null args) nil)
        (t (or (free-varsp-member (car args) vars)
               (free-varsp-member-lst (cdr args) vars)))))

)

(defun translate-expand-term1 (name form free-vars ctx wrld state)

; Returns an error triple (mv erp val state) where if erp is not nil, then val
; is an expand-hint determined by the given rune and alist.

  (cond
   ((not (arglistp free-vars))
    (er soft ctx
        "The use of :FREE in :expand hints should be of the form (:FREE ~
         var-list x), where var-list is a list of distinct variables, unlike ~
         ~x0."
        free-vars))
   (t
    (er-let*
     ((term (translate form t t t ctx wrld state)))
     (cond
      ((or (variablep term)
           (fquotep term))
       (er soft ctx
           "The term ~x0 is not expandable.  See the :expand discussion in ~
            :DOC hints."
           form))
      ((flambda-applicationp term)
       (cond
        (name (er soft ctx
                  "An :expand hint may only specify :WITH for an expression ~
                   that is the application of a function, unlike ~x0."
                  form))
        (t (value (make expand-hint
                        :pattern term
                        :alist (if (null free-vars)
                                   :none
                                 (let ((bound-vars
                                        (set-difference-eq (all-vars term)
                                                           free-vars)))
                                   (pairlis$ bound-vars bound-vars)))
                        :rune nil
                        :equiv 'equal
                        :hyp nil
                        :lhs term
                        :rhs (subcor-var (lambda-formals (ffn-symb term))
                                         (fargs term)
                                         (lambda-body (ffn-symb term))))))))
      (t
       (mv-let
        (er-msg rune equiv hyp lhs rhs)
        (cond
         (name
          (let* ((fn (ffn-symb term))
                 (lemmas (getprop fn 'lemmas nil 'current-acl2-world wrld))
                 (lemma (cond ((symbolp name)
                               (find-named-lemma
                                (deref-macro-name name (macro-aliases wrld))
                                lemmas
                                t))
                              (t (find-runed-lemma name lemmas)))))
            (cond
             (lemma
              (let* ((hyps (access rewrite-rule lemma :hyps))
                     (lhs (access rewrite-rule lemma :lhs))
                     (lhs-vars (all-vars lhs))
                     (rhs (access rewrite-rule lemma :rhs)))
                (cond
                 ((or (free-varsp-member-lst hyps lhs-vars)
                      (free-varsp-member rhs lhs-vars))
                  (mv (msg "The ~@0 of a rule given to :with in an :expand ~
                            hint must not contain free variables that are not ~
                            among the variables on its left-hand side.  The ~
                            ~#1~[variable ~&1 violates~/variables ~&1 ~
                            violate~] this requirement."
                           (if (free-varsp-member rhs lhs-vars)
                               "left-hand side"
                             "hypotheses")
                           (if (free-varsp-member rhs lhs-vars)
                               (set-difference-eq (all-vars rhs) lhs-vars)
                             (set-difference-eq (all-vars1-lst hyps nil)
                                                lhs-vars)))
                      nil nil nil nil nil))
                 (t (mv nil
                        (access rewrite-rule lemma :rune)
                        (access rewrite-rule lemma :equiv)
                        (and hyps (conjoin hyps))
                        lhs
                        rhs)))))
             (t (mv (msg "Unable to find a lemma for :expand hint (:WITH ~x0 ~
                          ...)."
                         name)
                    nil nil nil nil nil)))))
         (t (let ((def-body (def-body (ffn-symb term) wrld)))
              (cond
               (def-body
                (let ((formals (access def-body def-body :formals)))
                  (mv nil
                      (access def-body def-body :rune)
                      'equal
                      (access def-body def-body :hyp)
                      (cons-term (ffn-symb term) formals)
                      (access def-body def-body :concl))))
               (t (mv (msg "The :expand hint for ~x0 is illegal, because ~x1 ~
                            is not a defined function."
                           form
                           (ffn-symb term))
                      nil nil nil nil nil))))))

; We could do an extra check that the lemma has some chance of applying.  This
; would involve a call of (one-way-unify lhs term) unless :free was specified,
; in which case we would need to call a full unification routine.  That doesn't
; seem worth the trouble merely for early user feedback.

        (cond
         (er-msg (er soft ctx "~@0" er-msg))
         (t (value (make expand-hint
                         :pattern term
                         :alist (if (null free-vars)
                                    :none
                                  (let ((bound-vars
                                         (set-difference-eq (all-vars term)
                                                            free-vars)))
                                    (pairlis$ bound-vars bound-vars)))
                         :rune rune
                         :equiv equiv
                         :hyp hyp
                         :lhs lhs
                         :rhs rhs)))))))))))

(defun translate-expand-term (x ctx wrld state)

; X is a "term" given to an expand hint, which can be a term or the result of
; prepending (:free vars) or (:with name-or-rune), or both, to a term.  We
; return (mv erp expand-hint state).

  (case-match x
    (':lambdas
     (value x))
    ((':free vars (':with name form))
     (translate-expand-term1 name form vars ctx wrld state))
    ((':with name (':free vars form))
     (translate-expand-term1 name form vars ctx wrld state))
    ((':with name form)
     (translate-expand-term1 name form nil  ctx wrld state))
    ((':free vars form)
     (translate-expand-term1 nil  form vars ctx wrld state))
    (&
     (cond ((or (atom x)
                (keywordp (car x)))
            (er soft ctx
                "An :expand hint must either be a term, or of one of the ~
                 forms (:free vars term) or (:with name term), or a ~
                 combination of the two forms. The form ~x0 is thus illegal ~
                 for an :expand hint.  See :DOC hints."
                x))
           (t (translate-expand-term1 nil x nil ctx wrld state))))))

(defun translate-expand-hint1 (arg acc ctx wrld state)
  (cond ((atom arg)
         (cond
          ((null arg) (value (reverse acc)))
          (t (er soft ctx
                 "The value of the :expand hint must be a true list, ~
                  but your list ends in ~x0.  See :DOC hints."
                 arg))))
        (t (er-let*
            ((xtrans (translate-expand-term (car arg) ctx wrld state)))
            (translate-expand-hint1 (cdr arg) (cons xtrans acc) ctx wrld
                                    state)))))

(defun translate-expand-hint (arg ctx wrld state)

; Arg is whatever the user typed after the :expand keyword.  We
; allow it to be either a term or a list of terms.  For example,
; all of the following are legal:

;   :expand (append a b)
;   :expand ((append a b))
;   :expand (:with append (append a b))
;   :expand ((:with append (append a b)))
;   :expand ((:free (a) (append a b)))
;   :expand (:with append (:free (a) (append a b)))
;   :expand ((:with append (:free (a) (append a b))))

; Here we allow a general notion of "term" that includes expressions of the
; form (:free (var1 ... varn) term), indicating that the indicated variables
; are instantiatable in term, and (:with rd term), where rd is a runic
; designator (see :doc theories).  We also interpret :lambdas specially, to
; represent the user's desire that all lambda applications be expanded.

  (cond ((eq arg :lambdas)
         (translate-expand-hint1 (list arg) nil ctx wrld state))
        ((atom arg)

; Arg had better be nil, otherwise we'll cause an error.

         (translate-expand-hint1 arg nil ctx wrld state))
        ((and (consp arg)
              (symbolp (car arg))
              (not (eq (car arg) :lambdas)))

; In this case, arg is of the form (sym ...).  Now if arg were really
; intended as a list of terms to expand, the user would be asking us
; to expand the symbol sym, which doesn't make sense, and so we'd
; cause an error in translate-expand-hint1 above.  So we will treat
; this arg as a term.

         (translate-expand-hint1 (list arg) nil ctx wrld state))
        ((and (consp arg)
              (consp (car arg))
              (eq (caar arg) 'lambda))

; In this case, arg is of the form ((lambda ...) ...).  If arg were
; really intended as a list of terms, then the first object on the
; list is illegal and would cause an error because lambda is not a
; function symbol.  So we will treat arg as a single term.

         (translate-expand-hint1 (list arg) nil ctx wrld state))
        (t

; Otherwise, arg is treated as a list of terms.

         (translate-expand-hint1 arg nil ctx wrld state))))

(defun cons-all-to-lst (new-members lst)
  (cond ((null new-members) nil)
        (t (cons (cons (car new-members) lst)
                 (cons-all-to-lst (cdr new-members) lst)))))

(defun translate-substitution (substn ctx wrld state)

; Note: This function deals with variable substitutions.  For
; functional substitutions, use translate-functional-substitution.

; Substn is alleged to be a substitution from variables to terms.
; We know it is a true list!  We check that each element is of the
; the form (v term) where v is a variable symbol and term is a term.
; We also check that no v is bound twice.  If things check out we
; return an alist in which each pair is of the form (v . term'), where
; term' is the translation of term.  Otherwise, we cause an error.

  (cond
   ((null substn) (value nil))
   ((not (and (true-listp (car substn))
              (= (length (car substn)) 2)))
    (er soft ctx
        "Each element of a substitution must be a pair of the form ~
         (var term), where var is a variable symbol and term is a ~
         term.  Your alleged substitution contains the element ~x0, ~
         which is not of this form.  See the discussion of :instance ~
         in :MORE-DOC lemma-instance."
        (car substn)))
   (t (let ((var (caar substn))
            (term (cadar substn)))
        (cond
         ((not (legal-variablep var))
          (mv-let (x str)
                  (find-first-bad-arg (list var))
                  (declare (ignore x))
                  (er soft ctx
                      "It is illegal to substitute for the ~
                       non-variable ~x0.  It fails to be a variable ~
                       because ~@1.  See :DOC name and the ~
                       discussion of :instance in :MORE-DOC ~
                       lemma-instance."
                      var
                      (or str "LEGAL-VARIABLEP says so, but ~
                               FIND-FIRST-BAD-ARG can't see why"))))
         (t (er-let*
             ((term (translate term t t t ctx wrld state))
; known-stobjs = t (stobjs-out = t)
              (y (translate-substitution (cdr substn) ctx wrld state)))
             (cond ((assoc-eq var y)
                    (er soft ctx
                        "It is illegal to bind ~x0 twice in a ~
                         substitution.  See the discussion of :instance ~
                         in :MORE-DOC lemma-instance."
                        var))
                   (t (value (cons (cons var term) y)))))))))))

(defun translate-substitution-lst (substn-lst ctx wrld state)
  (cond
   ((null substn-lst) (value nil))
   (t (er-let* ((tsubstn
                 (translate-substitution (car substn-lst) ctx wrld state))
                (rst
                 (translate-substitution-lst (cdr substn-lst) ctx wrld state)))
               (value (cons tsubstn rst))))))

(defun get-rewrite-and-defn-runes-from-runic-mapping-pairs (pairs)
  (cond
   ((null pairs)
    nil)
   ((member-eq (cadr (car pairs)) '(:rewrite :definition))
    (cons (cdr (car pairs))
          (get-rewrite-and-defn-runes-from-runic-mapping-pairs (cdr pairs))))
   (t (get-rewrite-and-defn-runes-from-runic-mapping-pairs (cdr pairs)))))

(defun translate-restrict-hint (arg ctx wrld state)

; Arg is whatever the user typed after the :restrict keyword.

  (cond
   ((atom arg)
    (cond
     ((null arg) (value nil))
     (t (er soft ctx
            "The value of the :RESTRICT hint must be an alistp (association ~
             list), and hence a true list, but your list ends in ~x0.  See ~
             :DOC hints."
            arg))))
   ((not (and (true-listp (car arg))
              (cdr (car arg))))
    (er soft ctx
        "Each member of a :RESTRICT hint must be a true list associating a ~
         name with at least one substitution, but the member ~x0 of your hint ~
         violates this requirement.  See :DOC hints."
        (car arg)))
   ((not (or (symbolp (caar arg))
             (and (runep (caar arg) wrld)
                  (member-eq (car (caar arg)) '(:rewrite :definition)))))
    (er soft ctx
        "Each member of a :RESTRICT hint must be a true list whose first ~
         element is either a symbol or a :rewrite or :definition rune in the ~
         current ACL2 world.  The member ~x0 of your hint violates this ~
         requirement."
        (car arg)))
   (t (let ((runes (if (symbolp (caar arg))
                       (get-rewrite-and-defn-runes-from-runic-mapping-pairs
                        (getprop (caar arg)
                                 'runic-mapping-pairs nil
                                 'current-acl2-world wrld))
                     (list (caar arg)))))
        (cond
         ((null runes)
          (er soft ctx
              "The name ~x0 does not correspond to any :rewrite or ~
               :definition runes, so the element ~x1 of your :RESTRICT hint ~
               is not valid.  See :DOC hints."
              (caar arg) (car arg)))
         (t (er-let* ((subst-lst (translate-substitution-lst
                                  (cdr (car arg)) ctx wrld state))
                      (rst (translate-restrict-hint (cdr arg) ctx wrld state)))
                     (value (append (cons-all-to-lst runes subst-lst)
                                    rst)))))))))

(defconst *do-not-processes*
  '(generalize preprocess simplify eliminate-destructors
               fertilize eliminate-irrelevance))

(defun coerce-to-process-name-lst (lst)
  (declare (xargs :guard (symbol-listp lst)))
  (if lst
      (cons (intern (string-append (symbol-name (car lst)) "-CLAUSE") "ACL2")
            (coerce-to-process-name-lst (cdr lst)))
      nil))

(defun coerce-to-acl2-package-lst (lst)
  (declare (xargs :guard (symbol-listp lst)))
  (if lst
      (cons (intern (symbol-name (car lst)) "ACL2")
            (coerce-to-acl2-package-lst (cdr lst)))
      nil))

(defun chk-do-not-expr-value (lst expr ctx state)

  ;; here lst is the raw names, coerced to the "ACL2" package

  (cond ((atom lst)
         (cond ((null lst)
                (value nil))
               (t (er soft ctx
                      "The value of the :DO-NOT expression ~x0 ~
                       is not a true list and, hence, is not ~
                       legal.  In particular, the final ~
                       non-consp cdr is the atom ~x1.  See :DOC hints."
                      expr lst))))
        ((and (symbolp (car lst))
              (member-eq (car lst) *do-not-processes*))
         (chk-do-not-expr-value (cdr lst) expr ctx state))
        ((eq (car lst) 'induct)
         (er soft ctx
             "The value of the alleged :DO-NOT expression ~x0 ~
              includes INDUCT, which is not the name of a ~
              process to turn off.  You probably mean to use ~
              :DO-NOT-INDUCT T or :DO-NOT-INDUCT :BYE instead.  The ~
              legal names are ~&1."
             expr *do-not-processes*))
        (t (er soft ctx
               "The value of the alleged :DO-NOT expression ~x0 ~
                includes the element ~x1, which is not the name of a ~
                process to turn off.  The legal names are ~&2."
               expr (car lst) *do-not-processes*))))

(defun translate-do-not-hint (expr ctx state)

; We translate and evaluate expr and make sure that it produces something that
; is appropriate for :do-not.  We either cause an error or return the resulting
; list.

  (let ((wrld (w state)))
    (er-let*
     ((trans-ans (if (legal-variablep expr)
                     (value (cons nil (list expr)))
                     (simple-translate-and-eval
                      expr
                      (list (cons 'world wrld))
                      nil
                      "A :do-not hint"
                      ctx wrld state t))))

; trans-ans is (& . val), where & is either nil or a term.

     (cond
      ((not (symbol-listp (cdr trans-ans)))
       (er soft ctx
           "The expression following :do-not is required either to be a symbol ~
            or an expression whose value is a true list of symbols, but the ~
            expression ~x0 has returned the value ~x1.  See :DOC hints."
           expr (cdr trans-ans)))
      (t
       (er-progn
        (chk-do-not-expr-value
         (coerce-to-acl2-package-lst (cdr trans-ans)) expr ctx state)
        (value (coerce-to-process-name-lst (cdr trans-ans)))))))))

(defun translate-do-not-induct-hint (arg ctx wrld state)
  (declare (ignore wrld))
  (cond ((symbolp arg)
         (cond ((member-eq arg '(:otf :otf-flg-override))
                (value arg))
               ((keywordp arg)
                (let ((name (symbol-name arg)))
                  (cond ((and (<= 3 (length name))
                              (equal (subseq name 0 3) "OTF"))
                         (er soft ctx
                             "We do not allow :do-not-induct hint values in ~
                              the keyword package whose name starts with ~
                              \"OTF\", unless the value is :OTF-FLG-OVERRIDE, ~
                              because we suspect you intended ~
                              :OTF-FLG-OVERRIDE in this case.  The value ~x0 ~
                              is thus illegal."
                             arg))
                        (t (value arg)))))
               (t (value arg))))
        (t (er soft ctx
               "The :do-not-induct hint should be followed by a symbol: ~
                either T, :QUIT, or the root name to be used in the naming ~
                of any clauses given byes.  ~x0 is an illegal root name.  See ~
                the :do-not-induct discussion in :MORE-DOC hints."
               arg))))

(defun translate-hands-off-hint1 (arg ctx wrld state)
  (cond
   ((atom arg)
    (cond
     ((null arg) (value nil))
     (t (er soft ctx
            "The value of the :hands-off hint must be a true list, ~
             but your list ends in ~x0.  See the :hands-off ~
             discussion in :MORE-DOC hints."
            arg))))
   ((and (consp (car arg))
         (eq (car (car arg)) 'lambda)
         (consp (cdr (car arg)))
         (true-listp (cadr (car arg))))

; At this point we know that the car of arg is of the form (lambda
; (...) . &) and we want to translate it.  To do so, we create a term
; by applying it to a list of terms.  Where do we get a list of the
; right number of terms?  We use its own formals!

    (er-let*
     ((term (translate (cons (car arg) (cadr (car arg)))
                       t t t ctx wrld state))
; known-stobjs = t (stobjs-out = t)
      (rst (translate-hands-off-hint1 (cdr arg) ctx wrld state)))

; Below we assume that if you give translate ((lambda ...) ...) and it
; does not cause an error, then it gives you back a function application.

     (value (cons (ffn-symb term) rst))))
   ((and (symbolp (car arg))
         (function-symbolp (car arg) wrld))
    (er-let*
     ((rst (translate-hands-off-hint1 (cdr arg) ctx wrld state)))
     (value (cons (car arg) rst))))
   (t (er soft ctx
          "The object ~x0 is not a legal element of a :hands-off ~
           hint.  See the :hands-off discussion in :MORE-DOC hints."
          (car arg)))))

(defun translate-hands-off-hint (arg ctx wrld state)

; Arg is supposed to be a list of function symbols.  However, we
; allow either
;   :hands-off append
; or
;   :hands-off (append)
; in the singleton case.  If the user writes
;   :hands-off (lambda ...)
; we will understand it as 
;   :hands-off ((lambda ...))
; since lambda is not a function symbol.

  (cond ((atom arg)
         (cond ((null arg) (value nil))
               ((symbolp arg)
                (translate-hands-off-hint1 (list arg) ctx wrld state))
               (t (translate-hands-off-hint1 arg ctx wrld state))))
        ((eq (car arg) 'lambda)
         (translate-hands-off-hint1 (list arg) ctx wrld state))
        (t (translate-hands-off-hint1 arg ctx wrld state))))

; The next few functions are used to produced the formulas represented by
; type-prescriptions.

(defun convert-returned-vars-to-term-lst (term vars)
  (cond ((null vars) nil)
        (t (cons (mcons-term* 'equal term (car vars))
                 (convert-returned-vars-to-term-lst term (cdr vars))))))

(defun implicate (t1 t2)

; We return a term equivalent to (IMPLIES t1 t2).

  (cond ((equal t1 *t*) t2)
        ((equal t1 *nil*) *t*)
        ((equal t2 *t*) *t*)
        ((equal t2 *nil*) (dumb-negate-lit t1))
        (t (mcons-term* 'implies t1 t2))))

(defun convert-type-prescription-to-term (tp ens wrld)

; Tp is a type-prescription.  We generate a term that expresses it relative to
; the supplied ens.  We will usually store this term in the :corollary of tp
; itself; generally the current :corollary field of tp is *t* right now because
; tp was generated by putprop-initial-type-prescriptions.  We return
; the generated corollary term and a ttree citing the type-set-inverter
; rules used.

  (mv-let (concl ttree)
          (convert-type-set-to-term (access type-prescription tp :term)
                                    (access type-prescription tp :basic-ts)
                                    ens wrld nil)
          (mv (implicate (conjoin (access type-prescription tp :hyps))
                         (disjoin
                          (cons concl
                                (convert-returned-vars-to-term-lst
                                 (access type-prescription tp :term)
                                 (access type-prescription tp :vars)))))
              ttree)))

(defun truncated-class (rune mapping-pairs classes)

; Rune is a rune and mapping-pairs and classes are the corresponding
; properties of its base symbol.  We return the class corresponding to
; rune.  Recall that the classes stored are truncated classes, e.g.,
; they have the proof-specific parts removed and no :COROLLARY if it
; is the same as the 'THEOREM of the base symbol.  By convention, nil
; is the truncated class of a rune whose base symbol has no 'classes
; property.  An example of such a rune is (:DEFINITION fn).

  (cond ((null classes) nil)
        ((equal rune (cdr (car mapping-pairs))) (car classes))
        (t (truncated-class rune (cdr mapping-pairs) (cdr classes)))))

(defun tests-and-alists-lst-from-fn (fn wrld)
  (let* ((formals (formals fn wrld))
         (term (fcons-term fn formals))
         (quick-block-info
          (getprop fn 'quick-block-info
                   '(:error "See SUGGESTED-INDUCTION-CANDS1.")
                   'current-acl2-world wrld))
         (justification
          (getprop fn 'justification
                   '(:error "See SUGGESTED-INDUCTION-CANDS1.")
                   'current-acl2-world wrld))
         (mask (sound-induction-principle-mask term formals
                                               quick-block-info
                                               (access justification
                                                       justification
                                                       :subset)))
         (machine (getprop fn 'induction-machine nil
                           'current-acl2-world wrld)))
    (tests-and-alists-lst (pairlis$ formals (fargs term))
                          (fargs term) mask machine)))

(defun corollary (rune wrld)

; We return the :COROLLARY that justifies the rule named by rune.
; Nil is returned when we cannot recover a suitable formula.

  ":Doc-Section Miscellaneous

  the corollary formula of a ~il[rune]~/~/

  This is a low-level system function at the present time.
  ~l[pr] and ~pl[pr!] instead.  Also ~pl[rule-classes]
  for the use of the symbol ~c[:corollary] in specifying a rule
  class.~/"

  (let* ((name (base-symbol rune))
         (classes (getprop name 'classes nil 'current-acl2-world wrld)))
    (cond
     ((null classes)
      (cond
       ((or (eq (car rune) :definition)
            (eq (car rune) :executable-counterpart))
        (let ((body (body name t wrld)))
          (cond ((null body) nil)
                ((eq (car rune) :definition)
                 (let ((lemma (find-runed-lemma rune
                                                (getprop name 'lemmas nil
                                                         'current-acl2-world
                                                         wrld))))
                   (and lemma
                        (let ((concl
                               (mcons-term* (access rewrite-rule lemma :equiv)
                                            (access rewrite-rule lemma :lhs)
                                            (access rewrite-rule lemma :rhs))))
                          (if (access rewrite-rule lemma :hyps) ; impossible?
                              (mcons-term* 'implies
                                           (conjoin (access rewrite-rule lemma
                                                            :hyps))
                                           concl)
                            concl)))))
                (t
                 (mcons-term* 'equal
                              (cons-term name (formals name wrld))
                              body)))))
       ((eq (car rune) :type-prescription)
        (let ((tp (find-runed-type-prescription
                   rune
                   (getprop name 'type-prescriptions nil
                            'current-acl2-world wrld))))
          (cond
           ((null tp) *t*)
           (t (access type-prescription tp :corollary)))))
       ((and (eq (car rune) :induction)
             (equal (cddr rune) nil))
        (prettyify-clause-set
         (induction-formula (list (list (cons :p (formals (base-symbol rune)
                                                          wrld))))
                            (tests-and-alists-lst-from-fn (base-symbol rune)
                                                          wrld))
         nil
         wrld))
       (t (er hard 'corollary
              "It was thought to be impossible for a rune to have no ~
               'classes property except in the case of the four or five ~
               definition runes described in the Essay on the ~
               Assignment of Runes and Numes by DEFUNS.  But ~x0 is a ~
               counterexample."
              rune))))
     (t (let ((term
               (cadr
                (assoc-keyword
                 :COROLLARY
                 (cdr
                  (truncated-class
                   rune
                   (getprop name 'runic-mapping-pairs
                            '(:error "See COROLLARY.")
                            'current-acl2-world wrld)
                   classes))))))
          (or term
              (getprop name 'theorem nil 'current-acl2-world wrld)))))))

(defun formula (name normalp wrld)

; Name may be either an event name or a rune.  We return the formula associated
; with name.  We may return nil if we can find no such formula.

  (cond ((consp name) (corollary name wrld))
        (t (let ((body (body name normalp wrld)))
             (cond ((and body normalp)

; We have a defined function.  We want to use the original definition, not one
; installed by a :definition rule with non-nil :install-body field.

                    (corollary `(:DEFINITION ,name) wrld))
                   (body
                    (mcons-term* 'equal
                                 (cons-term name (formals name wrld))
                                 body))
                   (t (or (getprop name 'theorem nil 'current-acl2-world wrld)
                          (getprop name 'defchoose-axiom nil
                                   'current-acl2-world wrld))))))))

(defun pf-fn (name state)
  (io? temporary nil (mv erp val state)
       (name)
       (let ((wrld (w state)))
         (cond
          ((or (symbolp name)
               (runep name wrld))
           (let* ((name (if (symbolp name)
                            (deref-macro-name name (macro-aliases (w state)))
                          name))
                  (term (formula name t wrld)))
             (mv-let (col state)
                     (cond
                      ((equal term *t*)
                       (fmt1 "The formula associated with ~x0 is simply T.~%"
                             (list (cons #\0 name))
                             0
                             (standard-co state) state nil))
                      (term
                       (fmt1 "~p0~|"
                             (list (cons #\0 (untranslate term t wrld)))
                             0
                             (standard-co state) state
                             (term-evisc-tuple nil state)))
                      (t
                       (fmt1 "There is no formula associated with ~x0.~%"
                             (list (cons #\0 name))
                             0 (standard-co state) state nil)))
                     (declare (ignore col))
                     (value :invisible))))
          (t
           (er soft 'pf
               "~x0 is neither a symbol nor a rune in the current world."
               name))))))

(defmacro pf (name)

  ":Doc-Section History

  print the formula corresponding to the given name~/
  ~bv[]
  Examples:
  :pf (:definition fn) ; prints the definition of fn as an equality
  :pf fn               ; same as above

  :pf (:rewrite foo)   ; prints the statement of the rewrite rule foo
  :pf foo              ; same as above
  ~ev[]~/

  ~c[pf] takes one argument, an event name or a ~il[rune], and prints the
  formula associated with name.  If the argument is the name of a macro
  associated with a function name by ~il[macro-aliases-table], then the
  function name is used as the argument.~/"

  (List 'pf-fn name 'state))

(defun merge-symbol-< (l1 l2 acc)
  (cond ((null l1) (revappend acc l2))
        ((null l2) (revappend acc l1))
        ((symbol-< (car l1) (car l2))
         (merge-symbol-< (cdr l1) l2 (cons (car l1) acc)))
        (t (merge-symbol-< l1 (cdr l2) (cons (car l2) acc)))))

(defun merge-sort-symbol-< (l)
  (cond ((null (cdr l)) l)
        (t (merge-symbol-< (merge-sort-symbol-< (evens l))
                           (merge-sort-symbol-< (odds l))
                           nil))))

; The following variants of the above sorting routines are used when processing
; the in-package form at the top of proof-checker-pkg.lisp, so
; other-events.lisp is too late; so we define them here.  We expect to admit
; these, verify guards, and prove properties in books/misc/sort-symbols.lisp.

(defun strict-merge-symbol-< (l1 l2 acc)

; If l1 and l2 are strictly ordered by symbol-< and above acc, which is also
; thus strictly ordered, then the result is strictly ordered by symbol-<.

  (declare (xargs :guard (and (symbol-listp l1)
                              (symbol-listp l2)
                              (true-listp acc))

; We admit this to the logic and prove termination in
; books/misc/sort-symbols.lisp.

                  :mode :program))
  (cond ((endp l1) (revappend acc l2))
        ((endp l2) (revappend acc l1))
        ((eq (car l1) (car l2))
         (strict-merge-symbol-< (cdr l1) (cdr l2) (cons (car l1) acc)))
        ((symbol-< (car l1) (car l2))
         (strict-merge-symbol-< (cdr l1) l2 (cons (car l1) acc)))
        (t (strict-merge-symbol-< l1 (cdr l2) (cons (car l2) acc)))))

(defun strict-merge-sort-symbol-< (l)

; Produces a result with the same elements as the list l of symbols, but
; strictly ordered by symbol-name.

  (declare (xargs :guard (symbol-listp l)

; We admit this to the logic and prove termination in
; books/misc/sort-symbols.lisp.

                  :mode :program))
  (cond ((endp (cdr l)) l)
        (t (strict-merge-symbol-<
            (strict-merge-sort-symbol-< (evens l))
            (strict-merge-sort-symbol-< (odds l))
            nil))))

(defun strict-symbol-<-sortedp (x)
  (declare (xargs :guard (symbol-listp x)))
  (cond ((or (endp x) (null (cdr x)))
         t)
        (t (and (symbol-< (car x) (cadr x))
                (strict-symbol-<-sortedp (cdr x))))))

(defun sort-symbol-listp (x)
  (declare (xargs :guard (symbol-listp x)))
  (cond ((strict-symbol-<-sortedp x)
         x)
        (t (strict-merge-sort-symbol-< x))))

;; RAG - I added the non-standard primitives here.

(defconst *non-instantiable-primitives*

; We could redefine ENDP in terms of CONS so that ATOM doesn't have to be on
; the list below, but this seems unimportant.  If we take ATOM off, we need to
; change the definition of MAKE-CHARACTER-LIST.

  '(NOT IMPLIES O<
        MEMBER-EQUAL        ;;; perhaps not needed; we are conservative here
        FIX                 ;;; used in DEFAULT-+-2
        BOOLEANP            ;;; used in BOOLEANP-CHARACTERP
        CHARACTER-LISTP     ;;; used in CHARACTER-LISTP-COERCE
        FORCE               ;;; just nice to protect
        CASE-SPLIT          ;;; just nice to protect
        MAKE-CHARACTER-LIST ;;; used in COMPLETION-OF-COERCE
        EQL ENDP            ;;; probably used in others
        ATOM                ;;; used in ENDP; probably used in others
        BAD-ATOM            ;;; used in several defaxioms
        RETURN-LAST         ;;; affects constraints (see remove-guard-holders1)
        MV-LIST             ;;; affects constraints (see remove-guard-holders1)

; The next six are used in built-in defpkg axioms.

        MEMBER-SYMBOL-NAME
        SYMBOL-PACKAGE-NAME
        INTERN-IN-PACKAGE-OF-SYMBOL
        PKG-IMPORTS
        SYMBOL-LISTP
        NO-DUPLICATESP-EQUAL NO-DUPLICATESP-EQ-EXEC ; latter maybe not critical
                                               
; We do not want vestiges of the non-standard version in the standard version.

        #+:non-standard-analysis STANDARDP
        #+:non-standard-analysis STANDARD-PART
        #+:non-standard-analysis I-LARGE-INTEGER
        #+:non-standard-analysis REALFIX
        #+:non-standard-analysis I-LARGE
        #+:non-standard-analysis I-SMALL

        ))

(defun instantiablep (fn wrld)

; This function returns t if fn is instantiable and nil otherwise; except, if
; if it has been introduced with the designation of a dependent
; clause-processor, then it returns the name of such a dependent
; clause-processor.

  (and (symbolp fn)
       (not (member-eq fn *non-instantiable-primitives*))

; The list of functions above consists of o<, which we believe is built in
; implicitly in the defun principle, plus every symbol mentioned in any
; defaxiom in axioms.lisp that is not excluded by the tests below.  The
; function check-out-instantiablep, when applied to an :init world will check
; that this function excludes all the fns mentioned in axioms.  We call this
; function in initialize-acl2 to make sure we haven't forgotten some fns.

; We believe it would be ok to permit the instantiation of any defun'd
; function (except maybe o<) because we believe only one function
; satisfies each of those defuns.  It is not clear if we should be biased
; against the other fns above.

       (function-symbolp fn wrld)

; A :logic mode function symbol is non-primitive if and only if it has an
; 'unnormalized-body or 'constrainedp property.  For the forward implication,
; note that the symbol must have been introduced either in the signature of an
; encapsulate, in defuns, or in defchoose.  Note that the value of the
; 'constrainedp property can be a clause-processor, in which case that is the
; value we want to return here; so do not switch the order of the disjuncts
; below!

       (or (getprop fn 'constrainedp nil 'current-acl2-world wrld)
           (and (body fn nil wrld)
                t))))

(mutual-recursion

(defun all-ffn-symbs (term ans)
  (cond
   ((variablep term) ans)
   ((fquotep term) ans)
   (t (all-ffn-symbs-lst (fargs term)
                         (cond ((flambda-applicationp term)
                                (all-ffn-symbs (lambda-body (ffn-symb term))
                                               ans))
                               (t (add-to-set-eq (ffn-symb term) ans)))))))

(defun all-ffn-symbs-lst (lst ans)
  (cond ((null lst) ans)
        (t (all-ffn-symbs-lst (cdr lst)
                              (all-ffn-symbs (car lst) ans)))))

)

(defconst *unknown-constraints*

; This value must not be a function symbol, because functions may need to
; distinguish conses whose car is this value from those consisting of function
; symbols.

  :unknown-constraints)

(defun constraint-info (fn wrld)

; This function returns a pair (mv flg x).  In the simplest and perhaps most
; common case, there is no 'constraint-lst property for fn, e.g., when fn is
; defined by defun or defchoose and not in the scope of an encapsulate.  In
; this case, flg is nil, and x is the defining axiom for fn.  In the other
; case, flg is the name under which the actual constraint for fn is stored
; (possibly name itself), and x is the list of constraints stored there or else
; the value *unknown-constraints* (indicating that the constraints cannot be
; determined because they are associated with a dependent clause-processor).

; We assume that if fn was introduced by a non-local defun or defchoose in the
; context of an encapsulate that introduced constraints, then the defining
; axiom for fn is included in its 'constraint-lst property.  That is:  in that
; case, we do not need to use the definitional axiom explicitly in order to
; obtain the full list of constraints.

  (let ((prop (getprop fn 'constraint-lst

; We want to distinguish between not finding a list of constraints, and finding
; a list of constraints of nil.  Perhaps we only store non-nil constraints, but
; even if so, there is no need to rely on that invariant, and future versions
; of ACL2 may not respect it.

                       t
                       'current-acl2-world wrld)))

    (cond
     ((eq prop t)
      (let ((body (body fn nil wrld)))
        (cond (body

; Warning: Do not apply remove-guard-holders to body.  We rely on having all
; ancestors of body present in the constraint-info in our calculation of
; immediate-canonical-ancestors.  In particular, all function symbols in a call
; of return-last, especially one generated by mbe, must be collected here, to
; support the correct use of attachments in calls of metafunctions and
; clause-processor functions; see the remark about mbe in the Essay on
; Correctness of Meta Reasoning.

               (mv nil (mcons-term* 'equal
                                    (cons-term fn (formals fn wrld))
                                    body)))
              (t
               (mv nil
                   (or (getprop fn 'defchoose-axiom nil 'current-acl2-world wrld)

; Then fn is a primitive, and has no constraint.

                       *t*))))))
     ((and (symbolp prop)
           prop
           (not (eq prop *unknown-constraints*)))

; Then prop is a name, and the constraints for fn are found under that name.

      (mv prop
          (getprop prop 'constraint-lst
                   '(:error "See constraint-info:  expected to find a ~
                             'constraint-lst property where we did not.")
                   'current-acl2-world wrld)))
     (t
      (mv fn prop)))))

(defdoc constraint
  ":Doc-Section Miscellaneous

  restrictions on certain functions introduced in ~ilc[encapsulate] ~il[events]~/

  Suppose that a given theorem, ~c[thm], is to be functionally instantiated
  using a given functional substitution, ~c[alist].  (~l[lemma-instance], or
  for an example, ~pl[functional-instantiation-example].)  What is the set of
  proof obligations generated?  It is the set obtained by applying ~c[alist] to
  all terms, ~c[tm], such that (a) ~c[tm] mentions some function symbol in the
  domain of ~c[alist], and (b) either (i) ~c[tm] arises from the ``constraint''
  on a function symbol ancestral in ~c[thm] or in some ~ilc[defaxiom] or (ii)
  ~c[tm] is the body of a ~ilc[defaxiom].  Here, a function symbol is
  ``ancestral'' in ~c[thm] if either it occurs in ~c[thm], or it occurs in the
  definition of some function symbol that occurs in ~c[thm], and so on.

  The remainder of this note explains what we mean by ``constraint'' in the
  words above.~/

  In a certain sense, function symbols are introduced in essentially two ways.
  The most common way is to use ~ilc[defun] (or when there is mutual recursion,
  ~ilc[mutual-recursion] or ~ilc[defuns]).  There is also a mechanism for
  introducing ``witness functions''; ~pl[defchoose].  The documentation for
  these ~il[events] describes the axioms they introduce, which we will call
  here their ``definitional axioms.''  These definitional axioms are generally
  the constraints on the function symbols that these axioms introduce.

  However, when a function symbol is introduced in the scope of an
  ~ilc[encapsulate] event, its constraints may differ from the definitional
  axioms introduced for it.  For example, suppose that a function's definition
  is ~ilc[local] to the ~ilc[encapsulate]; that is, suppose the function is
  introduced in the ~il[signature] of the ~ilc[encapsulate].  Then its
  constraints include, at the least, those non-~ilc[local] theorems and
  definitions in the ~ilc[encapsulate] that mention the function symbol.

  Actually, it will follow from the discussion below that if the
  ~il[signature] is empty for an ~ilc[encapsulate], then the constraint on
  each of its new function symbols is exactly the definitional axiom
  introduced for it.  Intuitively, we view such ~c[encapsulates] just
  as we view ~ilc[include-book] ~il[events].  But the general case, where the
  ~il[signature] is not empty, is more complicated.

  In the discussion that follows we describe in detail exactly which
  constraints are associated with which function symbols that are introduced in
  the scope of an ~ilc[encapsulate] event.  In order to simplify the exposition
  we make two cuts at it.  In the first cut we present an over-simplified
  explanation that nevertheless captures the main ideas.  In the second cut we
  complete our explanation by explaining how we view certain ~il[events] as
  being ``lifted'' out of the ~ilc[encapsulate], resulting in a possibly
  smaller ~ilc[encapsulate], which becomes the target of the algorithm
  described in the first cut.

  At the end of this note we present an example showing why a more naive
  approach is unsound.

  Finally, before we start our ``first cut,'' we note that any information you
  want ``exported'' outside an ~ilc[encapsulate] event must be there as an
  explicit definition or theorem.  For example, even if a function ~c[foo] has
  output type ~c[(mv t t)] in its ~il[signature], the system will not know
  ~c[(true-listp (foo x))] merely on account of this information.  Thus, if you
  are using functions like ~c[foo] (constrained ~ilc[mv] functions), then you
  may find it useful to prove (inside the ~c[encapsulate], to be exported) a
  ~c[:]~ilc[type-prescription] rule for the constrained function, for example,
  the ~c[:]~ilc[type-prescription] rule ~c[(true-listp (foo x))].

  ~em[First cut at constraint-assigning algorithm.]  Quite simply, the formulas
  introduced in the scope of an ~ilc[encapsulate] are conjoined, and each
  function symbol introduced by the ~ilc[encapsulate] is assigned that
  conjunction as its constraint.

  Clearly this is a rather severe algorithm.  Let us consider two possible
  optimizations in an informal manner before presenting our second cut.

  Consider the (rather artificial) event below.  The function ~c[before1] does
  not refer at all, even indirectly, to the locally-introduced function
  ~c[sig-fn], so it is unfortunate to saddle it with constraints about
  ~c[sig-fn].
  ~bv[]
  (encapsulate
   (((sig-fn *) => *))

   (defun before1 (x)
     (if (consp x)
         (before1 (cdr x))
       x))

   (local (defun sig-fn (x) (cons x x)))

   (defthm sig-fn-prop
     (consp (sig-fn x)))
   )
  ~ev[]
  We would like to imagine moving the definition of ~c[before1] to just in
  front of this ~ilc[encapsulate], as follows.
  ~bv[]
  (defun before1 (x)
    (if (consp x)
        (before1 (cdr x))
      x))

  (encapsulate
   (((sig-fn *) => *))

   (local (defun sig-fn (x) (cons x x)))

   (defthm sig-fn-prop
     (consp (sig-fn x)))
   )
  ~ev[]
  Thus, we will only assign the constraint ~c[(consp (sig-fn x))], from the
  theorem ~c[sig-fn-prop], to the function ~c[sig-fn], not to the function
  ~c[before1].

  More generally, suppose an event in an ~ilc[encapsulate] event does not
  mention any function symbol in the ~il[signature] of the ~ilc[encapsulate],
  nor any function symbol that mentions any such function symbol, and so on.
  (We might say that no function symbol from the ~il[signature] is an
  ``ancestor'' of any function symbol occurring in the event.)  Then we imagine
  moving the event, so that it appears in front of the ~ilc[encapsulate].  We
  don't actually move it, but we pretend we do when it comes time to assign
  constraints.  Thus, such definitions only introduce definitional axioms as
  the constraints on the function symbols being defined.  In the example above,
  the event ~c[sig-fn-prop] introduces no constraints on function ~c[before1].

  Once this first optimization is performed, we have in mind a set of
  ``constrained functions.''  These are the functions introduced in the
  ~ilc[encapsulate] that would remain after moving some of them in front, as
  indicated above.  Consider the collection of all formulas introduced by the
  ~ilc[encapsulate], except the definitional axioms, that mention these
  constrained functions.  So for example, in the event below, no such formula
  mentions the function symbol ~c[after1].
  ~bv[]
  (encapsulate
   (((sig-fn *) => *))

   (local (defun sig-fn (x) (cons x x)))

   (defthm sig-fn-prop
     (consp (sig-fn x)))

   (defun after1 (x)
     (sig-fn x))
   )
  ~ev[]
  We can see that there is really no harm in imagining that we move the
  definition of ~c[after1] out of the ~ilc[encapsulate], to just after the
  ~ilc[encapsulate].

  Many subtle aspects of this rearrangement process have been omitted.  For
  example, suppose the function ~c[fn] uses ~c[sig-fn], the latter being a
  function in the signature of the encapsulation.  Suppose a formula about
  ~c[fn] is proved in the encapsulation.  Then from the discussion above ~c[fn]
  is among the constrained functions of the encapsulate: it cannot be moved
  before the encapsulate and it cannot be moved after the encapsulation.  But
  why is ~c[fn] constrained?  The reason is that the theorem proved about
  ~c[fn] may impose or express constraints on ~c[sig-fn].  That is, the theorem
  proved about ~c[fn] may depend upon properties of the witness used for
  ~c[sig-fn].  Here is a simple example:
  ~bv[]
  (encapsulate
   (((sig-fn *) => *))

   (local (defun sig-fn (x) (declare (ignore x)) 0))

   (defun fn (lst)
     (if (endp lst)
         t
         (and (integerp (sig-fn (car lst)))
              (fn (cdr lst)))))

   (defthm fn-always-true
     (fn lst)))
  ~ev[]
  In this example, there are no ~ilc[defthm] events that mention ~c[sig-fn]
  explicitly.  One might therefore conclude that it is completely
  unconstrained.  But the witness we chose for it always returns an integer.
  The function ~c[fn] uses ~c[sig-fn] and we prove that ~c[fn] always returns
  true.  Of course, the proof of this theorem depends upon the properties of
  the witness for ~c[sig-fn], even though those properties were not explicitly
  ``called out'' in theorems proved about ~c[sig-fn].  It would be unsound to
  move ~c[fn-always-true] after the encapsulate.  It would also be unsound to
  constrain ~c[sig-fn] to satisfy just ~c[fn-always-true] without including in
  the constraint the relation between ~c[sig-fn] and ~c[fn].  Hence both
  ~c[sig-fn] and ~c[fn] are constrained by this encapsulation and the
  constraint imposed on each is the same and states the relation between the
  two as characterized by the equation defining ~c[fn] as well as the property
  that ~c[fn] always returns true.  Suppose, later, one proved a theorem about
  ~c[sig-fn] and wished to functionally instantiate it.  Then one must also
  functionally instantiate ~c[fn], even if it is not involved in the theorem,
  because it is only through ~c[fn] that ~c[sig-fn] inherits its constrained
  properties.

  This is a pathological example that illustrate a trap into which one may
  easily fall: rather than identify the key properties of the constrained
  function the user has foreshadowed its intended application and constrained
  those notions.  Clearly, the user wishing to introduce the ~c[sig-fn] above
  would be well-advised to use the following instead:
  ~bv[]
  (encapsulate
   (((sig-fn *) => *))
   (local (defun sig-fn (x) (declare (ignore x)) 0))
   (defthm integerp-sig-fn
     (integerp (sig-fn x))))
  
  (defun fn (lst)
    (if (endp lst)
        t
      (and (integerp (sig-fn (car lst)))
           (fn (cdr lst)))))
  
  (defthm fn-always-true
     (fn lst)))
  ~ev[]
  Note that ~c[sig-fn] is constrained merely to be an integer.  It is the only
  constrained function.  Now ~c[fn] is introduced after the encapsulation, as a
  simple function that uses ~c[sig-fn].  We prove that ~c[fn] always returns
  true, but this fact does not constrain ~c[sig-fn].  Future uses of ~c[sig-fn]
  do not have to consider ~c[fn] at all.

  Sometimes it is necessary to introduce a function such as ~c[fn] within the
  ~c[encapsulate] merely to state the key properties of the undefined function
  ~c[sig-fn].  But that is unusual and the user should understand that both
  functions are being constrained.

  Another subtle aspect of encapsulation that has been brushed over so far has
  to do with exactly how functions defined within the encapsulation use the
  signature functions.  For example, above we say ``Consider the collection of
  all formulas introduced by the encapsulate,
  ~em[except the definitional axioms], that mention these constrained
  functions.''  We seem to suggest that a definitional axiom which mentions a
  constrained function can be moved out of the encapsulation and considered
  part of the ``post-encapsulation'' extension of the logical ~il[world], if
  the defined function is not used in any non-definitional formula proved in
  the encapsulation.  For example, in the encapsulation above that constrained
  ~c[sig-fn] and introduced ~c[fn] within the encapsulation, ~c[fn] was
  constrained because we proved the formula ~c[fn-always-true] within the
  encapsulation.  Had we not proved ~c[fn-always-true] within the
  encapsulation, ~c[fn] could have been moved after the encapsulation.  But
  this suggests an unsound rule because whether such a function can be moved
  after the encapsulate depend on whether its ~em[admission] used properties of
  the witnesses!  In particular, we say a function is ``subversive'' if any of
  its governing tests or the actuals in any recursive call involve a function
  in which the signature functions are ancestral.  ~l[subversive-recursions].

  (Aside: The definition of ~c[fn] in the first enapsulation above that defines
  ~c[fn], i.e., the encapsulation with ~c[fn-always-true] inside, is subversive
  because the call of the macro ~ilc[AND] expands to a call of ~c[IF] that
  governs a recursive call of ~c[fn], in this case:
  ~bv[]
  (defun fn (lst)
    (if (endp lst)
        t
        (if (integerp (sig-fn (car lst)))
            (fn (cdr lst))
          nil))).
  ~ev[]
  If we switch the order of conjuncts in ~c[fn], then the definition of ~c[fn]
  is no longer subversive, but it still ``infects'' the constraint generated
  for the encapsulation, hence for ~c[sig-fn], because ~c[fn-always-true]
  blocks the definition of ~c[fn] from being moved back (to after the
  encapsulation).  If we both switch the order of conjuncts and drop
  ~c[fn-always-true] from the encapsulation, then the definition of ~c[fn] is
  in essence moved back to after the encapsulation, and the constraint for
  ~c[sig-fn] no longer includes the definition of ~c[fn].  End of aside.)

  Another aspect we have not discussed is what happens to nested encapsulations
  when each introduces constrained functions.  We say an ~c[encapsulate] event
  is ``trivial'' if it introduces no constrained functions, i.e., if its
  signatures is ~c[nil].  Trivial encapsulations are just a way to wrap up a
  collection of events into a single event.

  From the foregoing discussion we see we are interested in exactly how we can
  ``rearrange'' the events in a non-trivial encapsulation -- moving some
  ``before'' the encapsulation and others ``after'' the encapsulation.  We are
  also interested in which functions introduced by the encapsulation are
  ``constrained'' and what the ``constraints'' on each are.  We may summarize
  the observations above as follows, after which we conclude with a more
  elaborate example.

  ~em[Second cut at constraint-assigning algorithm.]  First, we focus only on
  non-trivial encapsulations that neither contain nor are contained in
  non-trivial encapsulations.  (Nested non-trivial encapsulations are not
  rearranged at all: do not put anything in such a nest unless you mean for it
  to become part of the constraints generated.)  Second, in what follows we
  only consider the non-~c[local] events of such an ~c[encapsulate], assuming
  that they satisfy the restriction of using no locally defined function
  symbols other than the signature functions.  Given such an ~c[encapsulate]
  event, move, to just in front of it and in the same order, all definitions
  and theorems for which none of the signature functions is ancestral.  Now
  collect up all formulas (theorems) introduced in the ~ilc[encapsulate] other
  than definitional axioms.  Add to this set any of those definitional
  equations that is either subversive or defines a function used in a formula
  in the set.  The conjunction of the resulting set of formulas is called the
  ``constraint'' and the set of all the signature functions of the
  ~c[encapsulate] together with all function symbols defined in the
  ~c[encapsulate] and mentioned in the constraint is called the ``constrained
  functions.''  Assign the constraint to each of the constrained functions.
  Move, to just after the ~c[encapsulate], the definitions of all function
  symbols defined in the ~c[encapsulate] that have been omitted from the
  constraint.

  Implementation note.  In the implementation we do not actually move
  ~il[events], but we create constraints that pretend that we did.

  Here is an example illustrating our constraint-assigning algorithm.  It
  builds on the preceding examples.
  ~bv[]
  (encapsulate
   (((sig-fn *) => *))

   (defun before1 (x)
     (if (consp x)
         (before1 (cdr x))
       x))

   (local (defun sig-fn (x) (cons x x)))

   (defthm sig-fn-prop
     (consp (sig-fn x)))

   (defun during (x)
     (if (consp x)
         x
       (cons (car (sig-fn x))
             17)))

   (defun before2 (x)
     (before1 x))

   (defthm before2-prop
     (atom (before2 x)))

   (defthm during-prop
     (implies (and (atom x)
                   (before2 x))
              (equal (car (during x))
                     (car (sig-fn x)))))

   (defun after1 (x)
     (sig-fn x))

   (defchoose after2 (x) (u)
     (and (< u x) (during x)))
   )
  ~ev[]

  Only the functions ~c[sig-fn] and ~c[during] receive extra constraints.  The
  functions ~c[before1] and ~c[before2] are viewed as moving in front of the
  ~ilc[encapsulate], as is the theorem ~c[before2-prop].  The functions
  ~c[after1] and ~c[after2] are viewed as being moved past the
  ~ilc[encapsulate].  The implementation reports the following.
  ~bv[]
  In addition to SIG-FN, we export AFTER2, AFTER1, BEFORE2, DURING and
  BEFORE1.

  The following constraint is associated with both of the functions DURING and
  SIG-FN:

  (AND (EQUAL (DURING X)
              (IF (CONSP X)
                  X (CONS (CAR (SIG-FN X)) 17)))
       (CONSP (SIG-FN X))
       (IMPLIES (AND (ATOM X) (BEFORE2 X))
                (EQUAL (CAR (DURING X))
                       (CAR (SIG-FN X)))))
  ~ev[]
  Notice that the formula ~c[(consp (during x))] is not a conjunct of the
  constraint.  During the first pass of the ~c[encapsulate], this formula is
  stored as a ~c[:]~ilc[type-prescription] rule deduced during the definition
  of the function ~c[during].  However, the rule is not exported because of a
  rather subtle soundness issue.  (If you are interested in details, see the
  comments in source function ~c[putprop-type-prescription-lst].)

  We conclude by asking (and to a certain extent, answering) the following
  question: Isn't there an approach to assigning constraints that avoids
  over-constraining more simply than our ``second cut'' above?  Perhaps it
  seems that given an ~ilc[encapsulate], we should simply assign to each
  locally defined function the theorems exported about that function.  If we
  adopted that simple approach the events below would be admissible.

  ~bv[]
  (encapsulate
   (((foo *) => *))
   (local (defun foo (x) x))
   (defun bar (x)
     (foo x))
   (defthm bar-prop
     (equal (bar x) x)
     :rule-classes nil))

  (defthm foo-id
    (equal (foo x) x)
    :hints ((\"Goal\" :use bar-prop)))

  ; The following event is not admissible in ACL2.

  (defthm ouch!
    nil
    :rule-classes nil
    :hints
    ((\"Goal\" :use
      ((:functional-instance foo-id
                             (foo (lambda (x) (cons x x))))))))
  ~ev[]
  Under the simple approach we have in mind, ~c[bar] is constrained to satisfy
  both its definition and ~c[bar-prop] because ~c[bar] mentions a function
  declared in the signature list of the encapsulation.  In fact, ~c[bar] is
  so-constrained in the ACL2 semantics of encapsulation and the first two
  events above (the ~c[encapsulate] and the consequence that ~c[foo] must be
  the identity function) are actually admissible.  But under the simple
  approach to assigning constraints, ~c[foo] is unconstrained because no
  theorem about it is exported.  Under that approach, ~c[ouch!] is provable
  because ~c[foo] can be instantiated in ~c[foo-id] to a function other than
  the identity function.

  It's tempting to think we can fix this by including definitions, not just
  theorems, in constraints.  But consider the following slightly more elaborate
  example.  The problem is that we need to include as a constraint on ~c[foo]
  not only the definition of ~c[bar], which mentions ~c[foo] explicitly, but
  also ~c[abc], which has ~c[foo] as an ancestor.
  ~bv[]
  (encapsulate
   (((foo *) => *))
   (local (defun foo (x) x))
   (local (defthm foo-prop
            (equal (foo x) x)))
   (defun bar (x)
     (foo x))
   (defun abc (x)
     (bar x))
   (defthm abc-prop
     (equal (abc x) x)
     :rule-classes nil))

  (defthm foo-id
    (equal (foo x) x)
    :hints ((\"Goal\" :use abc-prop)))

  ; The following event is not admissible in ACL2.

  (defthm ouch!
    nil
    :rule-classes nil
    :hints
    ((\"Goal\" :use
      ((:functional-instance foo-id
                             (foo (lambda (x) (cons x x)))
                             (bar (lambda (x) (cons x x))))))))
  ~ev[]
  ")  

(defun chk-equal-arities (fn1 n1 fn2 n2 ctx state)
  (cond
   ((not (equal n1 n2))
    (er soft ctx
        "It is illegal to replace ~x0 by ~x1 because the former ~
         ~#2~[takes no arguments~/takes one argument~/takes ~n3 ~
         arguments~] while the latter ~#4~[takes none~/takes ~
         one~/takes ~n5~].  See the :functional-instance discussion ~
         in :MORE-DOC :lemma-instance."
        fn1
        fn2
        (cond ((int= n1 0) 0)
              ((int= n1 1) 1)
              (t 2))
        n1
        (cond ((int= n2 0) 0)
              ((int= n2 1) 1)
              (t 2))
        n2))
   (t (value nil))))

(defun extend-sorted-symbol-alist (pair alist)
  (cond
   ((endp alist)
    (list pair))
   ((symbol-< (car pair) (caar alist))
    (cons pair alist))
   (t
    (cons (car alist)
          (extend-sorted-symbol-alist pair (cdr alist))))))

;; RAG - This checks to see whether two function symbols are both
;; classical or both non-classical

#+:non-standard-analysis
(defun chk-equiv-classicalp (fn1 fn2 termp ctx wrld state)
  (let ((cp1 (classicalp fn1 wrld))
        (cp2 (if termp ; fn2 is a term, not a function symbol
                 (classical-fn-list-p (all-fnnames fn2) wrld)
               (classicalp fn2 wrld))))
    (if (equal cp1 cp2)
        (value nil)
      (er soft ctx
        "It is illegal to replace ~x0 by ~x1 because the former ~
         ~#2~[is classical~/is not classical~] while the latter ~
         ~#3~[is~/is not~]."
        (if (symbolp fn1) fn1 (untranslate fn1 nil wrld))
        (if (symbolp fn2) fn2 (untranslate fn2 nil wrld))
        (if cp1 0 1)
        (if cp2 0 1)))))

;; RAG - I modified the following, so that we do not allow substn to
;; map a non-classical constrained function into a classical function
;; or vice versa.

(defun translate-functional-substitution (substn ctx wrld state)

; Substn is alleged to be a functional substitution.  We know that it is a true
; list!  We check that each element is a pair of the form (fn1 fn2), where fn1
; is an instantiable function symbol of arity n and fn2 is either a function
; symbol of arity n or else a lambda expression of arity n with a body that
; translates.  We also check that no fn1 is bound twice.

; Note: We permit free variables to occur in the body, we permit implicitly
; ignored variables, and we do not permit declarations in the lambda.  That is,
; we take each lambda to be of the form (lambda (v1 ... vn) body) and we merely
; insist that body be a term with no particular relation to the vi.

; If substn satisfies these conditions we return an alist in which each pair
; has the form (fn1 . fn2'), where fn2' is the symbol fn2 or the lambda
; expression (lambda (v1 ... vn) body'), where body' is the translation of
; body.  We call this the translated functional substitution.  The returned
; result is sorted by car; see event-responsible-for-proved-constraint for how
; we make use of this fact.

; Warning: The presence of free variables in the lambda expressions means that
; capturing is possible during functional substitution.  We do not check that
; no capturing occurs, since we are not given the terms into which we will
; substitute.

  (cond
   ((null substn) (value nil))
   ((not (and (true-listp (car substn))
              (= (length (car substn)) 2)))
    (er soft ctx
        "The object ~x0 is not of the form (fi gi) as described in ~
         the :functional-instance discussion of :MORE-DOC lemma-instance."
        (car substn)))
   (t (let ((fn1 (caar substn))
            (fn2 (cadar substn))
            (str "The object ~x0 is not of the form (fi gi) as ~
                  described in the :functional-instance discussion of ~
                  :MORE-DOC lemma-instance.  ~x1 is neither a ~
                  function symbol nor a pseudo-lambda expression."))
        (cond
         ((not (and (symbolp fn1)
                    (function-symbolp fn1 wrld)))
          (er soft ctx
              "Each domain element in a functional substitution must ~
               be a function symbol, but ~x0 is not.  See the :functional-~
               instance discussion of :MORE-DOC lemma-instance."
              fn1))
         ((not (eq (instantiablep fn1 wrld) t))
          (er soft ctx
              "The function symbol ~x0 cannot be instantiated~@1.  See the ~
               :functional-instance discussion about `instantiable' in :DOC ~
               lemma-instance."
              fn1
              (if (eq (instantiablep fn1 wrld) nil)
                  ""
                (msg " because it was introduced in an encapsulate ~
                      specifying a dependent clause-processor, ~x0 (see DOC ~
                      define-trusted-clause-processor)"
                     (instantiablep fn1 wrld)))))
         (t
          (er-let*
           ((x
             (cond
              ((symbolp fn2)
               (let ((fn2 (deref-macro-name fn2 (macro-aliases wrld))))
                 (cond
                  ((function-symbolp fn2 wrld)
                   (er-progn
                    (chk-equal-arities fn1 (arity fn1 wrld)
                                       fn2 (arity fn2 wrld)
                                       ctx state)
                    #+:non-standard-analysis
                    (chk-equiv-classicalp fn1 fn2 nil ctx wrld state)
                    (value (cons fn1 fn2))))
                  (t (er soft ctx str (car substn) fn2)))))
              ((and (true-listp fn2)
                    (= (length fn2) 3)
                    (eq (car fn2) 'lambda))
               (er-let*
                ((body
                  (translate (caddr fn2) t t t ctx wrld state)))
; known-stobjs = t (stobjs-out = t)
                (er-progn
                 (chk-arglist (cadr fn2) t ctx wrld state)
                 (chk-equal-arities fn1 (arity fn1 wrld)
                                    fn2 (length (cadr fn2))
                                    ctx state)
                 #+:non-standard-analysis
                 (chk-equiv-classicalp fn1 body t ctx wrld state)
                 (value (cons fn1 (make-lambda (cadr fn2) body))))))
              (t (er soft ctx str (car substn) fn2))))
            (y
             (translate-functional-substitution (cdr substn)
                                                ctx wrld state)))
           (cond ((assoc-eq fn1 y)
                  (er soft ctx
                      "It is illegal to bind ~x0 twice in a ~
                       functional substitution.  See the ~
                       :functional-instance discussion of :MORE-DOC ~
                       lemma-instance."
                      fn1))
                 (t (value (extend-sorted-symbol-alist x y)))))))))))

(mutual-recursion

; After Version_3.4, Ruben Gamboa added the variable allow-freevars-p, with the
; following explanation:

; Allow-freevars-p should be set to t in the #-:non-standard-analysis case, but
; otherwise set to nil when we are trying to apply the substitution to a
; non-classical formula.  In those cases, free variables in the body can
; capture non-standard objects, resulting in invalid theorems.  For example,
; take the following theorem
;
; (standardp x) => (standardp (f x))
;
; This theorem is true for classical constrained function f.  Now instantiate
; (f x) with (lambda (x) (+ x y)).  The result is
;
; (standardp x) => (standardp (+ x y))
;
; This formula is false.  E.g., it fails when x=0 and y=(i-large-integer).

(defun sublis-fn-rec (alist term bound-vars allow-freevars-p)

; See the comment just above for additional discussion of allow-freevars-p.

; This function carries out the functional substitution into term specified by
; the translated functional substitution alist.  It checks that alist does not
; allow capturing of its free variables by lambda expressions in term and that
; the alist does not have free variables in lambda expressions when
; allow-freevars-p is nil, either returning (mv vars term) for vars a non-empty
; list of variables having captured occurrences (or when allow-freevars-p is
; nil), or else returning (mv nil new-term) if there are no such captures or
; invalid free variables, in which case new-term is the result of the
; functional substitution.  Note that the caller can tell whether an error is
; caused by capturing or by having disallowed free variables, since in the case
; that allow-freevars-p is nil, it is impossible for free variables to be
; captured (since no free variables are allowed).

; Let us say that an occurrence of fn in term is problematic if fn is bound to
; lambda-expr in alist and for every variable v that occurs free in
; lambda-expr, this occurrence of fn is not in the scope of a lambda binding of
; v.  Key Observation: If there is no problematic occurrence of any function
; symbol in term, then we can obtain the result of this call of sublis-fn by
; first replacing v in lambda-app by a fresh variable v', then carrying out the
; functional substitution, and finally doing an ordinary substitution of v for
; v'.  This Key Observation explains why it suffices to check that there is no
; such problematic occurrence.  We maintain bound-vars as we recur to be a list
; that includes all variables bound in the original term at the present
; occurrence of term.

; Every element of alist is either of the form (fn . sym) or of the form (fn
; . (LAMBDA (v1...vn) body)) where the vi are distinct variables and body is a
; translated term, but it is not known that body mentions only vars in formals.

; The former case, where fn is bound to a sym, is simple to handle: when we see
; calls of fn we replace them by calls of sym.  The latter case is not.  When
; we hit (g (FOO) y) with the functional substitution in which FOO gets (LAMBDA
; NIL X), we generate (g X y).  Note that this "imports" a free X into a term,
; (g (foo) y), where there was no X.

; But there is a problem.  If you hit ((lambda (z) (g (FOO) z)) y) with FOO
; gets (LAMBDA NIL X), you would naively produce ((lambda (z) (g X z)) y),
; importing the X into the G term as noted above.  But we also just imported
; the X into the scope of a lambda!  Even though there is no capture, we now
; have a lambda expression whose body contains a var not among the formals.
; That is not a term!

; The solution is to scan the new lambda body, which is known to be a term, and
; collect the free vars -- vars not bound among the formals of the lambda --
; and add them both to the lambda formals and to the actuals.

  (cond
   ((variablep term) (mv nil term))
   ((fquotep term) (mv nil term))
   ((flambda-applicationp term)
    (let ((old-lambda-formals (lambda-formals (ffn-symb term))))
      (mv-let
       (erp new-lambda-body)
       (sublis-fn-rec alist
                      (lambda-body (ffn-symb term))
                      (append old-lambda-formals bound-vars)
                      allow-freevars-p)
       (cond
        (erp (mv erp new-lambda-body))
        (t (mv-let
            (erp args)
            (sublis-fn-rec-lst alist (fargs term) bound-vars allow-freevars-p)
            (cond (erp (mv erp args))
                  (t (let* ((body-vars (all-vars new-lambda-body))
                            (extra-body-vars
                             (set-difference-eq body-vars
                                                old-lambda-formals)))
                       (mv nil
                           (fcons-term
                            (make-lambda
                             (append old-lambda-formals extra-body-vars)
                             new-lambda-body)
                            (append args extra-body-vars))))))))))))
   (t (let ((temp (assoc-eq (ffn-symb term) alist)))
        (cond
         (temp
          (cond ((symbolp (cdr temp))
                 (mv-let
                  (erp args)
                  (sublis-fn-rec-lst alist (fargs term) bound-vars
                                     allow-freevars-p)
                  (cond (erp (mv erp args))
                        (t (mv nil
                               (cons-term (cdr temp) args))))))
                (t
                 (let ((bad (if allow-freevars-p
                                (intersectp-eq (set-difference-eq
                                                (all-vars (lambda-body (cdr temp)))
                                                (lambda-formals (cdr temp)))
                                               bound-vars)
                              (set-difference-eq
                               (all-vars (lambda-body (cdr temp)))
                               (lambda-formals (cdr temp))))))
                   (cond
                    (bad (mv bad term))
                    (t (mv-let
                        (erp args)
                        (sublis-fn-rec-lst alist (fargs term) bound-vars
                                           allow-freevars-p)
                        (cond (erp (mv erp args))
                              (t (mv nil
                                     (sublis-var
                                      (pairlis$ (lambda-formals (cdr temp))
                                                args)
                                      (lambda-body (cdr temp)))))))))))))
         (t (mv-let (erp args)
                    (sublis-fn-rec-lst alist (fargs term) bound-vars
                                       allow-freevars-p)
                    (cond (erp (mv erp args))
                          (t (mv nil
                                 (cons-term (ffn-symb term) args)))))))))))

(defun sublis-fn-rec-lst (alist terms bound-vars allow-freevars-p)
  (cond ((null terms) (mv nil nil))
        (t (mv-let
            (erp term)
            (sublis-fn-rec alist (car terms) bound-vars allow-freevars-p)
            (cond (erp (mv erp term))
                  (t (mv-let
                      (erp tail)
                      (sublis-fn-rec-lst alist (cdr terms) bound-vars
                                         allow-freevars-p)
                      (cond (erp (mv erp tail))
                            (t (mv nil (cons term tail)))))))))))

)

(defun sublis-fn (alist term bound-vars)

; This is just the usual case.  We call the more general function
; sublis-fn-rec, which can be used on the non-standard case.

  (sublis-fn-rec alist term bound-vars t))

(defun sublis-fn-simple (alist term)

; This is the normal case, in which we call sublis-fn with no bound vars and we
; expect no vars to be captured (say, because alist has no free variables).

  (mv-let (vars result)
          (sublis-fn-rec alist term nil t)
          (assert$ (null vars)
                   result)))

(defun sublis-fn-lst-simple (alist termlist)

; See sublis-fn-simple, as this is the analogous function for a list of terms.

  (mv-let (vars result)
          (sublis-fn-rec-lst alist termlist nil t)
          (assert$ (null vars)
                   result)))

(mutual-recursion

(defun instantiable-ffn-symbs (term wrld ans ignore-fns)

; We collect every instantiablep ffn-symb occurring in term except those listed
; in ignore-fns.  We include functions introduced by an encapsulate specifying
; a dependent clause-processor.

  (cond
   ((variablep term) ans)
   ((fquotep term) ans)
   ((flambda-applicationp term)
    (let ((ans (instantiable-ffn-symbs (lambda-body (ffn-symb term))
                                       wrld
                                       ans
                                       ignore-fns)))
      (instantiable-ffn-symbs-lst (fargs term)
                                  wrld
                                  ans
                                  ignore-fns)))
   (t (instantiable-ffn-symbs-lst
       (fargs term)
       wrld
       (cond ((or (not (instantiablep (ffn-symb term) wrld))
                  (member-eq (ffn-symb term) ignore-fns))
              ans)
             (t (add-to-set-eq (ffn-symb term) ans)))
       ignore-fns))))

(defun instantiable-ffn-symbs-lst (lst wrld ans ignore-fns)
  (cond ((null lst) ans)
        (t
         (instantiable-ffn-symbs-lst (cdr lst)
                                     wrld
                                     (instantiable-ffn-symbs (car lst) wrld ans
                                                             ignore-fns)
                                     ignore-fns))))

)

(defun unknown-constraint-supporters (fn wrld)

; Fn is the constraint-lst property of some function g with a non-Boolean
; constraint-lst property, indicating that g was introduced in a dependent
; clause-processor.  The ancestors of g are guaranteed to be among the closure
; under ancestors of the supporters stored for fn in the
; trusted-clause-processor-table.

  (let ((entry (assoc-eq fn (table-alist 'trusted-clause-processor-table
                                         wrld))))
    (cond ((or (null entry)
               (not (eq (cddr entry) t)))
           (er hard 'unknown-constraint-supporters
               "Implementation error: Function ~x0 was called on ~x1, which ~
                was expected to be a dependent clause-processor function, but ~
                apparently is not."
               'unknown-constraint-supporters
               fn))
          (t (cadr entry)))))

(defun collect-instantiablep1 (fns wrld ignore-fns)

; We assume that fns has no duplicates.

  (cond ((endp fns) nil)
        ((and (not (member-eq (car fns) ignore-fns))
              (instantiablep (car fns) wrld))
         (cons (car fns)
               (collect-instantiablep1 (cdr fns) wrld ignore-fns)))
        (t (collect-instantiablep1 (cdr fns) wrld ignore-fns))))

(defun all-instantiablep (fns wrld)
  (cond ((endp fns) t)
        ((instantiablep (car fns) wrld)
         (all-instantiablep (cdr fns) wrld))
        (t nil)))

(defun collect-instantiablep (fns wrld ignore-fns)

; We assume that fns has no duplicates.

  (cond ((and (not (intersectp-eq fns ignore-fns))
              (all-instantiablep fns wrld))
         fns)
        (t (collect-instantiablep1 fns wrld ignore-fns))))

(defun immediate-instantiable-ancestors (fn wrld ignore-fns)

; We return the list of all the instantiable function symbols ('instantiablep
; property t) that are immediate supporters of the introduction of fn, except
; those appearing in ignore-fns.

; If there are (possibly empty) constraints associated with fn, then we get all
; of the instantiable function symbols used in the constraints, which includes
; the definitional axiom if there is one.  Note that the case of a dependent
; clause-processor with *unknown-constraints* is a bit different, as we use its
; supporters appropriately stored in a table.

; If fn was introduced by a defun or defchoose (it should be a non-primitive),
; we return the list of all instantiable functions used in its introduction.
; Note that even if fn is introduced by a defun, it may have constraints if its
; definition was within the scope of an encapsulate, in which case the
; preceding paragraph applies.

; If fn is introduced any other way we consider it primitive and all of the
; axioms about it had better involve non-instantiable symbols, so the answer is
; nil.

; Note: We pass down ignore-fns simply to avoid consing into our answer a
; function that the caller is going to ignore anyway.  It is possible for fn to
; occur as an element of its "immediate ancestors" as computed here.  This
; happens, for example, if fn is defun'd recursively and fn is not in
; ignore-fns.  At the time of this writing the only place we use
; immediate-instantiable-ancestors is in ancestors, where fn is always in
; ignore-fns (whether fn is recursive or not).

  (mv-let (name x)
          (constraint-info fn wrld)
    (cond
     ((eq x *unknown-constraints*)
      (let* ((cl-proc
              (getprop name 'constrainedp
                       '(:error
                         "See immediate-instantiable-ancestors:  expected to ~
                          find a 'constrainedp property where we did not.")
                       'current-acl2-world wrld))
             (supporters (unknown-constraint-supporters cl-proc wrld)))
        (collect-instantiablep supporters wrld ignore-fns)))
     (name (instantiable-ffn-symbs-lst x wrld nil ignore-fns))
     (t (instantiable-ffn-symbs x wrld nil ignore-fns)))))

(defun instantiable-ancestors (fns wrld ans)

; Fns is a list of function symbols.  We compute the list of all instantiable
; function symbols that are ancestral to the functions in fns and accumulate
; them in ans, including those introduced in an encapsulate specifying a
; dependent clause-processor.

  (cond
   ((null fns) ans)
   ((member-eq (car fns) ans)
    (instantiable-ancestors (cdr fns) wrld ans))
   (t
    (let* ((ans1 (cons (car fns) ans))
           (imm (immediate-instantiable-ancestors (car fns) wrld ans1))
           (ans2 (instantiable-ancestors imm wrld ans1)))
      (instantiable-ancestors (cdr fns) wrld ans2)))))

(mutual-recursion

(defun hitp (term alist)

; Alist is a translated functional substitution.  We return t iff
; term mentions some function symbol in the domain of alist.

  (cond ((variablep term) nil)
        ((fquotep term) nil)
        ((flambda-applicationp term)
         (or (hitp (lambda-body (ffn-symb term)) alist)
             (hitp-lst (fargs term) alist)))
        ((assoc-eq (ffn-symb term) alist) t)
        (t (hitp-lst (fargs term) alist))))

(defun hitp-lst (terms alist)
  (cond ((null terms) nil)
        (t (or (hitp (car terms) alist)
               (hitp-lst (cdr terms) alist)))))

)

(defun event-responsible-for-proved-constraint (name alist
                                                     proved-fnl-insts-alist)

; For context, see the Essay on the proved-functional-instances-alist.

; Here proved-fnl-insts-alist is of the form of the world global
; 'proved-functional-instances-alist.  Thus, it is a list of entries of the
; form (constraint-event-name restricted-alist . behalf-of-event-name), where
; constraint-event-name is the name of an event such that the functional
; instance of that event's constraint (i.e., function's constraint or axiom's
; 'theorem property) by restricted-alist was proved on behalf of the event
; named behalf-of-event-name.

  (cond
   ((endp proved-fnl-insts-alist)
    nil)
   ((and (eq name
             (access proved-functional-instances-alist-entry
                     (car proved-fnl-insts-alist)
                     :constraint-event-name))
         (equal alist
                (access proved-functional-instances-alist-entry
                        (car proved-fnl-insts-alist)
                        :restricted-alist)))

; We allow the behalf-of-event-name field (see comment above) to be nil in
; temporary versions of this sort of data structure, but we do not expect to
; find nil for that field in proved-fnl-insts-alist, which comes from the ACL2
; world.  (We store 0 there when there is no event name to use, e.g. when the
; event was a verify-guards event.  See the call of
; proved-functional-instances-from-tagged-objects in install-event.)  But to be
; safe in avoiding confusion with the first branch of our cond (in which there
; is no appropriate entry for our proof obligation), we check for nil here.

    (or (access proved-functional-instances-alist-entry
                (car proved-fnl-insts-alist)
                :behalf-of-event-name)
        (er hard 'event-responsible-for-proved-constraint
            "Implementation error: We expected to find a non-nil ~
             :behalf-of-event-name field in the following entry of the world ~
             global 'proved-functional-instances-alist, but did not:~%~x0."
            (car proved-fnl-insts-alist))))
   (t (event-responsible-for-proved-constraint
       name alist (cdr proved-fnl-insts-alist)))))

(defun getprop-x-lst (symbols prop wrld)
  (cond ((null symbols) nil)
        (t (cons (getprop (car symbols) prop nil
                          'current-acl2-world wrld)
                 (getprop-x-lst (cdr symbols) prop wrld)))))

(defun filter-hitps (lst alist ans)
  (cond
   ((endp lst) ans)
   ((hitp (car lst) alist)
    (filter-hitps (cdr lst) alist (cons (car lst) ans)))
   (t (filter-hitps (cdr lst) alist ans))))

(defun relevant-constraints1 (names alist proved-fnl-insts-alist constraints
                                    event-names new-entries seen wrld)

; For context, see the Essay on the proved-functional-instances-alist.

; Names is a list of function symbols, each of which therefore has a constraint
; formula.  We return three values, corresponding respectively to the following
; three formals, which are initially nil:  constraints, event-names, and
; new-entries.  The first value is the result of collecting those constraint
; formulas that are hit by the translated functional substitution alist, except
; for those that are known (via proved-fnl-insts-alist) to have already been
; proved.  The second is a list of names of events responsible for the validity
; of the omitted formulas.  The third is a list of pairs (cons name
; restr-alist), where restr-alist is obtained by restricting the given alist to
; the instantiable function symbols occurring in the constraint generated by
; name (in the sense of constraint-info).

; Exception: We are free to return (mv *unknown-constraints* g cl-proc).
; However, we only do so if the constraints cannot be determined because of the
; presence of unknown constraints on some function g encountered, where g was
; introduced with the designation of a dependent clause-processor, cl-proc.  We
; ignore this exceptional case in the comments just below.

; Seen is a list of names already processed.  Suppose that foo and bar are both
; constrained by the same encapsulate, and that the 'constraint-lst property of
; 'bar is 'foo.  Since both foo and bar generate the same constraint, we want
; to be sure only to process that constraint once.  So, we put foo on the list
; seen as soon as bar is processed, so that foo will not have to be processed.

; Note that the current ttree is not available here.  If it were, we could
; choose to avoid proving constraints that were already generated in the
; current proof.  It doesn't seem that this would buy us very much, though:
; how often does one find more than one :functional-instance lemma instance in
; a single proof, especially with overlapping constraints?

; See also relevant-constraints1-axioms, which is a similar function for
; collecting constraint information from defaxiom events.

  (cond ((null names) (mv constraints event-names new-entries))
        ((member-eq (car names) seen)
         (relevant-constraints1
          (cdr names) alist proved-fnl-insts-alist
          constraints event-names new-entries seen wrld))
        (t (mv-let
            (name x)
            (constraint-info (car names) wrld)

; Note that if x is not *unknown-constraints*, then x is a single constraint if
; name is nil and otherwise x is a list of constraints.

            (cond
             ((eq x *unknown-constraints*)
              (mv x
                  name
                  (getprop name 'constrainedp
                           '(:error
                             "See relevant-constraints1: expected to find a ~
                              'constrainedp property where we did not.")
                           'current-acl2-world wrld)))
             ((and name
                   (not (eq name (car names)))

; Minor point:  the test immediately above is subsumed by the one below, since
; we already know at this point that (not (member-eq (car names) seen)), but we
; keep it in for efficiency.

                   (member-eq name seen))
              (relevant-constraints1
               (cdr names) alist proved-fnl-insts-alist
               constraints event-names new-entries
               (cons (car names) seen) wrld))
             (t
              (let* ((x (cond (name (filter-hitps x alist nil))
                              ((hitp x alist) x)

; We continue to treat x as a list of constraints or a single constraint,
; depending respectively on whether name is non-nil or nil; except, we will
; use nil for x when there are no constraints even when name is nil.

                              (t nil)))
                     (instantiable-fns
                      (and x ; optimization
                           (cond (name (instantiable-ffn-symbs-lst
                                        x wrld nil nil))
                                 (t (instantiable-ffn-symbs
                                     x wrld nil nil))))))
                (let* ((constraint-alist
                        (and x ; optimization
                             (restrict-alist instantiable-fns alist)))
                       (ev
                        (and x ; optimization: ev unused when (null x) below
                             (event-responsible-for-proved-constraint
                              (or name (car names))
                              constraint-alist
                              proved-fnl-insts-alist)))
                       (seen (cons (car names)
                                   (if (and name (not (eq name (car names))))
                                       (cons name seen)
                                     seen))))
                  (cond
                   ((null x)
                    (relevant-constraints1
                     (cdr names) alist proved-fnl-insts-alist
                     constraints event-names new-entries
                     seen
                     wrld))
                   (ev (relevant-constraints1
                        (cdr names) alist proved-fnl-insts-alist
                        constraints

; Notice that ev could be 0; see event-responsible-for-proved-constraint.
; Where do we handle such an "event name"?  Here is an inverted call stack:

;           relevant-constraints1             ; called by:
;           relevant-constraints              ; called by:
;           translate-lmi/functional-instance ; called by:
;           translate-lmi                     ; called by:
; translate-use-hint(1)   translate-by-hint   ; called by:
;           translate-x-hint-value

; So, hints are translated.  Who looks at the results?  Well,
; apply-top-hints-clause adds :use and :by to the tag-tree.
; Who looks at the tag-tree?  It's
; apply-top-hints-clause-msg1, which in turn calls
; tilde-@-lmi-phrase -- and THAT is who sees and handles an "event" of 0.
; We might want to construct an example that illustrates this "0 handling" by
; way of providing a :functional-instance lemma-instance in a verify-guards.

                        (add-to-set ev event-names)
                        new-entries
                        seen
                        wrld))
                   (t (relevant-constraints1
                       (cdr names) alist proved-fnl-insts-alist
                       (if name
                           (append x constraints)
                         (cons x constraints))
                       event-names

; On which name's behalf do we note the constraint-alist?  If name is not nil,
; then it is a "canonical" name for which constraint-info returns the
; constraints we are using, in the sense that its constraint-lst is a list.
; Otherwise, (car names) is the name used to obtain constraint-info.

                       (cons (make proved-functional-instances-alist-entry
                                   :constraint-event-name (or name
                                                              (car names))
                                   :restricted-alist constraint-alist
                                   :behalf-of-event-name

; Eventually, the ``nil'' below may be filled in with the event name on behalf
; of which we are carrying out the current proof.

                                   nil)
                             new-entries)
                       seen
                       wrld)))))))))))

(defun relevant-constraints1-axioms (names alist proved-fnl-insts-alist
                                           constraints event-names new-entries
                                           wrld)

; For context, see the Essay on the proved-functional-instances-alist.

; This function is similar to relevant-constraints1, and should be kept more or
; less conceptually in sync with it.  However, in this function, names is a
; list of distinct axiom names rather than function names.  See
; relevant-constraints1 for comments.

  (cond ((null names) (mv constraints event-names new-entries))
        (t (let* ((constraint
                   (getprop (car names)
                            'theorem
                            '(:error "See relevant-constraints1-axioms.")
                            'current-acl2-world wrld))
                  (instantiable-fns
                   (instantiable-ffn-symbs constraint wrld nil nil)))
             (cond ((hitp constraint alist)
                    (let* ((constraint-alist
                            (restrict-alist
                             instantiable-fns
                             alist))
                           (ev (event-responsible-for-proved-constraint
                                (car names)
                                constraint-alist
                                proved-fnl-insts-alist)))
                      (cond
                       (ev (relevant-constraints1-axioms
                            (cdr names) alist proved-fnl-insts-alist
                            constraints
                            (add-to-set ev event-names)
                            new-entries
                            wrld))
                       (t (relevant-constraints1-axioms
                           (cdr names) alist proved-fnl-insts-alist
                           (cons constraint constraints)
                           event-names
                           (cons (make proved-functional-instances-alist-entry
                                       :constraint-event-name (car names)
                                       :restricted-alist constraint-alist
                                       :behalf-of-event-name nil)
                                 new-entries)
                           wrld)))))
                   (t (relevant-constraints1-axioms
                       (cdr names) alist proved-fnl-insts-alist
                       constraints event-names new-entries
                       wrld)))))))

(defun relevant-constraints (thm alist proved-fnl-insts-alist wrld)

; For context, see the Essay on the proved-functional-instances-alist.

; Thm is a term and alist is a translated functional substitution.  We return
; three values.  The first value is the list of the constraints that must be
; instantiated with alist and proved in order to justify the functional
; instantiation of thm.  The second value is a list of names of events on whose
; behalf proof obligations were not generated that would otherwise have been,
; because those proof obligations were proved during processing of those
; events.  (In such cases we do not include these constraints in our first
; value.)  Our third and final value is a list of new entries to add to the
; world global 'proved-functional-instances-alist, as described in the comment
; for event-responsible-for-proved-constraint.

; Keep the following comment in sync with the corresponding comment in
; defaxiom-supporters.

; The relevant theorems are the set of all terms, term, such that
;   (a) term mentions some function symbol in the domain of alist,
;   AND
;   (b) either
;      (i) term arises from a definition of or constraint on a function symbol
;          ancestral either in thm or in some defaxiom,
;       OR
;      (ii) term is the body of a defaxiom.
; In translate-lmi/functional-instance we check that variable capture is
; avoided.

  (let ((nonconstructive-axiom-names
         (global-val 'nonconstructive-axiom-names wrld)))
    (mv-let
     (constraints event-names new-entries)
     (relevant-constraints1-axioms
      nonconstructive-axiom-names alist proved-fnl-insts-alist
      nil nil nil
      wrld)
     (assert$
      (not (eq constraints *unknown-constraints*))
      (let* ((instantiable-fns
              (instantiable-ffn-symbs-lst
               (cons thm (getprop-x-lst nonconstructive-axiom-names
                                        'theorem wrld))
               wrld nil nil))
             (ancestors (instantiable-ancestors instantiable-fns wrld nil)))
        (relevant-constraints1 ancestors alist proved-fnl-insts-alist
                               constraints event-names new-entries nil
                               wrld))))))

(mutual-recursion

(defun bound-vars (term ans)
  (cond ((variablep term) ans)
        ((fquotep term) ans)
        ((flambda-applicationp term)
         (bound-vars
          (lambda-body (ffn-symb term))
          (bound-vars-lst (fargs term)
                                  (union-eq (lambda-formals (ffn-symb term))
                                            ans))))
        (t (bound-vars-lst (fargs term) ans))))

(defun bound-vars-lst (terms ans)
  (cond ((null terms) ans)
        (t (bound-vars-lst
            (cdr terms)
            (bound-vars (car terms) ans)))))

)

(defun translate-lmi/instance
  (formula constraints event-names new-entries substn ctx wrld state)

; Formula is some term, obtained by previous instantiations.  Constraints
; are the constraints generated by those instantiations -- i.e., if the
; constraints are theorems then formula is a theorem.  Substn is an
; alleged variable substitution.  We know substn is a true list.

; Provided substn indeed denotes a substitution that is ok to apply to formula,
; we create the instance of formula.  We return a list whose car is the
; instantiated formula and whose cdr is the incoming constraints, event-names
; and new-entries, which all pass through unchanged.  Otherwise, we cause an
; error.

  (er-let*
   ((alist (translate-substitution substn ctx wrld state)))
   (let* ((vars (all-vars formula))
          (un-mentioned-vars (set-difference-eq (strip-cars alist) vars)))
          (cond
           (un-mentioned-vars
             (er soft ctx
                 "The formula you wish to instantiate, ~p3, mentions ~
                  ~#0~[no variables~/only the variable ~&1~/the ~
                  variables ~&1~].  Thus, there is no reason to ~
                  include ~&2 in the domain of your substitution.  We ~
                  point this out only because it frequently indicates ~
                  that a mistake has been made.  See the :instance ~
                  discussion in :MORE-DOC lemma-instance."
                 (zero-one-or-more vars)
                 (merge-sort-symbol-< vars)
                 (merge-sort-symbol-< un-mentioned-vars)
                 (untranslate formula t wrld)))
           (t (value (list (sublis-var alist formula)
                           constraints
                           event-names
                           new-entries)))))))

(defun translate-lmi/functional-instance (formula constraints event-names
                                                  new-entries substn
                                                  proved-fnl-insts-alist
                                                  ctx wrld state)

; For context, see the Essay on the proved-functional-instances-alist.

; Formula is some term, obtained by previous instantiations.  Constraints are
; the constraints generated by those instantiations -- i.e., if the constraints
; are theorems then formula is a theorem.  Substn is an untranslated object
; alleged to be a functional substitution.

; Provided substn indeed denotes a functional substitution that is ok to apply
; to both formula and the new constraints imposed, we create the functional
; instance of formula and the new constraints to prove.  We return a pair whose
; car is the instantiated formula and whose cdr is the incoming constraints
; appended to the new ones added by this functional instantiation.  Otherwise,
; we cause an error.

  (er-let*
   ((alist (translate-functional-substitution substn ctx wrld state)))
   (mv-let
    (new-constraints new-event-names new-new-entries)
    (relevant-constraints formula alist proved-fnl-insts-alist wrld)
    (cond
     ((eq new-constraints *unknown-constraints*)
      (er soft ctx
          "Functional instantiation is disallowed in this context, because ~
           the function ~x0 has unknown constraints provided by the dependent ~
           clause-processor ~x1.  See :DOC define-trusted-clause-processor."
          new-event-names
          new-new-entries))
     (t
      (let ((allow-freevars-p
             #-:non-standard-analysis
             t
             #+:non-standard-analysis
             (classical-fn-list-p (all-fnnames formula) wrld)))
        (mv-let
         (erp0 formula0)
         (sublis-fn-rec alist formula nil allow-freevars-p)
         (mv-let
          (erp new-constraints0)
          (cond (erp0 (mv erp0 formula0))
                (t (sublis-fn-rec-lst alist new-constraints nil
                                      allow-freevars-p)))
          (cond
           (erp

; The following message is surprising in a situation where a variable is
; captured by a binding to itself, sinced for example (let ((x x)) ...)
; translates and then untranslates back to (let () ...).  Presumably we could
; detect such cases and not consider them to be captures.  But we keep it
; simple and simply expect and hope that such a misleading message is never
; actually seen by a user.

            (er soft ctx
                (if allow-freevars-p
                    "Your functional substitution contains one or more free ~
                     occurrences of the variable~#0~[~/s~] ~&0 in its range.  ~
                     Alas, ~#1~[this variable occurrence is~/these variables ~
                     occurrences are~] bound in a LET or MV-LET expression of ~
                     ~#2~[the formula you wish to functionally instantiate, ~
                     ~p3.~|~/the constraints that must be relieved.  ~]You ~
                     must therefore change your functional substitution so ~
                     that it avoids such ``capture.''  It will suffice for ~
                     your functional substitution to stay clear of all the ~
                     variables bound by a LET or MV-LET expression that are ~
                     used in the target formula or in the corresponding ~
                     constraints.  Thus it will suffice for your substitution ~
                     not to contain free occurrences of ~v4 in its range, by ~
                     using fresh variables instead.  Once you have fixed this ~
                     problem, you can :use an :instance of your ~
                     :functional-instance to bind the fresh variables to ~&4."

; With allow-freevars-p = nil, it is impossible for free variables to be
; captured, since no free variables are allowed.

                  "Your functional substitution contains one or more free ~
                   occurrences of the variable~#0~[~/s~] ~&0 in its range.  ~
                   Alas, the formula you wish to functionally instantiate is ~
                   not a classical formula, ~p3.  Free variables in lambda ~
                   expressions are only allowed when the formula to be ~
                   instantiated is classical, since these variables may admit ~
                   non-standard values, for which the theorem may be false.")
                (merge-sort-symbol-< erp)
                erp
                (if erp0 0 1)
                (untranslate formula t wrld)
                (bound-vars-lst (cons formula new-constraints)
                                nil)))
           (t (value
               (list formula0
                     (append constraints new-constraints0)
                     (union-equal new-event-names event-names)
                     (union-equal new-new-entries new-entries)))))))))))))

(defun translate-lmi (lmi normalizep ctx wrld state)

; Lmi is an object that specifies some instance of a theorem.  It may
; specify a substitution instance or a functional instantiation, or
; even some composition of such instances.  This function checks that
; lmi is meaningful and either causes an error or returns (as the
; value result of an error/value/state producing function) a list

; (thm constraints event-names new-entries)

; where:

; thm is a term, intuitively, the instance specified;

; constraints is a list of terms, intuitively a list of conjectures which must
; be proved in order to prove thm;

; event-names is a list of names to credit for avoiding certain proof
; obligations in the generation of the constraints; and

; new-entries is the list of new entries for the world global
; 'proved-functional-instances-alist, which we will place in a tag-tree and
; eventually using the name of the event currently being proved (if any).

; A lemma instance is either 
; (a) the name of a formula,
; (b) the rune of a corollary,
; (c) (:theorem formula)
; (d) (:instance lmi . substn), or
; (e) (:functional-instance lmi . substn)

; where lmi is another lemma instance and substn is a substitution of the
; appropriate type.

; Normalizep tells us whether to use the normalized body or the
; 'unnormalized-body when the lmi refers to a funcction definition.  We use the
; normalized body for :use hints, where added simplification can presumably
; only be helpful (and for backwards compatibility as we introduce normalizep
; in Version_2.7).  But we use the 'unnormalized-body for :by hints as a
; courtesy to the user, who probably is thinking of that rather than the
; normalized body when instantiating a definition.

  (let ((str "The object ~x0 is an ill-formed lemma instance because ~@1.  ~
              See :DOC lemma-instance."))
    (cond
     ((atom lmi)
      (cond ((symbolp lmi)
             (let ((term (formula lmi normalizep wrld)))
               (cond (term (value (list term nil nil nil)))
                     (t (er soft ctx str
                            lmi
                            (msg "there is no formula associated with the ~
                                  name ~x0"
                                 lmi))))))
            (t (er soft ctx str lmi
                   "it is an atom that is not a symbol"))))
     ((runep lmi wrld)
      (let ((term (and (not (eq (car lmi) :INDUCTION))
                       (corollary lmi wrld))))
        (cond (term (value (list term nil nil nil)))
              (t (er soft ctx str lmi
                     "there is no known formula associated with this rune")))))
     ((eq (car lmi) :theorem)
      (cond ((and (true-listp lmi)
                  (= (length lmi) 2))
             (er-let*
              ((term (translate (cadr lmi) t t t ctx wrld state)))
; known-stobjs = t (stobjs-out = t)
              (value (list term (list term) nil nil))))
            (t (er soft ctx str lmi
                   "this :THEOREM lemma instance is not a true list of length ~
                    2"))))
     ((or (eq (car lmi) :instance)
          (eq (car lmi) :functional-instance))
      (cond
       ((and (true-listp lmi)
             (>= (length lmi) 2))
        (er-let*
         ((lst (translate-lmi (cadr lmi) normalizep ctx wrld state)))
         (let ((formula (car lst))
               (constraints (cadr lst))
               (event-names (caddr lst))
               (new-entries (cadddr lst))
               (substn (cddr lmi)))
           (cond
            ((eq (car lmi) :instance)
             (translate-lmi/instance formula constraints event-names
                                     new-entries substn ctx wrld state))
            (t (translate-lmi/functional-instance
                formula constraints event-names new-entries substn
                (global-val 'proved-functional-instances-alist wrld)
                ctx wrld state))))))
       (t (er soft ctx str lmi
              (msg "this ~x0 lemma instance is not a true list of length at ~
                    least 2"
                   (car lmi))))))
     (t (er soft ctx str lmi
            "is not a symbol, a rune in the current logical world, or a list ~
             whose first element is :THEOREM, :INSTANCE, or ~
             :FUNCTIONAL-INSTANCE")))))

(deflabel lemma-instance
  :doc
  ":Doc-Section Miscellaneous

  an object denoting an instance of a theorem~/

  Lemma instances are the objects one provides via ~c[:use] and ~c[:by] ~il[hints]
  (~pl[hints]) to bring to the theorem prover's attention some previously
  proved or easily provable fact.  A typical use of the ~c[:use] hint is given
  below.  The value specified is a list of five lemma instances.
  ~bv[]
  :use (reverse-reverse
        (:type-prescription app)
        (:instance assoc-of-app
                   (x a) (y b) (z c))
        (:functional-instance p-f
                              (p consp) (f flatten))
        (:instance (:theorem (equal x x))
                   (x (flatten a))))
  ~ev[]
  Observe that an event name can be a lemma instance.  The ~c[:use] hint allows
  a single lemma instance to be provided in lieu of a list, as in:
  ~bv[]
  :use reverse-reverse
  ~ev[]
  or
  ~bv[]
  :use (:instance assoc-of-app (x a) (y b) (z c))
  ~ev[]~/

  A lemma instance denotes a formula which is either known to be a theorem or
  which must be proved to be a theorem before it can be used.  To use a lemma
  instance in a particular subgoal, the theorem prover adds the formula as a
  hypothesis to the subgoal before the normal theorem proving heuristics are
  applied.

  A lemma instance, or ~c[lmi], is of one of the following five forms:

  (1) ~c[name], where ~c[name] names a previously proved theorem, axiom, or
  definition and denotes the formula (theorem) of that name.

  (2) ~c[rune], where ~c[rune] is a ~il[rune] (~pl[rune]) denoting the
  ~c[:]~ilc[corollary] justifying the rule named by the ~il[rune].

  (3) ~c[(:theorem term)], where ~c[term] is any term alleged to be a theorem.
  Such a lemma instance denotes the formula ~c[term].  But before using such a
  lemma instance the system will undertake to prove ~c[term].

  (4) ~c[(:instance lmi (v1 t1) ... (vn tn))], where ~c[lmi] is recursively a
  lemma instance, the ~c[vi]'s are distinct variables and the ~c[ti]'s are
  terms.  Such a lemma instance denotes the formula obtained by instantiating
  the formula denoted by ~c[lmi], replacing each ~c[vi] by ~c[ti].

  (5) ~c[(:functional-instance lmi (f1 g1) ... (fn gn))], where ~c[lmi] is
  recursively a lemma instance and each ~c[fi] is an ``instantiable'' function
  symbol of arity ~c[ni] and ~c[gi] is a function symbol, a macro alias for a
  function symbol ~c[gi'] (~pl[macro-aliases-table]) in which case we treat
  ~c[gi] as ~c[gi'], or a pseudo-lambda expression of arity ~c[ni].  An
  instantiable function symbol is any defined or constrained function symbol
  except the primitives ~ilc[not], ~ilc[member], ~ilc[implies], and ~ilc[o<],
  and a few others, as listed by the constant
  ~c[*non-instantiable-primitives*].  These are built-in in such a way that we
  cannot recover the ~il[constraint]s on them.  (Special case: a function
  introduced in the ~c[:partial-theory] of a dependent clause-processor is not
  instantiable; ~pl[define-trusted-clause-processor].)  A pseudo-lambda
  expression is an expression of the form ~c[(lambda (v1 ... vn) body)] where
  the ~c[vi] are distinct variable symbols and ~c[body] is any term.  No
  ~i[a priori] relation is imposed between the ~c[vi] and the variables of
  ~c[body], i.e., ~c[body] may ignore some ~c[vi]'s and may contain ``free''
  variables.  However, we do not permit ~c[v] to occur freely in ~c[body] if
  the functional substitution is to be applied to any formula (~c[lmi] or the
  ~il[constraint]s to be satisfied) in a way that inserts ~c[v] into the scope
  of a binding of ~c[v] by ~ilc[let] or ~ilc[mv-let] (or, ~ilc[lambda]).  If
  you happen to violate this restriction, an informative error message will be
  printed.  That message will list for you the potentially illegal choices for
  ~c[v] in the context in which the functional substitution is offered.  A
  ~c[:functional-instance] lemma instance denotes the formula obtained by
  functionally instantiating the formula denoted by ~c[lmi], replacing ~c[fi]
  by ~c[gi].  However, before such a lemma instance can be used, the system
  will generate proof obligations arising from the replacement of the ~c[fi]'s
  by the ~c[gi]'s in constraints that ``support'' the lemma to be functionally
  instantiated; ~pl[constraint].  One might expect that if the same
  instantiated constraint were generated on behalf of several events, then each
  of those instances would have to be proved.  However, for the sake of
  efficiency, ACL2 stores the fact that such an instantiated constraint has
  been proved and avoids it in future events.

  Obscure case for ~il[definition]s.  If the lemma instance refers to a
  ~c[:definition] ~il[rune], then it refers to the ~ilc[corollary] formula of
  that rune, which can be a simplified (``normalized'') form of the original
  formula.  However, if the hint is a ~c[:by] hint and the lemma instance is
  based on a name (i.e., a symbol), rather than a rune, then the formula is the
  original formula of the event, as shown by ~c[:]~ilc[pe], rather than the
  normalized version, as shown by ~c[:]~ilc[pf].  This is as one would expect:
  If you supply the name of an event, you expect it to refer to the original
  event.  For ~c[:use] hints we use the simplified (normalized) form instead,
  which is reasonable since one would expect simplification during the proof
  that re-traces the normalization done at the time the rule was created.

  ~l[functional-instantiation-example] for an example of the use
  of ~c[:functional-instance] (so-called ``functional instantiation).''~/")

(defun translate-use-hint1 (arg ctx wrld state)

; Arg is a list of lemma instantiations and we return a list of the form (hyps
; constraints event-names new-entries); see translate-by-hint or translate-lmi
; for details.  In particular, hyps is a list of the instantiated theorems to
; be added as hypotheses and constraints is a list of the constraints that must
; be proved.

  (cond ((atom arg)
         (cond ((null arg) (value '(nil nil nil nil)))
               (t (er soft ctx
                      "The value of the :use hint must be a true list ~
                       but your list ends in ~x0.  See the :use ~
                       discussion in :MORE-DOC hints."
                      arg))))
        (t (er-let*
            ((lst1 (translate-lmi (car arg) t ctx wrld state))
             (lst2 (translate-use-hint1 (cdr arg) ctx wrld state)))
            (value (list (cons (car lst1) (car lst2))
                         (append (cadr lst1) (cadr lst2))
                         (union-eq (caddr lst1) (caddr lst2))
                         (union-equal (cadddr lst1) (cadddr lst2))))))))

(defun translate-use-hint (arg ctx wrld state)

; Nominally, the :use hint is followed by a list of lmi objects.
; However, if the :use hint is followed by a single lmi, we automatically
; make a singleton list out of the lmi, e.g.,

;   :use assoc-of-append
; is the same as
;   :use (assoc-of-append)
; 
;   :use (:instance assoc-of-append (x a))
; is the same as
;   :use ((:instance assoc-of-append (x a)))

; This function either causes an error or returns (as the value component of
; an error/value/state triple) a list of the form 
;    (lmi-lst (hyp1 ... hypn) cl k event-names new-entries),
; lmi-lst is the true-list of lmis processed, (hyp1 ... hypn) are the
; hypothesis theorems obtained, cl is a single clause that is the
; conjunction of the constraints, k is the number of conjuncts,
; event-names is a list of names to credit for avoiding certain proof
; obligations in the generation of the constraints, and new-entries is
; the list of new entries for the world global
; 'proved-functional-instances-alist.

; Note:  The subroutines of this function deal in answer pairs of the form
; ((hyp1 ... hypn) . constraints), where constraints is a list of all the
; constraint terms.  The conversion from that internal convention to the
; external one used in translated :use hints is made here.

; A Brief History of a Rapidly Changing Notation (Feb 28, 1990)

; Once upon a time, lemma instance had the form (assoc-of-append :x
; a).  We adopted the policy that if a substitution was going to be
; applied to a lemma, term, and x was in the domain of the
; substitution, then one wrote :x and wrote the substitution "flat",
; without parentheses around the variable/term pairs.  In general, :x
; meant "the variable symbol in term whose symbol name was "x"."  We
; enforced the restrictin that there was at most one variable symbol
; in a stored formula with a given symbol name.

; At that time we denoted lemma instances with such notation as
; (assoc-of-append :x a :y b :z c).  Functional instances were not yet
; implemented.  But in order to disambiguate the use of a single
; lemma instance from the use of several atomic instances, e.g.,
;    :use (assoc-of-append :x a :y b :z c)
; versus
;    :use (assoc-of-append rev-rev)
; we relied on the idea that the domain elements of the substitution
; were keywords.  

; The implementation of functional instantiation changed all that.
; First, we learned that the translation of a keyword domain element,
; e.g., :fn, into a function symbol could not be done in a way
; analogous to what we were doing with variables.  Which function is
; meant by :fn?  You might say, "the one with that symbol name in the
; target theorem being instantiated."  But there may be no such symbol
; in the target theorem; the user may want to instantiate :fn in some
; constraint being proved for that theorem's instantiation.  But then
; you might say "then search the constraint too for a suitable meaning
; for :fn."  Ah ha!  You can't compute the constraint until you know
; which functions are being instantiated.  So the general idea of
; using the target to translate keyword references just fails and it
; was necessary to come up with an unambiguous way of writing a
; substitution.  We temporarily adopted the idea that the "keywords"
; in flat substitutions might not be keywords at all.  E.g., you could
; write ACL2-NQTHM::X as a domain element.  That might have put into
; jeapardy their use to disambiguate :use hint.

; But simultaneously we adopted the idea that lemma instances are
; written as (:instance assoc-of-append ...) or (:functional-instance
; assoc-of-append ...).  This was done so lemma instances could be
; nested, to allow functional instances to then be instantiated.  But
; with the keyword at the beginning of a lemma instance it suddenly
; became possible to disambiguate :use hints:
;   :use (assoc-of-append rev-rev)
; can mean nothing but use two lemma instances because the argument to
; the use is not a lemma instance.

; So we were left with no compelling need to have keywords and flat
; substitutions and a lot of confusion if we did have keywords.  So we
; abandoned them in favor of the let-bindings like notation.

  (cond
   ((null arg)
    (er soft ctx "Implementation error:  Empty :USE hints should not be ~
                  handled by translate-use-hint (for example, they are ~
                  handled by translate-hint-settings."))
   (t (let ((lmi-lst (cond ((atom arg) (list arg))
                           ((or (eq (car arg) :instance)
                                (eq (car arg) :functional-instance)
                                (eq (car arg) :theorem)
                                (runep arg wrld))
                            (list arg))
                           (t arg))))
        (er-let*
         ((lst (translate-use-hint1 lmi-lst ctx wrld state)))

; Lst is of the form ((hyp1 ... hypn) constraints event-names new-entries),
; where constraints is a list of constraint terms, implicitly conjoined.  We
; wish to return something of the form
; (lmi-lst (hyp1 ... hypn) constraint-cl k event-names new-entries)
; where constraint-cl is a clause that is equivalent to the constraints.

         (value (list lmi-lst
                      (car lst)
                      (add-literal (conjoin (cadr lst)) nil nil)
                      (length (cadr lst))
                      (caddr lst)
                      (cadddr lst))))))))

(defun convert-name-tree-to-new-name1 (name-tree char-lst sym)
  (cond ((atom name-tree)
         (cond ((symbolp name-tree)
                (mv (append (coerce (symbol-name name-tree) 'list)
                            (cond ((null char-lst) nil)
                                  (t (cons #\Space char-lst))))
                    name-tree))
               ((stringp name-tree)
                (mv (append (coerce name-tree 'list)
                            (cond ((null char-lst) nil)
                                  (t (cons #\Space char-lst))))
                    sym))
               (t (mv
                   (er hard 'convert-name-tree-to-new-name1
                       "Name-tree was supposed to be a cons tree of ~
                        symbols and strings, but this one contained ~
                        ~x0.  One explanation for this is that we ~
                        liberalized what a goal-spec could be and ~
                        forgot this function."
                       name-tree)
                   nil))))
        (t (mv-let (char-lst sym)
                   (convert-name-tree-to-new-name1 (cdr name-tree)
                                                   char-lst sym)
                   (convert-name-tree-to-new-name1 (car name-tree)
                                                   char-lst sym)))))

(defun convert-name-tree-to-new-name (name-tree wrld)

; A name-tree is just a cons tree composed entirely of strings
; and symbols.  We construct the symbol whose symbol-name is the
; string that contains the fringe of the tree, separated by
; spaces, and then we generate a new name in wrld. For example,
; if name-tree is '(("Guard Lemma for" . APP) . "Subgoal 1.3''") then we
; will return '|Guard Lemma for APP Subgoal 1.3''|, provided that is new.
; To make it new we'll start tacking on successive subscripts,
; as with gen-new-name.  The symbol we generate is interned in
; the same package as the first symbol occurring in name-tree,
; or in "ACL2" if no symbol occurs in name-tree.

  (mv-let (char-lst sym)
          (convert-name-tree-to-new-name1 name-tree
                                          nil
                                          'convert-name-tree-to-new-name)
          (gen-new-name (intern-in-package-of-symbol
                         (coerce char-lst 'string)
                         sym)
                        wrld)))

(defun translate-by-hint (name-tree arg ctx wrld state)

; A :BY hint must either be a single lemma instance, nil, or a new
; name which we understand the user intends will eventually become a
; lemma instance.  Nil means that we are to make up an appropriate
; new name from the goal-spec.  Note:  We can't really guarantee that
; the name we make up (or one we check for the user) is new because
; the same name may be made up twice before either is actually
; created.  But this is just a courtesy to the user anyway.  In the
; end, he'll have to get his names defthm'd himself.

; If arg is an lemma instance, then we return a list of the form (lmi-lst
; thm-cl-set constraint-cl k event-names new-entries), where lmi-lst is a
; singleton list containing the lmi in question, thm-cl-set is the set of
; clauses obtained from the instantiated theorem and which is to subsume the
; indicated goal, constraint-cl is a single clause which represents the
; conjunction of the constraints we are to establish, k is the number of
; conjuncts, event-names is a list of names to credit for avoiding certain
; proof obligations in the generation of the constraints, and new-entries will
; be used to update the world global 'proved-functional-instances-alist.

; If arg is a new name, then we return just arg itself (or the name
; generated).

  (cond ((or (and arg
                  (symbolp arg)
                  (formula arg t wrld))
             (consp arg))
         (er-let*
          ((lst (translate-lmi arg nil ctx wrld state)))

; Lst is (thm constraints event-names new-entries), where:  thm is a term;
; constraints is a list of terms whose conjunction we must prove; event-names
; is a list of names of events on whose behalf we already proved certain proof
; obligations arising from functional instantiation; and new-entries may
; eventually be added to the world global 'proved-functional-instances-alist so
; that the present event can contribute to avoiding proof obligations for
; future proofs.

          (value
           (list (list arg)
                 (car lst)
                 (add-literal (conjoin (cadr lst)) nil nil)
                 (length (cadr lst))
                 (caddr lst)
                 (cadddr lst)))))
        ((null arg)

; The name nil is taken to mean make up a suitable name for this subgoal.

         (value (convert-name-tree-to-new-name name-tree wrld)))
        ((and (symbolp arg)
              (not (keywordp arg))
              (not (equal *main-lisp-package-name* (symbol-package-name arg)))
              (new-namep arg wrld))

; The above checks are equivalent to chk-all-but-new-name and chk-just-
; new-name, but don't cause the error upon failure.  The error message
; that would otherwise be generated is confusing because the user isn't
; really trying to define arg to be something yet.

         (value arg))
        (t
         (er soft ctx
             "The :BY hint must be given a lemma-instance, nil, or a ~
              new name.  ~x0 is none of these.  See :DOC hints."
             arg))))

(defun translate-cases-hint (arg ctx wrld state)

; This function either causes an error or returns (as the value component of
; an error/value/state triple) a list of terms.

  (cond
   ((null arg)
    (er soft ctx "We do not permit empty :CASES hints."))
   ((not (true-listp arg))
    (er soft ctx
        "The value associated with a :CASES hint must be a true-list of terms, ~
         but ~x0 is not."
        arg))
   (t (translate-term-lst arg t t t ctx wrld state))))

(defun translate-case-split-limitations-hint (arg ctx wrld state)

; This function returns an error triple.  In the non-error case, the value
; component of the error triple is a two-element list that controls the
; case-splitting, in analogy to set-case-split-limitations.

  (declare (ignore wrld))
  (cond ((null arg) (value '(nil nil)))
        ((and (true-listp arg)
              (equal (len arg) 2)
              (or (natp (car arg))
                  (null (car arg)))
              (or (natp (cadr arg))
                  (null (cadr arg))))
         (value arg))
        (t (er soft ctx
               "The value associated with a :CASE-SPLIT-LIMITATIONS hint must ~
                be either nil (denoting a list of two nils), or a true list ~
                of length two, each element which is either nil or a natural ~
                number; but ~x0 is not."
               arg))))

(defun translate-no-op-hint (arg ctx wrld state)
  (declare (ignore arg ctx wrld))
  (value t))

(defun character-alistp (x)

  ":Doc-Section ACL2::Programming

  recognizer for association lists with characters as keys~/

  ~c[(Character-alistp x)] is true if and only if ~c[x] is a list of pairs
  of the form ~c[(cons key val)] where ~c[key] is a ~ilc[characterp].~/~/"

  (declare (xargs :guard t))
  (cond ((atom x) (eq x nil))
        (t (and (consp (car x))
                (characterp (car (car x)))
                (character-alistp (cdr x))))))

(defun tilde-@p (arg)
  (declare (xargs :guard t))
  (or (stringp arg)
      (and (consp arg)
           (stringp (car arg))
           (character-alistp (cdr arg)))))

(defun translate-error-hint (arg ctx wrld state)
  (declare (ignore wrld))
  (cond ((tilde-@p arg)
         (er soft ctx "~@0" arg))
        (t (er soft ctx
               "The :ERROR hint keyword was included among your hints, with ~
                value ~x0."
               arg))))

(defun translate-induct-hint (arg ctx wrld state)
  (cond ((eq arg nil) (value nil))
        (t (translate arg t t t ctx wrld state))))

; known-stobjs = t (stobjs-out = t)

; We now turn to :in-theory hints.  We develop here only enough to
; translate and check an :in-theory hint.  We develop the code for
; the in-theory event and the related deftheory event later.
; Some such code (e.g., eval-theory-expr) was developed earlier in
; support of install-event.

(defconst *built-in-executable-counterparts*

; Keep this in sync with cons-term1.

  '(acl2-numberp
    binary-* binary-+ unary-- unary-/ < car cdr
    char-code characterp code-char complex
    complex-rationalp
    #+:non-standard-analysis complexp
    coerce cons consp denominator equal
    #+:non-standard-analysis floor1
    if imagpart integerp
    intern-in-package-of-symbol numerator pkg-witness pkg-imports rationalp
    #+:non-standard-analysis realp
    realpart stringp symbol-name symbol-package-name symbolp
    #+:non-standard-analysis standardp
    #+:non-standard-analysis standard-part
    ;; #+:non-standard-analysis i-large-integer
    not))

(defconst *s-prop-theory*

; This constant is no longer used in the ACL2 system code -- generally (theory
; 'minimal-theory) is more appropriate -- but we leave it here for use by
; existing books.

; This constant is not well-named, since some of its functions are not
; propositional.  But we keep the name since this constant has been used in
; theory hints since nearly as far back as the inception of ACL2.

  (cons 'iff ; expanded in tautologyp
        *expandable-boot-strap-non-rec-fns*))

(defconst *definition-minimal-theory*
  (list* 'mv-nth 'iff *expandable-boot-strap-non-rec-fns*))

(defun translate-in-theory-hint
  (expr chk-boot-strap-fns-flg ctx wrld state)

; We translate and evaluate expr and make sure that it produces a
; common theory.  We either cause an error or return the corresponding
; runic theory.

; Keep this definition in sync with minimal-theory.

  (er-let*
   ((runic-value (eval-theory-expr expr ctx wrld state)))
   (let* ((warning-disabled-p (warning-disabled-p "Theory"))
          (state
           (cond
            (warning-disabled-p
             state)
            ((and chk-boot-strap-fns-flg
                  (f-get-global 'verbose-theory-warning state)
                  (not (subsetp-equal
                        (getprop 'definition-minimal-theory 'theory
                                 nil ; so, returns nil early in boot-strap
                                 'current-acl2-world wrld)
                        runic-value)))
             (warning$ ctx ("Theory")
                       "The value of the theory expression ~x0 does not ~
                        include the :DEFINITION rule~#1~[~/s~] for ~v1.  But ~
                        ~#1~[this function is~/these functions are~] among a ~
                        set of primitive functions whose definitions are ~
                        built into the ACL2 system in various places.  This ~
                        set consists of the functions ~&2.  While excluding ~
                        them from the current theory will prevent certain ~
                        expansions it will not prevent others.  Good ~
                        luck!~|~%To inhibit this warning, evaluate:~|~x3."
                       expr
                       (strip-base-symbols
                        (set-difference-equal
                         (getprop 'definition-minimal-theory 'theory nil
                                  'current-acl2-world wrld)
                         runic-value))
                       *definition-minimal-theory*
                       '(assign verbose-theory-warning nil)))
            (t state))))
     (let ((state
            (cond
             (warning-disabled-p
              state)
             ((and chk-boot-strap-fns-flg
                   (f-get-global 'verbose-theory-warning state)
                   (not (subsetp-equal
                         (getprop 'executable-counterpart-minimal-theory
                                  'theory
                                  nil ; so, returns nil early in boot-strap
                                  'current-acl2-world wrld)
                         runic-value)))
              (warning$ ctx ("Theory")
                        "The value of the theory expression ~x0 does not ~
                         include the :EXECUTABLE-COUNTERPART rule~#1~[~/s~] ~
                         for ~v1.  But ~#1~[this function is~/these functions ~
                         are~] among a set of primitive functions whose ~
                         executable counterparts are built into the ACL2 ~
                         system.  This set consists of the functions ~&2.  ~
                         While excluding them from the current theory may ~
                         prevent certain expansions it will not prevent ~
                         others.  Good luck!~|~%To inhibit this warning, ~
                         evaluate:~|~x3."
                        expr
                        (strip-base-symbols
                         (set-difference-equal
                          (getprop 'executable-counterpart-minimal-theory
                                   'theory nil 'current-acl2-world wrld)
                          runic-value))
                        *built-in-executable-counterparts*
                        '(assign verbose-theory-warning nil)))
             (t state))))
       (value runic-value)))))

(defun all-function-symbolps (fns wrld)
  (cond ((atom fns) (equal fns nil))
        (t (and (symbolp (car fns))
                (function-symbolp (car fns) wrld)
                (all-function-symbolps (cdr fns) wrld)))))

(defun non-function-symbols (lst wrld)
  (cond ((null lst) nil)
        ((function-symbolp (car lst) wrld)
         (non-function-symbols (cdr lst) wrld))
        (t (cons (car lst)
                 (non-function-symbols (cdr lst) wrld)))))

(defun collect-non-logic-mode (alist wrld)
  (cond ((null alist) nil)
        ((and (function-symbolp (caar alist) wrld)
              (logicalp (caar alist) wrld))
         (collect-non-logic-mode (cdr alist) wrld))
        (t (cons (caar alist)
                 (collect-non-logic-mode (cdr alist) wrld)))))

(defun translate-bdd-hint1 (top-arg rest ctx wrld state)
  (cond
   ((null rest)
    (value nil))
   (t (let ((kwd (car rest)))
        (er-let*
         ((cdar-alist
           (case kwd
             (:vars
              (cond
               ((eq (cadr rest) t)
                (value t))
               ((not (true-listp (cadr rest)))
                (er soft ctx
                    "The value associated with :VARS in the :BDD hint must ~
                     either be T or a true list, but ~x0 is neither."
                    (cadr rest)))
               ((collect-non-legal-variableps (cadr rest))
                (er soft ctx
                    "The value associated with :VARS in the :BDD hint must ~
                     either be T or a true list of variables, but in the :BDD ~
                     hint ~x0, :VARS is associated with the following list of ~
                     non-variables:  ~x1."
                    top-arg
                    (collect-non-legal-variableps (cadr rest))))
               (t (value (cadr rest)))))
             (:prove
              (cond ((member-eq (cadr rest) '(t nil))
                     (value (cadr rest)))
                    (t (er soft ctx
                           "The value associated with ~x0 in the :BDD hint ~x1 ~
                            is ~x2, but it needs to be t or nil."
                           kwd top-arg (cadr rest)))))
             (:literal
              (cond ((member-eq (cadr rest) '(:conc :all))
                     (value (cadr rest)))
                    ((and (integerp (cadr rest))
                          (< 0 (cadr rest)))

; The user provides a 1-based index, but we want a 0-based index.

                     (value (1- (cadr rest))))
                    (t (er soft ctx
                           "The value associated with :LITERAL in a :BDD hint ~
                            must be either :CONC, :ALL, or a positive integer ~
                            (indicating the index, starting with 1, of a ~
                            hypothesis). The value ~x0 from the :BDD hint ~x1 ~
                            is therefore illegal."
                           (cadr rest) top-arg))))
             (:bdd-constructors
              (cond ((and (consp (cadr rest))
                          (eq (car (cadr rest)) 'quote)
                          (consp (cdr (cadr rest)))
                          (null (cddr (cadr rest))))
                     (er soft ctx
                         "The value associated with :BDD-CONSTRUCTORS must be ~
                          a list of function symbols.  It should not be ~
                          quoted, but the value supplied is of the form (QUOTE ~
                          x)."))
                    ((not (symbol-listp (cadr rest)))
                     (er soft ctx
                           "The value associated with :BDD-CONSTRUCTORS must ~
                            be a list of symbols, but ~x0 ~ is not."
                           (cadr rest)))
                    ((all-function-symbolps (cadr rest) wrld)
                     (value (cadr rest)))
                    (t (er soft ctx
                           "The value associated with :BDD-CONSTRUCTORS must ~
                            be a list of :logic mode function symbols, but ~
                            ~&0 ~#0~[is~/are~] not."
                           (collect-non-logic-mode

; This is an odd construct, but its saves us from defining a new function since
; we use collect-non-logic-mode elsewhere anyhow.
                       
                            (pairlis$ (cadr rest) nil)
                            wrld)))))
             (otherwise
              (er soft ctx
                  "The keyword ~x0 is not a legal keyword for a :BDD hint.  ~
                   The hint ~x1 is therefore illegal.  See :DOC hints."
                  (car rest) top-arg)))))
         (er-let*
          ((cdr-alist
            (translate-bdd-hint1 top-arg (cddr rest) ctx wrld state)))
          (value (cons (cons kwd cdar-alist) cdr-alist))))))))

(defun translate-bdd-hint (arg ctx wrld state)

; Returns an alist associating each of the permissible keywords with a value.

  (cond
   ((not (keyword-value-listp arg))
    (er soft ctx
        "The value associated with a :BDD hint must be a list of the form ~
         (:kw1 val1 :kw2 val2 ...), where each :kwi is a keyword.  However, ~
         ~x0 does not have this form."
        arg))
   ((not (assoc-keyword :vars arg))
    (er soft ctx
        "The value associated with a :BDD hint must include an assignment for ~
         :vars, but ~x0 does not."
        arg))
   (t (translate-bdd-hint1 arg arg ctx wrld state))))

(defun translate-nonlinearp-hint (arg ctx wrld state)
  (declare (ignore wrld))
  (if (or (equal arg t)
          (equal arg nil))
      (value arg)
    (er soft ctx
        "The only legal values for a :nonlinearp hint are T and NIL, but ~
         ~x0 is neither of these."
        arg)))

(defun translate-backchain-limit-rw-hint (arg ctx wrld state)
  (declare (ignore wrld))
  (if (or (natp arg)
          (equal arg nil))
      (value arg)
    (er soft ctx
        "The only legal values for a :backchain-limit-rw hint are NIL and ~
         natural numbers, but ~x0 is neither of these."
        arg)))

(defun translate-no-thanks-hint (arg ctx wrld state)
  (declare (ignore ctx wrld))
  (value arg))

(defun pos-listp (l)
  (cond ((atom l)
         (equal l nil))
        (t (and (posp (car l))
                (pos-listp (cdr l))))))

(defun translate-reorder-hint (arg ctx wrld state)
  (declare (ignore wrld))
  (if (and (pos-listp arg)
           (no-duplicatesp arg))
      (value arg)
    (er soft ctx
        "The value for a :reorder hint must be a true list of positive ~
         integers without duplicates, but ~x0 is not."
        arg)))

(defrec clause-processor-hint
  (term stobjs-out . verified-p)
  nil)

(defun arity-mismatch-msg (sym expected-arity wrld)

; This little function avoids code replication in
; translate-clause-processor-hint.  Expected-arity is either a number,
; indicating the expected arity, or of the form (list n), where n is the
; minimum expected arity.  We return the arity of sym (or its macro alias) if
; it is not as expected, and we return t if sym has no arity and is not a
; macro.  Otherwise we return nil.  So if sym is a macro, then we return nil
; even though there might be a mismatch (presumably to be detected by other
; means).

  (let* ((fn (or (deref-macro-name sym (macro-aliases wrld))
                 sym))
         (arity (arity fn wrld)))
    (cond
     ((null arity)
      (if (getprop sym 'macro-body nil 'current-acl2-world wrld)
          nil
        (msg "~x0 is neither a function symbol nor a macro name"
             sym)))
     ((and (consp expected-arity)
           (< arity (car expected-arity)))
      (msg "~x0 has arity ~x1 (expected arity of at least ~x2 for this hint ~
            syntax)"
           fn arity (car expected-arity)))
     ((and (integerp expected-arity)
           (not (eql expected-arity arity)))
      (msg "~x0 has arity ~x1 (expected arity ~x2 for this hint syntax)"
           fn arity expected-arity))
     (t nil))))

(defun translate-clause-processor-hint (form ctx wrld state)

; We are given the hint :clause-processor form.  We return an error triple
; whose value in the non-error case is a cons pair consisting of the
; corresponding translated term (a legal call of a clause-processor) and its
; associated stobjs-out, suitable for evaluation for a :clause-processor hint.

; Each of the following cases shows legal hint syntax for a signature (or in
; the third case, a class of signatures).

; For signature ((cl-proc cl) => cl-list):
; :CLAUSE-PROCESSOR cl-proc
; :CLAUSE-PROCESSOR (:FUNCTION cl-proc)
; :CLAUSE-PROCESSOR (cl-proc CLAUSE)
;    or any form macroexpanding to (cl-proc &) with at most CLAUSE free

; For signature ((cl-proc cl hint) => cl-list):
; :CLAUSE-PROCESSOR (:FUNCTION cl-proc :HINT hint)
; :CLAUSE-PROCESSOR (cl-proc CLAUSE hint)
;    or any term macroexpanding to (cl-proc & &) with at most CLAUSE free

; For signature ((cl-proc cl hint stobj1 ... stobjk) =>
;                (mv erp cl-list stobj1 ... stobjk)):
; :CLAUSE-PROCESSOR (:FUNCTION cl-proc :HINT hint)
; :CLAUSE-PROCESSOR (cl-proc CLAUSE hint stobj1 ... stobjk):
;    or any term macroexpanding to (cl-proc & & stobj1 ... stobjk)
;    where CLAUSE is the only legal non-stobj free variable

  (let ((err-msg (msg "The form ~x0 is not a legal value for a ~
                       :clause-processor hint because ~@1.  See :DOC hints."
                      form)))
    (er-let*
     ((form (cond ((atom form)
                   (cond ((symbolp form)
                          (let ((msg (arity-mismatch-msg form 1 wrld)))
                            (cond (msg (er soft ctx "~@0" err-msg msg))
                                  (t (value (list form 'clause))))))
                         (t (er soft ctx "~@0" err-msg
                                "it is an atom that is not a symbol"))))
                  ((not (true-listp form))
                   (er soft ctx "~@0" err-msg
                       "it is a cons that is not a true-listp"))
                  (t (case-match form
                       ((':function cl-proc)
                        (cond
                         ((symbolp cl-proc)
                          (let ((msg (arity-mismatch-msg cl-proc 1 wrld)))
                            (cond (msg (er soft ctx "~@0" err-msg msg))
                                  (t (value (list cl-proc 'clause))))))
                         (t (er soft ctx "~@0" err-msg
                                "the :FUNCTION is not a symbol"
                                ))))
                       ((':function cl-proc ':hint hint)
                        (cond ((symbolp cl-proc)
                               (let ((msg
                                      (arity-mismatch-msg cl-proc '(2) wrld)))
                                 (cond
                                  (msg (er soft ctx "~@0" err-msg msg))
                                  (t (value
                                      (list* cl-proc
                                             'clause
                                             hint
                                             (cddr (stobjs-out cl-proc
                                                               wrld))))))))
                              (t (er soft ctx "~@0" err-msg
                                     "the :FUNCTION is an atom that is not a ~
                                      symbol"))))
                       (& (value form)))))))
     (mv-let
      (erp term bindings state)
      (translate1 form
                  :stobjs-out ; form must be executable
                  '((:stobjs-out . :stobjs-out))
                  t ctx wrld state)
      (cond
       (erp (er soft ctx "~@0" err-msg
                "it was not successfully translated (see error message ~
                 above)"))
       ((or (variablep term)
            (fquotep term)
            (flambda-applicationp term))
        (er soft ctx "~@0" err-msg
            "it is not (even after doing macroexpansion) a call of a function ~
             symbol"))
       (t
        (let ((verified-p
               (getprop (ffn-symb term) 'clause-processor nil
                        'current-acl2-world wrld)))
          (cond
           ((not (or verified-p
                     (assoc-eq (ffn-symb term)
                               (table-alist 'trusted-clause-processor-table
                                            wrld))))
            (er soft ctx "~@0" err-msg
                "it is not a call of a clause-processor function"))
           ((not (eq (fargn term 1) 'clause))
            (er soft ctx "~@0" err-msg
                "its first argument is not the variable, CLAUSE"))
           ((set-difference-eq (non-stobjps (all-vars term) t wrld)
                               '(clause))
            (er soft ctx "~@0" err-msg
                (msg "it contains the free variable~#0~[~/s~] ~&0, but the ~
                      only legal variable (not including stobjs) is ~x1"
                     (set-difference-eq (non-stobjps (all-vars term) t wrld)
                                        '(clause))
                     'clause)))
           (t (value (make clause-processor-hint
                           :term term
                           :stobjs-out (translate-deref :stobjs-out
                                                        bindings)
                           :verified-p verified-p)))))))))))

; We next develop code for :custom hints.  See the Essay on the Design of
; Custom Keyword Hints.

(defconst *protected-system-state-globals*
  (let ((val
         (set-difference-eq
          (union-eq (strip-cars *initial-ld-special-bindings*)
                    (strip-cars *initial-global-table*))
          '(acl2-raw-mode-p            ;;; keep raw mode status
            bddnotes                   ;;; for feedback after expansion failure

; We handle world and enabled structure installation ourselves, with set-w! and
; revert-world-on-error.  We do not want to rely just on state globals because
; the world protection/modification functions do pretty fancy things.

            current-acl2-world global-enabled-structure
            inhibit-output-lst         ;;; allow user to modify this in a book
            inhibited-summary-types    ;;; allow user to modify this in a book
            keep-tmp-files             ;;; allow user to modify this in a book
            make-event-debug           ;;; allow user to modify this in a book
            saved-output-token-lst     ;;; allow user to modify this in a book
            print-clause-ids           ;;; allow user to modify this in a book
            fmt-soft-right-margin      ;;; allow user to modify this in a book
            fmt-hard-right-margin      ;;; allow user to modify this in a book
            parallel-evaluation-enabled ;; allow user to modify this in a book
            saved-output-reversed      ;;; for feedback after expansion failure
            saved-output-p             ;;; for feedback after expansion failure
            ttags-allowed              ;;; propagate changes outside expansion
            ld-evisc-tuple             ;;; allow user to modify this in a book
                                       ;;;   (e.g. misc/hons-help.lisp)
            term-evisc-tuple           ;;; see just above
            abbrev-evisc-tuple         ;;; see just above
            slow-array-action          ;;; see just above
            iprint-ar                  ;;; see just above
            iprint-soft-bound          ;;; see just above
            iprint-hard-bound          ;;; see just above
            writes-okp                 ;;; protected a different way (see
                                       ;;;   protect-system-state-globals)
            show-custom-keyword-hint-expansion
            trace-specs                ;;; keep in sync with functions that are
                                       ;;;   actually traced, e.g. trace! macro
            timer-alist                ;;; preserve accumulated summary info
            main-timer                 ;;; preserve accumulated summary info
            verbose-theory-warning     ;;; for warning on disabled mv-nth etc.
            more-doc-state             ;;; for proof-checker :more command
            pc-ss-alist                ;;; for saves under :instructions hints
            last-step-limit            ;;; propagate step-limit past expansion

; Note that tainted-okp is deliberately omitted from this list of exceptions,
; since its global value is the one that should be used during event
; processing.

            ))))
    val))

(defun state-global-bindings (names)
  (cond ((endp names)
         nil)
        (t (cons `(,(car names) (f-get-global ',(car names) state))
                 (state-global-bindings (cdr names))))))

(defmacro protect-system-state-globals (form)

; Form must return an error triple.  This macro not only reverts built-in state
; globals after evaluating form, but it also disables the opening of output
; channels.

  `(state-global-let*
    ,(cons `(writes-okp nil)
           (state-global-bindings *protected-system-state-globals*))
    ,form))

(defun formal-value-triple (erp val)
  (fcons-term* 'cons erp
               (fcons-term* 'cons val
                            (fcons-term* 'cons 'state *nil*))))

(defun translate-simple-or-error-triple (uform ctx wrld state)

; Uform is an untranslated term that is expected to translate either to an
; error triple or to an ordinary value.  In those cases we return an error
; triple whose value component is the translated term or, respectively, the
; term representing (mv nil tterm state) where tterm is the translated term.
; Otherwise, we return a soft error.

  (mv-let
   (erp term bindings state)
   (translate1 uform
               :stobjs-out ; form must be executable
               '((:stobjs-out . :stobjs-out))
               '(state) ctx wrld state)
   (cond
    (erp (silent-error state))
    (t
     (let ((stobjs-out (translate-deref :stobjs-out bindings)))
       (cond
        ((equal stobjs-out '(nil)) ; replace term by (value term)
         (value (formal-value-triple *nil* term)))
        ((equal stobjs-out *error-triple-sig*)
         (value term))
        (t (er soft ctx
               "The form ~x0 was expected to represent an ordinary value or ~
                an error triple (mv erp val state), but it returns a tuple of ~
                the form ~x1."
               uform
               (prettyify-stobj-flags stobjs-out)))))))))

(defun xtrans-eval (uterm alist trans-flg ev-flg ctx state aok)

; NOTE: Do not call this function with er-let* if ev-flg is nil.  Use mv-let
; and check erp manually.  See the discussion of 'wait below.

; Ignore trans-flg and ev-flg for the moment (or imagine their values are t).
; Then the spec of this function is as follows:

; Uterm is an untranslated term with an output signature of * or (mv * *
; state).  We translate it and eval it under alist (after extending alist with
; state bound to the current state) and return the resulting error triple or
; signal a translate or evaluation error.  We restore the world and certain
; state globals (*protected-system-state-globals*) after the evaluation.

; If trans-flg is nil, we do not translate.  We *assume* uterm is a
; single-threaded translated term with output signature (mv * * state)!

; Ev-flg is either t or nil.  If ev-flg is nil, we are to evaluate uterm only
; if all of its free vars are bound in the evaluation environment.  If ev-flg
; is nil and we find that a free variable of uterm is not bound, we return a
; special error triple, namely (mv t 'wait state) indicating that the caller
; should wait until it can get all the vars bound.  On the other hand, if
; ev-flg is t, it means eval the translated uterm, which will signal an error
; if there is an unbound var.

; Note that we do not evaluate in safe-mode.  Perhaps we should.  However, we
; experimented by timing certification of books/hints/ without and with
; safe-mode, and found times of 13.5 and 16.4 user seconds, respectively.
; That's not a huge penalty for safe-mode but it's not small, either, so out of
; concern for scalability we will avoid safe-mode for now.

  (er-let* ((term
             (if trans-flg
                 (translate-simple-or-error-triple uterm ctx (w state) state)
               (value uterm))))
    (cond
     ((or ev-flg
          (subsetp-eq (all-vars term)
                      (cons 'state (strip-cars alist))))

; We are to ev the term. But first we protect ourselves by arranging
; to revert the world and restore certain state globals.

      (let ((original-world (w state)))
        (er-let*
          ((val
            (acl2-unwind-protect
             "xtrans-eval"
             (protect-system-state-globals
              (mv-let (erp val latches)
                      (ev term
                          (cons (cons 'state
                                      (coerce-state-to-object state))
                                alist)
                          state
                          (list (cons 'state
                                      (coerce-state-to-object state)))
                          nil
                          aok)
                      (let ((state (coerce-object-to-state
                                    (cdr (car latches)))))
                        (cond
                         (erp

; An evaluation error occurred.  This could happen if we encountered
; an undefined (but constrained) function.  We print the error
; message.

                          (er soft ctx "~@0" val))
                         (t

; Val is the list version of (mv erp' val' state) -- and it really is
; state in that list (typically, the live state).  We assume that if
; erp' is non-nil then the evaluation also printed the error message.
; We return an error triple.

                          (mv (car val)
                              (cadr val)
                              state))))))
             (set-w! original-world state)
             (set-w! original-world state))))
          (value val))))
     (t 

; In this case, ev-flg is nil and there are variables in tterm that are
; not bound in the environment.  So we tell our caller to wait to ev the
; term.

      (mv t 'wait state)))))

(defun translate-custom-keyword-hint (arg uterm2 ctx wrld state)

; We run the checker term for the associated custom keyword and handle
; any error it generates.  But if no error is generated, the
; translation of arg (the user-supplied value for the custom keyword)
; is arg itself.

; Why do we not allow non-trivial translation of custom keyword hint
; values?  The main reason is that custom keyword hints do not see the
; translated values of common standard hints so why should they expect
; to see the translated values of custom hints?  While the author of
; custom keyword :key1 might like its argument to be translated, he
; probably doesn't want to know about the translated form of other
; custom keyword values.  Finally, when custom keyword hints generate
; new hints, they cannot be expected to translate their values.  And
; if they didn't translate their values then after one round of custom
; hint evaluation we could have a mix of translated and untranslated
; hint values: standard hints would not be translated -- no user wants
; to know the internal form of lmi's or theories! -- and some custom
; hint values would be translated and others wouldn't.  Furthermore,
; it is impossible to figure out which are which.  The only solution
; is to keep everything in untranslated form.  Example:
; Let :key1, :key2, and :key3 be custom keywords and suppose the user
; wrote the hint

;    :key1 val1  :key2 val2 :in-theory (enable foo)

; If we allowed non-trivial translation of custom hints, then at
; translate-time we'd convert that to

;    :key1 val1' :key2 val2' :in-theory (enable foo)

; Note the mix.  Then at prove-time we'd run :key1's generator on
; val1' and the whole hint.  It might return

;                :key2 val2' :key3 val3 :in-theory (enable foo)

; Note the additional mix.  We can't tell what's untranslated and what
; isn't, unless we made custom hint authors translate all custom
; hints, even those they don't "own."

  (er-progn (xtrans-eval uterm2
                         (list (cons 'val arg)
                               (cons 'world wrld)
                               (cons 'ctx ctx))
                         t ; trans-flg
                         t ; ev-flg
                         ctx
                         state
                         t)
            (value arg)))

(defun custom-keyword-hint (key wrld)

; If key is a custom keyword hint, we return (mv t ugterm ucterm); else
; (mv nil nil nil).  The terms are untranslated.

  (let ((temp (assoc-eq key (table-alist 'custom-keywords-table wrld))))
    (cond
     (temp
      (mv t (car (cdr temp)) (cadr (cdr temp))))
     (t (mv nil nil nil)))))

(defun remove-all-no-ops (key-val-lst)
  (cond ((endp key-val-lst) nil)
        ((eq (car key-val-lst) :no-op)
         (remove-all-no-ops (cddr key-val-lst)))
        (t (cons (car key-val-lst)
                 (cons (cadr key-val-lst)
                       (remove-all-no-ops (cddr key-val-lst)))))))

(defun remove-redundant-no-ops (key-val-lst)

; We return a keyword value list equivalent to key-val-lst but
; containing at most one :NO-OP setting on the front.  We don't even
; add that unless the hint would be empty otherwise.  The associated
; value is always T, no matter what the user wrote.

; (:INDUCT term :NO-OP T :IN-THEORY x :NO-OP NIL)
;   => (:INDUCT term :IN-THEORY x)

; (:NO-OP 1 :NO-OP 2) => (:NO-OP T)

  (cond
   ((assoc-keyword :no-op key-val-lst)
    (let ((temp (remove-all-no-ops key-val-lst)))
      (cond (temp temp)
            (t '(:no-op t)))))
   (t key-val-lst)))

(defun find-first-custom-keyword-hint (user-hints wrld)

; User-hints is a keyword value list of the form (:key1 val1 :key2
; val2 ...).  We look for the first :keyi in user-hints that is a
; custom keyword hint, and if we find it, we return (mv keyi vali
; uterm1 uterm2), where uterm1 is the untranslated generator for keyi
; and uterm2 is the untranslated checker.

  (cond
   ((endp user-hints) (mv nil nil nil nil))
   (t (mv-let (flg uterm1 uterm2)
              (custom-keyword-hint (car user-hints) wrld)
              (cond
               (flg
                (mv (car user-hints)
                    (cadr user-hints)
                    uterm1
                    uterm2))
               (t (find-first-custom-keyword-hint (cddr user-hints) wrld)))))))

(defconst *custom-keyword-max-iterations*
  100)

(defun custom-keyword-hint-interpreter1
  (keyword-alist max specified-id id clause wrld
                 stable-under-simplificationp hist pspv ctx state
                 keyword-alist0 eagerp)

; On the top-level call, keyword-alist must be known to be a keyword
; value list, e.g., (:key1 val1 ... keyn valn).  On subsequent calls,
; that is guaranteed.  This function returns an error triple
; (mv erp val state).  But a little more than usual is being passed
; back in the erp=t case.

; If erp is nil: val is either nil, meaning that the custom keyword
; hint did not apply or is a new keyword-alist to be used as the hint.
; That hint will be subjected to standard hint translation.

; If erp is t, then an error has occurred and the caller should abort
; -- UNLESS it passed in eagerp=t and the returned val is the symbol
; WAIT.  If eagerp is t we are trying to evaluate the custom keyword
; hint at pre-process time rather than proof time and don't have
; bindings for some variables.  In that case, an ``error'' is signaled
; with erp t but the returned val is the symbol WAIT, meaning it was
; impossible to eagerly evaluate this form.

  (cond
   ((equal specified-id id)
    
; This is the clause to which this hint applies.

    (mv-let
     (keyi vali uterm1 uterm2)
     (find-first-custom-keyword-hint keyword-alist wrld)
     (cond
      ((null keyi)

; There are no custom keyword hints in the list.  In this case,
; we're done and we return keyword-alist.

       (value keyword-alist))
      ((zp max)
       (er soft ctx
           "We expanded the custom keyword hints in ~x0 a total of ~
            ~x1 times and were still left with a hint containing ~
            custom keywords, namely ~x2."
           keyword-alist0
           *custom-keyword-max-iterations*
           keyword-alist))
      (t
       (let ((checker-bindings
              (list (cons 'val vali)
                    (cons 'world wrld)
                    (cons 'ctx ctx))))
         (er-progn
           (xtrans-eval uterm2
                        checker-bindings
                        t ; trans-flg = t
                        t ; ev-flg = t
                        ctx state t)

; We just evaluated the checker term and it did not cause an error.
; We ignore its value (though er-let* doesn't).
         
           (mv-let
            (erp val state)
            (xtrans-eval uterm1
                         (cond
                          (eagerp

; We are trying to evaluate the generator eagerly.  That means that
; our given values for some dynamic variables, CLAUSE,
; STABLE-UNDER-SIMPLIFICATIONP, HIST, and PSPV are bogus.  We thus
; don't pass them in and we tell xtrans-eval it doesn't really have to
; ev the term if it finds unbound vars.

                           (list* (cons 'keyword-alist keyword-alist)
                                  (cons 'id id)
;                                 (cons 'clause clause) ; bogus
;                                 (cons 'stable-under-simplificationp
;                                       stable-under-simplificationp)
;                                 (cons 'hist hist)
;                                 (cons 'pspv pspv)
                                  checker-bindings))
                          (t

; Otherwise, we want all the bindings:

                           (list* (cons 'keyword-alist keyword-alist)
                                  (cons 'id id)
                                  (cons 'clause clause) ; bogus
                                  (cons 'stable-under-simplificationp
                                        stable-under-simplificationp)
                                  (cons 'hist hist)
                                  (cons 'pspv pspv)
                                  checker-bindings)))
                         t ; trans-flg
                         (if eagerp nil t) ; ev-flg
                         ctx
                         state
                         t)
            (cond
             (erp

; If an error was caused, there are two possibilities.  One is that
; the form actually generated an error.  But the other is that we were
; trying eager evaluation with insufficient bindings.  That second
; case is characterized by eagerp = t and val = WAIT.  In both cases,
; we just pass it up.
            
              (mv erp val state))

; If no error was caused, we check the return value for our invariant.

             ((not (keyword-value-listp val))
              (er soft ctx
                  "The custom keyword hint ~x0 in the context below ~
                   generated a result that is not of the form (:key1 ~
                   val1 ... :keyn valn), where the :keyi are ~
                   keywords. The context is ~y1, and the result ~
                   generated was ~y2."
                  keyi
                  keyword-alist
                  val))
             (t

; We now know that val is a plausible new keyword-alist and replaces
; the old one.

              (pprogn
               (cond
                ((f-get-global 'show-custom-keyword-hint-expansion state)
                 (io? prove nil state
                      (keyi id  keyword-alist val)
                      (fms "~%(Advisory from ~
                            show-custom-keyword-hint-expansion:  The custom ~
                            keyword hint ~x0, appearing in ~@1, ~
                            transformed~%~%~Y23,~%into~%~%~Y43.)~%"
                           (list
                            (cons #\0 keyi)
                            (cons #\1 (tilde-@-clause-id-phrase id))
                            (cons #\2 (cons
                                       (string-for-tilde-@-clause-id-phrase id)
                                       keyword-alist))
                            (cons #\3 (term-evisc-tuple nil state))
                            (cons #\4 (cons
                                       (string-for-tilde-@-clause-id-phrase id)
                                       val)))
                           (proofs-co state)
                           state
                           nil)))
                (t state))
               (custom-keyword-hint-interpreter1
                val
                (- max 1)
                specified-id
                id clause wrld stable-under-simplificationp
                hist pspv ctx state
                keyword-alist0 eagerp)))))))))))
   (t (value nil))))

(defun custom-keyword-hint-interpreter
  (keyword-alist specified-id
              id clause wrld stable-under-simplificationp
              hist pspv ctx state eagerp)

; Warning: If you change or rearrange the arguments of this function,
; be sure to change custom-keyword-hint-in-computed-hint-form and
; put-cl-id-of-custom-keyword-hint-in-computed-hint-form.

; This function evaluates the custom keyword hints in keyword-alist.
; It either signals an error or returns as the value component of its
; error triple a new keyword-alist.  

; Eagerp should be set to t if this is an attempt to expand the custom
; keyword hints at pre-process time.  If eagerp = t, then it is
; assumed that CLAUSE, STABLE-UNDER-SIMPLIFICATIONP, HIST, and
; PSPV are bogus (nil).  

; WARNING: This function should be called from an mv-let, not an
; er-let*!  The erroneous return from this function should be handled
; carefully when eagerp = t.  It is possible in that case that the
; returned value, val, of (mv t erp state), is actually the symbol
; WAIT.  This means that during the eager expansion of some custom
; keyword hint we encountered a hint that required the dynamic
; variables.  It is not strictly an error, i.e., the caller shouldn't
; abort.

  (custom-keyword-hint-interpreter1
   keyword-alist *custom-keyword-max-iterations* specified-id id clause wrld
   stable-under-simplificationp hist pspv ctx state keyword-alist eagerp))

(defun custom-keyword-hint-in-computed-hint-form (computed-hint-tuple)

; Note:  Keep this in sync with eval-and-translate-hint-expression.
; That function uses the AND test below but not the rest, because it
; is dealing with the term itself, not the tuple.

; We assume computed-hint-tuple is the internal form of a computed
; hint.  If it is a custom keyword hint, we return the non-nil keyword
; alist supplied by the user.  Otherwise, nil.

; A translated computed hint has the form
; (EVAL-AND-TRANSLATE-HINT-EXPRESSION name-tree stablep term) and we
; assume that computed-hint-tuple is of that form.  A custom keyword
; hint is coded as a computed hint, where term, above, is
; (custom-keyword-hint-interpreter '(... :key val ...) 'cl-id ...)
; We insist that the keyword alist is a quoted constant (we will
; return its evg).  We also insist that the cl-id is a quoted
; constant.

  (let ((term (nth 3 computed-hint-tuple)))
    (cond ((and (nvariablep term)
                (not (fquotep term))
                (eq (ffn-symb term) 'custom-keyword-hint-interpreter)
                (quotep (fargn term 1))
                (quotep (fargn term 2)))
           (cadr (fargn term 1)))
          (t nil))))

(defun put-cl-id-of-custom-keyword-hint-in-computed-hint-form
  (computed-hint-tuple cl-id)

; We assume the computed-hint-tuple is a computed hint tuple and has
; passed custom-keyword-hint-in-computed-hint-form.  We set the cl-id
; field to cl-id.  This is only necessary in order to fix the cl-id
; for :or hints, which was set for the goal to which the :or hint was
; originally attached.

  (let ((term (nth 3 computed-hint-tuple)))
    (list 'eval-and-translate-hint-expression
          (nth 1 computed-hint-tuple)
          (nth 2 computed-hint-tuple)
          (fcons-term* 'custom-keyword-hint-interpreter
                       (fargn term 1)
                       (kwote cl-id)
                       (fargn term 3)
                       (fargn term 4)
                       (fargn term 5)
                       (fargn term 6)
                       (fargn term 7)
                       (fargn term 8)
                       (fargn term 9)
                       (fargn term 10)
                       (fargn term 11)))))

(defun make-disjunctive-clause-id (cl-id i pkg-name)
  (change clause-id cl-id
          :case-lst
          (append (access clause-id cl-id :case-lst)
                  (list (intern$ (coerce (packn1 (list 'd i)) 'string)
                                 pkg-name)))
          :primes 0))

(defun make-disjunctive-goal-spec (str i pkg-name)
  (let ((cl-id (parse-clause-id str)))
    (string-for-tilde-@-clause-id-phrase
     (make-disjunctive-clause-id cl-id i pkg-name))))

(defun minimally-well-formed-or-hintp (val)
  (cond ((atom val)
         (equal val nil))
        (t (and (consp (car val))
                (true-listp (car val))
                (evenp (length (car val)))
                (minimally-well-formed-or-hintp (cdr val))))))

(defun split-keyword-alist (key keyword-alist)
  (cond ((endp keyword-alist) (mv nil nil))
        ((eq key (car keyword-alist))
         (mv nil keyword-alist))
        (t (mv-let (pre post)
                   (split-keyword-alist key (cddr keyword-alist))
                   (mv (cons (car keyword-alist)
                             (cons (cadr keyword-alist)
                                   pre))
                       post)))))

(defun distribute-other-hints-into-or1 (pre x post)
  (cond ((endp x) nil)
        (t (cons (append pre (car x) post)
                 (distribute-other-hints-into-or1 pre (cdr x) post)))))

(defun distribute-other-hints-into-or (keyword-alist)

; We know keyword-alist is a keyword alist, that there is exactly one :OR, and
; that the value, val, of that :OR is a true-list of non-empty
; true-lists, each of which is of even length.  We distribute the
; other hints into the :OR.  Thus, given:

; (:in-theory a :OR ((:use l1) (:use l2)) :do-not '(...))

; we return:

; ((:OR ((:in-theory a :use l1 :do-not '(...))
;        (:in-theory a :use l2 :do-not '(...)))))

  (mv-let (pre post)
          (split-keyword-alist :OR keyword-alist)
          (list :OR
                (distribute-other-hints-into-or1 pre
                                                 (cadr post)
                                                 (cddr post)))))

(defconst *hint-expression-basic-vars*
  '(id clause world stable-under-simplificationp hist pspv ctx state))

(defconst *hint-expression-override-vars*
  (cons 'keyword-alist *hint-expression-basic-vars*))

(defconst *hint-expression-backtrack-vars*
  (append '(clause-list processor)
          (remove1-eq 'stable-under-simplificationp
                      *hint-expression-basic-vars*)))

(defconst *hint-expression-all-vars*
  (union-equal *hint-expression-override-vars*
               (union-equal *hint-expression-backtrack-vars*
                            *hint-expression-basic-vars*)))

(defun translate-hint-expression (name-tree term hint-type ctx wrld state)

; Term can be either (a) a non-variable term or (b) a symbol.

; (a) We allow a hint of the form term, where term is a term single-threaded in
; state that returns a single non-stobj value or an error triple and contains
; no free vars other than ID, CLAUSE, WORLD, STABLE-UNDER-SIMPLIFICATIONP,
; HIST, PSPV, CTX, and STATE, except that if if hint-type is non-nil then there
; may be additional variables.
; 
; If term is such a term, we return the translated hint:

; (EVAL-AND-TRANSLATE-HINT-EXPRESSION name-tree flg term')

; where term' is the translation of term and flg indicates whether
; STABLE-UNDER-SIMPLIFICATIONP occurs freely in it.

; (b) We also allow term to be a symbol denoting a 3, 4, or 7 argument function
; not involving state and returning a single value taking:

;     (i)   a clause-id, a clause, and world, or,
;     (ii)  a clause-id, a clause,     world, and 
;           stable-under-simplificationp, or
;     (iii) a clause-id, a clause,     world,
;           stable-under-simplificationp, hist, pspv, and ctx.

; We ``translate'' such a function symbol into a call of the function on the
; appropriate argument variables.

  (cond
   ((symbolp term)
    (cond ((and (function-symbolp term wrld)
                (or (equal (arity term wrld) 3)
                    (equal (arity term wrld) 4)
                    (equal (arity term wrld) 7))
                (all-nils (stobjs-in term wrld))
                (not (eq term 'return-last)) ; avoid taking stobjs-out
                (equal (stobjs-out term wrld) '(nil)))
           (value
            (cond
             ((equal (arity term wrld) 3)
              (list 'eval-and-translate-hint-expression
                    name-tree
                    nil
                    (formal-value-triple
                     *nil*
                     (fcons-term term '(id clause world)))))
             ((equal (arity term wrld) 4)
              (list 'eval-and-translate-hint-expression
                    name-tree
                    t
                    (formal-value-triple
                     *nil*
                     (fcons-term term
                                 '(id clause world
                                      stable-under-simplificationp)))))
             (t
              (list 'eval-and-translate-hint-expression
                    name-tree
                    t
                    (formal-value-triple
                     *nil*
                     (fcons-term term
                                 '(id clause world
                                      stable-under-simplificationp
                                      hist pspv ctx))))))))
          (t (er soft ctx
                 "When you give a hint that is a symbol, it must be a ~
                  function symbol of three, four or seven arguments (not ~
                  involving STATE or other single-threaded objects) that ~
                  returns a single value.  The allowable arguments are ID, ~
                  CLAUSE, WORLD, STABLE-UNDER-SIMPLIFICATIONP, HIST, PSPV, ~
                  and CTX. See :DOC computed-hints.  ~x0 is not such a symbol."
                 term))))
   (t
    (er-let*
     ((tterm (translate-simple-or-error-triple term ctx wrld state)))
     (let ((vars (all-vars tterm)))
       (cond
        ((subsetp-eq vars
                     (case hint-type
                       (backtrack *hint-expression-backtrack-vars*)
                       (override *hint-expression-override-vars*)
                       (otherwise *hint-expression-basic-vars*)))
         (value
          (list 'eval-and-translate-hint-expression
                name-tree
                (if (member-eq 'stable-under-simplificationp vars) t nil)
                tterm)))
        ((and (not hint-type) ; optimization
              (subsetp-eq vars *hint-expression-all-vars*))
         (let ((backtrack-bad-vars (intersection-eq '(CLAUSE-LIST PROCESSOR)
                                                    vars))
               (override-bad-vars (intersection-eq '(KEYWORD-ALIST)
                                                   vars)))
           (mv-let
            (bad-vars types-string)
            (cond (backtrack-bad-vars
                   (cond (override-bad-vars
                          (mv (append backtrack-bad-vars override-bad-vars)
                              ":BACKTRACK hints or override-hints"))
                         (t (mv backtrack-bad-vars ":BACKTRACK hints"))))
                  (t (assert$
                      override-bad-vars ; see subsetp-eq call above
                      (mv override-bad-vars "override-hints"))))
            (er soft ctx
                "The hint expression ~x0 mentions ~&1.  But variable~#2~[ ~&2 ~
                 is~/s ~&2 are~] legal only for ~@3.  See :DOC ~
                 computed-hints."
                term vars bad-vars types-string))))
        (t
         (mv-let
          (type-string legal-vars extra-doc-hint)
          (case hint-type
            (backtrack (mv ":BACKTRACK hint"
                       *hint-expression-backtrack-vars*
                       " and see :DOC hints for a discussion of :BACKTRACK ~
                        hints"))
            (override (mv "override-hint"
                          *hint-expression-override-vars*
                          " and see :DOC override-hints"))
            (otherwise (mv "Computed"
                           *hint-expression-basic-vars*
                           "")))
          (er soft ctx
              "~@0 expressions may not mention any variable symbols other ~
               than ~&1.  See :DOC computed-hints~@2.  But the hint ~
               expression ~x3 mentions ~&4."
              type-string
              legal-vars
              extra-doc-hint
              term
              vars)))))))))

(defun translate-backtrack-hint (name-tree arg ctx wrld state)
  (translate-hint-expression name-tree arg 'backtrack ctx wrld state))

(mutual-recursion

(defun translate-or-hint (name-tree str arg ctx wrld state)

; Arg is the value of the :OR key in a user-supplied hint settings,
; e.g., if the user typed: :OR ((:in-theory t1 :use lem1) (:in-theory
; t2 :use lem2)) then arg is ((:in-theory t1 :use lem1) (:in-theory t2
; :use lem2)).  The translated form of this is a list as long as arg
; in which each element of the translated list is a pair (orig
; . trans) where orig is what the user typed and trans is its
; translation as a hint-settings.  (For example, the two theory
; expressions, t1 and t2, will be expanded into full runic
; theories.)  We either cause an error or return (as the value
; component of an error/value/state triple) a list of such pairs.

; Note: str is the original goal-spec string to which this :OR was
; attached.

; Note: Unlike other hints, we do some additional translation of :OR
; hints on the output of this function!  See translate-hint.

  (cond ((atom arg)
         (if (null arg)
             (value nil)
           (er soft ctx
               "An :OR hint must be a true-list.")))
        (t (er-let*
             ((val (translate-hint name-tree
                                   (cons
                                    (make-disjunctive-goal-spec
                                     str
                                     (length arg)
                                     (current-package state))
                                    (car arg))
                                   nil ctx wrld state))
              (tl (translate-or-hint name-tree str (cdr arg) ctx wrld state)))

; Val is either a translated computed hint expression, whose car
; is eval-and-translate-hint-expression, or else it is a pair of
; the form (cl-id . hint-settings), where cl-id was derived from
; str.

             (cond
              ((eq (car val) 'eval-and-translate-hint-expression)
               (value (cons (cons (car arg) val)
                            tl)))
              (t

; If val is (cl-id . hint-settings), we just let val be hint-settings
; below, as the cl-id is being managed by the :OR itself.

               (let ((val (cdr val)))
                 (value (cons (cons (car arg) val)
                              tl)))))))))

(defun translate-hint-settings (name-tree str key-val-lst ctx wrld state)

; We assume that key-val-lst is a list of :keyword/value pairs, (:key1
; val1 ... :keyn valn), and that each :keyi is one of the acceptable
; hint keywords.  We convert key-val-lst to alist form, ((:key1 .
; val1') ... (:keyn . valn')), where each vali' is the translated form
; of vali.

; Str is the goal-spec string identifying the clause to which these
; hints are attached.

  (cond
   ((null key-val-lst) (value nil))
   ((and (eq (car key-val-lst) :use)
         (eq (cadr key-val-lst) nil))

; We allow empty :use hints, but we do not want to have to think about
; how to process them.

    (translate-hint-settings name-tree
                             str
                             (cddr key-val-lst) ctx wrld state))
   (t (er-let*
       ((val (translate-x-hint-value name-tree
                                     str
                                     (car key-val-lst) (cadr key-val-lst)
                                     ctx wrld state))
        (tl (translate-hint-settings name-tree
                                     str
                                     (cddr key-val-lst) ctx wrld state)))
       (value
        (cons (cons (car key-val-lst) val)
              tl))))))

(defun translate-x-hint-value (name-tree str x arg ctx wrld state)

; Str is the goal-spec string identifying the clause to which this
; hint was attached.  

  (mv-let
   (flg uterm1 uterm2)
   (custom-keyword-hint x wrld)
   (declare (ignore uterm1))
   (cond
    (flg
     (translate-custom-keyword-hint arg uterm2 ctx wrld state))
    (t
     (case x
       (:expand
        (translate-expand-hint arg ctx wrld state))
       (:restrict
        (translate-restrict-hint arg ctx wrld state))
       (:hands-off
        (translate-hands-off-hint arg ctx wrld state))
       (:do-not-induct
        (translate-do-not-induct-hint arg ctx wrld state))
       (:do-not
        (translate-do-not-hint arg ctx state))
       (:use
        (translate-use-hint arg ctx wrld state))
       (:or
        (translate-or-hint name-tree str arg ctx wrld state))
       (:cases
        (translate-cases-hint arg ctx wrld state))
       (:case-split-limitations
        (translate-case-split-limitations-hint arg ctx wrld state))
       (:by
        (translate-by-hint name-tree arg ctx wrld state))
       (:induct
        (translate-induct-hint arg ctx wrld state))
       (:in-theory
        (translate-in-theory-hint arg t ctx wrld state))
       (:bdd
        (translate-bdd-hint arg ctx wrld state))
       (:clause-processor
        (translate-clause-processor-hint arg ctx wrld state))
       (:nonlinearp
        (translate-nonlinearp-hint arg ctx wrld state))
       (:no-op
        (translate-no-op-hint arg ctx wrld state))
       (:no-thanks
        (translate-no-thanks-hint arg ctx wrld state))
       (:reorder
        (translate-reorder-hint arg ctx wrld state))
       (:backtrack
        (translate-backtrack-hint name-tree arg ctx wrld state))
       (:backchain-limit-rw
        (translate-backchain-limit-rw-hint arg ctx wrld state))
       (:error

; We know this case never happens.  The error is caught and signalled
; early by translate-hint.  But we include it here to remind us that
; :error is a legal keyword.  In fact the semantics given here --
; which causes an immediate error -- is also consistent with the
; intended interpretation of :error.

        (translate-error-hint arg ctx wrld state))
       (otherwise
        (mv
         (er hard 'translate-x-hint-value
             "The object ~x0 not recognized as a legal hint keyword. See :DOC ~
              hints."
             x)
         nil
         state)))))))

(defun replace-goal-spec-in-name-tree1 (name-tree goal-spec)
  (cond
   ((atom name-tree)
    (cond ((and (stringp name-tree)
                (parse-clause-id name-tree))
           (mv t goal-spec))
          (t (mv nil name-tree))))
   (t (mv-let
       (flg1 name-tree1)
       (replace-goal-spec-in-name-tree1 (car name-tree)
                                        goal-spec)
       (cond
        (flg1 (mv t (cons name-tree1 (cdr name-tree))))
        (t (mv-let (flg2 name-tree2)
                   (replace-goal-spec-in-name-tree1 (cdr name-tree)
                                                    goal-spec)
                   (mv flg2 
                       (cons (car name-tree)
                             name-tree2)))))))))

(defun replace-goal-spec-in-name-tree (name-tree goal-spec)

; Name-trees are trees of strings and symbols used to generate
; meaningful names for :by hints.  Typically, a name tree will have at
; most one goal spec in it, e.g., (name . "Subgoal *1/3") or
; ("Computed hint auto-generated for " (name . "Subgoal *1/3")).  We
; search nametree for the first occurrence of a goal spec and replace
; that goal spec by the given one.  This is an entirely heuristic
; operation. 

; Why do we do this?  Suppose an :OR hint is attached to a given goal
; spec and we have a name tree corresponding to that goal spec.  To process
; the :OR we will produce a copy of the goal and rename the goal spec
; by adding a "Dj" suffice.  We want to replace the original goal spec
; in the name-tree by this modified goal spec.

  (mv-let (flg new-name-tree)
          (replace-goal-spec-in-name-tree1 name-tree goal-spec)
          (cond
           (flg new-name-tree)
           (t (cons name-tree goal-spec)))))

(defun translate-hint (name-tree pair hint-type ctx wrld state)

; Pair is supposed to be a "hint", i.e., a pair of the form (str :key1
; val1 ...  :keyn valn).  We check that it is, that str is a string
; that parses to a clause-id, and that each :keyi is a legal hint
; keyword.  Then we translate pair into a pair of the form (cl-id .
; hint-settings), where cl-id is the parsed clause-id and
; hint-settings is the translated alist form of the key/val lst above.
; We try to eliminate custom keyword hints by eager expansion.  If we
; cannot eliminate all custom hints, we do check that the individual
; :keyi vali pairs are translatable (which, in the case of the custom
; hints among them, means we run their checkers) but we ignore the
; translations.  We then convert the entire hint into a computed hint.

; We return a standard error triple.  If no custom keyword hints
; appear (or if all custom hints could be eagerly eliminated), the
; value is (cl-id . hint-settings).  If an un-eliminable custom
; keyword hint appears, the value is the translated form of a computed
; hint -- with the original version of the hint appearing in it as a
; quoted constant.

; Thus, if the car of the returned value is the word
; 'eval-and-translate-hint-expression the answer is a translated
; computed hint, otherwise it is of the form (cl-id . hint-settings).

  (cond ((not (and (consp pair)
                   (stringp (car pair))
                   (keyword-value-listp (cdr pair))))
         (er soft ctx
             "Each hint is supposed to be a list of the form (str :key1 val1 ~
              ... :keyn valn), but a proposed hint, ~x0, is not.  See :DOC ~
              hints."
             pair))
        (t (let ((cl-id (parse-clause-id (car pair))))
             (cond
              ((null cl-id)
               (er soft ctx
                   "The object ~x0 is not a goal-spec.  See :DOC hints and ~
                    :DOC goal-spec."
                   (car pair)))
              ((assoc-keyword :error (cdr pair))

; If an :error hint was given, we immediately cause the requested error.
; Note that we thus allow :error hints to occur multiple times and just
; look at the first one.  If we get past this test, there are no
; :error hints.

               (translate-error-hint
                (cadr (assoc-keyword :error (cdr pair)))
                ctx wrld state))
              (t
               (mv-let
                (keyi vali uterm1 uterm2)
                (find-first-custom-keyword-hint (cdr pair) wrld)
                (declare (ignore vali uterm1 uterm2))
                (cond
                 (keyi

; There is a custom keyword among the keys.  One of two possibilities
; exists.  The first is that the hint can be expanded statically
; (``eagerly'') now.  The second is that the hint is truly sensitive
; to dynamically determined variables like the variables CLAUSE, HIST,
; STABLE-UNDER-SIMPLIFICATIONP, or PSPV and must consequently be
; treated essentially as a computed hint.  But there is no way to find
; out except by trying to evaluate it!  That is because even if this
; hint involves none of the dynamic variables it might be that the
; value it computes contains other custom keyword hints that do
; involve those variables.

; Note: Recall that the interpreter runs the checker on a val before
; it runs the generator.  So each generator knows that its val is ok.
; But generators do not know that all vals are ok.  That is, a
; generator cannot assume that a common hint has a well-formed val or
; that other custom hints have well-formed vals.

                  (mv-let
                   (erp val state)
                   (custom-keyword-hint-interpreter
                    (cdr pair)
                    cl-id
                    cl-id
                    NIL wrld NIL NIL NIL ctx state
                    t)

; The four NILs above are bogus values for the dynamic variables.  The
; final t is the eagerp flag which will cause the interpreter to
; signal the WAIT ``error'' if the expansion fails because of some
; unbound dynamic variable.

                    (cond
                     (erp
                      (cond
                       ((eq val 'WAIT)

; In this case, we must treat this as a computed hint so we will
; manufacture an appropriate one.  As a courtesy to the user, we will
; check that all the hints are translatable.  But we ignore the
; translations because there is no way to know whether they are
; involved in the actual hint that will be generated by the processing
; of these custom hints when the subgoal arises.

                        (er-let*
                          ((hint-settings
                            (translate-hint-settings
                             (replace-goal-spec-in-name-tree
                              name-tree
                              (car pair))
                             (car pair)
                             (cdr pair)
                             ctx wrld state)))

; Note: If you ever consider not ignoring the translated
; hint-settings, recognize how strange it is.  E.g., it may have
; duplicate conflicting bindings of standard keys and pairs
; binding custom keywords to their untranslated values, a data
; structure we never use.
                  
                          (translate-hint-expression
                           name-tree

; Below we generate a standard computed hint that uses the
; interpreter.  Note that the interpreter is given the eagerp
; NIL flag.

                           `(custom-keyword-hint-interpreter
                             ',(cdr pair)
                             ',cl-id
                             ID CLAUSE WORLD STABLE-UNDER-SIMPLIFICATIONP
                             HIST PSPV CTX STATE 'nil)
                           hint-type ctx wrld state)))
                       (t (mv t nil state))))
                     (t

; In this case, we have eliminated all custom keyword hints
; eagerly and val is a keyword alist we ought to
; use for the hint.  We translate it from scratch.

                      (translate-hint name-tree
                                      (cons (car pair) val)
                                      hint-type ctx wrld state)))))
                 (t

; There are no custom keywords in the hint.

                  (let* ((key-val-lst (remove-redundant-no-ops (cdr pair)))

; By stripping out redundant :NO-OPs now we allow such lists as (:OR x
; :NO-OP T), whereas normally :OR would "object" to the presence of
; another hint.

                         (keys (evens key-val-lst))
                         (expanded-hint-keywords
                          (append
                           (strip-cars
                            (table-alist 'custom-keywords-table wrld))
                           *hint-keywords*)))
                    (cond
                     ((null keys)
                      (er soft ctx
                          "There is no point in attaching the empty list of ~
                           hints to ~x0.  We suspect that you have made a ~
                           mistake in presenting your hints.  See :DOC hints. ~
                           ~ If you really want a hint that changes nothing, ~
                           use ~x1."
                          (car pair)
                          (cons (car pair) '(:NO-OP T))))
                     ((not (subsetp-eq keys expanded-hint-keywords))
                      (er soft ctx
                          "The legal hint keywords are ~&0.  ~&1 ~
                           ~#1~[is~/are~] unrecognized.  See :DOC hints."
                          expanded-hint-keywords
                          (set-difference-eq keys expanded-hint-keywords)))
                     ((member-eq :computed-hints-replacement keys)

; If translate-hint is called correctly, then we expect this case not to arise
; for well-formed hints.  For example, in eval-and-translate-hint-expression we
; remove an appropriate use of :computed-hints-replacement.

                      (er soft ctx
                          "The hint keyword ~x0 has been used incorrectly.  ~
                           Its only appropriate use is as a leading hint ~
                           keyword in computed hints.  See :DOC ~
                           computed-hints."
                          :computed-hints-replacement))
                     ((not (no-duplicatesp-equal keys))
                      (er soft ctx
                          "You have duplicate occurrences of the hint keyword ~
                           ~&0 in your hint.  While duplicate occurrences of ~
                           keywords are permitted by CLTL, the semantics ~
                           ignores all but the left-most.  We therefore ~
                           suspect that you have made a mistake in presenting ~
                           your hints."
                          (duplicates keys)))
                     ((and (assoc-keyword :OR (cdr pair))
                           (not (minimally-well-formed-or-hintp
                                 (cadr (assoc-keyword :OR (cdr pair))))))

; Users are inclined to write hints like this:

; ("Goal" :OR ((...) (...)) :in-theory e)

; as abbreviations for

; ("Goal" :OR ((... :in-theory e) (... :in-theory e)))

; We implement this abbreviation below.  But we have to know that the
; value supplied to the :OR is a list of non-empty true-lists of even
; lengths to insure that we can append the other hints to it and still
; get reasonable translation errors in the presence of ill-formed
; hints.  If not, we cause an error now.  We check the rest of the
; restrictions on :OR after the transformation.

                      (er soft ctx
                          "The value supplied to an :OR hint must be a ~
                           non-empty true-list of non-empty true-lists of ~
                           even length, i.e., of the form ((...) ...).  But ~
                           you supplied the value ~x0."
                          (cdr pair)))
                     ((and (member-eq :induct keys)
                           (member-eq :use keys))
                      (er soft ctx
                          "We do not support the use of an :INDUCT hint with ~
                           a :USE hint.  When a subgoal with an :INDUCT hint ~
                           arises, we push it for proof by induction.  Upon ~
                           popping it, we interpret the :INDUCT hint to ~
                           determine the induction and we also install any ~
                           other non-:USE hints supplied.  On the other hand, ~
                           when a subgoal with a :USE hint arises, we augment ~
                           the formula with the additional hypotheses ~
                           supplied by the hint.  If both an :INDUCT and a ~
                           :USE hint were attached to the same subgoal we ~
                           could either add the hypotheses before induction, ~
                           which is generally detrimental to a successful ~
                           induction, or add them to each of the formulas ~
                           produced by the induction, which generally adds ~
                           the hypotheses in many more places than they are ~
                           needed.  We therefore do neither and cause this ~
                           neat, informative error.  You are encouraged to ~
                           attach the :INDUCT hint to the goal or subgoal to ~
                           which you want us to apply induction and then ~
                           attach :USE hints to the individual subgoals ~
                           produced, as necessary.  For what it is worth, ~
                           :INDUCT hints get along just fine with hints ~
                           besides :USE.  For example, an :INDUCT hint and an ~
                           :IN-THEORY hint would cause an induction and set ~
                           the post-induction locally enabled theory to be as ~
                           specified by the :IN-THEORY."))
                     ((and (member-eq :reorder keys)
                           (intersectp-eq '(:or :induct) keys))
                      (cond
                       ((member-eq :or keys)
                        (er soft ctx
                            "We do not support the use of a :REORDER hint ~
                             with an :OR hint.  The order of disjunctive ~
                             subgoals corresponds to the list of hints given ~
                             by the :OR hint, so you may want to reorder that ~
                             list instead."))
                       (t
                        (er soft ctx
                            "We do not support the use of a :REORDER hint ~
                             with an :INDUCT hint.  If you want this ~
                             capability, please send a request to the ACL2 ~
                             implementors."))))
                     (t
                      (let ((bad-keys (intersection-eq
                                       `(:induct ,@*top-hint-keywords*)
                                       keys)))
                        (cond
                         ((and (< 1 (length bad-keys))
                               (not (and (member-eq :use bad-keys)
                                         (member-eq :cases bad-keys)
                                         (equal 2 (length bad-keys)))))
                          (er soft ctx
                              "We do not support the use of a~#0~[n~/~] ~x1 ~
                               hint with a~#2~[n~/~] ~x3 hint, since they ~
                               suggest two different ways of replacing the ~
                               current goal by new goals.  ~@4Which is it to ~
                               be?  To summarize:  A~#0~[n~/~] ~x1 hint ~
                               together with a~#2~[n~/~] ~x3 hint is not ~
                               allowed because the intention of such a ~
                               combination does not seem sufficiently clear."
                              (if (member-eq (car bad-keys) '(:or :induct))
                                  0 1)
                              (car bad-keys)
                              (if (member-eq (cadr bad-keys) '(:or :induct))
                                  0 1)
                              (cadr bad-keys)
                              (cond
                               ((and (eq (car bad-keys) :by)
                                     (eq (cadr bad-keys) :induct))
                                "The :BY hint suggests that the goal follows ~
                                 from an existing theorem, or is to be ~
                                 pushed.  However, the :INDUCT hint provides ~
                                 for replacement of the current goal by ~
                                 appropriate new goals before proceeding.  ")
                               (t ""))))
                         (t
                          (er-let* ((hint-settings
                                     (translate-hint-settings
                                      (replace-goal-spec-in-name-tree
                                       name-tree
                                       (car pair))
                                      (car pair)
                                      (cond
                                       ((assoc-keyword :or (cdr pair))
                                        (distribute-other-hints-into-or
                                         (cdr pair)))
                                       (t (cdr pair)))
                                      ctx wrld state)))
                            (cond

; Hint-settings is of the form ((:key1 . val1) ...(:keyn . valn)).
; If :key1 is :OR, we know n=1; translated :ORs always occur as
; singletons.  But in ((:OR . val1)), val1 is always
; (((key . val) ...) ... ), i.e., is a list of alists.
; If there is only one alist in that list, then we're dealing
; with an :OR with only one disjunct.

                             ((and (consp hint-settings)
                                   (eq (caar hint-settings) :OR)
                                   (consp (cdr (car hint-settings)))
                                   (null (cddr (car hint-settings))))

; This is a singleton :OR.  We just drop the :OR.

                              (assert$
                               (null (cdr hint-settings))
                               (value
                                (cons cl-id
                                      (car (cdr (car hint-settings)))))))
                             (t (value
                                 (cons cl-id hint-settings))))))))))))))))))))
)

(defun translate-hint-expressions (name-tree terms hint-type ctx wrld state)

; This function translates a true-list of hint expressions.  It is used when a
; hint generates a new list of hints.

  (cond
   ((endp terms)
    (cond ((equal terms nil) (value nil))
          (t (er soft ctx
                 "The value of the :COMPUTED-HINT-REPLACEMENT key must be ~
                  NIL, T, or a true list of terms.  Your list ends in ~x0."
                 terms))))
   (t (er-let* ((thint (translate-hint-expression name-tree (car terms)
                                                  hint-type ctx wrld
                                                  state))
                (thints (translate-hint-expressions name-tree (cdr terms)
                                                    hint-type ctx wrld state)))
        (value (cons thint thints))))))

(defun check-translated-override-hint (hint uhint ctx state)
  (cond ((not (and (consp hint)
                   (eq (car hint)
                       'eval-and-translate-hint-expression)))
         (er soft ctx
             "The proposed override-hint, ~x0, was not a computed hint.  See ~
              :DOC override-hints."
             uhint))
        (t ; term is (caddr (cdr hint)); we allow any term here
         (value nil))))

(defun translate-hints1 (name-tree lst hint-type override-hints ctx wrld state)

; A note on the taxonomy of hints.  A "hint setting" is a pair of the
; form (key . val), such as (:DO-NOT-INDUCT . T) or (:USE . (lmi-lst
; (h1...hn) ...)).  List of such pairs are called "hint settings."  A
; pair consisting of a clause-id and some hint-settings is called a
; "hint".  A list of such pairs is called "hints."

; Thus, following the :HINTS keyword to defthm, the user types "hints" (in
; untranslated form).  This function takes a lst, which is supposed be some
; hints, and translates it or else causes an error.

; Essay on the Handling of Override-hints

; When we translate an explicit (not computed) hint in the presence of at least
; one non-trivial override hint in the world, we append to the front of the
; hint-settings the list (:keyword-alist . x) (:name-tree . n), where x is the
; untranslated keyword-alist corresponding to hint-settings and n is the
; name-tree used for translation: so the hint is (goal-name (:keyword-alist
; . x) (:name-tree . n) (kwd1 . v1) ... (kwdk . vk)).  Later, when we select
; the hint with find-applicable-hint-settings, we will see (:keyword-alist . x)
; and apply the override-hints to x, and if the result of apply-override-hints
; is also x, then we will return ((kwd1 . v1) ... (kwdk . vk)); otherwise we
; will translate that result.  Note that in the special case that the original
; hint had at least one custom keyword hint but the ultimate resulting
; expansion was an explicit hint, the same technique will apply.  Also note
; that the keyword :keyword-alist is illegal for users, and would be flagged as
; such by translate-hint in translate-hints1; so we have full control over the
; use of :keyword-alist (and similarly for :name-tree).

; If however the resulting translated hint is a computed hint, i.e. a list
; whose car is 'eval-and-translate-hint-expression, then no modification is
; necessary; function find-applicable-hint-settings takes care to apply
; override-hints, by calling function eval-and-translate-hint-expression with
; the override-hints supplied.

; And how about backtrack hints?  Backtrack hints are computed hints, and
; receive the same treatment as described above, i.e. for computed hints
; selected by find-applicable-hint-settings -- namely, by passing the world's
; override-hints to eval-and-translate-hint-expression.

  (cond ((atom lst)
         (cond ((null lst) (value nil))
               (t (er soft ctx
                      "The :HINTS keyword is supposed to have a true-list as ~
                       its value, but ~x0 is not one.  See :DOC hints."
                      lst))))
        ((and (consp (car lst))
              (stringp (caar lst))
              (null (cdar lst)))
         (translate-hints1 name-tree (cdr lst) hint-type override-hints ctx
                           wrld state))
        (t (er-let*
            ((hint (cond ((and (consp (car lst))
                               (stringp (caar lst)))
                          (translate-hint name-tree (car lst) hint-type ctx
                                          wrld state))
                         (t (translate-hint-expression
                             name-tree (car lst) hint-type ctx wrld state))))
             (rst (translate-hints1 name-tree (cdr lst) hint-type
                                    override-hints ctx wrld state)))
            (er-progn
             (cond ((eq hint-type 'override)
                    (check-translated-override-hint hint (car lst) ctx state))
                   (t (value nil)))
             (value (cons (cond ((atom hint) hint) ; nil
                                ((and (consp (car lst))
                                      (stringp (caar lst)))
                                 (cond (override-hints
                                        (list* (car hint) ; (caar lst)
                                               (cons :KEYWORD-ALIST
                                                     (cdar lst))
                                               (cons :NAME-TREE
                                                     name-tree)
                                               (cdr hint)))
                                       (t hint)))
                                ((eq (car hint)
                                     'eval-and-translate-hint-expression)
                                 hint)
                                (t (er hard ctx
                                       "Internal error: Unexpected ~
                                        translation ~x0 for hint ~x1.  Please ~
                                        contact the ACL2 implementors."
                                       hint (car lst))))
                          rst)))))))

(defun warn-on-duplicate-hint-goal-specs (lst seen ctx state)
  (cond ((endp lst)
         state)
        ((and (consp (car lst))
              (stringp (caar lst)))
         (if (member-equal (caar lst) seen)
             (pprogn (warning$ ctx ("Hints")
                               "The goal-spec ~x0 is explicitly associated ~
                                with more than one hint.  All but the first ~
                                of these hints may be ignored.  If you ~
                                intended to give all of these hints, combine ~
                                them into a single hint of the form (~x0 ~
                                :kwd1 val1 :kwd2 val2 ...).  See :DOC ~
                                hints-and-the-waterfall."
                               (caar lst))
                     (warn-on-duplicate-hint-goal-specs (cdr lst) seen ctx
                                                        state))
           (warn-on-duplicate-hint-goal-specs (cdr lst) (cons (caar lst) seen)
                                              ctx state)))
        (t (warn-on-duplicate-hint-goal-specs (cdr lst) seen ctx state))))

(defun translate-hints2 (name-tree lst hint-type override-hints ctx wrld state)
  (cond ((warning-disabled-p "Hints")
         (translate-hints1 name-tree lst hint-type override-hints ctx wrld
                           state))
        (t
         (er-let* ((hints (translate-hints1 name-tree lst hint-type
                                            override-hints ctx wrld state)))
                  (pprogn (warn-on-duplicate-hint-goal-specs lst nil ctx state)
                          (value hints))))))

(defun override-hints (wrld)
  (declare (xargs :guard (and (plist-worldp wrld)
                              (alistp (table-alist 'default-hints-table
                                                   wrld)))))
  ":Doc-Section Miscellaneous

  a list of hints given priority in every proof attempt~/

  This is an advanced feature, originally implmented to help system designers
  to create ``modes'' that control the way hints are supplied to the theorem
  prover.  Please ~pl[default-hints] for the much more usual way to install
  hints that may be applied by default.~/

  ~bv[]
  Examples:
  ACL2 !>(override-hints (w state))
  ((computed-hint-1 clause keyword-alist processor)
   (computed-hint-2 clause keyword-alist stable-under-simplificationp))
  ~ev[]
  ~c[Override-hints] returns a list of computed hints (~pl[computed-hints])
  which, unlike other computed hints, may mention the variable
  ~c[KEYWORD-ALIST].

  Before reading further, please ~pl[hints-and-the-waterfall] to review the
  basics of how ~il[hints] are applied during a proof.  In particular, we
  assume familiarity with the notion of selecting a hint to be applied to the
  current goal.  If there are override-hints, that hint selection is tentative,
  because if it reduced to ~c[nil] after the application of override-hints,
  then that hint will be skipped and the attempt will continue for selecting an
  applicable hint.  (Craft your override-hints so that ~c[:no-op t] is returned
  in such cases instead of ~c[nil], if you don't want the hint to be skipped.)
  But we must explain what is meant by ``the application of override-hints'',
  and we do that now.

  Suppose that there are override-hints when a hint is selected for the current
  goal.  That selected hint is a keyword-alist, which is an alternating list of
  hint keywords and their values, whose source is either an explicit hint
  ~c[(goal-name :key1 val1 ... :keyn valn)] where the ~c[:keyi] are allowed to
  be custom hint keywords (which are expanded away; ~pl[custom-keyword-hints]),
  or else is the non-~c[nil] result from evaluating a computed hint.  Then the
  override-hints are applied to that keyword-alist as follows, one at a time,
  in order of their occurrence in the list of override-hints (as determined by
  the use of ~ilc[set-override-hints] and ~ilc[add-override-hints]).  The first
  override-hint is evaluated, in the usual manner of evaluating computed hints
  but with the variable ~c[KEYWORD-ALIST] bound to the above keyword-alist.
  That evaluation produces a result that should also be a keyword-alist, or
  else an error occurs.  Any custom keyword hints are then eliminated from that
  keyword-alist.  The resulting keyword-alist must not contain the ~c[:ERROR]
  hint keyword and must not start with the ~c[:COMPUTED-HINT-REPLACEMENT]
  keyword; otherwise an error occurs.  With ~c[KEYWORD-ALIST] is bound to this
  result, the second override-hint is similarly evaluated.  This process
  continues, and the keyword-alist returned by the final override-hint is the
  one used when processing the goal at hand.  If the final result is ~c[nil],
  then the hint is discarded and the remaining hints are considered as above,
  regardless of whether the tentatively selected hint object came from a
  computed hint or from an explicit hint.

  If finally no hint is selected for the current goal, then ~c[KEYWORD-ALIST]
  is bound to ~c[nil] and the override-hints are applied as described above.
  But note that this final step is skipped if hint selection is being performed
  because ~c[stable-under-simplificationp] has just become true, rather than at
  the top of the waterfall.  (Otherwise the override-hints could easily keep
  firing uselessly yet putting us back at the top of the waterfall, with no
  change to the given goal, resulting in an infinite loop.)

  As mentioned above, the ~c[:COMPUTED-HINT-REPLACEMENT] keyword is illegal for
  the value of an override-hint.  But a selected hint may be a computed hint
  that evaluates to a keyword-alist beginning with prefix
  ~c[:COMPUTED-HINT-REPLACEMENT val].  What value does ACL2 return for such a
  computed hint in the presence of override-hints?  First, this prefix is
  stripped off before passing the resulting keyword-alist to the override-hints
  as described above.  If the result of applying override-hints to that
  keyword-alist is not ~c[nil], then the prefix is put back on the front of
  that resulting keyword-alist after doing internal processing of the hint,
  including expansion of any custom keyword hints.  Otherwise, the application
  of override-hints to the computed hint is ~c[nil], so this hint is not
  selected after all.

  ~st[WARNING]: Unlike ordinary computed hints, a value of ~c[nil] for an
  override-hint is not ignored.  That is: When an ordinary computed hint
  evaluates to ~c[nil], it is deemed not to apply, and the next available hint
  is consulted.  But when an override-hint is evaluated, the result is always
  supplied for the next binding of the variable ~c[KEYWORD-ALIST], even if that
  result is ~c[nil].  If you want an override-hint to be a no-op, return as the
  expression the variable ~c[KEYWORD-ALIST] rather than an expression that
  evaluates to ~c[nil].

  This feature can be used in order to implement a form of additive hints.
  Suppose for example that you want a hint that turns off generalization.  A
  simple but inadequate solution is:
  ~bv[]
  (add-default-hints '((quote (:do-not '(generalize)))))
  ~ev[]
  The problem is that if there is any explicit hint supplied for a given goal,
  then it will be the one selected, and the above will be ignored.  But suppose
  that the explicit hint supplied is of the form
  ~c[(\"Subgoal x.y\" :do-not '(fertilize))].  What we would really want in
  this case is to generate the hint for the indicated subgoal that binds
  ~c[:do-not] to a list indicating that both fertilization _and_ generalization
  are disabled for that goal.  A solution is to merge, as follows.
  ~bv[]
  (add-override-hints
   '((let ((tmp (assoc-eq :do-not KEYWORD-ALIST)))
       (put-assoc-eq :do-not
                     (add-to-set-eq 'generalize
                                    (cdr tmp))
                     KEYWORD-ALIST))))
  ~ev[]

  ~sc[Remarks]

  (1) The utilities ~ilc[add-override-hints], ~ilc[add-override-hints!],
  ~ilc[set-override-hints], ~ilc[set-override-hints!],
  ~ilc[remove-override-hints], and ~ilc[remove-override-hints!] are also
  available, in complete analogy to their default-hints versions.

  (2) The distributed book ~c[hints/basic-tests.lisp] illustrates the use of
  override-hints and illuminates a number of corner cases; search in that file
  for ``Test override-hints.''

  (3) The distributed book ~c[hints/merge-hint.lisp] provides support for
  merging hints that might be useful for writers of override-hint expressions
  (see the examples at the end of that file).

  (4) Override-hints are used in the processing of ~c[:BACKTRACK] hints
  (~pl[hints]).
  ~/
  :cite set-override-hints
  :cite set-override-hints!
  :cite add-override-hints
  :cite add-override-hints!
  :cite remove-override-hints
  :cite remove-override-hints!
  "

  (cdr (assoc-eq :override (table-alist 'default-hints-table wrld))))

(defun translate-hints (name-tree lst ctx wrld state)
  (translate-hints2 name-tree lst nil (override-hints wrld) ctx wrld state))

(defun translate-hints+ (name-tree lst default-hints ctx wrld state)
  (cond
   ((not (true-listp lst))
    (er soft ctx
        "The :HINTS keyword is supposed to have a true-list as its value, but ~
         ~x0 is not one.  See :DOC hints."
        lst))
   (t
    (translate-hints name-tree (append lst default-hints) ctx wrld state))))

(defun translate-override-hints (name-tree lst ctx wrld state)
  (translate-hints2 name-tree lst 'override
                    nil ; no override-hints are applied
                    ctx wrld state))

(defun apply-override-hint
  (override-hint cl-id clause hist pspv ctx wrld
                 stable-under-simplificationp clause-list processor
                 keyword-alist state)

; Apply the given override-hints to the given keyword-alist (for a hint) to
; obtain a resulting keyword alist.

  (let* ((tuple override-hint)
         (flg (cadr (cdr tuple)))
         (term (caddr (cdr tuple))))
    (er-let*
     ((new-keyword-alist
       (xtrans-eval
        term
        (list* (cons 'id cl-id)
               (cons 'clause clause)
               (cons 'hist hist)
               (cons 'pspv pspv)
               (cons 'ctx ctx)
               (cons 'world wrld)
               (cons 'clause-list clause-list)
               (cons 'processor processor)
               (cons 'keyword-alist keyword-alist)
               (if flg
                   (cons (cons 'stable-under-simplificationp
                               stable-under-simplificationp)
                         nil)
                 nil))
        nil ; trans-flg = nil because term is already translated
        t ; ev-flg = t because we have bound all the vars
        ctx state t)))
     (cond
      ((not (keyword-value-listp new-keyword-alist))
       (er soft ctx
           "An override-hint, ~x0, has produced an illegal value from ~
            keyword-alist ~x1.  That value, ~x2, is illegal because it is not ~
            a keyword-value-listp, i.e., an alternating list of keywords and ~
            values."
           (untranslate term nil wrld)
           keyword-alist
           new-keyword-alist))
      (t

; If an override-hint generates a hint with a custom keyword that is sensitive
; to stable-under-simplificationp, then that keyword will not have been
; expanded away at hint translation time.  We deal with it now.  The following
; example from Ian Johnson failed before invoking
; custom-keyword-hint-interpreter here.

; (set-state-ok t)
; (defun blah (val stable-under-simplificationp state)
;   (declare (ignore val stable-under-simplificationp))
;   (value '(:in-theory (enable car-cons))))
; (add-custom-keyword-hint :test
;                          (blah val stable-under-simplificationp state))
; (defun ovrride (keyword-alist state)
;   (let ((ret (append keyword-alist (list :test t))))
;     (prog2$
;      (cw "HINTS ~x0 ~%" ret)
;      (if keyword-alist
;          (value ret)
;        (value nil)))))
; (add-override-hints (list '(ovrride keyword-alist state)))
; (thm (equal (* 4 (car (cons x x))) (* x 4))
;      :hints (("Goal" :in-theory (disable car-cons))))

       (mv-let
        (erp new-keyword-alist state)
        (custom-keyword-hint-interpreter
         new-keyword-alist
         cl-id
         cl-id
         clause wrld stable-under-simplificationp
         hist pspv ctx state
         nil)
        (cond
         (erp
          (er soft ctx
              "An override-hint applied to ~@0 has generated an illegal ~
               custom keyword hint, as reported above."
              (tilde-@-clause-id-phrase cl-id)))
         ((eq (car new-keyword-alist)
              :computed-hints-replacement)
          (er soft ctx
              "An override-hint, ~x0, has produced an illegal value from ~
               keyword-alist ~x1.  That value, ~x2, is illegal because it ~
               begins with the keyword :COMPUTED-HINT-REPLACEMENT; see :DOC ~
               override-hints."
              (untranslate term nil wrld)
              keyword-alist
              new-keyword-alist))
         ((assoc-keyword :error new-keyword-alist)
          (translate-error-hint
           (cadr (assoc-keyword :error new-keyword-alist))
           (msg "an override hint applied to ~@0"
                (tilde-@-clause-id-phrase cl-id))
           wrld state))
         (t
          (value new-keyword-alist)))))))))

(defun apply-override-hints
  (override-hints cl-id clause hist pspv ctx wrld
                  stable-under-simplificationp clause-list processor
                  keyword-alist state)

; Apply the given override-hints to the given keyword-alist (for a hint) to
; obtain a resulting keyword alist.

  (cond
   ((endp override-hints)
    (value keyword-alist))
   (t
    (er-let*
     ((new-keyword-alist
       (apply-override-hint
        (car override-hints) cl-id clause hist pspv ctx wrld
        stable-under-simplificationp clause-list processor
        keyword-alist state)))
     (apply-override-hints
      (cdr override-hints) cl-id clause hist pspv ctx wrld
      stable-under-simplificationp clause-list processor
      new-keyword-alist state)))))

(defun eval-and-translate-hint-expression
  (tuple cl-id clause wrld stable-under-simplificationp hist pspv clause-list
         processor keyword-alist hint-type override-hints ctx state)

; Tuple is of the form (name-tree flg term), where term is a translated
; single-threaded error-triple producing term that mentions, at most, the
; variables ID, CLAUSE, CLAUSE-LIST, PROCESSOR, KEYWORD-ALIST, WORLD,
; STABLE-UNDER-SIMPLIFICATIONP, HIST, PSPV, CTX, and STATE; and flg is a flag
; indicating whether the variable STABLE-UNDER-SIMPLIFICATIONP occurs freely in
; term.  We eval term under the corresponding alist, obtaining a value val, and
; if val is non-erroneous and non-nil then we treat it as though it were a
; keyword-alist from an untranslated hint, i.e., (:key1 val1 ...), and
; translate it, using name-tree as the gensym name-tree for :bye hints.  We
; return the translated hint-settings or nil.

; The above description is inaccurate in three respects.  First, after the
; evaluation of term we restore proof related components of state.  Our
; intention is that the user have state so the computed hint can, say,
; translate terms and print error messages.  But we cannot prevent the user
; from abusing state and doing things like reading from files (which we can't
; undo) or changing the logical world with defun or defthm (which we can undo).
; So think of us as ignoring the state returned by the evaluation and reverting
; to the original one.

; Second, let's first remind ourselves that a computed hint gets to specify not
; just what the hint-settings is for this application but also gets to affect
; the hints that will be available later.  A computed hint can direct the
; system to (a) remove itself from the hints after the application, (b) leave
; itself in after the application, or (c) replace itself with a list of other
; hints.  This direction is provided by including the keyword
; :COMPUTED-HINT-REPLACEMENT and an associated value in the result, val, of the
; evaluation.

; The :COMPUTED-HINT-REPLACEMENT keyword and its value, chr, if provided, MUST
; BE THE FIRST two elements of val.

; The first paragraph is correct when val does not start with
; :COMPUTED-HINT-REPLACEMENT.  Otherwise, val is of the form
; (:COMPUTED-HINT-REPLACEMENT chr . keyword-alist) and this is what we do.  If
; keyword-alist is nil then we return (value nil).  Otherwise, we treat
; keyword-alist as an untranslated hint-settings and translate it.  We inspect
; chr to see whether it is (a) nil, (b) t, or (c) something else.  The first
; two mean the hint is to be (a) deleted or (b) preserved.  The last is
; understood as a list of terms to be be spliced into the hints in place of
; this one.  But these terms must be translated and so we do that.  Then we
; return (:COMPUTED-HINT-REPLACEMENT chr' . hint-settings), where chr' is the
; possibly translated chr and hint-settings' is the translated keyword-alist.
; It is left to our caller to interpret chr' and modify the hints
; appropriately.

; Finally the third inaccuracy of our initial description above is that it
; fails to account for override-hints.  We apply the given override-hints if
; the computed hint returns a keyword-value-alistp that is non-nil even after
; stripping off a (:COMPUTED-HINT-REPLACEMENT val) prefix.

  (let* ((name-tree (car tuple))
         (flg (cadr tuple))
         (term (caddr tuple))
         (custom-keyword-alist

; Keep this is sync with custom-keyword-hint-in-computed-hint-form.  This
; variable is set to nil if this is an undistinguished computed hint and is set
; to non-nil if it is a custom keyword hint in computed hint form.  The non-nil
; value is a hint keyword alist containing at least one custom keyword.

          (if (and (nvariablep term)
                   (not (fquotep term))
                   (eq (ffn-symb term) 'custom-keyword-hint-interpreter)
                   (quotep (fargn term 1))
                   (quotep (fargn term 2)))
              (cadr (fargn term 1))
            nil)))

; The use of flg below might save a few conses.  We do this only because we
; can.  The real reason we have have the flg component in the computed hint
; tuple has to do with optimizing find-applicable-hint-settings.

    (er-let*
     ((val0 (xtrans-eval
             term
             (list* (cons 'id cl-id)
                    (cons 'clause clause)
                    (cons 'clause-list clause-list)
                    (cons 'processor processor)
                    (cons 'keyword-alist keyword-alist)
                    (cons 'world wrld)
                    (cons 'hist hist)
                    (cons 'pspv pspv)
                    (cons 'ctx ctx)
                    (if flg
                        (cons (cons 'stable-under-simplificationp
                                    stable-under-simplificationp)
                              nil)
                      nil))
             nil ; trans-flg = nil because term is already translated
             t ; ev-flg = t because we have bound all the vars
             ctx state t)))
     (cond
      ((null val0)
       (value nil))
      (t
       (er-let*
        ((str (value (string-for-tilde-@-clause-id-phrase cl-id)))
         (chr-p

; This is a reasonable place to catch a non-keyword-alist result.  Before we
; had override-hints, we waited for the translate-hint call below.  But
; override-hints expect keyword-alists, so we do our checking earlier now.

          (cond ((keyword-value-listp val0)
                 (value (eq (car val0) :computed-hint-replacement)))
                (t
                 (er soft ctx
                     "A ~#0~[custom keyword~/computed~] hint for ~x1 has ~
                      produced a result that is not an alternating list of ~
                      keywords and values, (str :key1 val1 ... :keyn valn).  ~
                      That result, ~x2, is thus illegal."
                     (if custom-keyword-alist 0 1)
                     str
                     val0))))
         (chr
          (cond
           ((null chr-p) (value :irrelevant)) ; chr is not used
           (custom-keyword-alist
            (er soft
                (msg "a custom keyword hint for ~x0"
                     str)
                "The hint ~x0 produced a :COMPUTED-HINT-REPLACEMENT value as ~
                 part of its result.  It is not permitted for custom keyword ~
                 hints to produce such a value (only computed hints are ~
                 allowed to do that). The result produced was ~x1."
                (cons str
                      (cadr (fargn term 1)))
                val0))
           ((not (consp (cdr val0)))
            (er soft
                (msg
                 "a computed hint for ~x0:  The computed hint ~% ~q1 produced ~
                  the non-nil result~%~y2.  But this is an illegal value"
                 str
                 (untranslate term nil wrld)
                 val0)
                "The :COMPUTED-HINT-REPLACEMENT keyword must be followed by a ~
                 list whose first element is NIL, T, or a list of terms.  The ~
                 remaining elements are to be keyword/value pairs."))
           ((or (eq (cadr val0) nil) (eq (cadr val0) t))
            (value (cadr val0)))
           (t 
            (translate-hint-expressions
             (cons "Computed hint auto-generated for "
                   name-tree)
             (cadr val0)
             hint-type 'auto-generated-hint wrld state))))
         (val1 (value (if chr-p (cddr val0) val0))))
        (cond
         ((null val1)
          (value nil))
         (t
          (er-let*
           ((val (cond ((and (keyword-value-listp val1)
                             (assoc-keyword :ERROR val1))

; If the hint produced an :ERROR as one of the keys of its result, then rather
; than translate the whole hint we pick out the :ERROR msg and print it
; directly.

                        (translate-error-hint
                         (cadr (assoc-keyword :ERROR val1))
                         (msg "a ~#0~[custom keyword~/computed~] hint for ~x1"
                              (if custom-keyword-alist 0 1)
                              str)
                         wrld
                         state))
                       (t (apply-override-hints
                           override-hints cl-id clause hist pspv ctx wrld
                           stable-under-simplificationp clause-list processor
                           val1 state)))))
           (cond
            ((null val)
             (value nil))
            (t
             (er-let*
              ((temp

; Explanation of the call of translate-hint below: The val computed is supposed
; to be of the form (:key1 val1 ...) and we need to check that it really is and
; translate it into the internal form of a hint-settings.  We cons str onto the
; front of what we translate to create (str :key1 val1 ...) and then run it
; through the standard hint translator.  That string is used in the name
; generated by :by.  If no error occurs, we get back either
; (eval-and-translate-hint-expression ...)  or (cl-id . hint-settings).  The
; former is the translated form of a computed hint.  The latter contains the
; translated hint settings we seek.  We ignore the cl-id, which comes from the
; str we consed onto val.
              
; The msg below is the context of any error message generated by this
; translate-hint.  It will be printed followed by a colon.

                (translate-hint
                 name-tree
                 (cons str val)
                 hint-type
                 (msg
                  "a ~#0~[custom keyword~/computed~] hint for ~x1:  The ~
                   ~#0~[custom keyword~/computed~] hint ~%~#0~[~x2 ~
                   ~/~q2~]produced the non-nil result~%~y3.~@4Regarding this ~
                   value"
                  (if custom-keyword-alist 0 1)
                  str
                  (if custom-keyword-alist
                      custom-keyword-alist
                    (untranslate term nil wrld))
                  val0
                  (cond ((equal val val1) "")
                        (t (msg "In turn, override-hints transformed these ~
                                 hint-settings~#0~[ (without the leading ~
                                 :COMPUTED-HINTS-REPLACEMENT value)~/~] into ~
                                 ~x1.  "
                                (if (equal val0 val1) 1 0)
                                val))))
                 wrld state)))
              (cond
               ((eq (car temp) 'eval-and-translate-hint-expression)
                (eval-and-translate-hint-expression
                 (cdr temp)
                 cl-id clause wrld stable-under-simplificationp hist pspv
                 clause-list processor keyword-alist hint-type
                 nil ; we have already dealt with the override-hints
                 ctx state))
               (chr-p (value (list* :computed-hint-replacement
                                    chr
                                    (cdr temp))))
               (t (value (cdr temp))))))))))))))))

(deflabel goal-spec
  :doc
  ":Doc-Section Miscellaneous

  to indicate where a hint is to be used~/
  ~bv[]
  Examples:
  \"Goal\"
  \"goal\"
  \"Subgoal *1/3''\"
  \"subgoal *1/3''\"
  \"[2]Subgoal *1/3''\"
  ~ev[]~/

  When ~il[hints] are given to the theorem prover, a goal-spec is provided
  to specify the goal to which the ~il[hints] are to be applied.  The ~il[hints]
  provided are carried along innocuously until the named goal arises.
  When it arises, the ~il[hints] are ``activated'' for that goal and its
  descendents.

  A legal goal specification may be extracted from the theorem
  prover's output.  Certain lines clearly label formulas, as in
  ~bv[]
  Subgoal *1/3.2'
  (IMPLIES ... ...)
  ~ev[]
  and these lines all give rise to goal specifications.  In general,
  these lines all start either with ``Goal'' or ``Subgoal'' or else
  with those words preceded by a number in square brackets, as in
  ~bv[]
  [1]Subgoal *1/3.2'
  (IMPLIES ... ...).
  ~ev[]
  A goal specification may be obtained by deleting any surrounding
  whitespace from such a line and embedding the text in string
  quotation marks.  Thus
  ~bv[]
  \"[1]Subgoal *1/3.2'\"
  ~ev[]
  is the goal specifier for the goal above.

  As noted, a hint is applied to a goal when the hint's goal
  specification matches the name ACL2 assigns to the goal.  The
  matching algorithm is case-insensitive.  Thus, alternative goal
  specifications for the goal above are ~c[\"[1~]subgoal *1/3.2'\"] and
  ~c[\"[1~]SUBGOAL *1/3.2'\"].  The matching algorithm does not tolerate
  non-case discrepancies.  Thus, ~c[\"[1~]Subgoal*1/3.2'\"] and
  ~c[\" [1~]Subgoal *1/3.2'\"] are unacceptable.

  Sometimes a formula is given two names, e.g.,
  ~bv[]
  Subgoal *1/14.2'
  (IMPLIES ... 
           ...)
  Name the formula above *1.1.
  ~ev[]
  It is the first name (the one that starts with ``Goal'' or
  ``Subgoal'') and not the second which constitutes a legal goal-spec.
  Roughly speaking, when the system prints the line containing the
  goal specification, it activates any ~il[hints] that are attached to that
  goal-spec.  Consider the example above.  Suppose ~c[Subgoal *1/14.2']
  could be proved by using a certain lemma instance.  Then the
  appropriate entry in the ~il[hints] would be:
  ~bv[]
  (\"Subgoal *1/14.2'\" :use ...)
  ~ev[]
  This might surprise you because the system appears to do nothing
  to ~c[*1/14.2'] besides push it for a subsequent induction.  But
  actually between the time the system printed the goal-spec line and
  the time it decides to push the goal, you can think of the system as
  trying everything it has.  So a ~c[use] hint activated when
  ~c[Subgoal *1/14.2'] arises is just what you want.

  But what if you want to give an ~c[:induct] hint?  By the time induction
  is tried, the formula has been given the name ~c[*1.1].  Well, this is
  one you just have to remember:
  ~bv[]
  (\"Subgoal *1/14.2'\" :induct ...).
  ~ev[]
  When the above hint is activated the ~c[:induct] directive
  short-circuits the rest of the processing and sends immediately the
  formula into the pool of goals to prove by induction.  The induct
  hint is attached to the formula in the pool and when the time comes
  to turn our attention to that goal, the induct advice is
  followed.~/")

(deflabel hints-and-the-waterfall
  :doc
  ":Doc-Section Miscellaneous

  how ~il[hints] fit into the ACL2 proof waterfall~/

  Below we describe the flow of an ACL2 proof attempt, with special attention
  to how ~il[hints] are applied during a proof.  For most ACL2 users, only one
  point is important to take away from this ~il[documentation] topic: you may
  specify hints during a proof (~pl[hints]; perhaps also ~pl[computed-hints]
  and ~pl[default-hints]), and they can be expected to behave intuitively.
  ~l[the-method] for a summary of how to interact with the ACL2 prover, and
  ~pl[hints] for an introduction to ACL2 hints and detailed ~il[documentation]
  for specific hint types.

  The remainder of this topic serves as a references in case one needs a deeper
  understanding of the workings of ACL2's handling of hints.  Also, for
  examples of the sophisticated use of hints, primarily for experts, see
  distributed book ~c[books/hints/basic-tests.lisp].

  First, we describe the ACL2 ``waterfall'', which handles each goal either by
  replacing it with a list (possibly empty) of child goals, or else by putting
  the goal into a ``pool'' for later proof by induction.  Then, we describe how
  hints are handled by the waterfall.

  ~st[The Waterfall.]

  Each goal considered by the ACL2 prover passes through a series of proof
  processes, called the ``waterfall processes'', as stored in the constant
  ~c[*preprocess-clause-ledge*].  The top process applies top-level hints,
  including ~c[:use] hints; the next is a lightweight ``preprocess'' simplifier
  for ``simple'' rules (~pl[simple]); the next is the main ACL2 simplifier; and
  finally ACL2 attempts (in this order) destructor elimination, fertilization
  (heuristic use of equalities), generalization, and elimination of
  irrelevance.  Each process may ``hit'', creating zero or more child goals
  that are each then handled at the top of the waterfall; or it may ``miss'',
  in which case the next process in the above sequence is considered.  If all
  processes miss, then a ``push'' process defers the goal until it is later
  considered for proof by induction.  When all goals have been thus handled,
  the goal most recently pushed for proof by induction is considered, and the
  process repeats.

  We next describe the two additional ways in which control can be returned to
  the top of the waterfall.

  When the simplification process is attempted unsuccessfully for a goal, the
  goal is deemed to have ``settled down''.  In this case, and if no ancestor of
  the goal has settled down, then the ``settled-down'' process is deemed to
  have ``hit'' on the goal, the effect being that the goal makes a new pass
  through all the waterfall processes.  (Other processes can then notice that
  settling down has occurred and modify their heuristics accordingly.)  For
  example, if ~c[\"Goal\"] simplifies to ~c[\"Subgoal 2\"] (among others), and
  ~c[\"Subgoal 2\"] simplifies to ~c[\"Subgoal 2.3\"] (among others), which in
  turn is not further simplified, then the the ``settled-down'' process hits on
  ~c[\"Subgoal 2.3\"] but not on any of its children, their children, and so
  on.

  When simplification has missed (and thus the goal has settled down), the next
  proof process is normally destructor elimination.  However, if a computed
  hint is suitable (in a sense described below; also ~pl[computed-hints],
  especially the discussion of ~c[stable-under-simplificationp]), then that
  hint is selected as control is returned to the top of the waterfall.  A
  subtlety is that in this case, if the most recent hit had been from settling
  down, then the prover ``changes its mind'' and considers that the goal has
  not yet settled down after all as it continues through the waterfall.

  Each time a goal is considered at the top of the waterfall, then before
  passing through the proof processes as described above, ACL2 searches for a
  relevant hint to select unless it has already been provided a hint in the
  ``~c[stable-under-simplificationp]'' case mentioned above.  We turn now to a
  more thorough discussion of how hints are selected and applied.~/

  ~st[The handling of hints.]

  In the discussion below we will ignore forcing rounds, as each forcing round
  is simply treated as a new proof attempt that uses the list of hints provided
  at the start of the proof.

  When the theorem prover is called by ~ilc[thm] or ~il[events] such as
  ~ilc[defthm], ~ilc[defun], and ~ilc[verify-guards], it gathers up the hints
  that have been supplied, often provided as a ~c[:]~ilc[hints] argument, but
  for example using a ~c[:guard-hints] argument for ~il[guard] verification
  proofs.  (ACL2(r) users (~pl[real]) may also employ ~c[:std-hints].)  It then
  appends these to the front of the list of default hints (~pl[default-hints]).
  The resulting list becomes the initial value of the list of ``pending
  hints'', one of two critical lists maintained by the theorem prover to manage
  hints.  The other critical list is a list of ``hint settings''; the two lists
  are maintained as follows.

  When a goal is first considered, a hint is selected from the list of pending
  hints if any is found to apply, as described below.  If a hint is selected,
  then it takes effect and is removed from the pending hints.  Except: if the
  selected hint is a computed hint with value ~c[t] specified for
  ~c[:computed-hint-replacement], then it is not removed; and if that value is
  a list of hints, then that list is appended to the front of the list of
  pending hints after the selected hint is removed (also ~pl[computed-hints]).
  The selected hint is also used to update the hint settings, as described
  below.

  The list of hint settings associates hint keywords with values.  It is passed
  from the current goal to its children (and hence the children's children, and
  so on), though modified by hints selected from pending hints, as described
  below.  This list is consulted when a goal is pushed for later proof by
  induction, at which time the hint settings are stored so that when the
  induction proof begins, it begins with those hint settings.  Note that the
  list of hint settings is not re-applied to descendents of a goal; a hint is
  applied only when it is selected.  For example, if the hint selected for
  ~c[\"Subgoal 3\"] includes ~c[:in-theory (enable foo)], then the hint
  settings are correspondingly updated when processing ~c[\"Subgoal 3\"], and
  they persist at subgoals such as ~c[\"Subgoal 3.2\"] and
  ~c[\"Subgoal 3.2.1\"] (unless overriden by hints on those goals); but the
  theory specifying ~c[foo] is not re-installed at every such subgoal.

  When a hint is selected, the list of hint-settings is updated so that for
  each keyword ~c[:kwd] and associated value ~c[val] from the hint, ~c[:kwd] is
  associated with ~c[val] in the hint-settings, discarding any previous
  association of ~c[:kwd] with a value in the hint-settings.  Except, certain
  ``top-level'' hints are never saved in the hint-settings: ~c[:use],
  ~c[:cases], ~c[:by], ~c[:bdd], ~c[:or], and ~c[:clause-processor].

  For example, suppose that we specify the following hints, with no default
  hints.
  ~bv[]
  ((\"Goal\" :expand ((bar x y)))
   (\"Subgoal 3\" :in-theory (enable foo)))
  ~ev[]
  These hints then become the initial list of pending hints.  When the proof
  attempt begins, the prover encounters the top-level goal (~c[\"Goal\"]) and
  pulls the ~c[\"Goal\"] hint from the pending hints, so that the list of hint
  settings contains a value only for keyword ~c[:expand].  This hint setting
  will remain for all children of the top-level goal as well, and their
  children, and so on, and will be inherited by induction ~-[] in other words,
  it will remain throughout the entire proof.  Now consider what happens when
  the proof reaches ~c[\"Subgoal 3\"].  At this point there is only one pending
  hint, which is in fact attached to that subgoal.  Therefore, this hint is
  pulled from the pending hints (leaving that list empty), and the hint
  settings are extended by associating the ~c[:in-theory] keyword with the
  theory represented by ~c[(enable foo)].  That theory is immediately installed
  until the prover finishes addressing ~c[\"Subgoal 3\"], its children, their
  children, and so on; and until that completion is reached, the ~c[:in-theory]
  keyword remains associated with the ~c[(enable foo)] in the hint settings,
  although of course there is no re-installation of the theory at any ensuing
  child goal.  When finally ~c[\"Subgoal 3\"] and its descendents have been
  completed and the prover is about to consider ~c[\"Subgoal 2\"], the
  ~c[:in-theory] association is removed from the hint settings and the global
  theory is re-installed.  However, the list of pending hints remains empty.

  It remains to describe how hints are chosen for a goal.  When a goal is first
  considered (hence at the top of the waterfall), the list of pending hints is
  scanned, in order, until one of the hints is suitable for the goal.  An
  explicit hint ~c[(goal-name :kwd1 val1 ... :kwdn valn)] is suitable if
  ~c[goal-name] is the name of the current goal and there is at least one
  keyword.  A computed hint is suitable if it evaluates to a non-~c[nil]
  value.  As indicated earlier in this documentation topic, an exception occurs
  when a computed hint is selected after simplification fails (the
  ``~c[stable-under-simplificationp]'' case): in that case, the goal returns to
  the top of the waterfall with that hint is the selected hint, and no
  additional search for a hint to select is made at that time.

  The following slightly tricky example illustrates handling of hints.
  ~bv[]
  ACL2 !>(set-default-hints '((\"Goal\" :do-not '(preprocess))))
   ((\"Goal\" :DO-NOT '(PREPROCESS)))
  ACL2 !>(thm (equal (append (append x y) z) (append x y z))
              :hints ((\"Goal\" :in-theory (disable car-cons))))

  ACL2 Warning [Hints] in ( THM ...):  The goal-spec \"Goal\" is explicitly
  associated with more than one hint.  All but the first of these hints
  may be ignored.  If you intended to give all of these hints, combine
  them into a single hint of the form (\"Goal\" :kwd1 val1 :kwd2 val2 ...).
  See :DOC hints-and-the-waterfall.

  [Note:  A hint was supplied for our processing of the goal above. 
  Thanks!]

  [Note:  A hint was supplied for our processing of the goal above. 
  Thanks!]

  Name the formula above *1.
  ~ev[]

  The warning above is printed because ~c[\"Goal\"] is associated with two
  hints: one given by the ~ilc[set-default-hints] call and one supplied by the
  ~c[:]~ilc[hints] keyword of the ~ilc[thm] form.  The ~c[:in-theory] hint is
  selected because user-supplied hints are ahead of default hints in the list
  of hints to consider; we then get the first ``Note'' above.  The goal
  progresses through the waterfall without any proof process applying to the
  goal; in particular, it cannot be further simplified.  After the
  simplification process, a ``settled-down'' process applies, as discussed
  above, immediately causing another trip through the waterfall.  At that point
  the ~c[:in-theory] hint had previously been removed when it was applied,
  leaving the default (~c[:do-not]) hint as the only applicable hint.  That
  hint is indeed applied, resulting in the second ``Note'' above.

  Again, more examples may be found in the distributed book
  ~c[books/hints/basic-tests.lisp].  A particularly tricky but informative
  example in that book is the one related to ~c[nonlinearp-default-hint].

  Also ~pl[override-hints] for an advanced feature that allows modification of
  the hint selected for a goal.")

(deflabel hints
  :doc
  ":Doc-Section Miscellaneous

  advice to the theorem proving process~/
  ~bv[]
  Examples:
  The following :hints value is nonsensical.  Nevertheless, it
  illustrates all of the available hint keywords except the
  ``custom keywords'' (~pl[custom-keyword-hints]) definable
  by the user.

  :hints ((\"Goal\"
           :do-not-induct t
           :do-not '(generalize fertilize)
           :expand ((assoc x a) 
                    :lambdas
                    (:free (y) (:with member (member y z))))
           :restrict ((<-trans ((x x) (y (foo x)))))
           :hands-off (length binary-append)
           :in-theory (set-difference-theories
                        (current-theory :here)
                        '(assoc))
           :induct (and (nth n a) (nth n b))
           :use ((:instance assoc-of-append
                            (x a) (y b) (z c))
                 (:functional-instance
                   (:instance p-f (x a) (y b))
                   (p consp)
                   (f assoc)))
           :bdd (:vars (c a0 b0 a1 b1) :prove nil :bdd-constructors (cons))
           :clause-processor (:function cl-proc :hint (my-hint clause))
           :instructions (:x :prove)
           :cases ((true-listp a) (consp a))
           :by (:instance rev-rev (x (cdr z)))
           :nonlinearp t
           :backchain-limit-rw 3
           :reorder (4 7 2)
           :case-split-limitations (20 10)
           :no-op t
           :no-thanks t
           :error (\"Bad value ~~x0.\" 123)
           :or (hint-kwd-alist-1 ... hint-kwd-alist-k)
           :backtrack (my-computed-hint clause processor clause-list)))
  ~ev[]
  A very common hint is the ~c[:use] hint, which in general takes as its
  value a list of ``lemma instances'' (~pl[lemma-instance]) but
  which allows a single lemma name as a special case:
  ~bv[]
  :hints ((\"[1]Subgoal *1/1.2'\" :use lemma23))
  ~ev[]

  ACL2 also provides ``custom keyword'' hints (~pl[custom-keyword-hints])
  and even more general ``computed hints'' for the advanced user
  (~pl[computed-hints]).

  Only the first hint applicable to a goal, as specified in the user-supplied
  list of ~c[:hints] followed by the default hints (~pl[default-hints-table]),
  will be applied to that goal.  For an advanced exception,
  ~pl[override-hints].  For a detailed discussion of how hints fit
  into the ACL2 waterfall, ~pl[hints-and-the-waterfall].  For examples of the
  sophisticated use of hints, primarily for experts, see distributed book
  ~c[books/hints/basic-tests.lisp].~/

  Background: ~c[Hints] are allowed in all ~il[events] that use the theorem
  prover.  During ~ilc[defun] ~il[events] there are two different uses of the
  theorem prover: one to prove termination and another to verify the
  ~il[guard]s.  To pass a hint to the theorem prover during termination proofs,
  use the ~c[:hints] keyword in the ~ilc[defun]'s ~ilc[xargs] declaration.  To
  pass a hint to the theorem prover during the ~il[guard] verification portion
  of admitting a ~ilc[defun], use the ~c[:guard-hints] keyword in the
  ~ilc[defun]'s ~ilc[xargs] declaration.  The ~ilc[verify-guards] event and the
  ~ilc[defthm] event also use the theorem prover.  To pass hints to them, use
  the ~c[:hints] keyword argument to the event.
  ~bv[]
  General Form of Common :hints:
    ((goal-spec :key1 val1 ... :keyn valn)
     ...
     (goal-spec :key1 val1 ... :keyn valn))
  ~ev[]
  where ~ilc[goal-spec] is as described elsewhere (~pl[goal-spec]) and the keys
  and their respective values are shown below with their interpretations.  (We
  also provide ``computed hints'' but discuss them separately;
  ~pl[computed-hints].)

  ~c[:DO-NOT-INDUCT]~nl[]
  ~c[Value] is ~c[t], ~c[:otf-flg-override], ~c[:otf], ~c[name] or ~c[nil],
  indicating whether ~il[induction] is permitted under the specified goal.  If
  ~c[value] is ~c[t] or ~c[:otf-flg-override], then the attempt to apply
  ~il[induction] to the indicated goal or any subgoal under the indicated goal
  will immediately cause the theorem prover to report ~il[failure], except that
  if ~c[:otf-flg] is specified (~pl[otf-flg]) and ~c[value] is ~c[t], then the
  proof will continue until the time at which the goal pushed for induction is
  finally considered.  The latter behavior is also what occurs if ~c[value] is
  ~c[:otf].  Thus, any non-~c[nil] value requires the indicated goal to be
  proved entirely by simplification, destructor elimination, and the other
  ``waterfall'' processes.  ~il[Induction] to prove the indicated goal (or any
  subgoal) is not permitted.  See however the ~c[:induct] hint below.  If
  ~c[value] is a symbol other than ~c[t], ~c[:otf-flg-override], ~c[:otf] or
  ~c[nil], the theorem prover will give a ``bye'' to any subgoal that would
  otherwise be attacked with induction.  This will cause the theorem prover to
  fail eventually but will collect the necessary subgoals.  If ~c[value] is
  ~c[nil], this hint means ~il[induction] is permitted.  Since that is the
  default, there is no reason to use the value ~c[nil].  Note that a
  ~c[:do-not-induct] hint is ignored for any goal on which an ~c[:induct] hint
  is supplied.  For an advanced example of the use of value ~c[:otf] with
  ~il[override-hints], see distributed book books/hints/basic-tests.lisp.

  ~c[:DO-NOT]~nl[]
  ~c[Value] is a term having at most the single free variable ~ilc[world], which
  when evaluated (with ~ilc[world] bound to the current ACL2 logical ~il[world])
  produces a list of symbols that is a subset of the list
  ~bv[]
  (preprocess ;propositional logic, simple rules
   simplify   ;as above plus rewriting, linear arithmetic
   eliminate-destructors
   fertilize  ;use of equalities
   generalize
   eliminate-irrelevance).
  ~ev[]
  The hint indicates that the ``processes'' named should not be used
  at or below the goal in question.  Thus, to prevent generalization
  and fertilization, say, include the hint
  ~bv[]
  :do-not '(generalize fertilize)
  ~ev[]
  If ~c[value] is a single symbol, as in
  ~bv[]
  :do-not generalize,
  ~ev[]
  it is taken to be ~c['(value)].

  ~c[:EXPAND]~nl[]
  ~c[Value] is a true list of terms, each of which is of one of the forms
  ~c[(let ((v1 t1)...) b)] or ~c[(fn t1 ... tn)], where ~c[fn] is a defined
  function symbol with formals ~c[v1, ..., vn,] and ~c[body] ~c[b].  Such a
  term is said to be ``expandable:'' it can be replaced by the result of
  substituting the ~c[ti]'s for the ~c[vi]'s in ~c[b].  The terms listed in the
  ~c[:expand] hint are expanded when they are encountered by the simplifier
  while working on the specified goal or any of its subgoals.  We permit
  ~c[value] to be a single such term instead of a singleton list.
  ~st[Remarks]: (1) Allowed are ``terms'' of the form
  ~c[(:free (var1 var2 ...  varn) pattern)] where the indicated variables are
  distinct and ~c[pattern] is a term.  Such ``terms'' indicate that we consider
  the indicated variables to be instantiatable, in the following sense:
  whenever the simplifier encounters a term that can be obtained from
  ~c[pattern] by instantiating the variables ~c[(var1 var2 ...  varn)], then it
  expands that term.  (2) Also allowed are ``terms'' of the form
  ~c[(:with name term)], where ~c[name] is a function symbol, a macro name that
  denotes a function symbol (~pl[macro-aliases-table]), or a ~il[rune].  The
  corresponding rule of class ~c[:rewrite], which is often a ~il[definition]
  rule but need not be, is then used in place of the current body for the
  function symbol of ~c[term]; ~pl[show-bodies] and ~pl[set-body].  If the rule
  is of the form ~c[(implies hyp (equiv lhs rhs))], then after matching ~c[lhs]
  to the current term in a context that is maintaining equivalence relation
  ~c[equiv], ACL2 will replace the current term with
  ~c[(if hyp rhs (hide term))], or just ~c[rhs] if the rule is just
  ~c[(equal lhs rhs)].  (3) A combination of both ~c[:free] and ~c[:with], as
  described above, is legal.  (4) The term ~c[:LAMBDAS] is treated specially.
  It denotes the list of all lambda applications (i.e., ~ilc[let] expressions)
  encountered during the proof.  Conceptually, this use of ~c[:LAMBDAS] tells
  ACL2 to treat lambda applications as a notation for substitutions, rather
  than as function calls whose opening is subject to the ACL2 rewriter's
  heuristics (specifically, not allowing lambda applications to open when they
  introduce ``too many'' if terms).

  ~c[:HANDS-OFF]~nl[]
  ~c[Value] is a true list of function symbols or lambda expressions,
  indicating that under the specified goal applications of these
  functions are not to be rewritten.  Note however that subterms will still be
  rewritten; ~pl[hide] if that is not what is intended.  (The distributed book
  ~c[books/clause-processors/autohide.lisp] from Jared Davis may also be
  helpful in that case.) ~c[Value] may also be a single function symbol or
  lambda expression instead of a list.

  ~c[:]~ilc[IN-THEORY]~nl[]
  ~c[Value] is a ``theory expression,'' i.e., a term having at most the
  single free variable ~ilc[world] which when evaluated (with ~ilc[world] bound to
  the current ACL2 logical world (~pl[world])) will produce a
  theory to use as the current theory for the goal specified.
  ~l[theories].

  Note that an ~c[:]~ilc[IN-THEORY] hint will always be evaluated relative to
  the current ACL2 logical ~il[world], not relative to the theory of a previous
  goal.  Consider the following example.
  ~bv[]
  (defthm prop
    (p (f (g x)))
    :hints ((\"Goal\"      :in-theory (disable f))
            (\"Subgoal 3\" :in-theory (enable  g))))
  ~ev[]
  Consider in particular the theory in effect at ~c[Subgoal 3].  This
  call of the ~ilc[enable] macro enables ~c[g] relative to the
  ~ilc[current-theory] of the current logical ~il[world], ~em[not] relative to
  the theory produced by the hint at ~c[Goal].  Thus, the ~ilc[disable] of
  ~c[f] on behalf of the hint at ~c[Goal] will be lost at ~c[Subgoal 3], and
  ~c[f] will be enabled at ~c[Subgoal 3] if was enabled globally when ~c[prop]
  was submitted.

  ~c[:INDUCT]~nl[]
  ~c[Value] is either ~c[t] or a term containing at least one recursively
  defined function symbol; if ~c[t], this hint indicates that the system
  should proceed to apply its induction heuristic to the specified
  goal produced (without trying simplification, etc.); if ~c[value] is
  a term other than ~c[t], then not only should the system apply
  induction immediately, but it should analyze ~c[value] rather than
  the goal to generate its ~il[induction] scheme.  Merging and the
  other ~il[induction] heuristics are applied.  Thus, if ~c[value]
  contains several mergeable ~il[induction]s, the ``best'' will be
  created and chosen.  E.g., the ~c[:induct] hint
  ~bv[]
   (and (nth i a) (nth j a))
  ~ev[]
  suggests simultaneous ~il[induction] on ~c[i], ~c[j], and ~c[a].

  If both an ~c[:induct] and a ~c[:do-not-induct] hint are supplied for a
  given goal then the indicated ~il[induction] is applied to the goal and
  the ~c[:do-not-induct] hint is inherited by all subgoals generated.

  ~c[:USE]~nl[]
  ~c[Value] is a ~il[lemma-instance] or a true list of ~il[lemma-instance]s,
  indicating that the propositions denoted by the instances be added
  as hypotheses to the specified goal.  ~l[lemma-instance].  Note
  that ~c[:use] makes the given instances available as ordinary hypotheses
  of the formula to be proved.  The ~c[:instance] form of a ~il[lemma-instance]
  permits you to instantiate the free variables of previously proved
  theorems any way you wish; but it is up to you to provide the
  appropriate instantiations because once the instances are added as
  hypotheses their variables are no longer instantiable.  These new
  hypotheses participate fully in all subsequent rewriting, etc.  If
  the goal in question is in fact an instance of a previously proved
  theorem, you may wish to use ~c[:by] below.  Note that ~il[theories] may be
  helpful when employing ~c[:use] hints; ~pl[minimal-theory].

  Note that if the value is the name of a function symbol introduced by
  ~ilc[defun], then the ``normalized'' body of that definition is used, for
  which ACL2 has propagated ~c[IF] tests upward.  This behavior differs from
  that provided by a ~c[:by] hint, where the original body of the definition is
  used.

  ~c[:]~il[BDD]~nl[]
  This hint indicates that ordered binary decision diagrams (BDDs)
  with rewriting are to be used to prove or simplify the goal.
  ~l[bdd] for an introduction to the ACL2 BDD algorithm.

  ~c[Value] is a list of even length, such that every other element,
  starting with the first, is one of the keywords ~c[:vars],
  ~c[:bdd-constructors], ~c[:prove], or ~c[:literal].  Each keyword that
  is supplied should be followed by a value of the appropriate form,
  as shown below; for others, a default is used.  Although ~c[:vars]
  must always be supplied, we expect that most users will be content
  with the defaults used for the other values.

  ~c[:vars] ~-[] A list of ACL2 variables, which are to be treated as
  Boolean variables.  The prover must be able to check, using trivial
  reasoning (~pl[type-set]), that each of these variables is
  Boolean in the context of the current goal.  Note that the prover
  will use very simple heuristics to order any variables that do not
  occur in ~c[:vars] (so that they are ``greater than'' the variables
  that do occur in ~c[:vars]), and these heuristics are often far from
  optimal.  In addition, any variables not listed may fail to be
  assumed Boolean by the prover, which is likely to seriously impede
  the effectiveness of ACL2's BDD algorithm.  Thus, users are
  encouraged ~em[not] to rely on the default order, but to supply a
  list of variables instead.  Finally, it is allowed to use a value of
  ~c[t] for ~c[vars].  This means the same as a ~c[nil] value, except
  that the BDD algorithm is directed to fail unless it can guarantee
  that all variables in the input term are known to be Boolean (in a
  sense discussed elsewhere; ~pl[bdd-algorithm]).

  ~c[:literal] ~-[] An indication of which part of the current goal
  should receive BDD processing.  Possible values are:
  ~bv[]
    :all     treat entire goal as a single literal (the default)
    :conc    process the conclusion
    n        process the hypothesis with index n (1, 2, ...)
  ~ev[]

  ~c[:bdd-constructors] ~-[] When supplied, this value should be a
  list of function symbols in the current ACL2 ~il[world]; it is
  ~c[(cons)] by default, unless ~c[:bdd-constructors] has a value in
  the ~ilc[acl2-defaults-table] by default, in which case that value is
  the default.  We expect that most users will be content with the
  default.  ~l[bdd-algorithm] for information about how this
  value is used.

  ~c[:prove] ~-[] When supplied, this value should be ~c[t] or ~c[nil]; it
  is ~c[t] by default.  When the goal is not proved and this value is
  ~c[t], the entire proof will abort.  Use the value ~c[nil] if you are
  happy to the proof to go on with the simplified term.

  ~c[:CLAUSE-PROCESSOR]

  ~c[Value] specifies the application of a user-defined simplifier to the
  current goal.  ~l[clause-processor], which provides necessary background and
  hint syntax.  Also ~pl[define-trusted-clause-processor] for a discussion of
  ``trusted clause-processors'':  goal-level simplifiers that may be external
  to ACL2 and do not need to be proved correct in ACL2.

  You can see all current ~c[:clause-processor] rules by issuing the command
  ~c[(print-clause-processor-rules)], and you can see the names of all trusted
  clause-processors by issuing the command
  ~c[(table trusted-clause-processor-table)].

  ~c[:INSTRUCTIONS]

  ~c[Value] is a list of ~il[proof-checker] instructions; ~pl[instructions].
  Unlike other hint keywords described here, this one is actually a custom
  keyword hint (~pl[custom-keyword-hints]) that generates a suitable
  ~c[:]~ilc[clause-processor] hint.

  ~c[:CASES]~nl[]
  ~c[Value] is a non-empty list of terms.  For each term in the list, a
  new goal is created from the current goal by assuming that term; and
  also, in essence, one additional new goal is created by assuming all
  the terms in the list false.  We say ``in essence'' because if the
  disjunction of the terms supplied is a tautology, then that final
  goal will be a tautology and hence will in fact never actually be
  created.

  ~c[:BY]~nl[]
  ~c[Value] is a ~il[lemma-instance], ~c[nil], or a new event name. If the
  value is a ~il[lemma-instance] (~pl[lemma-instance]), then it indicates that
  the goal (when viewed as a clause) is either equal to the proposition denoted
  by the instance, or is subsumed by that proposition when both are viewed as
  clauses.  To view a formula as a clause, union together the negations of the
  hypotheses and add the conclusion.  For example,
  ~bv[]
  (IMPLIES (AND (h1 t1) (h2 t2)) (c t1))
  ~ev[]
  may be viewed as the clause
  ~bv[]
  {~~(h1 t1) ~~(h2 t2) (c t1)}.
  ~ev[]
  Clause ~c[c1] is ``subsumed'' by clause ~c[c2] iff some instance of ~c[c2] is a
  subset of ~c[c1].  For example, the clause above is subsumed by
  ~c[{~~(h1 x) (c x)}], which when viewed as a formula is
  ~c[(implies (h1 x) (c x))].

  Note that if the value is the name of a function symbol introduced by
  ~ilc[defun], then the original form of the body of that definition is used.
  This behavior differs from that provided by a ~c[:use] hint, where the
  so-called ``normalized'' body, for which ACL2 has propagated ~c[IF] tests
  upward.

  If the value is ~c[nil] or a new name, the prover does not even
  attempt to prove the goal to which this hint is attached.  Instead
  the goal is given a ``bye'', i.e., it is skipped and the proof
  attempt continues as though the goal had been proved.  If the prover
  terminates without error then it reports that the proof would have
  succeeded had the indicated goals been proved and it prints an
  appropriate ~il[defthm] form to define each of the ~c[:by] names.  The
  ``name'' ~c[nil] means ``make up a name.''  Here is an example (admittedly
  contrived for illustration purposes).
  ~bv[]
  ACL2 !>(thm (equal (append (append x y) z)
                     (append x y z))
              :hints ((\"Subgoal *1/2'\" :by nil)))

  Name the formula above *1.

  [[... output omitted here ...]]

  [Note:  A hint was supplied for our processing of the goal below. 
  Thanks!]

  Subgoal *1/2'
  (IMPLIES (AND (CONSP X)
                (EQUAL (APPEND (APPEND (CDR X) Y) Z)
                       (APPEND (CDR X) Y Z)))
           (EQUAL (APPEND (APPEND X Y) Z)
                  (APPEND X Y Z))).

  But we have been asked to pretend that this goal is subsumed by the
  yet-to-be-proved |THM Subgoal *1/2'|.

  Subgoal *1/1
  [[... proof goes on; further output omitted here ...]]
  ~ev[]

  The system does not attempt to check the uniqueness of the ~c[:by] names
  (supplied or made up), since by the time those goals are proved the
  namespace will be cluttered still further.  Therefore, the final
  list of ``appropriate'' ~ilc[defthm] forms may be impossible to admit
  without some renaming by the user.  If you must invent new names,
  remember to substitute the new ones for the old ones in the ~c[:by]
  hints themselves.

  ~c[:RESTRICT]~nl[]
  Warning: This is a sophisticated hint, suggested by Bishop Brock, that is
  intended for advanced users.  In particular, ~c[:restrict] hints are ignored
  by the preprocessor, so you might find it useful to give the hint
  ~c[:do-not '(preprocess)] when using any ~c[:restrict] hints, at least if the
  rules in question are abbreviations (~pl[simple]).

  ~c[Value] is an association list.  Its members are of the form
  ~c[(x subst1 subst2 ...)], where: ~c[x] is either (1) a ~il[rune] whose
  ~ilc[car] is ~c[:]~ilc[rewrite] or ~c[:]~ilc[definition] or (2) an event name
  corresponding to one or more such ~il[rune]s; and ~c[(subst1 subst2 ...)] is
  a non-empty list of substitutions, i.e., of association lists pairing
  variables with terms.  First consider the case that ~c[x] is a
  ~c[:]~ilc[rewrite] or ~c[:]~ilc[definition] ~il[rune].  Recall that without
  this hint, the rule named ~c[x] is used by matching its left-hand side (call
  it ~c[lhs]) against the term currently being considered by the rewriter, that
  is, by attempting to find a substitution ~c[s] such that the instantiation of
  ~c[lhs] using ~c[s] is equal to that term.  If however the ~c[:restrict] hint
  contains ~c[(x subst1 subst2 ...)], then this behavior will be modified by
  restricting ~c[s] so that it must extend ~c[subst1]; and if there is no such
  ~c[s], then ~c[s] is restricted so that it must extend ~c[subst2]; and so on,
  until the list of substitutions is exhausted.  If no such ~c[s] is found,
  then the rewrite or definition rule named ~c[x] is not applied to that term.
  Finally, if ~c[x] is an event name corresponding to one or more
  ~c[:]~ilc[rewrite] or ~c[:]~ilc[definition] ~il[rune]s (that is, ~c[x] is the
  ``base symbol'' of such ~il[rune]s; ~pl[rune]), say ~il[rune]s ~c[r1],
  ... ~c[rn], then the meaning is the same except that
  ~c[(x subst1 subst2 ...)] is replaced by ~c[(ri subst1 subst2 ...)] for each
  ~c[i].  Once this replacement is complete, the hint may not contain two
  members whose ~ilc[car] is the same ~il[rune].

  Note that the substitutions in ~c[:restrict] hints refer to the
  variables actually appearing in the goals, not to the variables
  appearing in the rule being restricted.

  Here is an example, supplied by Bishop Brock.  Suppose that the
  database includes the following rewrite rule, which is probably kept
  ~il[disable]d.  (We ignore the question of how to prove this rule.)
  ~bv[]
  cancel-<-*$free:
  (implies (and (rationalp x)
                (rationalp y)
                (rationalp z))
           (equal (< y z)
                  (if (< x 0)
                      (> (* x y) (* x z))
                    (if (> x 0)
                        (< (* x y) (* x z))
                      (hide (< y z))))))
  ~ev[]
  Then ACL2 can prove the following theorem (unless other rules get in
  the way), essentially by multiplying both sides by ~c[x].
  ~bv[]
  (thm
    (implies (and (rationalp x)
                  (< 1 x))
             (< (/ x) 1))
    :hints
    ((\"Goal\"
      :in-theory (enable cancel-<-*$free)
      :restrict ((cancel-<-*$free ((x x) (y (/ x)) (z 1)))))))
  ~ev[]
  The ~c[:restrict] hint above says that the variables ~c[x], ~c[y], and ~c[z] in the
  rewrite rule ~c[cancel-<-*$free] above should be instantiated
  respectively by ~c[x], ~c[(/ x)], and ~c[1].  Thus ~c[(< y z)] becomes ~c[(< (/ x) 1)],
  and this inequality is replaced by the corresponding instance of the
  right-hand-side of ~c[cancel-<-*$free].  Since the current conjecture
  assumes ~c[(< 1 x)], that instance of the right-hand side simplifies to
  ~bv[]
  (< (* x (/ x)) (* x 1))
  ~ev[]
  which in turn simplifies to ~c[(< 1 x)], a hypothesis in the present
  theorem.

  ~c[:NONLINEARP]~nl[]
  ~c[Value] is ~c[t] or ~c[nil], indicating whether ~il[non-linear-arithmetic]
  is active.  The default value is ~c[nil].  ~l[non-linear-arithmetic].

  ~c[:BACKCHAIN-LIMIT-RW]~nl[]
  ~c[Value] is a natural number or ~c[nil], indicating the level of
  backchaining for ~il[rewrite], ~il[meta], and ~il[linear] rules.  This
  overrides, for the current goal and (as with ~c[:]~ilc[in-theory] hints)
  descendent goals, the default ~il[backchain-limit]
  (~pl[set-backchain-limit]).

  ~c[:REORDER]~nl[]
  ~c[Value] is a list of positive integers without duplicates, corresponding to
  the numbering of subgoals generated for the ~ilc[goal-spec], say ~c[\"G.k\"]
  down to ~c[\"G.1\"].  Those subgoals are reordered so that if ~c[value] is
  ~c[(n1 n2 ... nk)], then the goal now numbered ~c[\"G.k\"] will be the goal
  originally numbered ~c[\"G.n1\"]; the goal now numbered ~c[\"G.k-1\"] will be
  the goal formerly numbered ~c[\"G.n2\"]; and so on, down the list of ~c[ni],
  after which the goals not yet printed are printed in their original order.

  ~c[:CASE-SPLIT-LIMITATIONS]~nl[]
  ~c[Value] is the same as for ~ilc[set-case-split-limitations].  The
  simplifier will behave as though the value had instead been supplied to
  ~c[set-case-split-limitations]; ~pl[set-case-split-limitations].  This
  behavior will persist through subgoals unless overridden by another
  ~c[:CASE-SPLIT-LIMITATIONS] hint.

  ~c[:NO-OP]~nl[]
  ~c[Value] is any object and is irrelevant.  This hint does nothing.
  But empty hints, such as ~c[(\"Goal\")], are illegal and there are
  occasions, especially when writing custom keyword hints
  (~pl[custom-keyword-hints]) and computed hints (~pl[computed-hints])
  where it is convenient to be able to generate a non-empty no-op
  hint.  The standard idiom is ~c[(\"Goal\" :NO-OP T)] but the ~c[T]
  is completely ignored.  Unlike other hint keywords, multiple
  occurrences of the keyword ~c[:NO-OP] are tolerated.

  ~c[:NO-THANKS]~nl[]
  ~c[Value] is any object.  This hint does nothing, except that if
  ~c[value] is non-~c[nil] then the usual ``[Note:  A hint was
  supplied... Thanks!]'' is not printed.

  ~c[:ERROR]~nl[]
  ~c[Value] is typically a ``fmt message'' to be printed by the
  ~ilc[fmt] tilde-directive ~~@ but may be any object.  The effect
  of this hint is to cause an error when the hint is translated.
  There is no reason to include an ~c[:ERROR] hint in any user-typein,
  since it will only cause an error when the form is evaluated.
  ~c[:ERROR] hints are useful in the definition of functions that
  generate custom keyword hints (~il[custom-keyword-hints]) and
  computed hints (~il[computed-hints]).  For example, if you wish
  to define a custom keyword hint ~c[:my-hint val] and you wish the
  hint to signal an error if there is something inappropriate about
  ~c[val] in the context of the hint, use the following code to generate
  the hint
  ~bv[]
  (list :ERROR (cons \"Your specified value, ~~x0, is inappropriate\"
                     (list (cons \#0 val))))
  ~ev[]
  which is equivalent to
  ~bv[]
  (list :ERROR (msg \"Your specified value, ~~x0, is inappropriate\"
                    val))
  ~ev[]
  which, if ~c[val] has the value ~c[123], would evaluate to the hint
  ~bv[]  
  (:ERROR (\"Your specified value, ~~x0, is inappropriate\" (\#0 . 123))).
  ~ev[]
  Note that any time an ~c[:ERROR] keyword is produced during hint processing,
  including iterations of the expansions of custom keyword hints or of
  ~il[override-hints], an error will occur.

  ~c[:OR]~nl[]
  ~c[Value] is a list ~c[(kwd-val-listp-1 ... kwd-val-listp-k)], where each
  ~c[kwd-val-listp-i] is a list satisfying ~ilc[keyword-value-listp], i.e., an
  alternating list of keywords and values.  This hint causes an attempt to
  prove the specified goal using hints kwd-val-listp-1 in turn, until the first
  of these succeeds.  If none succeeds, then the prover proceeds after
  heuristically choosing the ``best'' result, taking into account the goals
  pushed in each case for proof by induction.

  The following (contrived but illustrative example illustrates how ~c[:or]
  hints work.
  ~bv[]
    ACL2 !>(thm (f x)
                :hints
                ((\"Goal\"
                  :expand ((nth x 3))
                  :or ((:in-theory (disable car-cons))
                       (:use cdr-cons :in-theory (enable append)))
                  :do-not '(generalize))))

    [Note:  A hint was supplied for our processing of the goal above. 
    Thanks!]

    The :OR hint for Goal gives rise to two disjunctive branches.  Proving
    any one of these branches would suffice to prove Goal.  We explore
    them in turn, describing their derivations as we go.

    ---
    Subgoal D2
    ( same formula as Goal ).

    The first disjunctive branch (of 2) for Goal can be created by applying
    the hint:
    (\"Subgoal D2\" :EXPAND ((NTH X 3))
                  :IN-THEORY (DISABLE CAR-CONS)
                  :DO-NOT '(GENERALIZE)).


    [Note:  A hint was supplied for our processing of the goal above. 
    Thanks!]

    Normally we would attempt to prove this formula by induction.  However,
    we prefer in this instance to focus on the original input conjecture
    rather than this simplified special case.  We therefore abandon our
    previous work on this conjecture and reassign the name *1 to the original
    conjecture.  (See :DOC otf-flg.)  [Note:  Thanks again for the hint.]

    ---
    Subgoal D1
    ( same formula as Goal ).

    The second disjunctive branch (of 2) for Goal can be created by applying
    the hint:
    (\"Subgoal D1\" :EXPAND ((NTH X 3))
                  :USE CDR-CONS
                  :IN-THEORY (ENABLE APPEND)
                  :DO-NOT '(GENERALIZE)).


    [Note:  A hint was supplied for our processing of the goal above. 
    Thanks!]

    ACL2 Warning [Use] in ( THM ...):  It is unusual to :USE an enabled
    :REWRITE or :DEFINITION rule, so you may want to consider disabling
    (:REWRITE CDR-CONS).


    We augment the goal with the hypothesis provided by the :USE hint.
    The hypothesis can be obtained from CDR-CONS.  We are left with the
    following subgoal.

    Subgoal D1'
    (IMPLIES (EQUAL (CDR (CONS X Y)) Y)
             (F X)).

    By the simple :rewrite rule CDR-CONS we reduce the conjecture to

    Subgoal D1''
    (F X).
  ~ev[]
  ... and so on.  This example illustrates how ACL2 processes ~c[:or] hints in
  general.  For each ~c[i] from 1 to ~c[k], a so-called ``disjunctive'' subgoal
  is created by splicing ~c[kwd-val-listp-i] into the other hint values (if
  any) supplied for the given goal, in order.  A corresponding subgoal is
  created for each ~c[i], numbered in the usual manner (hence, counting down)
  except that the ``~c[D]'' is prefixed to each resulting goal.

  ~c[:BACKTRACK]~nl[]
  This is an advanced hint.  You can probably accomplish its effect by the use
  of ordinary computed hints; ~pl[computed-hints].  But if you are an expert,
  read on.  (~l[hints-and-the-waterfall] for some relevant background.)

  ~c[Value] is a computed hint, which is an expression that evaluates either to
  ~c[nil] ~-[] indicating that the ~c[:backtrack] hint is to have no effect
  ~-[] or to a non-empty alternating list of ~c[:keyi :vali] pairs, as expected
  for a hint.  However, unlike ordinary computed hints, ~c[:backtrack] hints
  are evaluated ~st[after] a goal has been processed to yield zero or more
  subgoals, not before.  Moreover, variables ~c[PROCESSOR] and ~c[CLAUSE-LIST]
  are allowed, but variable ~c[STABLE-UNDER-SIMPLIFICATIONP] is not.  We
  explain in more detail below, but first consider the following simple
  example.  First we define a standard list reversal function:
  ~bv[]
  (defun rev (x)
    (if (consp x)
        (append (rev (cdr x)) (cons (car x) nil))
      nil))
  ~ev[]
  Now we prove:
  ~bv[]
  (thm (true-listp (rev x)))
  ~ev[]
  The successful proof includes the following output.
  ~bv[]
  Subgoal *1/1'
  (IMPLIES
    (AND (CONSP X)
         (TRUE-LISTP (REV (CDR X))))
    (TRUE-LISTP (APPEND (REV (CDR X)) (LIST (CAR X))))).

  The destructor terms (CAR X) and (CDR X) can be
  eliminated by using CAR-CDR-ELIM to replace X
  by (CONS X1 X2), (CAR X) by X1 and (CDR X) by
  X2.  This produces the following goal.

  Subgoal *1/1''
  (IMPLIES (AND (CONSP (CONS X1 X2))
                (TRUE-LISTP (REV X2)))
           (TRUE-LISTP (APPEND (REV X2) (LIST X1)))).
  ~ev[]
  But suppose that we attach a ~c[:backtrack] hint to the goal above at which
  destructor elimination was applied:
  ~bv[]
  (thm (true-listp (rev x))
       :hints ((\"Subgoal *1/1'\"
                :backtrack
                (quote (:do-not '(eliminate-destructors))))))
  ~ev[]
  Then when ACL2 applies destructor elimination as displayed above, this time
  the ~c[:backtrack] hint applies, evaluating to
  ~c[(:do-not '(eliminate-destructors))].  Since this list is not ~c[nil], the
  prover decides not to keep the new subgoal, and instead supplies this
  ~c[:do-not] hint before attacking the goal again.  In this example, ACL2
  happens to use a technique later in its ``waterfall'' arsenal than destructor
  elimination, namely, generalization:
  ~bv[]
  Subgoal *1/1'
  (IMPLIES
    (AND (CONSP X)
         (TRUE-LISTP (REV (CDR X))))
    (TRUE-LISTP (APPEND (REV (CDR X)) (LIST (CAR X))))).

  [Note:  A hint was supplied for our processing
  of the goal above, because of a :backtrack hint
  that is preventing destructor elimination.
  Thanks!]

  We generalize this conjecture, replacing 
  (REV (CDR X)) by RV.  This produces

  Subgoal *1/1''
  (IMPLIES (AND (CONSP X) (TRUE-LISTP RV))
           (TRUE-LISTP (APPEND RV (LIST (CAR X))))).
  ~ev[]  

  We now provide a careful explanation of how ~c[:backtrack] hints work, but we
  suggest that you keep the example above in mind.  If ``~c[:backtrack form]''
  is part of the hint that has been selected for a goal, then ~c[form] is
  evaluated when one of ACL2's clause processors successfully applies to the
  current goal to produce a list of subgoals.  This evaluation takes place in
  an environment just like that for any computed hint (~pl[computed-hints]),
  with the following exceptions.  First, the variable
  ~c[STABLE-UNDER-SIMPLIFICATIONP] is not allowed to occur free in ~c[form],
  but instead the following new variables are allowed to occur free and are
  bound for this evaluation as follows: ~c[PROCESSOR] is bound to the processor
  in the list ~c[*preprocess-clause-ledge*] that has applied to the goal, and
  ~c[CLAUSE-LIST] is bound to the list of clauses (each a list of literals that
  is implicitly disjoined) returned by that clause processor.  Second, the
  variables ~c[HIST] and ~c[PSPV] are bound to the history and pspv returned by
  the clause processor, ~st[not] the ones that were passed to the clause
  processor.  If this evaluation returns an error, then the proof aborts, as
  for any computed hint whose evaluation returns an error.  If this evaluation
  returns ~c[nil], then the ~c[:backtrack] hint has no effect, and the goal is
  replaced by the list of goals (the value of ~c[CLAUSE-LIST] described above),
  as usual.  Otherwise, the clause processor is deemed to have failed, and the
  goal clause is tried again after applying the hint returned by the above
  evaluation.  That hint will normally be an alternating list of hint keywords
  and their values, but if it is a custom keyword hint
  (~pl[custom-keyword-hints]), then it will be handled in the usual manner but
  with the first three variables above bound to the symbol ~c[:OMITTED].  Of
  course, if the new hint includes a value for ~c[:BACKTRACK] then this process
  can loop; care should be taken to keep that from happening.

  A final note about ~c[:BACKTRACK] hints: ~il[override-hints] (if any) are
  applied in their processing.  ~l[override-hints].~/")

(deflabel clause-identifier
  :doc
  ":Doc-Section Miscellaneous

  the internal form of a ~il[goal-spec]~/

  To each goal-spec, ~c[str], there corresponds a clause-identifier
  produced by ~c[(parse-clause-id str)].  For example,
  ~bv[]
  (parse-clause-id \"[2]Subgoal *4.5.6/7.8.9'''\")
  ~ev[]
  returns ~c[((2 4 5 6) (7 8 9) . 3)].

  The function ~c[string-for-tilde-@-clause-id-phrase] inverts
  ~c[parse-clause-id] in the sense that given a clause identifier it
  returns the corresponding goal-spec.~/

  As noted in the documentation for ~il[goal-spec], each clause
  printed in the theorem prover's proof attempt is identified by a
  name.  When these names are represented as strings they are called
  ``goal specs.''  Such strings are used to specify where in the proof
  attempt a given hint is to be applied.  The function
  ~c[parse-clause-id] converts goal-specs into clause identifiers,
  which are cons-trees containing natural numbers.

  Examples of goal-specs and their corresponding clause identifiers
  are shown below.
  ~bv[]
               parse-clause-id
                     -->

  \"Goal\"                       ((0) NIL . 0)
  \"Subgoal 3.2.1'\"             ((0) (3 2 1) . 1)
  \"[2]Subgoal *4.5.6/7.8.9'''\" ((2 4 5 6) (7 8 9) . 3)

                     <--
        string-for-tilde-@-clause-id-phrase
  ~ev[]

  The caar of a clause id specifies the forcing round, the cdar
  specifies the goal being proved by induction, the cadr specifies the
  particular subgoal, and the cddr is the number of primes in that
  subgoal.

  Internally, the system maintains clause ids, not goal-specs.  The
  system prints clause ids in the form shown by goal-specs.  When a
  goal-spec is used in a hint, it is parsed (before the proof attempt
  begins) into a clause id.  During the proof attempt, the system
  watches for the clause id and uses the corresponding hint when the
  id arises.  (Because of the expense of creating and garbage
  collecting a lot of strings, this design is more efficient than the
  alternative.)")

(deflabel computed-hints
  :doc
  ":Doc-Section Miscellaneous

  computing advice to the theorem proving process~/
  ~bv[]
  General Form of :hints:
  (hint1 hint2 ... hintk)
  ~ev[]
  Each element, hinti, must be either a common hint or a computed hint.~/

  A common hint is of the form
  ~bv[]
  (goal-spec :key1 val1 ... :keyn valn)
  ~ev[]
  where ~c[goal-spec] is as specified in ~il[goal-spec] and each ~c[:keyi] and
  ~c[vali] is as specified in ~il[hints].  Among the ``common hints'' we
  include both the primitive hints and user-defined custom keyword hints
  (~pl[custom-keyword-hints]).

  A computed hint may be a function symbol, ~c[fn], of three, four or seven
  arguments.  Otherwise, a computed hint is a term with the following
  properties:

  (a) the only free variables allowed in the term are ~c[ID], ~c[CLAUSE],
  ~c[WORLD], ~c[STABLE-UNDER-SIMPLIFICATIONP], ~c[HIST], ~c[PSPV], ~c[CTX], and
  ~ilc[STATE];

  (b) the output signature of the term is either ~c[(MV * * STATE)], which is
  to be treated as an error triple (see below), or is ~c[*], denoting a single
  non-~il[stobj] value; and

  (c) in the former case of (b) above, the term is single-threaded in
  ~ilc[STATE].

  If a computed hint is a function symbol ~c[fn], whose arity n is therefore
  three, four, or seven, then it is treated as the term resulting from applying
  that ~c[fn] to the first n variables shown in (a) above.  Notice that it must
  then return a single non-~il[stobj] value, not an error triple, since
  ~c[state] is not one of the first seven variables shown in (a).

  Note: Error triples are an ACL2 idiom for implementing ``errors.''  If a
  computation returns ~c[(mv erp val state)] in a context in which ACL2 is
  respecting the error triple convention (~pl[ld-error-triples] and
  ~pl[ld-error-action]), then an error is deemed to have occurred if ~c[erp] is
  non-~c[nil].  The computation is expected to have printed an appropriate
  error message to ~ilc[state] and further computation is aborted.  On the
  other hand, if a computation returns an error triple in which ~c[erp] is nil,
  then ``value'' of the computation is taken to be the second component,
  ~c[val], of the triple (along with the possibly modified ~ilc[state]), and
  computation continues.

  The function symbol cases are treated as abbreviations of the term
  ~c[(fn ID CLAUSE WORLD)],
  ~c[(fn ID CLAUSE WORLD STABLE-UNDER-SIMPLIFICATIONP)], or
  ~c[(fn ID CLAUSE WORLD STABLE-UNDER-SIMPLIFICATIONP HIST PSPV CTX)]
  as appropriate for the arity of ~c[fn].  (Note that this tells you which
  argument of ~c[fn] is which.)  Moreover, in these cases the value returned
  must be a single ordinary (non-~il[stobj]) value, not an error triple.  In
  the discussion below we assume all computed hints are of the term form.
  Indeed, we almost assume all computed hints are of the 3 and 4 argument
  forms.  We only comment briefly on the 7 argument form in
  ~il[using-computed-hints-8].

  The semantics of a computed hint term is as follows.  On every subgoal, the
  term is evaluated in an environment in which the variables mentioned in (a)
  above are bound to context-sensitive values explained below.  Either the
  computed hint signals an error, in which the proof attempt aborts, or else it
  returns a value, ~c[val] and a new state, ~ilc[state].  Any changes to those
  parts of ~ilc[state] that affect logical soundness are undone; more
  specifically, the values of symbols (sometimes called ``state global
  variables'') in the list ~c[*protected-system-state-globals*] in the global
  table of the state (~pl[state]) are restored when changed during evaluation.
  The value, ~c[val], of a non-erroneous computed hint calculation is either
  ~c[nil], which means the computed hint did not apply to the subgoal in
  question, or it is an alternating list of ~c[:keyi vali] pairs as specified
  in ~il[hints].  With one exception, those new hints are applied to the given
  subgoal as though the user had typed them explicitly.

  The exception is that the first keyword in the returned ~c[val] is allowed to
  be ~c[:COMPUTED-HINT-REPLACEMENT].  Its value should be ~c[nil], ~c[t], or a
  list of terms.  If this keyword is not present, the default value of ~c[nil]
  is provided.  We explain ~c[:COMPUTED-HINT-REPLACEMENT] below.

  The evaluation of a hint term is done with guard checking turned off
  (~pl[set-guard-checking]); e.g., the form ~c[(car 23)] in a
  computed hint returns ~c[nil] as per the axioms.

  When a non-~c[nil] value is returned, the keyword/value pairs (other than the
  optional ~c[:COMPUTED-HINT-REPLACEMENT]) are used as the hint for the subgoal
  in question.  Thus, your job as the programmer of computed hints is either to
  cause an error, typically by invoking ~ilc[er], or to return a non-erroneous
  value triple whose value is the list of keys and values you would have typed
  had you supplied a common hint for the subgoal. (In particular, any theory
  expressions in it are evaluated with respect to the global current-theory,
  not whatever theory is active at the subgoal in question.)  If the generated
  list of keywords and values is illegal, an error will be signaled and the
  proof attempt will be aborted.

  The purpose of the ~c[:COMPUTED-HINT-REPLACEMENT] keyword and its value,
  ~c[chr], is to change the list of hints.  If ~c[chr] is ~c[nil], then the
  hint which was applied is removed from the list of hints that is passed down
  to the children of the subgoal in question.  This is the default.  If ~c[chr]
  is ~c[t], then the hint is left in the list of hints.  This means that the
  same hint may act on the children of the subgoal.  Otherwise, ~c[chr] must be
  a list of terms, each of which is treated as a computed hint.  The hint which
  was applied is deleted from the list of hints and the hints in ~c[chr] are
  added to the list of hints passed to the children of the subgoal.  The
  ability to compute new hints and pass them down allows strange and wonderful
  behavior.

  For these purposes, the goals produced by induction and the top-level goals
  of forcing rounds are not considered children; all original hints are
  available to them.

  Only the first hint applicable to a goal, as specified in the user-supplied
  list of ~c[:hints] followed by the ~ilc[default-hints-table], will be applied
  to that goal.  (For an advanced exception, ~pl[override-hints].)

  It remains only to describe the bindings of the free variables.

  Suppose the theorem prover is working on some clause, clause, named by some
  ~ilc[goal-spec], e.g., \"Subgoal *1/2'''\" in some logical world, world.
  Corresponding to the printed ~c[goal-spec] is an internal data structure
  called a ``clause identifier'' id.  ~l[clause-identifier].

  In the case of a common hint, the hint applies if the goal-spec of the hint
  is the same as the goal-spec of the clause in question.

  In the case of a computed hint, the variable ~c[ID] is bound to the clause
  id, the variable ~c[CLAUSE] is bound to the (translated form of the) clause,
  and the variable ~c[WORLD] is bound to the current ACL2 world.  The variable
  ~c[STABLE-UNDER-SIMPLIFICATIONP] is bound to ~c[t] or ~c[nil].  It is bound
  to ~c[t] only if the clause is known to be stable under simplification.  That
  is, the simplifier has been applied to the clause and did not change it.
  Such a clause is sometimes known as a ``simplification checkpoint.''  It is
  frequently useful to inject hints (e.g., to enable a rule or provide a
  ~c[:use] hint) only when the goal in question has stabilized.  If a hint is
  provided, the processing of the clause starts over with simplification.

  As for ~c[CTX] and ~ilc[STATE], they are provided so that you can pass them
  to the ~ilc[er] macro to print error messages.  We recommend not writing
  computed hints that otherwise change ~ilc[STATE]!

  The remaining variables, ~c[HIST] and ~c[PSPV] are not documented yet.  Only
  users familiar with the internals of ACL2 are likely to need them or
  understand their values.

  For some instruction about how to use computed hints,
  ~pl[using-computed-hints].")

(deflabel using-computed-hints-1
  :doc
  ":Doc-Section Miscellaneous

  Driving Home the Basics~/~/

  The common hint
  ~bv[]
  (\"Subgoal 3.2.1''\" :use lemma42)
  ~ev[]
  has the same effect as the computed hint
  ~bv[]
  (if (equal id '((0) (3 2 1) . 2))
      '(:use lemma42)
      nil)
  ~ev[]
  which, of course, is equivalent to
  ~bv[]
  (and (equal id '((0) (3 2 1) . 2))
       '(:use lemma42))
  ~ev[]
  which is also equivalent to the computed hint
  ~bv[]
  my-special-hint
  ~ev[]
  provided the following ~c[defun] has first been executed
  ~bv[]
  (defun my-special-hint (id clause world)
    (declare (xargs :mode :program)
             (ignore clause world))
    (if (equal id '((0) (3 2 1) . 2))
        '(:use lemma42)
        nil))
  ~ev[]
  It is permitted for the ~c[defun] to be in :LOGIC mode
  (~pl[defun-mode]) also.

  Just to be concrete, the following three events all behave the same
  way (if ~c[my-special-hint] is as above):

  ~bv[]
  (defthm main (big-thm a b c)
    :hints ((\"Subgoal 3.2.1''\" :use lemma42)))
  
  (defthm main (big-thm a b c)
    :hints ((and (equal id '((0) (3 2 1) . 2)) '(:use lemma42))))

  (defthm main (big-thm a b c)
    :hints (my-special-hint))
  ~ev[]")

(deflabel using-computed-hints-2
  :doc
  ":Doc-Section Miscellaneous

  One Hint to Every Top-Level Goal in a Forcing Round~/~/

  Suppose the main proof completes with a forcing round on three
  subgoals, \"[1]Subgoal 3\", \"[1]Subgoal 2\", and \"[1]Subgoal 1\".
  Suppose you wish to ~c[:use lemma42] in all top-level goals of the
  first forcing round.  This can be done supplying the hint
  ~bv[]
  (if test '(:use lemma42) nil),
  ~ev[]
  where ~c[test] is an expression that returns
  ~c[t] when ~c[ID] is one of the clause ids in question.
  ~bv[]
      goal-spec     (parse-clause-id goal-spec)

  \"[1]Subgoal 3\"        ((1) (3) . 0)
  \"[1]Subgoal 2\"        ((1) (2) . 0)
  \"[1]Subgoal 1\"        ((1) (1) . 0)
  ~ev[]
  Recall (~pl[clause-identifier]) that ~c[parse-clause-id] maps
  from a goal spec to a clause id, so you can use that function on the
  goal specs printed in the failed proof attempt to determine the
  clause ids in question.

  So one acceptable ~c[test] is
  ~bv[]
  (member-equal id '(((1) (3) . 0) 
                     ((1) (2) . 0)
                     ((1) (1) . 0)))
  ~ev[]
  or you could use ~c[parse-clause-id] in your computed hint if you
  don't want to see clause ids in your script:
  ~bv[]
  (or (equal id (parse-clause-id \"[1]Subgoal 3\"))
      (equal id (parse-clause-id \"[1]Subgoal 2\"))
      (equal id (parse-clause-id \"[1]Subgoal 1\")))
  ~ev[]
  or you could use the inverse function (~pl[clause-identifier]):
  ~bv[]
  (member-equal (string-for-tilde-@-clause-id-phrase id)
                '(\"[1]Subgoal 3\"
                  \"[1]Subgoal 2\"
                  \"[1]Subgoal 1\"))
  ~ev[]

  Recall that what we've shown above are the tests to use in the
  computed hint.  The hint itself is ~c[(if test '(:use lemma42) nil)]
  or something equivalent like ~c[(and test '(:use lemma42))].

  The three tests above are all equivalent.  They suffer from the
  problem of requiring the explicit enumeration of all the goal specs
  in the first forcing round.  A change in the script might cause more
  forced subgoals and the ones other than those enumerated would not
  be given the hint.

  You could write a test that recognizes all first round top-level
  subgoals no matter how many there are.  Just think of the
  programming problem:  how do I recognize all the clause id's of the
  form ~c[((1) (n) . 0)]?  Often you can come to this formulation of
  the problem by using ~c[parse-clause-id] on a few of the candidate
  goal-specs to see the common structure.  A suitable test in this
  case is:
  ~bv[]
  (and (equal (car id) '(1))     ; forcing round 1, top-level (pre-induction)
       (equal (len (cadr id)) 1) ; Subgoal n (not Subgoal n.i ...)
       (equal (cddr id) 0))      ; no primes
  ~ev[]

  The test above is ``overkill'' because it recognizes precisely the
  clause ids in question.  But recall that once a computed hint is
  used, it is (by default) removed from the hints available to the
  children of the clause.  Thus, we can widen the set of clause ids
  recognized to include all the children without worrying that the
  hint will be applied to those children.

  In particular, the following test supplies the hint to every
  top-level goal of the first forcing round:
  ~bv[]
  (equal (car id) '(1))
  ~ev[]
  You might worry that it would also supply the hint to the subgoal
  produced by the hint -- the cases we ruled out by the ``overkill''
  above.  But that doesn't happen since the hint is unavailable to the
  children.  You could even write:
  ~bv[]
  (equal (car (car id)) 1)
  ~ev[]
  which would supply the hint to every goal of the form \"[1]Subgoal ...\"
  and again, because we see and fire on the top-level goals first, we
  will not fire on, say, \"[1]Subgoal *1.3/2\", i.e., the id '((1 1 3)
  (2) . 0) even though the test recognizes that id.

  Finally, the following test supplies the hint to every top-level goal
  of every forcing round (except the 0th, which is the ``gist'' of the
  proof, not ``really'' a forcing round):
  ~bv[]
  (not (equal (car (car id)) 0))
  ~ev[]

  Recall again that in all the examples above we have exhibited the
  ~c[test] in a computed hint of the form ~c[(if test '(:key1 val1 ...) nil)].")

(deflabel using-computed-hints-3
  :doc
  ":Doc-Section Miscellaneous

  Hints as a Function of the Goal (not its Name)~/~/

  Sometimes it is desirable to supply a hint whenever a certain term
  arises in a conjecture.  For example, suppose we have proved
  ~bv[]
  (defthm all-swaps-have-the-property
     (the-property (swap x))
     :rule-classes nil)
  ~ev[]
  and suppose that whenever ~c[(SWAP A)] occurs in a goal, we wish to
  add the additional hypothesis that ~c[(THE-PROPERTY (SWAP A))].
  Note that this is equivalent supplying the hint
  ~bv[]
  (if test
      '(:use (:instance all-swaps-have-the-property (x A)))
      nil)
  ~ev[]
  where ~c[test] answers the question ``does the clause contain ~c[(SWAP A)]?''
  That question can be asked with ~c[(occur-lst '(SWAP A) clause)].
  Briefly, ~c[occur-lst] takes the representation of a translated term,
  x, and a list of translated terms, y, and determines whether x
  occurs as a subterm of any term in y.  (By ``subterm'' here we mean
  proper or improper, e.g., the subterms of ~c[(CAR X)] are ~c[X] and
  ~c[(CAR X)].)

  Thus, the computed hint:
  ~bv[]
  (if (occur-lst '(swap a) clause)
      '(:use (:instance all-swaps-have-the-property (x A)))
      nil)
  ~ev[]
  will add the hypothesis ~c[(THE-PROPERTY (SWAP A))] to every goal
  containing ~c[(SWAP A)] -- except the children of goals to which the
  hypothesis was added.

  ~b[A COMMON MISTAKE] users are likely to make is to forget that they
  are dealing with translated terms.  For example, suppose we wished
  to look for ~c[(SWAP (LIST 1 A))] with ~c[occur-lst].  We would never
  find it with
  ~bv[]
  (occur-lst '(SWAP (LIST 1 A)) clause)
  ~ev[]
  because that presentation of the term contains macros and other
  abbreviations.  By using :trans (~pl[trans]) we can obtain the
  translation of the target term.  Then we can look for it with:
  ~bv[]
  (occur-lst '(SWAP (CONS '1 (CONS A 'NIL))) clause)
  ~ev[]
  Note in particular that you must 
  ~bf[]
  * eliminate all macros and
  * explicitly quote all constants.
  ~ef[]
  We recommend using ~c[:trans] to obtain the translated form of the
  terms in which you are interested, before programming your hints.

  An alternative is to use the expression
  ~c[(prettyify-clause clause nil nil)] in your hint to convert the
  current goal clause into the s-expression that is actually printed.
  For example, the clause
  ~bv[]
  ((NOT (CONSP X)) (SYMBOLP Y) (EQUAL (CONS '1 (CAR X)) Y)) 
  ~ev[]
  ``prettyifies'' to
  ~bv[]
  (IMPLIES (AND (CONSP X)
                (NOT (SYMBOLP Y)))
           (EQUAL (CONS 1 (CAR X)) Y))
  ~ev[]
  which is what you would see printed by ACL2 when the goal clause is
  that shown.

  However, if you choose to convert your clauses to prettyified form,
  you will have to write your own explorers (like our ~c[occur-lst]),
  because all of the ACL2 term processing utilities work on translated
  and/or clausal forms.  This should not be taken as a terrible
  burden.  You will, at least, gain the benefit of knowing what you
  are really looking for, because your explorers will be looking at
  exactly the s-expressions you see at your terminal.  And you won't
  have to wade through our still undocumented term/clause utilities.
  The approach will slow things down a little, since you will be
  paying the price of independently consing up the prettyified term.

  We make one more note on this example.  We said above that
  the computed hint:
  ~bv[]
  (if (occur-lst '(swap a) clause)
      '(:use (:instance all-swaps-have-the-property (x A)))
      nil)
  ~ev[]
  will add the hypothesis ~c[(THE-PROPERTY (SWAP A))] to every goal
  containing ~c[(SWAP A)] -- except the children of goals to which the
  hypothesis was added.

  It bears noting that the subgoals produced by induction and
  top-level forcing round goals are not children.  For example,
  suppose the hint above fires on \"Subgoal 3\" and produces, say,
  \"Subgoal 3'\".  Then the hint will not fire on \"Subgoal 3'\" even
  though it (still) contains ~c[(SWAP A)] because \"Subgoal 3'\" is a
  child of a goal on which the hint fired.

  But now suppose that \"Subgoal 3'\" is pushed for induction.  Then
  the goals created by that induction, i.e., the base case and
  induction step, are not considered children of \"Subgoal 3'\".  All
  of the original hints are available.

  Alternatively, suppose that \"Subgoal 3'\ is proved but forces some
  other subgoal, \"[1]Subgoal 1\" which is attacked in Forcing Round
  1.  That top-level forced subgoal is not a child.  All the original
  hints are available to it.  Thus, if it contains ~c[(SWAP A)], the
  hint will fire and supply the hypothesis, producing \"[1]Subgoal
  1'\".  This may be unnecessary, as the hypothesis might already be
  present in \"[1]Subgoal 1\".  In this case, no harm is done.  The
  hint won't fire on \"[1]Subgoal 1\" because it is a child of
  \"[1]Subgoal 1\" and the hint fired on that.")

(deflabel using-computed-hints-4
  :doc
  ":Doc-Section Miscellaneous

  Computing the Hints~/~/

  So far we have used computed hints only to compute when a fixed set
  of keys and values are to be used as a hint.  But computed hints
  can, of course, compute the set of keys and values.  You might, for
  example, write a hint that recognizes when a clause ``ought'' to be
  provable by a ~c[:BDD] hint and generate the appropriate hint.  You
  might build in a set of useful lemmas and check to see if the clause
  is provable ~c[:BY] one of them.  You can keep all function symbols
  disabled and use computed hints to compute which ones you want to
  ~c[:EXPAND].  In general, you can write a theorem prover for use in
  your hints, provided you can get it to do its job by directing our
  theorem prover.

  Suppose for example we wish to find every occurrence of an instance
  of ~c[(SWAP x)] and provide the corresponding instance of
  ~c[ALL-SWAPS-HAVE-THE-PROPERTY].  Obviously, we must explore the
  clause looking for instances of ~c[(SWAP x)] and build the
  appropriate instances of the lemma.  We could do this in many
  different ways, but below we show a general purpose set of utilities
  for doing it.  The functions are not defined in ACL2 but could be
  defined as shown.

  Our plan is:  (1) Find all instances of a given pattern (term) in a
  clause, obtaining a set of substitutions.  (2) Build a set of
  ~c[:instance] expressions for a given lemma name and set of
  substitutions.  (3) Generate a ~c[:use] hint for those instances when
  instances are found.

  The pair of functions below find all instances of a given pattern
  term in either a term or a list of terms.  The functions each return
  a list of substitutions, each substitution accounting for one of the
  matches of pat to a subterm.  At this level in ACL2 substitutions
  are lists of pairs of the form ~c[(var . term)].  All terms mentioned
  here are presumed to be in translated form.

  The functions take as their third argument a list of substitutions
  accumulated to date and add to it the substitutions produced by
  matching pat to the subterms of the term.  We intend this
  accumulator to be nil initially.  If the returned value is nil, then
  no instances of pat occurred.

  ~bv[]
  (mutual-recursion
 
  (defun find-all-instances (pat term alists)
   (declare (xargs :mode :program))
   (mv-let
    (instancep alist)
    (one-way-unify pat term)
    (let ((alists (if instancep (add-to-set-equal alist alists) alists)))
      (cond
       ((variablep term) alists)
       ((fquotep term) alists)
       ((flambdap (ffn-symb term))
        (find-all-instances pat
                            (lambda-body (ffn-symb term))
                            (find-all-instances-list pat (fargs term) alists)))
       (t (find-all-instances-list pat (fargs term) alists))))))

  (defun find-all-instances-list (pat list-of-terms alists)
   (declare (xargs :mode :program))
   (cond
    ((null list-of-terms) alists)
    (t (find-all-instances pat
                           (car list-of-terms)
                           (find-all-instances-list pat
                                                    (cdr list-of-terms)
                                                    alists))))))
  ~ev[]

  We now turn our attention to converting a list of substitutions into
  a list of lemma instances, each of the form
  ~bv[]
  (:INSTANCE name (var1 term1) ... (vark termk))
  ~ev[]
  as written in ~c[:use] hints.  In the code shown above, substitutions
  are lists of pairs of the form ~c[(var . term)], but in lemma
  instances we must write ``doublets.''  So here we show how to
  convert from one to the other:
  ~bv[]
  (defun pairs-to-doublets (alist)
    (declare (xargs :mode :program))
    (cond ((null alist) nil)
          (t (cons (list (caar alist) (cdar alist))
                   (pairs-to-doublets (cdr alist))))))
  ~ev[]

  Now we can make a list of lemma instances:
  ~bv[]
  (defun make-lemma-instances (name alists)
    (declare (xargs :mode :program))
    (cond
     ((null alists) nil)
     (t (cons (list* :instance name (pairs-to-doublets (car alists)))
              (make-lemma-instances name (cdr alists))))))
  ~ev[]

  Finally, we can package it all together into a hint function.  The
  function takes a pattern, ~c[pat], which must be a translated term,
  the name of a lemma, ~c[name], and a clause.  If some instances of
  ~c[pat] occur in ~c[clause], then the corresponding instances of
  ~c[name] are ~c[:USE]d in the computed hint.  Otherwise, the hint does
  not apply.
  ~bv[]
  (defun add-corresponding-instances (pat name clause)
    (declare (xargs :mode :program))
    (let ((alists (find-all-instances-list pat clause nil)))
      (cond
       ((null alists) nil)
       (t (list :use (make-lemma-instances name alists))))))
  ~ev[]
  The design of this particular hint function makes it important that
  the variables of the pattern be the variables of the named lemma and
  that all of the variables we wish to instantiate occur in the
  pattern.  We could, of course, redesign it to allow ``free
  variables'' or some sort of renaming.

  We could now use this hint as shown below:
  ~bv[]
  (defthm ... ...
    :hints ((add-corresponding-instances
             '(SWAP x)
             'ALL-SWAPS-HAVE-THE-PROPERTY
             clause)))
  ~ev[]
  The effect of the hint above is that any time a clause arises in
  which any instance of ~c[(SWAP x)] appears, we add the corresponding
  instance of ~c[ALL-SWAPS-HAVE-THE-PROPERTY].  So for example, if
  Subgoal *1/3.5 contains the subterm ~c[(SWAP (SWAP A))] then this
  hint fires and makes the system behave as though the hint:
  ~bv[]
  (\"Subgoal *1/3.5\"
   :USE ((:INSTANCE ALL-SWAPS-HAVE-THE-PROPERTY (X A))
         (:INSTANCE ALL-SWAPS-HAVE-THE-PROPERTY (X (SWAP A)))))
  ~ev[]
  had been present.")

(deflabel using-computed-hints-5
  :doc
  ":Doc-Section Miscellaneous

  Debugging Computed Hints~/~/

  We have found that it is sometimes helpful to define hints so that
  they print out messages to the terminal when they fire, so you can
  see what hint was generated and which of your computed hints did it.

  To that end we have defined a macro we sometimes use.  Suppose you
  have a ~c[:hints] specification such as:
  ~bv[]
  :hints (computed-hint-fn (hint-expr id))
  ~ev[]
  If you defmacro the macro below you could then write instead:
  ~bv[]
  :hints ((show-hint computed-hint-fn 1)
          (show-hint (hint-expr id) 2))
  ~ev[]
  with the effect that whenever either hint is fired (i.e., returns
  non-~c[nil]), a message identifying the hint by the marker (1 or 2,
  above) and the non-~c[nil] value is printed.

  ~bv[]
  (defmacro show-hint (hint &optional marker)
    (cond
     ((and (consp hint)
           (stringp (car hint)))
      hint)
     (t
      `(let ((marker ,marker)
             (ans ,(if (symbolp hint)
                       `(,hint id clause world stable-under-simplificationp)
                     hint)))
         (if ans
             (prog2$
              (cw \"~~%***** Computed Hint~~#0~~[~~/ (from hint ~~x1)~~]~~%~~x2~~%~~%\"
                  (if (null marker) 0 1)
                  marker
                  (cons (string-for-tilde-@-clause-id-phrase id)
                        ans))
              ans)
           nil)))))
  ~ev[]
  Note that when ~c[show-hint] is applied to a hint that is a symbol,
  e.g., ~c[computed-hint-fn], it applies the symbol to the four
  computed-hint arguments: ~c[id], ~c[clause], ~c[world], and
  ~c[stable-under-simplificationp].  If ~c[computed-hint-fn] is of 
  arity 3 the code above would cause an error.  One way to avoid it
  is to write
  ~bv[]
  :hints ((show-hints (computed-hint-fn id clause world) 1)
          (show-hint (hint-expr id) 2)).
  ~ev[]
  If you only use computed hints of arity 3, you might eliminate
  the occurrence of ~c[stable-under-simplificationp] in the definition
  of ~c[show-hint] above.

  Putting a ~c[show-hint] around a common hint has no effect.  If you
  find yourself using this utility let us know and we'll consider
  putting it into the system itself.  But it does illustrate that you
  can use computed hints to do unusual things.")

(deflabel using-computed-hints-6
  :doc
  ":Doc-Section Miscellaneous

  Using the computed-hint-replacement feature~/~/

  So far none of our computed hints have used the
  ~c[:COMPUTED-HINT-REPLACEMENT] feature.  We now illustrate that.

  The ~c[:computed-hint-replacement] feature can easily lead to loops.
  So as you experiment with the examples in this section and your own
  hints using this feature, be ready to interrupt the theorem prover
  and abort!

  A non-looping use of the ~c[:computed-hint-replacement] feature 
  would be a hint like this:
  ~bv[]
  (if (certain-terms-present clause)
      '(:computed-hint-replacement t
        :in-theory (enable lemma25))
      '(:computed-hint-replacement t
        :in-theory (disable lemma25)))
  ~ev[]
  In this hint, if certain terms are present in ~c[clause], as determined
  by the function with the obvious name (here undefined), then this
  hint enables ~c[lemma25] and otherwise disables it.  ~c[Lemma25] might be
  a very expensive lemma, e.g., one that matches frequently and has an
  expensive and rarely established hypothesis.  One might wish it enabled
  only under certain conditions.  Recall that theories are inherited by
  children.  So once ~c[lemma25] is enabled it ``stays'' enabled for the
  children, until disabled; and vice versa.  If the
  ~c[:computed-hint-replacement] feature were not present and computed 
  hints were always deleted after they had been used, then ~c[lemma25]
  would be left enabled (or disabled) for all the childen produced by the
  first firing of the hint.  But with the arrangement here, every subgoal
  gets a theory deemed suitable by the hint, and the hint persists.

  Now we will set up a toy to allow us to play with computed hints to
  understand them more deeply.  To follow the discussion it is best
  to execute the following events.
  ~bv[]
  (defstub wrapper (x) t)
  (defaxiom wrapper-axiom (wrapper x) :rule-classes nil)
  ~ev[]
  Now submit the following event and watch what happens.
  ~bv[]
  (thm (equal u v)
    :hints (`(:use (:instance wrapper-axiom (x a)))))
  ~ev[]
  The theorem prover adds ~c[(wrapper a)] to the goal
  and then abandons the proof attempt because it cannot prove the
  subgoal.  Since the computed hint is deleted upon use, the 
  hint is not applied to the subgoal (i.e., the child of the goal).

  What happens if we do the following?
  ~bv[]
  (thm (equal u v)
    :hints (`(:computed-hint-replacement t
              :use (:instance wrapper-axiom (x a)))))
  ~ev[]

  As one might expect, this loops forever: The hint is applied to the
  child and adds the hypothesis again.  When the hint fires, nothing
  is actually changed, since ~c[(wrapper a)] is already in the
  subgoal.

  So let's change the experiment a little.  Let's make the hint
  add the hypothesis ~c[(wrapper p)] where ~c[p] is the first literal
  of the clause.  This is silly but it allows us to explore the
  behavior of computed hints a little more.
  ~bv[]  
  (thm (equal u v)
    :hints (`(:use (:instance wrapper-axiom (x ,(car clause))))))
  ~ev[]
  So in this case, the theorem prover changes the goal to
  ~bv[]
  (IMPLIES (WRAPPER (EQUAL U V)) (EQUAL U V))
  ~ev[]
  which then simplifies to
  ~bv[]
  (IMPLIES (WRAPPER NIL) (EQUAL U V))
  ~ev[]
  because the concluding equality can be assumed false in the hypothesis
  (e.g., think of the contrapositive version).  Nothing else happens because
  the hint has been removed and so is not applicable to the child.

  Now consider the following -- and be ready to interrupt it and abort!
  ~bv[]  
  (thm (equal u v)
    :hints (`(:computed-hint-replacement t
              :use (:instance wrapper-axiom (x ,(car clause))))))
  ~ev[]
  This time the hint is not removed and so is applied to the child.
  So from ~c[Goal] we get
  ~bv[]
  Goal'
  (IMPLIES (WRAPPER (EQUAL U V))
           (EQUAL U V))
  ~ev[]
  and then
  ~bv[]
  Goal''
  (IMPLIES (AND (WRAPPER (NOT (WRAPPER (EQUAL U V))))
                (WRAPPER (EQUAL U V)))
           (EQUAL U V))
  ~ev[]
  etc.

  First, note that the hint is repeatedly applied to its children.
  That is because we wrote ~c[:computed-hint-replacement t].
  But second, note that ~c[Goal'] is not even being simplified
  before ~c[Goal''] is produced from it.  If it were being simplified,
  the ~c[(equal u v)]'s in the hypotheses would be replaced by ~c[nil].
  This is a feature.  It means after a computed hint has fired, other
  hints are given a chance at the result, even the hint itself unless
  it is removed from the list of hints.

  As an exercise, let's arrange for the hint to stay around and be
  applied indefinitely but with a simplification between each use of the
  the hint.  To do this we need to pass information from one application
  of the hint to the next, essentially to say ``stay around but don't fire.''

  First, we will define a function to use in the hint.  This is more
  than a mere convenience; it allows the hint to ``reproduce itself''
  in the replacement.

  ~bv[]
  (defun wrapper-challenge (clause parity)
    (if parity
        `(:computed-hint-replacement ((wrapper-challenge clause nil))
          :use (:instance wrapper-axiom (x ,(car clause))))
        `(:computed-hint-replacement ((wrapper-challenge clause t)))))
  ~ev[]
  
  Note that this function is not recursive, even though it uses its
  own name.  That is because the occurrence of its name is in a quoted
  constant.

  Now consider the following.  What will it do?

  ~bv[]
  (thm (equal u v)
    :hints ((wrapper-challenge clause t)))
  ~ev[]

  First, observe that this is a legal hint because it is a term that
  mentions only the free variable ~c[CLAUSE].  When defining hint functions
  you may sometimes think their only arguments are the four variables
  ~c[id], ~c[clause], ~c[world], and ~c[stable-under-simplificationp].
  That is not so.  But in your hints you must call those functions so that
  those are the only free variables.  Note also that the occurrence of
  ~c[clause] inside the ~c[:computed-hint-replacement] is not an occurrence
  of the variable clause but just a constant.  Just store this note
  away for a moment.  We'll return to it momentarily.

  Second, the basic cleverness of this hint is that every time it fires
  it reproduces itself with the opposite parity.  When the parity is
  ~c[t] it actually changes the goal by adding a hypothesis.  When
  the parity is ~c[nil] it doesn't change the goal and so allows
  simplification to proceed -- but it swaps the parity back to ~c[t].
  What you can see with this simple toy is that we can use the computed
  hints to pass information from parent to child.

  Ok, so what happens when the event above is executed?  Try it.  You will
  see that ACL2 applied the hint the first time.  It doesn't get around to
  printing the output because an error is caused before it can print.
  But here is a blow-by-blow description of what happens.  The hint is
  evaluated on ~c[Goal] with the ~c[clause] ~c[((equal u v))].  It produces
  a hint exactly as though we had typed:
  ~bv[]
  (\"Goal\" :use (:instance wrapper-axiom (x (equal u v))))
  ~ev[]
  which is applied to this goal. In addition, it produces the new hints
  argument
  ~bv[]
  :hints ((wrapper-challenge clause nil)).
  ~ev[]
  By applying the ~c[\"Goal\"] hint we get the new subgoal
  ~bv[]
  Goal'
  (implies (wrapper (equal u v))
           (equal u v))
  ~ev[]
  but this is not printed because, before printing it, the theorem prover
  looks for hints to apply to it and finds
  ~bv[]
  (wrapper-challenge clause nil)
  ~ev[]
  That is evaluated and produces a hint exactly as though we had typed:
  ~bv[]
  (\"Goal'\" )
  ~ev[]
  and the new hints argument:
  ~bv[]
  :hints ((wrapper-challenge clause nil)).
  ~ev[]
  But if you supply the hint ~c[(\"Goal'\" )], ACL2 will signal an error
  because it does not allow you to specify an empty hint!
  
  So the definition of ~c[wrapper-challenge] above is almost correct
  but fatally flawed.  We need a non-empty ``no-op'' hint.  One such
  hint is to tell the system to expand a term that will always be expanded
  anyway.  So undo ~c[wrapper-challenge], redefine it, and try
  the proof again.  Now remember the observation about ~c[clause] that
  we asked you to ``store'' above.  The new definition of ~c[wrapper-challenge]
  illustrates what we meant.  Note that the first formal parameter of 
  ~c[wrapper-challenge], below, is no longer named ~c[clause] but is called
  ~c[cl] instead.  But the ``call'' of ~c[wrapper-challenge] in the
  replacements is on ~c[clause].  This may seem to violate the rule that
  a function definition cannot use variables other than the formals.
  But the occurrences of ~c[clause] below are not variables but constants
  in an object that will eventually be treated as hint term.
  ~bv[]
  :ubt wrapper-challenge

  (defun wrapper-challenge (cl parity)
    (if parity
        `(:computed-hint-replacement ((wrapper-challenge clause nil))
          :use (:instance wrapper-axiom (x ,(car cl))))
        `(:computed-hint-replacement ((wrapper-challenge clause t))
          :expand ((atom zzz)))))

  (thm (equal u v)
    :hints ((wrapper-challenge clause t)))
  ~ev[]

  This time, things go as you might have expected!  ~c[Goal'] is produced
  and simplified, to 
  ~bv[]
  Goal''
  (implies (wrapper nil)
           (equal u v)).
  ~ev[]
  Simplification gets a chance because when the new hint
  ~c[(wrapper-challenge clause nil)] is fired it does not change the
  goal.  But it does change the parity in the hints argument so that
  before ~c[Goal''] is simplified again, the hint fires and adds the
  hypothesis:
  ~bv[]
  Goal'''
  (IMPLIES (AND (WRAPPER (NOT (WRAPPER NIL)))
                (WRAPPER NIL))
           (EQUAL U V)).
  ~ev[]
  This simplifies, replacing the first ~c[(NOT (WRAPPER NIL))] by ~c[NIL],
  since ~c[(WRAPPER NIL)] is known to be true here.  Thus the goal
  simplifies to
  ~bv[]
  Goal'4'
  (IMPLIES (WRAPPER NIL) (EQUAL U V)).
  ~ev[]
  The process repeats indefinitely.

  So we succeeded in getting a hint to fire indefinitely but allow a
  full simplification between rounds.")

(deflabel using-computed-hints-7
  :doc
  ":Doc-Section Miscellaneous

  Using the ~c[stable-under-simplificationp] flag~/~/

  A problem with the example in ~il[using-computed-hints-6] is that
  exactly one simplification occurs between each (effective) firing
  of the hint.  Much more commonly we wish to fire a hint once
  a subgoal has become stable under simplification.

  A classic example of this is when we are dealing with an interpreter
  for some state machine.  We typically do not want the ``step''
  function to open up on the symbolic representation of a state until
  that state has been maximally simplified.  We will illustrate with
  a simple state machine. 

  Let us start by defining the step function, ~c[stp], and the
  corresponding ~c[run] function that applies it a given number of times.
  ~bv[]
  (defun stp (s)
    (+ 1 s))

  (defun run (s n)
    (if (zp n)
        s
        (run (stp s) (- n 1))))
  ~ev[]
  The step function here is trivial:  a state is just a number and the
  step function increments it.  In this example we will not be interested
  in the theorems we prove but in how we prove them.  The formula we will
  focus on is
  ~bv[]
  (thm (equal (run s 7) xxx))
  ~ev[]
  This is not a theorem, of course.  But we want to test our advice
  on non-theorems because we do not want the advice to work only
  for proofs that succeed.  (In the past, we gave advice about
  using computed hints and that advice caused the theorem prover to
  run forever when given formulas that it couldn't prove -- but
  most of the time the system is presented with formulas it cannot
  prove!)

  Furthermore, without some kind of additional rules, the ~c[(run s 7)]
  expression in the conjecture above will not expand at all, because ACL2's
  heuristics do not approve.

  In fact, we do not want to take chances that ~c[run] will be
  expanded -- we want to control its expansion completely.
  Therefore, disable ~c[run].

  ~bv[]
  (in-theory (disable run))
  ~ev[]

  Now, what do we want?  (That is always a good question to ask!)  We want
  ~c[(run s 7)] to expand ``slowly.''  In particular, we want it to expand
  once, to ~c[(run (stp s) 6)].  Then we want the ~c[stp] to be expanded and
  fully simplified before the ~c[run] expression is expanded again.  That is,
  we want to force the expansion of ~c[run] whenever the goal is stable under
  simplification.  This is sometimes called ``staged simplification.''

  We can achieve staged simplification for any given function symbol by
  defining the functions shown below and then using a simple computed hint:

  ~bv[]
  (thm (equal (run s 7) xxx)
       :hints ((stage run)))
  ~ev[]

  By inspecting how ~c[stage] is defined you can see how to extend it,
  but we explain as we go.  To experiment, you can just paste the
  definitions (and defmacro) below into your ACL2 shell and then
  try the ~c[thm] command.

  First, define this pair of mutually recursive functions.
  ~c[Find-first-call] finds the first call of the function symbol ~c[fn]
  in a given term.
 
  ~bv[]
  (mutual-recursion
   (defun find-first-call (fn term)
   ; Find the first call of fn in term.
    (cond ((variablep term) nil)
          ((fquotep term) nil)
          ((equal (ffn-symb term) fn)
           term)
          (t (find-first-call-lst fn (fargs term)))))
   (defun find-first-call-lst (fn lst)
   ; Find the first call of fn in a list of terms.
    (cond ((endp lst) nil)
          (t (or (find-first-call fn (car lst))
                 (find-first-call-lst fn (cdr lst)))))))
  ~ev[]

  We will arrange for the computed hint to generate an ~c[:EXPAND]
  hint for the first call of ~c[fn], whenever the goal becomes
  stable under simplification.  If no call is found, the
  hint will do nothing.  To make sure the hint will not loop
  indefinitely (for example, by forcing ~c[fn] to expand only to
  have the rewriter ``fold'' it back up again), we will provide
  the hint with a bound that stops it after some number of
  iterations.  Here is the basic function that creates the
  ~c[expand] hint and replaces itself to count down.

  ~bv[]
  (defun stage1 (fn max clause flg)
  ; If the clause is stable under simplification and there is a call of
  ; fn in it, expand it.  But don't do it more than max times.
   (let ((temp (and flg
                    (find-first-call-lst fn clause))))
     (if temp
         (if (zp max)
             (cw \"~~%~~%HINT PROBLEM:  The maximum repetition count of ~~
                  your STAGE hint been reached without eliminating ~~
                  all of the calls of ~~x0.  You could supply a larger ~~
                  count with the optional second argument to STAGE ~~
                  (which defaults to 100).  But think about what is ~~
                  happening! Is each stage permanently eliminating a ~~
                  call of ~~x0?~~%~~%\"
                 fn)
           `(:computed-hint-replacement
              ((stage1 ',fn ,(- max 1)
                       clause
                       stable-under-simplificationp))
             :expand (,temp)))
       nil)))
  ~ev[]

  Suppose that when ~c[stage1] is called, ~c[fn] is the function we want to
  expand, ~c[max] is the maximum number of iterations of this expansion,
  ~c[clause] is the current goal clause, and ~c[flg] is the value of the
  ~c[stable-under-simplificationp] flag.  Then if ~c[clause] is stable and we
  can find a call of ~c[fn] in it, we ask whether ~c[max] is exhausted.  If
  so, we print an ``error message'' to the comment window with ~ilc[cw] and
  return ~c[nil] (the value of ~c[cw]).  That ~c[nil] means the hint does
  nothing.  But if ~c[max] is not yet exhausted, we return a new hint.  As
  you can see above, the hint replaces itself with another ~c[stage1] hint
  with the same ~c[fn] and a decremented ~c[max] to be applied to the new
  ~c[clause] and the then-current value of ~c[stable-under-simplificationp].
  The hint also contains an ~c[:expand] directive for the call of ~c[fn]
  found.

  Thus, if the computed hint was:

  ~bv[]
  (stage1 'run 5 clause stable-under-simplificationp)
  ~ev[]

  and ~c[(run s 7)] occurs in the clause, then it will 
  generate

  ~bv[]
  (:computed-hint-replacement
    ((stage1 'run 4 clause stable-under-simplificationp))
   :expand ((run s 7)))
  ~ev[]
  which will in turn replace the old ~c[stage1] hint with
  the new one and will apply ~c[:expand ((run s 7))] to
  the current goal.

  We can make this more convenient by defining the macro:
  ~bv[]
  (defmacro stage (fn &optional (max '100))
   `(stage1 ',fn ,max clause stable-under-simplificationp))
  ~ev[]
  Note that the macro allows us to either provide the maximum
  bound or let it default to 100.

  Henceforth, we can type
  ~bv[]
  (thm (equal (run s 7) xxx)
       :hints ((stage run)))
  ~ev[]
  to stage the opening of ~c[run] up to 100 times, or we can write
  ~bv[]
  (thm (equal (run s 7) xxx)
       :hints ((stage run 5)))
  ~ev[]
  to stage it only 5 times.  In the latter example, the system
  with print a ``error message'' after the fifth expansion.  

  Note that if we executed
  ~bv[]
  (set-default-hints '((stage run)))
  ~ev[]
  then we could attack all theorems (involving ~c[run]) with
  staged simplification (up to bound 100), without typing an
  explicit hint.
  ~bv[]
  (thm (equal (run s 7) xxx))
  ~ev[]

  Using techniques similar to those above we have implemented
  ``priority phased simplification'' and provided it as a book.  See
  ~c[books/misc/priorities.lisp].  This is an idea suggested by Pete
  Manolios, by which priorities may be assigned to rules and then the
  simplifier simplifies each subgoal maximally under the rules of a
  given priority before enabling the rules of the next priority level.
  The book above documents both how we implement it with computed
  hints and how to use it.

  Here is another example of using the ~c[stable-under-simplificationp] flag to
  delay certain actions.  It defines a default hint, ~pl[DEFAULT-HINTS],
  which will enable ~il[non-linear-arithmetic] on precisely those goals
  which are stable-under-simplificationp.  It also uses the ~c[HISTORY] and
  ~c[PSPV] variables to determine when toggling ~il[non-linear-arithmetic] is
  appropriate.  These variables are documented only in the source code.  If
  you start using these variables extensively, please contact the developers
  of ACL2 or Robert Krug (~c[rkrug@cs.utexas.edu]) and let us know how we can
  help.

  ~bv[]
  (defun nonlinearp-default-hint (stable-under-simplificationp hist pspv)
    (cond (stable-under-simplificationp
           (if (not (access rewrite-constant
                            (access prove-spec-var pspv :rewrite-constant)
                            :nonlinearp))
               '(:computed-hint-replacement t
                 :nonlinearp t)
             nil))
          ((access rewrite-constant
                   (access prove-spec-var pspv :rewrite-constant)
                   :nonlinearp)
           (if (not (equal (caar hist) 'SETTLED-DOWN-CLAUSE))
               '(:computed-hint-replacement t
                 :nonlinearp nil)
             nil))
          (t
           nil)))
  ~ev[]")
  
(deflabel using-computed-hints-8
  :doc
  ":Doc-Section Miscellaneous

  Some Final Comments~/

  None of the examples show the use of the variable ~c[WORLD], which is
  allowed in computed hints.  There are some (undocumented) ACL2
  utilities that might be useful in programming hints, but these
  utilities need access to the ACL2 logical world (~pl[world]).

  A very useful fact to know is that ~c[(table-alist name world)]
  returns an alist representation of the current value of the ~ilc[table]
  named ~c[name].

  The ACL2 source code is littered with ~c[:]~ilc[program] mode 
  functions for manipulating world.  In our source code, the
  world is usually bound a variable named ~c[wrld]; so searching
  our code for that name might be helpful.~/

  Using these utilities to look at the ~c[WORLD] one can, for example,
  determine whether a symbol is defined recursively or not, get the
  body and formals of a defined function, or fetch the statement of a
  given lemma.  Because these utilities are not yet documented, we do
  not expect users to employ ~c[WORLD] in computed hints.  But experts
  might and it might lead to the formulation of a more convenient
  language for computed hints.

  None of our examples illustrated the 7 argument form of a computed
  hint, 
  ~c[(fn ID CLAUSE WORLD STABLE-UNDER-SIMPLIFICATIONP HIST PSPV CTX)].
  When used, the variables ~c[HIST], ~c[PSPV], and ~c[CTX], are bound
  to the clause history, the package of ``special variables'' governing
  the clause, and the ``error message context.''  These variables are
  commonly used throughout our source code but are, unfortunately,
  undocumented.  Again, we expect a few experts will find them useful
  in developing computed hints.

  If you start using computed hints extensively, please contact the
  developers of ACL2 and let us know what you are doing with them and
  how we can help.")

(deflabel using-computed-hints
  :doc
  ":Doc-Section Miscellaneous

  how to use computed hints~/

  Computed hints (~pl[computed-hints]) are extraordinarily powerful.
  We show a few examples here to illustrate their use.  We recommend
  that the ~c[using-computed-hints-n] topics be read in the order
  ~c[using-computed-hints-1], ~c[using-computed-hints-2], and so on.
  ~/~/

  :CITE using-computed-hints-1
  :CITE using-computed-hints-2
  :CITE using-computed-hints-3
  :CITE using-computed-hints-4
  :CITE using-computed-hints-5
  :CITE using-computed-hints-6
  :CITE using-computed-hints-7
  :CITE set-default-hints
  :CITE add-default-hints
  :CITE remove-default-hints
  :CITE using-computed-hints-8")

; Essay on Trust Tags (Ttags)

; Here we place the bulk of the code for handling trust tags (ttags).

; A trust tag (ttag) is a symbol that represents where to place responsibility
; for potentially unsafe operations.  For example, suppose we define a
; function, foo, that calls sys-call.  Any call of sys-call is potentially
; unsafe, in the sense that it can do things not normally expected during book
; certification, such as overwriting a file or a core image.  But foo's call of
; sys-call may be one that can be explained somehow as safe.  At any rate,
; translate11 allows this call of sys-call if there is an active trust tag
; (ttag), in the sense that the key :ttag is bound to a non-nil value in the
; acl2-defaults-table.  See :doc defttag for more on ttags, in particular, the
; ``TTAG NOTE'' mechanism for determining which files need to be inspected in
; order to validate the proper use of ttags.

; There is a subtlety to the handling of trust tags by include-book in the case
; of uncertified books.  Consider the following example.  We have two books,
; sub.lisp and top.lisp, but we will be considering two versions of sub.lisp,
; as indicated.

; sub.lisp
; (in-package "ACL2")
; ; (defttag :sub-ttag1) ; will be uncommented later
; (defun f (x) x)

; top.lisp
; (in-package "ACL2")
; (encapsulate
;  () ;; start lemmas for sub
; 
;  (include-book "sub")
;  )

; Now take the following steps:

; In a fresh ACL2 session:
; (certify-book "sub")
; (u)
; (certify-book "top")

; Now edit sub.lisp by uncommenting the defttag form.  Then, in a fresh ACL2
; session:
; (certify-book "sub" 0 t :ttags :all)
; (u)
; (include-book "top")

; The (include-book "top") form will fail when the attempt is made to include
; the book "sub".  To see why, first consider what happens when a superior book
; "top" includes a subsidiary certified book "sub".  When include-book-fn1 is
; called in support of including "sub", the second call of
; chk-acceptable-ttags1 therein uses the certificate's ttags, stored in
; variable cert-ttags, to refine the state global 'ttags-allowed.  After that
; check and refinement, which prints ttag notes based on cert-ttags,
; ttags-allowed is bound to cert-ttags for the inclusion of "sub", with further
; ttag notes omitted during that inclusion.

; Returning to our example, the recertification of "sub" results in the
; addition of a ttag for "sub" that has not yet been noticed for "top".  So
; when we include "top", state global ttags-allowed is bound to nil, since that
; is the cert-ttags for "top".  When sub is encountered, its additional ttag is
; not allowed (because ttags-allowed is nil), and we get an error.

; In a way, this error is unfortunate; after all, top is uncertified, and we
; wish to allow inclusion of uncertified books (with a suitable warning).  But
; it seems non-trivial to re-work the scheme described above.  In particular,
; it seems that we would have to avoid binding ttags-allowed to nil when
; including "top", before we realize that "top" is uncertified.  (The check on
; sub-book checksums occurs after events are processed.)  We could eliminate
; this "barrier" under which we report no further ttag notes, but that could
; generate a lot of ttag notes -- even if we defer, we may be tempted to print
; a note for each defttag encountered in a different sub-book.

; That said, if the need is great enough for us to avoid the error described
; above, we'll figure out something.

(defmacro ttags-seen ()

; The following is a potentially useful utility, which we choose to include in
; the ACL2 sources rather than in books/hacking/hacker.lisp.  Thanks to Peter
; Dillinger for his contribution.

  ":Doc-Section Miscellaneous

  list some declared trust tags (ttags)~/
  ~bv[]
  General Forms:
  :ttags-seen
  (ttags-seen)
  ~ev[]
  Suppose the output is as follows.
  ~bv[]
  (T NIL)
  (FOO \"/home/bob/bar.lisp\"
       \"/home/cindy/bar.lisp\")
  Warning: This output is minimally trustworthy (see :DOC TTAGS-SEEN).
  ~ev[]
  This output indicates that the current logical ~il[world] has seen the
  declaration of trust tag ~c[T] at the top-level (~pl[defttag]) and the
  declaration of trust tag ~c[FOO] in the two books included from the listed
  locations.  The warning emphasizes that this command cannot be used to
  validate the ``purity'' of an ACL2 session, because using a ttag renders
  enough power to hide from this or any other command the fact that the ttag
  was ever declared.~/

  As discussed elsewhere (~pl[defttag]), the only reliable way to validate
  the ``purity'' of a session is to watch for ``~c[TTAG NOTE]'' output.

  Another shortcoming of this command is that it only checks the current
  logical ~il[world] for ttag declarations.  For example, one could execute a
  ~ilc[defttag] event; then use ~ilc[progn!] and ~ilc[set-raw-mode] to replace
  system functions with corrupt definitions or to introduce inconsistent axioms
  in the ~ilc[ground-zero] ~il[world]; and finally, execute
  ~c[:]~ilc[ubt!]~c[ 1] to remove all evidence of the ttag in the ~il[world]
  while leaving in place the corrupt definitions or axioms.  The base world is
  now tainted, meaning we could prove ~c[nil] or certify a book that proves
  ~c[nil], but the resulting session or book would contain no trace of the ttag
  that tainted it!

  Despite shortcomings, this command might be useful to system hackers.  It
  also serves to illustrate the inherent flaw in asking a session whether or
  how it is ``tainted'', justifying the ``~c[TTAG NOTE]'' approach
  (~pl[defttag])."

  '(mv-let (col state)
           (fmt1 "~*0Warning: This output is minimally trustworthy (see :DOC ~
                  ~x1).~%"
                 `((#\0 "<no ttags seen>~%" "~q*" "~q*" "~q*"
                        ,(global-val 'ttags-seen (w state)))
                   (#\1 . ttags-seen))
                 0 (standard-co state) state ())
           (declare (ignore col))
           (value ':invisible)))

(defun active-book-name (wrld state)

; This returns the full book name (an absolute pathname ending in .lisp) of the
; book currently being included, if any.  Otherwise, this returns the full book
; name of the book currently being certified, if any.

  (or (car (global-val 'include-book-path wrld))
      (let ((x (f-get-global 'certify-book-info state)))
        (cond (x (let ((y (if (consp x) (car x) x)))
                   (assert$ (stringp y) y)))))))

(defrec deferred-ttag-note
  (val active-book-name . include-bookp)
  t)

(defun fms-to-standard-co (str alist state evisc-tuple)

; Warning: This function is used for printing ttag notes, so do not change
; *standard-co*, not even to (standard-co state)!

  (fms str alist *standard-co* state evisc-tuple))

(defun print-ttag-note (val active-book-name include-bookp deferred-p state)
  (pprogn
   (let* ((filename (or active-book-name ""))
          (included (if include-bookp
                        " (for included book)"
                      ""))
          (str (if active-book-name
                   "TTAG NOTE~s0: Adding ttag ~x1 from file ~s2."
                 "TTAG NOTE~s0: Adding ttag ~x1 from the top level loop."))
          (bound (+ (length included)
                    (length str)
                    (length (symbol-package-name val))
                    2 ; for "::"
                    (length (symbol-name val))
                    (length filename))))
     (mv-let (erp val state)
             (state-global-let*
              ((fmt-hard-right-margin bound set-fmt-hard-right-margin)
               (fmt-soft-right-margin bound set-fmt-soft-right-margin))
              (pprogn (fms-to-standard-co str
                                          (list (cons #\0 included)
                                                (cons #\1 val)
                                                (cons #\2 filename))
                                          state nil)
                      (cond (deferred-p state)
                            (t (newline *standard-co* state)))
                      (value nil)))
             (declare (ignore erp val))
             state))
   (cond ((and (consp include-bookp) ; (cons ctx full-book-name)
               (not deferred-p))
          (warning$ (car include-bookp) ; ctx
                    "Ttags"
                    "The ttag note just printed to the terminal indicates a ~
                     modification to ACL2.  To avoid this warning, supply an ~
                     explicit :TTAGS argument when including the book ~x0."
                    (cdr include-bookp) ; full-book-name
                    ))
         (t state))))

(defun show-ttag-notes1 (notes state)
  (cond ((endp notes)
         (newline *standard-co* state))
        (t (pprogn (let ((note (car notes)))
                     (print-ttag-note
                      (access deferred-ttag-note note :val)
                      (access deferred-ttag-note note :active-book-name)
                      (access deferred-ttag-note note :include-bookp)
                      t
                      state))
                   (show-ttag-notes1 (cdr notes) state)))))

(defun show-ttag-notes-fn (state)
  (let* ((notes0 (f-get-global 'deferred-ttag-notes-saved state))
         (notes (remove-duplicates-equal notes0)))
    (cond (notes
           (pprogn (cond ((equal notes notes0)
                          state)
                         (t (fms-to-standard-co
                             "Note: Duplicates have been removed from the ~
                              list of deferred ttag notes before printing ~
                              them below.~|"
                             nil state nil)))
                   (show-ttag-notes1 (reverse notes) state)
                   (f-put-global 'deferred-ttag-notes-saved nil state)))
          (t (fms-to-standard-co
              "All ttag notes have already been printed.~|"
              nil state nil)))))

(defmacro show-ttag-notes ()
  '(pprogn (show-ttag-notes-fn state)
           (value :invisible)))

(defun set-deferred-ttag-notes (val state)

  ":Doc-Section switches-parameters-and-modes

  modify the verbosity of ~c[TTAG NOTE] printing~/

  ~bv[]
  General Form:
  (set-deferred-ttag-notes val state)
  ~ev[]
  where ~c[val] is ~c[t] or ~c[nil].~/

  ~l[defttag] for a discussion of trust tags (ttags).  By default, a
  ``~c[TTAG NOTE]'' is printed in order to indicate reliance on a ttag.  When
  many such notes are printed, it may be desirable to avoid seeing them all.
  Upon evaluation of the form
  ~bv[]
  (set-deferred-ttag-notes t state)
  ~ev[]
  ACL2 will enter a deferred mode for the printing of ttag notes.  In this
  mode, only the first ttag note is printed for each top-level command, and the
  remainder are summarized before the next top-level prompt (if any) is
  printed, hence before the next command is evaluated.  That summary is merely
  a list of ttags, but the summary explains that the full ttag notes may be
  printed with the command ~c[(show-ttag-notes)].

  Note that ~c[(show-ttag-notes)] spares you duplicate ttag notes.  If you want
  to see every ttag note as it would normally appear, for maximum security, do
  not evaluate the command ~c[(set-deferred-ttag-notes t state)].  You can undo
  the effect of this command, returning to an immediate mode for printing ttag
  notes, by evaluating:
  ~bv[]
  (set-deferred-ttag-notes nil state)
  ~ev[]"

  (let ((ctx 'set-deferred-ttag-notes)
        (immediate-p (not val)))
    (cond
     ((member-eq val '(t nil))
      (pprogn
       (cond ((eq immediate-p
                  (eq (f-get-global 'deferred-ttag-notes state)
                      :not-deferred))
              (observation ctx
                           "No change; ttag notes are already ~@0being ~
                            deferred."
                           (if immediate-p
                               "not "
                             "")))
             ((and immediate-p
                   (consp (f-get-global 'deferred-ttag-notes state)))
              (pprogn (fms-to-standard-co
                       "Note: Enabling immediate printing mode for ttag ~
                        notes.  Below are the ttag notes that have been ~
                        deferred without being reported."
                       nil state nil)
                      (f-put-global 'deferred-ttag-notes-saved
                                    (f-get-global 'deferred-ttag-notes state)
                                    state)
                      (f-put-global 'deferred-ttag-notes
                                    nil
                                    state)
                      (show-ttag-notes-fn state)))
             (immediate-p
              (pprogn
               (observation ctx
                            "Enabling immediate printing mode for ttag notes.")
               (f-put-global 'deferred-ttag-notes
                             :not-deferred
                             state)
               (f-put-global 'deferred-ttag-notes-saved
                             nil
                             state)))
             (t
              (pprogn (fms-to-standard-co
                       "TTAG NOTE: Printing of ttag notes is being put into ~
                        deferred mode.~|"
                       nil state nil)
                      (f-put-global 'deferred-ttag-notes
                                    :empty
                                    state))))
       (value :invisible)))
     (t (er soft ctx
            "The only legal values for set-deferred-ttag-notes are ~x0 and ~
             ~x1. ~ The value ~x2 is thus illegal."
            t nil val)))))

(defun ttags-from-deferred-ttag-notes1 (notes)

; Notes is formed by pushing ttag notes, hence we want to consider the
; corresponding ttags in reverse order.  But we'll want to reverse this
; result.

  (cond ((endp notes) nil)
        (t (add-to-set-eq (access deferred-ttag-note (car notes) :val)
                          (ttags-from-deferred-ttag-notes1 (cdr notes))))))

(defun ttags-from-deferred-ttag-notes (notes)
  (reverse (ttags-from-deferred-ttag-notes1 notes)))

(defun print-deferred-ttag-notes-summary (state)
  (let ((notes (f-get-global 'deferred-ttag-notes state)))
    (cond
     ((null notes)
      (f-put-global 'deferred-ttag-notes :empty state))
     ((atom notes) ; :empty or :not-deferred
      state)
     (t (pprogn (f-put-global 'deferred-ttag-notes-saved notes state)
                (fms-to-standard-co
                 "TTAG NOTE: Printing of ttag notes has been deferred for the ~
                  following list of ttags:~|  ~y0.To print the deferred ttag ~
                  notes:  ~y1."
                 (list (cons #\0 (ttags-from-deferred-ttag-notes notes))
                       (cons #\1 '(show-ttag-notes)))
                 state nil)
                (f-put-global 'deferred-ttag-notes :empty state))))))

(defun notify-on-defttag (val active-book-name include-bookp state)

; Warning: Here we must not call observation or any other printing function
; whose output can be inhibited.  The tightest security for ttags is obtained
; by searching for "TTAG NOTE" strings in the output.

  (cond
   ((or (f-get-global 'skip-notify-on-defttag state)
        (eq include-bookp :quiet))
    state)
   ((and (null include-bookp)
         (equal val (ttag (w state))))
; Avoid some noise, e.g. in encapsulate when there is already an active ttag.
    state)
   ((eq (f-get-global 'deferred-ttag-notes state)
        :not-deferred)
    (print-ttag-note val active-book-name include-bookp nil state))
   ((eq (f-get-global 'deferred-ttag-notes state)
        :empty)
    (pprogn (print-ttag-note val active-book-name include-bookp nil state)
            (f-put-global 'deferred-ttag-notes nil state)))
   (t
    (pprogn
     (cond ((null (f-get-global 'deferred-ttag-notes state))
            (fms-to-standard-co
             "TTAG NOTE: Deferring one or more ttag notes until the current ~
              top-level command completes.~|"
             nil state nil))
           (t state))
     (f-put-global 'deferred-ttag-notes
                   (cons (make deferred-ttag-note
                               :val val
                               :active-book-name active-book-name
                               :include-bookp include-bookp)
                         (f-get-global 'deferred-ttag-notes state))
                   state)))))

(defun ttag-allowed-p (ttag ttags active-book-name acc)

; We are executing a defttag event (or more accurately, a table event that
; could correspond to a defttag event).  We return nil if the ttag is illegal,
; else t if no update to ttags is required, else a new, more restrictive value
; for ttags that recognizes the association of ttag with active-book-name.

  (cond ((endp ttags)
         nil)
        ((eq ttag (car ttags))
         (revappend acc
                    (cons (list ttag active-book-name)
                          (cdr ttags))))
        ((atom (car ttags))
         (ttag-allowed-p ttag (cdr ttags) active-book-name
                         (cons (car ttags) acc)))
        ((eq ttag (caar ttags))
         (cond ((or (null (cdar ttags))
                    (member-equal active-book-name (cdar ttags)))
                t)
               (t nil)))
        (t (ttag-allowed-p ttag (cdr ttags) active-book-name
                           (cons (car ttags) acc)))))

(defun chk-acceptable-ttag1 (val active-book-name ttags-allowed ttags-seen
                                 include-bookp ctx state)

; An error triple (mv erp pair state) is returned, where if erp is nil then
; pair is either of the form (ttags-allowed1 . ttags-seen1), indicating a
; refined value for ttags-allowed and an extended value for ttags-seen, else is
; nil, indicating no such update.  By a "refined value" above, we mean that if
; val is a symbol then it is replaced in ttags-allowed by (val
; active-book-name).  However, val may be of the form (symbol), in which case
; no refinement takes place, or else of the form (symbol . filenames) where
; filenames is not nil, in which case active-book-name must be a member of
; filenames or we get an error.  Active-book-name is nil, representing the top
; level, or a string, generally thought of as an absolute filename.

; This function must be called if we are to add a ttag.  In particular, it
; should be called under table-fn; it would be a mistake to call this only
; under defttag, since then one could avoid this function by calling table
; directly.

; This function is where we call notify-on-defttag, which prints strings that
; provide the surest way for someone to check that functions requiring ttags
; are being called in a way that doesn't subvert the ttag mechanism.

  (let* ((ttags-allowed0 (cond ((eq ttags-allowed :all)
                                t)
                               (t (ttag-allowed-p val ttags-allowed
                                                  active-book-name nil))))
         (ttags-allowed1 (cond ((eq ttags-allowed0 t)
                                ttags-allowed)
                               (t ttags-allowed0))))
    (cond
     ((not ttags-allowed1)
      (er soft ctx
          "The ttag ~x0 associated with ~@1 is not among the set of ttags ~
           permitted in the current context, specified as follows:~|  ~
           ~x2.~|See :DOC defttag.~@3"
          val
          (if active-book-name
              (msg "file ~s0" active-book-name)
            "the top level loop")
          ttags-allowed
          (cond
           ((null (f-get-global 'skip-notify-on-defttag state))
            "")
           (t
            (msg "  This error is unusual since it is occurring while ~
                  including a book that appears to have been certified, in ~
                  this case, the book ~x0.  Most likely, that book needs to ~
                  be recertified, though a temporary workaround may be to ~
                  delete its certificate (i.e., its .cert file).  Otherwise ~
                  see :DOC make-event-details, section ``A note on ttags,'' ~
                  for a possible explanation."
                 (f-get-global 'skip-notify-on-defttag state))))))
     (t
      (pprogn
       (notify-on-defttag val active-book-name include-bookp state)
       (let ((old-filenames (cdr (assoc-eq val ttags-seen))))
         (cond
          ((member-equal active-book-name old-filenames)
           (value (cons ttags-allowed1 ttags-seen)))
          (t
           (value (cons ttags-allowed1
                        (put-assoc-eq val
                                      (cons active-book-name old-filenames)
                                      ttags-seen)))))))))))

(defun chk-acceptable-ttag (val include-bookp ctx wrld state)

; See the comment in chk-acceptable-ttag1, which explains the result for the
; call of chk-acceptable-ttag1 below.

  (cond
   ((null val)
    (value nil))
   (t
    (chk-acceptable-ttag1 val
                          (active-book-name wrld state)
                          (f-get-global 'ttags-allowed state)
                          (global-val 'ttags-seen wrld)
                          include-bookp ctx state))))

(defun chk-acceptable-ttags2 (ttag filenames ttags-allowed ttags-seen
                                   include-bookp ctx state)
  (cond ((endp filenames)
         (value (cons ttags-allowed ttags-seen)))
        (t (er-let* ((pair (chk-acceptable-ttag1 ttag (car filenames)
                                                 ttags-allowed ttags-seen
                                                 include-bookp ctx state)))
                    (mv-let (ttags-allowed ttags-seen)
                            (cond ((null pair)
                                   (mv ttags-allowed ttags-seen))
                                  (t (mv (car pair) (cdr pair))))
                            (chk-acceptable-ttags2 ttag (cdr filenames)
                                                   ttags-allowed ttags-seen
                                                   include-bookp ctx
                                                   state))))))

(defun chk-acceptable-ttags1 (vals active-book-name ttags-allowed ttags-seen
                                   include-bookp ctx state)

; See chk-acceptable-ttag1 for a description of the value returned based on the
; given active-book-name, tags-allowed, and ttags-seen.  Except, for this
; function, an element of vals can be a pair (tag . filenames), in which case
; active-book-name is irrelevant, as it is replaced by each filename in turn.
; If every element of vals has that form then active-book-name is irrelevant.

  (cond ((endp vals)
         (value (cons ttags-allowed ttags-seen)))
        (t (er-let* ((pair
                      (cond ((consp (car vals))
                             (chk-acceptable-ttags2 (caar vals) (cdar vals)
                                                    ttags-allowed ttags-seen
                                                    include-bookp ctx state))
                            (t
                             (chk-acceptable-ttag1 (car vals) active-book-name
                                                   ttags-allowed ttags-seen
                                                   include-bookp ctx state)))))
                    (mv-let (ttags-allowed ttags-seen)
                            (cond ((null pair)
                                   (mv ttags-allowed ttags-seen))
                                  (t (mv (car pair) (cdr pair))))
                            (chk-acceptable-ttags1 (cdr vals) active-book-name
                                                   ttags-allowed ttags-seen
                                                   include-bookp ctx
                                                   state))))))

(defun chk-acceptable-ttags (vals include-bookp ctx wrld state)

; See chk-acceptable-ttag1 for a description of the value returned based on the
; current book being included (if any), the value of state global
; 'tags-allowed, and the value of world global 'ttags-seen.

  (chk-acceptable-ttags1 vals
                         (active-book-name wrld state)
                         (f-get-global 'ttags-allowed state)
                         (global-val 'ttags-seen wrld)
                         include-bookp ctx state))

; Next we handle the table event.  We formerly did this in other-events.lisp,
; but in v2-9 we moved it here, in order to avoid a warning in admitting
; add-pc-command-1 that the *1* function for table-fn is undefined.

(defun chk-table-nil-args (op bad-arg bad-argn ctx state)

; See table-fn1 for representative calls of this weird little function.

  (cond (bad-arg
         (er soft ctx
             "Table operation ~x0 requires that the ~n1 argument to ~
              TABLE be nil.  Hence, ~x2 is an illegal ~n1 argument.  ~
              See :DOC table."
             op bad-argn bad-arg))
        (t (value nil))))

(defun chk-table-guard (name key val ctx wrld state)

; This function returns an error triple.  In the non-error case, the value is
; nil except when it is a pair as described in chk-acceptable-ttag1, based on
; the current book being included (if any), the value of state global
; 'tags-allowed, and the value of world global 'ttags-seen.

  (cond
   ((and (eq name 'acl2-defaults-table)
         (eq key :include-book-dir-alist)
         (not (f-get-global 'modifying-include-book-dir-alist state)))
    (er soft ctx
        "Illegal attempt to set the :include-book-dir-alist field of the ~
         acl2-defaults-table.  This can only be done by calling ~
         add-include-book-dir or delete-include-book-dir."))
   (t (let ((term (getprop name 'table-guard *t* 'current-acl2-world wrld)))
        (er-progn
         (mv-let
          (erp okp latches)
          (ev term
              (list (cons 'key key)
                    (cons 'val val)
                    (cons 'world wrld))
              state nil nil nil)
          (declare (ignore latches))
          (cond
           (erp (pprogn
                 (error-fms nil ctx (car okp) (cdr okp) state)
                 (er soft ctx
                     "The TABLE :guard for ~x0 on the key ~x1 and value ~x2 ~
                      could not be evaluated."
                     name key val)))
           (okp (value nil))
           (t (er soft ctx
                  "The TABLE :guard for ~x0 disallows the combination of key ~
                   ~x1 and value ~x2.  The :guard is ~x3.  See :DOC table."
                  name key val (untranslate term t wrld)))))
         (if (and (eq name 'acl2-defaults-table)
                  (eq key :ttag))
             (chk-acceptable-ttag val nil ctx wrld state)
           (value nil)))))))

(defun chk-table-guards-rec (name alist ctx pair wrld state)
  (if alist
      (er-let* ((new-pair (chk-table-guard name (caar alist) (cdar alist) ctx
                                           wrld state)))
               (if (and pair new-pair)
                   (assert$ (and (eq name 'acl2-defaults-table)
                                 (eq (caar alist) :ttag))
                            (er soft ctx
                                "It is illegal to specify the :ttag twice in ~
                                 the acl2-defaults-table."))
                 (chk-table-guards-rec name (cdr alist) ctx new-pair wrld
                                       state)))
    (value pair)))

(defun chk-table-guards (name alist ctx wrld state)

; Consider the case that name is 'acl2-defaults-table.  We do not allow a
; transition from a non-nil (ttag wrld) to a nil (ttag wrld) at the top level,
; but no such check will be made by chk-table-guard if :ttag is not bound in
; alist.  See chk-acceptable-ttag.

  (er-let* ((pair (cond ((and (eq name 'acl2-defaults-table)
                              (null (assoc-eq :ttag alist)))
                         (chk-acceptable-ttag nil nil ctx wrld state))
                        (t (value nil)))))
            (chk-table-guards-rec name alist ctx pair wrld state)))

(defun put-assoc-equal-fast (name val alist)

; If there is a large number of table events for a given table all with
; different keys, the use of assoc-equal to update the table (in table-fn1)
; causes a quadratic amount of cons garbage.  The following is thus used
; instead.

  (declare (xargs :guard (alistp alist)))
  (if (assoc-equal name alist)
      (put-assoc-equal name val alist)
    (acons name val alist)))

(defun global-set? (var val wrld old-val)
  (if (equal val old-val)
      wrld
    (global-set var val wrld)))

(defun cltl-def-from-name2 (fn stobj-function axiomatic-p wrld)

; Normally we expect to find the cltl definition of fn at the first
; 'cltl-command 'global-value triple.  But if fn is introduced by encapsulate
; then we may have to search further.  Try this, for example:

; (encapsulate ((f (x) x))
;              (local (defun f (x) x))
;              (defun g (x) (f x)))
; (cltl-def-from-name 'f nil (w state))

  (cond ((endp wrld)
         nil)
        ((and (eq 'cltl-command (caar wrld))
              (eq 'global-value (cadar wrld))
              (let ((cltl-command-value (cddar wrld)))
                (assoc-eq fn
                          (if stobj-function
                              (nth (if axiomatic-p 6 4)
                                   cltl-command-value)
                            (cdddr cltl-command-value))))))
        (t (cltl-def-from-name2 fn stobj-function axiomatic-p (cdr wrld)))))

(defun cltl-def-from-name1 (fn stobj-function axiomatic-p wrld)

; See cltl-def-from-name, which is a wrapper for this function in which
; axiomatic-p is nil.  When axiomatic-p is t, then we are to return a function
; suitable for oneify, which in the stobj case is the axiomatic definition
; rather than the raw Lisp definition.

  (and (function-symbolp fn wrld)
       (let* ((event-number (getprop (or stobj-function fn) 'absolute-event-number
                                     nil 'current-acl2-world wrld))
              (wrld (and event-number
                         (lookup-world-index 'event event-number wrld)))
              (def (and wrld
                        (cltl-def-from-name2 fn stobj-function axiomatic-p wrld))))
         (and def
              (or (null stobj-function)
                  (not (member-equal *stobj-inline-declare* def)))
              (cons 'defun def)))))

(defun cltl-def-from-name (fn stobj-function wrld)

; If fn does not have a 'stobj-function property in wrld, then this function
; returns the raw Lisp definition of fn, which is also the definition that is
; oneified to create the corresponding *1* function.

; But suppose that fn does have a 'stobj-function property in wrld.  If
; stobj-function is non-nil, it should be that property, and we use it to
; return the raw Lisp definition of fn.

  (cltl-def-from-name1 fn stobj-function nil wrld))

(defun table-cltl-cmd (name key val op ctx wrld)

; WARNING: For the case that name is 'memoize-table, keep this in sync with
; memoize-fn.

; Currently this function returns nil if name is 'memoize-table except in a
; hons-enabled (#+hons) version, because memoize-table has a table guard of nil
; (actually a hard-error call) in the #-hons version.

  (let ((unsupported-str
         "Unsupported operation, ~x0, for updating table ~x1."))
    (case name
      (memoize-table
       (cond ((eq op :guard) nil)
             ((not (eq op :put))
              (er hard ctx unsupported-str op name))
             (val

; We store enough in the cltl-cmd so that memoize-fn can be called (by
; add-trip) without having to consult the world.  This is important because in
; the hons version of Version_3.3, hence before we stored the cl-defun and
; condition-defun in this cltl-cmd tuple, we saw an error in the following, as
; explained below.

; (defun foo (x) (declare (xargs :guard t)) x)
; (defun bar (x) (declare (xargs :guard t)) x)
; (progn (defun foo-memoize-condition (x)
;          (declare (xargs :guard t))
;          (eq x 'term))
;        (table memoize-table 'foo (list 'foo-memoize-condition 't 'nil))
;        (progn (defun h (x) x)
;               (defun bar (x) (cons x x))))

; Why did this cause an error?  The problem was that when restoring the world
; from after bar up to the inner progn (due to its protection by
; revert-world-on-error), memoize-fn was calling cltl-def-from-name on (w
; *the-live-state*), but this world did not contain enough information for that
; call.  (Note that set-w! calls find-longest-common-retraction with event-p =
; nil in that case, which is why we roll back to the previous command, not
; event.  We might consider rolling back to the previous event in all cases,
; not just when certifying or including a book.  But perhaps that's risky,
; since one can execute non-events like defuns-fn in the look that one cannot
; execute in a book without a trust tag (or in make-event; hmmmm...).)

; See add-trip for a call of memoize-fn using the arguments indicated below.
; We have seen an error result due to revert-world-on-error winding back to a
; command landmark.  See set-w! for a comment about this, which explains how
; problem was fixed after Version_3.6.1.  However, we prefer to fix the problem
; here as well, by avoiding the call of cltl-def-from-name in memoize-fn that
; could be attempting to get a name during extend-world1 from a world not yet
; installed.  So we make that call here, just below, and store the result in
; the cltl-command tuple.

              (let* ((condition-fn (cdr (assoc-eq :condition-fn val)))
                     (condition-def (and condition-fn
                                         (not (eq condition-fn t))
                                         (cltl-def-from-name condition-fn
                                                             nil
                                                             wrld)))
                     (condition (or (eq condition-fn t) ; hence t
                                    (and condition-def
                                         (or (car (last condition-def))
                                             nil)))))
                `(memoize ,key ; fn
                          ,condition
                          ,(cdr (assoc-eq :inline val))
                          ,(cdr (assoc-eq :trace val))
                          ,(cltl-def-from-name key nil wrld) ; cl-defun
                          ,(getprop key 'formals t 'current-acl2-world
                                    wrld) ; formals
                          ,(getprop key 'stobjs-in t 'current-acl2-world
                                    wrld) ; stobjs-in
                          ,(getprop key 'stobjs-out t 'current-acl2-world

; Normally we would avoid getting the stobjs-out of return-last.  But
; return-last is rejected for mamoization anyhow (by memoize-table-chk).

                                    wrld) ; stobjs-out
                          ,(and (symbolp condition)
                                condition
                                (not (eq condition t))
                                (cltl-def-from-name
                                 condition nil wrld)) ; condition-defun
                          ,(and (cdr (assoc-eq :commutative val)) t)
                          ,(cdr (assoc-eq :forget val))
                          ,(cdr (assoc-eq :memo-table-init-size val))
                          ,(cdr (assoc-eq :aokp val)))))
             (t `(unmemoize ,key))))
      (t nil))))

(defun table-fn1 (name key val op term ctx wrld state event-form)

; Warning: If the table event ever generates proof obligations, remove it from
; the list of exceptions in install-event just below its "Comment on
; irrelevance of skip-proofs".

; This is just the rational version of table-fn, with key, val, op and
; term all handled as normal (evaluated) arguments.  The chart in
; table-fn explains the legal ops and arguments.

  (case op
        (:alist 
         (er-progn
          (chk-table-nil-args :alist
                              (or key val term)
                              (cond (key '(2)) (val '(3)) (t '(5)))
                              ctx state)
          (value (table-alist name wrld))))
        (:get
         (er-progn
          (chk-table-nil-args :get
                              (or val term)
                              (cond (val '(3)) (t '(5)))
                              ctx state)
          (value
           (cdr (assoc-equal key
                             (getprop name 'table-alist nil
                                      'current-acl2-world wrld))))))
        (:put
         (with-ctx-summarized
          (if (output-in-infixp state) event-form ctx)
          (let* ((tbl (getprop name 'table-alist nil
                               'current-acl2-world wrld)))
            (er-progn
             (chk-table-nil-args :put term '(5) ctx state)
             (cond
              ((let ((pair (assoc-equal key tbl)))
                 (and pair (equal val (cdr pair))))
               (stop-redundant-event ctx state))
              (t (er-let*
                  ((pair (chk-table-guard name key val ctx wrld state))
                   (wrld1 (cond
                           ((null pair)
                            (value wrld))
                           (t (let ((ttags-allowed1 (car pair))
                                    (ttags-seen1 (cdr pair)))
                                (pprogn (f-put-global 'ttags-allowed
                                                      ttags-allowed1
                                                      state)
                                        (value (global-set?
                                                'ttags-seen
                                                ttags-seen1
                                                wrld
                                                (global-val 'ttags-seen
                                                            wrld)))))))))
                  (install-event
                   name
                   event-form
                   'table
                   0
                   nil
                   (table-cltl-cmd name key val op ctx wrld)
                   nil ; theory-related events do their own checking
                   nil
                   (putprop name 'table-alist
                            (put-assoc-equal-fast
                             key val tbl)
                            wrld1)
                   state))))))))
        (:clear
         (with-ctx-summarized
          (if (output-in-infixp state) event-form ctx)
          (er-progn
           (chk-table-nil-args :clear
                               (or key term)
                               (cond (key '(2)) (t '(5)))
                               ctx state)
           (cond
            ((equal val (table-alist name wrld))
             (stop-redundant-event ctx state))
            ((not (alistp val))
             (er soft 'table ":CLEAR requires an alist, but ~x0 is not." val))
            (t
             (let ((val (if (duplicate-keysp val)
                            (reverse (clean-up-alist val nil))
                          val)))
               (er-let*
                ((wrld1
                  (er-let* ((pair (chk-table-guards name val ctx wrld state)))
                           (cond
                            ((null pair)
                             (value wrld))
                            (t (let ((ttags-allowed1 (car pair))
                                     (ttags-seen1 (cdr pair)))
                                 (pprogn (f-put-global 'ttags-allowed
                                                       ttags-allowed1
                                                       state)
                                         (value (global-set? 'ttags-seen
                                                             ttags-seen1
                                                             wrld
                                                             (global-val
                                                              'ttags-seen 
                                                              wrld))))))))))
                (install-event name event-form 'table 0 nil
                               (table-cltl-cmd name key val op ctx wrld)
                               nil ; theory-related events do their own checking
                               nil
                               (putprop name 'table-alist val wrld1)
                               state))))))))
        (:guard
         (cond
          ((eq term nil)
           (er-progn
            (chk-table-nil-args op
                                (or key val)
                                (cond (key '(2)) (t '(3)))
                                ctx state)
            (value (getprop name 'table-guard *t* 'current-acl2-world wrld))))
          (t
           (with-ctx-summarized
            (if (output-in-infixp state) event-form ctx)
            (er-progn
             (chk-table-nil-args op
                                 (or key val)
                                 (cond (key '(2)) (t '(3)))
                                 ctx state)
             (er-let* ((tterm (translate term '(nil) nil nil ctx wrld state)))

; known-stobjs = nil.  No variable is treated as a stobj in tterm.
; But below we check that the only vars mentioned are KEY, VAL and
; WORLD.  These could, in principle, be declared stobjs by the user.
; But when we ev tterm in the future, we will always bind them to
; non-stobjs.

                      (let ((old-guard
                             (getprop name 'table-guard nil
                                      'current-acl2-world wrld)))
                        (cond
                         ((equal old-guard tterm)
                          (stop-redundant-event ctx state))
                         (old-guard
                          (er soft ctx
                              "It is illegal to change the :guard on a table ~
                               after it has been given an explicit :guard.  ~
                               The :guard of ~x0 is ~x1 and this can be ~
                               changed only by undoing the event that set it.  ~
                               See :DOC table."
                              name
                              (untranslate (getprop name 'table-guard nil
                                                    'current-acl2-world wrld)
                                           t wrld)))
                         ((getprop name 'table-alist nil
                                   'current-acl2-world wrld)

; At one time Matt wanted the option of setting the :val-guard of a
; non-empty table, but he doesn't recall why.  Perhaps we'll add such
; an option in the future if others express such a desire.

                          (er soft ctx
                              "It is illegal to set the :guard of the ~
                               non-empty table ~x0.  See :DOC table."
                              name))
                         (t
                          (let ((legal-vars '(key val world))
                                (vars (all-vars tterm)))
                            (cond ((not (subsetp-eq vars legal-vars))
                                   (er soft ctx
                                       "The only variables permitted in the ~
                                        :guard of a table are ~&0, but your ~
                                        guard uses ~&1.  See :DOC table."
                                       legal-vars vars))
                                  (t (install-event
                                      name
                                      event-form
                                      'table
                                      0
                                      nil
                                      (table-cltl-cmd name key val op ctx wrld)
                                      nil ; theory-related events do the check
                                      nil
                                      (putprop name
                                               'table-guard
                                               tterm
                                               wrld)
                                      state)))))))))))))
        (otherwise (er soft ctx
                       "Unrecognized table operation, ~x0.  See :DOC table."
                       op))))

(defun table-fn (name args state event-form)

; Warning: If this event ever generates proof obligations, remove it from the
; list of exceptions in install-event just below its "Comment on irrelevance of
; skip-proofs".

; This is an unusual "event" because it sometimes has no effect on
; STATE and thus is not an event!  In general this function applies
; an operation, op, to some arguments (and to the table named name).
; Ideally, args is of length four and of the form (key val op term).
; But when args is shorter it is interpreted as follows.

; args              same as args
; ()                (nil nil :alist nil)
; (key)             (key nil :get   nil)
; (key val)         (key val :put   nil)
; (key val op)      (key val op     nil)

; Key and val are both treated as forms and evaluated to produce
; single results (which we call key and val below).  Op and term are
; not evaluated.  A rational version of this function that takes key,
; val, op and term all as normal arguments is table-fn1.  The odd
; design of this function with its positional interpretation of op and
; odd treatment of evaluation is due to the fact that it represents
; the macroexpansion of a form designed primarily to be typed by the
; user.

; Op may be any of :alist, :get, :put, :clear, or :guard.  Each op
; enforces certain restrictions on the other three arguments.

; op         restrictions and meaning
; :alist     Key val and term must be nil.  Return the table as an
;            alist pairing keys to their non-nil vals.
; :get       Val and term must be nil.Return the val associated with
;            key.
; :put       Key and val satisfy :guard and term must be nil.  Store
;            val with key.
; :clear     Key and term must be nil.  Clear the table, setting it
;            to val if val is supplied (else to nil).  Note that val
;            must be an alist, and as with :put, the keys and entries
;            must satisfy the :guard.
; :guard     Key and val must be nil, term must be a term mentioning
;            only the variables KEY, VAL, and WORLD, and returning one
;            result.  The table must be empty.  Store term as the
;            table's :guard.

; Should table events be permitted to have documentation strings?  No.
; The reason is that we do not protect other names from being used as
; tables.  For example, the user might set up a table with the name
; defthm.  If we permitted a doc-string for that table, :DOC defthm
; would be overwritten.

  (let* ((ctx (cons 'table name))
         (wrld (w state))
         (event-form (or event-form
                         `(table ,name ,@args)))
         (n (length args))
         (key-form (car args))
         (val-form (cadr args))
         (op (cond ((= n 2) :put)
                   ((= n 1) :get)
                   ((= n 0) :alist)
                   (t (caddr args))))
         (term (cadddr args)))
    (er-progn
     (cond ((not (symbolp name))
            (er soft ctx
                "The first argument to table must be a symbol, but ~
                 ~x0 is not.  See :DOC table."
                name))
           ((< 4 (length args))
            (er soft ctx
                "Table may be given no more than five arguments.  In ~
                 ~x0 it is given ~n1.  See :DOC table."
                event-form
                (1+ (length args))))
           (t (value nil)))
     (er-let* ((key-pair
                (simple-translate-and-eval
                 key-form
                 (if (eq name 'acl2-defaults-table)
                     nil
                     (list (cons 'world wrld)))
                 nil
                 (if (eq name 'acl2-defaults-table)
                     "In (TABLE ACL2-DEFAULTS-TABLE key ...), key"
                     "The second argument of TABLE")
                 ctx wrld state nil))
               (val-pair
                (simple-translate-and-eval
                 val-form
                 (if (eq name 'acl2-defaults-table)
                     nil
                     (list (cons 'world wrld)))
                 nil
                 (if (eq name 'acl2-defaults-table)
                     "In (TABLE ACL2-DEFAULTS-TABLE key val ...), val"
                     "The third argument of TABLE")
                 ctx wrld state nil)))
              (table-fn1 name (cdr key-pair) (cdr val-pair) op term
                         ctx wrld state event-form)))))

(defun set-override-hints-fn (lst at-end ctx wrld state)
  (er-let* ((tlst (translate-override-hints 'override-hints lst ctx wrld
                                            state))
            (new (case at-end
                   ((t)
                    (value (append (override-hints wrld) tlst)))
                   ((nil)
                    (value (append tlst (override-hints wrld))))
                   (:clear
                    (value tlst))
                   (:remove
                    (let ((old (override-hints wrld)))
                      (value (set-difference-equal old tlst))))
                   (otherwise
                    (er soft ctx
                        "Unrecognized operation in ~x0: ~x1."
                        'set-override-hints-fn at-end)))))
           (er-progn
            (table-fn 'default-hints-table (list :override (kwote new)) state nil)
            (table-fn 'default-hints-table (list :override) state nil))))