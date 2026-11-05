# =============================================================================
# Plush - Soft Form Studio  |  tests/support/sketchup_stub.rb
# A dependency-free double of the SketchUp / Geom surface that Plush touches.
# Loaded BEFORE main.rb so `require 'sketchup.rb'` resolves to a no-op shim.
# =============================================================================
require 'json'
require 'digest'
require 'tmpdir'

# Make fingerprints deterministic even on exotic shells.
ENV['COMPUTERNAME'] = 'PLUSH-TEST' if ENV['COMPUTERNAME'].to_s.empty?
ENV['USERPROFILE'] = 'C:\Users\plush-test' if ENV['USERPROFILE'].to_s.empty?

$plush_events = {
  :scripts       => [],
  :timers        => [],
  :messageboxes  => [],
  :opened_urls   => [],
  :registrations => [],
  :ops           => []
}
$plush_prefs = {}
$plush_load_once = {}

# ----------------------------------------------------------------------------
# Unit conversions (SketchUp keeps lengths in inches internally)
# ----------------------------------------------------------------------------
CM_IN_INCH   = 0.3937007874015748
MM_IN_INCH   = CM_IN_INCH / 10.0
M_IN_INCH    = 39.370078740157481

class ::Numeric
  def cm; self * CM_IN_INCH; end
  def mm; self * MM_IN_INCH; end
  def m;  self * M_IN_INCH;  end
  def ft; self * 12.0;       end
  def in; self * 1.0;        end
  def to_l; self * 1.0;      end
end

class ::String
  def to_l
    s = self.strip.gsub(' ', '')
    if s =~ /\A(-?\d*\.?\d+)\s*(mm|cm|m|in|ft|'|")\z/i
      v = $1.to_f
      u = $2.downcase
      return v * MM_IN_INCH if u == 'mm'
      return v * CM_IN_INCH if u == 'cm'
      return v * M_IN_INCH  if u == 'm'
      return v * 1.0        if u == 'in' || u == '"'
      return v * 12.0       if u == 'ft' || u == "'"
      return v
    elsif s =~ /\A(-?\d*\.?\d+)\z/
      # unitless: obey the stub model units (matches SketchUp behaviour)
      unit = $plush_world.model_unit
      return $1.to_f * CM_IN_INCH if unit == 'cm'
      return $1.to_f * MM_IN_INCH if unit == 'mm'
      return $1.to_f * M_IN_INCH  if unit == 'm'
      return $1.to_f * 12.0       if unit == 'ft'
      return $1.to_f
    end
    raise ArgumentError, "plush stub: cannot convert #{self.inspect} to a Length"
  end
end

# ----------------------------------------------------------------------------
# Geom
# ----------------------------------------------------------------------------
module Geom
  class Point3d
    attr_accessor :x, :y, :z

    def initialize(x = 0.0, y = 0.0, z = 0.0)
      if x.is_a?(Point3d)
        @x = x.x.to_f; @y = x.y.to_f; @z = x.z.to_f
      elsif x.is_a?(Array)
        @x = x[0].to_f; @y = x[1].to_f; @z = (x[2] || 0.0).to_f
      else
        @x = x.to_f; @y = y.to_f; @z = z.to_f
      end
    end

    def +(other)
      return Point3d.new(@x + other.x, @y + other.y, @z + other.z) if other.is_a?(Vector3d)
      raise ArgumentError, 'Point3d + Point3d is not defined'
    end

    def -(other)
      if other.is_a?(Point3d)
        Vector3d.new(@x - other.x, @y - other.y, @z - other.z)
      else
        Point3d.new(@x - other.x, @y - other.y, @z - other.z)
      end
    end

    def ==(other)
      other.is_a?(Point3d) && x == other.x && y == other.y && z == other.z
    end

    def distance(pt2)
      Math.sqrt((@x - pt2.x) ** 2 + (@y - pt2.y) ** 2 + (@z - pt2.z) ** 2)
    end

    # SketchUp semantics: offset(vector) or offset(unit_vector, distance)
    def offset(vec, dist = nil)
      if dist.nil?
        Point3d.new(@x + vec.x, @y + vec.y, @z + vec.z)
      else
        len = vec.length
        return Point3d.new(@x, @y, @z) if len < 1.0e-12
        k = dist / len
        Point3d.new(@x + vec.x * k, @y + vec.y * k, @z + vec.z * k)
      end
    end

    def transform(trans)
      trans.transform_point(self)
    end

    def clone
      Point3d.new(@x, @y, @z)
    end
    alias_method :dup, :clone

    def to_a
      [@x, @y, @z]
    end

    def vector_to(other)
      Vector3d.new(other.x - @x, other.y - @y, other.z - @z)
    end

    def to_s
      "(#{@x}, #{@y}, #{@z})"
    end

    def self.linear_combination(w1, p1, w2, p2)
      Point3d.new(w1 * p1.x + w2 * p2.x, w1 * p1.y + w2 * p2.y, w1 * p1.z + w2 * p2.z)
    end
  end

  class Vector3d
    attr_accessor :x, :y, :z

    def initialize(x = 0.0, y = 0.0, z = 0.0)
      @x = x.to_f; @y = y.to_f; @z = z.to_f
    end

    def +(other); Vector3d.new(@x + other.x, @y + other.y, @z + other.z); end
    def -(other); Vector3d.new(@x - other.x, @y - other.y, @z - other.z); end
    def *(k);     Vector3d.new(@x * k, @y * k, @z * k); end
    def /(k);     Vector3d.new(@x / k, @y / k, @z / k); end

    def length
      Math.sqrt(@x * @x + @y * @y + @z * @z)
    end

    def normalize!
      l = length
      return self if l < 1.0e-12
      @x /= l; @y /= l; @z /= l
      self
    end

    def normalize
      clone.normalize!
    end

    def clone
      Vector3d.new(@x, @y, @z)
    end
    alias_method :dup, :clone

    def cross(other)
      Vector3d.new(
        @y * other.z - @z * other.y,
        @z * other.x - @x * other.z,
        @x * other.y - @y * other.x
      )
    end

    def dot(other)
      @x * other.x + @y * other.y + @z * other.z
    end

    def parallel?(other)
      cross(other).length < 1.0e-9
    end

    def perpendicular?(other)
      dot(other).abs < 1.0e-9
    end

    def angle_between(other)
      d = length * other.length
      return 0.0 if d < 1.0e-12
      Math.acos([dot(other) / d, 1.0].min.max(-1.0))
    end

    def valid?
      length > 0.0
    end

    # SketchUp declares a stable-ish orthonormal pair plus self.
    def axes
      n = normalize
      ref = n.z.abs > 0.9 ? Vector3d.new(1, 0, 0) : Vector3d.new(0, 0, 1)
      u = n.cross(ref)
      u.normalize!
      v = n.cross(u)
      v.normalize!
      [u, v, n]
    end

    def to_s
      "(#{@x}, #{@y}, #{@z})"
    end
  end

  class Transformation
    attr_reader :origin, :basis, :kind

    def initialize(origin, u = nil, v = nil, z = nil, kind = :axes)
      @kind = kind
      if u.nil?
        @origin = Point3d.new(0, 0, 0)
        @basis = [Vector3d.new(1, 0, 0), Vector3d.new(0, 1, 0), Vector3d.new(0, 0, 1)]
      else
        @origin = origin
        @basis = [u.clone.normalize!, v.clone.normalize!, z.clone.normalize!]
      end
    end

    def self.axes(origin, u, v, z)
      new(origin, u, v, z, :axes)
    end

    def transform_point(pt)
      return inverse_transform(pt) if @kind == :inverse
      dx = pt.x - @origin.x
      dy = pt.y - @origin.y
      dz = pt.z - @origin.z
      Point3d.new(
        @origin.x + @basis[0].x * dx + @basis[1].x * dy + @basis[2].x * dz,
        @origin.y + @basis[0].y * dx + @basis[1].y * dy + @basis[2].y * dz,
        @origin.z + @basis[0].z * dx + @basis[1].z * dy + @basis[2].z * dz
      )
    end

    def inverse_transform(pt)
      dx = pt.x - @origin.x
      dy = pt.y - @origin.y
      dz = pt.z - @origin.z
      Point3d.new(
        dx * @basis[0].x + dy * @basis[0].y + dz * @basis[0].z,
        dx * @basis[1].x + dy * @basis[1].y + dz * @basis[1].z,
        dx * @basis[2].x + dy * @basis[2].y + dz * @basis[2].z
      )
    end

    def inverse
      Transformation.new(@origin, nil, nil, nil, :inverse).tap do |t|
        t.basis = @basis
      end
    end

    protected
    attr_writer :basis
  end

  class PolygonMesh
    attr_reader :points, :polygons

    def initialize
      @points = []
      @polygons = []
    end

    def add_point(pt)
      key = "#{pt.x.round(9)},#{pt.y.round(9)},#{pt.z.round(9)}"
      found = nil
      @points.each_with_index do |p, i|
        if "#{p.x.round(9)},#{p.y.round(9)},#{p.z.round(9)}" == key
          found = i
          break
        end
      end
      return found unless found.nil?
      @points << pt
      @points.size - 1
    end

    def add_polygon(*idx)
      @polygons << idx
      @polygons.size
    end

    def count_polygons
      @polygons.size
    end
  end
end

# ----------------------------------------------------------------------------
# SketchUp core classes
# ----------------------------------------------------------------------------
module Sketchup
  class EntityStub
    attr_accessor :material, :soft, :smooth
    attr_reader :deleted

    def initialize
      @deleted = false
      @material = nil
    end

    def valid?
      !@deleted
    end

    def erase!
      @deleted = true
    end
  end

  class Vertex < EntityStub
    attr_reader :position
    attr_accessor :edges

    def initialize(position, owner = nil)
      super()
      @position = position
      @edges = []
      @owner = owner
    end

    def faces
      @edges.map { |e| e.faces }.flatten.uniq
    end

    def position
      @position.clone
    end
  end

  class Edge < EntityStub
    attr_reader :start, :end
    attr_writer :faces
    attr_accessor :owner

    def initialize(v1, v2, owner = nil)
      super()
      @start = v1
      @end = v2
      @faces = []
      @owner = owner
    end

    def length
      @start.position.distance(@end.position)
    end

    def faces
      @faces.reject { |f| f.deleted }
    end

    def all_connected
      [@start, @end].flatten.compact
    end
  end

  class Loop
    attr_reader :vertices

    def initialize(face, vertices)
      @face = face
      @vertices = vertices
    end

    def edges
      @face.edges
    end
  end

  class Face < EntityStub
    attr_reader :vertices, :normal, :parent

    def initialize(points, parent)
      super()
      @parent = parent
      @vertices = []
      pts = points.map { |p| p.is_a?(Point3d) ? p : Point3d.new(*p) }
      pts.each { |p| @vertices << Vertex.new(p, parent) }
      # Newell normal (CCW loop points to +Z when flat on XY)
      nx = 0.0; ny = 0.0; nz = 0.0
      n = pts.size
      (0...n).each do |i|
        a = pts[i]
        b = pts[(i + 1) % n]
        nx += (a.y - b.y) * (a.z + b.z)
        ny += (a.z - b.z) * (a.x + b.x)
        nz += (a.x - b.x) * (a.y + b.y)
      end
      @normal = Vector3d.new(nx, ny, nz)
      begin
        @normal.normalize!
      rescue
        @normal = Vector3d.new(0, 0, 1)
      end
      @edges = []
      (0...n).each do |i|
        @edges << Edge.new(@vertices[i], @vertices[(i + 1) % n], parent)
      end
      @edges.each do |e|
        e.start.edges << e
        e.end.edges << e
      end
      @outer_loop = Loop.new(self, @vertices)
    end

    def edges
      @edges.reject(&:deleted)
    end

    def outer_loop
      @outer_loop
    end

    def faces
      [@edges.map { |e| e.faces }].flatten.uniq
    end

    # stubs used by legacy flows
    def pushpull(_d); end
    def wide?; false; end
    def area; 0.0; end
  end

  class Group < EntityStub
    attr_accessor :name

    def initialize(parent = nil)
      super()
      @entities = GroupEntities.new(self)
      @parent = parent
    end

    def entities
      @entities
    end

    def parent
      @parent
    end
  end

  class ComponentInstance < EntityStub
    def initialize
      super()
      @definition = ComponentDefinition.new
    end

    def definition
      @definition
    end
  end

  class ComponentDefinition < EntityStub
    attr_reader :entities

    def initialize
      @entities = Entities.new
    end
  end

  # Entities behave like a array container; subclasses can attach an owner.
  class Entities < ::Array
    # Faces store their parent as the Entities array itself, so code that does
    # face.parent.entities keeps working against the stub.
    def entities
      self
    end

    def add_group
      g = Group.new(self)
      self << g
      g
    end

    def add_face(points)
      f = Face.new(points, self)
      self << f
      f
    end

    def add_faces_from_mesh(mesh)
      made = 0
      mesh.polygons.each do |poly|
        pts = poly.map { |i| mesh.points[i] }.compact
        next if pts.size < 3
        add_face(pts)
        made += 1
      end
      made
    end

    def add_arc(center, normal_axis, normal, radius, start_angle, end_angle, segments = 12)
      sweep = end_angle - start_angle
      out = []
      u = normal_axis
      v = normal.cross(normal_axis)
      v.normalize!
      (0...segments).each do |i|
        a0 = start_angle + sweep * i.to_f / segments.to_f
        a1 = start_angle + sweep * (i + 1).to_f / segments.to_f
        p1 = center + u * (Math.cos(a0) * radius) + v * (Math.sin(a0) * radius)
        p2 = center + u * (Math.cos(a1) * radius) + v * (Math.sin(a1) * radius)
        e = Edge.new(Vertex.new(p1), Vertex.new(p2), self)
        self << e
        out << e
      end
      out
    end

    def erase_entities(list)
      doomed = list.respond_to?(:to_a) ? list : [list]
      delete_if { |e| doomed.include?(e) }
    end
  end

  class GroupEntities < Entities
    attr_reader :group

    def initialize(group)
      super()
      @group = group
    end
  end

  class Selection < ::Array
    def empty?
      size == 0
    end
  end

  class Color
    attr_reader :hex

    def initialize(hex)
      @hex = hex.to_s
    end

    def to_s
      @hex
    end
  end

  class Material < EntityStub
    attr_accessor :color, :name

    def initialize(name)
      @name = name
      @color = nil
    end
  end

  class Materials
    def initialize
      @by_name = {}
    end

    def [](name)
      @by_name[name.to_s]
    end

    def add(name)
      m = Material.new(name)
      @by_name[name.to_s] = m
      m
    end
  end

  class InputPoint
    def initialize
      @position = Point3d.new(0, 0, 0)
    end

    def pick(_view, _x, _y); self; end
    def position; @position; end
    def valid?; true; end
    def clear; end
    def draw(_view); end
  end

  class Extension
    attr_reader :name, :file
    attr_accessor :description, :version, :creator, :copyright

    def initialize(name, file)
      @name = name
      @file = file
    end
  end
end

# ----------------------------------------------------------------------------
# SketchUp + UI module functions
# ----------------------------------------------------------------------------
module UI
  class HtmlDialog
    STYLE_DIALOG = 2
    attr_reader :callbacks
    attr_reader :scripts

    def initialize(_opts = {})
      @callbacks = {}
      @scripts = []
      @shown = false
      @closed = false
      @on_closed = nil
    end

    def add_action_callback(name, &block)
      @callbacks[name.to_s] = block
      self
    end

    def execute_script(script)
      $plush_events[:scripts] << script
      @scripts << script
      self
    end

    def set_size(_w, _h); end
    def show; @shown = true; end
    def visible?; @shown && !@closed; end
    def bring_to_front; end
    def close
      @closed = true
      @on_closed.call if @on_closed
    end

    def set_on_closed(&block)
      @on_closed = block
    end
  end

  class Menu
    attr_reader :items

    def initialize(name)
      @name = name
      @items = []
    end

    def add_submenu(name)
      sub = Menu.new(name)
      @items << sub
      sub
    end

    def add_separator; end

    def add_item(label, &block)
      @items << [label, block]
    end
  end

  class Command
    attr_accessor :tooltip, :status_bar_text, :menu_text, :small_icon, :large_icon
    attr_reader :label

    def initialize(label, &block)
      @label = label
      @block = block
    end

    def invoke
      @block.call
    end
  end

  class Toolbar
    attr_reader :name, :commands

    def initialize(name)
      @name = name
      @commands = []
    end

    def add_item(cmd)
      @commands << cmd
      self
    end

    def restore; end
  end

  def self.menu(name)
    $plush_menu ||= Menu.new(name)
  end

  def self.start_timer(interval, repeat = false, &block)
    $plush_events[:timers] << { :interval => interval, :repeat => repeat, :block => block }
    Object.new
  end

  def self.messagebox(msg)
    $plush_events[:messageboxes] << msg
  end

  def self.openURL(url)
    $plush_events[:opened_urls] << url
    true
  end
end

module Sketchup
  class Model
    attr_reader :selection, :options, :materials
    attr_accessor :active_tool

    def initialize
      @selection = Selection.new
      @active_entities = Entities.new
      @options = { 'UnitsOptions' => { 'LengthUnit' => 3, 'LengthFormat' => 0 } }
      @materials = Materials.new
      @active_tool = nil
    end

    def active_entities
      @active_entities
    end

    def start_operation(name, _undoable = true)
      $plush_events[:ops] << [:start, name]
      true
    end

    def commit_operation
      $plush_events[:ops] << [:commit]
      true
    end

    def abort_operation
      $plush_events[:ops] << [:abort]
      true
    end

    def select_tool(tool)
      @active_tool = tool
    end

    def active_model
      self
    end
  end

  def self.active_model
    $plush_world.model
  end

  def self.version
    '24.0.384'
  end

  def self.temp_dir
    Dir.tmpdir
  end

  def self.read_default(section, key, default = nil)
    $plush_prefs["#{section}|#{key}"].nil? ? default : $plush_prefs["#{section}|#{key}"]
  end

  def self.write_default(section, key, value)
    $plush_prefs["#{section}|#{key}"] = value
    true
  end

  def self.register_extension(extension)
    $plush_events[:registrations] << extension
    require extension.file if $plush_events[:registrations].size == 1
    true
  end

  def self.extensions
    $plush_events[:registrations]
  end

  def self.file_loaded?(file)
    $plush_load_once.key?(file)
  end

  def self.file_loaded(file)
    $plush_load_once[file] = true
  end

  def self.status_text
    @status_text
  end

  def self.status_text=(text)
    @status_text = text
  end
end

# ----------------------------------------------------------------------------
# World + helpers
# ----------------------------------------------------------------------------
module PlushTests
  class World
    attr_accessor :model
    attr_writer :model_unit

    def initialize
      @model = Sketchup::Model.new
      @model_unit = 'cm'
    end

    def model_unit
      @model_unit || 'cm'
    end
  end

  def self.world
    $plush_world ||= World.new
  end

  def self.model_unit=(name)
    world.model_unit = name
    world.model.options['UnitsOptions']['LengthUnit'] = { 'mm' => 2, 'cm' => 3, 'm' => 4, 'in' => 0, 'ft' => 1 }[name]
  end

  # Rect face in inches placed at origin on XY, normal +Z
  def self.rect_face(w, h)
    pts = [
      Geom::Point3d.new(0, 0, 0),
      Geom::Point3d.new(w, 0, 0),
      Geom::Point3d.new(w, h, 0),
      Geom::Point3d.new(0, h, 0)
    ]
    world.model.active_entities.add_face(pts)
  end

  # Two separate square edge-start loops for the loft suite
  def self.square_loop_entities(z, size)
    ents = world.model.active_entities
    faces = []
    [[0, 0], [size * 2, size * 2]].each do |offset_x, offset_z_unused|
      # offset is applied on x only; z varies per loop
    end
    ents
  end

  def self.reset!
    $plush_events = {
      :scripts => [], :timers => [], :messageboxes => [],
      :opened_urls => [], :registrations => [], :ops => []
    }
    $plush_prefs = {}
    $plush_load_once = {}
    $plush_world = World.new
  end
end
