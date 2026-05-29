# frozen_string_literal: true

require 'rails_helper'

RSpec.describe SchemaBuilders::Target do
  let(:dummy_class) { Class.new { include SchemaBuilders::Target } }
  let(:instance) { dummy_class.new }

  it 'définit la méthode list_workspaces' do
    expect(instance).to respond_to(:list_workspaces)
    expect { instance.list_workspaces }.to raise_error(NotImplementedError)
  end

  it 'définit la méthode list_applications(workspace_id)' do
    expect(instance).to respond_to(:list_applications)
    expect { instance.list_applications(1) }.to raise_error(NotImplementedError)
  end

  it 'définit la méthode list_tables(application_id)' do
    expect(instance).to respond_to(:list_tables)
    expect { instance.list_tables(1) }.to raise_error(NotImplementedError)
  end

  it 'définit la méthode create_table(application_id, name, fields)' do
    expect(instance).to respond_to(:create_table)
    expect { instance.create_table(1, 'T', []) }.to raise_error(NotImplementedError)
  end

  it 'définit la méthode update_fields(table_id, fields)' do
    expect(instance).to respond_to(:update_fields)
    expect { instance.update_fields(1, []) }.to raise_error(NotImplementedError)
  end

  it 'définit la méthode table_exists?(application_id, name)' do
    expect(instance).to respond_to(:table_exists?)
    expect { instance.table_exists?(1, 'T') }.to raise_error(NotImplementedError)
  end

  it 'définit la méthode field_exists?(table_id, name)' do
    expect(instance).to respond_to(:field_exists?)
    expect { instance.field_exists?(1, 'F') }.to raise_error(NotImplementedError)
  end
end
