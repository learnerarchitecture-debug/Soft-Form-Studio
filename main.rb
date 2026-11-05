# =============================================================================
# Plush - Soft Form Studio by ArchInsights
# main.rb - Dialog, operations, menu/toolbar registration, licensing
# =============================================================================
# frozen_string_literal: true

require 'sketchup.rb'
require 'json'

require File.join(File.dirname(__FILE__), 'core_geometry.rb')
require File.join(File.dirname(__FILE__), 'fabric_engine.rb')
require File.join(File.dirname(__FILE__), 'curves.rb')
require File.join(File.dirname(__FILE__), 'updater.rb')

module Archinsights
  module Plush
    TOOL_PATHS = File.dirname(__FILE__)
    UI_HTML_PATH = File.join(TOOL_PATHS, 'ui.html')
    ICON_DIR = File.join(TOOL_PATHS, 'icons')

    # License storage intentionally keeps the legacy preference key so
    # customers who activated a previous build stay activated.
    LICENSE_PREF = 'com.archinsights.softedges.v3'
    STATE_PREF = 'com.archinsights.plush.state'
    SECRET_SALT = 'ArchinsightsSecretSaltKey2026!'

    @active_tab = 'corners'
    @pillow_height = 15.cm
    @pillow_form = 'sofa'

    # ======================================================================
    # Dialog
    # ======================================================================
    def self.show_dialog(tab_name = 'corners')
      @active_tab = tab_name

      if @dialog && @dialog.visible?
        @dialog.bring_to_front
        @dialog.execute_script("switchTool(#{@active_tab.to_json})")
        return
      end

      @dialog = UI::HtmlDialog.new(
        {
          :dialog_title => 'Plush - Soft Form Studio',
          :preferences_key => 'com.archinsights.plush.v2',
          :scrollable => false,
          :resizable => true,
          :min_width => 340,
          :min_height => 480,
          :max_width => 1080,
          :max_height => 1100,
          :width => 400,
          :height => 740,
          :left => 120,
          :top => 120,
          :style => UI::HtmlDialog::STYLE_DIALOG
        }
      )
      @dialog.set_size(400, 740)

      # ---- geometry operations -------------------------------------------
      @dialog.add_action_callback('apply_rounding') { |_ctx, params|
        apply_soft_edges_request(params)
      }
      @dialog.add_action_callback('apply_pillow') { |_ctx, params|
        self.apply_pillow_request(params)
      }
      @dialog.add_action_callback('apply_mattress') { |_ctx, params|
        self.apply_mattress_request(params)
      }
      @dialog.add_action_callback('apply_cushion') { |_ctx, params|
        self.apply_cushion_request(params)
      }
      @dialog.add_action_callback('apply_drape') { |_ctx, params|
        self.apply_drape_request(params)
      }
      @dialog.add_action_callback('apply_wall_curve') { |_ctx, params|
        self.apply_wall_curve_request(params)
      }
      @dialog.add_action_callback('apply_ceiling_curve') { |_ctx, params|
        self.apply_ceiling_curve_request(params)
      }
      @dialog.add_action_callback('apply_curved_pushpull') { |_ctx, params|
        self.apply_pushpull_request(params)
      }
      @dialog.add_action_callback('apply_opening') { |_ctx, params|
        self.apply_opening_request(params)
      }
      @dialog.add_action_callback('apply_loft') { |_ctx, params|
        self.apply_loft_request(params)
      }
      @dialog.add_action_callback('apply_pipe') { |_ctx, params|
        self.apply_pipe_request(params)
      }
      @dialog.add_action_callback('apply_soften_all') { |_ctx|
        self.finish_request { self.utility_soften_all }
      }
      @dialog.add_action_callback('apply_harden_all') { |_ctx|
        self.finish_request { self.utility_harden_all }
      }
      @dialog.add_action_callback('apply_batch_soften') { |_ctx, params|
        self.apply_batch_soften_request(params)
      }

      # ---- interactive pillow click tool ---------------------------------
      @dialog.add_action_callback('update_pillow_height') { |_ctx, params|
        unit = params['unit']
        @pillow_height = self.parse_length_input(params['height'].to_s, unit) rescue 15.cm
      }
      @dialog.add_action_callback('update_pillow_form') { |_ctx, params|
        @pillow_form = params['form'].to_s
      }
      @dialog.add_action_callback('activate_pillow_tool') { |_ctx|
        self.activate_pillow_tool
      }
      @dialog.add_action_callback('deactivate_pillow_tool') { |_ctx|
        self.deactivate_pillow_tool
      }

      # ---- housekeeping ---------------------------------------------------
      @dialog.add_action_callback('get_initial_tab') { |_ctx|
        @dialog.execute_script("switchTool(#{@active_tab.to_json})")
      }
      @dialog.add_action_callback('get_model_unit') { |_ctx|
        @dialog.execute_script("setWorkspaceUnit(#{self.get_model_unit_name.to_json})")
      }
      @dialog.add_action_callback('check_selection') { |_ctx|
        status = self.validate_selection
        payload = { 'valid' => status[:valid], 'message' => status[:message], 'count' => status[:count] || 0 }
        @dialog.execute_script("updateSelectionStatus(#{JSON.generate(payload)})")
      }
      @dialog.add_action_callback('close_dialog') { |_ctx|
        @dialog.close
      }
      @dialog.add_action_callback('set_window_minimized') { |_ctx, minimized|
        if minimized
          @dialog.set_size(@dialog_width_held || 400, 54)
        else
          @dialog.set_size(@dialog_width_held || 400, @dialog_height_held || 740)
        end
      }
      @dialog.add_action_callback('set_window_maximized') { |_ctx, maximized|
        if maximized
          @dialog_width_held = 400
          @dialog_height_held = 740
          @dialog.set_size(720, 940)
        else
          @dialog.set_size(400, 740)
        end
      }
      @dialog.add_action_callback('cancel_preview') { |_ctx|
        self.cancel_preview
      }

      # ---- settings persistence -------------------------------------------
      @dialog.add_action_callback('save_state') { |_ctx, params|
        self.save_ui_state(params)
      }
      @dialog.add_action_callback('get_state') { |_ctx|
        @dialog.execute_script("applySavedState(#{JSON.generate(self.load_ui_state)})")
      }

      # ---- licensing (unchanged algorithm; same storage for continuity) ----
      @dialog.add_action_callback('get_license_status') { |_ctx|
        self.send_license_status
      }
      @dialog.add_action_callback('activate_online') { |_ctx, params|
        self.activate_online(params)
      }
      @dialog.add_action_callback('on_activation_success') { |_ctx, params|
        self.store_license(params['email'], params['key'], params['type'] || 'Commercial', params['expires'] || 'Permanent')
      }
      @dialog.add_action_callback('on_activation_offline_fallback') { |_ctx, params|
        self.offline_fallback(params['email'], params['key'])
      }
      @dialog.add_action_callback('remove_license') { |_ctx|
        self.remove_license
      }

      # ---- updates ---------------------------------------------------------
      @dialog.add_action_callback('check_update_now') { |_ctx|
        self.send_update_result(Updater.check_now(@dialog))
      }
      @dialog.add_action_callback('update_download') { |_ctx|
        self.send_update_result(Updater.download_and_prepare(@dialog, Updater.fetch_manifest))
      }
      @dialog.add_action_callback('update_install') { |_ctx, params|
        ok = Updater.open_installer(params['path'].to_s)
        @dialog.execute_script("installRequested(#{ok.to_s});")
      }
      @dialog.add_action_callback('get_update_info') { |_ctx|
        info = {
          'version' => Plush::VERSION,
          'auto' => Updater.auto_check?,
          'feed' => Updater.feed_url,
          'last_check' => Updater.last_check,
          'environment' => Updater.environment
        }
        @dialog.execute_script("applyUpdateInfo(#{JSON.generate(info)});")
      }
      @dialog.add_action_callback('set_update_prefs') { |_ctx, params|
        Updater.auto_check = (params['auto'] == true || params['auto'] == 'true')
        Updater.feed_url = params['feed'].to_s if params['feed'] && !params['feed'].empty?
        @dialog.execute_script("applyUpdatePrefs(#{params['auto'] == true || params['auto'] == 'true'});")
      }
      @dialog.add_action_callback('dismiss_update') { |_ctx, params|
        Updater.ignore_version!(params['version'].to_s)
      }

      @dialog.set_on_closed do
        self.cancel_preview
        @dialog = nil
      end

      @dialog.show
      self.send_update_info_soon
    end

    def self.dialog_alive?
      !@dialog.nil? && @dialog.visible?
    end

    # ======================================================================
    # Soften corners request (auto or manual radius)
    # ======================================================================
    def self.apply_soft_edges_request(params)
      return unless self.license_gate
      model = Sketchup.active_model
      faces = self.selection_faces
      if faces.empty?
        self.op_done(false, 'Select at least one face to soften corners.')
        return
      end
      unit = params['unit'] || 'model'
      mode = params['mode'].to_s.empty? ? 'auto' : params['mode']
      radius = mode == 'manual' ? self.parse_length_input(params['radius'].to_s, unit) : 0.to_l
      if mode == 'manual' && radius <= 0
        self.op_done(false, 'Radius must be greater than zero.')
        return
      end
      result = Curves.apply_soft_edges(model, faces, mode, radius)
      self.op_done(result[:ok], result[:message])
    end

    # Runs a block and answers the UI with opDone(ok, message)
    def self.finish_request
      result = yield
      result = { :ok => true, :message => 'Done.' } unless result.is_a?(Hash)
      self.op_done(result[:ok], result[:message] || '')
    end

    def self.op_done(ok, message)
      return unless dialog_alive?
      @dialog.execute_script("opDone(#{ok == true}, #{message.to_json});")
    end

    def self.send_update_result(result)
      return unless dialog_alive?
      payload = {
        'ok' => result[:ok],
        'message' => result[:message].to_s,
        'update' => result[:update] ? {
          'version' => result[:update][:version],
          'notes' => result[:update][:notes],
          'released_at' => result[:update][:released_at],
          'size' => result[:update][:size]
        } : nil
      }
      @dialog.execute_script("updateCheckResult(#{JSON.generate(payload)});")
    end

    def self.send_update_info_soon
      UI.start_timer(2.5, false) do
        next unless dialog_alive?
        info = {
          'version' => Plush::VERSION,
          'auto' => Updater.auto_check?,
          'feed' => Updater.feed_url,
          'last_check' => Updater.last_check,
          'environment' => Updater.environment
        }
        @dialog.execute_script("applyUpdateInfo(#{JSON.generate(info)});")
      end
      UI.start_timer(9.0, false) do
        Updater.silent_check(@dialog)
      end
    end

    # ======================================================================
    # Units
    # ======================================================================
    def self.get_model_unit_name
      model = Sketchup.active_model
      return 'model' unless model
      code = model.options['UnitsOptions']['LengthUnit']
      case code
      when 0 then 'in'
      when 1 then 'ft'
      when 2 then 'mm'
      when 3 then 'cm'
      when 4 then 'm'
      else 'model'
      end
    end

    def self.parse_length_input(val_str, unit_name)
      clean_str = val_str.to_s.strip
      return 0.to_l if clean_str.empty?
      return clean_str.to_l if clean_str =~ /(?:mm|cm|m|in|ft|'|\")\z/i

      case unit_name.to_s
      when 'mm' then "#{clean_str}mm".to_l
      when 'cm' then "#{clean_str}cm".to_l
      when 'm' then "#{clean_str}m".to_l
      when 'in' then "#{clean_str}\"".to_l
      when 'ft' then "#{clean_str}'".to_l
      else clean_str.to_l
      end
    end

    def self.selection_faces
      model = Sketchup.active_model
      return [] unless model
      model.selection.grep(Sketchup::Face)
    end

    def self.selection_edges
      model = Sketchup.active_model
      return [] unless model
      model.selection.grep(Sketchup::Edge)
    end

    def self.validate_selection
      model = Sketchup.active_model
      return { :valid => false, :message => 'No active model open.' } unless model
      selection = model.selection
      if selection.empty?
        return { :valid => false, :message => 'Select geometry in the model.' }
      end
      faces = selection.grep(Sketchup::Face)
      edges = selection.grep(Sketchup::Edge)
      if faces.empty? && !edges.empty?
        return { :valid => true, :message => "#{edges.size} edge(s) ready.", :count => edges.size }
      end
      if faces.empty?
        return { :valid => false, :message => 'Select at least one face or edge.' }
      end
      { :valid => true, :message => 'Ready.', :count => faces.size }
    end

    def self.cancel_preview
      model = Sketchup.active_model
      return unless model
      model.select_tool(nil)
    rescue
      nil
    end

    # ======================================================================
    # Shared request helpers
    # ======================================================================
    def self.license_gate
      return true if license_valid?
      UI.messagebox('Plush needs activation. Please open the profile panel and activate your license.')
      false
    end

    def self.params_color(params, fallback)
      hex = params['color'].to_s
      hex = fallback if hex.empty?
      hex
    end

    def self.build_wrapped_group(face, label, opts = {})
      entities = face.parent.entities
      old_depth = Curves.find_extrusion_depth(face)
      box_entities = self.collect_3d_box_entities(face, old_depth)
      boundary_edges = face.edges.clone
      grp = entities.add_group
      grp.name = label
      if opts[:erase_old] == false
        box_entities = []
      end
      { :group => grp, :entities => grp.entities, :box_entities => box_entities, :boundary_edges => boundary_edges }
    end

    def self.finalize_wrapped_group(container, opts = {})
      entities = container[:entities]
      entities.erase_entities(container[:box_entities]) unless container[:box_entities].empty?
      loose = container[:boundary_edges].select { |e| e.valid? && e.faces.empty? }
      entities.erase_entities(loose) unless loose.empty?
      grp = container[:group]
      if opts[:color]
        self.apply_fabric_material(grp, opts[:color])
      end
      grp
    end

    # ======================================================================
    # PILLOW
    # ======================================================================
    def self.apply_pillow_request(params)
      return unless self.license_gate
      faces = self.selection_faces
      if faces.empty?
        self.op_done(false, 'Select a face in the model, or use the Click Tool directly in the viewport.')
        return
      end
      p = self.pillow_params(params, { :rest => params['rest'] == true || params['rest'] == 'true' })
      model = Sketchup.active_model
      model.start_operation('Plush Pillow', true)
      begin
        faces.each do |face|
          next unless face.valid?
          world_loop = face.outer_loop.vertices.map { |v| v.position.clone }
          container = self.build_wrapped_group(face, 'Plush Pillow')
          stack = FabricEngine.pillow_stack(world_loop, face.normal, p)
          FabricEngine.build_ring_mesh(container[:entities], stack[:rings], { :caps => [0, stack[:rings].size - 1] })
          self.finalize_wrapped_group(container, { :color => self.params_color(params, '#e9c8c2') })
        end
      rescue => e
        model.abort_operation rescue nil
        self.op_done(false, "Pillow error: #{e.message}")
        return
      end
      model.commit_operation
      self.op_done(true, 'Pillow ready.')
    end

    def self.pillow_params(params, overrides = {})
      unit = params['unit'] || 'model'
      height = self.parse_length_input(params['height'].to_s, unit) rescue 15.cm
      form = params['form'].to_s
      form = 'sofa' if form.empty?
      @pillow_form = form
      @pillow_height = height
      profile = {
        'sofa' => { :puff => 0.72, :pleats => 0.55, :top_piping => false },
        'euro' => { :puff => 0.52, :pleats => 0.30, :top_piping => true },
        'body' => { :puff => 0.85, :pleats => 0.80, :top_piping => false }
      }[form] || { :puff => 0.72, :pleats => 0.55, :top_piping => false }
      {
        :height => height.to_f,
        :drape => CoreGeometry.clamp_f((params['drape'] || 45).to_f / 100.0, 0.0, 1.0),
        :puff => CoreGeometry.clamp_f((params['puff'] || profile[:puff] * 100).to_f / 100.0, 0.2, 1.0),
        :wrinkle => CoreGeometry.clamp_f((params['wrinkle'] || 55).to_f / 100.0, 0.0, 1.0),
        :detail => (params['detail'] || 7).to_i,
        :seed => (params['seed'] || 1).to_i,
        :pleats => profile[:pleats],
        :piping => (params['piping'] != false && params['piping'] != 'false'),
        :top_piping => (params['top_piping'] == true || params['top_piping'] == 'true') || profile[:top_piping],
        :folds => ((params['folds'] || 6).to_i) == 0 ? 6 : (params['folds'] || 6).to_i.abs % 12
      }.merge(overrides)
    end

    # ======================================================================
    # MATTRESS
    # ======================================================================
    def self.apply_mattress_request(params)
      return unless self.license_gate
      faces = self.selection_faces
      if faces.empty?
        self.op_done(false, 'Select a face to build the mattress on.')
        return
      end
      model = Sketchup.active_model
      unit = params['unit'] || 'model'
      thickness = self.parse_length_input(params['thickness'].to_s, unit) rescue 25.cm
      style = params['style'].to_s.empty? ? 'classic' : params['style']
      pattern = params['pattern'].to_s.empty? ? 'none' : params['pattern']
      tuft = (params['tuft'] == true || params['tuft'] == 'true')
      bulge = CoreGeometry.clamp_f((params['bulge'] || 45).to_f / 100.0, 0.0, 1.0)
      seed = (params['seed'] || 5).to_i

      model.start_operation('Plush Mattress', true)
      begin
        faces.each do |face|
          next unless face.valid?
          world_loop = face.outer_loop.vertices.map { |v| v.position.clone }
          base_params = {
            :height => thickness.to_f,
            :bulge => bulge,
            :piping => true,
            :pattern => pattern.empty? || pattern == 'none' ? nil : pattern,
            :pocket => 0.9.cm,
            :groove => 0.45.cm,
            :cells => self.quilt_cells_for(thickness, world_loop),
            :tuft => tuft,
            :seed => seed
          }
          container = self.build_wrapped_group(face, 'Plush Mattress')
          side = FabricEngine.mattress_side_rings(world_loop, face.normal, base_params)
          FabricEngine.build_ring_mesh(container[:entities], side[:rings], { :caps => [0, side[:rings].size - 1] })

          if style == 'pillowtop' || style == 'euro'
            top_h = style == 'euro' ? thickness * 0.28 : thickness * 0.22
            top_h = 1.5.cm if top_h < 1.5.cm
            topper = FabricEngine.pillow_stack(
              self.shift_loop(world_loop, face.normal, base_params[:height]),
              face.normal,
              {
                :height => top_h.to_f, :rest => true, :puff => 0.55,
                :drape => 0.35, :wrinkle => 0.30, :pleats => 0.4,
                :detail => 5, :seed => seed, :piping => true,
                :top_piping => false, :folds => 4
              }
            )
            FabricEngine.build_ring_mesh(container[:entities], topper[:rings], { :caps => [0, topper[:rings].size - 1] })
          end

          if base_params[:pattern] && FabricEngine.rectangle_corners(world_loop, face.normal)
            quilt = FabricEngine.quilt_grid(world_loop, face.normal, side[:rings].last, base_params)
            if quilt
              FabricEngine.build_quilt_cap(container[:entities], quilt, side[:rings].last, face.normal)
              if tuft
                self.mattress_tufts(container[:entities], quilt, face.normal, seed)
              end
            end
          end

          self.finalize_wrapped_group(container, { :color => self.params_color(params, '#dfeef0') })
        end
      rescue => e
        model.abort_operation rescue nil
        self.op_done(false, "Mattress error: #{e.message}")
        return
      end
      model.commit_operation
      self.op_done(true, 'Mattress ready.')
    end

    def self.quilt_cells_for(thickness, world_loop)
      span = 0.0
      pts = world_loop
      (0...pts.size).each do |i|
        span = [span, pts[i].distance(pts[(i + 1) % pts.size])].max
      end
      target = 16.cm
      cells = (span / target).round
      cells = 3 if cells < 3
      cells = 14 if cells > 14
      cells
    end

    def self.mattress_tufts(entities, quilt, normal, seed)
      grid = quilt[:grid]
      cols = quilt[:cols]
      rows = quilt[:rows]
      rng = CoreGeometry::Rng.new(seed * 31 + 7)
      step_x = [rows / 3, 1].max
      step_y = [cols / 3, 1].max
      radius = 1.4.cm
      depth = 1.1.cm
      (0...rows).each do |j|
        next if (j % step_x) != (step_x / 2) && j != rows - 1
        (0...cols).each do |i|
          next if (i % step_y) != (step_y / 2) && i != cols - 1
          center = grid[j][i]
          rings = FabricEngine.crater_rings(center, normal, radius, depth)
          FabricEngine.build_ring_mesh(entities, rings, { :caps => [] })
          junk = rng.next_f
        end
      end
    end

    def self.shift_loop(world_loop, normal, distance)
      world_loop.map { |pt| pt.offset(normal, distance) }
    end

    # ======================================================================
    # CUSHION
    # ======================================================================
    def self.apply_cushion_request(params)
      return unless self.license_gate
      faces = self.selection_faces
      if faces.empty?
        self.op_done(false, 'Select a face for the seat cushion.')
        return
      end
      model = Sketchup.active_model
      model.start_operation('Plush Cushion', true)
      begin
        faces.each do |face|
          next unless face.valid?
          world_loop = face.outer_loop.vertices.map { |v| v.position.clone }
          unit = params['unit'] || 'model'
          height = self.parse_length_input(params['height'].to_s, unit) rescue 12.cm
          p = {
            :height => height.to_f,
            :drape => 0.25,
            :puff => 0.42,
            :wrinkle => CoreGeometry.clamp_f((params['wrinkle'] || 30).to_f / 100.0, 0.0, 1.0),
            :detail => (params['detail'] || 6).to_i,
            :seed => (params['seed'] || 11).to_i,
            :pleats => 0.22,
            :piping => true,
            :top_piping => true,
            :folds => 5,
            :rest => (params['rest'] != false)
          }
          container = self.build_wrapped_group(face, 'Plush Cushion')
          stack = FabricEngine.pillow_stack(world_loop, face.normal, p)
          FabricEngine.build_ring_mesh(container[:entities], stack[:rings], { :caps => [0, stack[:rings].size - 1] })
          self.finalize_wrapped_group(container, { :color => self.params_color(params, '#cdd9e8') })
        end
      rescue => e
        model.abort_operation rescue nil
        self.op_done(false, "Cushion error: #{e.message}")
        return
      end
      model.commit_operation
      self.op_done(true, 'Cushion ready.')
    end

    # ======================================================================
    # DRAPE
    # ======================================================================
    def self.apply_drape_request(params)
      return unless self.license_gate
      faces = self.selection_faces
      if faces.empty?
        self.op_done(false, 'Select the tabletop or base face to dress.')
        return
      end
      model = Sketchup.active_model
      model.start_operation('Plush Drape', true)
      begin
        faces.each do |face|
          next unless face.valid?
          world_loop = face.outer_loop.vertices.map { |v| v.position.clone }
          unit = params['unit'] || 'model'
          drop = self.parse_length_input(params['drop'].to_s, unit) rescue 30.cm

          p = {
            :drop => drop.to_f,
            :flare => CoreGeometry.clamp_f((params['flare'] || 50).to_f / 100.0, 0.0, 1.0),
            :wrinkle => CoreGeometry.clamp_f((params['wrinkle'] || 40).to_f / 100.0, 0.0, 1.0),
            :detail => (params['detail'] || 6).to_i,
            :seed => (params['seed'] || 21).to_i
          }
          entities = face.parent.entities
          grp = entities.add_group
          grp.name = 'Plush Drape'
          bands = FabricEngine.drape_rings(world_loop, face.normal, p)
          FabricEngine.build_ring_mesh(grp.entities, bands[:rings], { :open => bands[:open] })
          self.apply_fabric_material(grp, self.params_color(params, '#c9d7c5'))
        end
      rescue => e
        model.abort_operation rescue nil
        self.op_done(false, "Drape error: #{e.message}")
        return
      end
      model.commit_operation
      self.op_done(true, 'Drape ready.')
    end

    # ======================================================================
    # CURVED WALL
    # ======================================================================
    def self.apply_wall_curve_request(params)
      return unless self.license_gate
      model = Sketchup.active_model
      faces = self.selection_faces
      edges = self.selection_edges

      unit = params['unit'] || 'model'
      height = self.parse_length_input(params['height'].to_s, unit) rescue 240.cm
      amplitude = self.parse_length_input(params['amplitude'].to_s, unit) rescue 30.cm
      p = {
        :height => height.to_f,
        :amplitude => amplitude.to_f,
        :style => params['style'].to_s.empty? ? 'bulge' : params['style'],
        :waves => (params['waves'] || 2).to_i,
        :wrinkle => CoreGeometry.clamp_f((params['wrinkle'] || 15).to_f / 100.0, 0.0, 1.0),
        :detail => (params['detail'] || 6).to_i,
        :seed => (params['seed'] || 3).to_i
      }

      model.start_operation('Plush Curved Wall', true)
      built = 0
      begin
        ents = model.active_entities
        if !faces.empty?
          faces.each do |face|
            next unless face.valid?
            path = face.outer_loop.vertices.map { |v| v.position.clone }
            bands = Curves.curved_wall(nil, path, true, p)
            next unless bands[:ok].nil?
            grp = ents.add_group
            grp.name = 'Plush Curved Wall'
            FabricEngine.build_ring_mesh(grp.entities, bands[:rings], { :open => bands[:open] })
            built += 1
          end
        elsif !edges.empty?
          trace = CoreGeometry.chain_path_from_pairs(Curves.edges_to_pairs(edges))
          if trace[:points].size < 2
            model.abort_operation rescue nil
            self.op_done(false, 'Connect the selected edges into a path first.')
            return
          end
          bands = Curves.curved_wall(nil, trace[:points], trace[:closed], p)
          grp = ents.add_group
          grp.name = 'Plush Curved Wall'
          FabricEngine.build_ring_mesh(grp.entities, bands[:rings], { :open => bands[:open] })
          built += 1
        else
          model.abort_operation rescue nil
          self.op_done(false, 'Select a face (floor plan) or connected edges.')
          return
        end
      rescue => e
        model.abort_operation rescue nil
        self.op_done(false, "Curved Wall error: #{e.message}")
        return
      end
      model.commit_operation
      self.op_done(true, "#{built} curved wall(s) ready.")
    end

    # ======================================================================
    # CEILING CURVE
    # ======================================================================
    def self.apply_ceiling_curve_request(params)
      return unless self.license_gate
      faces = self.selection_faces
      if faces.empty?
        self.op_done(false, 'Select ceiling face(s) where they meet the walls.')
        return
      end
      model = Sketchup.active_model
      unit = params['unit'] || 'model'
      radius = self.parse_length_input(params['radius'].to_s, unit) rescue 15.cm
      style = params['style'].to_s.empty? ? 'cove' : params['style']
      p = {
        :radius => radius.to_f,
        :style => style,
        :segments => (params['segments'] || 9).to_i
      }
      model.start_operation('Plush Ceiling Curve', true)
      built = 0
      begin
        faces.each do |face|
          next unless face.valid?
          container_grp = face.parent.entities.add_group
          container_grp.name = 'Plush Ceiling Curve'
          built += Curves.ceiling_curve(container_grp.entities, [face], p)
        end
      rescue => e
        model.abort_operation rescue nil
        self.op_done(false, "Ceiling Curve error: #{e.message}")
        return
      end
      model.commit_operation
      self.op_done(true, "#{built} cove band(s) ready.")
    end

    # ======================================================================
    # CURVED PUSH/PULL
    # ======================================================================
    def self.apply_pushpull_request(params)
      return unless self.license_gate
      faces = self.selection_faces
      if faces.empty?
        self.op_done(false, 'Select curved faces to extrude.')
        return
      end
      model = Sketchup.active_model
      unit = params['unit'] || 'model'
      distance = self.parse_length_input(params['distance'].to_s, unit) rescue 0
      unified = params['mode'].to_s == 'unified'
      result = Curves.pushpull_curved(model, faces, distance.to_f, unified)
      if result[:ok]
        self.op_done(true, 'Extruded.')
      else
        self.op_done(false, result[:message] || 'Extrusion failed.')
      end
    end

    # ======================================================================
    # OPENINGS (cutout)
    # ======================================================================
    def self.apply_opening_request(params)
      return unless self.license_gate
      faces = self.selection_faces
      if faces.empty?
        self.op_done(false, 'Select a face to cut the opening in.')
        return
      end
      model = Sketchup.active_model
      unit = params['unit'] || 'model'
      p = {
        :shape => params['shape'].to_s.empty? ? 'rect' : params['shape'],
        :width => self.parse_length_input(params['width'].to_s, unit).to_f,
        :height => self.parse_length_input((params['height'].to_s.empty? ? params['width'].to_s : params['height'].to_s), unit).to_f,
        :offset_u => self.parse_length_input(params['offsetU'].to_s.empty? ? '0' : params['offsetU'].to_s, unit).to_f,
        :offset_v => self.parse_length_input(params['offsetV'].to_s.empty? ? '0' : params['offsetV'].to_s, unit).to_f,
        :depth => self.parse_length_input(params['depth'].to_s.empty? ? '0' : params['depth'].to_s, unit).to_f,
        :rounded => (params['rounded'] != false && params['rounded'] != 'false')
      }
      model.start_operation('Plush Opening', true)
      begin
        faces.each do |face|
          next unless face.valid?
          result = Curves.opening(face, p)
          unless result[:ok]
            model.abort_operation rescue nil
            self.op_done(false, result[:message].to_s)
            return
          end
        end
      rescue => e
        model.abort_operation rescue nil
        self.op_done(false, "Opening error: #{e.message}")
        return
      end
      model.commit_operation
      self.op_done(true, 'Opening created.')
    end

    # ======================================================================
    # LOFT
    # ======================================================================
    def self.apply_loft_request(params)
      return unless self.license_gate
      model = Sketchup.active_model
      edges = self.selection_edges
      if edges.size < 2
        self.op_done(false, 'Select the two profile loops to loft between.')
        return
      end
      p = {
        :segments => (params['segments'] || '8').to_i,
        :style => params['style'].to_s.empty? ? 'ruled' : params['style'],
        :cap_start => (params['capStart'] != false && params['capStart'] != 'false'),
        :cap_end => (params['capEnd'] != false && params['capEnd'] != 'false')
      }
      result = Curves.loft(model, edges, p)
      if result[:ok]
        self.op_done(true, 'Loft ready.')
      else
        self.op_done(false, result[:message] || 'Loft failed.')
      end
    end

    # ======================================================================
    # PIPE
    # ======================================================================
    def self.apply_pipe_request(params)
      return unless self.license_gate
      model = Sketchup.active_model
      edges = self.selection_edges
      if edges.empty?
        self.op_done(false, 'Select one or more connected edges for the pipe path.')
        return
      end
      unit = params['unit'] || 'model'
      p = {
        :outer_diameter => self.parse_length_input(params['outerDiameter'].to_s, unit).to_f,
        :inner_diameter => self.parse_length_input((params['innerDiameter'].to_s.empty? ? '0' : params['innerDiameter'].to_s), unit).to_f,
        :sides => (params['sides'] || '24').to_i,
        :caps => params['caps'].to_s.empty? ? 'none' : params['caps']
      }
      if p[:outer_diameter] <= 0
        self.op_done(false, 'Outer diameter must be positive.')
        return
      end
      result = Curves.pipe(model, edges, p)
      if result[:ok]
        self.op_done(true, 'Pipe ready.')
      else
        self.op_done(false, result[:message] || 'Pipe failed.')
      end
    end

    # ======================================================================
    # UTILITIES
    # ======================================================================
    def self.utility_soften_all
      model = Sketchup.active_model
      count = Curves.soften_all_selection(model.selection)
      { :ok => count > 0, :message => count > 0 ? "Softened #{count} edges." : 'Nothing selected.' }
    end

    def self.utility_harden_all
      model = Sketchup.active_model
      count = Curves.harden_all_selection(model.selection)
      { :ok => count > 0, :message => count > 0 ? "Hardened #{count} edges." : 'Nothing selected.' }
    end

    def self.apply_batch_soften_request(params)
      return unless self.license_gate
      model = Sketchup.active_model
      faces = self.selection_faces
      if faces.empty?
        self.op_done(false, 'Select faces (or groups) to soften.')
        return
      end
      # include direct faces of selected groups
      model.selection.grep(Sketchup::Group).each do |g|
        faces = faces.concat(g.entities.grep(Sketchup::Face))
      end
      faces.uniq!
      unit = params['unit'] || 'model'
      mode = params['mode'].to_s.empty? ? 'auto' : params['mode']
      result = Curves.apply_soft_edges(model, faces, mode, self.parse_length_input(params['radius'].to_s, unit))
      self.op_done(result[:ok], result[:message])
    end

    # ======================================================================
    # Fabric material
    # ======================================================================
    def self.apply_fabric_material(group, hex_color)
      return unless group && group.valid?
      model = Sketchup.active_model
      name = "Plush Fabric #{hex_color.to_s.upcase}"
      material = model.materials[name]
      if material.nil?
        material = model.materials.add(name)
        material.color = Sketchup::Color.new(hex_color)
      end
      group.entities.grep(Sketchup::Face).each do |f|
        f.material = material if f.valid?
      end
    rescue => e
      $stderr.puts "Plush: material failed: #{e.message}"
    end

    # ======================================================================
    # Geometric helpers shared across ops
    # ======================================================================
    def self.collect_3d_box_entities(face, depth)
      return [] unless depth
      remove_list = [face]
      normal = face.normal
      side_edges = []
      face.vertices.each do |v|
        v.edges.each do |e|
          next if e.faces.include?(face)
          next unless e.valid?
          vec = (e.end.position - e.start.position).normalize
          side_edges << e if vec.parallel?(normal)
        end
      end
      side_edges.uniq!
      side_edges.each do |e|
        remove_list << e
        e.faces.each do |f|
          next unless f.valid?
          remove_list << f
          f.edges.each { |fe| remove_list << fe if fe.valid? }
        end
      end
      remove_list.uniq.select { |ent| ent.valid? }
    end

    # ======================================================================
    # Legacy-compatible 3D helper used by group builders
    # ======================================================================
    def self.apply_pillow_to_selection(params)
      self.apply_pillow_request(params)
    end

    # ======================================================================
    # Interactive Pillow Click Tool
    # ======================================================================
    def self.activate_pillow_tool
      model = Sketchup.active_model
      return unless model
      model.select_tool(PillowClickTool.new)
    end

    def self.deactivate_pillow_tool
      model = Sketchup.active_model
      return unless model
      model.select_tool(nil)
    end

    def self.get_pillow_height_setting
      @pillow_height || 15.cm
    end

    class PillowClickTool
      def initialize
        @ip = Sketchup::InputPoint.new
        @current_face = nil
      end

      def activate
        Sketchup.status_text = 'Plush Pillow: click any face to generate a soft pillow.'
      end

      def deactivate(view)
        view.invalidate rescue nil
      end

      def onMouseMove(_flags, x, y, view)
        @ip.pick(view, x, y)
        ph = view.pick_helper
        ph.do_pick(x, y)
        @current_face = ph.picked_face
        view.invalidate
      end

      def onLButtonDown(_flags, x, y, view)
        ph = view.pick_helper
        ph.do_pick(x, y)
        face = ph.picked_face
        if face && face.valid?
          model = Sketchup.active_model
          model.start_operation('Plush Pillow', true)
          begin
            thickness = Plush.get_pillow_height_setting
            world_loop = face.outer_loop.vertices.map { |v| v.position.clone }
            container = Plush.build_wrapped_group(face, 'Plush Pillow')
            p = {
              :height => thickness.to_f, :rest => true, :drape => 0.45,
              :puff => 0.72, :wrinkle => 0.55, :detail => 7,
              :seed => Time.now.to_i % 100000, :pleats => 0.55,
              :piping => true, :top_piping => false, :folds => 6
            }
            stack = FabricEngine.pillow_stack(world_loop, face.normal, p)
            FabricEngine.build_ring_mesh(container[:entities], stack[:rings], { :caps => [0, stack[:rings].size - 1] })
            Plush.finalize_wrapped_group(container, {})
            model.commit_operation
          rescue => e
            model.abort_operation rescue nil
            UI.messagebox("Plush pillow error: #{e.message}")
          end
          @current_face = nil
          @ip.clear
          view.invalidate
        end
      end

      def draw(view)
        @ip.draw(view) if @ip.valid?
        if @current_face && @current_face.valid?
          view.drawing_color = '#e25689'
          view.line_width = 3
          pts = @current_face.outer_loop.vertices.map { |v| v.position }
          view.draw(GL_LINE_LOOP, pts)
        end
      end

      def onCancel(_flags, view)
        view.invalidate
      end
    end

    # ======================================================================
    # UI state persistence
    # ======================================================================
    def self.save_ui_state(params)
      Sketchup.write_default(STATE_PREF, 'state', JSON.generate(params))
    rescue => e
      $stderr.puts "Plush: save state failed: #{e.message}"
    end

    def self.load_ui_state
      raw = Sketchup.read_default(STATE_PREF, 'state', '')
      return {} if raw.to_s.empty?
      JSON.parse(raw)
    rescue
      {}
    end

    # ======================================================================
    # Licensing (identical algorithm to the previous build for continuity)
    # ======================================================================
    # Standard activation: the key is validated locally with the same seed
    # algorithm the generator uses, then bound to this machine.
    def self.activate_online(params)
      email = params['email'].to_s.strip
      key = params['key'].to_s.strip
      return self.alert_ui('Please enter both the email and the license key.') if email.empty? || key.empty?
      unless self.verify_license_key(email, key)
        return self.alert_ui('That email and key pair is not valid. Check for typos or contact support.')
      end
      expiry = key.split('-').first
      self.store_license(email, key, 'Commercial', "#{expiry[0, 4]}-#{expiry[4, 2]}-#{expiry[6, 2]}")
    end

    def self.license_valid?
      email = Sketchup.read_default(LICENSE_PREF, 'license_email', '')
      key = Sketchup.read_default(LICENSE_PREF, 'license_key', '')
      stored = Sketchup.read_default(LICENSE_PREF, 'license_machine_id', '')
      return false if email.nil? || email.empty? || key.nil? || key.empty?
      begin
        return false unless self.verify_license_key(email, key)
        return stored == self.machine_fingerprint
      rescue
        false
      end
    end

    def self.verify_license_key(email, key)
      return false if email.nil? || key.nil?
      parts = key.strip.split('-')
      return false if parts.length != 4
      expiry = parts[0]
      return false unless expiry =~ /\A\d{8}\z/
      begin
        t_expiry = Time.new(expiry[0, 4].to_i, expiry[4, 2].to_i, expiry[6, 2].to_i, 23, 59, 59)
      rescue
        return false
      end
      return false if Time.now > t_expiry
      expected = self.license_signature(email, expiry)
      parts[1, 3].join('-') == expected
    end

    def self.license_signature(email, expiry)
      raw = "#{email.to_s.strip.downcase}|#{expiry}|#{SECRET_SALT}"
      digest = Digest::SHA256.hexdigest(raw)
      "#{digest[0, 4]}-#{digest[4, 4]}-#{digest[8, 4]}".upcase
    end

    def self.machine_fingerprint
      comp = ENV['COMPUTERNAME'] || ENV['HOSTNAME'] || `hostname`.strip rescue 'PC'
      prof = ENV['USERPROFILE'] || ENV['HOME'] || 'USER'
      digest = Digest::SHA256.hexdigest("#{comp.to_s.strip.upcase}||#{prof.to_s.strip.upcase}")
      "#{digest[0, 4]}-#{digest[4, 4]}".upcase
    end

    def self.store_license(email, key, kind, expiry)
      begin
        if self.verify_license_key(email, key)
          Sketchup.write_default(LICENSE_PREF, 'license_email', email)
          Sketchup.write_default(LICENSE_PREF, 'license_key', key)
          Sketchup.write_default(LICENSE_PREF, 'license_machine_id', self.machine_fingerprint)
          Sketchup.write_default(LICENSE_PREF, 'license_activation_date', Time.now.strftime('%Y-%m-%d'))
          Sketchup.write_default(LICENSE_PREF, 'license_expiry_date', expiry.to_s)
          Sketchup.write_default(LICENSE_PREF, 'license_type', kind)
          self.alert_ui('License activated. Welcome to Plush!')
          self.send_license_status
        else
          self.alert_ui('That license could not be validated on this machine.')
        end
      rescue => e
        self.alert_ui("Error saving license: #{e.message}")
      end
    end

    def self.offline_fallback(email, key)
      return unless dialog_alive?
      if self.verify_license_key(email, key)
        expiry = key.split('-')[0]
        begin
          Sketchup.write_default(LICENSE_PREF, 'license_email', email)
          Sketchup.write_default(LICENSE_PREF, 'license_key', key)
          Sketchup.write_default(LICENSE_PREF, 'license_machine_id', self.machine_fingerprint)
          Sketchup.write_default(LICENSE_PREF, 'license_activation_date', Time.now.strftime('%Y-%m-%d'))
          Sketchup.write_default(LICENSE_PREF, 'license_expiry_date', "#{expiry[0, 4]}-#{expiry[4, 2]}-#{expiry[6, 2]}")
          Sketchup.write_default(LICENSE_PREF, 'license_type', 'Commercial')
          self.alert_ui('License activated. Welcome to Plush!')
          self.send_license_status
        rescue => e
          self.alert_ui("Error saving license: #{e.message}")
        end
      else
        self.alert_ui('Email or license key is not valid.')
      end
    end

    def self.remove_license
      %w[license_email license_key license_machine_id license_activation_date license_expiry_date license_type].each do |field|
        Sketchup.write_default(LICENSE_PREF, field, '')
      end
      self.alert_ui('License removed from this machine.')
      self.send_license_status
    end

    def self.alert_ui(message)
      return unless dialog_alive?
      @dialog.execute_script("uiAlert(#{message.to_json});")
    end

    def self.send_license_status
      return unless dialog_alive?
      email = Sketchup.read_default(LICENSE_PREF, 'license_email', '')
      email = '-' if email.nil? || email.empty?
      reg = Sketchup.read_default(LICENSE_PREF, 'license_activation_date', '')
      reg = '-' if reg.to_s.empty?
      exp = Sketchup.read_default(LICENSE_PREF, 'license_expiry_date', '')
      exp = '-' if exp.to_s.empty?
      kind = Sketchup.read_default(LICENSE_PREF, 'license_type', '')
      kind = 'Commercial' if kind.to_s.empty?
      payload = {
        'activated' => self.license_valid?,
        'fingerprint' => self.machine_fingerprint,
        'email' => email,
        'reg_date' => reg,
        'exp_date' => exp,
        'kind' => kind
      }
      @dialog.execute_script("updateLicenseStatus(#{JSON.generate(payload)});")
    end

    # ======================================================================
    # Menus + Toolbar
    # ======================================================================
    unless defined?(@menu_registered)
      @menu_registered = true

      TOOLS = [
        ['corners', 'Soften Corners', 'icon_corners.png', 'Soften or round face corners automatically or with a precise radius.'],
        ['pillow', 'Pillow Maker', 'icon_pillow.png', 'Generate a realistic pillow on any face. Click Tool available.'],
        ['mattress', 'Mattress Maker', 'icon_mattress.png', 'Classic, quilted or pillow-top mattresses with tufting.'],
        ['cushion', 'Cushion Maker', 'icon_cushion.png', 'Seat and box cushions with piping.'],
        ['drape', 'Fabric Drape', 'icon_drape.png', 'Dress tabletops and beds with hanging fabric.'],
        ['wall_curve', 'Curved Wall', 'icon_wall.png', 'Sweep bulged, S-curved or wavy walls.'],
        ['ceiling_curve', 'Ceiling Curve', 'icon_ceiling.png', 'Cove, crown and scallop fillets between ceiling and walls.'],
        ['curved_pushpull', 'Curved Push/Pull', 'icon_pushpull.png', 'Extrude curved surfaces - native Push/Pull cannot.'],
        ['cutout', 'Openings', 'icon_opening.png', 'Cut rectangular or circular openings through panels.'],
        ['loft', 'Loft Surface', 'icon_loft.png', 'Loft smooth or ruled surfaces between two loops.'],
        ['pipe', 'Pipe & Tube', 'icon_pipe.png', 'Sweep a solid or hollow tube along any edge path.']
      ]

      menu = UI.menu('Extensions')
      sub_menu = menu.add_submenu('Plush - Soft Form Studio')
      TOOLS.each do |id, label, _icon, _tip|
        sub_menu.add_item(label) { self.show_dialog(id) }
      end
      sub_menu.add_separator
      sub_menu.add_item('Utilities') { self.show_dialog('utilities') }
      sub_menu.add_item('Check for Updates') { self.show_dialog('utilities') }
      sub_menu.add_item('About & License') { self.show_dialog('utilities') }

      toolbar = UI::Toolbar.new('Plush Suite')
      TOOLS.each do |id, label, icon, tip|
        cmd = UI::Command.new(label) { self.show_dialog(id) }
        cmd.tooltip = label
        cmd.status_bar_text = tip
        cmd.menu_text = label
        icon_path = File.join(ICON_DIR, icon)
        large_path = File.join(ICON_DIR, icon.gsub('.png', '@2x.png'))
        if File.exist?(icon_path)
          cmd.small_icon = icon_path
          cmd.large_icon = File.exist?(large_path) ? large_path : icon_path
        end
        toolbar.add_item(cmd)
      end
      toolbar.restore

      # Silently probe the release feed shortly after startup
      UI.start_timer(7.0, false) do
        begin
          Updater.silent_check(@dialog)
        rescue => e
          $stderr.puts "Plush: update probe failed: #{e.message}"
        end
      end
    end
  end
end
