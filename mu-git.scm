;;; mu-git.scm --- Guix package for Emacs-Guix

;; Copyright (C) 2011-2019 Dirk-Jan C. Binnema

;; Author: Trey Peacock <gpg@treypeacock.com>

;; This file is not part of GNU Emacs.

;; GNU Emacs is free software: you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation, either version 3 of the License, or
;; (at your option) any later version.

;; GNU Emacs is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.

;; You should have received a copy of the GNU General Public License
;; along with GNU Emacs.  If not, see <http://www.gnu.org/licenses/>.

;;; Commentary:

;;; Commentary:

;; This file contains Guix package for development version of
;; Mu.  To build or install, comment out the final line in autogen.sh
;; './configure --config-cache $@' and run:

;;
;;   guix build --file=mu-git.scm
;;   guix package --install-from-file=mu-git.scm

;; The main purpose of this file though is to make a development
;; environment for building Mu & mu4e:
;;
;;   guix environment --pure --load=mu-git.scm
;;   ./autogen.sh
;;   (or ./configure)
;;   make

;;; Code:

(use-modules
 (ice-9 popen)
 (ice-9 rdelim)
 (ice-9 regex)
 (guix build utils)
 (guix build-system gnu)
 (guix gexp)
 (guix git-download)
 (guix packages)
 (gnu packages base)
 (gnu packages autotools)
 (gnu packages m4)
 (gnu packages emacs)
 (gnu packages mail)
 (gnu packages emacs-xyz)
 (gnu packages pkg-config)
 (gnu packages glib)
 (gnu packages texinfo))

(define %source-dir (dirname (current-filename)))

(define (version-output . args)
  "Execute 'git ARGS ...' command and return its output without trailing
newspace."
  (with-directory-excursion %source-dir
    (let* ((port   (apply open-pipe* OPEN_READ "grep" "AC_INIT" "configure.ac" args))
           (output (read-string port)))
      (close-pipe port)
      (string-trim-right output #\newline))))

(define (git-output . args)
  "Execute 'git ARGS ...' command and return its output without trailing
newspace."
  (with-directory-excursion %source-dir
    (let* ((port   (apply open-pipe* OPEN_READ "git" args))
           (output (read-string port)))
      (close-pipe port)
      (string-trim-right output #\newline))))

(define (current-commit)
  (git-output "log" "-n" "1" "--pretty=format:%H"))

(define (current-version)
  (match:substring (regexp-exec (make-regexp "[0-9].[0-9].[0-9]") (version-output))))

(define mu-git
  (let ((commit (current-commit)))
    (package
      (inherit mu)
      (version (string-append (current-version)
                              "-" (string-take commit 7)))
      (source (local-file %source-dir
                          #:recursive? #t
                          #:select? (git-predicate %source-dir)))
      (arguments
       `(#:modules ((guix build gnu-build-system)
                    (guix build utils)
                    (guix build emacs-utils))
                   #:imported-modules (,@%gnu-build-system-modules
                                       (guix build emacs-utils))
                   #:phases
                   (modify-phases %standard-phases
                     (add-after 'unpack 'autogen
                       (lambda _
                         (setenv "CONFIG_SHELL" (which "sh"))
                         (zero? (system* "sh" "autogen.sh"))
                         ;; replace final line in autogen.sh with the below
                         (zero? (system* "sh" "configure" "--config-cache"))))
                     (add-after 'unpack 'patch-configure
                       ;; By default, elisp code goes to "share/emacs/site-lisp/mu4e",
                       ;; so our Emacs package can't find it.  Setting "--with-lispdir"
                       ;; configure flag doesn't help because "mu4e" will be added to
                       ;; the lispdir anyway, so we have to modify "configure.ac".
                       (lambda _
                         (substitute* "configure.ac"
                           (("^ +lispdir=\"\\$\\{lispdir\\}/mu4e/\".*") "")
                           ;; Use latest Guile
                           (("guile-2.0") "guile-2.2"))
                         #t))
                     (add-after 'unpack 'patch-bin-sh-in-tests
                       (lambda _
                         (substitute* '("guile/tests/test-mu-guile.c"
                                        "mu/test-mu-cmd.cc"
                                        "mu/test-mu-cmd-cfind.cc"
                                        "mu/test-mu-query.cc"
                                        "mu/test-mu-threads.cc")
                           (("/bin/sh") (which "sh")))
                         #t))
                     (add-before 'install 'fix-ffi
                       (lambda* (#:key outputs #:allow-other-keys)
                         (substitute* "guile/mu.scm"
                           (("\"libguile-mu\"")
                            (format #f "\"~a/lib/libguile-mu\""
                                    (assoc-ref outputs "out"))))
                         #t))
                     (add-before 'check 'check-tz-setup
                       (lambda* (#:key inputs #:allow-other-keys)
                         ;; For mu/test/test-mu-query.c
                         (setenv "TZDIR"
                                 (string-append (assoc-ref inputs "tzdata")
                                                "/share/zoneinfo"))
                         #t))
                     (add-after 'install 'install-emacs-autoloads
                       (lambda* (#:key outputs #:allow-other-keys)
                         (emacs-generate-autoloads
                          "mu4e"
                          (string-append (assoc-ref outputs "out")
                                         "/share/emacs/site-lisp"))
                         #t)))))
      (native-inputs
       `(("pkg-config" ,pkg-config)
         ;; 'emacs-minimal' does not find Emacs packages (this is for
         ;; "guix environment").
         ("emacs" ,emacs-no-x)
         ("glib" ,glib "bin")           ; for gtester
         ("autoconf" ,autoconf)
         ("libtool" ,libtool)
         ("m4" ,m4)
         ("automake" ,automake)
         ("texinfo" ,texinfo)
         ("tzdata" ,tzdata-for-tests)   ; for mu/test/test-mu-query.c
         )))))

mu-git

;;; mu-git.scm ends here
