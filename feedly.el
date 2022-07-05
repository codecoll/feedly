;; -*- lexical-binding: t -*-

(defface feedly-feed-face
  '((t :inherit variable-pitch
       :foreground "darkgreen"))
  "")

(defface feedly-feed-item-face
  '((t :inherit variable-pitch))
  "")

(defface feedly-feed-item-time-face
  '((t :inherit variable-pitch
       :foreground "dim gray"
       :height 0.8))
  "")

(defface feedly-feed-item-read-face
  '((t :inherit variable-pitch
       :foreground "gray"))
  "")

(defface feedly-top-title-face
  '((t :inherit variable-pitch
       :background "powder blue"
       :height 1.1))
  "")

(defface feedly-selection-face
  '((t :foreground "chocolate"
       :underline t))
  "")


(setq feedly-map (let ((map (make-sparse-keymap)))
                   (define-key map (kbd "<right>") 'feedly-expand-feed)
                   (define-key map (kbd "<left>") 'feedly-collapse-feed)
                   (define-key map (kbd "<RET>") 'feedly-show-item)
                   (define-key map (kbd "<up>") 'feedly-select-previous-item)
                   (define-key map (kbd "<down>") 'feedly-select-next-item)
                   (define-key map (kbd "a") 'feedly-mark-feed-as-read)
                   (define-key map (kbd "g") 'feedly)
                   (define-key map (kbd "q") 'feedly-restore-window-configuration)
                   (define-key map (kbd "w") 'feedly-close-item-preview-window)
                   (define-key map (kbd "s") 'feedly-mark-feed-as-read-and-quit)
                   (suppress-keymap map)
                   map))

(setq feedly-summary-map (let ((map (make-sparse-keymap)))
                           (suppress-keymap map)
                           (define-key map (kbd "q") 'delete-window)
                           map))


(defvar feedly-access-token nil)

(defvar feedly-buffer "*feedly*")

(defvar feedly-line-height 1.4)

(defvar feedly-custom-feed-names nil
  "Custom name for feeds in the form of an ALIST: '((current_name . new_name) ..)")



;; internal from here


(setq feedly-user-id nil)

(setq feedly-last-selected-item nil)

(setq feedly-api-usage-count nil)

(setq feedly-api-usage-limit nil)

(setq feedly-api-usage-reset nil)

(setq feedly-selection-overlay (make-overlay 0 0))
(overlay-put feedly-selection-overlay 'face 'feedly-selection-face)

(setq feedly-last-selection-position nil)

(setq feedly-previous-window-configuration nil)


(require 'json)
(require 'shr)


(defun feedly-network-request (request handler &optional postdata)
  (unless feedly-access-token
    (error "You need an access token. Get it here: https://developer.feedly.com/v3/developer/"))
  
  (let ((url-request-method (if postdata "POST"))
        (url-request-extra-headers
         (append `(("Authorization" . ,(concat "OAuth " feedly-access-token)))
                 (if postdata
                     '(("Content-Type" . "text/plain")))))
        (url-request-data (if postdata (json-encode postdata))))
    (url-retrieve
     (concat "https://cloud.feedly.com/v3/" request)

     (lambda (status handler post)
       (if (plist-get status :error)
           (progn
             (search-forward "\n\n" nil t)
             (error (assoc-default 'errorMessage (json-read))))

         (condition-case err
             (progn
               (goto-char (point-min))
               (re-search-forward "X-Ratelimit-Count: \\(.+\\)")
               (setq feedly-api-usage-count (match-string 1))
               
               (goto-char (point-min))
               (re-search-forward "X-RateLimit-Limit: \\(.+\\)")
               (setq feedly-api-usage-limit (match-string 1))

               (goto-char (point-min))
               (re-search-forward "X-Ratelimit-Reset: \\(.+\\)")
               (setq feedly-api-usage-reset (match-string 1)))
           
           (t
            (let ((response (buffer-string)))
              (pop-to-buffer "*feedly error*")
              (erase-buffer)
              (insert response)
              (goto-char (point-min))
              (signal (car err) (cdr err)))))

         (if post
             (funcall handler)
           
           (search-forward "\n\n")
           (set-buffer-multibyte t)
           (let ((data (json-read)))
             (kill-buffer)
             (funcall handler data)))))
     
     (list handler postdata))))



(defun feedly-fetch-batch-of-new-items (&optional continuation)
  (unless continuation
    (setq feedly-new-items nil))
  (feedly-network-request
   (format "streams/contents?streamId=user/%s/category/global.all&unreadOnly=true&count=1000%s"
           feedly-user-id
           (if continuation
               (concat "&continuation=" continuation)
             ""))
   (lambda (result)
     (setq feedly-new-items
           (append
            feedly-new-items
            (append (assoc-default 'items result) nil)))
     (if (assoc-default 'continuation result)
         (feedly-fetch-batch-of-new-items (assoc-default 'continuation result))

       (message "Done.")
       (feedly-process-items))))
  (message "Fetching new items... %s" (if feedly-new-items
                                          (length feedly-new-items)
                                        "")))


(defun feedly ()
  (interactive)
  (if feedly-user-id
      (feedly-fetch-batch-of-new-items)

    (message "Getting user id...")
    (feedly-network-request
     "profile"
     (lambda (result)
       (setq feedly-user-id (assoc-default 'id result))
       (feedly-fetch-batch-of-new-items)))))


(defun feedly-process-items ()
  (setq feedly-previous-window-configuration (current-window-configuration))
  (switch-to-buffer feedly-buffer)
  (setq buffer-read-only nil)
  (setq truncate-lines t)
  (erase-buffer)
  (use-local-map feedly-map)

  (insert (propertize
           " Unread Feedly items\n"
           'face 'feedly-top-title-face))
  (insert "\n")

  (if feedly-new-items
      (let ((hash (make-hash-table :test 'equal))
            source items)
        (dolist (item feedly-new-items)
          (setq source (assoc-default 'title (assoc-default 'origin item)))
          (puthash source
                   (append (gethash source hash) (list item))
                   hash))
        (maphash (lambda (key items)
                   (message "Processing %s..." key)
                   (insert "   "
                           (propertize
                            (concat (or (assoc-default key feedly-custom-feed-names)
                                        key)
                                    " ("
                                    (number-to-string (length items))
                                    ")")
                            'face 'feedly-feed-face))

                   (let ((feed-start (line-beginning-position))
                         (items-start (1+ (point)))
                         item-start)
                     (insert (propertize
                              "\n"
                              'line-height feedly-line-height))
                     (dolist (item (reverse items))
                       (insert (propertize "    " 'display `((height ,feedly-line-height))))
                       (setq item-start (point))
                       (insert (propertize
                                (replace-regexp-in-string
                                 "\n" " "
                                 (or (assoc-default 'title item)
                                     "no title"))
                                'face 'feedly-feed-item-face))
                       (put-text-property
                        (line-beginning-position)
                        (line-end-position)
                        'feedly-item (append item
                                             (list (cons 'item-start item-start)
                                                   (cons 'item-end (point)))))
                       (insert " ")
                       (insert (propertize
                                (format-time-string
                                 "(%Y-%m-%d %H:%M)"
                                 (/ (or (assoc-default 'published item)
                                        0)
                                    1000))
                                'face 'feedly-feed-item-time-face))
                       (insert "\n"))
                     (put-text-property
                      feed-start (1+ feed-start)
                      'feedly-items (list 'start items-start
                                          'end (point)))
                     (put-text-property items-start (point) 'invisible t)))
                 hash))

    (insert (propertize
             "    no new items"
             'face 'feedly-feed-face)))

  (insert "\n\n"
          (propertize
           (concat (format (concat " You have used %s API calls of %s for today."
                                   " Your daily quota will reset in %s")
                           feedly-api-usage-count
                           feedly-api-usage-limit
                           (let* ((reset (string-to-number feedly-api-usage-reset))
                                  (hours (/ reset 3600))
                                  (minutes (/ (% reset 3600) 60))
                                  (seconds (% reset 60)))
                             (format "%s%s%s"
                                     (if (> hours 0)
                                         (format "%sh " hours)
                                       "")
                                     (if (> minutes 0)
                                         (format "%sm " minutes)
                                       "")
                                     (if (> seconds 0)
                                         (format "%ss" seconds)
                                       ""))))
                   "\n"
                   " Remember that your access token expires after 30 days and you'll have to get a new one."
                   "\n") ;; for next-line, so it does not signal an error at the end
           'face '((:foreground "dim gray" :height 0.8) variable-pitch)))
  (message "")
  (goto-char (point-min))

  (when feedly-new-items
    (goto-char (next-single-property-change (1+ (point)) 'feedly-items))
    (feedly-move-selection)
    (add-hook 'post-command-hook 'feedly-post-command t t))

  (setq cursor-type nil)
  (setq buffer-read-only t))


(defun feedly-expand-feed (&optional collapse)
  (interactive)
  (let ((items (get-text-property (line-beginning-position) 'feedly-items)))
    (if (and items
             (eq (get-text-property (plist-get items 'start) 'invisible)
                 (not collapse)))
        (let ((inhibit-read-only t))
          (put-text-property
           (plist-get items 'start)
           (plist-get items 'end)
           'invisible
           collapse)))))


(defun feedly-get-current-feed-position ()
  (previous-single-property-change (1+ (point)) 'feedly-items))


(defun feedly-collapse-feed ()
  (interactive)
  (let ((pos (feedly-get-current-feed-position)))
    (when pos
      (goto-char pos)
      (feedly-expand-feed t))))


(defun feedly-set-item-to-read (item)
  (put-text-property (assoc-default 'item-start item)
                     (assoc-default 'item-end item)
                     'face 'feedly-feed-item-read-face)
  (setcdr (assoc 'unread item) nil))


(defun feedly-show-item ()
  (interactive)
  (let ((item (get-text-property (line-beginning-position) 'feedly-item)))
    (if item
        (if (eq item feedly-last-selected-item)
            (browse-url (or (assoc-default 'canonicalUrl item)
                            (let ((alternate (assoc-default 'alternate item)))
                              (if alternate
                                  (assoc-default 'href (aref alternate 0))))
                            (assoc-default 'originId item)))
          
          (setq feedly-last-selected-item item)

          (when (assoc-default 'unread item)
            (let ((inhibit-read-only t))
              (feedly-set-item-to-read item)
              (save-excursion
                (goto-char (feedly-get-current-feed-position))
                (re-search-forward "(\\([0-9]+\\))$")
                (replace-match
                 (propertize
                  (format "(%s)"
                          (1- (string-to-number (match-string 1))))
                  'face 'feedly-feed-face))))

            (feedly-network-request
             "markers"

             (lambda ()
               ;; do this here, so the message is visible after network
               ;; messages
               (with-current-buffer feedly-buffer
                 (message (substitute-command-keys
                           "Press \\[feedly-show-item] again to open the full item.")))
               )

             `(("action" . "markAsRead")
               ("type" . "entries")
               ("entryIds". ,(vector (assoc-default 'id item))
                ))))

          (save-selected-window
            (pop-to-buffer "*feedly item*")
            (use-local-map feedly-summary-map)
            (setq buffer-read-only t)
            (let ((inhibit-read-only t))
              (erase-buffer)
              (setq cursor-type nil)
              (insert (or (assoc-default 'content (assoc-default 'content item))
                          (assoc-default 'content (assoc-default 'summary item))
                          "no description")
                      (let ((url (or (assoc-default 'canonicalUrl item)
                                     (let ((alt (assoc-default 'alternate item)))
                                       (if alt
                                           (assoc-default 'href (aref alt 0)))))))
                        (format "<p><a href=\"%s\">%s</a></p>"
                                url url)))
              (shr-render-region (point-min) (point-max))
              (goto-char (point-min))
              (save-excursion
                (insert
                 "\n"
                 (propertize
                  (or (assoc-default 'title item)
                      "no title")
                  'face '(:height 1.3 :weight bold))
                 "\n\n")))))

      (message "Not a feed item."))))


(defun feedly-move-selection ()
  (move-overlay feedly-selection-overlay
                (save-excursion
                  (beginning-of-line)
                  (skip-chars-forward " ")
                  (point))
                (line-end-position)
                (current-buffer))
  (setq feedly-last-selection-position (line-beginning-position))
  (setq feedly-last-selected-item nil)
  (delete-other-windows))


(defun feedly-select-next-item ()
  (interactive)
  (let ((start (point)))
    (next-line 1)
    (while (not (or (get-text-property
                     (line-beginning-position)
                     'feedly-items)
                    (get-text-property
                     (line-beginning-position)
                     'feedly-item)
                    (eobp)))
      (beginning-of-line) ;; so we don't get an error at the end
      (next-line 1))

    (if (eobp)
        (goto-char start)
      (feedly-move-selection))))


(defun feedly-select-previous-item ()
  (interactive)
  (let ((start (point)))
    (previous-line 1)
    (while (not (or (get-text-property
                     (line-beginning-position)
                     'feedly-items)
                    (get-text-property
                     (line-beginning-position)
                     'feedly-item)
                    (bobp)))
      (previous-line -1))

    (if (bobp)
        (goto-char start)
      (feedly-move-selection))))


(defun feedly-post-command ()
  (unless (eq feedly-last-selection-position (line-beginning-position))
    (if (or (get-text-property
             (line-beginning-position)
             'feedly-items)
            (get-text-property
             (line-beginning-position)
             'feedly-item))
        (feedly-move-selection)

      (goto-char (point-min))
      (feedly-select-next-item))))


(defun feedly-mark-feed-as-read ()
  (interactive)
  (let (items)
    (with-current-buffer feedly-buffer
      (save-excursion
        (goto-char (feedly-get-current-feed-position))

        (forward-line 1)
        (let (item)
          (while (setq item (get-text-property (line-beginning-position)
                                               'feedly-item))
            (push item items)
            (forward-line 1)))))

    (feedly-network-request
     "markers"

     (lambda ()
       ;; if no error then mark items visually as read
       (with-current-buffer feedly-buffer
         (let ((inhibit-read-only t))
           (dolist (item items)
             (feedly-set-item-to-read item))))
       
       (message "Done."))
     
     `(("action" . "markAsRead")
       ("type" . "entries")
       ("entryIds". ,(vconcat (mapcar
                               (lambda (item)
                                 (assoc-default 'id item))
                               items)))))))


(defun feedly-restore-window-configuration ()
  (interactive)
  (set-window-configuration feedly-previous-window-configuration))


(defun feedly-close-item-preview-window ()
  (interactive)
  (delete-other-windows))


(defun feedly-mark-feed-as-read-and-quit ()
  (interactive)
  (feedly-mark-feed-as-read)
  (feedly-restore-window-configuration))


(provide 'feedly)
