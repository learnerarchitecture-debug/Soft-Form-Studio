# =============================================================================
# Plush - Soft Form Studio by ArchInsights
# fabric_engine.rb - Real-world softness: pillow, cushion, drape, mattress
# =============================================================================
# frozen_string_literal: true

require File.join(File.dirname(__FILE__), 'core_geometry.rb')

module Archinsights
  module Plush
    module FabricEngine
      module_function

      # Pure math lives in CoreGeometry; all calls are explicitly qualified
      # so the module stays safe when re-opened by plugins or test harnesses.

      # ------------------------------------------------------------------
      # Local planar frame
      # ------------------------------------------------------------------
      def frame_for(boundary_pts, normal)
        cx = 0.0; cy = 0.0; cz = 0.0
        boundary_pts.each do |pt|
          cx += pt.x; cy += pt.y; cz += pt.z
        end
        n = boundary_pts.size.to_f
        centroid = Geom::Point3d.new(cx / n, cy / n, cz / n)
        axes = normal.axes
        trans = Geom::Transformation.axes(centroid, axes[0], axes[1], axes[2])
        { :centre => centroid, :trans => trans, :inv => trans.inverse }
      end

      def to_local(fr, pt)
        pt.transform(fr[:inv])
      end

      def to_world(fr, pt)
        pt.transform(fr[:trans])
      end

      # ------------------------------------------------------------------
      # Boundary refinement: subdivided seam ring with catenary sag +
      # corner dog-ears. Works on local XY points (z kept as given).
      # Returns a hash with :pts (array of Point3d), :corner_factor array,
      # :theta array, :radius array, :size.
      # ------------------------------------------------------------------
      def refine_boundary(local_pts, opts = {})
        n = local_pts.size
        return { :pts => local_pts.compact, :corner_factor => [], :theta => [], :radius => [], :size => 1.0 } if n < 3

        centre = Geom::Point3d.new(0.0, 0.0, 0.0)
        local_pts.each do |p|
          centre.x += p.x; centre.y += p.y; centre.z += p.z
        end
        centre.x /= n; centre.y /= n; centre.z /= n

        max_r = 0.0
        local_pts.each do |p|
          d = Math.sqrt((p.x - centre.x) ** 2 + (p.y - centre.y) ** 2)
          max_r = d if d > max_r
        end
        size = max_r

        detail = opts[:detail] || 7
        seg_target = size / (6.0 + detail * 1.4)
        drape = opts.fetch(:drape, 0.45)
        pleats = opts.fetch(:pleats, 0.55)

        # corner sharpness per vertex
        corner_f = [0.0] * n
        (0...n).each do |i|
          a = local_pts[(i - 1) % n]
          b = local_pts[i]
          c = local_pts[(i + 1) % n]
          v1 = Geom::Vector3d.new(a.x - b.x, a.y - b.y, 0.0)
          v2 = Geom::Vector3d.new(c.x - b.x, c.y - b.y, 0.0)
          l1 = v1.length; l2 = v2.length
          if l1 > 1.0e-9 && l2 > 1.0e-9
            dot = CoreGeometry.clamp_f(v1.x * v2.x + v1.y * v2.y, -1.0, 1.0) / (l1 * l2)
            ang = Math.acos(dot)
            corner_f[i] = CoreGeometry.clamp_f((ang - 0.9) / 1.4, 0.0, 1.0) # sharper corner -> 1
          end
        end

        pts = []
        cf_out = []
        (0...n).each do |i|
          a = local_pts[i]
          b = local_pts[(i + 1) % n]
          span = Math.sqrt((b.x - a.x) ** 2 + (b.y - a.y) ** 2)
          k = (span / seg_target).round
          k = 2 if k < 2
          k = 26 if k > 26

          (0...k).each do |s|
            f = s.to_f / k.to_f
            x = CoreGeometry.lerp_f(a.x, b.x, f)
            y = CoreGeometry.lerp_f(a.y, b.y, f)

            # catenary: pull the seam inward mid-span
            sag = CoreGeometry.catenary_sag(f) * [span * 0.05 * drape, size * 0.022].min
            dx = centre.x - x
            dy = centre.y - y
            dl = Math.sqrt(dx * dx + dy * dy)
            if dl > 1.0e-9
              x += dx / dl * sag
              y += dy / dl * sag
            end

            pts << Geom::Point3d.new(x, y, a.z)
            cf = corner_f[i] * (1.0 - f)
            cf += corner_f[(i + 1) % n] * f if s == k - 1
            cf_out << cf
          end
        end

        # dog-ears: local outward gathers near corners over the seam ring
        if pleats > 0.0 && size > 0.0
          m = pts.size
          ear_r = size * 0.045 * pleats
          (0...m).each do |j|
            cf = cf_out[j]
            if cf > 0.02
              # both neighbours also participate for a smooth bump
              cj = [(cf_out[(j - 1) % m] || 0.0), cf, (cf_out[(j + 1) % m] || 0.0)].max
              amp = ear_r * cj * cj
              if amp > 1.0e-7
                dx = pts[j].x - centre.x
                dy = pts[j].y - centre.y
                dl = Math.sqrt(dx * dx + dy * dy)
                if dl > 1.0e-9
                  pts[j] = Geom::Point3d.new(pts[j].x + dx / dl * amp, pts[j].y + dy / dl * amp, pts[j].z)
                end
              end
            end
          end
        end

        # precompute polar data
        theta = []
        radius = []
        out_dir = []
        pts.each do |p|
          dx = p.x - centre.x
          dy = p.y - centre.y
          r = Math.sqrt(dx * dx + dy * dy)
          theta << Math.atan2(dy, dx)
          radius << r
          if r > 1.0e-9
            out_dir << Geom::Vector3d.new(dx / r, dy / r, 0.0)
          else
            out_dir << Geom::Vector3d.new(1.0, 0.0, 0.0)
          end
        end

        { :pts => pts, :corner_factor => cf_out, :theta => theta, :radius => radius,
          :out_dir => out_dir, :size => size, :centre => centre }
      end

      # ------------------------------------------------------------------
      # Piping (welt) crest ring: same sample layout, radius pushed outward
      # by width, lifted by height. dir +1 above, -1 below the seam plane.
      # ------------------------------------------------------------------
      def piping_ring(seam, opts)
        width = opts[:width] || 0.0
        height = opts[:height] || 0.0
        dir = opts.fetch(:dir, 1.0)
        pts = []
        seam[:out_dir].each_with_index do |od, j|
          r = seam[:radius][j] + width
          pts << Geom::Point3d.new(
            seam[:centre].x + od.x * r,
            seam[:centre].y + od.y * r,
            dir * height
          )
        end
        pts
      end

      # ------------------------------------------------------------------
      # Dome ring stack (pure): grows from the crest ring (z = z0, radius =
      # crest radius per sample) up/down to a small plateau + flat cap ring.
      # dir: +1 above seam, -1 below.
      # ------------------------------------------------------------------
      def dome_rings(seam, opts)
        dir = opts.fetch(:dir, 1.0) >= 0 ? 1.0 : -1.0
        height = opts[:height].to_f
        return [] if height <= 0.0
        steps = (opts[:steps] || 6).to_i
        steps = 3 if steps < 3
        steps = 10 if steps > 10
        plateau = CoreGeometry.clamp_f(opts.fetch(:plateau, 0.20), 0.06, 0.6)
        wrinkle = CoreGeometry.clamp_f(opts.fetch(:wrinkle, 0.5), 0.0, 1.0)
        folds = (opts[:folds] || 6).to_i
        rng = opts[:rng] || CoreGeometry::Rng.new(1)
        cf = seam[:corner_factor]
        size = seam[:size]
        crest = seam[:crest_radius_add] || 0.0
        z0 = opts.fetch(:z0, 0.0)
        drape = CoreGeometry.clamp_f(opts.fetch(:drape, 0.4), 0.0, 1.0)

        rings = []
        (1..steps).each do |i|
          t = i.to_f / steps.to_f
          z = z0 + dir * height * CoreGeometry.dome_height_profile(t)
          s = CoreGeometry.ring_scale(t, plateau)
          ear_fade = t < 0.35 ? (1.0 - t / 0.35) : 0.0
          pts = []
          seam[:radius].each_with_index do |r0, j|
            base_r = r0 + crest
            w = CoreGeometry.wrinkle_radius(seam[:theta][j], t, wrinkle, folds, rng, size * 0.016)
            rad = base_r * s * (1.0 + w)
            # corner gathers on the shoulder
            if cf[j] > 0.02 && ear_fade > 0.0
              rad += CoreGeometry.dog_ear_offset(cf[j], 0.5, ear_r_low(opts, size)) * ear_fade
            end
            pts << Geom::Point3d.new(
              seam[:centre].x + seam[:out_dir][j].x * rad,
              seam[:centre].y + seam[:out_dir][j].y * rad,
              z - dir * drape * size * 0.02 * CoreGeometry.dome_height_profile(t) * CoreGeometry.dome_height_profile(t)
            )
          end
          rings << pts
        end

        # plateau cap ring (flat top instead of pinched apex)
        apex_r = CoreGeometry.ring_scale(1.0, plateau)
        cap_pts = []
        seam[:radius].each_with_index do |r0, j|
          rad = (r0 + crest) * apex_r * (1.0 + CoreGeometry.wrinkle_radius(seam[:theta][j], 0.95, wrinkle * 0.35, folds, rng, size * 0.010))
          cap_pts << Geom::Point3d.new(
            seam[:centre].x + seam[:out_dir][j].x * rad,
            seam[:centre].y + seam[:out_dir][j].y * rad,
            dir * height + z0 - dir * drape * size * 0.02
          )
        end
        rings << cap_pts
        rings
      end

      def ear_r_low(opts, size)
        (opts[:ear_radius] || size * 0.035)
      end

      # ------------------------------------------------------------------
      # RING STACK ASSEMBLY - Pillow / Cushion
      # opts keys: height, rest(bool), drape, puff(0..1), wrinkle(0..1),
      # detail, seed, piping(bool), piping_scale(0..1 top_piping(bool))
      # ------------------------------------------------------------------
      def pillow_stack(boundary_world, normal, p)
        fr = frame_for(boundary_world, normal)
        local = boundary_world.map { |pt| to_local(fr, pt) }
        seam = refine_boundary(local, p)

        height = p[:height].to_f
        height = seam[:size] if height <= 0.0
        puff = CoreGeometry.clamp_f(p.fetch(:puff, 0.72), 0.2, 1.0)
        rng = CoreGeometry::Rng.new((p[:seed] || 1).to_i)
        rest = p[:rest] ? true : false
        piping = p.fetch(:piping, true)
        top_pipe = p.fetch(:top_piping, false)

        pw = seam[:size] * 0.030 * (piping ? 1.0 : 0.0)
        ph = [height * 0.10, seam[:size] * 0.045].min * (piping ? 1.0 : 0.0)
        steps = (p[:detail] || 7).to_i

        rings = []
        if rest
          # flat resting bottom = the seam ring itself at z 0
          rings << seam[:pts].map { |pt| Geom::Point3d.new(pt.x, pt.y, 0.0) }
          # side wall up to piping crest
          rings << piping_ring(seam, { :width => pw * 0.5, :height => ph * 0.5, :dir => 1 }) if piping
          crest = piping_ring(seam, { :width => pw, :height => ph, :dir => 1 })
          rings << crest
          dome = dome_rings(seam.merge(:crest_radius_add => pw), {
            :dir => 1, :height => height - ph,
            :z0 => ph, :steps => steps,
            :plateau => 0.14 + 0.16 * (1.0 - puff),
            :wrinkle => p.fetch(:wrinkle, 0.5),
            :folds => p[:folds] || 6, :rng => rng,
            :drape => p.fetch(:drape, 0.45),
            :ear_radius => seam[:size] * 0.035
          })
          rings.concat(dome)
        else
          bottom_h = height * 0.55
          top_h = height * 0.45
          # bottom dome (compressed by gravity): mirrored below the seam
          b_dome = dome_rings(seam, {
            :dir => -1, :height => bottom_h,
            :z0 => 0.0, :steps => steps,
            :plateau => 0.22 + 0.14 * (1.0 - puff),
            :wrinkle => p.fetch(:wrinkle, 0.5) * 0.8,
            :folds => (p[:folds] || 6) + 1, :rng => rng,
            :drape => p.fetch(:drape, 0.4) * 0.7,
            :ear_radius => seam[:size] * 0.03
          })
          # dome_rings returns ascending within given dir; rewalk bottom-up:
          b_asc = b_dome.reverse
          b_asc.each do |pts|
            rings << pts.map { |pt| Geom::Point3d.new(pt.x, pt.y, pt.z) }
          end
          rings << seam[:pts].map { |pt| Geom::Point3d.new(pt.x, pt.y, 0.0) }
          rings << piping_ring(seam, { :width => pw * 0.5, :height => ph * 0.5, :dir => 1 }) if piping
          rings << piping_ring(seam, { :width => pw, :height => ph, :dir => 1 }) if piping
          dome = dome_rings(seam.merge(:crest_radius_add => pw), {
            :dir => 1, :height => top_h - ph,
            :z0 => ph, :steps => steps,
            :plateau => 0.14 + 0.16 * (1.0 - puff),
            :wrinkle => p.fetch(:wrinkle, 0.5),
            :folds => p[:folds] || 6, :rng => rng,
            :drape => p.fetch(:drape, 0.45),
            :ear_radius => seam[:size] * 0.035
          })
          rings.concat(dome)
        end

        # cushion-style top piping (decorative welt right under the cap)
        if top_pipe && rings.size >= 2
          last = rings[-1]
          prev = rings[-2]
          if last.size == prev.size
            bump = []
            last.each_with_index do |pt, j|
              dx = pt.x - seam[:centre].x
              dy = pt.y - seam[:centre].y
              r = seam[:radius][j] * (CoreGeometry.ring_scale(1.0, 0.2)) + pw * 0.7
              z = prev[j].z + (pt.z - prev[j].z).abs * 0.5
              bump << Geom::Point3d.new(
                seam[:centre].x + seam[:out_dir][j].x * r,
                seam[:centre].y + seam[:out_dir][j].y * r,
                z
              )
            end
            rings.insert(-2, bump)
          end
        end

        # convert local ring pts to world coordinates
        world = rings.map do |loop_pts|
          loop_pts.map { |pt| to_world(fr, pt) }
        end
        { :rings => world, :caps => [0, world.size - 1], :seam_index => rest ? 0 : index_of_seam(rings) }
      end

      def index_of_seam(rings)
        rings.each_with_index do |loop_pts, i|
          z = loop_pts[0].z
          return i if loop_pts.all? { |p| (p.z - z).abs < 1.0e-9 }
        end
        nil
      end

      # ------------------------------------------------------------------
      # SU glue: build faces from an ordered ring stack (bottom -> top).
      # Optional caps: flat polygon faces on given ring indices.
      # Returns the geometry counts for tests/logging.
      # ------------------------------------------------------------------
      def build_ring_mesh(entities, rings, opts = {})
        return { :faces => 0 } if rings.size < 2
        open_band = opts[:open] ? true : false
        mesh = Geom::PolygonMesh.new
        idx = []
        rings.each do |loop_pts|
          row = []
          loop_pts.each do |pt|
            row << mesh.add_point(pt)
          end
          idx << row
        end
        m = rings[0].size
        (0...rings.size - 1).each do |i|
          (0...m).each do |j|
            jn = open_band ? j + 1 : (j + 1) % m
            next if jn >= m
            a = idx[i][j]
            b = idx[i][jn]
            c = idx[i + 1][jn]
            d = idx[i + 1][j]
            if a != b && b != c && c != a
              mesh.add_polygon(a, b, c) rescue nil
            end
            if a != c && c != d && d != a
              mesh.add_polygon(a, c, d) rescue nil
            end
          end
        end

        existing = entities.grep(Sketchup::Edge).to_a
        entities.add_faces_from_mesh(mesh)
        new_edges = entities.grep(Sketchup::Edge).to_a - existing
        new_edges.each do |e|
          e.soft = true
          e.smooth = true
        end

        faces_made = 0
        caps = opts[:caps] || []
        caps.each do |ring_index|
          loop_pts = rings[ring_index]
          next if loop_pts.nil? || loop_pts.size < 3
          begin
            f = entities.add_face(loop_pts)
            if f
              faces_made += 1
              f.edges.each do |e|
                e.soft = true
                e.smooth = true
              end
            end
          rescue => e
            $stderr.puts "Plush: cap face failed: #{e.message}"
          end
        end

        { :faces => faces_made + mesh_polygon_count(mesh), :edges => new_edges.size }
      end

      def mesh_polygon_count(mesh)
        # Geom::PolygonMesh#count_polygons available in modern SketchUp
        begin
          mesh.count_polygons
        rescue
          0
        end
      end

      # ------------------------------------------------------------------
      # Drape: hanging cloth skirt over the selected face boundary.
      # The face itself stays; we build the falling skirt band outside it.
      # ------------------------------------------------------------------
      def drape_rings(boundary_world, normal, p)
        fr = frame_for(boundary_world, normal)
        local = boundary_world.map { |pt| to_local(fr, pt) }
        seam = refine_boundary(local, { :detail => p[:detail] || 7 })
        drop = p[:drop].to_f
        drop = seam[:size] * 0.5 if drop <= 0.0
        steps = (p[:detail] || 6).to_i + 1
        steps = 4 if steps < 4
        steps = 12 if steps > 12
        wrinkle = CoreGeometry.clamp_f(p.fetch(:wrinkle, 0.45), 0.0, 1.0)
        flare = CoreGeometry.clamp_f(p.fetch(:flare, 0.5), 0.0, 1.0)
        rng = CoreGeometry::Rng.new((p[:seed] || 3).to_i)
        cf = seam[:corner_factor]

        rings = []
        rings << seam[:pts].map { |pt| Geom::Point3d.new(pt.x, pt.y, pt.z) }
        (1..steps).each do |i|
          t = i.to_f / steps.to_f
          fall = t * t * 0.25 + t * 0.75 # cloth accelerating fall
          z = -drop * fall
          flare_env = Math.sin(Math::PI * t) ** 1.5
          pts = []
          seam[:radius].each_with_index do |r0, j|
            w = CoreGeometry.wrinkle_radius(seam[:theta][j], CoreGeometry.clamp_f(t * 1.4, 0.0, 1.0), wrinkle * 0.6, 5, rng, seam[:size] * 0.012)
            rad = r0 * (1.0 + flare_env * 0.10 * flare) * (1.0 + w)
            x = seam[:centre].x + seam[:out_dir][j].x * rad
            y = seam[:centre].y + seam[:out_dir][j].y * rad
            zz = z - drop * 0.05 * cf[j] # corners hang lower
            zz += rng.range(-1.0, 1.0) * drop * 0.008 if t >= 0.99 # hem wobble
            pts << Geom::Point3d.new(x, y, zz)
          end
          rings << pts
        end
        world = rings.map { |loop_pts| loop_pts.map { |pt| to_world(fr, pt) } }
        { :rings => world, :open => true }
      end

      # ------------------------------------------------------------------
      # Tuft button: small crater dented into a horizontal surface.
      # ------------------------------------------------------------------
      def crater_rings(center, normal, radius, depth, steps = 4)
        centre_l = Geom::Point3d.new(0.0, 0.0, 0.0)
        axes = axes_for_horizontal(normal)
        rings_data = []
        profile = [[1.55, 0.0], [1.0, 0.30], [0.55, 0.78], [0.22, 1.0]]
        (0...profile.size).each do |i|
          rs = profile[i][0]
          zs = profile[i][1]
          pts = []
          seg = 10
          (0...seg).each do |k|
            a = CoreGeometry::TAU * k.to_f / seg
            # local: x along axes[0], y along axes[1], z along normal
            pts << center.offset(axes[0], Math.cos(a) * radius * rs)
                    .offset(axes[1], Math.sin(a) * radius * rs)
                    .offset(normal, -depth * zs)
          end
          rings_data << pts
        end
        rings_data
      end

      def axes_for_horizontal(normal)
        n = normal.clone
        n.normalize!
        ref = Geom::Vector3d.new(0, 0, 1)
        if n.parallel?(ref)
          ref = Geom::Vector3d.new(1, 0, 0)
        end
        u = n.cross(ref)
        u.length < 1.0e-9 ? u = Geom::Vector3d.new(1, 0, 0) : u.normalize!
        v = n.cross(u)
        v.normalize!
        [u, v, n]
      end

      # ------------------------------------------------------------------
      # Mattress
      # p: {height, bulge, piping, pattern(nil/grid/diamond/waves),
      #     pocket, groove, cells, tuft(bool), detail, seed}
      # Rectangles ONLY for quilt patterns; otherwise falls back to a
      # soft micro-dome top (handled by caller via :top => "dome").
      # ------------------------------------------------------------------
      def mattress_side_rings(boundary_world, normal, p)
        fr = frame_for(boundary_world, normal)
        local = boundary_world.map { |pt| to_local(fr, pt) }
        seam = refine_boundary(local, { :detail => 4, :drape => 0.0, :pleats => 0.0 })
        height = p[:height].to_f
        height = seam[:size] if height <= 0.0
        bulge = CoreGeometry.clamp_f(p.fetch(:bulge, 0.5), 0.0, 1.0)
        bev = [height * 0.10, seam[:size] * 0.055].min
        pw = seam[:size] * 0.022 * (p.fetch(:piping, true) ? 1.0 : 0.0)
        ph = [height * 0.05, seam[:size] * 0.02].min
        bamt = bulge * 0.030

        rings = []
        rings << seam[:pts].map { |pt| Geom::Point3d.new(pt.x, pt.y, 0.0) }
        rings << seam[:pts].map { |pt| Geom::Point3d.new(pt.x, pt.y, bev) }
        rings << ring_scaled(seam, 1.0 + bamt, height * 0.5)
        rings << seam[:pts].map { |pt| Geom::Point3d.new(pt.x, pt.y, height - bev) }
        if pw > 0.0
          rings << ring_scaled(seam, 1.0 + pw / seam[:size].to_f, height - ph)
        end
        rings << seam[:pts].map { |pt| Geom::Point3d.new(pt.x, pt.y, height) }
        world = rings.map { |loop_pts| loop_pts.map { |pt| to_world(fr, pt) } }
        { :rings => world, :seam => seam, :fr => fr, :height => height }
      end

      def ring_scaled(seam, scale, z)
        pts = []
        seam[:radius].each_with_index do |r0, j|
          rad = r0 * scale
          pts << Geom::Point3d.new(
            seam[:centre].x + seam[:out_dir][j].x * rad,
            seam[:centre].y + seam[:out_dir][j].y * rad,
            z
          )
        end
        pts
      end

      # Rectangular bilinear quilt cap matched to the top ring's per-edge
      # sampling. top_ring must be the 4-corner path subdivided per edge.
      # Returns grid rows (v index) of points.
      def quilt_grid(boundary_world, normal, top_ring, p)
        # detect corner anchors: the four sharp corners of the rectangle
        corners = rectangle_corners(boundary_world, normal)
        return nil if corners.nil?

        p00, p10, p11, p01 = corners
        cols = (p[:cells] || 10).to_i
        rows = (p[:cells] || 10).to_i
        cols = 14 if cols > 14
        rows = 14 if rows > 14

        pattern = p[:pattern]
        pocket = p.fetch(:pocket, 0.9.cm)
        groove = p.fetch(:groove, 0.5.cm)

        grid = []
        (0..rows).each do |vj|
          row = []
          (0..cols).each do |ui|
            u = ui.to_f / cols
            v = vj.to_f / rows
            pt = bilinear(p00, p10, p11, p01, u, v)
            edge_f = edge_falloff(u, v)
            zz = quilt_height(u, v, pattern, pocket * edge_f, groove * edge_f, [(cols + rows) / 2.0, 3.0].max)
            pt = pt.offset(normal, zz)
            row << pt
          end
          grid << row
        end
        { :grid => grid, :cols => cols, :rows => rows, :normal => normal }
      end

      def bilinear(p00, p10, p11, p01, u, v)
        x = (p00.x * (1 - u) * (1 - v)) + (p10.x * u * (1 - v)) + (p11.x * u * v) + (p01.x * (1 - u) * v)
        y = (p00.y * (1 - u) * (1 - v)) + (p10.y * u * (1 - v)) + (p11.y * u * v) + (p01.y * (1 - u) * v)
        z = (p00.z * (1 - u) * (1 - v)) + (p10.z * u * (1 - v)) + (p11.z * u * v) + (p01.z * (1 - u) * v)
        Geom::Point3d.new(x, y, z)
      end

      def edge_falloff(u, v)
        d = [u, v, 1.0 - u, 1.0 - v].min * 4.0
        CoreGeometry.clamp_f(d, 0.0, 1.0)
      end

      # Detect an axis-aligned (or near) rectangle loop and order its
      # corners p00 (origin), p10 (u end), p11 (far), p01 (v end).
      def rectangle_corners(boundary_world, normal)
        pts = boundary_world.first.is_a?(Geom::Point3d) ? boundary_world : boundary_world
        return nil if pts.size < 3 || pts.size > 6

        centre = Geom::Point3d.new(0.0, 0.0, 0.0)
        pts.each do |pt|
          centre.x += pt.x; centre.y += pt.y; centre.z += pt.z
        end
        centre.x /= pts.size; centre.y /= pts.size; centre.z /= pts.size

        axes = normal.clone
        axes.normalize!
        ref = Geom::Vector3d.new(0, 0, 1)
        if axes.parallel?(ref)
          ref = Geom::Vector3d.new(1, 0, 0)
        end
        u = axes.cross(ref)
        u.normalize! rescue u = Geom::Vector3d.new(1, 0, 0)
        v = axes.cross(u)
        v.normalize! rescue v = Geom::Vector3d.new(0, 1, 0)

        us = []
        vs = []
        pts.each do |pt|
          d = pt - centre
          us << d.dot(u)
          vs << d.dot(v)
        end
        umin = us.min; umax = us.max
        vmin = vs.min; vmax = vs.max
        # verify all points sit in the corners within tolerance
        tol = (umax - umin) * 0.08
        ok = true
        pts.each_with_index do |_, i|
          near_u0 = (us[i] - umin).abs < tol || (us[i] - umax).abs < tol
          near_v0 = (vs[i] - vmin).abs < tol || (vs[i] - vmax).abs < tol
          ok = false unless near_u0 && near_v0
        end
        return nil unless ok

        d00 = (u * umin) + (v * vmin)
        p00 = centre + d00
        p10 = centre + (u * umax) + (v * vmin)
        p11 = centre + (u * umax) + (v * vmax)
        p01 = centre + (u * umin) + (v * vmax)
        [p00, p10, p11, p01]
      end

      # Build the quilt cap from a grid: quads between consecutive rows.
      def build_quilt_cap(entities, quilt, top_ring, normal)
        grid = quilt[:grid]
        cols = quilt[:cols]
        rows = quilt[:rows]
        ring = top_ring
        # side stack rings share per-edge samples; the grid boundary row
        # corresponds to ring corners - we close with simple triangles:
        mesh = Geom::PolygonMesh.new
        gidx = []
        grid.each do |row|
          ridx = row.map { |pt| mesh.add_point(pt) }
          gidx << ridx
        end
        (0...rows).each do |j|
          (0...cols).each do |i|
            a = gidx[j][i]
            b = gidx[j][i + 1]
            c = gidx[j + 1][i + 1]
            d = gidx[j + 1][i]
            if a != b && b != c && c != a
              mesh.add_polygon(a, b, c) rescue nil
            end
            if a != c && c != d && d != a
              mesh.add_polygon(a, c, d) rescue nil
            end
          end
        end
        existing = entities.grep(Sketchup::Edge).to_a
        begin
          entities.add_faces_from_mesh(mesh)
        rescue => e
          $stderr.puts "Plush: quilt cap failed: #{e.message}"
        end
        new_edges = entities.grep(Sketchup::Edge).to_a - existing
        new_edges.each do |e|
          e.soft = true
          e.smooth = true
        end
        new_edges.size
      end
    end
  end
end

