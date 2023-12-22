local ls = require "luasnip"
local fmt = require("luasnip.extras.fmt").fmt
local extras = require "luasnip.extras"
local l = extras.lambda
local i = ls.insert_node
local c = ls.choice_node

local s = ls.snippet
local sn = ls.snippet_node
local t = ls.text_node

-- require snippets
return {
  s("waitp", {
    t {
      [[# wait for shell's child process to exit]],
      [[shell_pid=]],
    },
    i(1, "pid"),
    t {
      "",
      [[child_pid=$(ps -ef | awk -v shell_pid=$shell_pid '$3==shell_pid {print $2}')]],
      [[echo "child_pid: $child_pid"]],
      'while [[ -n "$child_pid" ]] && [[ -d /proc/$child_pid ]]; do',
      "\tsleep 1",
      [[done]],
      "",
    },
    i(0),
  }),
}
