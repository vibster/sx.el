;;; sx-question.el --- Base question logic. -*- lexical-binding: t; -*-

;; Copyright (C) 2014  Sean Allred

;; Author: Sean Allred <code@seanallred.com>

;; This program is free software; you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation, either version 3 of the License, or
;; (at your option) any later version.

;; This program is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.

;; You should have received a copy of the GNU General Public License
;; along with this program.  If not, see <http://www.gnu.org/licenses/>.

;;; Commentary:


;;; Code:

(require 'sx)
(require 'sx-filter)
(require 'sx-method)

(defun sx-question-get-questions (site &optional page keywords)
  "Get SITE questions.  Return page PAGE (the first if nil).
Return a list of question.  Each question is an alist of
properties returned by the API with an added (site SITE)
property.

KEYWORDS are added to the method call along with PAGE.

`sx-method-call' is used with `sx-browse-filter'."
  (sx-method-call 'questions
    :keywords `((page . ,page) ,@keywords)
    :site site
    :auth t
    :filter sx-browse-filter))

(defun sx-question-get-question (site question-id)
  "Query SITE for a QUESTION-ID and return it.
If QUESTION-ID doesn't exist on SITE, raise an error."
  (let ((res (sx-method-call 'questions
               :id question-id
               :site site
               :auth t
               :filter sx-browse-filter)))
    (if (vectorp res)
        (elt res 0)
      (error "Couldn't find question %S in %S"
             question-id site))))


;;; Question Properties

;;;; Read/unread
(defvar sx-question--user-read-list nil
  "Alist of questions read by the user.

Each element has the form

    (SITE . QUESTION-LIST)

where each element in QUESTION-LIST has the form

    (QUESTION_ID . LAST-VIEWED-DATE).")

(defun sx-question--ensure-read-list (site)
  "Ensure `sx-question--user-read-list' has been read from cache.
If no cache exists for it, initialize one with SITE."
  (unless sx-question--user-read-list
    (setq sx-question--user-read-list
          (sx-cache-get 'read-questions `'((,site))))))

(defun sx-question--read-p (question)
  "Non-nil if QUESTION has been read since last updated.
See `sx-question--user-read-list'."
  (sx-assoc-let question
    (sx-question--ensure-read-list .site)
    (let ((ql (cdr (assoc .site sx-question--user-read-list))))
      (and ql
           (>= (or (cdr (assoc .question_id ql)) 0)
               .last_activity_date)))))

(defun sx-question--mark-read (question)
  "Mark QUESTION as being read until it is updated again.
Returns nil if question (in its current state) was already marked
read, i.e., if it was `sx-question--read-p'.
See `sx-question--user-read-list'."
  (prog1
      (sx-assoc-let question
        (sx-question--ensure-read-list .site)
        (let ((site-cell (assoc .site sx-question--user-read-list))
              (q-cell (cons .question_id .last_activity_date))
              cell)
          (cond
           ;; First question from this site.
           ((null site-cell)
            (push (list .site q-cell) sx-question--user-read-list))
           ;; Question already present.
           ((setq cell (assoc .question_id site-cell))
            ;; Current version is newer than cached version.
            (when (> .last_activity_date (cdr cell))
              (setcdr cell .last_activity_date)))
           ;; Question wasn't present.
           (t
            (sx-sorted-insert-skip-first
             q-cell site-cell (lambda (x y) (> (car x) (car y))))))))
    ;; Save the results.
    ;; @TODO This causes a small lag on `j' and `k' as the list gets
    ;; large.  Should we do this on a timer?
    (sx-cache-set 'read-questions sx-question--user-read-list)))


;;;; Hidden
(defvar sx-question--user-hidden-list nil
  "Alist of questions hidden by the user.

Each element has the form

  (SITE QUESTION_ID QUESTION_ID ...)")

(defun sx-question--ensure-hidden-list (site)
  "Ensure the `sx-question--user-hidden-list' has been read from cache.

If no cache exists for it, initialize one with SITE."
  (unless sx-question--user-hidden-list
    (setq sx-question--user-hidden-list
          (sx-cache-get 'hidden-questions `'((,site))))))

(defun sx-question--hidden-p (question)
  "Non-nil if QUESTION has been hidden."
  (sx-assoc-let question
    (sx-question--ensure-hidden-list .site)
    (let ((ql (cdr (assoc .site sx-question--user-hidden-list))))
      (and ql (memq .question_id ql)))))

(defun sx-question--mark-hidden (question)
  "Mark QUESTION as being hidden."
  (sx-assoc-let question
    (let ((site-cell (assoc .site sx-question--user-hidden-list))
          cell)
      ;; If question already hidden, do nothing.
      (unless (memq .question_id site-cell)
        ;; First question from this site.
        (push (list .site .question_id) sx-question--user-hidden-list)
        ;; Question wasn't present.
        ;; Add it in, but make sure it's sorted (just in case we need
        ;; it later).
        (sx-sorted-insert-skip-first .question_id site-cell >)
        ;; This causes a small lag on `j' and `k' as the list gets large.
        ;; Should we do this on a timer?
        ;; Save the results.
        (sx-cache-set 'hidden-questions sx-question--user-hidden-list)))))


;;;; Other data

(defun sx-question--accepted-answer-id (question)
  "Return accepted answer in QUESTION or nil if none exists."
  (sx-assoc-let question
    (and (integerp .accepted_answer_id)
         .accepted_answer_id)))

(defun sx-question--tag-format (tag)
  "Formats TAG for display."
  (concat "[" tag "]"))

(provide 'sx-question)
;;; sx-question.el ends here

;; Local Variables:
;; indent-tabs-mode: nil
;; lexical-binding: t
;; End:
