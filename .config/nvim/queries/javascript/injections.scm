; Hogan.compile(`...`) - inject as HTML
(call_expression
  function: (member_expression
    object: (identifier) @_obj
    property: (property_identifier) @_prop)
  arguments: (arguments (template_string) @injection.content)
  (#eq? @_obj "Hogan")
  (#eq? @_prop "compile")
  (#set! injection.language "html")
  (#offset! @injection.content 0 1 0 -1)
  (#set! injection.include-children))
