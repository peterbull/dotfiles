; extends

; Redis Lua scripts kept in template strings, e.g. redis.eval(`... redis.call(...) ...`)
((template_string) @injection.content
  (#lua-match? @injection.content "redis%.call")
  (#set! injection.language "lua")
  (#offset! @injection.content 0 1 0 -1)
  (#set! injection.include-children))
