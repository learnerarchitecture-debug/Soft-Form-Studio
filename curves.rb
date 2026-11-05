# =============================================================================
# Plush - Soft Form Studio by ArchInsights
# curves.rb - Soften Corners, Curved Wall, Ceiling Curve, Curved Push/Pull,
#             Openings, Loft, Pipe and bulk edge utilities.
# =============================================================================
# frozen_string_literal: true

require File.join(File.dirname(__FILE__), 'core_geometry.rb')
require File.join(File.dirname(__FILE__), 'fabric_engine.rb')

module Archinsights
  module Plush
    module Curves
      module_function

      # ==================================================================
      # SOFTEN CORNERS (round planar face corners, extrusion aware)
      # ==================================================================
      # faces: array of Sketchup::Face; mode: "auto"|"manual"; radius: Length
      def apply_soft_edges(model, faces, mode, radius)
        model.start_operation('Plush Soften Corners', true)
        begin
          faces.each do |face|
            next unless face.valid?
            round_face_corners(face, mode, radius)
          end
        rescue => e
          model.abort_operation rescue nil
          return { :ok => false, :message => "Soften Corners error: #{e.message}" }
        end
        model.commit_operation
        { :ok => true, :message => 'Corners softened.' }
      end

      def round_face_corners(face, mode, manual_radius)
        entities = face.parent.entities
        normal = face.normal.clone
        outer_loop = face.outer_loop
        vertices = outer_loop.vertices
        n = vertices.length
        return if n < 3

        positions = vertices.map { |v| v.position }
        corners = CoreGeometry.compute_corner_data(positions, mode, manual_radius.to_f)
        return if corners.empty?

        existing_edges = entities.grep(Sketchup::Edge).to_a
        existing_faces = entities.grep(Sketchup::Face).to_a

        depth = find_extrusion_depth(face)

        all_arc_edges = []
        corners.each do |c|
          segs = CoreGeometry.arc_segments_for(c[:radius], c[:angle] * c[:radius])
          arc_edges = entities.add_arc(
            c[:center],
            c[:r_prev].normalize,
            c[:arc_normal],
            c[:radius],
            0.0,
            c[:angle],
            segs
          )
          all_arc_edges.concat(arc_edges) if arc_edges
        end

        corner_faces = []
        corners.each do |c|
          v = vertices[c[:index]]
          next unless v && v.valid?
          v.faces.each do |f|
            next unless f.valid? && f != face
            corner_faces << f if f.normal.dot(normal) > 0.99
          end
        end
        corner_faces.uniq!

        if depth
          corner_faces.each do |cf|
            next unless cf.valid?
            cf.pushpull(-depth)
          end
          soften_edges(all_arc_edges)
          arc_vertices = []
          all_arc_edges.each do |edge|
            next unless edge.valid?
            arc_vertices << edge.start
            arc_vertices << edge.end
          end
          arc_vertices.uniq!
          arc_vertices.each do |av|
            av.edges.each do |edge|
              next unless edge.valid?
              vec = normal.clone
              if (edge.end.position - edge.start.position).normalize.parallel?(vec)
                edge.soft = true
                edge.smooth = true
              end
            end
          end
        else
          entities.erase_entities(corner_faces) unless corner_faces.empty?
          to_delete = corners.map { |c| vertices[c[:index]] }.select { |v| v && v.valid? }
          entities.erase_entities(to_delete) unless to_delete.empty?
        end

        new_edges = entities.grep(Sketchup::Edge).to_a - existing_edges
        cleanup_coplanar_edges(new_edges) unless new_edges.empty?
      end

      # ==================================================================
      # CURVED WALL - sweep an organic curve along an edge path or a face
      # params: { height, amplitude, style, waves, detail, seed, wrinkle }
      # ==================================================================
      def curved_wall(entities, path_pts, closed, p)
        return { :ok => false, :message => 'Path too short.' } if path_pts.size < 2
        return { :ok => false, :message => 'Closed path needs 3+ points.' } if closed && path_pts.size < 3

        height = p[:height].to_f
        height = 80.0 if height <= 0.0
        amp = p[:amplitude].to_f
        style = p.fetch(:style, 'bulge')
        waves = (p[:waves] || 2).to_i
        waves = 8 if waves > 8
        waves = 1 if waves < 1
        rng = CoreGeometry::Rng.new((p[:seed] || 7).to_i)
        wrinkle = CoreGeometry.clamp_f(p.fetch(:wrinkle, 0.3), 0.0, 1.0)

        cx = 0.0; cy = 0.0; cz = 0.0
        path_pts.each do |pt|
          cx += pt.x; cy += pt.y; cz += pt.z
        end
        centre = Geom::Point3d.new(cx / path_pts.size, cy / path_pts.size, cz / path_pts.size)

        pts = subdivide_path(path_pts, closed, (p[:detail] || 6).to_i)
        segs = pts.size

        # arc length along the span chain (for the wave profile u)
        span_count = segs - 1
        lens = []
        total = 0.0
        (0...span_count).each do |i|
          l = pts[i].distance(pts[i + 1])
          lens << l
          total += l
        end
        return { :ok => false } if total < 1.0e-6

        cum = [0.0]
        (0...span_count).each do |i|
          cum << cum.last + lens[i]
        end

        height_steps = 4
        base_rings = []
        (0..height_steps).each do |h|
          zt = h.to_f / height_steps.to_f
          ring = []
          (0...segs).each do |i|
            pt = pts[i]
            u = CoreGeometry.clamp_f(cum[i] / total, 0.0, 1.0)
            d = lateral_profile(u, style, waves)
            out_x = centre.x - pt.x
            out_y = centre.y - pt.y
            ol = Math.sqrt(out_x * out_x + out_y * out_y)
            ol = 1.0 if ol < 1.0e-9
            j = rng.range(-1.0, 1.0) * wrinkle * height * 0.018 * zt
            dx = out_x / ol
            dy = out_y / ol
            lateral = amp * d * zt
            ring << Geom::Point3d.new(
              pt.x + dx * lateral + dx * j,
              pt.y + dy * lateral + dy * j,
              pt.z + height * zt
            )
          end
          base_rings << ring
        end

        { :rings => base_rings, :open => !closed }
      end

      def lateral_profile(u, style, waves)
        u = CoreGeometry.clamp_f(u, 0.0, 1.0)
        case style
        when 's'
          Math.sin(Math::PI * 2.0 * u) * 0.5
        when 'wave'
          Math.sin(Math::PI * 2.0 * waves * u)
        else # bulge
          Math.sin(Math::PI * u)
        end
      end

      def subdivide_path(path_pts, closed, detail)
        seg_target = 24.0 / (1.0 + [detail, 1].max.to_f) # inches-ish target
        out = []
        n = path_pts.size
        last = closed ? n : n - 1
        (0...last).each do |i|
          a = path_pts[i]
          b = path_pts[(i + 1) % n]
          span = a.distance(b)
          k = (span / [seg_target, 1.0].max).round
          k = 1 if k < 1
          k = 40 if k > 40
          (0...k).each do |s|
            f = s.to_f / k.to_f
            out << Geom::Point3d.linear_combination(1.0 - f, a, f, b)
          end
        end
        out << path_pts[0] if closed
        out << path_pts.last unless closed
        out
      end

      # ==================================================================
      # CEILING CURVE - cove / crown / scallop fillets along wall edges
      # params: { radius, style(cove|crown|scallop), segments, detail }
      # ==================================================================
      def ceiling_curve(entities, faces, p)
        radius = p[:radius].to_f
        radius = 10.0 if radius <= 0.0
        style = p.fetch(:style, 'cove')
        built = 0
        faces.each do |face|
          next unless face.valid?
          n_c = face.normal.clone
          n_c.normalize!
          face.outer_loop.edges.each do |edge|
            next unless edge.valid?
            neighbour = edge.faces.find do |f|
              next false unless f.valid? && f != face
              dot = f.normal.normalize.dot(n_c)
              dot.abs < 0.35
            end
            next unless neighbour
            built += build_fillet_band(entities, edge, face, neighbour, radius, style, p)
          end
        end
        built
      end

      def build_fillet_band(entities, edge, ceiling_face, wall_face, radius, style, p)
        n_c = ceiling_face.normal.clone
        n_c.normalize!
        n_w = wall_face.normal.clone
        n_w.normalize!

        ip = edge.start.position
        dir = edge.end.position - edge.start.position
        len = dir.length
        return 0 if len < 1.0e-6
        dirx = dir.x / len
        diry = dir.y / len
        dirz = dir.z / len

        edge_pts = subdivide_path([ip, edge.end.position], false, 4)
        arc_segs = (p[:segments] || 8).to_i
        arc_segs = 4 if arc_segs < 4
        arc_segs = 24 if arc_segs > 24

        steps = edge_pts.size
        rings = []
        (0...arc_segs + 1).each do |k|
          a = (k.to_f / arc_segs.to_f) * (Math::PI / 2.0)
          ring = []
          (0...steps).each do |s|
            base = edge_pts[s]
            rr = radius
            if style == 'scallop'
              rr = radius * (1.0 + 0.28 * Math.sin(edge_pts[s].distance(ip) / [radius * 2.0, 1.0].max * Math::PI * 2.0))
            end
            pt = nil
            if style == 'crown'
              v = n_c * Math.cos(a) + n_w * Math.sin(a)
              pt = base + v * rr
            else
              centre = base + n_c * rr + n_w * rr
              v = n_c * (-Math.cos(a)) + n_w * (-Math.sin(a))
              pt = centre + v * rr
            end
            ring << pt
          end
          rings << ring
        end
        result = FabricEngine.build_ring_mesh(entities, rings, { :caps => [] })
        result[:faces] ? 1 : 0
      rescue => e
        $stderr.puts "Plush: fillet band failed: #{e.message}"
        0
      end

      # ==================================================================
      # CURVED PUSH/PULL
      # ==================================================================
      def pushpull_curved(model, faces, distance, unified)
        model.start_operation('Plush Curved Push/Pull', true)
        begin
          if unified
            avg = Geom::Vector3d.new(0, 0, 0)
            faces.each { |f| avg += f.normal }
            avg_len = avg.length
            avg = Geom::Vector3d.new(0, 0, 1) if avg_len < 1.0e-9
            avg.normalize!
            faces.each { |f| extrude_face_along_vector(f, avg, distance) }
          else
            faces.each { |f| extrude_face_along_vector(f, f.normal, distance) }
          end
        rescue => e
          model.abort_operation rescue nil
          return { :ok => false, :message => "Push/Pull error: #{e.message}" }
        end
        model.commit_operation
        { :ok => true }
      end

      def extrude_face_along_vector(face, normal, distance)
        entities = face.parent.entities
        outer_pts = face.outer_loop.vertices.map { |v| v.position.clone }
        n = outer_pts.length
        return if n < 3

        offset_pts = outer_pts.map { |pt| pt.offset(normal, distance) }
        grp = entities.add_group
        ge = grp.entities

        mesh = Geom::PolygonMesh.new
        bottom = outer_pts.map { |pt| mesh.add_point(pt) }
        top = offset_pts.map { |pt| mesh.add_point(pt) }
        begin
          mesh.add_polygon(bottom)
          mesh.add_polygon(top.reverse)
        rescue => e
          $stderr.puts "Plush: cap polygon failed: #{e.message}"
        end
        (0...n).each do |i|
          j = (i + 1) % n
          begin
            if bottom[i] != bottom[j] && bottom[j] != top[j] && top[j] != bottom[i]
              mesh.add_polygon(bottom[i], bottom[j], top[j])
            end
            if bottom[i] != top[j] && top[j] != top[i] && top[i] != bottom[i]
              mesh.add_polygon(bottom[i], top[j], top[i])
            end
          rescue => e
            $stderr.puts "Plush: side polygon failed: #{e.message}"
          end
        end
        existing = ge.grep(Sketchup::Edge).to_a
        ge.add_faces_from_mesh(mesh)
        new_edges = ge.grep(Sketchup::Edge).to_a - existing
        soften_edges(new_edges)
      end

      # ==================================================================
      # OPENINGS - punch a rectangular or circular opening through a face
      # params: { shape(rect|circle), width, height, offset_u, offset_v,
      #           depth(0=auto), rounded }
      # ==================================================================
      def opening(face, p)
        entities = face.parent.entities
        normal = face.normal.clone
        normal.normalize!
        outer_loop = face.outer_loop.vertices.map { |v| v.position.clone }
        n = outer_loop.length
        return { :ok => false, :message => 'Face too small.' } if n < 3

        fr = FabricEngine.frame_for(outer_loop, normal)
        local = outer_loop.map { |pt| pt.transform(fr[:inv]) }

        size = 0.0
        local.each do |pt|
          d = Math.sqrt(pt.x * pt.x + pt.y * pt.y)
          size = d if d > size
        end

        # hole polygon in local coords
        shape = p.fetch(:shape, 'rect')
        w = p[:width].to_f
        h = p.fetch(:height, p[:width]).to_f
        w = size * 0.3 if w <= 0
        h = w if h <= 0
        cu = p.fetch(:offset_u, 0).to_f
        cv = p.fetch(:offset_v, 0).to_f
        rounded = p.fetch(:rounded, true)

        hole = []
        if shape == 'circle'
          r = w / 2.0
          seg = p.fetch(:segments, 28).to_i
          seg = 48 if seg > 48
          (0...seg).each do |i|
            a = CoreGeometry::TAU * i.to_f / seg.to_f
            hole << Geom::Point3d.new(cu + Math.cos(a) * r, cv + Math.sin(a) * r, 0.0)
          end
        else
          hw = w / 2.0
          hh = h / 2.0
          rc = [CoreGeometry.clamp_f(p.fetch(:corner_radius, [hw, hh].min * 0.25).to_f || 0.0, 0.0, [hw * 0.9, hh * 0.9].min), 0.0].max
          if rounded && rc > 0.05
            seg = 4
            corners = [
              [cu - hw + rc, cv - hh + rc, 1.5 * Math::PI],
              [cu + hw - rc, cv - hh + rc, 0.0],
              [cu + hw - rc, cv + hh - rc, 0.5 * Math::PI],
              [cu - hw + rc, cv + hh - rc, 1.0 * Math::PI]
            ]
            corners.each do |cx, cy, a0|
              (0..seg).each do |i|
                a = a0 + (Math::PI / 2.0) * i.to_f / seg.to_f
                hole << Geom::Point3d.new(cx + Math.cos(a) * rc, cy + Math.sin(a) * rc, 0.0)
              end
            end
          else
            hole << Geom::Point3d.new(cu - hw, cv - hh, 0.0)
            hole << Geom::Point3d.new(cu + hw, cv - hh, 0.0)
            hole << Geom::Point3d.new(cu + hw, cv + hh, 0.0)
            hole << Geom::Point3d.new(cu - hw, cv + hh, 0.0)
          end
        end

        annulus = CoreGeometry.build_star_annulus(local, hole, 36)
        return { :ok => false, :message => 'Opening shape does not fit inside the face.' } unless annulus

        outer_local = annulus[:outer]
        hole_local = annulus[:hole]
        centre_local = annulus[:centre]

        depth = p[:depth].to_f
        depth = size * 0.25 if depth <= 0

        outer_top = outer_local.map { |pt| pt.transform(fr[:trans]) }
        hole_top = hole_local.map { |pt| pt.transform(fr[:trans]) }
        hole_bottom = hole_top.map { |pt| pt.offset(normal, -depth) }
        outer_bottom = outer_top.map { |pt| pt.offset(normal, -depth) }

        mesh = Geom::PolygonMesh.new
        bands = [
          [outer_top, hole_top, false],
          [hole_top, hole_bottom, false],
          [hole_bottom, outer_bottom, true],
          [outer_bottom, outer_top, true]
        ]
        bands.each do |a_ring, b_ring, flip|
          rn = a_ring.size
          (0...rn).each do |i|
            jn = (i + 1) % rn
            q = [a_ring[i], a_ring[jn], b_ring[jn], b_ring[i]]
            q = q.reverse if flip
            ia = mesh.add_point(q[0]); ib = mesh.add_point(q[1]); ic = mesh.add_point(q[2])
            idd = mesh.add_point(q[3])
            begin
              mesh.add_polygon(ia, ib, ic) if ia != ib && ib != ic && ic != ia
              mesh.add_polygon(ia, ic, idd) if ia != ic && ic != idd && idd != ia
            rescue => e
              $stderr.puts "Plush: opening polygon failed: #{e.message}"
            end
          end
        end

        begin
          face.erase!
        rescue => e
          $stderr.puts "Plush: erase failed: #{e.message}"
        end

        begin
          entities.add_faces_from_mesh(mesh)
        rescue => e
          $stderr.puts "Plush: opening faces failed: #{e.message}"
        end
        entity_list = entities.to_a
        face_edges = []
        entity_list.grep(Sketchup::Edge).each do |e|
          face_edges << e
        end
        cleanup_coplanar_edges(face_edges)
        { :ok => true }
      end

      # ==================================================================
      # LOFT
      # ==================================================================
      def loft(model, edges, p)
        model.start_operation('Plush Loft', true)
        begin
          pairs = edges_to_pairs(edges)
          loops = CoreGeometry.extract_loops_from_pairs(pairs)
          if loops.size < 2
            model.abort_operation rescue nil
            return { :ok => false, :message => 'Select two closed edge loops to loft.' }
          end

          loop_a = loops[0]
          loop_b = loops[1]
          if loop_a.size != loop_b.size
            target = [loop_a.size, loop_b.size].max
            loop_a = CoreGeometry.resample_loop(loop_a, target)
            loop_b = CoreGeometry.resample_loop(loop_b, target)
          end
          loop_b = loop_b.reverse if CoreGeometry.loop_winding(loop_a) != CoreGeometry.loop_winding(loop_b)

          segments = (p[:segments] || 8).to_i
          segments = 2 if segments < 2
          segments = 50 if segments > 50
          smooth = p.fetch(:style, 'ruled') == 'smooth'
          n = loop_a.size

          all_loops = [loop_a]
          (1...segments).each do |i|
            t = i.to_f / segments.to_f
            interp = []
            (0...n).each do |j|
              if smooth
                eased = t * t * (3.0 - 2.0 * t)
                interp << Geom::Point3d.linear_combination(1.0 - eased, loop_a[j], eased, loop_b[j])
              else
                interp << Geom::Point3d.linear_combination(1.0 - t, loop_a[j], t, loop_b[j])
              end
            end
            all_loops << interp
          end
          all_loops << loop_b

          grp = model.active_entities.add_group
          ge = grp.entities
          mesh = Geom::PolygonMesh.new
          idx = all_loops.map { |loop| loop.map { |pt| mesh.add_point(pt) } }
          (0...segments).each do |i|
            (0...n).each do |j|
              jn = (j + 1) % n
              a = idx[i][j]; b = idx[i][jn]; c = idx[i + 1][jn]; d = idx[i + 1][j]
              begin
                mesh.add_polygon(a, b, c) if a != b && b != c && c != a
                mesh.add_polygon(a, c, d) if a != c && c != d && d != a
              rescue => e
                $stderr.puts "Plush: loft polygon failed: #{e.message}"
              end
            end
          end
          existing = ge.grep(Sketchup::Edge).to_a
          ge.add_faces_from_mesh(mesh)
          new_edges = ge.grep(Sketchup::Edge).to_a - existing
          soften_edges(new_edges)

          if p.fetch(:cap_start, true)
            begin
              ge.add_face(loop_a)
            rescue => e
              $stderr.puts "Plush: loft cap failed: #{e.message}"
            end
          end
          if p.fetch(:cap_end, true)
            begin
              ge.add_face(loop_b.reverse)
            rescue => e
              $stderr.puts "Plush: loft cap failed: #{e.message}"
            end
          end
        rescue => e
          model.abort_operation rescue nil
          return { :ok => false, :message => "Loft error: #{e.message}" }
        end
        model.commit_operation
        { :ok => true }
      end

      def edges_to_pairs(edges)
        pairs = []
        edges.each do |e|
          next unless e && e.valid?
          pairs << [e.start.position, e.end.position]
        end
        pairs
      end

      # ==================================================================
      # PIPE / TUBE
      # ==================================================================
      def pipe(model, edges, p)
        model.start_operation('Plush Pipe', true)
        begin
          pairs = edges_to_pairs(edges)
          trace = CoreGeometry.chain_path_from_pairs(pairs)
          path = trace[:points]
          if path.size < 2
            model.abort_operation rescue nil
            return { :ok => false, :message => 'Could not trace a valid path from the selection.' }
          end

          outer_dia = p[:outer_diameter].to_f
          inner_dia = p.fetch(:inner_diameter, 0.0).to_f
          outer_r = outer_dia / 2.0
          inner_r = inner_dia > 0 ? inner_dia / 2.0 : 0.0
          sides = (p[:sides] || 24).to_i
          sides = 3 if sides < 3
          sides = 64 if sides > 64
          caps = p.fetch(:caps, 'none')

          grp = model.active_entities.add_group
          ge = grp.entities

          profiles = []
          prev_u = nil
          prev_t = nil
          path.each_with_index do |pt, i|
            tangent = if i < path.size - 1
                        path[i + 1] - pt
                      else
                        pt - path[i - 1]
                      end
            if tangent.length < 1.0e-9
              tangent = Geom::Vector3d.new(0, 0, 1)
            end
            tangent.normalize!

            if prev_u && prev_t
              proj = prev_u - prev_t * (prev_u.dot(prev_t))
              if proj.length < 0.001
                u_axis = tangent.z.abs > 0.999 ? Geom::Vector3d.new(1, 0, 0) : Geom::Vector3d.new(0, 0, 1).cross(tangent).normalize
              else
                u_axis = proj.normalize
              end
            else
              u_axis = tangent.z.abs > 0.999 ? Geom::Vector3d.new(1, 0, 0) : Geom::Vector3d.new(0, 0, 1).cross(tangent).normalize
            end
            v_axis = tangent.cross(u_axis)
            v_axis.normalize! rescue nil
            prev_u = u_axis.clone
            prev_t = tangent.clone

            outer_loop = []
            inner_loop = []
            (0...sides).each do |s|
              a = CoreGeometry::TAU * s.to_f / sides.to_f
              co = Math.cos(a)
              si = Math.sin(a)
              outer_loop << pt + (u_axis * (co * outer_r)) + (v_axis * (si * outer_r))
              inner_loop << pt + (u_axis * (co * inner_r)) + (v_axis * (si * inner_r)) if inner_r > 0
            end
            profiles << { :outer => outer_loop, :inner => inner_loop }
          end

          mesh = Geom::PolygonMesh.new
          outer_idx = profiles.map { |pl| pl[:outer].map { |pt| mesh.add_point(pt) } }
          inner_idx = profiles.map { |pl| pl[:inner].map { |pt| mesh.add_point(pt) } }
          num = profiles.size
          (0...num - 1).each do |i|
            (0...sides).each do |j|
              jn = (j + 1) % sides
              a = outer_idx[i][j]; b = outer_idx[i][jn]; c = outer_idx[i + 1][jn]; d = outer_idx[i + 1][j]
              begin
                mesh.add_polygon(a, b, c) if a != b && b != c && c != a
                mesh.add_polygon(a, c, d) if a != c && c != d && d != a
              rescue => e
                $stderr.puts "Plush: pipe polygon failed: #{e.message}"
              end
              next unless inner_r > 0
              ia = inner_idx[i][j]; ib = inner_idx[i][jn]; ic = inner_idx[i + 1][jn]; idd = inner_idx[i + 1][j]
              begin
                mesh.add_polygon(ib, ic, ia) if ib != ic && ic != ia && ia != ib
                mesh.add_polygon(ic, idd, ia) if ic != idd && idd != ia && ia != ic
              rescue => e
                $stderr.puts "Plush: pipe polygon failed: #{e.message}"
              end
            end
          end
          begin
            mesh.add_polygon(outer_idx.first) if caps == 'both' || caps == 'start'
            mesh.add_polygon(outer_idx.last.reverse) if caps == 'both' || caps == 'end'
          rescue => e
            $stderr.puts "Plush: pipe caps failed: #{e.message}"
          end

          existing = ge.grep(Sketchup::Edge).to_a
          ge.add_faces_from_mesh(mesh)
          new_edges = ge.grep(Sketchup::Edge).to_a - existing
          soften_edges(new_edges)
        rescue => e
          model.abort_operation rescue nil
          return { :ok => false, :message => "Pipe error: #{e.message}" }
        end
        model.commit_operation
        { :ok => true }
      end

      # ==================================================================
      # Bulk edge utilities
      # ==================================================================
      def soften_edges(edges)
        edges.each do |e|
          next unless e && e.valid?
          e.soft = true
          e.smooth = true
        end
      end

      def soften_all_selection(selection)
        edges = collect_edges(selection)
        model = Sketchup.active_model
        model.start_operation('Plush Soften All Edges', true)
        soften_edges(edges)
        model.commit_operation
        edges.size
      end

      def harden_all_selection(selection)
        edges = collect_edges(selection)
        model = Sketchup.active_model
        model.start_operation('Plush Harden All Edges', true)
        edges.each do |e|
          next unless e && e.valid?
          e.soft = false
          e.smooth = false
        end
        model.commit_operation
        edges.size
      end

      def collect_edges(selection)
        edges = []
        stack = selection.to_a.dup
        until stack.empty?
          ent = stack.pop
          next unless ent && ent.valid?
          case ent
          when Sketchup::Edge
            edges << ent
          when Sketchup::Face
            ent.edges.each { |e| edges << e }
          when Sketchup::Group
            stack.concat(ent.entities.to_a)
          when Sketchup::ComponentInstance
            stack.concat(ent.definition.entities.to_a)
          end
        end
        edges.uniq
      end

      def cleanup_coplanar_edges(edges_or_entities)
        edges = edges_or_entities.is_a?(Array) ? edges_or_entities : edges_or_entities.grep(Sketchup::Edge).to_a
        doomed = []
        edges.each do |edge|
          next unless edge && edge.valid?
          if edge.faces.size == 2
            f1, f2 = edge.faces
            if f1.normal.parallel?(f2.normal) && f1.normal.dot(f2.normal) > 0.999
              doomed << edge
            end
          end
        end
        doomed.each { |e| e.erase! if e.valid? } unless doomed.empty?
        doomed.size
      end

      def find_extrusion_depth(face)
        side_edges = []
        face.vertices.each do |v|
          v.edges.each do |e|
            next if e.faces.include?(face)
            side_edges << e
          end
        end
        side_edges.uniq!
        return nil if side_edges.empty?

        parallel = side_edges.select do |e|
          next false unless e.valid?
          (e.end.position - e.start.position).normalize.parallel?(face.normal)
        end
        return nil if parallel.empty?
        parallel.map { |e| e.length }.min
      end
    end
  end
end
