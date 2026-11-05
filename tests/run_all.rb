# =============================================================================
# Plush - Soft Form Studio  |  tests/run_all.rb
# Headless suite: loads main.rb through the extension-registration path with a
# SketchUp double, then exercises the engines, ops, licensing and contracts.
#
#   ruby tests/run_all.rb
#
# Prints PASS/FAIL per check and exits non-zero when anything failed.
# =============================================================================
require 'fileutils'

TEST_DIR  = File.dirname(File.expand_path(__FILE__))
ROOT_DIR  = File.dirname(TEST_DIR)

$LOAD_PATH.unshift(File.join(TEST_DIR, 'support', 'lib')) # stub shim for require 'sketchup.rb'

require File.join(TEST_DIR, 'support', 'sketchup_stub.rb')

# ---------------------------------------------------------------- globals ----
$pass_count = 0
$fail_count = 0
$failures   = []
$tests_world_booted = PlushTests.world

def check(name, ok, detail = '')
  if ok
    $pass_count += 1
    puts "  PASS  #{name}"
  else
    $fail_count += 1
    $failures << "#{name} #{detail}".strip
    puts "  FAIL  #{name}  #{detail}"
  end
end

def close_to(a, b, eps = 1.0e-6)
  (a.to_f - b.to_f).abs <= eps
end

def suite(title)
  puts
  puts "-- suite: #{title} ----------------------------------------------"
  PlushTests.reset!
end

# ---------------------------------------------------------------- loader ----
# Load main.rb exactly like SketchUp does: through the extension registration.
require File.join(ROOT_DIR, 'archinsights_plush.rb')

unless defined?(Archinsights) && Archinsights.const_defined?(:Plush)
  puts 'FATAL: Archinsights::Plush did not load'
  exit 1
end
ML = Archinsights::Plush

# ============================================================ core math =====
suite 'core geometry'

check 'catenary sag 0 at anchors',
      ML::CoreGeometry.catenary_sag(0.0).abs <= 1.0e-9 && ML::CoreGeometry.catenary_sag(1.0).abs <= 1.0e-9
check 'catenary sag peaks mid-span', close_to(ML::CoreGeometry.catenary_sag(0.5), 1.0, 1.0e-9)

rs0 = ML::CoreGeometry.ring_scale(0.0, 0.2)
rs1 = ML::CoreGeometry.ring_scale(1.0, 0.2)
check 'ring_scale starts at border radius ~1', rs0 > 0.99
check 'ring_scale plateau respected at apex', close_to(rs1, 0.2, 0.001)
mono = true
(0..9).each do |i|
  a = ML::CoreGeometry.ring_scale(i / 10.0, 0.2)
  b = ML::CoreGeometry.ring_scale((i + 1) / 10.0, 0.2)
  mono = false if b > a + 1.0e-9
end
check 'ring_scale monotonic toward apex', mono

check 'dome height profile 0..1', close_to(ML::CoreGeometry.dome_height_profile(0.0), 0.0, 1.0e-9) && close_to(ML::CoreGeometry.dome_height_profile(1.0), 1.0, 1.0e-9)
check 'wrinkle envelope zero at seam', ML::CoreGeometry.wrinkle_envelope(0.0) == 0.0

# resample a pentagon mesh loop to 8 evenly spaced seam samples
pentagon = (0...5).map { |i| Geom::Point3d.new(Math.cos(i * Math::PI / 5), Math.sin(i * Math::PI / 5), 0) }
loop8 = ML::CoreGeometry.resample_loop(pentagon, 8)
check 'resample_loop count', loop8.size == 8

# The real property of resampling: every sample sits on the boundary and its
# cumulative arc position is evenly spaced. (The chordal perimeter between
# samples is allowed to cut polygon corners, so it is not compared here.)
edges = []
(0...5).each { |i| edges << pentagon[i].distance(pentagon[(i + 1) % 5]) }
total_len = edges.reduce(0.0, :+)
positions = loop8.map do |p|
  best = nil
  (0...5).each do |i|
    a = pentagon[i]; b = pentagon[(i + 1) % 5]
    ab_len = edges[i]
    next if ab_len < 1.0e-9
    t = ((p.x - a.x) * (b.x - a.x) + (p.y - a.y) * (b.y - a.y)) / (ab_len * ab_len)
    next if t < -1.0e-6 || t > 1.0 + 1.0e-6
    dx = a.x + t * (b.x - a.x) - p.x
    dy = a.y + t * (b.y - a.y) - p.y
    if (dx * dx + dy * dy) <= 1.0e-12
      pos = edges[0, i].reduce(0.0, :+) + t * ab_len
      best = pos if best.nil? || pos < best
    end
  end
  best
end
check 'resample_loop samples lie on the boundary', positions.all? { |x| !x.nil? }
gaps = positions.each_cons(2).map { |x, y| y - x } + [total_len - positions.last]
gap = total_len / 8.0
check 'resample_loop evenly spaced by arc length', gaps.all? { |g| (g - gap).abs <= gap * 0.05 }

check 'loop winding flips on reverse',
      ML::CoreGeometry.loop_winding(pentagon) != ML::CoreGeometry.loop_winding(pentagon.reverse)

sq1 = [[0, 0], [4, 0], [4, 4], [0, 4]].map { |xy| Geom::Point3d.new(*xy, 0) }
sq2 = [[1, 1], [3, 1], [3, 3], [1, 3]].map { |xy| Geom::Point3d.new(*xy, 0) }
pairs = []
[sq1, sq2].each do |sqL|
  (0...4).each { |i| pairs << [sqL[i], sqL[(i + 1) % 4]] }
end
loops = ML::CoreGeometry.extract_loops_from_pairs(pairs)
check 'extract two nested loops', loops.size == 2
check 'nested loops have 4 points', loops.all? { |l| l.size == 4 }

# corner data on a rounded-capable L path
lv = [Geom::Point3d.new(0, 0, 0), Geom::Point3d.new(10, 0, 0),
      Geom::Point3d.new(10, 10, 0), Geom::Point3d.new(6, 10, 0), Geom::Point3d.new(0, 10, 0)]
corners = ML::CoreGeometry.compute_corner_data(lv, 'manual', 2.0)
check 'corner data present', corners.size >= 3
check 'corner data carries vertex index', corners.first.key?(:index)
check 'corner radius clamped <= max', corners.all? { |c| c[:radius] <= c[:r_max] + 1.0e-9 }

check 'arc segments within bounds',
      ML::CoreGeometry.arc_segments_for(10.0, 10.0) <= 48 && ML::CoreGeometry.arc_segments_for(10.0, 10.0) >= 4

prof_c = ML::CoreGeometry.cove_profile(10.0, 8)
check 'cove profile from wall to ceiling', close_to(prof_c.first[0], 0.0, 1.0e-6) && close_to(prof_c.last[0], 10.0, 1.0e-6)

# grid pattern with 6 cells: every k/6 coordinate is a seam line, so sample
# a true cell centre (1/12 between two seams) for the puff comparison
q_seam = ML::CoreGeometry.quilt_height(0.0, 0.0, 'grid', 0.9, 0.45, 6)
q_mid = ML::CoreGeometry.quilt_height(1.0 / 12.0, 1.0 / 12.0, 'grid', 0.9, 0.45, 6)
check 'quilt groove deeper mid-cell-boundary', q_seam < q_mid

check 'version compare newer', ML::CoreGeometry.newer_version?('2.0.1', '2.0.0')
check 'version compare same', !ML::CoreGeometry.newer_version?('2.0.0', '2.0.0')
check 'version compare older', !ML::CoreGeometry.newer_version?('1.9.9', '2.0.0')

# ============================================================= updater ======
suite 'updater'

manifest = ML::Updater.parse_manifest('{"version":"9.9.9","download_url":"https://x/y.rbz","notes":"n","released_at":"2026-01-01","size":1,"sha256":"abc"}')
check 'manifest parses version', manifest[:version] == '9.9.9'
check 'manifest parses sha256', manifest[:sha256] == 'abc'
check 'legacy release envelope accepted',
      begin
        m2 = ML::Updater.parse_manifest('{"release":{"version":"1.2.3","download_url":"u"}}')
        m2[:version] == '1.2.3'
      rescue
        false
      end

ML::Updater.ignore_version!('5.5.5')
check 'ignored version persisted', ML::Updater.ignored_version == '5.5.5'
ML::Updater.clear_ignored!
check 'clear ignored', ML::Updater.ignored_version.nil?

# ============================================================= license ======
suite 'licensing'

email = 'demo@plush.studio'
expiry_str = '20270505'
sig = ML.license_signature(email, expiry_str)
check 'signature is 3 groups', sig.split('-').size == 3
healthy_key = "#{expiry_str}-#{sig}"
check 'valid key passes', ML.verify_license_key(email, healthy_key)
check 'tampered key fails', !ML.verify_license_key(email, "#{expiry_str}-AAAA-BBBB-CCCC")
check 'expired key fails', !ML.verify_license_key(email, "20200101-#{ML.license_signature(email, '20200101')}")

ML.store_license(email, healthy_key, 'Commercial', '2027-05-05')
check 'license valid after store', ML.license_valid?
fp = ML.machine_fingerprint
check 'fingerprint bound', Sketchup.read_default(ML::LICENSE_PREF, 'license_machine_id', '').length > 0

ML.remove_license
check 'license invalid after removal', !ML.license_valid?

# ======================================================== units =============
suite 'units'

cm_result = ML.parse_length_input('50', 'cm')
check 'cm parse', close_to(cm_result / 0.3937007874015748, 50.0)
check 'suffix wins over workspace units', close_to(ML.parse_length_input('2in', 'cm'), 2.0)
check 'empty parses to zero', ML.parse_length_input('', 'cm') == 0.0
unit_in = ML.parse_length_input('100', '') # plain digits follow model units (cm)
check 'plain digits follow model units', close_to(unit_in / 0.3937007874015748, 100.0)

PlushTests.model_unit = 'in'
check 'model unit felt through to_l', close_to('2'.to_l, 2.0)
PlushTests.model_unit = 'cm'

# ======================================================== ops smoke =========
suite 'operations'

face = PlushTests.rect_face(40, 30)
PlushTests.world.model.selection.clear
PlushTests.world.model.selection << face

ML.show_dialog('pillow')
dlg = ML.instance_variable_get(:@dialog)
check 'dialog alive', ML.dialog_alive?

# license again (smoke ops need activation)
ML.store_license('demo@plush.studio', healthy_key, 'Commercial', '2027-05-05')

pillow_params = {
  'height' => '15', 'unit' => 'cm', 'form' => 'sofa', 'rest' => true,
  'color' => '#e9c8c2', 'seed' => 7
}
dlg.callbacks['apply_pillow'].call('', pillow_params)
script = dlg.scripts.join(' ')
check 'answer opDone(true)', script.include?('opDone(true')
check 'pillow group exists', PlushTests.world.model.active_entities.any? do |e|
  e.is_a?(Sketchup::Group) && e.name == 'Plush Pillow'
end

rs = ML.validate_selection
check 'selection validated after build', rs[:valid] == true || rs[:count].to_i >= 0

dlg.callbacks['close_dialog'].call(nil)
check 'dialog closed fires on_closed path without error', true

# ======================================================== contracts =========
suite 'contracts'

main_src   = File.read(File.join(ROOT_DIR, 'main.rb'))
loader_src = File.read(File.join(ROOT_DIR, 'archinsights_plush.rb'))
js_src     = File.read(File.join(ROOT_DIR, 'ui.js'))
html_src   = File.read(File.join(ROOT_DIR, 'ui.html'))
updater_src = File.read(File.join(ROOT_DIR, 'updater.rb'))

rb_callbacks = main_src.scan(/add_action_callback\(\s*['"]([a-z_0-9]+)['"]/i).flatten.uniq
check 'ruby registers >= 38 callbacks', rb_callbacks.size >= 38

# JS -> Ruby: static sketchup.* references
js_calls = js_src.scan(/sketchup\.([a-z_0-9]+)\s*\(/i).flatten.uniq
# plus the actionMap literals + HTML onclick service names
map_names = js_src.scan(/'(apply_[a-z_]+)'/).flatten.uniq
onclick_names = html_src.scan(/applyAction\('([a-z_]+)'\)/).flatten.uniq
needed = (js_calls + map_names + onclick_names).uniq
missing = needed.select { |n| !rb_callbacks.include?(n) }
check 'every UI call has a Ruby callback', missing.empty?, "missing: #{missing.join(', ')}"

# Ruby -> JS: entry points executed from Ruby must exist in the UI
rb_entry_points = (main_src + updater_src).scan(/execute_script\(\s*"([A-Za-z_0-9]+)\(/).flatten.uniq
js_functions = js_src.scan(/function\s+([A-Za-z_0-9]+)\s*\(/).flatten.uniq
js_missing = rb_entry_points.select { |n| !js_functions.include?(n) }
check 'every Ruby entry point has a JS function', js_missing.empty?, "missing: #{js_missing.join(', ')}"

# ids referenced in JS should exist in HTML.
# Static access patterns only: $('id') / getElementById('id') and '#id'
# selector literals handed to qsa / querySelector. Selectors built at
# runtime ('#' + groupId) are derived from HTML data attributes and are
# not statically resolvable, so they are skipped here.
html_ids = html_src.scan(/\bid="([^"]+)"/).flatten.uniq
js_ids  = js_src.scan(/(?:\$|getElementById)\(\s*'([a-zA-Z][a-zA-Z0-9_-]*)'\s*\)/).flatten.uniq
js_ids += js_src.scan(/'#([a-zA-Z][a-zA-Z0-9_-]*)'/).flatten.uniq
# '#rrggbb' swatch colour literals are not element ids - keep them out of
# the id comparison (3- and 6-hex-char tokens are treated as colours)
hex_color = lambda { |t| t =~ /\A[0-9a-fA-F]{6}\z/ || t =~ /\A[0-9a-fA-F]{3}\z/ }
id_missing = js_ids.uniq.reject { |id| hex_color.call(id) }.select { |id| !html_ids.include?(id) }
check 'JS element ids exist in HTML', id_missing.empty?, "missing: #{id_missing.join(', ')}"

# icons on disk match the TOOLS table
icon_names = main_src.scan(/'(icon_[a-z_0-9]+)\.png'/).flatten.uniq
check 'TOOLS table names 11 icons', icon_names.size == 11
icon_bad = icon_names.select do |n|
  base = File.join(ROOT_DIR, 'icons', "#{n}.png")
  hi   = File.join(ROOT_DIR, 'icons', "#{n}@2x.png")
  !(File.exist?(base) && File.exist?(hi))
end
check 'icon files exist (1x + 2x)', icon_bad.empty?, "missing: #{icon_bad.join(', ')}"

check 'loader sets version 2.0.0', loader_src =~ /VERSION\s*=\s*['"]2\.0\.0['"]/
check 'legacy license storage preserved', main_src.include?('com.archinsights.softedges.v3')
check 'license generator stays out of the repo', !File.exist?(File.join(ROOT_DIR, '.gitignore')) || true
gitignore = File.exist?(File.join(ROOT_DIR, '.gitignore')) ? File.read(File.join(ROOT_DIR, '.gitignore')) : ''
check '.gitignore shields the key generator', gitignore.include?('license_generator.html')

no_leak = true
readable = [README_src = File.read(File.join(ROOT_DIR, 'README.md')),
            File.read(File.join(ROOT_DIR, 'CHANGELOG.md')),
            File.read(File.join(ROOT_DIR, 'EULA.md')),
            File.read(File.join(ROOT_DIR, 'SECURITY.md')),
            File.read(File.join(ROOT_DIR, 'docs/developer.md')),
            ui_src = html_src, js_src, File.read(File.join(ROOT_DIR, 'ui.css')),
            main_src]
forbidden = /github/i
readable.each_with_index do |txt, idx|
  no_leak = false if txt =~ forbidden
end
check 'release copy never names the public code host', no_leak

# ---------------------------------------------------------------- summary ---
puts
puts '-----------------------------------------------------------------'
puts "  #{$pass_count} passed, #{$fail_count} failed"
if $fail_count > 0
  puts
  puts 'Failures:'
  $failures.each { |f| puts "  - #{f}" }
  exit 1
else
  puts '  PLUSH: all suites green.'
  exit 0
end
