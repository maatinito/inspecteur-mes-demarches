# frozen_string_literal: true

require 'rails_helper'

RSpec.describe MesDemarches::AvisFetcher do
  describe '.fetch' do
    let(:dossier_number) { 12_345 }

    context 'quand la requête GraphQL réussit avec des avis' do
      let(:graphql_response) do
        double(
          'GraphQLResponse',
          errors: double('Errors', present?: false),
          data: double('Data', dossier: double('Dossier', avis: %i[avis1 avis2]))
        )
      end

      before do
        allow(MesDemarches).to receive(:query).and_return(graphql_response)
      end

      it 'retourne la liste des avis' do
        expect(described_class.fetch(dossier_number)).to eq(%i[avis1 avis2])
      end
    end

    context 'quand le dossier n\'a pas d\'avis' do
      let(:graphql_response) do
        double(
          'GraphQLResponse',
          errors: double('Errors', present?: false),
          data: double('Data', dossier: double('Dossier', avis: nil))
        )
      end

      before do
        allow(MesDemarches).to receive(:query).and_return(graphql_response)
      end

      it 'retourne un tableau vide' do
        expect(described_class.fetch(dossier_number)).to eq([])
      end
    end

    context 'quand la requête GraphQL échoue' do
      let(:graphql_response) do
        double(
          'GraphQLResponse',
          errors: [double('Error', message: 'Erreur réseau')],
          data: nil
        )
      end

      before do
        allow(MesDemarches).to receive(:query).and_return(graphql_response)
        allow(Rails.logger).to receive(:error)
      end

      it 'log l\'erreur et retourne un tableau vide' do
        result = described_class.fetch(dossier_number)
        expect(result).to eq([])
        expect(Rails.logger).to have_received(:error).with(/AvisFetcher.*12345/)
      end
    end

    context 'quand le dossier est introuvable' do
      let(:graphql_response) do
        double(
          'GraphQLResponse',
          errors: double('Errors', present?: false),
          data: double('Data', dossier: nil)
        )
      end

      before do
        allow(MesDemarches).to receive(:query).and_return(graphql_response)
      end

      it 'retourne un tableau vide' do
        expect(described_class.fetch(12_345)).to eq([])
      end
    end
  end
end
