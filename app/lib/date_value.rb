# frozen_string_literal: true

# Date d'un champ Mes-Démarches : un vrai `Date`, manipulable par les plugins
# (comparaisons, arithmétique, `Date` dans un `case`), mais qui s'affiche au
# format français dès qu'il est interpolé dans un message, un champ de fusion
# .docx ou un `join`.
#
# C'est la transposition aux dates du pattern `BooleanValue` : le type reste
# natif, seul l'affichage est francisé. La sérialisation JSON reste ISO8601
# (ActiveSupport passe par `strftime`, pas par `to_s`), ce qui garantit que les
# mutations GraphQL `ISO8601Date` continuent de partir correctement.
class DateValue < Date
  def to_s
    strftime('%d/%m/%Y')
  end
end
