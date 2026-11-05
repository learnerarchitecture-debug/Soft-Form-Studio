# =============================================================================
# Plush - Soft Form Studio by ArchInsights
# core_geometry.rb - Pure, testable geometry math (no SketchUp entities here)
# =============================================================================
# frozen_string_literal: true

module Archinsights
  module Plush
    module CoreGeometry
      module_function

      TAU = Math::PI * 2.0

      # ------------------------------------------------------------------
      # Numeric helpers
      # ------------------------------------------------------------------
      def clamp_f(value, lo, hi)
        return lo if value < lo
        return hi if value > hi
        value
      end

      def lerp_f(a, b, t)
        a + (b - a) * t
      end

      # Small deterministic linear congruential generator.
      # Guarantees identical output across platforms/runs for a given seed,
      # which makes generated fabric repeatable and unit-testable.
      class Rng
        def initialize(seed)
          @state = (seed & 0x7fffffff)
          @state = 20_246_083 if @state == 0
        end

        # Returns a float in [0.0, 1.0)
        def next_f
          @state = (@state * 11_035_15245 + 12_345) & 0x7fffffff
          @state.to_f / 0x7fffffff.to_f
        end

        # Returns a float in [min, max)
        def range(min, max)
          min + next_f * (max - min)
        end

        # Returns an integer in [min, max]
        def int(min, max)
          min + (next_f * (max - min + 1)).floor
        end

        # Returns -1.0 or +1.0
        def sign
          next_f < 0.5 ? -1.0 : 1.0
        end
      end

      # ------------------------------------------------------------------
      # Cloth factors
      # ------------------------------------------------------------------
      # Normalised catenary sag: 0 at anchors (t=0, t=1), peak at mid-span.
      def catenary_sag(t)
        s = Math.sin(Math::PI * t)
        s * s
      end

      # Radial shrink factor for dome rings.
      # r(t) follows a quarter-ellipse that flattens onto a plateau near the
      # apex, which produces realistic fabric tops instead of a pinched point.
      #   t: 0.0 at the border -> 1.0 at the apex
      #   plateau: minimum radius fraction kept flat at the top (0.04 - 0.5)
      def ring_scale(t, plateau)
        t = clamp_f(t, 0.0, 1.0)
        base = Math.cos(t * Math::PI * 0.5)
        floor = clamp_f(plateau, 0.02, 0.98)
        # smooth transition between the ellipse curve and the flat plateau
        blend_width = [(1.0 - floor) * 0.8, 0.2].max
        k = clamp_f((base - floor) / blend_width, 0.0, 1.0)
        smooth = floor + (base - floor) * k * k
        smooth
      end

      # Vertical dome profile: returns the z fraction (0..1) reached at ring t.
      # A very slight S easing keeps the shoulder fuller, like real stuffing.
      def dome_height_profile(t)
        t = clamp_f(t, 0.0, 1.0)
        x = t * t * (3.0 - 2.0 * t) # smoothstep
        0.88 * Math.sin(x * Math::PI * 0.5) + 0.12 * t * t
      end

      # ------------------------------------------------------------------
      # Organi wrinkle field (deterministic)
      # ------------------------------------------------------------------
      # Envelope keeps wrinkles zero at the border and near the apex so seams
      # stay crisp and tops stay smooth.
      def wrinkle_envelope(t)
        s = Math.sin(Math::PI * clamp_f(t, 0.0, 1.0))
        s * s * s # strong fade at both ends
      end

      # Sum of seeded harmonics around the loop angle (theta in radians).
      # wrinkle: 0..1 user amount. folds: base fold count. Returns radius
      # modulation factor (≈1.0 centre, plus/minus amplitude).
      def wrinkle_radius(theta, t, wrinkle, folds, rng, amp_scale)
        env = wrinkle_envelope(t)
        return 0.0 if env <= 0.0 || wrinkle <= 0.0

        amp = wrinkle * amp_scale * env
        total = 0.0
        # 3 harmonics with seeded phases, decreasing amplitude
        (1..3).each do |h|
          count = (folds * (1 + h)).to_f
          phase = rng.range(0.0, TAU)
          speed = h == 1 ? 1.0 : (h == 2 ? 0.6 : 0.35)
          total += Math.sin(theta * count + phase) * speed
        end
        # micro cloth noise, always present but tiny
        total += rng.range(-0.08, 0.08)
        total * amp
      end

      # Corner "dog ear": outward gather bumps on the seam near corners.
      # corner_dirs: array of booleans/floats marking corner influence per
      # boundary point (1.0 at corner, 0.0 mid-span).
      def dog_ear_offset(corner_factor, tightness, size)
        corner_factor * corner_factor * tightness * size
      end

      # ------------------------------------------------------------------
      # Catmull-Rom spline on Geom::Point3d (uniform)
      # ------------------------------------------------------------------
      def catmull_rom(p0, p1, p2, p3, t)
        t2 = t * t
        t3 = t2 * t
        x = 0.5 * ((2.0 * p1.x) +
                   (-p0.x + p2.x) * t +
                   (2.0 * p0.x - 5.0 * p1.x + 4.0 * p2.x - p3.x) * t2 +
                   (-p0.x + 3.0 * p1.x - 3.0 * p2.x + p3.x) * t3)
        y = 0.5 * ((2.0 * p1.y) +
                   (-p0.y + p2.y) * t +
                   (2.0 * p0.y - 5.0 * p1.y + 4.0 * p2.y - p3.y) * t2 +
                   (-p0.y + 3.0 * p1.y - 3.0 * p2.y + p3.y) * t3)
        z = 0.5 * ((2.0 * p1.z) +
                   (-p0.z + p2.z) * t +
                   (2.0 * p0.z - 5.0 * p1.z + 4.0 * p2.z - p3.z) * t2 +
                   (-p0.z + 3.0 * p1.z - 3.0 * p2.z + p3.z) * t3)
        Geom::Point3d.new(x, y, z)
      end

      # Interpolate a stack of loops (array of arrays of Point3d, all equal
      # length) with Catmull-Rom along the stack axis. i in 0..loops.size-1,
      # f fractional. Requires loops.size >= 2.
      def catmull_stack_point(loops, col, i, f)
        n = loops.size
        if n == 2
          a = loops[0][col]
          b = loops[1][col]
          return Geom::Point3d.linear_combination(1.0 - f, a, f, b)
        end
        i0 = clamp_f(i - 1 + f, 0.0, n - 1.0)
        base = i0.floor
        base = n - 2 if base > n - 2
        base = 0 if base < 0
        frac = i0 - base
        p0 = loops[clamp_i(base - 1, 0, n - 1)][col]
        p1 = loops[clamp_i(base, 0, n - 1)][col]
        p2 = loops[clamp_i(base + 1, 0, n - 1)][col]
        p3 = loops[clamp_i(base + 2, 0, n - 1)][col]
        catmull_rom(p0, p1, p2, p3, frac)
      end

      def clamp_i(v, lo, hi)
        v = lo if v < lo
        v = hi if v > hi
        v
      end

      # ------------------------------------------------------------------
      # Loop utilities (arrays of Geom::Point3d)
      # ------------------------------------------------------------------
      # Resample a closed loop polyline into exactly target_count points,
      # evenly spaced by arc length.
      def resample_loop(pts, target_count)
        return pts.dup if pts.size == target_count
        return pts.dup if pts.size < 3 || target_count < 3

        n = pts.size
        edge_lengths = []
        total_len = 0.0
        (0...n).each do |i|
          l = pts[i].distance(pts[(i + 1) % n])
          edge_lengths << l
          total_len += l
        end
        return pts.dup if total_len < 1.0e-9

        result = []
        (0...target_count).each do |i|
          target_dist = (i.to_f / target_count.to_f) * total_len
          # walk edges to find the segment containing target_dist
          acc = 0.0
          seg = 0
          (0...n).each do |j|
            if target_dist <= acc + edge_lengths[j] + 1.0e-9
              seg = j
              break
            end
            acc += edge_lengths[j]
            seg = j
          end
          seg_len = edge_lengths[seg]
          t = seg_len < 1.0e-9 ? 0.0 : (target_dist - acc) / seg_len
          t = clamp_f(t, 0.0, 1.0)
          result << Geom::Point3d.linear_combination(1.0 - t, pts[seg], t, pts[(seg + 1) % n])
        end
        result
      end

      # Signed winding of a closed loop: +1 or -1.
      # Uses the doubled signed area of the projection onto the coordinate
      # plane that carries the most area. This flips exactly on reversal,
      # works for planar and near-planar loops, and never degenerates to
      # zero on axes-aligned test geometry.
      def loop_winding(pts)
        return 1 if pts.size < 3

        ax = 0.0; ay = 0.0; az = 0.0
        n = pts.size
        (0...n).each do |i|
          a = pts[i]
          b = pts[(i + 1) % n]
          ax += a.y * b.z - a.z * b.y # projected area onto the YZ plane
          ay += a.z * b.x - a.x * b.z # ... onto the ZX plane
          az += a.x * b.y - a.y * b.x # ... onto the XY plane
        end
        fx = ax.abs; fy = ay.abs; fz = az.abs
        if fz >= fx && fz >= fy
          az >= 0.0 ? 1 : -1
        elsif fx >= fy
          ax >= 0.0 ? 1 : -1
        else
          ay >= 0.0 ? 1 : -1
        end
      end

      # ------------------------------------------------------------------
      # Edge-chain helpers operating on plain point pairs so they are
      # testable without SketchUp Edge objects.
      # pairs: array of [start_point, end_point]
      # ------------------------------------------------------------------
      # Trace a single open or closed path through chained segments.
      def chain_path_from_pairs(pairs)
        return [] if pairs.nil? || pairs.empty?

        adjacency = Hash.new { |h, k| h[k] = [] }
        pairs.each do |a, b|
          next unless a && b
          adjacency[a] << b
          adjacency[b] << a
        end

        # start at an endpoint with a single link if any (open path),
        # otherwise any vertex (closed path)
        start_p = nil
        adjacency.each do |p, links|
          if links.size == 1
            start_p = p
            break
          end
        end
        start_p = adjacency.keys.first unless start_p

        path = []
        visited = Hash.new(false)
        cur = start_p
        prev = nil
        closed = false

        loop do
          path << cur
          next_p = nil
          adjacency[cur].each do |cand|
            next if visited[[cur, cand]] || visited[[cand, cur]]
            next if prev && cand.distance(prev) < 1.0e-9
            visited[[cur, cand]] = true
            visited[[cand, cur]] = true
            next_p = cand
            break
          end
          if next_p.nil?
            closed = path.size > 2 && path.first.distance(path.last) < 1.0e-7
            break
          end
          closed = next_p.distance(start_p) < 1.0e-7
          prev = cur
          cur = next_p
          break if closed
        end

        path << path.first if closed && path.first.distance(path.last) >= 1.0e-7
        { :points => path, :closed => closed }
      end

      # Detect closed loops from a bag of chained segments.
      # Returns an array of point arrays (each loop with >= 3 points).
      def extract_loops_from_pairs(pairs)
        loops = []
        remaining = pairs.select { |p| p[0] && p[1] }.dup
        until remaining.empty?
          trace = chain_path_from_pairs(remaining)
          break if trace[:points].size < 3
          pts = trace[:points]
          if trace[:closed]
            loop_pts = pts.dup
            loop_pts.pop if loop_pts.size > 3 && loop_pts.first.distance(loop_pts.last) < 1.0e-9
            loops << loop_pts if loop_pts.size >= 3
            remaining = remaining_after(remaining, pts, true)
          else
            remaining = remaining_after(remaining, pts, false)
          end
        end
        loops
      end

      def remaining_after(pairs, traced_pts, closed)
        used = {}
        (0...traced_pts.size - 1).each do |i|
          a = traced_pts[i]
          b = traced_pts[i + 1]
          used[[a, b]] = true
          used[[b, a]] = true
        end
        if closed && traced_pts.size >= 3
          a = traced_pts.last
          b = traced_pts.first
          used[[a, b]] = true
          used[[b, a]] = true
        end
        pairs.reject do |a, b|
          used[[a, b]] || used[[b, a]]
        end
      end

      # ------------------------------------------------------------------
      # Corner rounding math for a planar loop of vertices.
      # Returns array of corner data hashes (one per roundable corner).
      # vertices: ordered positions (Geom::Point3d), assumed coplanar.
      # ------------------------------------------------------------------
      def compute_corner_data(vertices, mode, manual_radius, auto_ratio = 0.4)
        n = vertices.length
        corners = []
        return corners if n < 3

        (0...n).each do |i|
          pt = vertices[i]
          pt_prev = vertices[(i - 1) % n]
          pt_next = vertices[(i + 1) % n]

          vec_prev = Geom::Vector3d.new(pt_prev.x - pt.x, pt_prev.y - pt.y, pt_prev.z - pt.z)
          vec_next = Geom::Vector3d.new(pt_next.x - pt.x, pt_next.y - pt.y, pt_next.z - pt.z)
          len_prev = vec_prev.length
          len_next = vec_next.length
          next if len_prev < 1.0e-9 || len_next < 1.0e-9

          vec_prev.normalize!
          vec_next.normalize!

          dot = vec_prev.dot(vec_next)
          theta = Math.acos(clamp_f(dot, -1.0, 1.0))
          next if theta < 0.05 || theta > 3.09

          min_edge = [len_prev, len_next].min
          d_max = min_edge * 0.45
          r_max = d_max * Math.tan(theta / 2.0)

          r = if mode == "auto"
                r_max * auto_ratio
              else
                clamp_f(manual_radius, 0.0, r_max)
              end
          next if r < 1.0e-4

          d = r / Math.tan(theta / 2.0)
          bisector = Geom::Vector3d.new((vec_prev.x + vec_next.x), (vec_prev.y + vec_next.y), (vec_prev.z + vec_next.z))
          blen = bisector.length
          next if blen < 1.0e-9
          bisector.normalize!

          center = pt.offset(bisector, r / Math.sin(theta / 2.0))
          t_prev = pt.offset(vec_prev, d)
          t_next = pt.offset(vec_next, d)
          r_prev = t_prev - center
          r_next = t_next - center
          arc_normal = r_prev.cross(r_next)
          next if arc_normal.length < 1.0e-12
          arc_normal.normalize!

          corners << {
            :index => i,
            :vertex => pt,
            :center => center,
            :t_prev => t_prev,
            :t_next => t_next,
            :r_prev => r_prev,
            :arc_normal => arc_normal,
            :radius => r,
            :angle => r_prev.angle_between(r_next),
            :r_max => r_max
          }
        end
        corners
      end

      # Adaptive segments for an arc based on radius and chord length.
      def arc_segments_for(radius, span)
        target = 3.0 # degrees of sweep per segment target
        segs = (span / (radius * 0.12)).ceil
        segs = 48 if segs > 48
        segs = 4 if segs < 4
        segs
      end

      # ------------------------------------------------------------------
      # Cove / crown cross-sections (2D: x = inward from wall, z = up)
      # Sample arrays of [x, z] floats, first point on the wall, last on the
      # ceiling plane (z reaches -depth semantics handled by caller).
      # ------------------------------------------------------------------
      # Concave quarter-circle fillet from wall to ceiling.
      def cove_profile(radius, segments)
        pts = []
        (0..segments).each do |i|
          t = i.to_f / segments.to_f
          a = t * Math::PI * 0.5
          pts << [radius - radius * Math.cos(a), -radius + radius * Math.sin(a)]
        end
        pts
      end

      # Convex quarter-cylinder (crown) around the corner line.
      def crown_profile(radius, segments)
        pts = []
        (0..segments).each do |i|
          t = i.to_f / segments.to_f
          a = t * Math::PI * 0.5
          pts << [radius - radius * Math.sin(a), -(radius - radius * Math.cos(a))]
        end
        # push ends to the tangent planes
        pts[0] = [0.0, -radius]
        pts[segments] = [radius, 0.0]
        pts
      end

      # ------------------------------------------------------------------
      # Annulus (patch with hole) construction between an outer boundary and
      # a centered hole polygon. Both in the same plane, star-shaped w.r.t.
      # the hole centre. Returns two rings of equal length: outer ring and
      # hole ring, sampled on the same ray angles.
      # outer: array of Point3d (closed loop order)
      # hole: array of Point3d (closed loop order)
      # ray_count: number of radial samples
      # ------------------------------------------------------------------
      def ray_polygon_hit(origin, dir_x, dir_y, ring)
        # ring points projected as 2D against origin + unit dir (x,y)
        best = nil
        n = ring.size
        (0...n).each do |i|
          a = ring[i]
          b = ring[(i + 1) % n]
          ex = b.x - a.x
          ey = b.y - a.y
          # solve origin + t*dir = a + s*(b-a)
          denom = dir_x * ey - dir_y * ex
          next if denom.abs < 1.0e-12
          ox = origin.x - a.x
          oy = origin.y - a.y
          s = (dir_x * oy - dir_y * ox) / denom
          t = (ex * oy - ey * ox) / denom
          next if t <= 1.0e-9
          next if s < -1.0e-9 || s > 1.0 + 1.0e-9
          if best.nil? || t < best
            best = t
          end
        end
        best
      end

      def build_star_annulus(outer, hole, ray_count)
        centre = Geom::Point3d.new(0.0, 0.0, 0.0)
        hole.each do |p|
          centre.x += p.x; centre.y += p.y; centre.z += p.z
        end
        centre.x /= hole.size; centre.y /= hole.size; centre.z /= hole.size

        outer_ring = []
        hole_ring = []
        (0...ray_count).each do |i|
          a = TAU * i.to_f / ray_count.to_f
          dx = Math.cos(a)
          dy = Math.sin(a)
          t_out = ray_polygon_hit(centre, dx, dy, outer)
          t_in = ray_polygon_hit(centre, dx, dy, hole)
          if t_out.nil? || t_in.nil?
            return nil
          end
          outer_ring << Geom::Point3d.new(
            centre.x + dx * t_out,
            centre.y + dy * t_out,
            centre.z
          )
          hole_ring << Geom::Point3d.new(
            centre.x + dx * t_in,
            centre.y + dy * t_in,
            centre.z
          )
        end
        { :outer => outer_ring, :hole => hole_ring, :centre => centre }
      end

      # ------------------------------------------------------------------
      # Quilt height field for mattress tops (u,v in 0..1)
      # pattern: nil | "grid" | "diamond" | "waves"
      # Returns z offset (<=0 grooves, >=0 pocket puffs combined smoothly)
      # ------------------------------------------------------------------
      def quilt_height(u01, v01, pattern, pocket_depth, seam_depth, cells)
        cells = clamp_f(cells.to_f, 2.0, 40.0)
        base = 0.0
        return base if pattern.nil? || pattern == "" || seam_depth <= 0.0

        # distance to nearest seam line for each pattern, normalised 0..1
        line_dist = 1.0
        pocket = pocket_depth
        if pattern == "grid"
          du = (u01 * cells) % 1.0
          dv = (v01 * cells) % 1.0
          line_dist = [du, 1.0 - du, dv, 1.0 - dv].min
          line_dist *= (1.0 / cells) # normalise roughly to cell space
        elsif pattern == "diamond"
          du = ((u01 + v01) * cells * 0.5) % 1.0
          dv = ((u01 - v01) * cells * 0.5) % 1.0
          line_dist = [du.abs, (1.0 - du).abs, dv.abs, (1.0 - dv).abs].min
          line_dist *= 1.0
        elsif pattern == "waves"
          line_dist = 1.0 - Math.sin(v01 * Math::PI * cells).abs
          line_dist *= 0.5
        else
          return base
        end

        groove = seam_depth * Math.exp(-(line_dist * line_dist) / (2.0 * (0.035 + 0.02)))
        puff = pocket * Math.exp(-((line_dist - 0.5) * (line_dist - 0.5)) / (2.0 * 0.25 * 0.25))
        base + puff - groove
      end

      # ------------------------------------------------------------------
      # Version comparison for the update feed: "1.2.3" tuples
      # ------------------------------------------------------------------
      def version_tuple(v)
        parts = v.to_s.strip.split(".")
        out = []
        parts.each do |p|
          out << (p.to_i)
        end
        out
      end

      def newer_version?(remote, current)
        return false if remote.to_s.empty?
        return true if current.to_s.empty?

        a = version_tuple(remote)
        b = version_tuple(current)
        n = [a.size, b.size].max
        (0...n).each do |i|
          av = a[i] || 0
          bv = b[i] || 0
          return true if av > bv
          return false if av < bv
        end
        false
      end
    end
  end
end
