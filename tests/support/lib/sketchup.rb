# Stub shim for `require 'sketchup.rb'` when running the Plush test suite.
# The real double is defined in tests/support/sketchup_stub.rb, which must be
# required BEFORE main.rb (run_all.rb does this).
#
# This shim also supplies the small top-level helpers the real SketchUp
# runtime hands to every extension: file_loaded? / file_loaded.
unless defined?(file_loaded?)

  SU_LOADED_FILES = {}

  # True when the given script has already been processed this session.
  def file_loaded?(path)
    SU_LOADED_FILES.key?(path)
  end

  # Mark a script as processed this session.
  def file_loaded(path)
    SU_LOADED_FILES[path] = true
  end

end
