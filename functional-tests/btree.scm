(library
  (btree)

  (export btree-open
          btree-lookup
          btree-each)

  (import (block-io)
          (chezscheme)
          (binary-format)
          (list-utils))

  ;;; Unlike the kernel or c++ versions, I'm going to leave it to the hiogher
  ;;; levels to handle multi level btrees.
  (binary-format
    (node-header pack-btree-node unpack-btree-node)

    (csum le32)
    (flags le32)
    (blocknr le64)
    (nr-entries le32)
    (max-entries le32)
    (value-size le32)
    (padding le32))

  (define-record-type value-type (fields size unpacker))

  (define (max-entries vt)
    (/ (- metadata-block-size node-header-size)
       (+ (size-of 'le64)
          (value-type-size vt))))

  (define (key-offset index)
    (+ node-header-size (* (size-of 'le64 index))))

  (define (value-base vt)
    (+ node-header-size
       (* (max-entries vt)
          (size-of 'le64))))

  (define (value-offset vt index)
    (+ (value-base vt)
       (* (value-type-size vt) index)))

  (define-record-type btree
                      (fields value-type dev root))

  (define (btree-open vt dev root)
    (make-btree value-type dev root))

  (define le64-type
    (make-value-type (size-of 'le64)
                     (lambda (bv offset)
                       (unpack-type bv offset le64))))

  (define (internal-node? header)
    (bitwise-bit-set? 0 (node-header-flags header)))

  (define (leaf-node? header)
    (bitwise-bit-set? 1 (node-header-flags header)))

  (define (key-at node index)
    (unpack-type node (key-offset index le64)))

  (define (value-at node index vt)
    ((value-type-unpacker vt) node (value-offset vt index)))

  ;;; Performs a binary search looking for the key and returns the index of the
  ;;; lower bound.
  (define (lower-bound node header key)
    (let ((nr-entries (node-header-nr-entries header)))
     (let loop ((lo 0) (hi nr-entries))
      (if (= 1 (- hi lo))
          lo
          (let* ((mid (+ lo (/ (- hi lo) 2)))
                 (k (key-at mid)))
            (cond
              ((= key k) mid)
              ((< k key) (loop mid hi))
              (else (loop lo mid))))))))

  ;;;;----------------------------------------------
  ;;;; Lookup
  ;;;;----------------------------------------------

  (define (btree-lookup tree key default)
    (let ((dev (btree-dev tree))
          (vt (btree-value-type tree)))

      (define (lookup root fail-k)
        (let loop ((root root))
         (let* ((node (read-block dev root))
                (header (unpack-node-header node 0))
                (index (lower-bound node header key fail-k)))
           (if (internal-node? header)
               (loop (unpack-value node index le64-type))
               (if (= key (key-at node index))
                   (value-at node index vt)
                   (fail-k default))))))

      (call/cc
        (lambda (fail-k)
          (lookup (btree-root tree) fail-k)))))

  ;;;;----------------------------------------------
  ;;;; Walking the btree
  ;;;;----------------------------------------------

  ;;; Calls (fn key value) on every entry of the btree.
  (define (btree-each tree fn)
    (let ((vt (btree-value-type tree)))

     (define (visit-leaf node header)
       (let loop ((index 0))
        (when (< index (node-header-nr-entries header))
          (fn (key-at node index) (value-at node index vt))
          (loop (+ 1 index)))))

     (define (visit-internal node header)
       (let loop ((index 0))
        (when (< index (node-header-nr-entries header))
          (visit-node (value-at node index le64-type))
          (loop (+ 1 index)))))

     (define (visit-node root)
       (let* ((node (read-block root))
              (header (unpack-node-header node 0)))
         ((if (internal-node? header) visit-internal visit-leaf) node header)))

     (visit-node (btree-root tree)))







    ))
