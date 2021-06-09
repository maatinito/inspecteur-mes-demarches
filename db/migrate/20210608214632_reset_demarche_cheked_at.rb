# frozen_string_literal: true

class ResetDemarcheChekedAt < ActiveRecord::Migration[6.1]
  def change
    Demarche.update_all(checked_at: 2.years.ago)
  end
end
