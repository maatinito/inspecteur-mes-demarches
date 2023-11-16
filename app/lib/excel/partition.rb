# frozen_string_literal: true

module Excel
  class Partition < FieldChecker
    def version
      super + 1
    end

    def required_fields
      super + %i[variable colonne]
    end

    def initialize(params)
      super
      @field_name = @params[:variable]
      @column_name = @params[:colonne]
    end

    def process_row(_row, output)
      raise "La variable #{@field_name} n'est pas disponible" if output[@field_name].blank?
      raise "La variable #{@field_name} n'est pas un tableau (#{output[@field_name]}" unless output[@field_name].is_a?(Array)

      set_fields(output, partition(output[@field_name], @column_name))
    end

    def set_fields(output, partition)
      partition.each { |k, v| output["#{@field_name}.#{k}"] = v }
      output
    end

    # return hash key ==> lines for each value of given column_name
    def partition(lines, column_name)
      lines.each_with_object({}) { |line, h| (h[line[column_name]] ||= []) << line }
    end
  end
end
