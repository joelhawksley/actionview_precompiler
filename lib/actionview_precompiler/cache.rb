require "json"
require "fileutils"

module ActionviewPrecompiler
  class Cache
    CACHE_VERSION = 1

    attr_reader :cache_path

    def initialize(cache_path)
      @cache_path = cache_path
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
      data["version"] == CACHE_VERSION &&
        data["ruby_version"] == RUBY_VERSION &&
        checksums_match?(data["source_checksums"])
    end

    def checksums_match?(checksums)
      return true if checksums.nil? || checksums.empty?

      checksums.all? do |path, expected_mtime|
        File.exist?(path) && Cache.file_mtime(path) == expected_mtime
      end
    end
  end
end
