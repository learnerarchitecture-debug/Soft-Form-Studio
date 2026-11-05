# =============================================================================
# Plush - Soft Form Studio by ArchInsights
# updater.rb - Automatic update detection, download and install support
# =============================================================================
# frozen_string_literal: true

require 'json'
require 'net/http'
require 'uri'
require 'digest'
require 'openssl'
require 'tmpdir'

module Archinsights
  module Plush
    module Updater
      module_function

      # The release feed is fully configurable by the publisher. It serves a
      # small JSON document describing the newest published build.
      DEFAULT_FEED = 'https://raw.githubusercontent.com/learnerarchitecture-debug/Soft-Form-Studio/main/release.json'
      PREF_FEED = 'com.archinsights.plush.update.feed'
      PREF_AUTO = 'com.archinsights.plush.update.auto'
      PREF_LAST = 'com.archinsights.plush.update.last_check'
      PREF_IGNORED = 'com.archinsights.plush.update.ignored'

      def feed_url
        Sketchup.read_default(PREF_FEED, 'url', DEFAULT_FEED).to_s
      end

      def feed_url=(value)
        Sketchup.write_default(PREF_FEED, 'url', value.to_s)
      end

      def auto_check?
        Sketchup.read_default(PREF_AUTO, 'enabled', true) != false
      end

      def auto_check=(value)
        Sketchup.write_default(PREF_AUTO, 'enabled', value ? true : false)
      end

      def last_check
        Sketchup.read_default(PREF_LAST, 'at', '')
      end

      def ignored_version
        v = Sketchup.read_default(PREF_IGNORED, 'version', '')
        v.to_s.empty? ? nil : v.to_s
      end

      def ignore_version!(version)
        Sketchup.write_default(PREF_IGNORED, 'version', version.to_s)
      end

      def clear_ignored!
        Sketchup.write_default(PREF_IGNORED, 'version', '')
      end

      # ---------------------------------------------------------------
      # Fetch + validate the release manifest
      # Expected JSON:
      # {
      #   "version": "2.0.1",
      #   "download_url": "https://.../Plush-2.0.1.rbz",
      #   "notes": "What changed",
      #   "released_at": "2026-11-05",
      #   "size": 1234567,            (optional)
      #   "sha256": "..."             (optional integrity digest)
      # }
      # ---------------------------------------------------------------
      def fetch_manifest(feed = nil, timeout_seconds = 10)
        url = (feed.nil? || feed.empty?) ? feed_url : feed
        uri = URI.parse(url)
        raise 'Update service address is not configured.' if uri.host.to_s.empty?

        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl = (uri.scheme == 'https')
        http.open_timeout = timeout_seconds
        http.read_timeout = timeout_seconds
        http.verify_mode = OpenSSL::SSL::VERIFY_PEER
        request = Net::HTTP::Get.new(uri.request_uri.empty? ? '/' : uri.request_uri)
        request['Accept'] = 'application/json'
        response = http.request(request)
        raise "Update service returned status #{response.code}." unless response.code.to_i == 200

        manifest = parse_manifest(response.body)
        raise 'Update response is missing version information.' unless manifest[:version]
        raise 'Update response is missing a download link.' unless manifest[:download_url]
        manifest
      end

      def parse_manifest(raw)
        data = JSON.parse(raw.to_s)
        data = data['release'] if data.is_a?(Hash) && data['release'].is_a?(Hash)
        raise 'Update payload is not valid.' unless data.is_a?(Hash)
        {
          :version => data['version'].to_s,
          :download_url => data['download_url'].to_s,
          :notes => data['notes'].to_s,
          :released_at => data['released_at'].to_s,
          :size => data['size'].to_i,
          :sha256 => data['sha256'].to_s
        }
      end

      # ---------------------------------------------------------------
      # Compare + notify
      # ---------------------------------------------------------------
      def pending_update?
        m = fetch_manifest
        newer = CoreGeometry.newer_version?(m[:version], Plush::VERSION)
        ignore = ignored_version
        if newer && (!ignore || ignore != m[:version])
          m
        else
          nil
        end
      end

      def silent_check(dialog)
        return unless auto_check?
        previous = last_check
        today = Time.now.strftime('%Y%m%d%H')
        return if previous.to_s == today

        Sketchup.write_default(PREF_LAST, 'at', today)
        m = fetch_manifest
        if CoreGeometry.newer_version?(m[:version], Plush::VERSION) && ignored_version != m[:version]
          notify_update(dialog, m)
        end
      rescue => e
        # silent mode: never disturb the user for network problems
        $stderr.puts "Plush update check skipped: #{e.message}"
      end

      def check_now(dialog)
        m = fetch_manifest
        Sketchup.write_default(PREF_LAST, 'at', Time.now.strftime('%Y%m%d%H'))
        if CoreGeometry.newer_version?(m[:version], Plush::VERSION)
          notify_update(dialog, m)
          { :ok => true, :update => m }
        else
          { :ok => true, :update => nil, :message => "You are running the latest version (#{Plush::VERSION})." }
        end
      rescue => e
        { :ok => false, :message => e.message }
      end

      def notify_update(dialog, manifest)
        return if dialog.nil? || !dialog.visible?
        dialog.execute_script(
          "showUpdateCard(#{JSON.generate(
            'version' => manifest[:version],
            'notes' => manifest[:notes],
            'released_at' => manifest[:released_at],
            'size' => manifest[:size]
          )});"
        )
      end

      # ---------------------------------------------------------------
      # Download the build package and offer installation
      # ---------------------------------------------------------------
      def download_folder
        candidates = [
          ENV['USERPROFILE'] ? File.join(ENV['USERPROFILE'], 'Downloads') : nil,
          Sketchup.temp_dir,
          Dir.tmpdir
        ].compact
        candidates.find { |d| File.directory?(d) && File.writable?(d) } || Sketchup.temp_dir
      rescue
        Sketchup.temp_dir
      end

      def download_and_prepare(dialog, manifest)
        uri = URI.parse(manifest[:download_url])
        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl = (uri.scheme == 'https')
        http.open_timeout = 15
        http.read_timeout = 300
        http.verify_mode = OpenSSL::SSL::VERIFY_PEER
        request = Net::HTTP::Get.new(uri.request_uri.empty? ? '/' : uri.request_uri)
        response = http.request(request)
        raise "Package download failed (status #{response.code})." unless response.code.to_i == 200

        expected = manifest[:sha256].to_s.strip.downcase
        if !expected.empty?
          digest = Digest::SHA256.hexdigest(response.body)
          raise 'Downloaded package failed the integrity check and was removed.' unless digest == expected
        end

        version_tag = manifest[:version].gsub(/[^0-9A-Za-z.\_]/, '_')
        safe_name = "Plush-#{version_tag}.rbz"
        folder = download_folder
        target = File.join(folder, safe_name)
        File.open(target, 'wb') { |f| f.write(response.body) }

        notify_downloaded(dialog, target, manifest)
        { :ok => true, :path => target }
      rescue => e
        { :ok => false, :message => e.message }
      end

      def notify_downloaded(dialog, path, manifest)
        return if dialog.nil? || !dialog.visible?
        dialog.execute_script("showUpdateDownloaded(#{JSON.generate(
          'path' => path,
          'version' => manifest[:version]
        )});")
      end

      # Opens the package with the operating system's default handler,
      # which is SketchUp's model-space installer on both major platforms.
      def open_installer(path)
        flat = path.gsub('\\', '/')
        UI.openURL("file:///#{flat}")
        true
      rescue => e
        begin
          folder_flat = download_folder.gsub('\\', '/')
          UI.openURL("file:///#{folder_flat}")
          true
        rescue
          $stderr.puts "Plush: could not open installer: #{e.message}"
          false
        end
      end

      # ---------------------------------------------------------------
      # Small environment report used by the About panel
      # ---------------------------------------------------------------
      def environment
        sketchup_version = begin
          Sketchup.version
        rescue
          'unknown'
        end
        {
          :app_version => sketchup_version,
          :ruby_version => RUBY_VERSION,
          :plugin_version => Plush::VERSION,
          :feed_configured => (feed_url != DEFAULT_FEED)
        }
      end
    end
  end
end
