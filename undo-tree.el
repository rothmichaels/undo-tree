

(defvar buffer-undo-tree nil
  "Undo history tree in current buffer.")
(make-variable-buffer-local 'buffer-undo-tree)



(defstruct
  (undo-tree
   :named
   (:constructor nil)
   (:constructor make-undo-tree (&aux
				 (root (make-undo-tree-node nil nil))
				 (current root)))
   (:copier nil))
  root current)


(defstruct
  (undo-tree-node
   (:type vector)   ; create unnamed struct
   (:constructor nil)
   (:constructor make-undo-tree-node
		 (previous undo &aux (timestamp (current-time)) (branch 0)))
   (:constructor make-undo-tree-node-backwards
		 (next-node undo
		  &aux
		  (next (list next-node))
		  (timestamp (current-time))
		  (branch 0)))
   (:copier nil))
  previous next undo redo timestamp branch)


(defun undo-tree-grow (undo)
  "Add an UNDO node to current branch of `buffer-undo-tree'."
  (let* ((current (undo-tree-current buffer-undo-tree))
  	 (new (make-undo-tree-node current undo)))
    (push new (undo-tree-node-next current))
    (setf (undo-tree-current buffer-undo-tree) new)))


(defun undo-tree-grow-backwards (node undo)
  "Add an UNDO node *above* undo-tree NODE, and return new node.
Note that this will overwrite NODE's \"previous\" link, so should
only be used on detached nodes, never on nodes that are already
part of `buffer-undo-tree'."
  (let* ((new (make-undo-tree-node-backwards node undo)))
    (setf (undo-tree-node-previous node) new)
    new))


(defun undo-list-pop-changeset ()
  "Pop changeset from `buffer-undo-list'."
  ;; discard undo boundaries at head of list
  (while (null (car buffer-undo-list))
    (setq buffer-undo-list (cdr buffer-undo-list)))
  ;; pop elements up to next undo boundary
  (let* ((changeset (cons (pop buffer-undo-list) nil))
	 (p changeset))
    (while (car buffer-undo-list)
      (setcdr p (cons (pop buffer-undo-list) nil))
      (setq p (cdr p)))
    changeset))


(defun undo-list-to-tree ()
  "Transfer entries accumulated in `buffer-undo-list'
to `buffer-undo-tree'."
  (when buffer-undo-list
    (let* ((node (make-undo-tree-node nil (undo-list-pop-changeset)))
	   (splice (undo-tree-current buffer-undo-tree)))
      (setf (undo-tree-current buffer-undo-tree) node)
      (while buffer-undo-list
	(setq node (undo-tree-grow-backwards node (undo-list-pop-changeset))))
      (setf (undo-tree-node-previous node) splice)
      (push node (undo-tree-node-next splice)))))


(defun undo-tree-undo (&optional arg)
  "Undo changes. A numeric ARG serves as a repeat count."
  (interactive "p")
  ;; if `buffer-undo-tree' is empty, create initial undo-tree
  (when (null buffer-undo-tree)
    (setq buffer-undo-tree (make-undo-tree)))
  ;; transfer entries accumulated in `buffer-undo-list' to `buffer-undo-tree'
  (undo-list-to-tree)
  (dotimes (i arg)
    ;; check if at top of tree
    (if (null (undo-tree-node-undo (undo-tree-current buffer-undo-tree)))
	(error "No further undo information")
      ;; undo one record from tree
      (primitive-undo 1 (undo-copy-list
			 (undo-tree-node-undo
			  (undo-tree-current buffer-undo-tree))))
      ;; pop redo entries that `primitive-undo' has added to
      ;; `buffer-undo-list' and record them in current node's redo record
      (setf (undo-tree-node-redo (undo-tree-current buffer-undo-tree))
	    (undo-list-pop-changeset))
      ;; rewind pointer to current node
      (setf (undo-tree-current buffer-undo-tree)
	    (undo-tree-node-previous (undo-tree-current buffer-undo-tree)))
      )))
