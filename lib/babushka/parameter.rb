module Babushka
  class Parameter
    attr_reader :name

    def initialize(name, value = nil)
      @name = name
      @value = value
    end

    def default value
      tap { @default = value }
    end
    def ask value
      tap { @ask = value }
    end
    def choose value
      tap { @choose value }
    end

    def set?
      !!@value
    end

    def to_s
      value.to_s
    end

    def to_str
      if !value.respond_to?(:to_str)
        raise DepArgumentError, "Can't coerce #{value}:#{value.class.name} into a String"
      else
        value.to_str
      end
    end

    def inspect
      "#<Babushka::Parameter:#{object_id} #{name}: #{@value || '[unset]'}>"
    end

  private

    def value
      @value ||= Prompt.get_value((@ask || name).to_s, prompt_opts)
    end

    def prompt_opts
      {}.tap {|hsh|
        hsh[:default] = @default unless @default.nil?
        hsh[:choices] = @choose if @choose.is_a?(Array)
        hsh[:choice_descriptions] = @choose if @choose.is_a?(Hash)
      }
    end
  end
end
