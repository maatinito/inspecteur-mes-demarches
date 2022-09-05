# frozen_string_literal: true

module Payzen
  class Task < FieldChecker
    attr_accessor :order

    def process_order(demarche, dossier, order)
      process(demarche, dossier)
      handle_order(order) if order
    end

    def handle_order(order) end
  end
end
