module ActionviewPrecompiler
  class TemplateLoader
    VIRTUAL_PATH_REGEX = %r{\A(?:(?<prefix>.*)\/)?(?<partial>_)?(?<action>[^\/\.]+)}

    def initialize
      target = ActionController::Base
      @lookup_context = ActionView::LookupContext.new(target.view_paths)
      @view_context_class = target.view_context_class
    end

    # eager_load_templates isn't idempotent, so only call it once per process
    def eager_load_resolvers!
      @@eager_loaded_resolvers ||= begin
        @lookup_context.view_paths.each do |resolver|
          resolver.eager_load_templates if resolver.respond_to?(:eager_load_templates)
        end
        true
      end
    end

    def load_template(virtual_path, locals)
      templates = find_all_templates(virtual_path, locals)
      templates.each do |template|
        template.send(:compile!, @view_context_class)
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
  end
end
