;;
;; Package Gauche-dbd-sqlite
;;

(define-gauche-package "Gauche-dbd-sqlite"
  ;;
  :version "0.6.5"

  ;; Description of the package.  The first line is used as a short
  ;; summary.
  :description "SQLite library for Gauche\n\
                Previous Gauche-dbd-sqlite3 is purged cause of license problem."

  ;; List of dependencies.
  ;; Example:
  ;;     :require (("Gauche" (>= "0.9.5"))  ; requires Gauche 0.9.5 or later
  ;;               ("Gauche-gl" "0.6"))     ; and Gauche-gl 0.6
  :require (
            ("Gauche" (>= "0.9.12"))
            )

  ;; List of providing modules
  ;; NB: This will be recognized >= Gauche 0.9.7.
  ;; Example:
  ;;      :providing-modules (util.algorithm1 util.algorithm1.option)
  :providing-modules (
                      dbd.sqlite
                      )

  ;; List name and contact info of authors.
  ;; e.g. ("Eva Lu Ator <eval@example.com>"
  ;;       "Alyssa P. Hacker <lisper@example.com>")
  :authors ("Masahiro Hayashi <mhayashi1120@gmail.com>")

  ;; List name and contact info of package maintainers, if they differ
  ;; from authors.
  ;; e.g. ("Cy D. Fect <c@example.com>")
  :maintainers ()

  ;; List licenses
  ;; e.g. ("BSD")
  :licenses ("BSD")

  :homepage "https://github.com/mhayashi1120/Gauche-dbd-sqlite/"

  :repository "https://github.com/mhayashi1120/Gauche-dbd-sqlite.git"
  )
