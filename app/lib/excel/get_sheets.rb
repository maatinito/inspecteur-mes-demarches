# frozen_string_literal: true

module Excel
  class GetSheets < FieldChecker
    def version
      super + 1
    end

    def required_fields
      super + %i[champ]
    end

    def process_row(row, output)
      champs = object_field_values(row, params[:champ])
      champs.each do |champ_source|
        raise "Le champ #{params[:champ]} n'est pas de type PieceJustificative" if champ_source.__typename != 'PieceJustificativeChamp'

        source_file = champ_source.files.filter { File.extname(it.filename) == '.xlsx' }.last
        next unless source_file

        PieceJustificativeCache.get(source_file) do |file|
          xlsx = Roo::Spreadsheet.open(file)
          xlsx.sheets.each do |name|
            sheet = xlsx.sheet(name)
            header_line = header_line(sheet)
            output["#{params[:champ]}.#{name}"] = sheet_rows(header_line, sheet)
          end
        ensure
          xlsx&.close
        end
      end
      output
    end

    def sheet_rows(header_line, sheet)
      rows = []
      headers = sheet.row(header_line)
      sheet.each_row_streaming do |row|
        data_row = row.size >= headers.size && row[1].coordinate[0] > header_line && row[1].value.present?
        rows << headers.map.with_index { |v, i| [v, row[i].value] }.to_h if data_row
      end
      rows
    end

    def header_line(sheet)
      header_line = 0
      max = 0
      sheet.each_row_streaming do |row|
        cell = row.find { |c| c.value.nil? } || row.last
        next if cell.nil?

        count = cell.coordinate[1]
        count -= 1 if cell.value.nil?
        if count > max
          max = count
          header_line = cell.coordinate[0]
        end
      end
      header_line
    end
  end
end
