# frozen_string_literal: true

module Cis
  class ExcelWriter
    attr_writer :title, :variables, :hidden_columns, :unlocked_columns, :password

    def write(input_sheet, file, columns: nil)
      @columns = columns || input_sheet.first&.keys || [] # keys of the first row hash
      new_xlsx
      write_title
      write_variables
      write_table(input_sheet, @unlocked_columns)
      hide_columns
      @output_xlsx.serialize(file)
    end

    private

    def hide_columns
      return if @hidden_columns.blank?

      @hidden_columns.each do |name|
        index = @columns.index(name)
        @output_sheet.column_info[index].hidden = true if index.present?
      end
    end

    def write_title
      return if @title.nil?

      title_style = @output_xlsx.workbook.styles.add_style sz: 16, alignment: { horizontal: :center, vertical: :center }
      row = @output_sheet.add_row [@title], style: [title_style], widths: [:ignore]

      index = row.row_index + 1
      @output_sheet.merge_cells("A#{index}:#{last_column_letter}#{index}")
    end

    def write_variables
      return if @variables.blank?

      @output_sheet.add_row []
      s = @output_xlsx.workbook.styles
      s_variable = s.add_style num_fmt: 1, sz: 12
      s_standard = s.add_style num_fmt: 1, sz: 12, b: true
      s_date = s.add_style format_code: 'mmmm yyy', sz: 12, b: true
      @variables.each do |variable, value|
        styles = [s_standard, s_variable, (value.is_a?(Date) ? s_date : s_standard)]
        values = ['', variable, value]
        @output_sheet.add_row values, style: styles
      end
      @output_sheet.add_row []
    end

    def write_table(input_sheet, unlocked_columns)
      create_styles(unlocked_columns)
      beg_row = create_headers
      end_row = beg_row
      input_sheet.each do |row|
        write_row(row)
        end_row += 1
      end

      define_table(beg_row, end_row)
    end

    def define_table(beg_row, end_row)
      @output_sheet.add_table "A#{beg_row}:#{last_column_letter}#{end_row}", name: 'Personnes1', style_info: { name: 'TableStyleMedium2', show_row_stripes: true }
    end

    def last_column_letter
      ('A'.ord + @columns.size - 1).chr
    end

    def write_row(row)
      @output_sheet.add_row @columns.map { |key| row[key] }, style: @styles
    end

    def new_xlsx
      @output_xlsx = Axlsx::Package.new
      @output_sheet = @output_xlsx.workbook.add_worksheet(name: 'Personnes')
      @output_sheet.sheet_protection { |protection| protection.password = @password } if @password.present?
    end

    def create_styles(unlock_columns)
      s = @output_xlsx.workbook.styles
      s_standard = create_styles_fmt(s, 1)
      s_date = create_styles_fmt(s, 14)
      # s_date_time = s.add_style num_fmt: 22
      @styles = @columns.map do |column_name|
        locked = !unlock_columns&.include?(column_name)
        column_name.match?(/date/i) ? s_date[locked] : s_standard[locked]
      end
    end

    def create_styles_fmt(styles, fmt)
      {
        true => (styles.add_style num_fmt: fmt, locked: true),
        false => (styles.add_style num_fmt: fmt, locked: false)
      }
    end

    def create_headers
      header_style = @output_xlsx.workbook.styles.add_style sz: 12, alignment: { horizontal: :center, vertical: :center }
      row = @output_sheet.add_row(@columns, style: header_style, height: 30)
      row.row_index + 1
    end
  end
end
