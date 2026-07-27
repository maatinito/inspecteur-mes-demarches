# frozen_string_literal: true

# Pendant de `DateValue` pour les champs date-heure.
#
# Hérite de `DateTime` et **pas** de `Time` : `Time#to_a` existe, donc un splat
# (`[*value]`, utilisé par `Publipostage#generate_docx`) exploserait la valeur en
# dix éléments. `DateTime` est une sous-classe de `Date` et n'a pas de `to_a`.
class DatetimeValue < DateTime
  def to_s
    strftime('%d/%m/%Y à %Hh%M')
  end
end
