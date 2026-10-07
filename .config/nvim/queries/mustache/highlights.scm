; Mustache highlights — tuned to blend with HTML in onedark
;
; Color mapping in onedark:
;   @tag.delimiter     #abb2bf (grey)    — HTML < > brackets
;   @punctuation.special #abb2bf (grey)  — Django {{ }} braces
;   @variable          #e06c75 (red)     — matches @tag.attribute
;   @keyword.conditional #c678dd (purple) — structural markers
;   @comment           #5c6370 (muted grey)
;   @punctuation.delimiter (inherits)

; Delimiters — match HTML bracket color (grey)
[
  (start_delimiter)
  (end_delimiter)
  "{"
  "}"
] @tag.delimiter

; Template variables — match HTML attribute name color (red)
(identifier) @variable

; Partials — slightly distinct from regular variables
(partial_content) @variable.builtin

; Dots in paths — subtle punctuation
"." @punctuation.delimiter

; Section markers (# ^ / >) — structural, keep visible
[
  "#"
  "/"
  "^"
  ">"
] @keyword.conditional

; Comments
(comment_statement) @comment @spell
