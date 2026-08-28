-- dev_uiinspector: inspect and edit the LIVE, already-running client UI.
--
-- In edit mode, Ctrl+Alt+click any widget on screen. The property panel shows
-- the widget's values; "Apply (live)" pushes edits onto the running widget with
-- mergeStyle (instant, no reload); "Save to file" writes the change back into
-- the widget's source .otui -- but only when the widget can be traced to a file
-- node, which is why Save is often disabled (Lua-created widgets, list rows,
-- style-class children, HTML have no instance line to write to).
--
-- Sibling tool dev_otui/ solved most of this for a self-loaded file; the pieces
-- here (otml.lua, nodeForWidget, persistText, applyAll, ...) are adapted from it.

-- ============================================================ module state

local inspectorWindow = nil
local topButton = nil

local editModeOn = false
local suppressEditCheck = false

local captureLayer = nil
local selectionBox = nil
local hoverBox = nil
local restackEvent = nil

-- widget -> { file = '/norm/path.otui', src = 'wrap'|'scan'|'manual' }
local registry = setmetatable({}, { __mode = 'k' })
local rawLoadUI, rawDisplayUI = nil, nil
local wrappedLoadUI, wrappedDisplayUI = nil, nil

local selectedWidget = nil
local anchorWidget = nil        -- widget that the file's doc.root corresponds to
local currentSourceFile = nil   -- normalized virtual path of the owning .otui
local doc = nil                 -- parsed OTML document of currentSourceFile
local currentNode = nil         -- file node matching selectedWidget
local currentRef = nil          -- { kind = 'widget', path = { childIndex, ... } }
local nodeError = nil           -- why currentNode is missing

local propRows = {}             -- { key, edit, label, liveHint, original, readOnly, removed }
local selecting = false

local RESTACK_INTERVAL = 500

-- ============================================================ small helpers

local function status(msg, isError)
  if not inspectorWindow then return end
  local label = inspectorWindow:recursiveGetChildById('statusLabel')
  label:setText(msg)
  label:setColor(isError and '#ff6b6b' or '#dfdf7f')
  label:setTooltip(msg)
  if isError then g_logger.warning('[dev_uiinspector] ' .. msg) end
end

local function normOtui(path)
  if not path then return nil end
  path = path:trim()
  if path == '' then return nil end
  if path:sub(1, 1) ~= '/' then path = '/' .. path end
  if not path:ends('.otui') then path = path .. '.otui' end
  return path
end

-- Turn whatever was passed to loadUI/displayUI ("dev_otui", "game_idle/x", a
-- full path) into a canonical virtual .otui path, the same way UIManager does
-- (uimanager.cpp:615: g_resources.guessFilePath(file, "otui")).
local function resolveOtuiPath(file)
  if not file or file == '' then return nil end
  local ok, guessed = pcall(function() return g_resources.guessFilePath(file, 'otui') end)
  if ok and guessed and guessed ~= '' then
    if guessed:sub(1, 1) ~= '/' then guessed = '/' .. guessed end
    return guessed
  end
  return normOtui(file)
end

local function topLevelOf(w)
  local cur = w
  while cur do
    local p = cur:getParent()
    if not p or p == rootWidget then return cur end
    cur = p
  end
  return cur
end

local function isUnder(w, ancestor)
  local cur = w
  while cur do
    if cur == ancestor then return true end
    cur = cur:getParent()
  end
  return false
end

-- child-index path from `root` down to `w` ({} when w == root)
local function indexPath(w, root)
  local path = {}
  local cur = w
  while cur and cur ~= root and cur:getParent() do
    local parent = cur:getParent()
    table.insert(path, 1, parent:getChildIndex(cur))
    cur = parent
  end
  return path
end

local function describePath(w)
  local parts = {}
  local top = topLevelOf(w)
  local cur = w
  while cur do
    local name = cur:getStyleName()
    if not name or name == '' then name = 'UIWidget' end
    local id = cur:getId()
    if id and id ~= '' and id ~= name then name = name .. '#' .. id end
    table.insert(parts, 1, name)
    if cur == top then break end
    cur = cur:getParent()
  end
  return table.concat(parts, ' > ')
end

-- ============================================================ overlay boxes

local function ensureBox(existing, color, filled)
  if existing and not existing:isDestroyed() then return existing end
  local box = g_ui.createWidget('UIWidget', rootWidget)
  box:setPhantom(true)
  box:setFocusable(false)
  box:breakAnchors()
  if filled then
    box:setBackgroundColor(color)
  else
    box:setBorderWidth(1)
    box:setBorderColor(color)
  end
  box:hide()
  return box
end

local function moveBoxTo(box, widget)
  if not box then return end
  if not widget or widget:isDestroyed() then box:hide(); return end
  box:setRect(widget:getRect())
  box:show()
  box:raise()
end

-- Stacking bottom -> top: captureLayer, inspectorWindow, hoverBox, selectionBox.
local function restackLayers()
  if captureLayer and not captureLayer:isDestroyed() then captureLayer:raise() end
  if inspectorWindow and not inspectorWindow:isDestroyed() and inspectorWindow:isVisible() then
    inspectorWindow:raise()
  end
  if hoverBox and not hoverBox:isDestroyed() then hoverBox:raise() end
  if selectionBox and not selectionBox:isDestroyed() then selectionBox:raise() end
end

local function refreshSelectionVisuals()
  if not selectedWidget or selectedWidget:isDestroyed() then
    if selectionBox then selectionBox:hide() end
    return
  end
  selectionBox = ensureBox(selectionBox, '#00ff00')
  moveBoxTo(selectionBox, selectedWidget)
end

-- ============================================================ file document

local function readDocument(path)
  local readOk, text = pcall(function() return g_resources.readFileContents(path) end)
  if not readOk or not text then
    doc = nil
    status('Could not read the file: ' .. tostring(path) ..
      (readOk and '' or (' (' .. tostring(text) .. ')')), true)
    return false
  end

  local parseOk, parsedOrErr = pcall(function() return UiInspectorOtml.parse(text) end)
  if not parseOk then
    doc = nil
    status('Could not parse the file: ' .. tostring(parsedOrErr), true)
    return false
  end

  doc = parsedOrErr
  return true
end

-- Workdir-relative write path. "/game_idle/x.otui" lives on disk under
-- "<workdir>/modules/game_idle/x.otui" because init.lua mounts modules at the
-- virtual root. Refuses anything outside the project.
local function workDirWritePath(virtualPath)
  local probe = virtualPath
  if not g_resources.fileExists(virtualPath) then
    probe = virtualPath:match('^(.*)/[^/]*$') or '/'
    if probe == '' then probe = '/' end
  end

  local realDir = g_resources.getRealDir(probe)
  local workDir = g_resources.getWorkDir()
  if not realDir or realDir == '' or not workDir or workDir == '' then
    return nil, 'could not locate the file on disk'
  end

  realDir = realDir:gsub('\\', '/')
  workDir = workDir:gsub('\\', '/')
  if workDir:sub(-1) ~= '/' then workDir = workDir .. '/' end
  if realDir:sub(-1) == '/' then realDir = realDir:sub(1, -2) end

  if realDir:sub(1, #workDir) ~= workDir then
    return nil, 'file is outside the project directory (' .. realDir .. ')'
  end

  local prefix = realDir:sub(#workDir + 1)
  if prefix == '' then
    return virtualPath:sub(2)
  end
  return prefix .. virtualPath
end

-- Writes text with a .bak backup, then reads it back and compares.
local function persistText(virtualPath, newText, backupText)
  local writePath, why = workDirWritePath(virtualPath)
  if not writePath then
    return false, 'cannot write: ' .. tostring(why)
  end

  if backupText then
    if not g_resources.writeFileContentsToWorkDir(writePath .. '.bak', backupText) then
      return false, 'could not write the .bak backup; nothing was changed'
    end
  end

  if not g_resources.writeFileContentsToWorkDir(writePath, newText) then
    return false, 'the write failed' ..
      (backupText and (' - the original is at ' .. writePath .. '.bak') or '')
  end

  local okRead, current = pcall(function() return g_resources.readFileContents(virtualPath) end)
  if not okRead or current ~= newText then
    return false, 'wrote to ' .. writePath .. ', but the file read back does not match'
  end

  return true, writePath
end

-- ============================================================ widget -> node

-- Two nodes are the same when style name and id both match. Guards a save
-- against a file edited (reordered) between load and save.
local function sameNodeIdentity(a, b)
  if not a or not b then return false end
  if a.tag ~= b.tag then return false end
  local idA = UiInspectorOtml.findProperty(a, 'id')
  local idB = UiInspectorOtml.findProperty(b, 'id')
  return (idA and idA.value or nil) == (idB and idB.value or nil)
end

local function resolveNodeByPath(document, path)
  if not document or not document.root then return nil end
  local node = document.root
  for i = 1, #path do
    local kids = UiInspectorOtml.widgetChildren(node)
    node = kids[path[i]]
    if not node then return nil end
  end
  return node
end

local function resolveRef(document, ref)
  if not document or not ref then return nil end
  return resolveNodeByPath(document, ref.path)
end

-- Maps `widget` to a node of `doc`, validating style name == file tag at every
-- level. A mismatch means the widget did not come from this file's text (style
-- class child, list row, Lua-created, HTML) -> refuse, so Save stays off.
local function nodeForWidget(widget, anchorW)
  if not doc then return nil, 'file was not read' end
  if not doc.root then return nil, 'file defines only styles, no main widget' end
  if not anchorW or anchorW:isDestroyed() then return nil, 'anchor widget is gone' end

  if anchorW:getStyleName() ~= doc.root.tag then
    return nil, 'file root (' .. tostring(doc.root.tag) .. ') != window style (' ..
      tostring(anchorW:getStyleName()) .. ')'
  end

  local path = indexPath(widget, anchorW)
  local node = doc.root
  local w = anchorW
  for _, idx in ipairs(path) do
    local kids = UiInspectorOtml.widgetChildren(node)
    node = kids[idx]
    w = w:getChildByIndex(idx)
    if not node or not w then
      return nil, 'not in the file (Lua-created, a list row, or from a style?)'
    end
    if w:getStyleName() ~= node.tag then
      return nil, 'file and screen disagree at "' .. tostring(node.tag) ..
        '" (style-class child or injected row)'
    end
  end

  return node, nil, { kind = 'widget', path = path }
end

-- ============================================================ window -> file registry

local function recordMapping(w, file, src)
  if not w or w:isDestroyed() then return end
  local norm = resolveOtuiPath(file)
  if not norm then return end
  if src ~= 'manual' and registry[w] and registry[w].src ~= 'scan' then return end
  registry[w] = { file = norm, src = src }
end

-- Windows that existed before this module loaded are not in the registry. Guess
-- the file from the window's style/id and accept only if the parsed root tag
-- matches. A wrong guess is caught later by nodeForWidget (Save just stays off).
local function seedGuessRegistry(win)
  if not win or win:isDestroyed() or registry[win] then return end
  local style = win:getStyleName()
  local id = win:getId()
  local names = {}
  for _, n in ipairs({ id, style }) do
    if n and n ~= '' then
      names[#names + 1] = n
      names[#names + 1] = n:lower()
    end
  end
  for _, n in ipairs(names) do
    for _, cand in ipairs({ '/modules/' .. n .. '/' .. n .. '.otui',
                            '/modules/game_' .. n .. '/game_' .. n .. '.otui' }) do
      if g_resources.fileExists(cand) then
        local okRead, text = pcall(function() return g_resources.readFileContents(cand) end)
        if okRead and text then
          local okParse, d = pcall(function() return UiInspectorOtml.parse(text) end)
          if okParse and d and d.root and d.root.tag == style then
            registry[win] = { file = normOtui(cand), src = 'scan' }
            return
          end
        end
      end
    end
  end
end

-- Returns file, anchorWidget, srcKind for the widget's owning .otui.
local function resolveOwningFile(w, win)
  local cur = w
  while cur do
    local hit = registry[cur]
    if hit then return hit.file, cur, hit.src end
    if cur == win then break end
    cur = cur:getParent()
  end

  local key = (win:getStyleName() or 'UIWidget') .. '#' .. (win:getId() or '')
  local cached = g_settings.getString('dev_uiinspector_map_' .. key)
  if cached and cached ~= '' and g_resources.fileExists(cached) then
    return cached, win, 'manual'
  end

  seedGuessRegistry(win)
  local hit = registry[win]
  if hit then return hit.file, win, hit.src end

  return nil, win, nil
end

function setSourceFromInput()
  if not selectedWidget or selectedWidget:isDestroyed() then
    status('Select a widget first.', true)
    return
  end
  local file = resolveOtuiPath(inspectorWindow:recursiveGetChildById('sourceFileEdit'):getText())
  if not file then status('Type an .otui path.', true); return end
  if not g_resources.fileExists(file) then
    status('File not found: ' .. file, true)
    return
  end

  local win = topLevelOf(selectedWidget)
  registry[win] = { file = file, src = 'manual' }
  local key = (win:getStyleName() or 'UIWidget') .. '#' .. (win:getId() or '')
  g_settings.set('dev_uiinspector_map_' .. key, file)
  g_settings.set('dev_uiinspector_lastSource', file)

  selectWidget(selectedWidget)
end

-- ============================================================ property panel

local function fmtColor(c)
  if type(c) ~= 'table' then return tostring(c) end
  return string.format('#%02x%02x%02x%02x', c.r or 0, c.g or 0, c.b or 0, c.a == nil and 255 or c.a)
end
local function fmtPoint(p)
  if type(p) ~= 'table' then return tostring(p) end
  return math.floor(p.x or 0) .. ' ' .. math.floor(p.y or 0)
end

-- Curated live getters, used to seed rows when there is no file node and to fill
-- the dim "current value" hint when there is one.
local LIVE_GETTERS = {
  { key = 'id',               editable = false, get = function(w) return w:getId() end },
  { key = 'style',            editable = false, get = function(w) return w:getStyleName() end },
  { key = 'position',         editable = false, get = function(w) return fmtPoint(w:getPosition()) end },
  { key = 'size',             editable = true,  get = function(w) return w:getWidth() .. ' ' .. w:getHeight() end },
  { key = 'width',            editable = true,  get = function(w) return tostring(w:getWidth()) end },
  { key = 'height',           editable = true,  get = function(w) return tostring(w:getHeight()) end },
  { key = 'margin-top',       editable = true,  get = function(w) return tostring(w:getMarginTop()) end },
  { key = 'margin-right',     editable = true,  get = function(w) return tostring(w:getMarginRight()) end },
  { key = 'margin-bottom',    editable = true,  get = function(w) return tostring(w:getMarginBottom()) end },
  { key = 'margin-left',      editable = true,  get = function(w) return tostring(w:getMarginLeft()) end },
  { key = 'padding-top',      editable = true,  get = function(w) return tostring(w:getPaddingTop()) end },
  { key = 'padding-right',    editable = true,  get = function(w) return tostring(w:getPaddingRight()) end },
  { key = 'padding-bottom',   editable = true,  get = function(w) return tostring(w:getPaddingBottom()) end },
  { key = 'padding-left',     editable = true,  get = function(w) return tostring(w:getPaddingLeft()) end },
  { key = 'color',            editable = true,  get = function(w) return fmtColor(w:getColor()) end },
  { key = 'background-color',  editable = true,  get = function(w) return fmtColor(w:getBackgroundColor()) end },
  { key = 'opacity',          editable = true,  get = function(w) return tostring(w:getOpacity()) end },
  { key = 'rotation',         editable = true,  get = function(w) return tostring(w:getRotation()) end },
  { key = 'phantom',          editable = true,  get = function(w) return tostring(w:isPhantom()) end },
  { key = 'image-source',     editable = true,  get = function(w) return w:getImageSource() end },
  { key = 'image-color',      editable = true,  get = function(w) return fmtColor(w:getImageColor()) end },
  { key = 'text',             editable = true,  get = function(w) return w:getText() end },
  { key = 'font',             editable = true,  get = function(w) return w:getFont() end },
}

local function liveValueFor(widget, key)
  for _, g in ipairs(LIVE_GETTERS) do
    if g.key == key then
      local ok, v = pcall(g.get, widget)
      if ok and v ~= nil then return tostring(v) end
      return nil
    end
  end
  return nil
end

local function findRow(key)
  for _, row in ipairs(propRows) do
    if row.key == key then return row end
  end
  return nil
end

local function addPropRow(key, value, readOnly, pending)
  local list = inspectorWindow:recursiveGetChildById('propList')
  local widget = g_ui.createWidget('UiiPropRow', list)

  local keyLabel = widget:getChildById('keyLabel')
  local valueEdit = widget:getChildById('valueEdit')
  local removeBtn = widget:getChildById('removeBtn')
  local liveHint = widget:getChildById('liveHint')

  keyLabel:setText(key)
  valueEdit:setText(value or '')

  if readOnly then
    valueEdit:setEnabled(false)
    keyLabel:setColor('#808080')
  elseif pending then
    keyLabel:setColor('#ffcc00')
  end

  if selectedWidget and not selectedWidget:isDestroyed() then
    local live = liveValueFor(selectedWidget, key)
    liveHint:setText(live and ('now: ' .. live) or '')
  end

  local row = {
    key = key,
    edit = valueEdit,
    label = keyLabel,
    liveHint = liveHint,
    original = value or '',
    readOnly = readOnly or false,
    pending = pending or false,
    removed = false,
  }

  removeBtn.onClick = function() modules.dev_uiinspector.removeProperty(key) end

  valueEdit.onKeyPress = function(_, keyCode)
    if keyCode == KeyEnter then
      modules.dev_uiinspector.applyAll()
      return true
    end
    return false
  end

  valueEdit.onFocusChange = function(self, focused)
    if not focused and not self:isDestroyed() and self:getText() ~= row.original then
      modules.dev_uiinspector.applyAll()
    end
  end

  table.insert(propRows, row)
  return row
end

local function rebuildPropertyPanel()
  local list = inspectorWindow:recursiveGetChildById('propList')
  list:destroyChildren()
  propRows = {}

  if not selectedWidget or selectedWidget:isDestroyed() then return end

  if currentNode then
    for _, prop in ipairs(UiInspectorOtml.properties(currentNode)) do
      local composite = #prop.children > 0
      local ro = composite or prop.tag:starts('anchors.') or prop.tag:sub(1, 1) == '@'
      addPropRow(prop.tag, composite and '(block - edit in file)' or prop.value, ro, false)
    end
  else
    for _, g in ipairs(LIVE_GETTERS) do
      local ok, v = pcall(g.get, selectedWidget)
      addPropRow(g.key, (ok and v ~= nil) and tostring(v) or '', not g.editable, false)
    end
  end
end

-- Reflects in the panel a value already applied to the widget (drag / anchor).
local function setPendingProperty(key, value)
  local row = findRow(key)
  if row then
    row.edit:setText(value)
    if not row.pending then
      row.pending = true
      row.label:setColor('#ffcc00')
    end
  else
    addPropRow(key, value, false, true)
  end
end

function removeProperty(key)
  local row = findRow(key)
  if not row then return end
  if row.readOnly then
    status('Read-only row: edit it in the file.', true)
    return
  end
  if not currentNode then
    status('No file node - "remove" only works on a mapped widget (use it, then Save).', true)
    return
  end
  row.removed = true
  row.edit:setText('')
  row.edit:setEnabled(false)
  row.label:setColor('#ff6b6b')
  status('"' .. key .. '" will be removed from the file on Save.')
end

function addPropertyFromInput()
  if not selectedWidget or selectedWidget:isDestroyed() then
    status('Select a widget first.', true)
    return
  end

  local field = inspectorWindow:recursiveGetChildById('newPropEdit')
  local input = field:getText():trim()
  local key, value = input:match('^%s*([^:]+)%s*:%s*(.-)%s*$')
  if not key then
    status('Use the format "property: value".', true)
    return
  end
  key = key:trim()

  local row = findRow(key)
  if row then
    row.removed = false
    row.edit:setEnabled(true)
    setPendingProperty(key, value)
  else
    addPropRow(key, value, false, true)
  end

  field:setText('')
  applyAll()
end

-- ============================================================ selection

local function updateInfoLabel(w, srcKind)
  local rect = w:getRect()
  local origin
  if currentNode then
    origin = 'line ' .. currentNode.line .. ' of ' .. tostring(currentSourceFile)
  elseif currentSourceFile then
    origin = 'file: ' .. currentSourceFile .. '  (' .. tostring(nodeError) .. ')'
  else
    origin = tostring(nodeError)
  end
  local info = table.concat({
    describePath(w),
    string.format('rect: x=%d y=%d  w=%d h=%d', rect.x, rect.y, rect.width, rect.height),
    origin .. (srcKind and ('  [' .. srcKind .. ']') or ''),
  }, '\n')
  local label = inspectorWindow:recursiveGetChildById('infoLabel')
  label:setText(info)
  label:setTooltip(info)
end

function selectWidget(w)
  if not w or w:isDestroyed() or selecting then return end
  selecting = true

  selectedWidget = w
  anchorWidget = nil
  currentSourceFile = nil
  currentNode, nodeError, currentRef = nil, nil, nil

  local win = topLevelOf(w)
  local file, anchor, srcKind = resolveOwningFile(w, win)
  currentSourceFile = file
  anchorWidget = anchor
  inspectorWindow:recursiveGetChildById('sourceFileEdit'):setText(file or '')

  if file then
    if readDocument(file) then
      currentNode, nodeError, currentRef = nodeForWidget(w, anchor)
    else
      nodeError = 'source .otui could not be read/parsed'
    end
  else
    nodeError = 'owning .otui unknown - set it above; Save stays disabled'
  end

  refreshSelectionVisuals()
  updateInfoLabel(w, srcKind)
  rebuildPropertyPanel()

  inspectorWindow:recursiveGetChildById('saveBtn'):setEnabled(currentNode ~= nil)

  local banner = inspectorWindow:recursiveGetChildById('mappingBanner')
  if currentNode then
    banner:setText('')
    banner:setVisible(false)
    status('Selected. Mapped to line ' .. currentNode.line .. '. Apply is live; Save writes the file.')
  else
    banner:setText('Live-edit only - Save disabled: ' .. tostring(nodeError))
    banner:setVisible(true)
    status('Selected (live-edit only).')
  end

  if not inspectorWindow:isVisible() then
    inspectorWindow:show()
  end
  restackLayers()

  selecting = false
end

-- ============================================================ apply / save

function applyAll()
  if not selectedWidget or selectedWidget:isDestroyed() then
    status('Select a widget first.', true)
    return
  end

  local style = {}
  local count = 0
  for _, row in ipairs(propRows) do
    if not row.readOnly and not row.removed and row.key:sub(1, 1) ~= '@' then
      style[row.key] = row.edit:getText()
      count = count + 1
    end
  end

  if count == 0 then
    status('No applicable property to apply.', true)
    return
  end

  local ok, err = pcall(function() selectedWidget:mergeStyle(style) end)
  if not ok then
    local culprit, culpritErr
    for key, value in pairs(style) do
      local okOne, errOne = pcall(function() selectedWidget:mergeStyle({ [key] = value }) end)
      if not okOne then
        culprit, culpritErr = key, errOne
        break
      end
    end
    if culprit then
      local hint = ''
      if culprit:sub(1, 1) == '!' then
        hint = " - values of \"" .. culprit .. "\" are Lua code: quote them, e.g. 'my text'"
      end
      status('Apply failed at "' .. culprit .. '": ' .. tostring(culpritErr) .. hint, true)
    else
      status('Apply failed: ' .. tostring(err), true)
    end
    return
  end

  local parent = selectedWidget:getParent()
  if parent then parent:updateLayout() end

  refreshSelectionVisuals()

  -- refresh the "now:" hints from the freshly applied state
  for _, row in ipairs(propRows) do
    local live = liveValueFor(selectedWidget, row.key)
    if row.liveHint and not row.liveHint:isDestroyed() then
      row.liveHint:setText(live and ('now: ' .. live) or '')
    end
  end

  status('Applied live to the running widget. Nothing saved - use "Save to file" to persist.')
end

function saveFile()
  if not currentNode then
    status('Cannot save: ' .. tostring(nodeError), true)
    return
  end
  if not selectedWidget or selectedWidget:isDestroyed() then
    status('Select a widget before saving.', true)
    return
  end
  if not currentSourceFile then
    status('No source file.', true)
    return
  end

  if not readDocument(currentSourceFile) then
    status('Could not re-read the file before saving.', true)
    return
  end

  local originalText = UiInspectorOtml.serialize(doc)
  local ref = currentRef

  if not sameNodeIdentity(resolveRef(doc, ref), currentNode) then
    status('The .otui changed on disk since selection and the node no longer matches. ' ..
      'Nothing written - reselect the widget.', true)
    return
  end

  local edits = {}
  for _, row in ipairs(propRows) do
    if not row.readOnly then
      if row.removed then
        table.insert(edits, { key = row.key, remove = true })
      else
        local value = row.edit:getText()
        if value ~= row.original then
          table.insert(edits, { key = row.key, value = value })
        end
      end
    end
  end

  if #edits == 0 then
    status('Nothing changed.')
    return
  end

  for _, edit in ipairs(edits) do
    local node = resolveRef(doc, ref)
    if not node then
      status('Lost track of the widget in the file. Nothing was written.', true)
      readDocument(currentSourceFile)
      return
    end

    local ok, err
    if edit.remove then
      ok, err = UiInspectorOtml.removeProperty(doc, node, edit.key)
    else
      ok, err = UiInspectorOtml.setProperty(doc, node, edit.key, edit.value)
    end
    if not ok then
      status('Failed at "' .. edit.key .. '": ' .. tostring(err) .. '. Nothing was written.', true)
      readDocument(currentSourceFile)
      return
    end

    doc = UiInspectorOtml.reparse(doc)
  end

  local newText = UiInspectorOtml.serialize(doc)
  local ok, result = persistText(currentSourceFile, newText, originalText)
  if not ok then
    status(result .. '. Check the .bak before continuing.', true)
    readDocument(currentSourceFile)
    return
  end

  readDocument(currentSourceFile)
  currentNode = resolveRef(doc, ref)
  rebuildPropertyPanel()

  status(#edits .. ' change(s) saved to ' .. result ..
    '. NOTHING was reloaded - the live view already shows these values; ' ..
    'the file takes effect on this screen\'s next load.')
end

-- ============================================================ edit mode

local function altChord()
  return g_keyboard.isCtrlPressed() and g_keyboard.isAltPressed()
end

local function pickAt(pos)
  local hit = rootWidget:recursiveGetChildByPos(pos, false)
  if not hit or hit == captureLayer then return nil end
  if inspectorWindow and inspectorWindow:isVisible() and isUnder(hit, inspectorWindow) then return nil end
  return hit
end

local function enterEditMode()
  if captureLayer and not captureLayer:isDestroyed() then captureLayer:destroy() end

  captureLayer = g_ui.createWidget('UIWidget', rootWidget)
  captureLayer:setId('uiInspectorCaptureLayer')
  captureLayer:fill('parent')
  captureLayer:setPhantom(true)
  captureLayer:setFocusable(false)

  captureLayer.onMousePress = function(_, mousePos, button)
    if button ~= MouseLeftButton or not altChord() then return false end
    local w = pickAt(mousePos)
    if w then
      modules.dev_uiinspector.selectWidget(w)
    else
      status('No widget at that point.')
    end
    return true
  end

  captureLayer.onMouseRelease = function(_, _, button)
    if button == MouseLeftButton and altChord() then return true end
    return false
  end

  captureLayer.onMouseMove = function(_, mousePos)
    if not editModeOn then return false end
    hoverBox = ensureBox(hoverBox, '#ffcc00')
    if altChord() then
      moveBoxTo(hoverBox, pickAt(mousePos))
    else
      hoverBox:hide()
    end
    if selectionBox and not selectionBox:isDestroyed() and selectionBox:isVisible() then
      selectionBox:raise()
    end
    return false
  end

  restackLayers()
  removeEvent(restackEvent)
  restackEvent = cycleEvent(restackLayers, RESTACK_INTERVAL)
  status('Edit mode ON. Ctrl+Alt+click a widget to inspect it.')
end

local function exitEditMode()
  removeEvent(restackEvent)
  restackEvent = nil
  if captureLayer and not captureLayer:isDestroyed() then captureLayer:destroy() end
  captureLayer = nil
  if hoverBox and not hoverBox:isDestroyed() then hoverBox:hide() end
  status('Edit mode off. The client responds to clicks normally.')
end

function setEditMode(on)
  if suppressEditCheck then return end
  if on == editModeOn then return end
  editModeOn = on

  if on then enterEditMode() else exitEditMode() end

  local check = inspectorWindow and inspectorWindow:recursiveGetChildById('editModeCheck')
  if check and check:isChecked() ~= on then
    suppressEditCheck = true
    check:setChecked(on)
    suppressEditCheck = false
  end

  g_settings.set('dev_uiinspector_editMode', on)
end

function toggleEditMode()
  if not inspectorWindow then return end
  if not inspectorWindow:isVisible() then
    inspectorWindow:show()
    restackLayers()
    if topButton then topButton:setOn(true) end
  end
  setEditMode(not editModeOn)
end

function setDebugBoxes(enabled)
  g_ui.setDebugBoxesDrawing(enabled)
end

-- ============================================================ lifecycle

function toggle()
  if inspectorWindow:isVisible() then
    inspectorWindow:hide()
    if topButton then topButton:setOn(false) end
  else
    inspectorWindow:show()
    restackLayers()
    inspectorWindow:focus()
    if topButton then topButton:setOn(true) end
  end
end

function init()
  inspectorWindow = g_ui.displayUI('dev_uiinspector')
  inspectorWindow:hide()

  -- wrap g_ui.loadUI / g_ui.displayUI so windows opened after us are traceable
  -- to their .otui. displayUI is C++ loadUI(file, rootWidget) internally, a
  -- C++->C++ call, so both must be wrapped.
  rawLoadUI = g_ui.loadUI
  rawDisplayUI = g_ui.displayUI

  wrappedLoadUI = function(...)
    local w = rawLoadUI(...)
    local file = ...
    if w and type(file) == 'string' then recordMapping(w, file, 'wrap') end
    return w
  end
  wrappedDisplayUI = function(...)
    local w = rawDisplayUI(...)
    local file = ...
    if w and type(file) == 'string' then recordMapping(w, file, 'wrap') end
    return w
  end
  g_ui.loadUI = wrappedLoadUI
  g_ui.displayUI = wrappedDisplayUI

  -- windows that already exist: best-effort guess
  for _, w in ipairs(rootWidget:getChildren()) do
    seedGuessRegistry(w)
  end

  topButton = modules.client_topmenu.addTopRightToggleButton(
    'uiInspectorButton', tr('UI Inspector'), '/images/topbuttons/buttons', toggle)
  topButton:setOn(false)

  Keybind.new('Debug', 'Toggle UI Inspector Edit Mode', 'Ctrl+Alt+I', '')
  Keybind.bind('Debug', 'Toggle UI Inspector Edit Mode', {
    { type = KEY_DOWN, callback = toggleEditMode }
  })

  local last = g_settings.getString('dev_uiinspector_lastSource')
  if last and last ~= '' then
    inspectorWindow:recursiveGetChildById('sourceFileEdit'):setText(last)
  end
end

function terminate()
  removeEvent(restackEvent)
  restackEvent = nil

  Keybind.delete('Debug', 'Toggle UI Inspector Edit Mode')

  if g_ui.loadUI == wrappedLoadUI and rawLoadUI then g_ui.loadUI = rawLoadUI end
  if g_ui.displayUI == wrappedDisplayUI and rawDisplayUI then g_ui.displayUI = rawDisplayUI end
  rawLoadUI, rawDisplayUI, wrappedLoadUI, wrappedDisplayUI = nil, nil, nil, nil

  editModeOn = false
  if captureLayer and not captureLayer:isDestroyed() then captureLayer:destroy() end
  captureLayer = nil

  for _, w in ipairs({ selectionBox, hoverBox }) do
    if w and not w:isDestroyed() then w:destroy() end
  end
  selectionBox, hoverBox = nil, nil

  if topButton then topButton:destroy() end
  if inspectorWindow then inspectorWindow:destroy() end
  topButton, inspectorWindow = nil, nil

  registry = setmetatable({}, { __mode = 'k' })
  selectedWidget, anchorWidget, doc = nil, nil, nil
  currentNode, currentRef, nodeError, currentSourceFile = nil, nil, nil, nil
  propRows = {}
end
