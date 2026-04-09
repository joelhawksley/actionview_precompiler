require "test_helper"
require "tmpdir"
require "json"

module ActionviewPrecompiler
  class CacheTest < Minitest::Test
    def setup
      @cache_dir = Dir.mktmpdir("precompiler_cache_test")
      @cache_path = File.join(@cache_dir, "precompiler_cache.json")
    end

    def teardown
      FileUtils.rm_rf(@cache_dir)
    end

    # --- Cache class unit tests ---

    def test_cache_write_and_read
      cache = Cache.new(@cache_path)

      cache.write(
        template_renders: [["users/_user", ["user"]]],
        compiled_templates: {},
        source_checksums: {}
      )

      assert File.exist?(@cache_path)
      data = cache.read
      assert_equal [["users/_user", ["user"]]], data["template_renders"]
    end

    def test_cache_read_returns_nil_when_no_file
      cache = Cache.new(@cache_path)
      assert_nil cache.read
    end

    def test_cache_read_returns_nil_on_version_mismatch
      cache = Cache.new(@cache_path)

      File.write(@cache_path, JSON.generate({
        "version" => 999,
        "ruby_version" => RUBY_VERSION,
        "template_renders" => [],
        "compiled_templates" => {},
        "source_checksums" => {}
      }))

      assert_nil cache.read
    end

    def test_cache_read_returns_nil_on_ruby_version_mismatch
      cache = Cache.new(@cache_path)

      File.write(@cache_path, JSON.generate({
        "version" => Cache::CACHE_VERSION,
        "ruby_version" => "0.0.0",
        "template_renders" => [],
        "compiled_templates" => {},
        "source_checksums" => {}
      }))

      assert_nil cache.read
    end

    def test_cache_read_returns_nil_on_corrupt_json
      cache = Cache.new(@cache_path)

      File.write(@cache_path, "not valid json{{{")

      assert_nil cache.read
    end

    def test_cache_invalidated_when_source_file_changes
      src_file = File.join(@cache_dir, "test_template.html.erb")
      File.write(src_file, "<%= 'hello' %>")
      original_mtime = Cache.file_mtime(src_file)

      cache = Cache.new(@cache_path)
      cache.write(
        template_renders: [["test/template", []]],
        compiled_templates: {},
        source_checksums: { src_file => original_mtime }
      )

      # Cache should be valid
      assert cache.read

      # Modify the source file (sleep to ensure mtime changes)
      sleep 0.05
      File.write(src_file, "<%= 'goodbye' %>")

      # Cache should now be invalid
      assert_nil cache.read
    end

    def test_cache_invalidated_when_source_file_deleted
      src_file = File.join(@cache_dir, "deleted_template.html.erb")
      File.write(src_file, "<%= 'hello' %>")

      cache = Cache.new(@cache_path)
      cache.write(
        template_renders: [],
        compiled_templates: {},
        source_checksums: { src_file => Cache.file_mtime(src_file) }
      )

      File.delete(src_file)

      assert_nil cache.read
    end

    # --- Integration with Precompiler ---

    def test_precompiler_writes_cache
      reset_action_view!

      precompiler = Precompiler.new(cache_path: @cache_path)
      precompiler.scan_view_dir FIXTURES_VIEW_DIR

      precompiler.run

      assert File.exist?(@cache_path)

      data = JSON.parse(File.read(@cache_path))
      assert_equal Cache::CACHE_VERSION, data["version"]
      assert_equal RUBY_VERSION, data["ruby_version"]
      assert_includes data["template_renders"], ["users/_user", ["user"]]
      refute_empty data["source_checksums"]
    end

    def test_precompiler_loads_from_cache
      reset_action_view!

      # First run: write cache
      precompiler1 = Precompiler.new(cache_path: @cache_path)
      precompiler1.scan_view_dir FIXTURES_VIEW_DIR
      precompiler1.run

      assert File.exist?(@cache_path)

      # Second run: load from cache
      reset_action_view!

      precompiler2 = Precompiler.new(cache_path: @cache_path)
      precompiler2.scan_view_dir FIXTURES_VIEW_DIR
      precompiler2.run

      # The cached run should still result in templates being available
      assert File.exist?(@cache_path)
    end

    def test_precompiler_falls_back_on_stale_cache
      reset_action_view!

      # Write a cache with wrong version
      File.write(@cache_path, JSON.generate({
        "version" => 999,
        "ruby_version" => RUBY_VERSION,
        "template_renders" => [],
        "compiled_templates" => {},
        "source_checksums" => {}
      }))

      precompiler = Precompiler.new(cache_path: @cache_path)
      precompiler.scan_view_dir FIXTURES_VIEW_DIR

      compiled_templates = []
      callback = ->(name, start, finish, id, payload) do
        compiled_templates << payload[:virtual_path]
      end
      ActiveSupport::Notifications.subscribed(callback, "!compile_template.action_view") do
        precompiler.run
      end

      # Should have fallen back to fresh compilation
      assert_includes compiled_templates, "users/_user"

      # And should have rewritten the cache
      data = JSON.parse(File.read(@cache_path))
      assert_equal Cache::CACHE_VERSION, data["version"]
    end

    def test_precompiler_without_cache_path_works_normally
      reset_action_view!

      precompiler = Precompiler.new
      precompiler.scan_view_dir FIXTURES_VIEW_DIR

      compiled_templates = []
      callback = ->(name, start, finish, id, payload) do
        compiled_templates << payload[:virtual_path]
      end
      ActiveSupport::Notifications.subscribed(callback, "!compile_template.action_view") do
        precompiler.run
      end

      assert_includes compiled_templates, "users/_user"
      refute File.exist?(@cache_path)
    end

    def test_source_checksums_collected_from_scanners
      scanner = TemplateScanner.new(FIXTURES_VIEW_DIR)
      checksums = scanner.source_checksums

      refute_empty checksums
      checksums.each do |path, mtime|
        assert File.exist?(path), "#{path} should exist"
        assert_kind_of Float, mtime
        assert_equal File.mtime(path).to_f, mtime
      end
    end

    def test_controller_scanner_source_checksums
      scanner = ControllerScanner.new(FIXTURES_CONTROLLER_DIR)
      checksums = scanner.source_checksums

      refute_empty checksums
      checksums.each do |path, mtime|
        assert File.exist?(path)
        assert_kind_of Float, mtime
      end
    end

    def test_helper_scanner_source_checksums
      scanner = HelperScanner.new(FIXTURES_HELPER_DIR)
      checksums = scanner.source_checksums

      refute_empty checksums
      checksums.each do |path, mtime|
        assert File.exist?(path)
        assert_kind_of Float, mtime
      end
    end
  end
end
