/* ==========================================================================
   Plush - Soft Form Studio  |  ui.js
   Wires the plush UI to the Ruby side (Archinsights::Plush) and back.
   --------------------------------------------------------------------------
   Contract notes
   - JS -> Ruby   : sketchup.<callback>({object})   (bridge delivers a Hash)
   - Ruby -> JS   : these globals exist            (see CALLBACKS FROM RUBY)
   - Success path : Ruby answers geometry ops via opDone(ok, message)
   ========================================================================== */

/* ------------------------------------------------------------------ *
 * Tiny helpers
 * ------------------------------------------------------------------ */
function $(id) { return document.getElementById(id); }
function qsa(sel) { return Array.prototype.slice.call(document.querySelectorAll(sel)); }
function num(id) { return parseFloat($(id).value); }
function txt(id) { return String($(id).value).trim(); }
function cbx(id) { return $(id).checked; }

/* ------------------------------------------------------------------ *
 * State
 * ------------------------------------------------------------------ */
var APPLY_LABELS = {
  'corners':        'Soften Corners',
  'pillow':         'Pillow the Selection',
  'mattress':       'Lay the Mattress',
  'cushion':        'Plump the Cushion',
  'drape':          'Dress with Fabric',
  'wall_curve':     'Build Curved Wall',
  'ceiling_curve':  'Install Cove',
  'curved_pushpull':'Push / Pull Outward',
  'cutout':         'Cut Opening',
  'loft':           'Loft the Faces',
  'pipe':           'Sweep Tube',
  'utilities':      'Batch Soften'
};

var TOOL_LIST = [
  'corners', 'pillow', 'mattress', 'cushion', 'drape', 'wall_curve',
  'ceiling_curve', 'curved_pushpull', 'cutout', 'loft', 'pipe', 'utilities'
];

var UNIT_LIST = ['mm', 'cm', 'm', 'in', 'ft'];

var _tool = 'corners';
var _unitMode = 'manual';   /* 'manual' | 'auto' */
var _manualUnit = 'cm';     /* last unit picked by the user */
var _modelUnit = 'cm';      /* reported by the model */
var _busy = false;
var _minimized = false;
var _maximized = false;
var _updateCard = null;
var _updatePath = null;
var _saveTimer = null;
var _toastTimer = null;

var _colors = {
  'pillow':   '#e9c8c2',
  'mattress': '#dfeef0',
  'cushion':  '#cdd9e8',
  'drape':    '#c9d7c5'
};

var _seeds = { 'pillow': 1, 'cushion': 11, 'drape': 21, 'wall': 3 };

/* ================================================================== *
 * INIT
 * ================================================================== */
document.addEventListener('DOMContentLoaded', function () {
  bindRail();
  bindChips();
  bindRows();
  bindSliders();
  bindSwatches();
  bindDice();
  bindLengthInputs();
  applyUnit(_manualUnit);

  /* Ask the Ruby side for everything it knows */
  try { sketchup.get_state(); } catch (e) { }
  try { sketchup.get_model_unit(); } catch (e) { }
  try { sketchup.get_license_status(); } catch (e) { }
  try { sketchup.get_update_info(); } catch (e) { }

  setInterval(function () {
    try { sketchup.check_selection(); } catch (e) { }
  }, 1100);
});

/* ================================================================== *
 * RAIL + TOOL SWITCHING
 * ================================================================== */
function bindRail() {
  qsa('.rail-item').forEach(function (btn) {
    btn.addEventListener('click', function () {
      switchTool(btn.getAttribute('data-tool'));
    });
  });
}

function bindRows() {
  /* conditional rows react to chip changes; nothing to bind directly */
  updateRows();
}

function switchTool(toolName) {
  if (TOOL_LIST.indexOf(toolName) < 0) { toolName = 'corners'; }
  var leaving = _tool;
  _tool = toolName;

  qsa('.rail-item').forEach(function (b) {
    b.classList.toggle('on', b.getAttribute('data-tool') === toolName);
  });
  TOOL_LIST.forEach(function (t) {
    var panel = $('panel-' + t);
    if (panel) { panel.classList.toggle('on', t === toolName); }
  });

  var applyBtn = $('btn-apply');
  if (applyBtn) {
    applyBtn.textContent = APPLY_LABELS[toolName] || 'Apply';
    applyBtn.disabled = false;
  }

  /* Pillow click tool follows the tab */
  if (typeof sketchup !== 'undefined' && sketchup) {
    try {
      if (toolName === 'pillow') { sketchup.activate_pillow_tool(); }
      else if (leaving === 'pillow') { sketchup.deactivate_pillow_tool(); }
    } catch (e) { }
  }

  updateRows();
  saveState();
}

/* ================================================================== *
 * UNITS
 * ================================================================== */
function bindUnitSegment() {
  qsa('#unit-seg button').forEach(function (btn) {
    btn.addEventListener('click', function () {
      _unitMode = 'manual';
      _manualUnit = btn.getAttribute('data-unit');
      applyUnit(_manualUnit);
      saveState();
    });
  });
  var autoBtn = $('unit-model');
  if (autoBtn) {
    autoBtn.addEventListener('click', function () {
      _unitMode = 'auto';
      applyUnit(_modelUnit);
      saveState();
    });
  }
}

function applyUnit(unit) {
  _activeUnit = UNIT_LIST.indexOf(unit) >= 0 ? unit : _modelUnit;
  qsa('#unit-seg button').forEach(function (b) {
    b.classList.toggle('on', _activeUnit === b.getAttribute('data-unit'));
  });
  var autoBtn = $('unit-model');
  if (autoBtn) { autoBtn.classList.toggle('tie', _unitMode === 'auto'); }
  qsa('.unit-chip[data-unit-for]').forEach(function (chip) {
    chip.textContent = _activeUnit;
  });
}

/* ================================================================== *
 * CHIP GROUPS
 * ================================================================== */
var CHIP_ATTRS = {
  'corner-mode':     { attr: 'data-mode',    key: 'corner_mode' },
  'pillow-form':     { attr: 'data-form',    key: 'pillow_form' },
  'mattress-style':  { attr: 'data-style',   key: 'mattress_style' },
  'mattress-pattern':{ attr: 'data-pattern', key: 'mattress_pattern' },
  'wall-style':      { attr: 'data-style',   key: 'wall_style' },
  'ceiling-style':   { attr: 'data-style',   key: 'ceiling_style' },
  'pushpull-mode':   { attr: 'data-mode',    key: 'pushpull_mode' },
  'cutout-shape':    { attr: 'data-shape',   key: 'cutout_shape' },
  'loft-style':      { attr: 'data-style',   key: 'loft_style' },
  'pipe-caps':       { attr: 'data-caps',    key: 'pipe_caps' },
  'batch-mode':      { attr: 'data-mode',    key: 'batch_mode' }
};

var _chips = {};   /* group id -> selected value */

function bindChips() {
  Object.keys(CHIP_ATTRS).forEach(function (groupId) {
    _chips[groupId] = '';
    var spec = CHIP_ATTRS[groupId];
    var groupEl = $(groupId);
    if (!groupEl) { return; }
    qsa('#' + groupId + ' .chip').forEach(function (chip) {
      chip.addEventListener('click', function () {
        var value = chip.getAttribute(spec.attr);
        qsa('#' + groupId + ' .chip').forEach(function (c) {
          c.classList.remove('on');
        });
        chip.classList.add('on');
        _chips[groupId] = value;
        onChipChanged(groupId, value);
        updateRows();
        saveState();
      });
    });
    /* remember the pre-selected chip in the markup */
    var on = groupEl.querySelector('.chip.on');
    if (on) { _chips[groupId] = on.getAttribute(spec.attr); }
  });
}

function setChip(groupId, value) {
  var spec = CHIP_ATTRS[groupId];
  if (!spec) { return; }
  var groupEl = $(groupId);
  if (!groupEl) { return; }
  qsa('#' + groupId + ' .chip').forEach(function (c) {
    c.classList.toggle('on', c.getAttribute(spec.attr) === value);
  });
  _chips[groupId] = value;
  onChipChanged(groupId, value);
  updateRows();
}

function onChipChanged(groupId, value) {
  if (groupId === 'pillow-form') {
    try { sketchup.update_pillow_form({ 'form': value }); } catch (e) { }
  }
}

/* Show / hide conditional rows */
function updateRows() {
  var cornerManual = $('corner-manual');
  if (cornerManual) {
    cornerManual.style.display = _chips['corner-mode'] === 'manual' ? 'flex' : 'none';
  }
  var wavesRow = $('wall-waves-row');
  if (wavesRow) {
    wavesRow.style.display = _chips['wall-style'] === 'wave' ? 'flex' : 'none';
  }
  var rectRow = $('cutout-rect-row');
  var circleRow = $('cutout-circle-row');
  if (rectRow && circleRow) {
    var shape = _chips['cutout-shape'];
    rectRow.style.display = shape === 'circle' ? 'none' : 'flex';
    circleRow.style.display = shape === 'circle' ? 'flex' : 'none';
  }
  var batchManual = $('batch-manual');
  if (batchManual) {
    batchManual.style.display = _chips['batch-mode'] === 'manual' ? 'flex' : 'none';
  }
}

/* ================================================================== *
 * SLIDERS
 * ================================================================== */
function bindSliders() {
  qsa('.slider-row input[type=range]').forEach(function (range) {
    var outId = range.id.replace(/^in-/, 'v-');
    var readout = $(outId);
    var sync = function () {
      if (readout) { readout.textContent = range.value; }
    };
    range.addEventListener('input', function () {
      sync();
      saveState();
    });
    sync();
  });
}

/* ================================================================== *
 * FABRIC SWATCHES
 * ================================================================== */
function bindSwatches() {
  qsa('.swatches').forEach(function (card) {
    var group = card.getAttribute('data-swatch-group');
    Array.prototype.forEach.call(card.querySelectorAll('.dot'), function (dot) {
      dot.addEventListener('click', function () {
        var color = dot.getAttribute('data-color');
        Array.prototype.forEach.call(card.querySelectorAll('.dot'), function (d) {
          d.classList.remove('on');
        });
        dot.classList.add('on');
        _colors[group] = color;
        saveState();
      });
    });
    var on = card.querySelector('.dot.on');
    if (on) { _colors[group] = on.getAttribute('data-color'); }
  });
}

/* ================================================================== *
 * DICE (fabric seeds)
 * ================================================================== */
function bindDice() {
  Object.keys(_seeds).forEach(function (tool) {
    var btn = $(tool + '-dice');
    if (!btn) { return; }
    btn.addEventListener('click', function () {
      rollSeed(tool);
    });
  });
}

function rollSeed(tool) {
  _seeds[tool] = 1 + Math.floor(Math.random() * 99998);
  var label = $(tool + '-seed-label');
  if (label) { label.textContent = 'seed ' + _seeds[tool]; }
  saveState();
}

/* ================================================================== *
 * LENGTH INPUTS  (pillow height pushes live settings for the click tool)
 * ================================================================== */
function bindLengthInputs() {
  Object.keys(_seeds).forEach(function (tool) {
    var label = $(tool + '-seed-label');
    if (label) { label.textContent = 'seed ' + _seeds[tool]; }
  });

  var pillowHeight = $('in-pillow-height');
  if (pillowHeight) {
    pillowHeight.addEventListener('change', function () {
      try { sketchup.update_pillow_height({ 'height': txt('in-pillow-height'), 'unit': _activeUnit }); } catch (e) { }
      saveState();
    });
  }
}

/* ================================================================== *
 * SELECTION STATUS
 * ================================================================== */
function updateSelectionStatus(payload) {
  var card = $('status-card');
  var msg = $('status-message');
  if (!card) { return; }
  var ok = payload && payload.valid === true;
  card.classList.remove('checking', 'valid', 'invalid');
  card.classList.add(ok ? 'valid' : 'invalid');
  if (msg) { msg.textContent = (payload && payload.message) ? payload.message : ''; }
}

/* ================================================================== *
 * APPLY DISPATCH
 * ================================================================== */
function currentColor(group, fallback) {
  var c = _colors[group];
  return (c === undefined || c === null || c === '') ? fallback : c;
}

function applyAction(actionName) {
  if (_busy) { return; }
  try {
    sketchup[actionName]();
  } catch (e) {
    toast('Could not reach SketchUp: ' + e.message);
  }
}

function runApply() {
  if (_busy) { return; }
  var actionMap = {
    'corners':         'apply_rounding',
    'pillow':          'apply_pillow',
    'mattress':        'apply_mattress',
    'cushion':         'apply_cushion',
    'drape':           'apply_drape',
    'wall_curve':      'apply_wall_curve',
    'ceiling_curve':   'apply_ceiling_curve',
    'curved_pushpull': 'apply_curved_pushpull',
    'cutout':          'apply_opening',
    'loft':            'apply_loft',
    'pipe':            'apply_pipe',
    'utilities':       'batchSoftener'
  };
  var action = actionMap[_tool];
  if (!action) { return; }
  if (action === 'batchSoftener') { applyBatch(); return; }

  var params = collectParams(_tool, action);
  if (params === null) { return; }

  _busy = true;
  var btn = $('btn-apply');
  if (btn) { btn.disabled = true; btn.textContent = 'Working...'; }
  try {
    sketchup[action](params);
  } catch (e) {
    _busy = false;
    opDone(false, 'Could not reach SketchUp: ' + e.message);
  }
}

/* Per-tool parameter assembly - keys match exactly what Ruby reads. */
function collectParams(tool, action) {
  var u = _activeUnit;
  switch (tool) {
    case 'corners':
      var mode = _chips['corner-mode'] || 'auto';
      var radius = mode === 'manual' ? txt('in-corners-radius') : '';
      if (mode === 'manual' && radius === '') {
        toast('Enter a radius first.');
        return null;
      }
      return { 'mode': mode, 'radius': radius, 'unit': u };

    case 'pillow':
      return {
        'height': txt('in-pillow-height'), 'unit': u,
        'form': _chips['pillow-form'] || 'sofa',
        'drape': num('in-pillow-drape'), 'puff': num('in-pillow-puff'),
        'wrinkle': num('in-pillow-wrinkle'), 'detail': num('in-pillow-detail'),
        'seed': _seeds.pillow,
        'rest': cbx('in-pillow-rest'),
        'piping': cbx('in-pillow-piping'),
        'top_piping': false,
        'color': _colors.pillow || ''
      };

    case 'mattress':
      return {
        'thickness': txt('in-mattress-thickness'), 'unit': u,
        'style': _chips['mattress-style'] || 'classic',
        'pattern': _chips['mattress-pattern'] || 'grid',
        'tuft': cbx('in-mattress-tuft'),
        'bulge': num('in-mattress-bulge'),
        'seed': 5,
        'color': _colors.mattress || ''
      };

    case 'cushion':
      return {
        'height': txt('in-cushion-height'), 'unit': u,
        'rest': cbx('in-cushion-rest'),
        'wrinkle': num('in-cushion-wrinkle'),
        'detail': num('in-cushion-detail'),
        'seed': _seeds.cushion,
        'color': _colors.cushion || ''
      };

    case 'drape':
      return {
        'drop': txt('in-drape-drop'), 'unit': u,
        'flare': num('in-drape-flare'),
        'wrinkle': num('in-drape-wrinkle'),
        'detail': num('in-drape-detail'),
        'seed': _seeds.drape,
        'color': _colors.drape || ''
      };

    case 'wall_curve':
      var waves = _chips['wall-style'] === 'wave' ? txt('in-wall-waves') : '2';
      return {
        'height': txt('in-wall-height'),
        'amplitude': txt('in-wall-amp'),
        'unit': u,
        'style': _chips['wall-style'] || 'bulge',
        'waves': waves,
        'wrinkle': num('in-wall-wrinkle'),
        'detail': num('in-wall-detail'),
        'seed': _seeds.wall
      };

    case 'ceiling_curve':
      return {
        'radius': txt('in-ceiling-radius'), 'unit': u,
        'style': _chips['ceiling-style'] || 'cove',
        'segments': txt('in-ceiling-segments')
      };

    case 'curved_pushpull':
      return {
        'distance': txt('in-pushpull-distance'), 'unit': u,
        'mode': _chips['pushpull-mode'] || 'normal'
      };

    case 'cutout':
      var shape = _chips['cutout-shape'] || 'rect';
      var w = shape === 'circle' ? txt('in-cutout-diameter') : txt('in-cutout-width');
      var h = shape === 'circle' ? txt('in-cutout-diameter') : txt('in-cutout-height');
      return {
        'shape': shape, 'width': w, 'height': h, 'unit': u,
        'offsetU': txt('in-cutout-offx'), 'offsetV': txt('in-cutout-offy'),
        'depth': txt('in-cutout-depth'),
        'rounded': cbx('in-cutout-rounded')
      };

    case 'loft':
      return {
        'segments': txt('in-loft-segments'),
        'style': _chips['loft-style'] || 'ruled',
        'capStart': cbx('in-loft-capstart'),
        'capEnd': cbx('in-loft-capend')
      };

    case 'pipe':
      return {
        'outerDiameter': txt('in-pipe-outer'),
        'innerDiameter': txt('in-pipe-inner'),
        'sides': txt('in-pipe-sides'),
        'caps': _chips['pipe-caps'] || 'none',
        'unit': u
      };
  }
  return {};
}

function applyBatch() {
  if (_busy) { return; }
  var mode = _chips['batch-mode'] || 'auto';
  var radius = mode === 'manual' ? txt('in-batch-radius') : '';
  if (mode === 'manual' && radius === '') {
    toast('Enter a radius first.');
    return;
  }
  _busy = true;
  var btn = $('btn-apply');
  if (btn) { btn.disabled = true; btn.textContent = 'Working...'; }
  try {
    sketchup.apply_batch_soften({ 'mode': mode, 'radius': radius, 'unit': _activeUnit });
  } catch (e) {
    _busy = false;
    opDone(false, 'Could not reach SketchUp: ' + e.message);
  }
}

/* Ruby answers geometry ops here */
function opDone(ok, message) {
  _busy = false;
  var btn = $('btn-apply');
  if (btn) {
    btn.disabled = false;
    btn.textContent = APPLY_LABELS[_tool] || 'Apply';
  }
  if (message && String(message).length > 0) {
    if (ok) { toast(message); } else { toast('' + message); }
  }
  try { sketchup.check_selection(); } catch (e) { }
}

/* ================================================================== *
 * STATE PERSISTENCE
 * ================================================================== */
var FIELD_IDS = [
  'in-corners-radius',
  'in-pillow-height', 'in-pillow-drape', 'in-pillow-puff',
  'in-pillow-wrinkle', 'in-pillow-detail', 'in-pillow-rest', 'in-pillow-piping',
  'in-mattress-thickness', 'in-mattress-bulge', 'in-mattress-tuft',
  'in-cushion-height', 'in-cushion-wrinkle', 'in-cushion-detail', 'in-cushion-rest',
  'in-drape-drop', 'in-drape-flare', 'in-drape-wrinkle', 'in-drape-detail',
  'in-wall-height', 'in-wall-amp', 'in-wall-waves', 'in-wall-wrinkle', 'in-wall-detail',
  'in-ceiling-radius', 'in-ceiling-segments',
  'in-pushpull-distance',
  'in-cutout-width', 'in-cutout-height', 'in-cutout-diameter',
  'in-cutout-offx', 'in-cutout-offy', 'in-cutout-depth', 'in-cutout-rounded',
  'in-loft-segments', 'in-loft-capstart', 'in-loft-capend',
  'in-pipe-outer', 'in-pipe-inner', 'in-pipe-sides',
  'in-batch-radius'
];

function gatherState() {
  var fields = {};
  FIELD_IDS.forEach(function (id) {
    var el = $(id);
    if (!el) { return; }
    fields[id] = el.type === 'checkbox' ? el.checked : el.value;
  });
  var chips = {};
  Object.keys(_chips).forEach(function (g) { chips[g] = _chips[g]; });
  return {
    'tool': _tool,
    'unitMode': _unitMode,
    'unit': _manualUnit,
    'fields': fields,
    'chips': chips,
    'colors': _colors,
    'seeds': _seeds
  };
}

function saveState() {
  if (_saveTimer) { clearTimeout(_saveTimer); }
  _saveTimer = setTimeout(function () {
    try { sketchup.save_state(gatherState()); } catch (e) { }
  }, 350);
}

function applySavedState(state) {
  if (!state) { return; }
  if (state.unitMode === 'auto') {
    _unitMode = 'auto';
    applyUnit(_modelUnit);
  } else if (state.unit) {
    _unitMode = 'manual';
    _manualUnit = state.unit;
    applyUnit(state.unit);
  }
  if (state.fields) {
    Object.keys(state.fields).forEach(function (id) {
      var el = $(id);
      if (!el) { return; }
      if (el.type === 'checkbox') {
        el.checked = state.fields[id] === true || state.fields[id] === 'true';
      } else {
        el.value = state.fields[id];
      }
    });
  }
  if (state.chips) {
    Object.keys(state.chips).forEach(function (g) {
      setChip(g, state.chips[g]);
    });
  }
  if (state.colors) {
    Object.keys(state.colors).forEach(function (group) {
      var card = document.querySelector('.swatches[data-swatch-group="' + group + '"]');
      if (!card) { return; }
      var want = state.colors[group];
      Array.prototype.forEach.call(card.querySelectorAll('.dot'), function (d) {
        d.classList.toggle('on', d.getAttribute('data-color') === want);
      });
      _colors[group] = want;
    });
  }
  if (state.seeds) {
    Object.keys(state.seeds).forEach(function (t) {
      _seeds[t] = parseInt(state.seeds[t], 10) || _seeds[t];
      var label = $(t + '-seed-label');
      if (label) { label.textContent = 'seed ' + _seeds[t]; }
    });
  }
  /* refresh slider readouts after restore */
  qsa('.slider-row input[type=range]').forEach(function (range) {
    var out = $(range.id.replace(/^in-/, 'v-'));
    if (out) { out.textContent = range.value; }
  });
  if (state.tool) { switchTool(state.tool); }
}

/* ================================================================== *
 * UPDATES
 * ================================================================== */
function openUpdates() {
  openProfile('updates');
}

function openProfile(tab) {
  var modal = $('profile-modal');
  if (!modal) { return; }
  modal.classList.add('open');
  showMtab(tab === 'updates' ? 'updates' : (tab === 'about' ? 'about' : 'license'));
}

function closeProfile() {
  var modal = $('profile-modal');
  if (modal) { modal.classList.remove('open'); }
}

function showMtab(tab) {
  qsa('.mtab').forEach(function (b) {
    b.classList.toggle('on', b.getAttribute('data-mtab') === tab);
  });
  ['license', 'updates', 'about'].forEach(function (t) {
    var body = $('mtab-' + t);
    if (body) { body.classList.toggle('on', t === tab); }
  });
}

function bindMtabs() {
  qsa('.mtab').forEach(function (b) {
    b.addEventListener('click', function () {
      showMtab(b.getAttribute('data-mtab'));
    });
  });
}

function showUpdateCard(data) {
  _updateCard = data;
  var banner = $('update-banner');
  if (!banner) { return; }
  var title = $('ub-title');
  var notes = $('ub-notes');
  if (title) {
    title.textContent = 'Version ' + data.version + ' is ready';
  }
  if (notes) {
    notes.textContent = data.notes && String(data.notes).length > 0
      ? trimText(data.notes, 70) : 'Fresh release from the studio.';
  }
  banner.style.display = 'flex';
  var dot = $('update-dot');
  if (dot) { dot.style.display = ''; }
}

function trimText(s, n) {
  s = String(s);
  return s.length > n ? s.slice(0, n - 1) + '\u2026' : s;
}

function downloadUpdate() {
  if (!_updateCard) { return; }
  toast('Downloading version ' + _updateCard.version + '...');
  try { sketchup.update_download(); } catch (e) { toast('Download failed to start.'); }
}

function showUpdateDownloaded(data) {
  _updatePath = data.path;
  var banner = $('update-downloaded');
  if (!banner) { return; }
  var title = $('ud-title');
  var pathEl = $('ud-path');
  if (title) { title.textContent = 'Plush ' + data.version + ' package saved'; }
  if (pathEl) { pathEl.textContent = shortPath(data.path); }
  banner.style.display = 'flex';
}

function shortPath(p) {
  p = String(p);
  if (p.length <= 40) { return p; }
  return p.slice(0, 16) + '\u2026' + p.slice(p.length - 22);
}

function runInstaller() {
  if (!_updatePath) { return; }
  try {
    sketchup.update_install({ 'path': _updatePath });
  } catch (e) { toast('Could not start the installer.'); }
}

function installRequested(ok) {
  var banner = $('update-downloaded');
  if (banner && ok) {
    setTimeout(function () { banner.style.display = 'none'; }, 1200);
  }
  toast(ok ? 'Handing the package to SketchUp - confirm the prompt to finish.'
           : 'The installer declined to open.');
}

function updateCheckResult(payload) {
  var box = $('upd-result');
  if (box && payload && payload.message && String(payload.message).length > 0) {
    box.textContent = payload.message;
  }
  var remote = $('upd-remote');
  if (remote) {
    remote.textContent = payload && payload.update ? payload.update.version : '\u2014';
  }
  if (payload && payload.ok === false && payload.message) {
    toast(payload.message);
  }
}

function applyUpdateInfo(info) {
  if (!info) { return; }
  var current = $('upd-current');
  if (current) { current.textContent = info.version || '\u2014'; }
  var about = $('about-version');
  if (about) { about.textContent = 'Plush ' + (info.version || '') + ' by ArchInsights'; }
  var badge = $('about-version-badge');
  if (badge && info.version) { badge.textContent = info.version; }
  var feed = $('upd-feed');
  if (feed && info.feed) { feed.value = info.feed; }
  var last = $('upd-last');
  if (last) {
    last.textContent = info.last_check && String(info.last_check).length > 0
      ? formatStamp(info.last_check) : 'never';
  }
  var auto = $('upd-auto');
  if (auto) { auto.checked = info.auto === true; }
  if (info.environment) {
    var su = $('env-sketchup');
    if (su) { su.textContent = info.environment.app_version || '-'; }
    var rb = $('env-ruby');
    if (rb) { rb.textContent = 'Ruby ' + (info.environment.ruby_version || '-'); }
  }
}

function formatStamp(stamp) {
  var s = String(stamp);
  if (s.length !== 10) { return s; }
  return s.slice(0, 4) + '-' + s.slice(4, 6) + '-' + s.slice(6, 8) + ' ' + s.slice(8, 10) + 'h';
}

function applyUpdatePrefs(autoOn) {
  var auto = $('upd-auto');
  if (auto) { auto.checked = autoOn === true; }
  toast('Update preferences saved.');
}

function dismissUpdate() {
  var banner = $('update-banner');
  if (banner) { banner.style.display = 'none'; }
  if (_updateCard) {
    try { sketchup.dismiss_update({ 'version': _updateCard.version }); } catch (e) { }
  }
}

function checkNow() {
  var box = $('upd-result');
  if (box) { box.textContent = 'Knocking on the release feed...'; }
  try { sketchup.check_update_now(); } catch (e) {
    if (box) { box.textContent = 'Could not reach the release feed.'; }
  }
}

function saveUpdatePrefs(includeFeed) {
  var auto = cbx('upd-auto');
  var feed = includeFeed === true ? txt('upd-feed') : '';
  try {
    sketchup.set_update_prefs({ 'auto': auto, 'feed': feed });
  } catch (e) {
    toast('Could not save preferences.');
  }
}

/* ================================================================== *
 * LICENSE
 * ================================================================== */
function updateLicenseStatus(payload) {
  if (!payload) { return; }
  var active = $('lic-active');
  var inactive = $('lic-inactive');
  var activated = payload.activated === true;
  if (active && inactive) {
    active.style.display = activated ? '' : 'none';
    inactive.style.display = activated ? 'none' : '';
  }
  if (activated) {
    var email = $('lic-email');
    var reg = $('lic-reg');
    var exp = $('lic-exp');
    var kind = $('lic-kind');
    if (email) { email.textContent = payload.email || '-'; }
    if (reg) { reg.textContent = payload.reg_date || '-'; }
    if (exp) { exp.textContent = payload.exp_date || '-'; }
    if (kind) { kind.textContent = payload.kind || 'Commercial'; }
  }
  var hwid = $('act-hwid');
  if (hwid && payload.fingerprint) { hwid.value = payload.fingerprint; }
}

function submitActivation() {
  var email = txt('act-email');
  var key = txt('act-key');
  if (email.length === 0 || key.length === 0) {
    toast('Fill in the email and the license key.');
    return;
  }
  var btn = $('btn-activate');
  if (btn) { btn.disabled = true; btn.textContent = 'Checking...'; }
  try {
    sketchup.activate_online({ 'email': email, 'key': key });
  } catch (e) {
    toast('Activation could not start.');
  }
  if (btn) {
    btn.disabled = false;
    btn.textContent = 'Activate';
  }
}

/* Offline helper callbacks, kept for API parity with the generator tool */
function onOnlineActivationSuccess(payload) {
  try { sketchup.on_activation_success(payload); } catch (e) { }
}

function onOnlineActivationOffline(payload) {
  try { sketchup.on_activation_offline_fallback(payload); } catch (e) { }
}

function removeLicense() {
  try { sketchup.remove_license(); } catch (e) { toast('Could not remove the license.'); }
}

/* ================================================================== *
 * TOAST / ALERT
 * ================================================================== */
function uiAlert(message) {
  toast(message);
}

function toast(message) {
  var host = $('toast');
  if (!host) { return; }
  host.textContent = String(message);
  host.classList.add('show');
  if (_toastTimer) { clearTimeout(_toastTimer); }
  _toastTimer = setTimeout(function () {
    host.classList.remove('show');
  }, 2800);
}

/* ================================================================== *
 * WINDOW CONTROLS
 * ================================================================== */
function toggleMinimize() {
  _minimized = !_minimized;
  try { sketchup.set_window_minimized(_minimized); } catch (e) { }
  var btn = $('btn-collapse');
  if (btn) { btn.classList.toggle('alarm', _minimized); }
}

function toggleMaximize() {
  _maximized = !_maximized;
  try { sketchup.set_window_maximized(_maximized); } catch (e) { }
  var btn = $('btn-max');
  if (btn) { btn.classList.toggle('alarm', _maximized); }
}

function closeDialog() {
  if (_tool === 'pillow') {
    try { sketchup.deactivate_pillow_tool(); } catch (e) { }
  }
  try { sketchup.close_dialog(); } catch (e) { }
}

function setWorkspaceUnit(unitName) {
  _modelUnit = UNIT_LIST.indexOf(unitName) >= 0 ? unitName : 'cm';
  if (_unitMode === 'auto') { applyUnit(_modelUnit); }
  var envUnits = $('env-units');
  if (envUnits) {
    envUnits.textContent = (_unitMode === 'auto' ? 'Auto - ' : '') + _modelUnit;
  }
}

/* ================================================================== *
 * BOOT
 * ================================================================== */
document.addEventListener('DOMContentLoaded', function () {
  bindUnitSegment();
  bindMtabs();

  /* footer apply button */
  var btn = $('btn-apply');
  if (btn) {
    btn.addEventListener('click', runApply);
  }

  /* logo acts as the profile button */
  var logo = document.querySelector('.brand-mark');
  if (logo) {
    logo.addEventListener('click', function () { openProfile('license'); });
    logo.style.cursor = 'pointer';
  }
});
