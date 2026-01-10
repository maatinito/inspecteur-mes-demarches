# frozen_string_literal: true

module Excel
  class Group < FieldChecker
    def version
      super + 1
    end

    def required_fields
      super + %i[variable colonnes]
    end

    def initialize(params)
      super
      @field_name = @params[:variable]
      @colonnes = @params[:colonnes]
      @colonnes = @colonnes.split(/\s*,\s*/) if @colonnes.is_a?(String)
    end

    def process_row(_row, output)
      raise "La variable #{@field_name} n'est pas disponible" if output[@field_name].blank?
      raise "La variable #{@field_name} n'est pas un tableau (#{output[@field_name]}" unless output[@field_name].is_a?(Array)

      output[@field_name] = merge_lines(group_lines(output[@field_name], @colonnes))
    end

    def group_lines(lines, colonnes)
      lines.each_with_object({}) { |line, h| (h[colonnes.map { line[it].to_s }.reduce(&:+)] ||= []) << line }
    end

    def merge_lines(groups)
      groups.map do |_k, lines|
        result = {}
        lines.each { |line| line.each { |k, v| (result[k] ||= Set.new).add(v) } }
        result.transform_values! { |v| v.size == 1 ? v.first : v.join(', ') }
      end
    end
  end
end
