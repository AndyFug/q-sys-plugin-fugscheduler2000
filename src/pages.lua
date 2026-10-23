-- Q-SYS calls this to define page objects for the plugin control panel.
function GetPages(props)
  local pages = {}
  for _, name in ipairs(pageNames(props)) do
    table.insert(pages, {name = name})
  end
  return pages
end
