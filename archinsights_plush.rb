# =============================================================================
# Plush - Soft Form Studio by ArchInsights
# archinsights_plush.rb - Extension loader
# =============================================================================
# frozen_string_literal: true

require 'sketchup.rb'

module Archinsights
  module Plush
    PRODUCT = 'Plush - Soft Form Studio'
    VERSION = '2.0.0'
    AUTHOR = 'ArchInsights'
    COPYRIGHT = 'Copyright 2026 ArchInsights. All rights reserved.'
  end
end

file = File.join(File.dirname(__FILE__), 'main.rb')

unless file_loaded?(file)
  extension = Sketchup::Extension.new('Plush - Soft Form Studio (ArchInsights)', file)
  extension.description = 'Building Interiors, Explained - a soft form studio for SketchUp: ' \
    'natural pillows, mattresses with real quilting, cushions, fabric drapes, curved walls, ' \
    'ceiling coves, open-through openings, lofts and pipes. Every tool supports metric and imperial units.'
  extension.version = Archinsights::Plush::VERSION
  extension.creator = Archinsights::Plush::AUTHOR
  extension.copyright = Archinsights::Plush::COPYRIGHT
  Sketchup.register_extension(extension)
end
