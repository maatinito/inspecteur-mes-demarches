# frozen_string_literal: true

module Cis
  class ExcelWriter
    def write(input_sheet, file, columns: nil)
      @columns = columns || input_sheet.first&.keys || [] # keys of the first row hash
      new_xlsx
      count = 0
      input_sheet.each do |row|
        write_row(row)
        count += 1
      end

      define_table(count)
      @output_xlsx.serialize(file)
    end

    private

    def define_table(count)
      last_column = ('A'.ord + @columns.size - 1).chr
      last_row = count + 1
      @output_sheet.add_table "A1:#{last_column}#{last_row}", name: 'Personnes1', style_info: { name: 'TableStyleMedium2', show_row_stripes: true }
    end

    def write_row(row)
      @output_sheet.add_row @columns.map { |key| row[key] }, style: @styles
    end

    def new_xlsx
      @output_xlsx = Axlsx::Package.new
      @output_sheet = @output_xlsx.workbook.add_worksheet(name: 'Personnes')
      create_styles
      create_headers
    end

    def create_styles
      s = @output_xlsx.workbook.styles
      s_standard = s.add_style num_fmt: 1
      s_date = s.add_style num_fmt: 14
      # s_date_time = s.add_style num_fmt: 22
      @styles = @columns.map { |column_name| column_name.match?(/date/i) ? s_date : s_standard }
    end

    def create_headers
      header_style = @output_xlsx.workbook.styles.add_style sz: 12, alignment: { horizontal: :center, vertical: :center }
      @output_sheet.add_row(@columns, style: header_style, height: 30)
    end
  end
end
