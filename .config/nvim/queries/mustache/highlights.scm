; Keep template captures visible inside injected HTML and JavaScript strings.
([
  (start_delimiter)
  (end_delimiter)
  "{"
  "}"
] @tag.delimiter
  (#set! priority 110))

((identifier) @variable
  (#set! priority 110))

((partial_content) @variable.builtin
  (#set! priority 110))

("." @punctuation.delimiter
  (#set! priority 110))

([
  "#"
  "/"
  "^"
  ">"
] @keyword.conditional
  (#set! priority 110))

((comment_statement) @comment @spell
  (#set! priority 110))
