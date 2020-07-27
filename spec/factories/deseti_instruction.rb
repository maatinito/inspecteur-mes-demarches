# frozen_string_literal: true

FactoryBot.define do
  factory :deseti_instruction, class: Deseti::Instruction do
    motivation_reprise { 'motivation_reprise' }
    motivation_deseti_css { 'motivation_deseti_css' }
    motivation_deseti_refuse { 'motivation_deseti_refuse' }
    motivation_deseti_en_instruction { 'motivation_deseti_en_instruction' }

    initialize_with { Deseti::Instruction.new(attributes) }
  end
end
