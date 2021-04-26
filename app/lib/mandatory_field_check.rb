class MandatoryFieldCheck < FieldChecker
  def required_fields
    super + %i[champs message]
  end

  def version
    super + 2
  end

  def check(dossier)
    mandotory_fields = @params[:champs]
    if mandotory_fields
      mandotory_fields.each do |field_name|
        puts field_name
        fields = field_values(field_name)
        empty = fields.empty? || fields.any? do |field|
          case field.__typename
          when 'PieceJustificativeChamp'
            field.file
          when 'DossierLinkChamp'
            field.string_value
          when 'RepetitionChamp'
            field.champs
          else
            field.value
          end.blank?
        end
        if empty
          add_message(field_name, "vide", @params[:message])
        end
      end
    end
  end
end