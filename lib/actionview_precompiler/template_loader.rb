require "actionview_precompiler/cache"

module ActionviewPrecompiler
  class TemplateLoader
    VIRTUAL_PATH_REGEX = %r{\A(?:(?<prefix>.*)\/)?(?<partial>_)?(?<action>[^\/\.]+)}

    attr_reader :compiled_templates

    def initialize
      target = ActionController::Base
      @lookup_context = ActionView::LookupContext.new(target.view_paths)
      @view_context_class = target.view_context_class
      @compiled_templates = {}
    end

    def load_template(virtual_path, locals, compiled_cache: nil)
      templates = find_all_templates(virtual_path, locals)
      templates.each do |template|
        next if compiled_cache && use_cached_source(template, compiled_cache)

        template.send(:compile!, @view_context_class)
        capture_compiled_source(template)
      end
    end

    private

    def find_all_templates(virtual_path, locals)
      match = virtual_path.match(VIRTUAL_PATH_REGEX)
      if match
        action = match[:action]
        prefix = match[:prefix] ? [match[:prefix]] : []
        partial = !!match[:partial]

        # Assume templates with different details take same locals
        details = {}

        @lookup_context.find_all(action, prefix, partial, locals, details)
      else
        []
      end
    end

    def capture_compiled_source(template)
      identifier = template.identifier
      return unless File.exist?(identifier)

      # Re-generate the compiled source by calling the handler directly.
      # This mirrors what ActionView::Template#compile does internally.
      source = template.source
      source = source.to_s if source.respond_to?(:to_s) && !source.is_a?(String)
      code = template.handler.call(template, source)

      method_name = template.send(:method_name)
      locals_code = template.send(:locals_code)

      compiled_source = "def #{method_name}(local_assigns, output_buffer)\n  @virtual_path = #{template.virtual_path.inspect};#{locals_code};#{code}\nend"

      @compiled_templates[identifier] = {
        "source" => compiled_source,
        "method_name" => method_name
      }
    end

    def use_cached_source(template, compiled_cache)
      identifier = template.identifier
      cached = compiled_cache[identifier]
      return false unless cached

      mod = @view_context_class.compiled_method_container

      begin
        mod.module_eval(cached["source"], identifier, 0)
      rescue SyntaxError
        return false
      end

      template.instance_variable_set(:@compiled, true)

      true
    end
  end
end
