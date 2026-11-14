# frozen_string_literal: true

require 'rails_helper'

RSpec.describe DossierActions do
  describe '.on_deleted_dossiers' do
    let(:since) { Time.zone.parse('2026-11-01 08:00') }

    def page(numbers, end_cursor: nil, has_next: false)
      connexion = double('connexion',
                         nodes: numbers.map { |n| double('node', number: n) },
                         page_info: double('page_info', end_cursor:, has_next_page: has_next))
      double('response', data: double('data', demarche: double('demarche',
                                                               pending_deleted_dossiers: connexion,
                                                               deleted_dossiers: connexion)))
    end

    it 'rend une seule fois un numéro présent dans les deux flux' do
      allow(MesDemarches).to receive(:query) do |requete, variables:|
        if requete.equal?(MesDemarches::Queries::DossiersEnCorbeille)
          page([12, 13])
        else
          variables[:cursor].nil? ? page([13], end_cursor: 'p2', has_next: true) : page([14])
        end
      end

      expect { |b| described_class.on_deleted_dossiers(3604, since, &b) }.to yield_successive_args(12, 13, 14)
      expect(MesDemarches).to have_received(:query)
        .with(MesDemarches::Queries::DossiersSupprimes,
              variables: { demarche: 3604, since: since.iso8601, cursor: 'p2' })
    end

    it 'lève quand la démarche est introuvable' do
      allow(MesDemarches).to receive(:query)
        .and_return(double('response', data: nil, errors: { 'a' => 'introuvable' }))

      expect { described_class.on_deleted_dossiers(1, since) { nil } }.to raise_error(StandardError, /introuvable/)
    end
  end
end
