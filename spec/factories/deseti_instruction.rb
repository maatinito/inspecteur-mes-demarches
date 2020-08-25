# frozen_string_literal: true

FactoryBot.define do
  factory :deseti_instruction, class: Deseti::Instruction do
    motivation_reprise { 'motivation_reprise' }
    motivation_deseti_refuse { 'motivation_deseti_refuse' }
    motivation_deseti_sans_suite { 'motivation_deseti_sans_suite' }
    motivation_deseti_en_instruction { 'motivation_deseti_en_instruction' }
    motivation_deseti_en_construction { 'motivation_deseti_en_construction' }

    initialize_with { Deseti::Instruction.new(attributes) }
  end
end
