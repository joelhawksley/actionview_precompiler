require "json"
require "fileutils"

module ActionviewPrecompiler
  class Cache
    CACHE_VERSION = 2

    attr_reader :cache_path

    def initialize(cache_path, verbose: false)
      @cache_path = cache_path
      @verbose = verbose
    end

    def write(template_renders:, compiled_templates:, source_checksums:)
      data = {
        "version" => CACHE_VERSION,
        "ruby_version" => RUBY_VERSION,
        "template_renders" => template_renders,
        "compiled_templates" => compiled_templates,
        "source_checksums" => source_checksums
      }
      FileUtils.mkdir_p(File.dirname(@cache_path))
      File.write(@cache_path, JSON.generate(data))
    end

    def read
      return nil unless File.exist?(@cache_path)
      data = JSON.parse(File.read(@cache_path))
      return nil unless valid?(data)
      data
    rescue JSON::ParserError
      nil
    end

    def self.file_mtime(path)
      File.mtime(path).to_f
    end

    private

    def valid?(data)
      unless data["version"] == CACHE_VERSION
        debug "Cache invalid: version mismatch (got #{data["version"]}, expected #{CACHE_VERSION})"
        return false
      end

      unless data["ruby_version"] == RUBY_VERSION
        debug "Cache invalid: ruby_version mismatch (got #{data["ruby_version"]}, expected #{RUBY_VERSION})"
        return false
      end

      unless checksums_match?(data["source_checksums"])
        debug "Cache invalid: source checksums mismatch"
        return false
      end

      debug "Cache valid"

      true
    end

    def checksums_match?(checksums)
      return true if checksums.nil? || checksums.empty?

      checksums.all? do |path, expected_mtime|
        File.exist?(path) && Cache.file_mtime(path) == expected_mtime
      end
    end

    def debug(msg)
      puts msg if @verbose
    end
  end
end
